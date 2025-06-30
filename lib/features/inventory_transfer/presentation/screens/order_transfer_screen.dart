// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Intent;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() => _OrderTransferScreenState();
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
  late final InventoryTransferRepository _repo;
  late final BarcodeIntentService _barcodeService;
  final _scrollController = ScrollController();

  StreamSubscription<String>? _intentSub;

  bool _isLoading = true, _isSaving = false;
  List<TransferableContainer> _containers = [];
  List<GlobalKey> _cardKeys = [];
  List<MapEntry<String, int>> _availableLocations = [];
  int _focusedIndex = 0;
  final Map<String, MapEntry<String, int>> _targets = {};
  final Map<String, Map<int, TextEditingController>> _quantityControllers = {};
  final Map<String, bool> _isPalletOpeningMap = {};

  static String get sourceLocationName => 'common_labels.goods_receiving_area'.tr();
  static const int sourceLocationId = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _repo = context.read<InventoryTransferRepository>();
      await _loadContainers();
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _intentSub?.cancel();
    _quantityControllers.forEach((_, controllers) {
      controllers.forEach((_, ctrl) => ctrl.dispose());
    });
    super.dispose();
  }

  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _barcodeService = BarcodeIntentService();
    final first = await _barcodeService.getInitialBarcode();
    if (first != null) {
      Future.delayed(const Duration(milliseconds: 200), () => _handleBarcode(first));
    }
    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _snack('order_transfer.barcode_stream_error'.tr(namedArgs: {'error': e.toString()}), err: true));
  }

  void _handleBarcode(String code) {
    if (_containers.isEmpty || !mounted) return;
    _processScannedLocation(_containers[_focusedIndex], code);
  }

  Future<void> _loadContainers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final containers = await _repo.getTransferableContainers(sourceLocationId, orderId: widget.order.id);
      final locations = await _repo.getTargetLocations();

      if (mounted) {
        if (containers.isEmpty) {
          _snack('order_transfer.all_items_transferred'.tr());
          Navigator.of(context).pop(true);
          return;
        }

        setState(() {
          _containers = containers;
          _cardKeys = List.generate(containers.length, (_) => GlobalKey());
          _availableLocations = locations.entries.toList();
          _isLoading = false;
          _targets.clear();
          _quantityControllers.clear();
          _isPalletOpeningMap.clear();

          for (var container in containers) {
            final controllers = <int, TextEditingController>{};
            for (var item in container.items) {
              final qty = item.quantity;
              final initialQtyText = qty == qty.truncate() ? qty.toInt().toString() : qty.toString();
              controllers[item.product.id] = TextEditingController(text: initialQtyText);
            }
            _quantityControllers[container.id] = controllers;
            if (!container.id.startsWith('PALETSIZ_')) {
              _isPalletOpeningMap[container.id] = false;
            }
          }
        });
        _scrollLater();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('order_transfer.data_load_error'.tr(namedArgs: {'error': e.toString()}), err: true);
      }
    }
  }

  void _processScannedLocation(TransferableContainer container, String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;
    try {
      final match = await _repo.findLocationByCode(clean);
      if (!mounted) return;
      if (match != null && match.value != sourceLocationId) {
        _assignTarget(container, match);
      } else {
        final reason = match == null ? 'order_transfer.invalid_location'.tr() : 'order_transfer.same_as_source_location'.tr();
        _snack(reason, err: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('order_transfer.location_search_error'.tr(namedArgs: {'error': e.toString()}), err: true);
    }
  }

  void _assignTarget(TransferableContainer c, MapEntry<String, int> loc) {
    setState(() => _targets[c.id] = loc);
    _snack('${c.displayName} → ${loc.key}');
    _focusNext();
  }

  void _focusNext() {
    final next = _containers.indexWhere(
            (c) => !_targets.containsKey(c.id), _focusedIndex + 1);
    setState(() {
      _focusedIndex = next != -1 ? next : _containers.indexWhere((c) => !_targets.containsKey(c.id));
    });
    _scrollLater();
  }

  void _scrollLater() => Future.delayed(
      const Duration(milliseconds: 100), () => _scrollTo(_focusedIndex));

  void _scrollTo(int index) {
    if (index < 0 || index >= _cardKeys.length) return;
    final context = _cardKeys[index].currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, alignment: 0.05);
    }
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _save() async {
    if (_targets.isEmpty) {
      _snack('order_transfer.cart_empty'.tr(), err: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = (await SharedPreferences.getInstance()).getInt('user_id');
      if (uid == null) throw 'order_transfer.user_not_found'.tr();

      for (final containerId in _targets.keys) {
        final container = _containers.firstWhere((c) => c.id == containerId);
        final targetLocation = _targets[containerId]!;
        final List<TransferItemDetail> detailsForOperation = [];
        final itemControllers = _quantityControllers[container.id]!;

        // DOĞRU MANTIK: Operasyon tipini belirlemek için doğrudan switch'in durumu kontrol ediliyor.
        final bool isPalletOpening = _isPalletOpeningMap[container.id] ?? false;

        for (var item in container.items) {
          final qtyText = itemControllers[item.product.id]?.text ?? '0';
          final qty = double.tryParse(qtyText) ?? 0.0;
          if (qty > 0) {
            detailsForOperation.add(TransferItemDetail(
              productId: item.product.id,
              productName: item.product.name,
              productCode: item.product.stockCode,
              quantity: qty,
              palletId: item.sourcePalletBarcode,
              targetLocationId: targetLocation.value,
              targetLocationName: targetLocation.key,
            ));
          }
        }

        if (detailsForOperation.isEmpty) continue;

        // DOĞRU MANTIK: Operasyon tipi artık miktar karşılaştırmasına göre değil,
        // doğrudan kullanıcının "Paleti Aç" seçimine göre belirleniyor.
        final operationType = container.id.startsWith('PALETSIZ_')
            ? AssignmentMode.box
            : (isPalletOpening ? AssignmentMode.boxFromPallet : AssignmentMode.pallet);

        final header = TransferOperationHeader(
          employeeId: uid,
          transferDate: DateTime.now(),
          operationType: operationType,
          sourceLocationName: sourceLocationName,
          targetLocationName: targetLocation.key,
          containerId: container.id,
          siparisId: widget.order.id,
        );

        await _repo.recordTransferOperation(header, detailsForOperation, sourceLocationId, targetLocation.value);
      }

      if (!mounted) return;

      _snack('order_transfer.saved'.tr());
      context.read<SyncService>().performFullSync(force: true);
      Navigator.of(context).pop(true);

    } catch (e) {
      if (!mounted) return;
      _snack('order_transfer.save_error'.tr(namedArgs: {'error': e.toString()}), err: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _targets.isNotEmpty && !_isSaving;
    return Scaffold(
      appBar: SharedAppBar(title: 'order_transfer.title'.tr(), showBackButton: true),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: canSave ? _save : null,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: Text('order_transfer.save_button'.tr(namedArgs: {'count': _targets.length.toString()})),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_containers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'order_transfer.no_items_to_transfer'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            OrderInfoCard(order: widget.order),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadContainers,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 80, top: 8),
                  itemCount: _containers.length,
                  itemBuilder: (_, i) {
                    final c = _containers[i];
                    return _ContainerCard(
                      key: _cardKeys[i],
                      container: c,
                      focused: i == _focusedIndex,
                      target: _targets[c.id],
                      availableLocations: _availableLocations,
                      onTarget: (loc) => _assignTarget(c, loc),
                      onClear: () => setState(() => _targets.remove(c.id)),
                      onTap: () {
                        if (_focusedIndex != i) {
                          setState(() => _focusedIndex = i);
                          _scrollTo(i);
                        }
                      },
                      onScan: (text) => _processScannedLocation(c, text),
                      quantityControllers: _quantityControllers[c.id] ?? {},
                      isPalletOpening: _isPalletOpeningMap[c.id] ?? false,
                      onPalletOpeningChanged: (value) {
                        setState(() {
                          _isPalletOpeningMap[c.id] = value;
                          if (!value) {
                            final container = _containers.firstWhere((cont) => cont.id == c.id);
                            final itemControllers = _quantityControllers[container.id]!;
                            for (var item in container.items) {
                              final initialQty = item.quantity;
                              final initialQtyText = initialQty == initialQty.truncate()
                                  ? initialQty.toInt().toString()
                                  : initialQty.toString();
                              itemControllers[item.product.id]?.text = initialQtyText;
                            }
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContainerCard extends StatefulWidget {
  final TransferableContainer container;
  final bool focused;
  final MapEntry<String, int>? target;
  final List<MapEntry<String, int>> availableLocations;
  final ValueChanged<MapEntry<String, int>> onTarget;
  final VoidCallback onClear;
  final VoidCallback onTap;
  final void Function(String) onScan;
  final Map<int, TextEditingController> quantityControllers;
  final bool isPalletOpening;
  final ValueChanged<bool> onPalletOpeningChanged;

  const _ContainerCard({
    super.key,
    required this.container,
    required this.focused,
    required this.target,
    required this.availableLocations,
    required this.onTarget,
    required this.onClear,
    required this.onTap,
    required this.onScan,
    required this.quantityControllers,
    required this.isPalletOpening,
    required this.onPalletOpeningChanged,
  });

  @override
  State<_ContainerCard> createState() => _ContainerCardState();
}

class _ContainerCardState extends State<_ContainerCard> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _updateControllerAndFocus();
  }

  @override
  void didUpdateWidget(covariant _ContainerCard old) {
    super.didUpdateWidget(old);
    if (widget.target?.key != old.target?.key || (widget.focused && !old.focused)) {
      _updateControllerAndFocus();
    }
  }

  void _updateControllerAndFocus() {
    if (widget.target != null) _ctrl.text = widget.target!.key;
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        if (_ctrl.text.isNotEmpty) {
          _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _showLocationSearch() async {
    final searchResult = await Navigator.push<MapEntry<String, int>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _LocationSearchPage(
          title: 'order_transfer.dialog_select_target'.tr(),
          items: widget.availableLocations,
        ),
      ),
    );
    if (searchResult != null) widget.onTarget(searchResult);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assigned = widget.target != null;
    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: widget.focused ? 4 : 2,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: widget.focused ? theme.colorScheme.primary : (assigned ? Colors.green : Colors.transparent),
              width: widget.focused ? 2.5 : 1.5),
        ),
        child: Column(
          children: [
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey(widget.container.id),
                initiallyExpanded: widget.focused,
                onExpansionChanged: (expanding) { if (expanding) widget.onTap(); },
                title: Text(widget.container.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: assigned ? Icon(Icons.check_circle, color: Colors.green.shade700) : const Icon(Icons.pending_outlined),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (!widget.container.id.startsWith("PALETSIZ_"))
                    SwitchListTile(
                      title: Text('inventory_transfer.label_break_pallet'.tr()),
                      value: widget.isPalletOpening,
                      onChanged: widget.onPalletOpeningChanged,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ...widget.container.items.map((i) {
                    final qtyController = widget.quantityControllers[i.product.id]!;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 3, child: Text(i.product.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: qtyController,
                              enabled: widget.container.id.startsWith("PALETSIZ_") || widget.isPalletOpening,
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(labelText: 'common_labels.quantity'.tr(), isDense: true, border: const OutlineInputBorder()),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'validators.required'.tr();
                                final qty = double.tryParse(v);
                                if (qty == null) return 'validators.invalid'.tr();
                                if (qty > i.quantity + 0.001) return 'validators.max_qty'.tr();
                                if (qty < 0) return 'validators.negative'.tr();
                                return null;
                              },
                            ),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: assigned ? _rowAssigned(theme) : _rowInput(theme)),
          ],
        ),
      ),
    );
  }

  Widget _rowAssigned(ThemeData theme) => Row(
    children: [
      Icon(Icons.location_on, color: Colors.green.shade700),
      const SizedBox(width: 8),
      Expanded(child: Text(widget.target!.key, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
      IconButton(icon: Icon(Icons.close, color: theme.colorScheme.error), onPressed: widget.onClear),
    ],
  );

  Widget _rowInput(ThemeData theme) => SizedBox(
    height: 56,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: _ctrl,
            focusNode: _focus,
            decoration: InputDecoration(
              labelText: 'order_transfer.label_target_shelf'.tr(),
              hintText: 'order_transfer.hint_scan_or_select'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_drop_down_circle_outlined), onPressed: _showLocationSearch),
            ),
            onFieldSubmitted: (v) => v.isNotEmpty ? widget.onScan(v) : null,
            onTap: () {
              _focus.requestFocus();
              _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
            },
          ),
        ),
        const SizedBox(width: 8),
        _QrButton(onTap: () async {
          final res = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
          if (res != null && res.isNotEmpty) widget.onScan(res);
        }),
      ],
    ),
  );
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QrButton({required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    width: 56,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)), padding: EdgeInsets.zero),
      child: LayoutBuilder(builder: (context, constraints) => Icon(Icons.qr_code_scanner, size: constraints.maxHeight * 0.6)),
    ),
  );
}

class _LocationSearchPage extends StatefulWidget {
  final String title;
  final List<MapEntry<String, int>> items;
  const _LocationSearchPage({required this.title, required this.items});
  @override
  State<_LocationSearchPage> createState() => _LocationSearchPageState();
}

class _LocationSearchPageState extends State<_LocationSearchPage> {
  late List<MapEntry<String, int>> _filteredItems;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchCtrl.addListener(() => _filterItems(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() => _filteredItems = widget.items.where((item) => item.key.toLowerCase().contains(lowerQuery)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'inventory_transfer.dialog_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchCtrl.clear()) : null,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(child: Text('inventory_transfer.dialog_search_no_results'.tr()))
                  : ListView.separated(
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _filteredItems.length,
                itemBuilder: (_, index) {
                  final item = _filteredItems[index];
                  return ListTile(title: Text(item.key), onTap: () => Navigator.of(context).pop(item));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

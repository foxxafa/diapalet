// ----- lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart (GÜNCELLENDİ) -----
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
import 'package:diapalet/core/network/network_info.dart';

/// *************************
/// Ekran State
/// *************************
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

  // sabitler
  static String get sourceLocationName => 'common_labels.goods_receiving_area'.tr();
  static const sourceLocationId = 1;

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

  /* ------------------  Barkod ------------------ */
  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;

    _barcodeService = BarcodeIntentService();

    final first = await _barcodeService.getInitialBarcode();
    if (first != null) {
      // Handle initial barcode with a slight delay to avoid race conditions on startup
      Future.delayed(const Duration(milliseconds: 200), () => _handleBarcode(first));
    }

    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _snack('order_transfer.barcode_stream_error'.tr(namedArgs: {'error': e.toString()}), err: true));
  }

  void _handleBarcode(String code) {
    if (_containers.isEmpty) {
      _snack('order_transfer.barcode_received_but_container_list_empty'.tr(), err: true);
      return;
    }
    if (!mounted) return;
    _processScannedLocation(_containers[_focusedIndex], code);
  }

  /* ------------------  Veri ------------------ */
  Future<void> _loadContainers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final warehouseId = prefs.getInt('warehouse_id');
      if (warehouseId == null) {
        throw Exception('order_transfer.warehouse_info_not_found'.tr());
      }

      final containers = await _repo.getTransferableContainers(widget.order.id);
      final locationsMap = await _repo.getTargetLocations();
      final locations = locationsMap.entries.toList();

      if (mounted) {
        setState(() {
          _containers = containers;
          _cardKeys = List.generate(containers.length, (_) => GlobalKey());
          _availableLocations = locations;
          _isLoading = false;
          _targets.clear();
          _quantityControllers.clear();

          // Miktar kontrolcülerini oluştur
          for (var container in containers) {
            final controllers = <int, TextEditingController>{};
            for (var item in container.items) {
               final qty = item.quantity;
               final initialQtyText = qty == qty.truncate() ? qty.toInt().toString() : qty.toString();
               controllers[item.product.id] = TextEditingController(text: initialQtyText);
            }
            _quantityControllers[container.id] = controllers;
          }
        });

        // EĞER TRANSFER EDILECEK ÜRÜN KALMADIYSA, SAYFAYI KAPAT
        if (_containers.isEmpty) {
          if (mounted) {
            // Sipariş durumunu 3 (Tamamlandı) olarak güncelle
            await _repo.updatePurchaseOrderStatus(widget.order.id, 3);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('order_transfer.all_items_transferred'.tr())),
            );
            // Bir önceki sayfaya 'true' sonucuyla dönerek yenileme tetikle
            Navigator.of(context).pop(true);
          }
          return;
        }
        _scrollLater();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('order_transfer.data_load_error'.tr(namedArgs: {'error': e.toString()}), err: true);
      }
    }
  }

  /* ------------------  Lokasyon işleme (GÜNCELLENDİ) ------------------ */
  void _processScannedLocation(
      TransferableContainer container, String code) async {
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

  /* ------------------  UI yardımcıları ------------------ */
  void _focusNext() {
    final next = _containers.indexWhere(
            (c) => !_targets.containsKey(c.id), _focusedIndex + 1);
    setState(() {
      _focusedIndex =
      next != -1 ? next : _containers.indexWhere((c) => !_targets.containsKey(c.id));
    });
    _scrollLater();
  }

  void _scrollLater() => Future.delayed(
      const Duration(milliseconds: 100), () => _scrollTo(_focusedIndex));

  void _scrollTo(int index) {
    if (index < 0 || index >= _cardKeys.length) return;

    final key = _cardKeys[index];
    final context = key.currentContext;

    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /* ------------------  KAYDET (GÜNCELLENDİ) ------------------ */
  Future<void> _save() async {
    if (_targets.isEmpty) {
      _snack('order_transfer.cart_empty'.tr(), err: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = (await SharedPreferences.getInstance()).getInt('user_id');
      if (uid == null) throw 'order_transfer.user_not_found'.tr();

      // HEDEF LOKASYONLARINA GÖRE GRUPLANMIŞ TRANSFER DETAYLARI OLUŞTUR
      // Her bir hedef lokasyon için ayrı bir transfer işlemi kaydedilecek.
      final groupedTargets = <int, List<TransferableContainer>>{};
      for (final containerId in _targets.keys) {
        final targetLocation = _targets[containerId]!;
        (groupedTargets[targetLocation.value] ??= []).add(_containers.firstWhere((c) => c.id == containerId));
      }

      for (final entry in groupedTargets.entries) {
        final targetLocationId = entry.key;
        final targetLocationName = _targets.values.firstWhere((loc) => loc.value == targetLocationId).key;
        final containersForLocation = entry.value;

        // Her bir konteyner için ayrı başlık ve işlem oluştur
        for (final container in containersForLocation) {
          bool isFullPalletTransfer = true;
          final List<TransferItemDetail> detailsForOperation = [];

          final itemControllers = _quantityControllers[container.id]!;

          for (var item in container.items) {
            final qtyText = itemControllers[item.product.id]?.text ?? '0';
            final qty = double.tryParse(qtyText) ?? 0.0;

            if (qty > 0) {
              // Eğer miktar asıl miktardan farklıysa, bu bir palet bozma işlemidir.
              if (qty.toStringAsFixed(2) != item.quantity.toStringAsFixed(2)) {
                isFullPalletTransfer = false;
              }
              detailsForOperation.add(TransferItemDetail(
                productId: item.product.id,
                productName: item.product.name,
                productCode: item.product.stockCode,
                quantity: qty,
                sourcePalletBarcode: item.sourcePalletBarcode,
                targetLocationId: targetLocationId,
                targetLocationName: targetLocationName,
              ));
            }
          }

          if (detailsForOperation.isEmpty) continue;

          final operationType = isFullPalletTransfer ? AssignmentMode.pallet : AssignmentMode.boxFromPallet;

          final header = TransferOperationHeader(
            employeeId: uid,
            transferDate: DateTime.now(),
            operationType: operationType,
            sourceLocationName: sourceLocationName,
            targetLocationName: targetLocationName,
            containerId: container.id,
          );

          await _repo.recordTransferOperation(header, detailsForOperation, sourceLocationId, targetLocationId);
        }
      }

      if (!mounted) return;

      // Eğer online ise, işlemi hemen sunucuya göndermeyi dene
      if (await context.read<NetworkInfo>().isConnected) {
        await context.read<SyncService>().uploadPendingOperations();
      }

      _snack('order_transfer.saved'.tr());
      
      // Bir önceki sayfaya 'true' sonucuyla dönerek yenileme tetikle
      Navigator.of(context).pop(true);

    } catch (e) {
      if (!mounted) return;
      _snack('order_transfer.save_error'.tr(namedArgs: {'error': e.toString()}), err: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /* ==================  BUILD  ================== */
  @override
  Widget build(BuildContext context) {
    final canSave = _targets.isNotEmpty && !_isSaving;

    return Scaffold(
      appBar: SharedAppBar(
        title: 'order_transfer.title'.tr(),
        showBackButton: true,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: canSave ? _save : null,
          icon: _isSaving
              ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: Text('order_transfer.save_button'.tr(namedArgs: {'count': _targets.length.toString()})),
          style:
          ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
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
            OrderInfoCard(order: widget.order), // GÜNCELLENDİ
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
                      onClear: () {
                        setState(() => _targets.remove(c.id));
                      },
                      onTap: () {
                        final alreadyFocused = _focusedIndex == i;
                        setState(() {
                          _focusedIndex = i;
                        });
                        if (!alreadyFocused) {
                          _scrollTo(i);
                        }
                      },
                      onScan: (text) => _processScannedLocation(c, text),
                      quantityControllers: _quantityControllers[c.id] ?? {},
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

/// *************************
/// Tek konteyner kartı
/// *************************
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
    if (widget.target != null) _ctrl.text = widget.target!.key;
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ContainerCard old) {
    super.didUpdateWidget(old);
    if (widget.target?.key != old.target?.key) {
      _ctrl.text = widget.target?.key ?? '';
    }
    if (widget.focused && !old.focused) {
      // Kart odaklandığında metin alanına odaklan ve metni seç
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        if (_ctrl.text.isNotEmpty) {
          _ctrl.selection =
              TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
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
          itemToString: (item) => item.key,
          filterCondition: (item, query) =>
              item.key.toLowerCase().contains(query.toLowerCase()),
        ),
      ),
    );

    if (searchResult != null) {
      widget.onTarget(searchResult);
    }
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
              color: widget.focused
                  ? theme.colorScheme.primary
                  : assigned
                  ? Colors.green
                  : Colors.transparent,
              width: widget.focused ? 2.5 : 1.5),
        ),
        child: Column(
          children: [
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: widget.focused,
                onExpansionChanged: (expanding) {
                  // Kullanıcı başlığa dokunduğunda, durumu yönetmesi için
                  // her zaman üst widget'ın onTap'ını çağırırız.
                  if (expanding) {
                    widget.onTap();
                  }
                },
                title: Text(widget.container.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: assigned
                    ? Icon(Icons.check_circle, color: Colors.green.shade700)
                    : const Icon(Icons.pending_outlined),
                childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: widget.container.items.map((i) {
                  final qtyController = widget.quantityControllers[i.product.id]!;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: RichText(
                            text: TextSpan(
                              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
                              children: [
                                TextSpan(
                                  text: i.product.name,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                TextSpan(
                                  text: '  ·  ${i.product.stockCode}',
                                  style: TextStyle(color: theme.hintColor, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: qtyController,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'common_labels.quantity'.tr(),
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                               if (v == null || v.isEmpty) return 'validators.required'.tr();
                               final qty = double.tryParse(v);
                               if (qty == null) return 'validators.invalid'.tr();
                               if (qty > i.quantity) return 'validators.max_qty'.tr();
                               if (qty < 0) return 'validators.negative'.tr();
                               return null;
                            },
                          ),
                        )
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: assigned ? _rowAssigned(theme) : _rowInput(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowAssigned(ThemeData theme) => Row(
    children: [
      Icon(Icons.location_on, color: Colors.green.shade700),
      const SizedBox(width: 8),
      Expanded(
          child: Text(widget.target!.key,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold))),
      IconButton(
          icon: Icon(Icons.close, color: theme.colorScheme.error),
          onPressed: widget.onClear),
    ],
  );

  Widget _rowInput(ThemeData theme) {
    return SizedBox(
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
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                  onPressed: _showLocationSearch,
                ),
              ),
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  widget.onScan(value);
                }
              },
              onTap: () {
                // Odaklandığında tüm metni seç
                _focus.requestFocus();
                _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
              },
            ),
          ),
          const SizedBox(width: 8),
          _QrButton(
            onTap: () async {
              final res = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const QrScannerScreen()),
              );
              if (res != null && res.isNotEmpty) {
                widget.onScan(res);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;

  const _QrButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconSize = constraints.maxHeight * 0.6;
            return Icon(Icons.qr_code_scanner, size: iconSize);
          },
        ),
      ),
    );
  }
}

class _LocationSearchPage<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemToString;
  final bool Function(T, String) filterCondition;

  const _LocationSearchPage({
    required this.title,
    required this.items,
    required this.itemToString,
    required this.filterCondition,
  });

  @override
  State<_LocationSearchPage<T>> createState() => _LocationSearchPageState<T>();
}

class _LocationSearchPageState<T> extends State<_LocationSearchPage<T>> {
  String _searchQuery = '';
  late List<T> _filteredItems;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchCtrl.addListener(() {
      _filterItems(_searchCtrl.text);
    });
  }

  @override
  void dispose(){
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query;
      _filteredItems = widget.items
          .where((item) => widget.filterCondition(item, _searchQuery))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.appBarTheme.titleTextStyle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(child: Text('inventory_transfer.dialog_search_no_results'.tr()))
                  : ListView.separated(
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        return ListTile(
                          title: Text(widget.itemToString(item)),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

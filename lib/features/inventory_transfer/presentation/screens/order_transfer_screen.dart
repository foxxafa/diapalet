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
import 'package:receive_intent/receive_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final List<TransferableContainer> _containers = [];
  final Map<String, MapEntry<String, int>> _targets = {};
  int _focusedIndex = 0;
  List<MapEntry<String, int>> _availableLocations = [];

  final List<String> _debug = [];
  bool _showDebug = false;

  // sabitler
  static const sourceLocationName = 'Mal Kabul Alanı';
  static const sourceLocationId = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = context.read<InventoryTransferRepository>();
      _loadContainers();
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _intentSub?.cancel();
    super.dispose();
  }

  /* ------------------  Barkod ------------------ */
  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;

    _barcodeService = BarcodeIntentService();
    _addDbg('Barkod servisi başladı');

    final first = await _barcodeService.getInitialBarcode();
    if (first != null) _handleBarcode(first);

    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _addDbg('Barkod stream hatası: $e'));
  }

  void _handleBarcode(String code) {
    if (_containers.isEmpty) {
      _addDbg('Barkod geldi ama konteyner listesi boş');
      return;
    }
    _processScannedLocation(_containers[_focusedIndex], code);
  }

  /* ------------------  Veri ------------------ */
  Future<void> _loadContainers() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<InventoryTransferRepository>();
      final prefs = await SharedPreferences.getInstance();
      final warehouseId = prefs.getInt('warehouse_id');
      if (warehouseId == null) {
        throw Exception('Depo bilgisi bulunamadı. Lütfen tekrar giriş yapın.');
      }

      final results = await Future.wait([
        repo.getTransferableContainers(widget.order.id),
        repo.getAllLocations(warehouseId),
      ]);

      if (!mounted) return;

      final containerList = results[0] as List<TransferableContainer>;
      final locationList = results[1] as List<MapEntry<String, int>>;

      setState(() {
        _containers
          ..clear()
          ..addAll(containerList);
        _availableLocations = locationList;
        _targets.clear();
        _focusedIndex = 0;
      });

      // EĞER TRANSFER EDILECEK ÜRÜN KALMADIYSA, SAYFAYI KAPAT
      if (_containers.isEmpty && mounted) {
        // Kullanıcıya bilgi ver
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('order_transfer.all_items_transferred'.tr()),
          backgroundColor: Colors.green,
        ));
        // Bir önceki sayfaya 'true' sonucuyla dönerek yenileme tetikle
        Navigator.of(context).pop(true);
        return; // Fonksiyonun devamını çalıştırma
      }

      _scrollLater();
    } catch (e) {
      _snack('Veri yüklenemedi: $e', err: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ------------------  Lokasyon işleme (GÜNCELLENDİ) ------------------ */
  void _processScannedLocation(
      TransferableContainer container, String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;

    _addDbg("İşlenen barkod: '$clean'");
    try {
      // YENİ MANTIK: Artık doğrudan koda göre arama yapılıyor.
      final match = await _repo.findLocationByCode(clean);

      // Eşleşme bulundu mu ve kaynak lokasyonla aynı mı kontrolü
      if (match != null && match.value != sourceLocationId) {
        // Eşleşme bulundu, hedefi ata.
        _assignTarget(container, match);
      } else {
        // Eşleşme bulunamadı veya kaynak lokasyonla aynı.
        final reason = match == null ? 'Geçersiz lokasyon' : 'Kaynak ile aynı lokasyon';
        _snack('$reason: $clean', err: true);
      }
    } catch (e) {
      _snack('Lokasyon arama hatası: $e', err: true);
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
      const Duration(milliseconds: 50), () => _scrollTo(_focusedIndex));

  void _scrollTo(int index) {
    if (!_scrollController.hasClients) return;
    final offset = (index * 240.0).clamp(
        0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _addDbg(String m) {
    final t = DateTime.now();
    final s =
        '[${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}] $m';
    setState(() {
      _debug.insert(0, s);
      if (_debug.length > 50) _debug.removeLast();
    });
    debugPrint('DBG $m');
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor:
        err ? Theme.of(context).colorScheme.error : Colors.green,
      ));
  }

  /* ------------------  KAYDET ------------------ */
  Future<void> _save() async {
    if (_targets.isEmpty) {
      _snack('Sepet boş', err: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = (await SharedPreferences.getInstance()).getInt('user_id');
      if (uid == null) throw 'Kullanıcı bulunamadı';

      final allDetails = <TransferItemDetail>[];
      _targets.forEach((cid, loc) {
        final cont = _containers.firstWhere((c) => c.id == cid);
        for (final item in cont.items) {
          allDetails.add(TransferItemDetail(
            productId: item.product.id,
            productName: item.product.name,
            productCode: item.product.stockCode,
            quantity: item.quantity,
            sourcePalletBarcode: item.sourcePalletBarcode,
            targetLocationId: loc.value,
            targetLocationName: loc.key,
          ));
        }
      });

      // Öğeleri hedef lokasyona göre grupla
      final groupedByLocation = <int, List<TransferItemDetail>>{};
      for (final detail in allDetails) {
        (groupedByLocation[detail.targetLocationId!] ??= []).add(detail);
      }

      // Her lokasyon grubu için ayrı bir transfer operasyonu kaydet
      for (final entry in groupedByLocation.entries) {
        final targetLocationId = entry.key;
        final detailsForLocation = entry.value;
        final targetLocationName = detailsForLocation.first.targetLocationName;

        final header = TransferOperationHeader(
          employeeId: uid,
          transferDate: DateTime.now(),
          operationType: detailsForLocation.first.sourcePalletBarcode != null
              ? AssignmentMode.pallet
              : AssignmentMode.box,
          sourceLocationName: sourceLocationName,
          targetLocationName: targetLocationName,
        );

        await _repo.recordTransferOperation(
          header,
          detailsForLocation,
          sourceLocationId,
          targetLocationId,
        );
      }

      _snack('Kaydedildi');
      context.read<SyncService>().performFullSync(force: true);
      await _loadContainers();
    } catch (e) {
      _snack('Kaydetme hatası: $e', err: true);
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
        actions: [
          IconButton(
              tooltip: 'Debug',
              onPressed: () => setState(() => _showDebug = !_showDebug),
              icon: Icon(_showDebug
                  ? Icons.bug_report
                  : Icons.bug_report_outlined)),
        ],
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
          label: Text('Kaydet (${_targets.length})'),
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
            if (_showDebug) _debugPanel(),
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
                      key: ValueKey(c.id),
                      container: c,
                      focused: i == _focusedIndex,
                      target: _targets[c.id],
                      availableLocations: _availableLocations,
                      onTarget: (loc) => _assignTarget(c, loc),
                      onClear: () {
                        setState(() => _targets.remove(c.id));
                      },
                      onTap: () {
                        setState(() => _focusedIndex = i);
                        _scrollTo(i);
                      },
                      onScan: (text) => _processScannedLocation(c, text),
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

  Widget _debugPanel() => Card(
    margin: const EdgeInsets.only(top: 12),
    child: ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Debug'),
      children: [
        Container(
          height: 150,
          color: Colors.black87,
          padding: const EdgeInsets.all(8),
          child: ListView.builder(
            reverse: true,
            itemCount: _debug.length,
            itemBuilder: (_, i) => Text(_debug[i],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white)),
          ),
        ),
      ],
    ),
  );
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
        _focus.requestFocus();
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
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
      _focus.requestFocus();
      // Select all text when focus is gained
      _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
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
            ExpansionTile(
              key: PageStorageKey(widget.container.id),
              initiallyExpanded: widget.focused,
              onExpansionChanged: (ex) {
                if (ex) {
                  widget.onTap();
                  _focus.requestFocus();
                }
              },
              title: Text(widget.container.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: assigned
                  ? Icon(Icons.check_circle, color: Colors.green.shade700)
                  : const Icon(Icons.pending_outlined),
              childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: widget.container.items.map((i) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
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
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                                text: 'Miktar ',
                                style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor)
                            ),
                            TextSpan(
                              text: i.quantity.toStringAsFixed(0),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ]
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
    return Row(
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
              suffixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
            ),
            onTap: _showLocationSearch,
            readOnly: true,
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

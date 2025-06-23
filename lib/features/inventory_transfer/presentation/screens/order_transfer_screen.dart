// ----- lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart (GÜNCELLENDİ) -----
import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
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
/// Barkod Intent Servisi
/// *************************
class BarcodeIntentService {
  static const _supportedActions = {
    'unitech.scanservice.data', // Unitech
    'com.symbol.datawedge.data.ACTION', // Zebra
    'com.honeywell.decode.intent.action.DECODE_EVENT', // Honeywell
    'com.datalogic.decodewedge.decode_action', // Datalogic
    'nlscan.action.SCANNER_RESULT', // Newland
    'android.intent.action.SEND', // Paylaşılan metin
  };

  static const _payloadKeys = [
    'text', // Unitech
    'com.symbol.datawedge.data_string',
    'com.honeywell.decode.intent.extra.DATA_STRING',
    'nlscan_code',
    'scannerdata',
    'barcode_data',
    'barcode',
    'data',
    'android.intent.extra.TEXT',
  ];

  /// Sürekli dinleyen yayın.
  Stream<String> get stream => ReceiveIntent.receivedIntentStream
      .where((intent) =>
  intent != null && _supportedActions.contains(intent.action))
      .map(_extractBarcode)
      .where((code) => code != null)
      .cast<String>();

  /// Uygulama ilk açılırken gelen Intent’i getirir.
  Future<String?> getInitialBarcode() async {
    final intent = await ReceiveIntent.getInitialIntent();
    if (intent == null || !_supportedActions.contains(intent.action)) {
      return null;
    }
    return _extractBarcode(intent);
  }

  /// Ortak veri çıkarıcı
  String? _extractBarcode(Intent? intent) {
    if (intent == null) return null;
    for (final key in _payloadKeys) {
      final value = intent.extra?[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
      }
    }
    return null;
  }
}

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
      final list = await _repo.getTransferableContainers(widget.order.id);
      if (!mounted) return;
      setState(() {
        _containers
          ..clear()
          ..addAll(list);
        _targets.clear();
        _focusedIndex = 0;
      });
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
    if (!_scrollController.hasClients || _scrollController.position.maxScrollExtent == null) return;
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

      final details = <TransferItemDetail>[];
      _targets.forEach((cid, loc) {
        final cont = _containers.firstWhere((c) => c.id == cid);
        for (final item in cont.items) {
          details.add(TransferItemDetail(
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

      final header = TransferOperationHeader(
        employeeId: uid,
        transferDate: DateTime.now(),
        operationType: details.first.sourcePalletBarcode != null
            ? AssignmentMode.pallet
            : AssignmentMode.box,
        sourceLocationName: sourceLocationName,
        targetLocationName: 'Muhtelif',
      );

      // targetLocationId'yi geçici olarak 0 yapıyoruz, çünkü her item kendi hedefini içeriyor.
      // Sunucu tarafında bu durumun nasıl ele alınacağı önemli.
      // Eğer tek bir header targetId bekleniyorsa, mantığın değişmesi gerekir.
      // Mevcut yapıda her item'ın kendi hedefi olduğundan, header'daki anlamsız kalıyor.
      await _repo.recordTransferOperation(
          header, details, sourceLocationId, 0);

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
    if (_containers.isEmpty) return Center(child: Text('Bu siparişe ait, mal kabul alanında transfer edilecek ürün bulunmuyor.'));

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
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
  final ValueChanged<MapEntry<String, int>> onTarget;
  final VoidCallback onClear;
  final VoidCallback onTap;
  final void Function(String) onScan;

  const _ContainerCard({
    super.key,
    required this.container,
    required this.focused,
    required this.target,
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
    if (widget.focused) _focus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant _ContainerCard old) {
    super.didUpdateWidget(old);
    if (widget.target?.key != old.target?.key) _ctrl.text = widget.target?.key ?? '';
    if (widget.focused && !old.focused) _focus.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final t = text.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
    if (t.isNotEmpty) {
      widget.onScan(t);
      _ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assigned = widget.target != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
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
              children: widget.container.items
                  .map((i) => ListTile(
                dense: true,
                title: Text(i.product.name),
                subtitle: Text(i.product.stockCode),
                trailing:
                Text('Miktar: ${i.quantity.toStringAsFixed(0)}'),
              ))
                  .toList(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
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

  Widget _rowInput(ThemeData theme) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextFormField(
          controller: _ctrl,
          focusNode: _focus,
          decoration: InputDecoration(
            labelText: 'Hedef Raf',
            hintText: 'Okutun veya yazın',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) {
            if (v.contains('\n')) _submit(v);
          },
          onFieldSubmitted: _submit,
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: () async {
            final res = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                    builder: (_) => const QrScannerScreen()));
            if (res != null && res.isNotEmpty) _submit(res);
          },
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: const Icon(Icons.qr_code_scanner),
        ),
      ),
    ],
  );
}

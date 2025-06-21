// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart
import 'package:collection/collection.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() => _OrderTransferScreenState();
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
  late InventoryTransferRepository _repo;

  bool _isLoading = true;
  bool _isSaving = false;

  List<TransferableContainer> _transferableContainers = [];
  final List<TransferItemDetail> _transferCart = [];

  static const String sourceLocationName = "Mal Kabul Alanı";

  @override
  void initState() {
    super.initState();
    _repo = context.read<InventoryTransferRepository>();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _transferableContainers = [];
    });

    try {
      final containers = await _repo.getTransferableContainers(widget.order.id);
      if (mounted) {
        setState(() {
          _transferableContainers = containers;
        });
      }
    } catch (e, s) {
      if (mounted) {
        debugPrint("Konteyner yükleme hatası: $e\n$s");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Veri yüklenirken hata: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _transferContainer(TransferableContainer container) async {
    final selectedLocation = await showDialog<MapEntry<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SelectTargetLocationDialog(repo: _repo),
    );

    if (selectedLocation == null) return;

    final List<TransferItemDetail> itemsToAdd = [];
    for (final item in container.items) {
      itemsToAdd.add(TransferItemDetail(
        productId: item.product.id,
        productName: item.product.name,
        productCode: item.product.stockCode,
        quantity: item.quantity,
        sourcePalletBarcode: item.sourcePalletBarcode,
        targetLocationId: selectedLocation.value,
        targetLocationName: selectedLocation.key,
      ));
    }

    if (itemsToAdd.isEmpty) return;

    setState(() => _transferCart.addAll(itemsToAdd));

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${container.displayName} -> ${selectedLocation.key} hedefine eklendi."), backgroundColor: Colors.green));
  }

  Future<void> _saveTransferCart() async {
    if (_transferCart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lütfen önce transfer edilecek ürün ekleyin."), backgroundColor: Colors.red));
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmationDialog(
        transferItems: _transferCart,
        sourceLocationName: sourceLocationName,
      ),
    );
    if (confirmed == true) _executeSave();
  }

  Future<void> _executeSave() async {
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');
      if (employeeId == null) throw Exception("Kullanıcı bilgisi bulunamadı.");

      final groupedByTarget = groupBy(_transferCart, (item) => item.targetLocationId);

      const sourceLocationId = 1;

      for (var entry in groupedByTarget.entries) {
        final targetLocationId = entry.key;
        final itemsForTarget = entry.value;
        final targetLocationName = itemsForTarget.first.targetLocationName;

        // --- GÜNCELLEME BAŞLANGICI: Operasyon tipini dinamik olarak belirle ---
        // Eğer transfer sepetindeki ilk ürünün bir kaynak paleti varsa,
        // bu bir tam palet transferidir. Yoksa, kutu transferidir.
        final operationMode = itemsForTarget.first.sourcePalletBarcode != null
            ? AssignmentMode.pallet
            : AssignmentMode.box;

        final header = TransferOperationHeader(
          employeeId: employeeId,
          transferDate: DateTime.now(),
          // HATA BURADAYDI: Eskiden sabit olarak 'AssignmentMode.box' idi.
          operationType: operationMode,
          sourceLocationName: sourceLocationName,
          targetLocationName: targetLocationName,
        );
        // --- GÜNCELLEME SONU ---

        await _repo.recordTransferOperation(header, itemsForTarget, sourceLocationId, targetLocationId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Tüm transferler başarıyla kaydedildi! Senkronizasyon başlatılıyor..."), backgroundColor: Colors.green));

        context.read<SyncService>().performFullSync(force: true);

        setState(() => _transferCart.clear());
        _loadContainers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: "Sipariş Transferi", showBackButton: true),
      bottomNavigationBar: _transferCart.isNotEmpty ? _buildBottomBar() : null,
      body: Column(
        children: [
          _buildOrderHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transferableContainers.isEmpty
                ? Center(
              child: Text(
                "Bu siparişe ait taşınacak ürün bulunamadı.",
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadContainers,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80.0, left: 8, right: 8, top: 8),
                itemCount: _transferableContainers.length,
                itemBuilder: (context, index) {
                  final container = _transferableContainers[index];
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ExpansionTile(
                      title: Text(container.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: ElevatedButton.icon(
                        icon: const Icon(Icons.move_to_inbox, size: 18),
                        label: const Text("Tümünü Taşı"),
                        onPressed: () => _transferContainer(container),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact),
                      ),
                      children: container.items.map((item) {
                        return ListTile(
                          dense: true,
                          title: Text(item.product.name),
                          trailing: Text(
                            "Miktar: ${item.quantity.toStringAsFixed(0)}",
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveTransferCart,
        icon: _isSaving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text("${_transferCart.length} Kalemlik Transferi Kaydet"),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
    );
  }

  Widget _buildOrderHeader() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceVariant,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SİPARİŞ", style: Theme.of(context).textTheme.labelSmall),
          Text(widget.order.poId ?? 'PO-XXXX', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _SelectTargetLocationDialog extends StatefulWidget {
  final InventoryTransferRepository repo;
  const _SelectTargetLocationDialog({required this.repo});
  @override
  State<_SelectTargetLocationDialog> createState() => _SelectTargetLocationDialogState();
}

class _SelectTargetLocationDialogState extends State<_SelectTargetLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  Map<String, int> _targetLocations = {};
  int? _selectedLocationId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.repo.getTargetLocations().then((locations) {
      if (mounted) {
        setState(() {
          _targetLocations = locations;
          _isLoading = false;
        });
      }
    });
  }

  void _onConfirm() {
    if (!(_formKey.currentState?.validate() ?? false) || _selectedLocationId == null) return;
    final selectedEntry = _targetLocations.entries
        .firstWhere((entry) => entry.value == _selectedLocationId);
    Navigator.of(context).pop(selectedEntry);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Hedef Raf Seçin"),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: DropdownButtonFormField<int>(
          value: _selectedLocationId,
          hint: const Text("Hedef Raf Seçin"),
          items: _targetLocations.entries.map((entry) {
            return DropdownMenuItem<int>(
              value: entry.value,
              child: Text(entry.key),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedLocationId = val),
          validator: (val) => val == null ? "Hedef seçmek zorunludur." : null,
          isExpanded: true,
          autofocus: true,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("İptal")),
        ElevatedButton(onPressed: _isLoading ? null : _onConfirm, child: const Text("Onayla")),
      ],
    );
  }
}

class _ConfirmationDialog extends StatelessWidget {
  final List<TransferItemDetail> transferItems;
  final String sourceLocationName;
  const _ConfirmationDialog({required this.transferItems, required this.sourceLocationName});

  @override
  Widget build(BuildContext context) {
    final sortedItems = List<TransferItemDetail>.from(transferItems)
      ..sort((a, b) => a.targetLocationName.compareTo(b.targetLocationName));
    return AlertDialog(
      title: const Text("Transferi Onayla"),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text("$sourceLocationName lokasyonundan aşağıdaki transferler yapılacak. Onaylıyor musunuz?"),
            const Divider(height: 20),
            ...sortedItems.map((item) => ListTile(
              title: Text(item.productName),
              subtitle: Text("Hedef: ${item.targetLocationName}"),
              trailing: Text(item.quantity.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("İptal")),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Onayla ve Kaydet")),
      ],
    );
  }
}
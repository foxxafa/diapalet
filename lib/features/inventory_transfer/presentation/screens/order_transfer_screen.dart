// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seçilen bir siparişin kalemlerini listeleyen ve transfer işlemini başlatan ana ekran.
class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() => _OrderTransferScreenState();
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
  late Future<List<PurchaseOrderItem>> _itemsFuture;
  late InventoryTransferRepository _repo;

  // Varsayılan Mal Kabul lokasyon ID'si. Transferin kaynağı her zaman burası olacak.
  static const int sourceLocationId = 1;
  static const String sourceLocationName = "Mal Kabul Alanı";

  @override
  void initState() {
    super.initState();
    _repo = context.read<InventoryTransferRepository>();
    _loadItems();
  }

  void _loadItems() {
    setState(() {
      _itemsFuture = _repo.getPurchaseOrderItemsForTransfer(widget.order.id);
    });
  }

  Future<void> _showTransferDialog(PurchaseOrderItem item) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransferItemDialog(
        item: item,
        repo: _repo,
        sourceLocationId: sourceLocationId,
        sourceLocationName: sourceLocationName,
      ),
    );

    if (result == true && mounted) {
      _loadItems(); // İşlem başarılıysa listeyi yenile
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: "Sipariş Transferi",
        showBackButton: true,
      ),
      body: Column(
        children: [
          _buildOrderHeader(),
          Expanded(
            child: FutureBuilder<List<PurchaseOrderItem>>(
              future: _itemsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Hata: ${snapshot.error}"));
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(child: Text("Bu siparişe ait taşınacak kalem bulunamadı."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final remainingQty = item.receivedQuantity - item.transferredQuantity;
                    final bool isTransferCompleted = remainingQty < 0.01;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text(item.product?.name ?? "Bilinmeyen Ürün"),
                        subtitle: Text(
                          "Alınan: ${item.receivedQuantity.toStringAsFixed(0)} | Taşınan: ${item.transferredQuantity.toStringAsFixed(0)}",
                        ),
                        trailing: ElevatedButton.icon(
                          icon: Icon(isTransferCompleted ? Icons.check_circle : Icons.move_to_inbox),
                          onPressed: !isTransferCompleted ? () => _showTransferDialog(item) : null,
                          label: Text(isTransferCompleted ? "Taşındı" : "Taşı"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isTransferCompleted ? Colors.green : null,
                            foregroundColor: isTransferCompleted ? Colors.white : null,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
          Text(widget.order.supplierName ?? 'Tedarikçi bilgisi yok', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// --- Taşıma işleminin yapıldığı Modal Dialog ---
class _TransferItemDialog extends StatefulWidget {
  final PurchaseOrderItem item;
  final InventoryTransferRepository repo;
  final int sourceLocationId;
  final String sourceLocationName;

  const _TransferItemDialog({
    required this.item,
    required this.repo,
    required this.sourceLocationId,
    required this.sourceLocationName,
  });

  @override
  State<_TransferItemDialog> createState() => _TransferItemDialogState();
}

class _TransferItemDialogState extends State<_TransferItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _quantityController;
  Map<String, int> _targetLocations = {};
  String? _selectedTargetLocationName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final remainingQty = widget.item.receivedQuantity - widget.item.transferredQuantity;
    _quantityController = TextEditingController(text: remainingQty.toStringAsFixed(0));
    widget.repo.getTargetLocations().then((locations) {
      if (mounted) setState(() => _targetLocations = locations);
    });
  }

  @override
  void dispose(){
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');
      final targetLocationId = _targetLocations[_selectedTargetLocationName!];
      final quantity = double.tryParse(_quantityController.text) ?? 0.0;

      if (employeeId == null || targetLocationId == null) {
        throw Exception("Kullanıcı veya hedef lokasyon bilgisi bulunamadı.");
      }

      final header = TransferOperationHeader(
        employeeId: employeeId,
        transferDate: DateTime.now(),
        operationType: AssignmentMode.box, // Siparişten taşıma her zaman kutu bazlıdır
        sourceLocationName: widget.sourceLocationName,
        targetLocationName: _selectedTargetLocationName!,
      );

      final transferItem = TransferItemDetail(
        productId: widget.item.product!.id,
        productName: widget.item.product!.name,
        // DÜZELTME: 'productCode' yerine 'stockCode' kullanıldı.
        productCode: widget.item.product!.stockCode,
        quantity: quantity,
      );

      await widget.repo.recordTransferOperation(header, [transferItem], widget.sourceLocationId, targetLocationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transfer işlemi kaydedildi."), backgroundColor: Colors.green));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if(mounted){
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Ürün Taşı"),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.item.product?.name ?? '', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Taşınacak Miktar"),
                validator: (val) {
                  if (val == null || val.isEmpty) return "Miktar girin.";
                  final qty = double.tryParse(val);
                  final maxQty = widget.item.receivedQuantity - widget.item.transferredQuantity;
                  if (qty == null) return "Geçersiz sayı.";
                  if (qty <= 0) return "Miktar > 0 olmalı.";
                  if (qty > maxQty + 0.001) return "En fazla ${maxQty.toStringAsFixed(0)} taşıyabilirsiniz.";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTargetLocationName,
                hint: const Text("Hedef Raf Seçin"),
                items: _targetLocations.keys.map((name) {
                  return DropdownMenuItem(value: name, child: Text(name));
                }).toList(),
                onChanged: (val) => setState(() => _selectedTargetLocationName = val),
                validator: (val) => val == null ? "Hedef seçin." : null,
                isExpanded: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text("İptal"),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _onConfirm,
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Onayla"),
        ),
      ],
    );
  }
}

// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum GoodsReceivingMode { pallet, box }

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late final GoodsReceivingRepository _repository;
  final TextEditingController _receiptNumberController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  final List<GoodsReceiptItem> _receiptItems = [];
  final Map<int, TextEditingController> _quantityControllers = {};

  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
    _repository = GoodsReceivingRepositoryImpl(dbHelper: dbHelper);
    _loadPurchaseOrders();
  }

  Future<void> _loadPurchaseOrders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final orders = await _repository.getOpenPurchaseOrders();
      if (mounted) {
        setState(() {
          _purchaseOrders = orders;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Siparişler yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveReceipt() async {
    if (_selectedOrder == null || _receiptItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Lütfen sipariş seçin ve en az bir ürün miktarı girin.')),
      );
      return;
    }

    final receipt = GoodsReceipt(
      id: 0, // Yeni kayıt için 0
      purchaseOrderId: _selectedOrder!.id,
      receiptNumber: _receiptNumberController.text,
      receiptDate: DateTime.now(),
      notes: _notesController.text,
      status: 'pending', // Senkronizasyon bekliyor
      items: _receiptItems,
    );

    try {
      await _repository.saveGoodsReceipt(receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Mal kabul kaydı başarıyla oluşturuldu')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  void _onOrderItemChanged(PurchaseOrderItem item, String value) {
    final quantity = double.tryParse(value) ?? 0.0;

    _receiptItems.removeWhere((receiptItem) => receiptItem.productId == item.productId);

    if (quantity > 0) {
      _receiptItems.add(
        GoodsReceiptItem(
          id: 0,
          goodsReceiptId: 0, // DB'de atanacak
          productId: item.productId,
          quantity: quantity,
          notes: '',
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mal Kabul'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderSelection(),
                  if (_selectedOrder != null) _buildOrderDetails(),
                ],
              ),
            ),
      bottomNavigationBar: _selectedOrder != null
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: _saveReceipt,
                child: const Text('Kaydet'),
              ),
            )
          : null,
    );
  }

  Widget _buildOrderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sipariş Seç', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<PurchaseOrder>(
          value: _selectedOrder,
          items: _purchaseOrders.map((order) {
            return DropdownMenuItem(
              value: order,
              child: Text(
                  '${order.orderNumber} - ${order.supplierName ?? 'Tedarikçi Yok'}'),
            );
          }).toList(),
          onChanged: (order) async {
            if (order == null) return;
            setState(() {
              _selectedOrder = order;
              _receiptItems.clear();
              _quantityControllers.forEach((key, val) => val.dispose());
              _quantityControllers.clear();
            });
            await _loadOrderItems(order.id);
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            hintText: 'Bir sipariş seçin',
          ),
          isExpanded: true,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _receiptNumberController,
          decoration: const InputDecoration(
            labelText: 'İrsaliye Numarası',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notlar',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Future<void> _loadOrderItems(int orderId) async {
    setState(() => _isLoading = true);
    try {
      final items = await _repository.getPurchaseOrderItems(orderId);
      if(mounted) {
        setState(() {
          for (var item in items) {
            _quantityControllers[item.id] = TextEditingController();
          }
        });
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sipariş kalemleri yüklenemedi: $e')));
      }
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  Widget _buildOrderDetails() {
    if (_selectedOrder == null) return const SizedBox.shrink();
    
    return FutureBuilder<List<PurchaseOrderItem>>(
      future: _repository.getPurchaseOrderItems(_selectedOrder!.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Bu siparişe ait ürün bulunamadı.'));
        }

        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text('Sipariş Kalemleri',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                _quantityControllers.putIfAbsent(item.id, () => TextEditingController());
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(item.product?.name ?? 'Ürün Adı Yok'),
                    subtitle: Text('Sipariş: ${item.quantity}'),
                    trailing: SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _quantityControllers[item.id],
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Gelen',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _onOrderItemChanged(item, value),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _receiptNumberController.dispose();
    _notesController.dispose();
    _quantityControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }
}

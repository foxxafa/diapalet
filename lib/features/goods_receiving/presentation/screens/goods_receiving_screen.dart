// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/recent_receipt_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

enum GoodsReceivingMode { pallet, box }

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late final GoodsReceivingRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _receiptNumberController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
  final Map<int, TextEditingController> _quantityControllers = {};
  List<GoodsReceiptItem> _receiptItems = [];

  bool _isLoading = false;

  // UI State
  GoodsReceivingMode _mode = GoodsReceivingMode.pallet;
  List<RecentReceiptItem> _recentReceipts = [];

  // Form Controllers
  final _palletBarcodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = GoodsReceivingRepositoryImpl(DatabaseHelper());
    _loadPurchaseOrders();
    _loadRecentReceipts();
  }

  Future<void> _loadPurchaseOrders() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final orders = await _repository.getPurchaseOrders();
      setState(() {
        _purchaseOrders = orders;
      });
    } catch (e) {
      // Handle error
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRecentReceipts() async {
    try {
      final receipts = await _repository.getRecentReceipts(limit: 50);
      if (mounted) {
        setState(() {
          _recentReceipts = receipts;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading recent receipts: $e")),
        );
      }
    }
  }

  Future<void> _onOrderSelected(PurchaseOrder order) async {
    setState(() {
      _isLoading = true;
      _selectedOrder = order;
      _orderItems = [];
      _quantityControllers.clear();
    });
    try {
      final items = await _repository.getPurchaseOrderItems(order.id);
      if (mounted) {
        setState(() {
          _orderItems = items;
          for (var item in items) {
            // Başlangıçta beklenen miktar ile doldur
            _quantityControllers[item.id] = TextEditingController(text: item.orderedQuantity.toString());
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading order items: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveReceipt() async {
    if (_selectedOrder == null) return;

    final receipt = GoodsReceipt(
      id: 0, // Yeni kayıt
      purchaseOrderId: _selectedOrder!.id,
      receiptNumber: _receiptNumberController.text,
      receiptDate: DateTime.now(),
      notes: _notesController.text,
      status: 'pending',
      items: _receiptItems,
    );

    try {
      await _repository.saveGoodsReceipt(receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mal kabul kaydı başarıyla oluşturuldu')),
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
    if (quantity > 0) {
      final existingIndex =
          _receiptItems.indexWhere((element) => element.productId == item.productId);
      if (existingIndex != -1) {
        _receiptItems[existingIndex] = GoodsReceiptItem(
          id: _receiptItems[existingIndex].id,
          goodsReceiptId: _receiptItems[existingIndex].goodsReceiptId,
          productId: item.productId,
          quantity: quantity,
          notes: '',
        );
      } else {
        _receiptItems.add(
          GoodsReceiptItem(
            id: 0,
            goodsReceiptId: 0,
            productId: item.productId,
            quantity: quantity,
            notes: '',
          ),
        );
      }
    } else {
      _receiptItems.removeWhere((element) => element.productId == item.productId);
    }
    setState(() {});
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
    if (barcode != null && barcode.isNotEmpty) {
      _palletBarcodeController.text = barcode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mal Kabul')),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModeSelector(),
                  const SizedBox(height: 16),
                  _buildOrderSelector(),
                  const SizedBox(height: 16),
                  if (_mode == GoodsReceivingMode.pallet) ...[
                    _buildPalletBarcodeField(),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedOrder != null) Expanded(child: _buildOrderItemsList()),
                  if (_selectedOrder == null) Expanded(child: _buildRecentReceiptsList()),
                ],
              ),
            ),
      floatingActionButton: _selectedOrder != null
          ? FloatingActionButton.extended(
              onPressed: _saveReceipt,
              label: const Text('Kaydet'),
              icon: const Icon(Icons.save),
            )
          : null,
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<GoodsReceivingMode>(
      segments: const <ButtonSegment<GoodsReceivingMode>>[
        ButtonSegment<GoodsReceivingMode>(value: GoodsReceivingMode.pallet, label: Text('Palet'), icon: Icon(Icons.pallet)),
        ButtonSegment<GoodsReceivingMode>(value: GoodsReceivingMode.box, label: Text('Kutu'), icon: Icon(Icons.inventory_2)),
      ],
      selected: <GoodsReceivingMode>{_mode},
      onSelectionChanged: (Set<GoodsReceivingMode> newSelection) {
        setState(() {
          _mode = newSelection.first;
        });
      },
    );
  }

  Widget _buildOrderSelector() {
    return Autocomplete<PurchaseOrder>(
      displayStringForOption: (option) => option.poId ?? 'PO #${option.id}',
      optionsBuilder: (TextEditingValue textEditingValue) {
        return _repository.getOpenPurchaseOrders(); // Simplified: fetches all open orders
      },
      onSelected: _onOrderSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Satınalma Siparişi Seç',
            hintText: 'Sipariş ara...',
            suffixIcon: _selectedOrder != null 
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                  setState(() {
                    _selectedOrder = null;
                    _orderItems = [];
                    controller.clear();
                  });
                })
              : null,
          ),
        );
      },
    );
  }

  Widget _buildPalletBarcodeField() {
    return TextFormField(
      controller: _palletBarcodeController,
      decoration: InputDecoration(
        labelText: 'Palet Barkodu',
        hintText: 'Palet barkodunu okutun veya girin',
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: _scanBarcode,
        ),
      ),
    );
  }
  
  Widget _buildOrderItemsList() {
    if (_orderItems.isEmpty) return const Center(child: Text('Bu siparişe ait ürün bulunamadı.'));
    
    return ListView.builder(
      itemCount: _orderItems.length,
      itemBuilder: (context, index) {
        final item = _orderItems[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Beklenen Miktar: ${item.orderedQuantity} ${item.unit}'),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _quantityControllers[item.id],
                    decoration: const InputDecoration(labelText: 'Gelen Miktar'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentReceiptsList() {
    if (_recentReceipts.isEmpty) return const Center(child: Text('Son işlem bulunmuyor.'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Son İşlemler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _recentReceipts.length,
            itemBuilder: (context, index) {
              final item = _recentReceipts[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text('${item.productName} (${item.quantity} birim)'),
                  subtitle: Text(
                    'Palet: ${item.palletBarcode ?? "YOK"}\nTarih: ${DateFormat.yMd().add_Hms().format(DateTime.parse(item.createdAt))}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _receiptNumberController.dispose();
    _notesController.dispose();
    _quantityControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }
}

// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/recent_receipt_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

enum GoodsReceivingMode { pallet, box }

class GoodsReceiptScreen extends StatefulWidget {
  const GoodsReceiptScreen({super.key});

  @override
  State<GoodsReceiptScreen> createState() => _GoodsReceiptScreenState();
}

class _GoodsReceiptScreenState extends State<GoodsReceiptScreen> {
  late final GoodsReceivingRepository _repository;

  // UI State
  GoodsReceivingMode _mode = GoodsReceivingMode.pallet;
  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
  List<RecentReceiptItem> _recentReceipts = [];
  bool _isLoading = false;

  // Form Controllers
  final _palletBarcodeController = TextEditingController();
  // Her bir sipariş kalemi için bir controller listesi tutacağız
  final Map<int, TextEditingController> _quantityControllers = {};

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadRecentReceipts();
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
    if (_selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a purchase order first.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final palletBarcode = _mode == GoodsReceivingMode.pallet ? _palletBarcodeController.text.trim() : null;
    if (_mode == GoodsReceivingMode.pallet && (palletBarcode == null || palletBarcode.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pallet barcode is required for pallet receiving mode.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final List<({int productId, double quantity, String? palletBarcode})> receivedItems = [];
    for (var item in _orderItems) {
      final quantity = double.tryParse(_quantityControllers[item.id]?.text ?? '0') ?? 0;
      if (quantity > 0) {
        receivedItems.add((
          productId: item.productId,
          quantity: quantity,
          palletBarcode: palletBarcode,
        ));
      }
    }

    if (receivedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter quantity for at least one item.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() { _isLoading = true; });
    try {
      await _repository.saveGoodsReceipt(
        purchaseOrderId: _selectedOrder!.id,
        items: receivedItems,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goods receipt saved successfully!'), backgroundColor: Colors.green),
      );
      // Reset state
      setState(() {
        _selectedOrder = null;
        _orderItems = [];
        _quantityControllers.clear();
        _palletBarcodeController.clear();
      });
      await _loadRecentReceipts(); // Refresh logs
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving receipt: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
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
}

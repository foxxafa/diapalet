// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_log_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter
import 'package:easy_localization/easy_localization.dart';

// Palet ve Kutu modları için enum tanımı
enum GoodsReceivingMode { pallet, box }

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final GoodsReceivingRepository _repository;

  final _productController = TextEditingController();
  final _locationController = TextEditingController();
  final _palletBarcodeController = TextEditingController();
  final _quantityController = TextEditingController();

  ProductInfo? _selectedProduct;
  LocationInfo? _selectedLocation;
  
  List<GoodsReceiptLogItem> _logItems = [];

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadInitialLogs();
  }

  void _loadInitialLogs() async {
    final logs = await _repository.getRecentReceipts(limit: 50);
    if (mounted) {
      setState(() {
        _logItems = logs;
      });
    }
  }

  void _onProductSelected(ProductInfo? product) {
    setState(() {
      _selectedProduct = product;
      if (product != null) {
        _productController.text = product.name;
      }
    });
  }

  void _onLocationSelected(LocationInfo? location) {
    setState(() {
      _selectedLocation = location;
       if (location != null) {
        _locationController.text = location.name;
      }
    });
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );
    if (barcode != null && barcode.isNotEmpty) {
      setState(() {
        _palletBarcodeController.text = barcode;
      });
    }
  }

  Future<void> _saveReceipt() async {
    if (_formKey.currentState!.validate() && _selectedProduct != null && _selectedLocation != null) {
      final palletBarcode = _palletBarcodeController.text.trim();
      final quantity = double.tryParse(_quantityController.text);

      if (quantity == null || quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid quantity.')),
        );
        return;
      }
      
      await _repository.saveGoodsReceipt(
        productId: _selectedProduct!.id,
        locationId: _selectedLocation!.id,
        quantity: quantity,
        palletBarcode: palletBarcode.isEmpty ? null : palletBarcode,
      );

      _formKey.currentState!.reset();
      _productController.clear();
      _locationController.clear();
      _palletBarcodeController.clear();
      _quantityController.clear();
      setState(() {
        _selectedProduct = null;
        _selectedLocation = null;
      });
      _loadInitialLogs(); 

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goods receipt saved successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goods Receiving')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Product Autocomplete
              Autocomplete<ProductInfo>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<ProductInfo>.empty();
                  }
                  return _repository.getProducts(filter: textEditingValue.text);
                },
                onSelected: _onProductSelected,
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Product', hintText: 'Start typing to search...'),
                    validator: (value) => _selectedProduct == null ? 'Please select a product' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              // Location Autocomplete
              Autocomplete<LocationInfo>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<LocationInfo>.empty();
                  }
                  return _repository.getLocations(filter: textEditingValue.text);
                },
                onSelected: _onLocationSelected,
                 fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Location'),
                     validator: (value) => _selectedLocation == null ? 'Please select a location' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (value) {
                  if (value == null || value.isEmpty || double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _palletBarcodeController,
                decoration: InputDecoration(
                  labelText: 'Pallet Barcode (Optional)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanBarcode,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveReceipt,
                child: const Text('Save Receipt'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const Divider(height: 32),
              const Text('Recent Receipts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Expanded(
                child: ListView.builder(
                  itemCount: _logItems.length,
                  itemBuilder: (context, index) {
                    final item = _logItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.check_circle, color: Colors.green),
                        title: Text(
                          '${item.urun_name} (${item.quantity} units)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Pallet: ${item.container_id ?? 'N/A'}\nTo: ${item.location_name} at ${item.created_at}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

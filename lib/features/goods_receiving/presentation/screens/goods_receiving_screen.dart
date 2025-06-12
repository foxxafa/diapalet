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
import 'package:intl/intl.dart';

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

  ProductInfo? _selectedProduct;
  LocationInfo? _selectedLocation;

  List<GoodsReceiptLogItem> _logItems = [];

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadInitialLogs();
  }

  Future<void> _loadInitialLogs() async {
    try {
      final logs = await _repository.getRecentReceipts(limit: 50);
      if (mounted) {
        setState(() {
          _logItems = logs;
        });
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading logs: $e")));
    }
  }

  void _onProductSelected(ProductInfo product, TextEditingController controller) {
    setState(() {
      _selectedProduct = product;
      controller.text = product.name;
    });
  }

  void _onLocationSelected(LocationInfo location, TextEditingController controller) {
    setState(() {
      _selectedLocation = location;
      controller.text = location.name;
    });
  }

  Future<void> _scanBarcode(TextEditingController controller) async {
      final barcode = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
    if (barcode != null && barcode.isNotEmpty) {
      controller.text = barcode;
    }
  }

  Future<void> _saveReceipt(BuildContext context, Map<String, TextEditingController> controllers) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final palletBarcode = controllers['pallet']!.text.trim();
    final quantity = double.tryParse(controllers['quantity']!.text);

    try {
      await _repository.saveGoodsReceipt(
        productId: _selectedProduct!.id,
        locationId: _selectedLocation!.id,
        quantity: quantity!,
        palletBarcode: palletBarcode.isEmpty ? null : palletBarcode,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goods receipt saved successfully!'), backgroundColor: Colors.green),
      );

      _formKey.currentState!.reset();
      controllers.forEach((_, c) => c.clear());
      setState(() {
        _selectedProduct = null;
        _selectedLocation = null;
      });
      _loadInitialLogs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving receipt: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palletController = TextEditingController();
    final quantityController = TextEditingController();
    final productController = TextEditingController();
    final locationController = TextEditingController();

    final controllers = {
      'pallet': palletController,
      'quantity': quantityController,
      'product': productController,
      'location': locationController,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Goods Receiving')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Autocomplete<ProductInfo>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const Iterable.empty();
                  return _repository.getProducts(filter: textEditingValue.text);
                },
                onSelected: (product) => _onProductSelected(product, productController),
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Product', hintText: 'Search product...'),
                    validator: (value) => _selectedProduct == null ? 'Please select a product' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              Autocomplete<LocationInfo>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) return const Iterable.empty();
                  return _repository.getLocations(filter: textEditingValue.text);
                },
                onSelected: (location) => _onLocationSelected(location, locationController),
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
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty || (double.tryParse(value) ?? 0) <= 0) {
                    return 'Please enter a valid quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: palletController,
                decoration: InputDecoration(
                  labelText: 'Pallet Barcode (Optional)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () => _scanBarcode(palletController),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _saveReceipt(context, controllers),
                child: const Text('Save Receipt'),
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
                        title: Text('${item.urunName} (${item.quantity} units)'),
                        subtitle: Text(
                          'Pallet: ${item.containerId ?? "N/A"}\nTo: ${item.locationName} at ${DateFormat.yMd().add_Hms().format(DateTime.parse(item.createdAt))}',
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

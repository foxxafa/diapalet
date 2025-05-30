import 'package:diapalet/features/product_placement/data/mock_product_service.dart';
import 'package:flutter/material.dart';

class ProductPlacementScreen extends StatefulWidget {
  const ProductPlacementScreen({super.key});

  @override
  State<ProductPlacementScreen> createState() => _ProductPlacementScreenState();
}

class _ProductPlacementScreenState extends State<ProductPlacementScreen> {
  List<String> _products = [];

  @override
  void initState() {
    super.initState();
    loadDummy();
  }

  void loadDummy() async {
    final items = await MockProductService.getProducts();
    setState(() {
      _products = items;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Products to Pallet')),
      body: ListView.builder(
        itemCount: _products.length,
        itemBuilder: (context, index) {
          return ListTile(title: Text(_products[index]));
        },
      ),
    );
  }
}

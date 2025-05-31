import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../domain/product_repository.dart';

class ProductPlacementScreen extends StatefulWidget {
  const ProductPlacementScreen({super.key});

  @override
  State<ProductPlacementScreen> createState() => _ProductPlacementScreenState();
}

class _ProductPlacementScreenState extends State<ProductPlacementScreen> {
  late final ProductRepository _repository;

  List<String> pallets = [];
  List<String> invoices = [];
  List<String> products = [];

  String? selectedPallet;
  String? selectedInvoice;
  String? selectedProduct;
  final TextEditingController quantityController = TextEditingController();

  List<Map<String, dynamic>> addedProducts = [];
  bool _loading = true;
  final _borderRadius = BorderRadius.circular(12);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = Provider.of<ProductRepository>(context, listen: false);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    pallets = await _repository.getPallets();
    invoices = await _repository.getInvoices();
    products = await _repository.getProducts();
    setState(() {
      selectedPallet = pallets.isNotEmpty ? pallets.first : null;
      selectedInvoice = invoices.isNotEmpty ? invoices.first : null;
      selectedProduct = products.isNotEmpty ? products.first : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double buttonHeight = screenHeight * 0.10;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Palete Ürün Yerleştir'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        height: buttonHeight,
        child: ElevatedButton.icon(
          onPressed: _loading ? null : onConfirm,
          icon: const Icon(Icons.check),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Palet Seç'),
                        value: selectedPallet,
                        items: pallets
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) => setState(() => selectedPallet = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _QrButton(onTap: () {}),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: _inputDecoration('İrsaliye Seç'),
                        value: selectedInvoice,
                        items: invoices
                            .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                            .toList(),
                        onChanged: (val) => setState(() => selectedInvoice = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Ürün Seç'),
                        value: selectedProduct,
                        items: products
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) => setState(() => selectedProduct = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _QrButton(onTap: () {}),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Miktar Girin'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: addProduct,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.add, size: 22),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Eklenen Ürünler',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Divider(height: 1),
                      addedProducts.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(
                          child: Text('Henüz ürün eklenmedi.',
                              style: TextStyle(fontStyle: FontStyle.italic)),
                        ),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: addedProducts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = addedProducts[index];
                          return ListTile(
                            title: Text(item['product']),
                            trailing: Text(
                              '${item['quantity']}x',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: _borderRadius),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );

  void addProduct() {
    if (selectedProduct == null || quantityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen ürün ve miktar girin.')),
      );
      return;
    }
    setState(() {
      addedProducts.add({
        'product': selectedProduct!,
        'quantity': int.parse(quantityController.text),
      });
      quantityController.clear();
    });
  }

  void onConfirm() {
    debugPrint('Palet: $selectedPallet');
    debugPrint('İrsaliye: $selectedInvoice');
    debugPrint('Ürünler: $addedProducts');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Palet kaydedildi!')),
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QrButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.qr_code_scanner, size: 24),
        ),
      ),
    );
  }
}

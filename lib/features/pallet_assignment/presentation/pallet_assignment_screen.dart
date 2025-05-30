import 'package:flutter/material.dart';

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  // Dummy listeler
  final List<String> pallets = ['Palet A', 'Palet B', 'Palet C'];
  final List<String> invoices = ['İrsaliye 1', 'İrsaliye 2'];
  final List<String> products = ['Gofret', 'Sucuk', 'Bal'];

  // Seçimler
  String? selectedPallet;
  String? selectedInvoice;
  String? selectedProduct;

  // Miktar girişi
  final TextEditingController quantityController = TextEditingController();

  // Eklenen ürünler listesi
  List<Map<String, dynamic>> addedProducts = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Palet Oluştur'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Palet Seç
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Palet Seç'),
                value: selectedPallet,
                items: pallets
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    selectedPallet = val;
                  });
                },
              ),
              const SizedBox(height: 16),

              // İrsaliye Seç
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'İrsaliye Seç'),
                value: selectedInvoice,
                items: invoices
                    .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    selectedInvoice = val;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Ürün Seç
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Ürün Seç'),
                value: selectedProduct,
                items: products
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    selectedProduct = val;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Miktar Girişi + Ekle Butonu
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Miktar Girin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: addProduct,
                    child: const Text("Ekle"),
                  )
                ],
              ),
              const SizedBox(height: 24),

              // Eklenen Ürünler Listesi
              const Text(
                'Eklenen Ürünler:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: addedProducts.length,
                  itemBuilder: (context, index) {
                    final item = addedProducts[index];
                    return ListTile(
                      title: Text(item['product']),
                      trailing: Text('${item['quantity']}x'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Onayla Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  child: const Text("Onayla"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

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
    // Şimdilik dummy işlem yapıyoruz
    debugPrint('Palet: $selectedPallet');
    debugPrint('İrsaliye: $selectedInvoice');
    debugPrint('Ürünler: $addedProducts');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Palet kaydedildi!')),
    );
  }
}

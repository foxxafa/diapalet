// features/product_placement/presentation/product_placement_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../domain/product_repository.dart'; // Assuming this path is correct for your project
import '../../../core/widgets/qr_scanner_screen.dart'; // Import the scanner screen

class ProductPlacementScreen extends StatefulWidget {
  const ProductPlacementScreen({super.key});

  @override
  State<ProductPlacementScreen> createState() => _ProductPlacementScreenState();
}

class _ProductPlacementScreenState extends State<ProductPlacementScreen> {
  // ---- repo & state ---------------------------------------------------------
  late ProductRepository _repository;
  bool _isRepoInitialized = false;

  List<String> pallets = [];
  List<String> invoices = [];
  List<String> products = [];

  String? selectedPallet;
  String? selectedInvoice;
  String? selectedProduct;
  final TextEditingController quantityController = TextEditingController();

  List<Map<String, dynamic>> addedProducts = [];
  bool _loading = true;

  // ---- ui constants ---------------------------------------------------------
  static const double _fieldHeight = 56;      // tüm giriş/btn yüksekliği
  static const double _gap = 8;              // yan boşluk
  final _borderRadius = BorderRadius.circular(12);

  // ---------------------------------------------------------------------------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repository = Provider.of<ProductRepository>(context, listen: false);
      _loadData();
      _isRepoInitialized = true;
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      pallets  = await _repository.getPallets();
      invoices = await _repository.getInvoices();
      products = await _repository.getProducts();
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yüklenirken hata oluştu: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) {
      setState(() {
        selectedPallet  = pallets.isNotEmpty  ? pallets.first  : null;
        selectedInvoice = invoices.isNotEmpty ? invoices.first : null;
        selectedProduct = products.isNotEmpty ? products.first : null;
        _loading = false;
      });
    }
  }

  Future<void> _scanQrAndUpdateDropdown(String fieldType) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      String fieldNameForSnackbar = '';
      bool isValid = false;

      if (fieldType == 'pallet') {
        fieldNameForSnackbar = 'Palet';
        if (pallets.contains(result)) {
          setState(() => selectedPallet = result);
          isValid = true;
        }
      } else if (fieldType == 'product') {
        fieldNameForSnackbar = 'Ürün';
        if (products.contains(result)) {
          setState(() => selectedProduct = result);
          isValid = true;
        }
      }
      // İrsaliye için de benzer bir yapı eklenebilir istenirse.
      // else if (fieldType == 'invoice') {
      //   fieldNameForSnackbar = 'İrsaliye';
      //   if (invoices.contains(result)) {
      //     setState(() => selectedInvoice = result);
      //     isValid = true;
      //   }
      // }

      if (isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$fieldNameForSnackbar QR ile seçildi: $result'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Taranan QR ($result) geçerli bir $fieldNameForSnackbar seçeneği değil.'), backgroundColor: Colors.orangeAccent, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }


  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomNavHeight = (screenHeight * 0.09).clamp(70.0, 90.0);


    return Scaffold(
      appBar: AppBar(
        title: const Text('Palete Ürün Yerleştir'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(bottom: 8.0, left: 20.0, right: 20.0),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _loading || addedProducts.isEmpty ? null : onConfirm,
          icon: const Icon(Icons.check),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- PALET --------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: _palletDropdown(),
                  ),
                  const SizedBox(width: _gap),
                  _QrButton(
                    onTap: () => _scanQrAndUpdateDropdown('pallet'),
                    size: _fieldHeight,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ---------- İRSALİYE -----------------------------------------------
              Row(
                children: [
                  Expanded(child: _invoiceDropdown()),
                  const SizedBox(width: _gap),
                  // İrsaliye için QR butonu yoksa boşluk bırakılır
                  SizedBox(width: _fieldHeight, height: _fieldHeight),
                ],
              ),
              const SizedBox(height: 12),

              // ---------- ÜRÜN ----------------------------------------------------
              Row(
                children: [
                  Expanded(child: _productDropdown()),
                  const SizedBox(width: _gap),
                  _QrButton(
                    onTap: () => _scanQrAndUpdateDropdown('product'),
                    size: _fieldHeight,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ---------- MİKTAR & + BUTONU --------------------------------------
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _fieldHeight,
                      child: TextField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Miktar Girin'),
                      ),
                    ),
                  ),
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: _fieldHeight,
                    height: _fieldHeight,
                    child: ElevatedButton(
                      onPressed: addProduct,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: _borderRadius,
                        ),
                        padding: EdgeInsets.zero,
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Icon(Icons.add, size: 30.0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ---------- EKLENEN ÜRÜNLER LİSTESİ --------------------------------
              _addedProductList(),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------- widgets ----------------------------------------
  Widget _buildDropdownContainer(Widget dropdown) {
    return Container(
      height: _fieldHeight,
      alignment: Alignment.center,
      child: dropdown,
    );
  }

  DropdownButtonFormField<String> _palletDropdown() => DropdownButtonFormField(
    decoration: _inputDecoration('Palet Seç', filled: true),
    value: selectedPallet,
    isExpanded: true,
    items: pallets.isEmpty
        ? [DropdownMenuItem(value: null, child: Text('Palet Yok', style: TextStyle(color: Colors.grey)))]
        : pallets.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
    onChanged: pallets.isEmpty ? null : (val) => setState(() => selectedPallet = val),
    hint: pallets.isEmpty ? null : const Text("Palet Seçin"),
  );

  DropdownButtonFormField<String> _invoiceDropdown() => DropdownButtonFormField(
    decoration: _inputDecoration('İrsaliye Seç', filled: true),
    value: selectedInvoice,
    isExpanded: true,
    items: invoices.isEmpty
        ? [DropdownMenuItem(value: null, child: Text('İrsaliye Yok', style: TextStyle(color: Colors.grey)))]
        : invoices.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
    onChanged: invoices.isEmpty ? null : (val) => setState(() => selectedInvoice = val),
    hint: invoices.isEmpty ? null : const Text("İrsaliye Seçin"),
  );

  DropdownButtonFormField<String> _productDropdown() => DropdownButtonFormField(
    decoration: _inputDecoration('Ürün Seç', filled: true),
    value: selectedProduct,
    isExpanded: true,
    items: products.isEmpty
        ? [DropdownMenuItem(value: null, child: Text('Ürün Yok', style: TextStyle(color: Colors.grey)))]
        : products.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
    onChanged: products.isEmpty ? null : (val) => setState(() => selectedProduct = val),
    hint: products.isEmpty ? null : const Text("Ürün Seçin"),
  );

  Widget _addedProductList() => Expanded(
    child: Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Eklenen Ürünler',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: addedProducts.isEmpty
                ? const Center(
              child: Text(
                'Henüz ürün eklenmedi.',
                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            )
                : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: addedProducts.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final item = addedProducts[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  title: Text(
                    '${item['product']}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  subtitle: Text('Palet: ${item['pallet']} / İrsaliye: ${item['invoice']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${item['quantity']}x',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _removeProduct(index),
                        tooltip: 'Ürünü Sil',
                      )
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  // -------------------------- helpers ----------------------------------------
  InputDecoration _inputDecoration(String label, {bool filled = false}) => InputDecoration(
    labelText: label,
    filled: filled,
    fillColor: filled ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
    border: OutlineInputBorder(borderRadius: _borderRadius),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: (_fieldHeight - 24) / 2),
    floatingLabelBehavior: FloatingLabelBehavior.auto,
  );

  void addProduct() {
    if (selectedPallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir palet seçin.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    if (selectedInvoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir irsaliye seçin.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    if (selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir ürün seçin.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    if (quantityController.text.isEmpty || int.tryParse(quantityController.text) == null || int.parse(quantityController.text) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir miktar girin.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final existingProductIndex = addedProducts.indexWhere((p) =>
    p['pallet'] == selectedPallet &&
        p['invoice'] == selectedInvoice &&
        p['product'] == selectedProduct);

    setState(() {
      if (existingProductIndex != -1) {
        addedProducts[existingProductIndex]['quantity'] =
            (addedProducts[existingProductIndex]['quantity'] as int) +
                int.parse(quantityController.text);
      } else {
        addedProducts.add({
          'pallet': selectedPallet,
          'invoice': selectedInvoice,
          'product': selectedProduct,
          'quantity': int.parse(quantityController.text),
        });
      }
      quantityController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedProduct} eklendi/güncellendi.'), backgroundColor: Colors.green),
    );
  }

  void _removeProduct(int index) {
    setState(() {
      final removedProduct = addedProducts.removeAt(index);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${removedProduct['product']} silindi.'), backgroundColor: Colors.redAccent),
      );
    });
  }


  Future<void> onConfirm() async {
    if (addedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilecek ürün bulunmuyor.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    bool? confirmSave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Onay'),
          content: Text('${addedProducts.length} kalem ürün palete kaydedilecek. Emin misiniz?'),
          actions: <Widget>[
            TextButton(
              child: const Text('İptal'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: const Text('Kaydet ve Onayla'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmSave == true) {
      setState(() => _loading = true);
      try {
        debugPrint('Palet: $selectedPallet');
        debugPrint('İrsaliye: $selectedInvoice');
        debugPrint('Ürünler: $addedProducts');

        await Future.delayed(const Duration(seconds: 1)); // Simulate save

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Palet başarıyla kaydedildi!'), backgroundColor: Colors.green),
        );
        setState(() {
          addedProducts.clear();
        });

      } catch (e) {
        debugPrint("Error saving data: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Veri kaydedilirken hata: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    }
  }
}

// ---------------------------- QR button widget -------------------------------
class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const _QrButton({required this.onTap, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: Icon(
              Icons.qr_code_scanner,
              size: size * 0.65,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

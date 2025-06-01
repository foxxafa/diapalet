// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/product_info.dart';
import '../../domain/entities/received_product_item.dart';
import '../../domain/repositories/goods_receiving_repository.dart';
import '../widgets/received_product_list_item_card.dart'; // Import the card widget

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late GoodsReceivingRepository _repository;
  bool _isRepoInitialized = false;
  bool _isLoading = false; // For general loading state
  bool _isFetchingProduct = false; // For barcode specific loading

  // Form Controllers & State
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _barcodeController = TextEditingController();
  ProductInfo? _currentProductInfo;
  DateTime? _expirationDate;
  final TextEditingController _trackingNumberController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  String? _selectedUnit;
  List<String> _availableUnits = [];

  // List of added products
  final List<ReceivedProductItem> _addedProducts = [];

  // UI Constants
  static const double _fieldHeight = 56;
  static const double _gap = 12;
  final _borderRadius = BorderRadius.circular(12);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
      _loadInitialData();
      _isRepoInitialized = true;
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _availableUnits = await _repository.getAvailableUnits();
      if (_availableUnits.isNotEmpty) {
        // _selectedUnit = _availableUnits.first; // Optionally pre-select
      }
    } catch (e) {
      _showErrorSnackBar("Birimler yüklenirken hata: ${e.toString()}");
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProductDetails() async {
    if (_barcodeController.text.isEmpty) {
      _showErrorSnackBar("Lütfen bir barkod girin.");
      return;
    }
    setState(() => _isFetchingProduct = true);
    try {
      final productInfo = await _repository.getProductDetailsByBarcode(_barcodeController.text);
      if (mounted) {
        setState(() {
          _currentProductInfo = productInfo;
          if (productInfo == null) {
            _showErrorSnackBar("Barkod bulunamadı: ${_barcodeController.text}");
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentProductInfo = null);
        _showErrorSnackBar("Ürün bilgisi alınırken hata: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingProduct = false);
      }
    }
  }

  void _generateTrackingNumber() {
    if (_expirationDate != null) {
      // Kural: Tarihin tersten yazımı (YYAAGG) -> Example: 06.03.2027 → 270306 (yyMMdd)
      _trackingNumberController.text = DateFormat('yyMMdd').format(_expirationDate!);
    } else {
      _trackingNumberController.clear();
    }
  }

  Future<void> _selectExpirationDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _expirationDate) {
      setState(() {
        _expirationDate = picked;
        _generateTrackingNumber();
      });
    }
  }

  void _addProductToList() {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar("Lütfen tüm zorunlu alanları doğru doldurun.");
      return;
    }
    if (_currentProductInfo == null) {
      _showErrorSnackBar("Lütfen geçerli bir ürün için barkod okutun.");
      return;
    }

    final newProduct = ReceivedProductItem(
      barcode: _barcodeController.text,
      productInfo: _currentProductInfo!,
      expirationDate: _expirationDate!,
      trackingNumber: _trackingNumberController.text,
      quantity: int.parse(_quantityController.text),
      unit: _selectedUnit!,
    );

    setState(() {
      _addedProducts.add(newProduct);
      _resetFormFields(); // Clear form for next entry
    });
    _showSuccessSnackBar("${newProduct.productInfo.name} listeye eklendi.");
  }

  void _resetFormFields() {
    _barcodeController.clear();
    _currentProductInfo = null;
    _expirationDate = null;
    _trackingNumberController.clear();
    _quantityController.clear();
    // _selectedUnit = _availableUnits.isNotEmpty ? _availableUnits.first : null; // Optionally reset unit
    // Keep unit selected or reset as per preference
    if (mounted) {
      _formKey.currentState?.reset(); // Resets validation state as well
      // Manually reset dropdown if not handled by form reset
      setState(() {
        _selectedUnit = null; // Or pre-select if desired
      });
    }
  }

  void _removeProductFromList(int index) {
    setState(() {
      final removedItem = _addedProducts.removeAt(index);
      _showSuccessSnackBar("${removedItem.productInfo.name} listeden silindi.", isError: true);
    });
  }

  Future<void> _saveAndConfirm() async {
    if (_addedProducts.isEmpty) {
      _showErrorSnackBar("Kaydedilecek ürün bulunmuyor.");
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Onay'),
          content: Text('${_addedProducts.length} kalem ürün sisteme kaydedilecek. Emin misiniz?'),
          actions: <Widget>[
            TextButton(
              child: const Text('İptal'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: const Text('Kaydet ve Onayla'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _repository.saveReceivedProducts(_addedProducts);
        if (mounted) {
          _showSuccessSnackBar("Ürünler başarıyla kaydedildi!");
          setState(() {
            _addedProducts.clear();
            _resetFormFields();
          });
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar("Kaydetme sırasında hata: ${e.toString()}");
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.orangeAccent : Colors.green),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool filled = false}) {
    return InputDecoration(
      labelText: label,
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: (_fieldHeight - 24) / 2),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomNavHeight = (screenHeight * 0.09).clamp(70.0, 90.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mal Kabul Ekranı'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _isLoading
          ? null // Hide if overall loading
          : Container(
        margin: const EdgeInsets.only(bottom: 8.0, left: 20.0, right: 20.0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _addedProducts.isEmpty || _isLoading ? null : _saveAndConfirm,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      body: SafeArea(
        child: _isLoading && _availableUnits.isEmpty // Show loader only if initial data isn't loaded
            ? const Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBarcodeSection(),
                const SizedBox(height: _gap),
                _buildProductInfoSection(),
                const SizedBox(height: _gap),
                _buildExpirationAndTrackingSection(),
                const SizedBox(height: _gap),
                _buildQuantityAndUnitSection(),
                const SizedBox(height: _gap),
                _buildAddButton(),
                const SizedBox(height: _gap + 4),
                _buildAddedProductsListTitle(),
                _buildAddedProductsList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarcodeSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _barcodeController,
            decoration: _inputDecoration(
              'Barkod Okut/Yaz',
              suffixIcon: _isFetchingProduct
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                icon: const Icon(Icons.search),
                onPressed: _fetchProductDetails,
                tooltip: 'Ürünü Bul',
              ),
            ),
            validator: (value) => value == null || value.isEmpty ? 'Barkod boş olamaz' : null,
            onFieldSubmitted: (_) => _fetchProductDetails(), // Fetch on submit
          ),
        ),
        const SizedBox(width: _gap / 2),
        SizedBox(
          width: _fieldHeight,
          height: _fieldHeight,
          child: ElevatedButton(
            onPressed: () { /* Placeholder for QR Scan Logic */
              _showSuccessSnackBar('QR Okuyucu açılacak (entegre edilecek).');
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.qr_code_scanner, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildProductInfoSection() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currentProductInfo != null ? _currentProductInfo!.name : 'Ürün Adı: -',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _currentProductInfo != null ? 'Stok Kodu: ${_currentProductInfo!.stockCode}' : 'Stok Kodu: -',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildExpirationAndTrackingSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            readOnly: true,
            onTap: () => _selectExpirationDate(context),
            decoration: _inputDecoration(
              _expirationDate != null ? DateFormat('dd.MM.yyyy').format(_expirationDate!) : 'Son Kullanma Tarihi',
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            validator: (value) => _expirationDate == null ? 'SKT seçin' : null,
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: TextFormField(
            controller: _trackingNumberController,
            readOnly: true,
            decoration: _inputDecoration('Takip Numarası (Oto)'),
            // No validator needed as it's auto-generated
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityAndUnitSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2, // Give more space to quantity
          child: TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('Miktar'),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Miktar girin';
              if (int.tryParse(value) == null || int.parse(value) <= 0) return 'Geçerli miktar';
              return null;
            },
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          flex: 3, // Give more space to unit dropdown
          child: DropdownButtonFormField<String>(
            decoration: _inputDecoration('Birim', filled: true),
            value: _selectedUnit,
            isExpanded: true,
            hint: const Text('Birim Seçin'),
            items: _availableUnits.map((String unit) {
              return DropdownMenuItem<String>(value: unit, child: Text(unit));
            }).toList(),
            onChanged: (String? newValue) {
              setState(() => _selectedUnit = newValue);
            },
            validator: (value) => value == null ? 'Birim seçin' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      height: _fieldHeight,
      child: ElevatedButton.icon(
        onPressed: _isLoading || _isFetchingProduct ? null : _addProductToList,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Listeye Ekle'),
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildAddedProductsListTitle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Text(
        'Eklenen Ürünler (${_addedProducts.length})',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAddedProductsList() {
    return Expanded(
      child: _addedProducts.isEmpty
          ? Center(
          child: Text(
            'Henüz listeye ürün eklenmedi.',
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade600),
          ))
          : ListView.builder(
        itemCount: _addedProducts.length,
        itemBuilder: (context, index) {
          final item = _addedProducts[index];
          return ReceivedProductListItemCard(
            item: item,
            onDelete: () => _removeProductFromList(index),
          );
        },
      ),
    );
  }
}


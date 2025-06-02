// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/product_info.dart';
import '../../domain/entities/received_product_item.dart';
import '../../domain/repositories/goods_receiving_repository.dart';
import '../widgets/received_product_list_item_card.dart';
import '../../../../core/widgets/qr_scanner_screen.dart'; // Import the scanner screen

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late GoodsReceivingRepository _repository;
  bool _isRepoInitialized = false;
  bool _isLoading = false;
  bool _isFetchingProduct = false;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _barcodeController = TextEditingController();
  ProductInfo? _currentProductInfo;
  DateTime? _expirationDate;
  final TextEditingController _trackingNumberController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  String? _selectedUnit;
  List<String> _availableUnits = [];

  final List<ReceivedProductItem> _addedProducts = [];

  static const double _fieldHeight = 56;
  static const double _gap = 12; // Form elemanları arası genel boşluk
  static const double _smallGap = 6; // Daha küçük boşluklar için
  final _borderRadius = BorderRadius.circular(12);
  late FocusNode _barcodeFocusNode; // Barkod alanı için FocusNode

  @override
  void initState() {
    super.initState();
    _barcodeFocusNode = FocusNode(); // FocusNode'u başlat
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
      _loadInitialData();
      _isRepoInitialized = true;
    }
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _trackingNumberController.dispose();
    _quantityController.dispose();
    _barcodeFocusNode.dispose(); // FocusNode'u dispose et
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _availableUnits = await _repository.getAvailableUnits();
      if (_availableUnits.isNotEmpty && _selectedUnit == null) {
        // Otomatik birim seçimi istenirse burada yapılabilir
        // _selectedUnit = _availableUnits.first;
      }
    } catch (e) {
      _showErrorSnackBar("Birimler yüklenirken hata: ${e.toString()}");
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProductDetails({String? barcodeValue}) async {
    final String barcodeToFetch = barcodeValue ?? _barcodeController.text;
    if (barcodeToFetch.isEmpty) {
      _showErrorSnackBar("Lütfen bir barkod girin veya taratın.");
      return;
    }
    if (barcodeValue != null && _barcodeController.text != barcodeValue) {
      _barcodeController.text = barcodeValue;
    }

    FocusScope.of(context).unfocus(); // Genel odağı kaldır
    setState(() => _isFetchingProduct = true);
    try {
      final productInfo = await _repository.getProductDetailsByBarcode(barcodeToFetch);
      if (mounted) {
        setState(() {
          _currentProductInfo = productInfo;
          if (productInfo == null) {
            _showErrorSnackBar("Barkod bulunamadı: $barcodeToFetch");
          }
          // Ürün bulunduktan sonra SKT alanına odaklanılabilir veya miktar alanına.
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

  Future<void> _scanBarcode() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      await _fetchProductDetails(barcodeValue: result);
    }
  }

  void _generateTrackingNumber() {
    if (_expirationDate != null) {
      _trackingNumberController.text = DateFormat('yyMMdd').format(_expirationDate!);
    } else {
      _trackingNumberController.clear();
    }
  }

  Future<void> _selectExpirationDate(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)), // Son 5 yıl
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)), // Gelecek 10 yıl
      helpText: 'SON KULLANMA TARİHİ',
      confirmText: 'TAMAM',
      cancelText: 'İPTAL',
    );
    if (picked != null && picked != _expirationDate) {
      setState(() {
        _expirationDate = picked;
        _generateTrackingNumber();
      });
    }
  }

  void _addProductToList() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar("Lütfen tüm zorunlu alanları doğru doldurun.");
      return;
    }
    if (_currentProductInfo == null || _currentProductInfo == ProductInfo.empty) {
      _showErrorSnackBar("Lütfen geçerli bir ürün için barkod okutun.");
      return;
    }
    if (_expirationDate == null) {
      _showErrorSnackBar("Lütfen son kullanma tarihi seçin.");
      return;
    }
    if (_selectedUnit == null) {
      _showErrorSnackBar("Lütfen birim seçin.");
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
      _addedProducts.insert(0, newProduct);
      _resetFormFields();
    });
    _showSuccessSnackBar("${newProduct.productInfo.name} listeye eklendi.");
  }

  void _resetFormFields() {
    _formKey.currentState?.reset(); // Formun kendi reset metodu çağrılabilir.
    _barcodeController.clear();
    _currentProductInfo = null;
    _expirationDate = null;
    _trackingNumberController.clear();
    _quantityController.clear();

    if (mounted) {
      setState(() {
        _selectedUnit = null; // Dropdown'ı sıfırla
      });
      // Barkod alanına tekrar odaklan
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _barcodeFocusNode.canRequestFocus) {
          FocusScope.of(context).requestFocus(_barcodeFocusNode);
        }
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
    FocusScope.of(context).unfocus();
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
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.orangeAccent : Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool filled = false}) {
    final textTheme = Theme.of(context).textTheme;
    final double baseFontSize = textTheme.titleMedium?.fontSize ?? 16.0;
    final double verticalPadding = (_fieldHeight - (baseFontSize * 1.2)) / 2;

    return InputDecoration(
      labelText: label,
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalPadding > 0 ? verticalPadding : 16),
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
          ? null
          : Container(
        margin: const EdgeInsets.only(bottom: 8.0, left: 20.0, right: 20.0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _addedProducts.isEmpty || _isLoading || _isFetchingProduct ? null : _saveAndConfirm,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      body: Builder( // Wrap the body's content with a Builder
        builder: (BuildContext scaffoldContext) { // This context is under the Scaffold
          // Use scaffoldContext to get appBarMaxHeight.
          // kToolbarHeight is a standard AppBar height, used as part of a fallback.
          final double appBarMaxHeight = Scaffold.of(scaffoldContext).appBarMaxHeight ??
              (kToolbarHeight + MediaQuery.of(scaffoldContext).padding.top);

          // Calculate the available height for the SizedBox.
          // This formula subtracts:
          // 1. appBarMaxHeight (which includes AppBar's own height + status bar height).
          // 2. bottomNavHeight.
          // 3. System bottom inset (like Android navigation bar).
          // 4. Vertical padding of the main Padding widget (16 top + 16 bottom = 32).
          final double calculatedHeight = screenHeight -
              appBarMaxHeight -
              bottomNavHeight -
              MediaQuery.of(context).padding.bottom - // System bottom inset (can use outer context)
              32; // Vertical padding from Padding widget

          return SafeArea(
            child: _isLoading && _availableUnits.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: SizedBox(
                    height: calculatedHeight < 0 ? 0 : calculatedHeight, // Ensure height is not negative
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBarcodeSection(),
                        const SizedBox(height: _smallGap),
                        _buildProductInfoSection(),
                        const SizedBox(height: _gap),
                        _buildExpirationAndTrackingSection(),
                        const SizedBox(height: _gap),
                        _buildQuantityAndUnitSection(),
                        const SizedBox(height: _gap),
                        _buildAddButton(),
                        const SizedBox(height: _smallGap),
                        Expanded(
                          child: _buildAddedProductsSection(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBarcodeSection() {
    return SizedBox(
      height: _fieldHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextFormField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              decoration: _inputDecoration(
                'Barkod Okut/Yaz',
                suffixIcon: _isFetchingProduct
                    ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _fetchProductDetails(),
                  tooltip: 'Ürünü Bul',
                ),
              ),
              validator: (value) => value == null || value.isEmpty ? 'Barkod boş olamaz' : null,
              onFieldSubmitted: (_) => _fetchProductDetails(),
            ),
          ),
          const SizedBox(width: _gap / 2),
          SizedBox(
            width: _fieldHeight,
            height: _fieldHeight,
            child: ElevatedButton(
              onPressed: _scanBarcode,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: _borderRadius),
                padding: EdgeInsets.zero,
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              child: const Icon(Icons.qr_code_scanner, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      alignment: Alignment.centerLeft,
      child: _isFetchingProduct
          ? const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: SizedBox(width:20, height:20, child: CircularProgressIndicator(strokeWidth: 2.5)),
      ))
          : (_currentProductInfo == null || _currentProductInfo == ProductInfo.empty)
          ? Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Text('Barkod okutulduğunda ürün bilgileri burada görünecektir.', style: TextStyle(color: Theme.of(context).hintColor)),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentProductInfo!.name.isNotEmpty ? _currentProductInfo!.name : "Ürün Adı: Bulunamadı",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _currentProductInfo!.stockCode.isNotEmpty ? 'Stok Kodu: ${_currentProductInfo!.stockCode}' : 'Stok Kodu: -',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildExpirationAndTrackingSection() {
    return SizedBox(
      height: _fieldHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityAndUnitSection() {
    return SizedBox(
      height: _fieldHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
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
            flex: 3,
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
      ),
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

  Widget _buildAddedProductsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Eklenen Ürünler (${_addedProducts.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: _addedProducts.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Henüz listeye ürün eklenmedi.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.only(top: _smallGap, bottom: _smallGap),
              itemCount: _addedProducts.length,
              itemBuilder: (context, index) {
                final item = _addedProducts[index];
                return ReceivedProductListItemCard(
                  item: item,
                  onDelete: () => _removeProductFromList(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter

import '../../domain/entities/product_info.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/repositories/goods_receiving_repository.dart';
import '../../../../core/widgets/qr_scanner_screen.dart';

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late GoodsReceivingRepository _repository;
  bool _isRepoInitialized = false;
  bool _isLoading = true;
  bool _isSaving = false;

  final _formKey = GlobalKey<FormState>(); // For validating inputs before adding to list

  ReceiveMode _selectedMode = ReceiveMode.palet;

  List<String> _availableInvoices = [];
  String? _selectedInvoice;
  final TextEditingController _invoiceController = TextEditingController();

  List<String> _availablePallets = [];
  List<String> _availableBoxes = [];
  String? _selectedPalletOrBoxId;
  final TextEditingController _palletOrBoxController = TextEditingController();

  List<ProductInfo> _availableProducts = [];
  ProductInfo? _selectedProduct;
  final TextEditingController _productController = TextEditingController();

  final TextEditingController _quantityController = TextEditingController();
  final List<GoodsReceiptItem> _addedItems = [];

  static const double _fieldHeight = 56;
  static const double _gap = 12;
  static const double _smallGap = 8;
  final _borderRadius = BorderRadius.circular(12);

  @override
  void initState() {
    super.initState();
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
    _quantityController.dispose();
    _invoiceController.dispose();
    _palletOrBoxController.dispose();
    _productController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getInvoices(),
        _repository.getPalletsForDropdown(),
        _repository.getBoxesForDropdown(),
        _repository.getProductsForDropdown(),
      ]);
      if (!mounted) return;

      setState(() {
        _availableInvoices = List<String>.from(results[0]);
        _availablePallets = List<String>.from(results[1]);
        _availableBoxes = List<String>.from(results[2]);
        _availableProducts = List<ProductInfo>.from(results[3]);
        _updatePalletOrBoxOptions(setDefault: false);
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar("Başlangıç verileri yüklenirken hata: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updatePalletOrBoxOptions({bool setDefault = false}) {
    setState(() {
      final currentOptions = _selectedMode == ReceiveMode.palet ? _availablePallets : _availableBoxes;
      if (setDefault && currentOptions.isNotEmpty) {
        // Default selection logic can be re-enabled if needed
        // _selectedPalletOrBoxId = currentOptions.first;
        // _palletOrBoxController.text = _selectedPalletOrBoxId ?? "";
      } else if (!currentOptions.contains(_selectedPalletOrBoxId)) {
        _selectedPalletOrBoxId = null;
        _palletOrBoxController.clear();
      }
    });
  }

  void _resetInputFields({bool resetAll = false}) {
    _productController.clear();
    _quantityController.clear();
    _selectedProduct = null;

    if (mounted) {
      setState(() {
        if (resetAll) {
          _selectedInvoice = null;
          _invoiceController.clear();
          _selectedMode = ReceiveMode.palet;
          _selectedPalletOrBoxId = null;
          _palletOrBoxController.clear();
          _updatePalletOrBoxOptions(setDefault: false);
          _addedItems.clear();
          _formKey.currentState?.reset();
        }
      });
    }
  }

  void _addItemToList() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar("Lütfen ürün eklemek için tüm zorunlu alanları (Palet/Kutu, Ürün, Miktar) doğru doldurun.");
      return;
    }

    // Additional checks for selected objects after form validation passes
    if (_selectedPalletOrBoxId == null || _selectedPalletOrBoxId!.isEmpty) {
      _showErrorSnackBar("Lütfen geçerli bir Palet/Kutu seçin veya okutun.");
      return;
    }
    if (_selectedProduct == null) {
      _showErrorSnackBar("Lütfen geçerli bir Ürün seçin veya okutun.");
      return;
    }

    final quantity = int.tryParse(_quantityController.text);
    // The form validator for quantity already ensures it's a positive number.
    // This is an additional safeguard, though unlikely to be null if form validation passed.
    if (quantity == null) {
      _showErrorSnackBar("Miktar geçersiz.");
      return;
    }

    final newItem = GoodsReceiptItem(
      goodsReceiptId: -1,
      palletOrBoxId: _selectedPalletOrBoxId!, // Safe due to check above
      product: _selectedProduct!,           // Safe due to check above
      quantity: quantity,
    );
    if (mounted) {
      setState(() {
        _addedItems.insert(0, newItem);
        _selectedProduct = null;
        _productController.clear();
        _quantityController.clear();
      });
      _showSuccessSnackBar("${newItem.product.name} listeye eklendi.");
    }
  }

  void _removeItemFromList(int index) {
    if (mounted) {
      setState(() {
        final removedItem = _addedItems.removeAt(index);
        _showSuccessSnackBar("${removedItem.product.name} listeden silindi.", isError: true);
      });
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (_addedItems.isEmpty) {
      _showErrorSnackBar("Kaydedilecek ürün bulunmuyor.");
      return;
    }

    if (_selectedInvoice == null || _selectedInvoice!.isEmpty) {
      _showErrorSnackBar("Lütfen bir irsaliye seçin.");
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Onay'),
          content: Text('${_addedItems.length} kalem ürün sisteme kaydedilecek. Emin misiniz?'),
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
      if (!mounted) return;
      setState(() => _isSaving = true);
      try {
        final header = GoodsReceipt(
          invoiceNumber: _selectedInvoice!,
          receiptDate: DateTime.now(),
          mode: _selectedMode,
        );
        await _repository.saveGoodsReceipt(header, _addedItems);
        if (mounted) {
          _showSuccessSnackBar("Ürünler başarıyla kaydedildi!");
          _resetInputFields(resetAll: true);
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar("Kaydetme sırasında hata: ${e.toString()}");
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  Future<void> _scanQrAndUpdateSelection(String fieldType) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      String successMessage = "";
      bool found = false;
      setState(() {
        if (fieldType == 'palletOrBox') {
          final currentOptions = _selectedMode == ReceiveMode.palet ? _availablePallets : _availableBoxes;
          if (currentOptions.contains(result)) {
            _selectedPalletOrBoxId = result;
            _palletOrBoxController.text = result;
            successMessage = "${_selectedMode.displayName} QR ile seçildi: $result";
            found = true;
          } else {
            _showErrorSnackBar("Taranan QR ($result) geçerli bir ${_selectedMode.displayName} seçeneği değil.");
            // Clear previous selection if invalid QR is scanned
            _selectedPalletOrBoxId = null;
            _palletOrBoxController.clear();
          }
        } else if (fieldType == 'product') {
          final matchedProduct = _availableProducts.firstWhere(
                (p) => p.id == result || p.stockCode == result || p.name.toLowerCase() == result.toLowerCase(),
            orElse: () => ProductInfo.empty,
          );
          if (matchedProduct != ProductInfo.empty) {
            _selectedProduct = matchedProduct;
            _productController.text = "${matchedProduct.name} (${matchedProduct.stockCode})";
            successMessage = "Ürün QR ile seçildi: ${matchedProduct.name}";
            found = true;
          } else {
            _showErrorSnackBar("Taranan QR ($result) geçerli bir ürün seçeneği değil.");
            // Clear previous selection if invalid QR is scanned
            _selectedProduct = null;
            _productController.clear();
          }
        }
      });
      if (found && mounted && successMessage.isNotEmpty) {
        _showSuccessSnackBar(successMessage);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
      ),
    );
  }

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.orangeAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {bool filled = false, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: (_fieldHeight - 24) / 2),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(fontSize: 0, height: 0.01),
      helperText: ' ',
      helperStyle: const TextStyle(fontSize: 0, height: 0.01),
    );
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
    T? initialValue,
  }) async {
    return showDialog<T>(
      context: context,
      builder: (BuildContext dialogContext) {
        String searchText = '';
        List<T> filteredItems = List.from(items);
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            if (searchText.isNotEmpty) {
              filteredItems = items.where((item) => filterCondition(item, searchText)).toList();
            } else {
              filteredItems = List.from(items);
            }
            return AlertDialog(
              title: Text(title),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Ara...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: _borderRadius),
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          searchText = value;
                        });
                      },
                    ),
                    const SizedBox(height: _gap),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? const Center(child: Text("Sonuç bulunamadı"))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        itemBuilder: (BuildContext context, int index) {
                          final item = filteredItems[index];
                          return ListTile(
                            title: Text(itemToString(item)),
                            onTap: () {
                              Navigator.of(dialogContext).pop(item);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('İptal'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomNavHeight = (screenHeight * 0.09).clamp(70.0, 90.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mal Kabul'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _isLoading || _isSaving
          ? null
          : Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _addedItems.isEmpty ? null : _onConfirmSave,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeSelector(),
                const SizedBox(height: _gap),
                _buildSearchableInvoiceDropdown(),
                const SizedBox(height: _gap),
                _buildSearchablePalletOrBoxInputRow(),
                const SizedBox(height: _gap),
                _buildSearchableProductInputRow(),
                const SizedBox(height: _gap),
                _buildQuantityInput(),
                const SizedBox(height: _gap),
                _buildAddToListButton(),
                const SizedBox(height: _smallGap + 4),
                Expanded(child: _buildAddedItemsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<ReceiveMode>(
        segments: const [
          ButtonSegment(value: ReceiveMode.palet, label: Text('Palet'), icon: Icon(Icons.pallet)),
          ButtonSegment(value: ReceiveMode.kutu, label: Text('Kutu'), icon: Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<ReceiveMode> newSelection) {
          if (mounted && newSelection.first != _selectedMode) {
            setState(() {
              _selectedMode = newSelection.first;
              _updatePalletOrBoxOptions();
              _selectedPalletOrBoxId = null;
              _palletOrBoxController.clear();
              // Switching between Palet and Kutu should start with an empty list
              // to avoid mixing items of different modes.
              _addedItems.clear();
              _formKey.currentState?.reset();
            });
            _showSuccessSnackBar(
                "${_selectedMode.displayName} moduna geçildi. Liste temizlendi.");
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildSearchableInvoiceDropdown() {
    return SizedBox(
      child: TextFormField(
        controller: _invoiceController,
        readOnly: true,
        decoration: _inputDecoration('İrsaliye Seç', filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
        onTap: () async {
          final String? selected = await _showSearchableDropdownDialog<String>(
            context: context,
            title: 'İrsaliye Seç',
            items: _availableInvoices,
            itemToString: (item) => item,
            filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
            initialValue: _selectedInvoice,
          );
          if (selected != null) {
            setState(() {
              _selectedInvoice = selected;
              _invoiceController.text = selected;
            });
          }
        },
        validator: (value) => (value == null || value.isEmpty) ? 'Lütfen bir irsaliye seçin.' : null,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  Widget _buildSearchablePalletOrBoxInputRow() {
    final label = _selectedMode == ReceiveMode.palet ? 'Palet Seç' : 'Kutu Seç';
    final currentOptions = _selectedMode == ReceiveMode.palet ? _availablePallets : _availableBoxes;

    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _palletOrBoxController,
              readOnly: true,
              decoration: _inputDecoration(label, filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
              onTap: () async {
                final String? selected = await _showSearchableDropdownDialog<String>(
                  context: context,
                  title: label,
                  items: currentOptions,
                  itemToString: (item) => item,
                  filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                  initialValue: _selectedPalletOrBoxId,
                );
                if (selected != null) {
                  setState(() {
                    _selectedPalletOrBoxId = selected;
                    _palletOrBoxController.text = selected;
                  });
                }
              },
              validator: (value) => (value == null || value.isEmpty) ? 'Lütfen bir $label.' : null,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () => _scanQrAndUpdateSelection('palletOrBox'),
            size: _fieldHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchableProductInputRow() {
    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _productController,
              readOnly: true,
              decoration: _inputDecoration('Ürün Seç', filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
              onTap: () async {
                final ProductInfo? selected = await _showSearchableDropdownDialog<ProductInfo>(
                  context: context,
                  title: 'Ürün Seç',
                  items: _availableProducts,
                  itemToString: (product) => "${product.name} (${product.stockCode})",
                  filterCondition: (product, query) =>
                  product.name.toLowerCase().contains(query.toLowerCase()) ||
                      product.stockCode.toLowerCase().contains(query.toLowerCase()),
                  initialValue: _selectedProduct,
                );
                if (selected != null) {
                  setState(() {
                    _selectedProduct = selected;
                    _productController.text = "${selected.name} (${selected.stockCode})";
                  });
                }
              },
              validator: (value) => (value == null || value.isEmpty) ? 'Lütfen bir ürün seçin.' : null,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () => _scanQrAndUpdateSelection('product'),
            size: _fieldHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityInput() {
    return SizedBox(
      child: TextFormField(
        controller: _quantityController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _inputDecoration('Miktar Girin'),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Miktar girin.';
          final number = int.tryParse(value);
          if (number == null) return 'Lütfen sayı girin.';
          if (number <= 0) return 'Miktar 0\'dan büyük olmalı.';
          return null;
        },
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  Widget _buildAddToListButton() {
    return SizedBox(
      height: _fieldHeight,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _addItemToList,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Listeye Ekle'),
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildAddedItemsList() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Eklenen Kalemler (${_addedItems.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: _addedItems.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Henüz listeye kalem eklenmedi veya liste temizlendi.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: _smallGap, horizontal: _smallGap / 2),
              itemCount: _addedItems.length,
              itemBuilder: (context, index) {
                final item = _addedItems[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: _smallGap / 2),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    title: Text("${item.product.name} (${item.product.stockCode})", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        '${_selectedMode.displayName}: ${item.palletOrBoxId}\nİrsaliye: ${_selectedInvoice ?? 'Belirtilmedi'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${item.quantity} Adet', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(width: _smallGap),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.redAccent[700]),
                          onPressed: () => _removeItemFromList(index),
                          tooltip: 'Bu Kalemi Sil',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const _QrButton({required this.onTap, required this.size, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }
}


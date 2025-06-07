// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter
import 'package:easy_localization/easy_localization.dart';

import '../../domain/entities/product_info.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/repositories/goods_receiving_repository.dart';
import '../../../../core/widgets/qr_scanner_screen.dart';

// Palet ve Kutu modları için enum tanımı
enum ReceivingMode { palet, kutu }

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  // Sabit lokasyon kuralı: Fiziksel olarak tüm ürünler bu lokasyona girer.
  static const String _defaultLocation = "MAL KABUL";

  late GoodsReceivingRepository _repository;
  bool _isRepoInitialized = false;
  bool _isLoading = true;
  bool _isSaving = false;

  final _formKey = GlobalKey<FormState>();

  // Yeni state: Palet/Kutu modu
  ReceivingMode _selectedMode = ReceivingMode.palet;

  List<String> _availableInvoices = [];
  String? _selectedInvoice;
  final TextEditingController _invoiceController = TextEditingController();

  // Palet ID'si için controller
  final TextEditingController _palletIdController = TextEditingController();

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
    _productController.dispose();
    _palletIdController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getInvoices(),
        _repository.getProductsForDropdown(),
      ]);
      if (!mounted) return;

      setState(() {
        _availableInvoices = List<String>.from(results[0]);
        _availableProducts = List<ProductInfo>.from(results[1]);
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
            tr('goods_receiving.errors.load_initial', namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  void _resetInputFields({bool resetAll = false}) {
    _productController.clear();
    _quantityController.clear();
    _selectedProduct = null;
    if(_selectedMode == ReceivingMode.palet) {
      _palletIdController.clear();
    }


    if (mounted) {
      setState(() {
        if (resetAll) {
          _selectedInvoice = null;
          _invoiceController.clear();
          _addedItems.clear();
          _formKey.currentState?.reset();
        }
      });
    }
  }

  Future<void> _addItemToList() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      _showErrorSnackBar(tr('goods_receiving.errors.required_fields'));
      return;
    }

    if (_selectedProduct == null) {
      _showErrorSnackBar(tr('goods_receiving.errors.invalid_product'));
      return;
    }

    final quantity = int.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      _showErrorSnackBar(tr('goods_receiving.errors.invalid_qty'));
      return;
    }

    // Tüm konteynerler varsayılan fiziksel lokasyonda başlar.
    const String itemLocation = _defaultLocation;

    // Kutu modunda sadece tek çeşit ürün eklenmesine izin ver.
    if (_selectedMode == ReceivingMode.kutu && _addedItems.isNotEmpty) {
      _showErrorSnackBar("Kutu modunda sadece tek çeşit ürün ekleyebilirsiniz.");
      return;
    }

    final newItem = GoodsReceiptItem(
      goodsReceiptId: -1,
      product: _selectedProduct!,
      quantity: quantity,
      location: itemLocation,
      containerId: _selectedMode == ReceivingMode.palet ? _palletIdController.text : null,
    );

    if (mounted) {
      setState(() {
        _addedItems.insert(0, newItem);
        _selectedProduct = null;
        _productController.clear();
        _quantityController.clear();
      });
      _showSuccessSnackBar(tr('goods_receiving.success.item_added', namedArgs: {'product': newItem.product.name}));
    }
  }

  void _removeItemFromList(int index) {
    if (mounted) {
      setState(() {
        final removedItem = _addedItems.removeAt(index);
        _showSuccessSnackBar(tr('goods_receiving.success.item_removed', namedArgs: {'product': removedItem.product.name}), isError: true);
      });
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (_addedItems.isEmpty) {
      _showErrorSnackBar(tr('goods_receiving.errors.no_items'));
      return;
    }

    if (_selectedInvoice == null || _selectedInvoice!.isEmpty) {
      _showErrorSnackBar(tr('goods_receiving.errors.select_invoice'));
      return;
    }

    if (_selectedMode == ReceivingMode.palet && _palletIdController.text.isEmpty) {
      _showErrorSnackBar("Lütfen bir palet barkodu girin veya okutun.");
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('goods_receiving.confirm_title'.tr()),
          content: Text('goods_receiving.confirm_message'.tr(namedArgs: {'count': _addedItems.length.toString()})),
          actions: <Widget>[
            TextButton(
              child: Text('common.cancel'.tr()),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: Text('goods_receiving.save_and_confirm'.tr()),
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
        );
        await _repository.saveGoodsReceipt(header, _addedItems);
        if (mounted) {
          _showSuccessSnackBar(tr('goods_receiving.success.saved'));
          _resetInputFields(resetAll: true);
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar(tr('goods_receiving.errors.save_error', namedArgs: {'error': e.toString()}));
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
    if (result == null || result.isEmpty || !mounted) return;

    switch (fieldType) {
      case 'pallet':
        setState(() {
          _palletIdController.text = result;
        });
        _showSuccessSnackBar("Palet barkodu okundu: $result");
        break;
      case 'product':
        final matchedProduct = _availableProducts.firstWhere(
              (p) => p.id == result || p.stockCode == result || p.name.toLowerCase() == result.toLowerCase(),
          orElse: () => ProductInfo.empty,
        );
        if (matchedProduct != ProductInfo.empty) {
          setState(() {
            _selectedProduct = matchedProduct;
            _productController.text = "${matchedProduct.name} (${matchedProduct.stockCode})";
          });
          _showSuccessSnackBar(tr('goods_receiving.success.item_added', namedArgs: {'product': matchedProduct.name}));
        } else {
          _showErrorSnackBar(tr('goods_receiving.errors.invalid_qr_product', namedArgs: {'qr': result}));
        }
        break;
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

  InputDecoration _inputDecoration(String label, {bool filled = false, Widget? suffixIcon, bool enabled = true}) {
    return InputDecoration(
      labelText: label,
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()) : null,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabled: enabled,
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
                        hintText: tr('goods_receiving.search_hint'),
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
                          ? Center(child: Text('goods_receiving.search_no_result'.tr()))
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
                  child: Text('common.cancel'.tr()),
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
    final bool isKutuModeLocked = _selectedMode == ReceivingMode.kutu && _addedItems.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('goods_receiving.title'.tr()),
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
          label: Text('goods_receiving.save_and_confirm'.tr()),
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
                if (_selectedMode == ReceivingMode.palet) ...[
                  const SizedBox(height: _gap),
                  _buildPalletIdInput(),
                ],
                const SizedBox(height: _gap),
                _buildSearchableProductInputRow(isLocked: isKutuModeLocked),
                const SizedBox(height: _gap),
                _buildQuantityInput(isLocked: isKutuModeLocked),
                const SizedBox(height: _gap),
                _buildAddToListButton(isLocked: isKutuModeLocked),
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
      child: SegmentedButton<ReceivingMode>(
        segments: const [
          ButtonSegment(
              value: ReceivingMode.palet,
              label: Text('Palet'), // L10n key: 'goods_receiving.modes.pallet'
              icon: Icon(Icons.pallet)),
          ButtonSegment(
              value: ReceivingMode.kutu,
              label: Text('Kutu'), // L10n key: 'goods_receiving.modes.box'
              icon: Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<ReceivingMode> newSelection) {
          if (mounted) {
            setState(() {
              _selectedMode = newSelection.first;
              // Mod değiştiğinde listeyi ve giriş alanlarını temizle
              _addedItems.clear();
              _resetInputFields();
            });
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
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
        decoration: _inputDecoration('goods_receiving.select_invoice'.tr(), filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
        onTap: () async {
          final String? selected = await _showSearchableDropdownDialog<String>(
            context: context,
            title: 'goods_receiving.select_invoice'.tr(),
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
        validator: (value) => (value == null || value.isEmpty) ? 'goods_receiving.errors.select_invoice'.tr() : null,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  Widget _buildPalletIdInput() {
    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _palletIdController,
              decoration: _inputDecoration('Palet Barkodu Girin/Okutun', filled: false),
              validator: (value) {
                if (_selectedMode == ReceivingMode.palet && (value == null || value.isEmpty)) {
                  return "Palet barkodu zorunludur.";
                }
                return null;
              },
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () => _scanQrAndUpdateSelection('pallet'),
            size: _fieldHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchableProductInputRow({required bool isLocked}) {
    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _productController,
              readOnly: true,
              enabled: !isLocked,
              decoration: _inputDecoration('goods_receiving.select_product'.tr(), filled: true, suffixIcon: const Icon(Icons.arrow_drop_down), enabled: !isLocked),
              onTap: isLocked ? null : () async {
                final ProductInfo? selected = await _showSearchableDropdownDialog<ProductInfo>(
                  context: context,
                  title: 'goods_receiving.select_product'.tr(),
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
              validator: (value) {
                if(isLocked) return null;
                return (value == null || value.isEmpty) ? tr('goods_receiving.errors.invalid_product') : null;
              },
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: isLocked ? (){} : () => _scanQrAndUpdateSelection('product'),
            size: _fieldHeight,
            isEnabled: !isLocked,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityInput({required bool isLocked}) {
    return SizedBox(
      child: TextFormField(
        controller: _quantityController,
        keyboardType: TextInputType.number,
        enabled: !isLocked,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _inputDecoration('goods_receiving.enter_qty'.tr(), enabled: !isLocked),
        validator: (value) {
          if (isLocked) return null; // Do not validate if locked
          if (value == null || value.isEmpty) return tr('goods_receiving.enter_qty');
          final number = int.tryParse(value);
          if (number == null) return tr('goods_receiving.errors.invalid_qty');
          if (number <= 0) return tr('goods_receiving.errors.invalid_qty');
          return null;
        },
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  Widget _buildAddToListButton({required bool isLocked}) {
    return SizedBox(
      height: _fieldHeight,
      child: ElevatedButton.icon(
        onPressed: isLocked || _isSaving ? null : _addItemToList,
        icon: const Icon(Icons.add_circle_outline),
        label: Text('goods_receiving.add_to_list'.tr()),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.5).round()),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha((255 * 0.7).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              tr('goods_receiving.items_added', namedArgs: {'count': _addedItems.length.toString()}),
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
                  'goods_receiving.no_items'.tr(),
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
                final bool isPalletItem = item.containerId != null;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: _smallGap / 2),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    title: Text("${item.product.name} (${item.product.stockCode})", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("İrsaliye: ${_selectedInvoice ?? 'N/A'}"),
                        Text("Konum: ${item.location}"),
                        if (isPalletItem)
                          Text("Palet: ${item.containerId}"),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('goods_receiving.qty_unit', namedArgs: {'qty': item.quantity.toString()}), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(width: _smallGap),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.redAccent[700]),
                          onPressed: () => _removeItemFromList(index),
                          tooltip: 'goods_receiving.delete_item'.tr(),
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
  final bool isEnabled;

  const _QrButton({required this.onTap, required this.size, this.isEnabled = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: isEnabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.grey.shade300;
              }
              return Theme.of(context).colorScheme.secondaryContainer;
            },
          ),
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }
}

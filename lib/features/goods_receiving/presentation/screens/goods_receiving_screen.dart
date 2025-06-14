// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:collection/collection.dart';

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  // --- Sabitler ve Stil Değişkenleri ---
  static const double _gap = 12;
  static const double _smallGap = 8;
  final _borderRadius = BorderRadius.circular(12);

  // --- State ve Controller'lar ---
  late final GoodsReceivingRepository _repository;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;

  ReceivingMode _receivingMode = ReceivingMode.palet;
  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<ProductInfo> _availableProducts = [];
  ProductInfo? _selectedProduct;
  List<ReceiptItemDraft> _addedItems = [];

  final _orderController = TextEditingController();
  final _palletIdController = TextEditingController();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();

  final _orderFocusNode = FocusNode();
  final _palletIdFocusNode = FocusNode();
  final _productFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadInitialData();
  }

  @override
  void dispose() {
    _orderController.dispose();
    _palletIdController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    _orderFocusNode.dispose();
    _palletIdFocusNode.dispose();
    _productFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  // --- VERİ YÜKLEME ---
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getOpenPurchaseOrders(),
        _repository.searchProducts(''),
      ]);
      if (!mounted) return;

      setState(() {
        _purchaseOrders = results[0] as List<PurchaseOrder>;
        _availableProducts = results[1] as List<ProductInfo>;
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _orderFocusNode.requestFocus());
    } catch (e) {
      if (mounted) _showErrorSnackBar('Başlangıç verileri yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- BARKOD/ÜRÜN İŞLEME ---
  void _processScannedProduct(String scannedData) {
    if (scannedData.isEmpty) return;
    final foundProduct = _availableProducts.firstWhereOrNull(
          (p) =>
      p.stockCode.toLowerCase() == scannedData.toLowerCase() ||
          (p.barcode1?.toLowerCase() == scannedData.toLowerCase()),
    );

    if (foundProduct != null) {
      _selectProduct(foundProduct);
    } else {
      _productController.clear();
      _selectedProduct = null;
      _showErrorSnackBar("Ürün bulunamadı: $scannedData");
    }
  }

  void _selectProduct(ProductInfo product) {
    setState(() {
      _selectedProduct = product;
      _productController.text = "${product.name} (${product.stockCode})";
    });
    // Ürün seçildiğinde veya okutulduğunda miktar alanına odaklan
    _quantityFocusNode.requestFocus();
  }

  // --- LİSTE VE KAYDETME İŞLEMLERİ ---
  void _addItemToList() {
    // Manuel doğrulama
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final quantity = double.tryParse(_quantityController.text);
    if (_selectedProduct == null || quantity == null || quantity <= 0) {
      _showErrorSnackBar("Lütfen ürün seçin ve geçerli bir miktar girin.");
      return;
    }

    final isKutuModeLocked =
        _receivingMode == ReceivingMode.kutu && _addedItems.isNotEmpty;
    if (isKutuModeLocked) {
      _showErrorSnackBar("Kutu modunda sadece tek çeşit ürün ekleyebilirsiniz.");
      return;
    }

    final String addedProductName = _selectedProduct!.name;

    // DEĞİŞİKLİK: Formu sıfırlamadan önce sipariş bilgilerini kaydet
    final PurchaseOrder? savedOrder = _selectedOrder;
    final String savedOrderText = _orderController.text;

    setState(() {
      _addedItems.insert(
          0,
          ReceiptItemDraft(
            product: _selectedProduct!,
            quantity: quantity,
            palletBarcode: _receivingMode == ReceivingMode.palet
                ? _palletIdController.text
                : null,
          ));

      // DEĞİŞİKLİK: Formun durumunu (hata mesajları dahil) sıfırla
      _formKey.currentState?.reset();
      _clearEntryFields();

      // DEĞİŞİKLİK: Kaydedilen sipariş bilgilerini geri yükle
      _selectedOrder = savedOrder;
      _orderController.text = savedOrderText;
    });

    _showSuccessSnackBar("$addedProductName listeye eklendi.");
    // Ürün eklendikten sonra bir sonraki ürün için odaklan
    _productFocusNode.requestFocus();
  }

  void _removeItemFromList(int index) {
    if (!mounted) return;
    final removedItemName = _addedItems[index].product.name;
    setState(() => _addedItems.removeAt(index));
    _showSuccessSnackBar("$removedItemName listeden kaldırıldı.", isError: true);
  }

  Future<void> _saveAndConfirm() async {
    if (_addedItems.isEmpty) {
      _showErrorSnackBar("Kaydetmek için listeye en az bir ürün eklemelisiniz.");
      return;
    }
    if (_selectedOrder == null) {
      _showErrorSnackBar("Lütfen bir sipariş seçin.");
      return;
    }

    final bool? confirmed = await _showConfirmationListDialog();

    if (confirmed != true) return;
    setState(() => _isSaving = true);

    try {
      final payload = GoodsReceiptPayload(
        header: GoodsReceiptHeader(
          siparisId: _selectedOrder!.id,
          invoiceNumber: _selectedOrder!.poId,
          receiptDate: DateTime.now(),
        ),
        items: _addedItems
            .map((draft) => GoodsReceiptItemPayload(
          urunId: draft.product.id,
          quantity: draft.quantity,
          palletBarcode: draft.palletBarcode,
        ))
            .toList(),
      );
      await _repository.saveGoodsReceipt(payload);

      if (mounted) {
        _showSuccessSnackBar("Mal kabul başarıyla kaydedildi!");
        _resetScreen();
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar("Kaydetme hatası: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearEntryFields() {
    _productController.clear();
    _quantityController.clear();
    _selectedProduct = null;
    if (_receivingMode == ReceivingMode.kutu || _addedItems.isEmpty) {
      _palletIdController.clear();
    }
  }

  void _resetScreen() {
    setState(() {
      _addedItems.clear();
      _selectedOrder = null;
      _orderController.clear();
      _formKey.currentState?.reset();
      _clearEntryFields();
      _orderFocusNode.requestFocus();
    });
  }

  // --- ARAYÜZ ---
  @override
  Widget build(BuildContext context) {
    // --- Responsive Boyutlandırma ---
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final bool isKeyboardVisible = mediaQuery.viewInsets.bottom > 0;

    // YÜKSEKLİKLER (İstenen oranlara göre)
    final appBarHeight = screenHeight * 0.07;
    final segmentedButtonHeight = screenHeight * 0.07;
    final inputRowHeight = screenHeight * 0.075; // Sabit satır yüksekliği
    final bottomButtonHeight = screenHeight * 0.09;
    final summaryHeight = screenHeight * 0.175;

    // Dinamik Font ve Ikon Boyutları
    final sizeFactor = (screenWidth / 480.0).clamp(0.9, 1.3);

    final appBarFontSize = 19.0 * sizeFactor;
    final labelFontSize = 15.0 * sizeFactor;
    final buttonFontSize = 16.0 * sizeFactor;
    final summaryHeaderFontSize = 16.0 * sizeFactor;
    final summaryTitleFontSize = 15.0 * sizeFactor;
    final summarySubtitleFontSize = 13.0 * sizeFactor;
    final segmentedButtonFontSize = 13.0 * sizeFactor;
    final errorFontSize = 11.0 * sizeFactor;

    final baseIconSize = 24.0 * sizeFactor;
    final qrIconSize = 28.0 * sizeFactor;
    final segmentedButtonIconSize = 20.0 * sizeFactor;

    final bool isKutuModeLocked =
        _receivingMode == ReceivingMode.kutu && _addedItems.isNotEmpty;

    return Scaffold(
      appBar: SharedAppBar(
        title: 'Mal Kabul',
        preferredHeight: appBarHeight,
        titleFontSize: appBarFontSize,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: isKeyboardVisible
          ? null
          : _buildBottomBar(
        height: bottomButtonHeight,
        fontSize: buttonFontSize,
        iconSize: baseIconSize,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: _gap),
                            _buildModeSelector(
                              height: segmentedButtonHeight,
                              iconSize: segmentedButtonIconSize,
                              fontSize: segmentedButtonFontSize,
                            ),
                            const SizedBox(height: _gap),
                            _buildSearchableOrderDropdown(
                                height: inputRowHeight,
                                labelFontSize: labelFontSize,
                                errorFontSize: errorFontSize),
                            if (_receivingMode == ReceivingMode.palet) ...[
                              const SizedBox(height: _gap),
                              _buildPalletIdInput(
                                height: inputRowHeight,
                                labelFontSize: labelFontSize,
                                errorFontSize: errorFontSize,
                                iconSize: qrIconSize,
                              ),
                            ],
                            const SizedBox(height: _gap),
                            _buildSearchableProductInputRow(
                              isLocked: isKutuModeLocked,
                              height: inputRowHeight,
                              labelFontSize: labelFontSize,
                              errorFontSize: errorFontSize,
                              iconSize: qrIconSize,
                            ),
                            const SizedBox(height: _gap),
                            _buildQuantityInput(
                                isLocked: isKutuModeLocked,
                                height: inputRowHeight,
                                labelFontSize: labelFontSize,
                                errorFontSize: errorFontSize),
                            const Spacer(),
                            _buildLastAddedItemSummary(
                              height: summaryHeight,
                              headerFontSize: summaryHeaderFontSize,
                              titleFontSize: summaryTitleFontSize,
                              subtitleFontSize: summarySubtitleFontSize,
                            ),
                            const SizedBox(height: _gap),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
      ),
    );
  }

  Widget _buildModeSelector(
      {required double height, required double iconSize, required double fontSize}) {
    return SizedBox(
      height: height,
      child: Center(
        child: SegmentedButton<ReceivingMode>(
          segments: [
            ButtonSegment(
                value: ReceivingMode.palet,
                label: Text('Palet', style: TextStyle(fontSize: fontSize)),
                icon: Icon(Icons.pallet, size: iconSize)),
            ButtonSegment(
                value: ReceivingMode.kutu,
                label: Text('Kutu', style: TextStyle(fontSize: fontSize)),
                icon: Icon(Icons.inventory_2_outlined, size: iconSize)),
          ],
          selected: {_receivingMode},
          onSelectionChanged: (newSelection) {
            if (_isSaving) return;
            setState(() {
              _receivingMode = newSelection.first;
              _addedItems.clear();
              _clearEntryFields();
            });
          },
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.comfortable,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withAlpha(75),
            selectedBackgroundColor: Theme.of(context).colorScheme.primary,
            selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchableOrderDropdown(
      {required double height, required double labelFontSize, required double errorFontSize}) {
    return SizedBox(
      height: height,
      child: TextFormField(
        controller: _orderController,
        focusNode: _orderFocusNode,
        readOnly: true,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: labelFontSize),
        decoration: _inputDecoration(
          'Sipariş Seç',
          labelFontSize: labelFontSize,
          errorFontSize: errorFontSize,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        onTap: () async {
          final PurchaseOrder? selected =
          await _showSearchableDropdownDialog<PurchaseOrder>(
            title: 'Sipariş Seç',
            items: _purchaseOrders,
            itemToString: (item) => item.poId ?? "ID: ${item.id}",
            filterCondition: (item, query) =>
                (item.poId ?? "ID: ${item.id}")
                    .toLowerCase()
                    .contains(query.toLowerCase()),
          );
          if (selected != null) {
            setState(() {
              _selectedOrder = selected;
              _orderController.text = selected.poId ?? "ID: ${selected.id}";
            });
            if (_receivingMode == ReceivingMode.palet) {
              _palletIdFocusNode.requestFocus();
            } else {
              _productFocusNode.requestFocus();
            }
          }
        },
        validator: (value) =>
        (value == null || value.isEmpty) ? 'Lütfen bir sipariş seçin.' : null,
      ),
    );
  }

  Widget _buildPalletIdInput({
    required double height,
    required double labelFontSize,
    required double errorFontSize,
    required double iconSize,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextFormField(
              controller: _palletIdController,
              focusNode: _palletIdFocusNode,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: labelFontSize),
              decoration: _inputDecoration(
                'Palet Barkodu Girin/Okutun',
                labelFontSize: labelFontSize,
                errorFontSize: errorFontSize,
              ),
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  _productFocusNode.requestFocus();
                }
              },
              validator: (value) {
                if (_receivingMode == ReceivingMode.palet &&
                    (value == null || value.isEmpty)) {
                  return "Palet barkodu zorunludur.";
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () async {
              final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const QrScannerScreen()));
              if (result != null && result.isNotEmpty && mounted) {
                _palletIdController.text = result;
                _productFocusNode.requestFocus();
              }
            },
            size: height,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchableProductInputRow({
    required bool isLocked,
    required double height,
    required double labelFontSize,
    required double errorFontSize,
    required double iconSize,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextFormField(
              controller: _productController,
              focusNode: _productFocusNode,
              enabled: !isLocked,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: labelFontSize),
              decoration: _inputDecoration(
                'Ürün Seç/Okut',
                labelFontSize: labelFontSize,
                errorFontSize: errorFontSize,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  tooltip: 'Listeden Ürün Seç',
                  onPressed: isLocked
                      ? null
                      : () async {
                    final ProductInfo? selected =
                    await _showSearchableDropdownDialog<ProductInfo>(
                      title: 'Ürün Seç',
                      items: _availableProducts,
                      itemToString: (product) =>
                      "${product.name} (${product.stockCode})",
                      filterCondition: (product, query) =>
                      product.name
                          .toLowerCase()
                          .contains(query.toLowerCase()) ||
                          product.stockCode
                              .toLowerCase()
                              .contains(query.toLowerCase()) ||
                          (product.barcode1
                              ?.toLowerCase()
                              .contains(query.toLowerCase()) ??
                              false),
                    );
                    if (selected != null) {
                      _selectProduct(selected);
                    }
                  },
                ),
                enabled: !isLocked,
              ),
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  _processScannedProduct(value);
                }
              },
              validator: (value) =>
              (value == null || value.isEmpty) ? 'Lütfen bir ürün seçin.' : null,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () async {
              final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const QrScannerScreen()));
              if (result != null && result.isNotEmpty && mounted) {
                _productController.text = result;
                _processScannedProduct(result);
              }
            },
            size: height,
            isEnabled: !isLocked,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityInput(
      {required bool isLocked,
        required double height,
        required double labelFontSize,
        required double errorFontSize}) {
    return SizedBox(
      height: height,
      child: TextFormField(
        controller: _quantityController,
        focusNode: _quantityFocusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: labelFontSize),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
        ],
        enabled: !isLocked,
        decoration: _inputDecoration(
          'Miktar Girin',
          labelFontSize: labelFontSize,
          errorFontSize: errorFontSize,
          enabled: !isLocked,
        ),
        onFieldSubmitted: (value) {
          if (value.isNotEmpty) {
            _addItemToList();
          }
        },
        validator: (value) {
          if (isLocked) return null;
          if (value == null || value.isEmpty) return 'Miktar girin.';
          final number = double.tryParse(value);
          if (number == null || number <= 0) return 'Geçerli bir miktar girin.';
          return null;
        },
      ),
    );
  }

  Widget _buildLastAddedItemSummary({
    required double height,
    required double headerFontSize,
    required double titleFontSize,
    required double subtitleFontSize,
  }) {
    final lastItem = _addedItems.isNotEmpty ? _addedItems.first : null;

    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color:
          Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(125),
          borderRadius: _borderRadius,
          border:
          Border.all(color: Theme.of(context).dividerColor.withAlpha(180)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                "Eklenen Ürünler (${_addedItems.length})",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: headerFontSize,
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: lastItem == null
                  ? Center(
                child: Text(
                  "Son eklenen ürün burada görünecek.",
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).hintColor,
                    fontSize: subtitleFontSize,
                  ),
                ),
              )
                  : ListTile(
                title: Text(
                  lastItem.product.name,
                  style: TextStyle(
                      fontSize: titleFontSize, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  "Palet: ${lastItem.palletBarcode ?? 'YOK'}",
                  style: TextStyle(fontSize: subtitleFontSize),
                ),
                trailing: Text(
                  "x${lastItem.quantity.toString()}",
                  style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
      {required double height,
        required double fontSize,
        required double iconSize}) {
    if (_isLoading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: SizedBox(
        height: height,
        child: ElevatedButton.icon(
          onPressed: _addedItems.isEmpty || _isSaving ? null : _saveAndConfirm,
          icon: _isSaving
              ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
              : Icon(Icons.check_circle_outline, size: iconSize),
          label: Text('Kaydet ve Onayla', style: TextStyle(fontSize: fontSize)),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle:
              TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  // --- YARDIMCI METOTLAR (GÜNCELLENDİ) ---
  InputDecoration _inputDecoration(
      String label, {
        Widget? suffixIcon,
        bool enabled = true,
        required double labelFontSize,
        required double errorFontSize,
      }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: labelFontSize),
      filled: true,
      fillColor: enabled
          ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(75)
          : Colors.grey.shade200,
      errorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2.0),
      ),
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).dividerColor.withAlpha(180)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      errorStyle: const TextStyle(height: 0, fontSize: 0),
    );
  }

  Future<bool?> _showConfirmationListDialog() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final sizeFactor = (screenWidth / 480.0).clamp(0.9, 1.3);
    final dialogTitleFontSize = 18.0 * sizeFactor;
    final dialogContentFontSize = 15.0 * sizeFactor;
    final dialogButtonFontSize = 15.0 * sizeFactor;
    final iconSize = 22.0 * sizeFactor;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Onay Listesi",
                  style: TextStyle(fontSize: dialogTitleFontSize)),
              content: SizedBox(
                width: double.maxFinite,
                height: screenHeight * 0.5,
                child: _addedItems.isEmpty
                    ? Center(
                    child: Text("Liste boş.",
                        style: TextStyle(fontSize: dialogContentFontSize)))
                    : ListView.builder(
                  itemCount: _addedItems.length,
                  itemBuilder: (context, index) {
                    final item = _addedItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          item.product.name,
                          style:
                          TextStyle(fontSize: dialogContentFontSize),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                            "Palet: ${item.palletBarcode ?? 'YOK'}",
                            style: TextStyle(
                                fontSize: dialogContentFontSize * 0.85)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "x${item.quantity}",
                              style: TextStyle(
                                  fontSize: dialogContentFontSize,
                                  fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error,
                                  size: iconSize),
                              onPressed: () {
                                setDialogState(() {
                                  _removeItemFromList(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  child: Text("İptal",
                      style: TextStyle(fontSize: dialogButtonFontSize)),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                ElevatedButton(
                  child: Text("Onayla ve Kaydet",
                      style: TextStyle(fontSize: dialogButtonFontSize)),
                  onPressed: _addedItems.isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
  }) {
    String searchQuery = '';

    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredItems = items
                .where((item) => filterCondition(item, searchQuery))
                .toList();

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 40,
                  left: 16,
                  right: 16),
              child: Center(
                child: Material(
                  borderRadius: _borderRadius,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    height: MediaQuery.of(context).size.height * 0.7,
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(title,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: _gap),
                        TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Ara...',
                            prefixIcon: const Icon(Icons.search),
                            border:
                            OutlineInputBorder(borderRadius: _borderRadius),
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              searchQuery = value;
                            });
                          },
                        ),
                        const SizedBox(height: _gap),
                        Expanded(
                          child: filteredItems.isEmpty
                              ? const Center(child: Text('Sonuç bulunamadı.'))
                              : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return ListTile(
                                title: Text(itemToString(item)),
                                onTap: () =>
                                    Navigator.of(dialogContext).pop(item),
                              );
                            },
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            child: const Text('İptal'),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.orangeAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool isEnabled;
  final double iconSize;

  const _QrButton(
      {required this.onTap,
        required this.size,
        this.isEnabled = true,
        required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: isEnabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade300;
            }
            return Theme.of(context).colorScheme.secondaryContainer;
          }),
        ),
        child: Icon(Icons.qr_code_scanner, size: iconSize),
      ),
    );
  }
}

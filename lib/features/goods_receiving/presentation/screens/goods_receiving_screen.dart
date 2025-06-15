// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:easy_localization/easy_localization.dart';
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
  bool _isOrderDetailsLoading = false;

  ReceivingMode _receivingMode = ReceivingMode.palet;
  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
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

  // --- Donanım Tarayıcı Buffer ---
  final List<String> _barcodeBuffer = [];
  DateTime? _lastScanTime;
  final Duration _bufferTimeout = const Duration(milliseconds: 100);

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

  // --- DONANIM TARAYICI OLAY DİNLEYİCİSİ ---
  void _onKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    // Eğer ürün alanı odaklıysa, onFieldSubmitted halledeceği için bu dinleyiciyi pas geç.
    // readOnly olmayan alanlar klavye olaylarını kendileri yönetir.
    if (_productFocusNode.hasFocus) return;

    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!) > _bufferTimeout) {
      _barcodeBuffer.clear();
    }
    _lastScanTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_barcodeBuffer.isEmpty) return;

      final scannedData = _barcodeBuffer.join().trim();
      _barcodeBuffer.clear();

      if (scannedData.isEmpty) return;

      // Odaklanmış alana göre işlemi yönlendir.
      // setState içinde çalıştırarak UI güncellemelerini garantile.
      setState(() {
        if (_palletIdFocusNode.hasFocus) {
          _palletIdController.text = scannedData;
          _productFocusNode.requestFocus();
        }
      });

    } else if (event.character != null && event.character!.isNotEmpty) {
      // Sadece yazdırılabilir karakterleri buffer'a ekle
      _barcodeBuffer.add(event.character!);
    }
  }

  // --- VERİ YÜKLEME ---
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _purchaseOrders = await _repository.getOpenPurchaseOrders();
      _availableProducts = await _repository.searchProducts('');

      if (!mounted) return;
      setState(() => _isLoading = false);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _orderFocusNode.requestFocus());
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('goods_receiving_screen.error_loading_initial'
            .tr(namedArgs: {'error': '$e'}));
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SİPARİŞ İŞLEMLERİ ---
  void _onOrderSelected(PurchaseOrder order) {
    setState(() {
      _selectedOrder = order;
      _orderController.text = order.poId ?? "ID: ${order.id}";
      _addedItems.clear();
      _orderItems = [];
      _isOrderDetailsLoading = true;
      _clearEntryFields(clearPallet: true);
    });
    _loadOrderDetails(order.id);
  }

  Future<void> _loadOrderDetails(int orderId) async {
    try {
      final items = await _repository.getPurchaseOrderItems(orderId);
      if (!mounted) return;
      setState(() {
        _orderItems = items;
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('goods_receiving_screen.error_loading_details'
            .tr(namedArgs: {'error': '$e'}));
      }
    } finally {
      if (mounted) {
        setState(() => _isOrderDetailsLoading = false);
        _setInitialFocusAfterOrderLoad();
      }
    }
  }

  void _setInitialFocusAfterOrderLoad() {
    // GÜNCELLEME: requestFocus'u bir sonraki frame'e erteleyerek
    // widget ağacının hazır olmasını garantiliyoruz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_receivingMode == ReceivingMode.palet) {
        _palletIdFocusNode.requestFocus();
      } else {
        _productFocusNode.requestFocus();
      }
    });
  }

  // --- BARKOD/ÜRÜN İŞLEME ---
  void _processScannedProduct(String scannedData) {
    if (scannedData.isEmpty) return;

    final List<ProductInfo> productSource = _selectedOrder != null
        ? _orderItems.map((item) => item.product).whereNotNull().toList()
        : _availableProducts;

    final foundProduct = productSource.firstWhereOrNull(
          (p) =>
      p.stockCode.toLowerCase() == scannedData.toLowerCase() ||
          (p.barcode1?.toLowerCase() == scannedData.toLowerCase()),
    );

    if (foundProduct != null) {
      _selectProduct(foundProduct);
    } else {
      _productController.clear();
      _selectedProduct = null;
      _showErrorSnackBar('goods_receiving_screen.error_product_not_found'
          .tr(namedArgs: {'scannedData': scannedData}));
    }
  }

  void _selectProduct(ProductInfo product) {
    setState(() {
      _selectedProduct = product;
      _productController.text = "${product.name} (${product.stockCode})";
    });
    _quantityFocusNode.requestFocus();
  }

  // --- LİSTE VE KAYDETME İŞLEMLERİ ---
  void _addItemToList() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final quantity = double.tryParse(_quantityController.text);
    if (_selectedProduct == null || quantity == null || quantity <= 0) {
      _showErrorSnackBar(
          'goods_receiving_screen.error_select_product_and_quantity'.tr());
      return;
    }

    if (_selectedOrder != null) {
      if (_isOrderDetailsLoading) {
        _showErrorSnackBar(
            'goods_receiving_screen.error_loading_order_details'.tr());
        return;
      }

      final orderItem = _orderItems.firstWhereOrNull(
            (item) => item.product?.id == _selectedProduct!.id,
      );

      if (orderItem == null) {
        _showErrorSnackBar(
            'goods_receiving_screen.error_product_not_in_order'.tr());
        return;
      }

      final alreadyAddedInUI = _addedItems
          .where((item) => item.product.id == _selectedProduct!.id && (_receivingMode == ReceivingMode.palet ? item.palletBarcode == _palletIdController.text : true))
          .map((item) => item.quantity)
          .fold(0.0, (prev, qty) => prev + qty);

      final totalPreviouslyReceived = orderItem.receivedQuantity;
      final remainingQuantity =
          orderItem.expectedQuantity - totalPreviouslyReceived - alreadyAddedInUI;

      if (quantity > remainingQuantity + 0.001) {
        _showErrorSnackBar(
          'goods_receiving_screen.error_quantity_exceeds_order'.tr(
            namedArgs: {
              'remainingQuantity': remainingQuantity.toStringAsFixed(2),
              'unit': orderItem.unit ?? '',
            },
          ),
        );
        return;
      }
    }

    final isKutuModeLocked =
        _receivingMode == ReceivingMode.kutu && _addedItems.isNotEmpty;
    if (isKutuModeLocked) {
      _showErrorSnackBar(
          'goods_receiving_screen.error_box_mode_single_product'.tr());
      return;
    }

    final addedProductName = _selectedProduct!.name;

    setState(() {
      _addedItems.insert(
        0,
        ReceiptItemDraft(
          product: _selectedProduct!,
          quantity: quantity,
          palletBarcode: _receivingMode == ReceivingMode.palet
              ? _palletIdController.text
              : null,
        ),
      );

      _clearEntryFields(clearPallet: false);
    });

    _showSuccessSnackBar('goods_receiving_screen.success_item_added'
        .tr(namedArgs: {'productName': addedProductName}));

    _productFocusNode.requestFocus();
  }

  void _removeItemFromList(int index) {
    if (!mounted) return;
    final removedItemName = _addedItems[index].product.name;
    setState(() => _addedItems.removeAt(index));
    _showSuccessSnackBar(
        'goods_receiving_screen.success_item_removed'
            .tr(namedArgs: {'removedItemName': removedItemName}),
        isError: true);
  }

  Future<void> _saveAndConfirm() async {
    if (_addedItems.isEmpty) {
      _showErrorSnackBar('goods_receiving_screen.error_at_least_one_item'.tr());
      return;
    }
    if (_selectedOrder == null) {
      _showErrorSnackBar('goods_receiving_screen.error_select_order'.tr());
      _orderFocusNode.requestFocus();
      return;
    }

    final bool? confirmed = await _showConfirmationListDialog();
    if (confirmed != true) return;

    setState(() => _isSaving = true);

    final currentOrder = _selectedOrder!;

    try {
      final payload = GoodsReceiptPayload(
        header: GoodsReceiptHeader(
          siparisId: currentOrder.id,
          invoiceNumber: currentOrder.poId,
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
        _showSuccessSnackBar('goods_receiving_screen.success_receipt_saved'.tr());
        _handleSuccessfulSave(currentOrder.id);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
            'goods_receiving_screen.error_saving'.tr(namedArgs: {'error': '$e'}));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleSuccessfulSave(int savedOrderId) {
    setState(() {
      _addedItems.clear();
      _isOrderDetailsLoading = true;
      _clearEntryFields(clearPallet: true);
    });
    _loadOrderDetails(savedOrderId);
  }

  void _clearEntryFields({required bool clearPallet}) {
    _productController.clear();
    _quantityController.clear();
    _selectedProduct = null;
    if (clearPallet) {
      _palletIdController.clear();
    }
  }

  void _resetScreenForNewOrder() {
    setState(() {
      _addedItems.clear();
      _selectedOrder = null;
      _orderController.clear();
      _orderItems.clear();
      _clearEntryFields(clearPallet: true);
      _orderFocusNode.requestFocus();
    });
  }

  // --- ARAYÜZ ---
  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final bool isKeyboardVisible = mediaQuery.viewInsets.bottom > 0;

    final appBarHeight = screenHeight * 0.07;
    final inputRowHeight = screenHeight * 0.075;
    final bottomButtonHeight = screenHeight * 0.09;
    final summaryHeight = screenHeight * 0.175;
    final segmentedButtonHeight = screenHeight * 0.07;


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
    final bool areFieldsEnabled = !_isOrderDetailsLoading && !_isSaving;

    return Scaffold(
      appBar: SharedAppBar(
        title: 'goods_receiving_screen.title'.tr(),
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
      body: RawKeyboardListener(
        // GÜNCELLEME: Listener artık kendi FocusNode'una sahip değil.
        // Bu, alt widget'lar odaklandığında bile olayları dinlemesini sağlar.
        focusNode: FocusNode(),
        autofocus: true,
        onKey: _onKeyEvent,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: LayoutBuilder(builder: (context, constraints) {
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
                              errorFontSize: errorFontSize,
                            ),
                            if (_isOrderDetailsLoading)
                              const Padding(
                                padding: EdgeInsets.only(top: 4.0),
                                child: LinearProgressIndicator(),
                              ),
                            if (_receivingMode == ReceivingMode.palet) ...[
                              const SizedBox(height: _gap),
                              _buildPalletIdInput(
                                height: inputRowHeight,
                                labelFontSize: labelFontSize,
                                errorFontSize: errorFontSize,
                                iconSize: qrIconSize,
                                isEnabled: areFieldsEnabled,
                              ),
                            ],
                            const SizedBox(height: _gap),
                            _buildSearchableProductInputRow(
                              isLocked: isKutuModeLocked,
                              height: inputRowHeight,
                              labelFontSize: labelFontSize,
                              errorFontSize: errorFontSize,
                              iconSize: qrIconSize,
                              isEnabled: areFieldsEnabled,
                            ),
                            const SizedBox(height: _gap),
                            _buildQuantityAndStatusRow(
                              isLocked: isKutuModeLocked,
                              height: inputRowHeight,
                              labelFontSize: labelFontSize,
                              errorFontSize: errorFontSize,
                              isEnabled: areFieldsEnabled,
                              valueFontSize: summaryTitleFontSize,
                            ),
                            const SizedBox(height: _gap),
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
        ),
      ),
    );
  }

  Widget _buildModeSelector(
      {required double height,
        required double iconSize,
        required double fontSize}) {
    return SizedBox(
      height: height,
      child: Center(
        child: SegmentedButton<ReceivingMode>(
          segments: [
            ButtonSegment(
                value: ReceivingMode.palet,
                label: Text('goods_receiving_screen.mode_pallet'.tr(),
                    style: TextStyle(fontSize: fontSize)),
                icon: Icon(Icons.pallet, size: iconSize)),
            ButtonSegment(
                value: ReceivingMode.kutu,
                label: Text('goods_receiving_screen.mode_box'.tr(),
                    style: TextStyle(fontSize: fontSize)),
                icon: Icon(Icons.inventory_2_outlined, size: iconSize)),
          ],
          selected: {_receivingMode},
          onSelectionChanged: (newSelection) {
            if (_isSaving) return;
            // Kullanıcının talebi üzerine: Mod değiştirirken uyarı verme, listeyi temizle ve devam et.
            setState(() {
              _addedItems.clear();
              _clearEntryFields(clearPallet: true); // Palet, ürün ve miktar alanlarını temizler.
              _receivingMode = newSelection.first;

              // Eğer bir sipariş zaten seçiliyse, yeni moda uygun alana odaklan.
              // Değilse, sipariş seçme alanına odaklan.
              if (_selectedOrder != null) {
                _setInitialFocusAfterOrderLoad();
              } else {
                _orderFocusNode.requestFocus();
              }
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
      {required double height,
        required double labelFontSize,
        required double errorFontSize}) {
    return SizedBox(
      height: height,
      child: TextFormField(
        controller: _orderController,
        focusNode: _orderFocusNode,
        readOnly: true,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: labelFontSize),
        decoration: _inputDecoration(
          'goods_receiving_screen.label_select_order'.tr(),
          labelFontSize: labelFontSize,
          errorFontSize: errorFontSize,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        onTap: () async {
          if (_isSaving) return;
          final PurchaseOrder? selected =
          await _showSearchableDropdownDialog<PurchaseOrder>(
            title: 'goods_receiving_screen.label_select_order'.tr(),
            items: _purchaseOrders,
            itemToString: (item) => item.poId ?? "ID: ${item.id}",
            filterCondition: (item, query) =>
                (item.poId ?? "ID: ${item.id}")
                    .toLowerCase()
                    .contains(query.toLowerCase()),
            itemFontSize: labelFontSize,
          );
          if (selected != null) {
            _onOrderSelected(selected);
          }
        },
        validator: (value) =>
        (value == null || value.isEmpty) ? 'goods_receiving_screen.validator_select_order'.tr() : null,
      ),
    );
  }

  Widget _buildPalletIdInput({
    required double height,
    required double labelFontSize,
    required double errorFontSize,
    required double iconSize,
    required bool isEnabled,
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
              enabled: isEnabled,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: labelFontSize),
              decoration: _inputDecoration(
                'goods_receiving_screen.label_pallet_barcode'.tr(),
                labelFontSize: labelFontSize,
                errorFontSize: errorFontSize,
                enabled: isEnabled,
              ),
              onTap: () {
                if (_palletIdController.text.isNotEmpty) {
                  _palletIdController.clear();
                }
              },
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  _productFocusNode.requestFocus();
                }
              },
              validator: (value) {
                if (!isEnabled) return null;
                if (_receivingMode == ReceivingMode.palet &&
                    (value == null || value.isEmpty)) {
                  return 'goods_receiving_screen.validator_pallet_barcode'.tr();
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
            isEnabled: isEnabled,
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
    required bool isEnabled,
  }) {
    final bool fieldEnabled = isEnabled && !isLocked;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextFormField(
              controller: _productController,
              focusNode: _productFocusNode,
              // DÜZELTME: readOnly kaldırıldı. Bu, donanım tarayıcısının
              // bu alana yazmasına olanak tanır.
              // readOnly: true,
              showCursor: true,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                  fontSize: labelFontSize, overflow: TextOverflow.ellipsis),
              decoration: _inputDecoration(
                _selectedOrder != null
                    ? 'goods_receiving_screen.label_select_product_in_order'.tr()
                    : 'goods_receiving_screen.label_select_product'.tr(),
                labelFontSize: labelFontSize,
                errorFontSize: errorFontSize,
                suffixIcon: const Icon(Icons.arrow_drop_down),
                enabled: fieldEnabled,
              ),
              // DÜZELTME: onFieldSubmitted eklendi. Tarayıcı "Enter" gönderdiğinde
              // veya klavyeden "Enter"a basıldığında bu fonksiyon tetiklenir.
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  _processScannedProduct(value);
                }
              },
              onTap: !fieldEnabled
                  ? null
                  : () async {
                // onTap davranışı aynı kalır, kullanıcıya hala dialog ile seçim yapma imkanı sunar.
                final productList = _selectedOrder != null
                    ? _orderItems
                    .map((orderItem) => orderItem.product)
                    .whereNotNull()
                    .toList()
                    : _availableProducts;

                final ProductInfo? selected =
                await _showSearchableDropdownDialog<ProductInfo>(
                  title: 'goods_receiving_screen.label_select_product'.tr(),
                  items: productList,
                  itemToString: (product) =>
                  "${product.name} (${product.stockCode})",
                  filterCondition: (product, query) {
                    final lowerQuery = query.toLowerCase();
                    return product.name
                        .toLowerCase()
                        .contains(lowerQuery) ||
                        product.stockCode
                            .toLowerCase()
                            .contains(lowerQuery) ||
                        (product.barcode1
                            ?.toLowerCase()
                            .contains(lowerQuery) ??
                            false);
                  },
                  itemFontSize: labelFontSize,
                );
                if (selected != null) {
                  _selectProduct(selected);
                }
              },
              validator: (value) {
                if (!fieldEnabled) return null;
                // `_selectedProduct` kontrolü yerine `value` kontrolü kalır.
                // Çünkü `_addItemToList` içinde `_selectedProduct` hala kontrol ediliyor.
                return (value == null || value.isEmpty)
                    ? 'goods_receiving_screen.validator_select_product'.tr()
                    : null;
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
                // QR buton sonucu doğrudan product a işlenir
                _processScannedProduct(result);
              }
            },
            size: height,
            isEnabled: fieldEnabled,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityAndStatusRow({
    required bool isLocked,
    required double height,
    required double labelFontSize,
    required double errorFontSize,
    required bool isEnabled,
    required double valueFontSize,
  }) {
    final bool fieldEnabled = isEnabled && !isLocked;

    final orderItem = _selectedProduct == null || _selectedOrder == null
        ? null
        : _orderItems.firstWhereOrNull(
          (item) => item.product?.id == _selectedProduct!.id,
    );

    final alreadyAddedInUI = orderItem == null ? 0.0 : _addedItems
        .where((item) => item.product.id == orderItem.product!.id)
        .map((item) => item.quantity)
        .fold(0.0, (prev, qty) => prev + qty);

    final receivedQty = orderItem?.receivedQuantity ?? 0;
    final expectedQty = orderItem?.expectedQuantity ?? 0;
    final totalReceived = receivedQty + alreadyAddedInUI;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextFormField(
              controller: _quantityController,
              focusNode: _quantityFocusNode,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: labelFontSize),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ],
              enabled: fieldEnabled,
              decoration: _inputDecoration(
                'goods_receiving_screen.label_quantity'.tr(),
                labelFontSize: labelFontSize,
                errorFontSize: errorFontSize,
                enabled: fieldEnabled,
              ),
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  _addItemToList();
                }
              },
              validator: (value) {
                if (!fieldEnabled) return null;
                if (value == null || value.isEmpty) {
                  return 'goods_receiving_screen.validator_enter_quantity'.tr();
                }
                final number = double.tryParse(value);
                if (number == null || number <= 0) {
                  return 'goods_receiving_screen.validator_enter_valid_quantity'
                      .tr();
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: _borderRadius,
                border: Border.all(
                  color: Theme.of(context).dividerColor.withAlpha(180),
                ),
              ),
              child: Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      TextSpan(
                        text: '${totalReceived.toStringAsFixed(0)} ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const TextSpan(text: '/ '),
                      TextSpan(text: expectedQty.toStringAsFixed(0)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withAlpha(125),
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
                'goods_receiving_screen.header_added_items'
                    .tr(namedArgs: {'count': _addedItems.length.toString()}),
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
                  'goods_receiving_screen.last_added_item_placeholder'.tr(),
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
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  lastItem.palletBarcode != null
                      ? 'goods_receiving_screen.label_pallet_barcode_display'
                      .tr(namedArgs: {'barcode': lastItem.palletBarcode!})
                      : 'goods_receiving_screen.label_pallet_barcode_none'
                      .tr(),
                  style: TextStyle(fontSize: subtitleFontSize),
                ),
                trailing: Text(
                  'goods_receiving_screen.label_quantity_display'
                      .tr(namedArgs: {'quantity': lastItem.quantity.toString()}),
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
          label: Text('goods_receiving_screen.button_save_and_confirm'.tr(),
              style: TextStyle(fontSize: fontSize)),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: Size(double.infinity, height),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle:
              TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

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
        borderSide:
        BorderSide(color: Theme.of(context).colorScheme.error, width: 2.0),
      ),
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide:
        BorderSide(color: Theme.of(context).dividerColor.withAlpha(180)),
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
              title: Text('goods_receiving_screen.dialog_confirmation_title'.tr(),
                  style: TextStyle(fontSize: dialogTitleFontSize)),
              content: SizedBox(
                width: double.maxFinite,
                height: screenHeight * 0.5,
                child: _addedItems.isEmpty
                    ? Center(
                    child: Text(
                        'goods_receiving_screen.dialog_list_empty'.tr(),
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
                            item.palletBarcode != null
                                ? 'goods_receiving_screen.label_pallet_barcode_display'
                                .tr(namedArgs: {
                              'barcode': item.palletBarcode!
                            })
                                : 'goods_receiving_screen.label_pallet_barcode_none'
                                .tr(),
                            style: TextStyle(
                                fontSize:
                                dialogContentFontSize * 0.85)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'goods_receiving_screen.label_quantity_display'
                                  .tr(namedArgs: {
                                'quantity': item.quantity.toString()
                              }),
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
                  child: Text('dialog.cancel'.tr(),
                      style: TextStyle(fontSize: dialogButtonFontSize)),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                ElevatedButton(
                  child: Text(
                      'goods_receiving_screen.dialog_button_confirm_and_save'.tr(),
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
    required double itemFontSize,
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

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              title:
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              titlePadding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 40,
                      child: TextField(
                        autofocus: true,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'goods_receiving_screen.dialog_search_hint'.tr(),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border:
                          OutlineInputBorder(borderRadius: _borderRadius),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 12),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            searchQuery = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: _gap),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                          child: Text(
                              'goods_receiving_screen.dialog_search_no_results'
                                  .tr()))
                          : ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 2.0),
                            title: Text(itemToString(item),
                                style: TextStyle(fontSize: itemFontSize)),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(item),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('dialog.cancel'.tr()),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
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

enum ReceivingMode { palet, kutu }
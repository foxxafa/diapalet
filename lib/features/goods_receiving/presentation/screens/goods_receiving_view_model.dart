import 'dart:async';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/utils/gs1_parser.dart';
import 'package:diapalet/core/constants/warehouse_receiving_mode.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConfirmationAction { saveAndContinue, saveAndComplete, forceClose }

class GoodsReceivingViewModel extends ChangeNotifier {
  final GoodsReceivingRepository _repository;
  final SyncService _syncService;
  final BarcodeIntentService _barcodeService;

  // Controllers
  final palletIdController = TextEditingController();
  final deliveryNoteController = TextEditingController();
  final productController = TextEditingController();
  final quantityController = TextEditingController();
  final expiryDateController = TextEditingController();

  // Focus nodes
  final palletIdFocusNode = FocusNode();
  final deliveryNoteFocusNode = FocusNode();
  final productFocusNode = FocusNode();
  final quantityFocusNode = FocusNode();
  final expiryDateFocusNode = FocusNode();

  // State variables
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOrderDetailsLoading = false;
  bool _isDisposed = false;
  ReceivingMode _receivingMode = ReceivingMode.palet;

  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
  List<ProductInfo> _availableProducts = [];
  List<ProductInfo> _productSearchResults = [];
  ProductInfo? _selectedProduct;
  List<Map<String, dynamic>> _availableUnitsForSelectedProduct = [];
  final List<ReceiptItemDraft> _addedItems = [];

  // Subscriptions
  StreamSubscription<String>? _intentSub;
  StreamSubscription<SyncStatus>? _syncStatusSub;

  // UI Events
  String? _error;
  String? _successMessage;
  bool _navigateBack = false;

  // Getters
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isOrderDetailsLoading => _isOrderDetailsLoading;
  bool get isOrderBased => _selectedOrder != null;
  bool get areFieldsEnabled => !_isOrderDetailsLoading && !_isSaving;

  // New getters for field-specific enabling
  bool get isExpiryDateEnabled => _selectedProduct != null && areFieldsEnabled;
  bool get isQuantityEnabled => _selectedProduct != null && expiryDateController.text.isNotEmpty && areFieldsEnabled;
  bool get isDeliveryNoteEnabled => areFieldsEnabled;

  ReceivingMode get receivingMode => _receivingMode;
  PurchaseOrder? get selectedOrder => _selectedOrder;
  List<PurchaseOrderItem> get orderItems => _orderItems;
  List<ProductInfo> get availableProducts => _availableProducts;
  List<ProductInfo> get productSearchResults => _productSearchResults;
  ProductInfo? get selectedProduct => _selectedProduct;
  List<Map<String, dynamic>> get availableUnitsForSelectedProduct => _availableUnitsForSelectedProduct;
  List<ReceiptItemDraft> get addedItems => _addedItems;
  int get addedItemsCount => _addedItems.length;

  String? get error => _error;
  String? get successMessage => _successMessage;
  bool get navigateBack => _navigateBack;
  
  /// Seçili ürün sipariş dışı mı?
  bool get isSelectedProductOutOfOrder => _selectedProduct?.isOutOfOrder == true;

  /// Warehouse receiving mode kontrolü
  Future<WarehouseReceivingMode> get warehouseReceivingMode async {
    final prefs = await SharedPreferences.getInstance();
    final modeValue = prefs.getInt('receiving_mode') ?? 2;
    return WarehouseReceivingMode.fromValue(modeValue);
  }

  /// Mode selector görünür mü?
  Future<bool> get shouldShowModeSelector async {
    final mode = await warehouseReceivingMode;
    return mode == WarehouseReceivingMode.mixed;
  }

  /// Validates the delivery note number for free receipt
  String? validateDeliveryNote(String? value) {
    if (!areFieldsEnabled || isOrderBased) return null;
    if (value == null || value.isEmpty) {
      return 'goods_receiving_screen.validator_delivery_note_required'.tr();
    }
    return null;
  }

  bool get isReceiptCompletingOrder {
    if (!isOrderBased || _orderItems.isEmpty) return false;

    // Create a map of quantities being added in this receipt session.
    final currentAdditionMap = <int, double>{};
    for (final item in _addedItems) {
      currentAdditionMap.update(item.product.id, (value) => value + item.quantity, ifAbsent: () => item.quantity);
    }

    // Check if every line item in the order will be complete after this receipt.
    for (final orderItem in _orderItems) {
      final product = orderItem.product;
      if (product == null) continue;

      final expected = orderItem.expectedQuantity;
      final previouslyReceived = orderItem.receivedQuantity;
      final currentlyAdding = currentAdditionMap[product.id] ?? 0.0;

      if (previouslyReceived + currentlyAdding < expected - 0.001) {
        return false;
      }
    }

    return true;
  }

  GoodsReceivingViewModel({
    required GoodsReceivingRepository repository,
    required SyncService syncService,
    required BarcodeIntentService barcodeService,
    PurchaseOrder? initialOrder,
  }) : _repository = repository,
       _syncService = syncService,
       _barcodeService = barcodeService,
       _selectedOrder = initialOrder;

  void init() {
    palletIdFocusNode.addListener(_onFocusChange);
    productFocusNode.addListener(_onFocusChange);
    _loadInitialData();
    _initBarcode();
    _syncStatusSub = _syncService.syncStatusStream.listen((status) {
      if (status == SyncStatus.upToDate && isOrderBased) {
        debugPrint("Sync completed, refreshing order details...");
        _loadOrderDetails(_selectedOrder!.id);
      }
    });
  }


  @override
  void dispose() {
    _isDisposed = true;
    _intentSub?.cancel();
    _syncStatusSub?.cancel();
    palletIdFocusNode.removeListener(_onFocusChange);
    productFocusNode.removeListener(_onFocusChange);
    palletIdController.dispose();
    productController.dispose();
    quantityController.dispose();
    expiryDateController.dispose();
    palletIdFocusNode.dispose();
    productFocusNode.dispose();
    quantityFocusNode.dispose();
    expiryDateFocusNode.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void _onFocusChange() {
    if (palletIdFocusNode.hasFocus && palletIdController.text.isNotEmpty) {
      palletIdController.selection = TextSelection(baseOffset: 0, extentOffset: palletIdController.text.length);
    }
    if (productFocusNode.hasFocus && productController.text.isNotEmpty) {
      productController.selection = TextSelection(baseOffset: 0, extentOffset: productController.text.length);
    }
  }

  Future<void> _loadInitialData() async {
    if (_isDisposed) return;

    _isLoading = true;
    notifyListeners();
    try {
      // Warehouse receiving mode'a göre varsayılan modu ayarla
      final mode = await warehouseReceivingMode;
      final availableModes = mode.availableModes;
      if (availableModes.isNotEmpty && !availableModes.contains(_receivingMode)) {
        _receivingMode = availableModes.first;
      }

      if (!isOrderBased) {
        _availableProducts = await _repository.getAllActiveProducts();
      }

      if (_isDisposed) return;

      _isLoading = false;
      notifyListeners();

      if (isOrderBased) {
        _onOrderSelected(_selectedOrder!);
      } else {
        _setInitialFocus();
      }
    } catch (e) {
      if (_isDisposed) return;

      _error = 'goods_receiving_screen.error_loading_initial'.tr(namedArgs: {'error': e.toString()});
      _isLoading = false;
      notifyListeners();
    }
  }

  void _onOrderSelected(PurchaseOrder order) {
    _selectedOrder = order;
    _addedItems.clear();
    _orderItems = [];
    _isOrderDetailsLoading = true;
    _clearEntryFields(clearPallet: true);
    notifyListeners();
    _loadOrderDetails(order.id);
  }

  Future<void> _loadOrderDetails(int orderId) async {
    if (_isDisposed) return;

    try {
      _orderItems = await _repository.getPurchaseOrderItems(orderId);
      
      // Debug: Sipariş ürünlerinin barkodlarını kontrol et
      debugPrint("DEBUG: Order items loaded for order $orderId:");
      for (var item in _orderItems) {
        final barcode = item.product?.productBarcode ?? 'null';
        debugPrint("  - Product: ${item.product?.name}, StokKodu: ${item.product?.stockCode}, Unit: ${item.product?.displayUnitName ?? item.unit ?? 'N/A'}, Barcode: '$barcode'");
      }

      if (_isDisposed) return;
    } catch (e) {
      if (_isDisposed) return;

      _error = 'goods_receiving_screen.error_loading_details'.tr(namedArgs: {'error': e.toString()});
    } finally {
      if (!_isDisposed) {
        _isOrderDetailsLoading = false;
        _setInitialFocus();
        notifyListeners();
      }
    }
  }

  /// Belirli bir sipariş için sipariş dışı kabul edilen ürünleri getirir
  Future<List<ProductInfo>> getOutOfOrderReceiptItems() async {
    if (_selectedOrder == null) return [];
    return await _repository.getOutOfOrderReceiptItems(_selectedOrder!.id);
  }

  /// DEBUG: Manuel olarak free değerini güncelle
  Future<void> debugUpdateFreeValues(String urunKey) async {
    if (_selectedOrder == null) return;
    await _repository.debugUpdateFreeValues(_selectedOrder!.id, urunKey);
  }

  void _setInitialFocus() {
    if (_isDisposed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;

      if (_receivingMode == ReceivingMode.palet) {
        palletIdFocusNode.requestFocus();
      } else {
        productFocusNode.requestFocus();
      }
    });
  }

  void changeReceivingMode(ReceivingMode newMode) async {
    if (_isSaving) return;

    // Check if the new mode is supported by the warehouse
    final warehouseMode = await warehouseReceivingMode;
    if (!warehouseMode.availableModes.contains(newMode)) {
      return; // Don't change mode if not supported by warehouse
    }

    _clearEntryFields(clearPallet: true);
    _receivingMode = newMode;
    _setInitialFocus();
    notifyListeners();
  }

  void _initBarcode() {
    if (_isDisposed) return;

    _intentSub?.cancel();
    _intentSub = _barcodeService.stream.listen(_handleBarcode, onError: (e) {
      if (!_isDisposed) {
        _error = 'common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()});
        notifyListeners();
      }
    });
    _barcodeService.getInitialBarcode().then((code) {
      if (code != null && code.isNotEmpty && !_isDisposed) {
        _handleBarcode(code);
      }
    });
  }

  void _handleBarcode(String code) {
    if (_isDisposed) return;

    // Async operasyonu çalıştır ama beklemeden devam et
    _processScannedDataAsync(code);
  }

  Future<void> _processScannedDataAsync(String code) async {
    // Sadece izin verilen alanlarda barcode kabul et
    if (palletIdFocusNode.hasFocus) {
      await processScannedData('pallet', code);
    } else if (productFocusNode.hasFocus) {
      await processScannedData('product', code);
    } else if (deliveryNoteFocusNode.hasFocus || quantityFocusNode.hasFocus || expiryDateFocusNode.hasFocus) {
      // Bu alanlar barcode kabul etmez, uygun alana yönlendir
      _redirectToAppropriateField(code);
    } else {
      // Hiçbir alan focus'ta değilse varsayılan mantığı kullan
      _redirectToAppropriateField(code);
    }
  }

  Future<void> _redirectToAppropriateField(String code) async {
    if (_receivingMode == ReceivingMode.palet) {
      // Pallet modunda: pallet boşsa pallet'e, doluysa product'a
      if (palletIdController.text.isEmpty) {
        palletIdFocusNode.requestFocus();
        await processScannedData('pallet', code);
      } else {
        productFocusNode.requestFocus();
        await processScannedData('product', code);
      }
    } else {
      // Product modunda: her zaman product alanına
      productFocusNode.requestFocus();
      await processScannedData('product', code);
    }
  }

  /// Manuel olarak barkod okuma işlemini tetikle (scan button veya shortcut key için)
  Future<void> triggerManualScan() async {
    if (productFocusNode.hasFocus) {
      // Eğer product field'da metin varsa, bunu barkod olarak işle
      final currentText = productController.text.trim();
      if (currentText.isNotEmpty) {
        await processScannedData('product', currentText);
        return;
      }
    } else if (palletIdFocusNode.hasFocus) {
      // Eğer pallet field'da metin varsa, bunu barkod olarak işle
      final currentText = palletIdController.text.trim();
      if (currentText.isNotEmpty) {
        await processScannedData('pallet', currentText);
        return;
      }
    }

    // Metin yoksa normal barkod okuma akışı çalışır (intent service'den gelecek)
  }

  Future<bool> processScannedData(String field, String data, {BuildContext? context}) async {
    if (data.isEmpty) return false;

    switch (field) {
      case 'pallet':
        palletIdController.text = data;
        productFocusNode.requestFocus();
        return true;
      case 'product':
        // Parse GS1 data to extract GTIN and expiry date
        final parsedData = GS1Parser.parse(data);
        String productCodeToSearch = data;
        DateTime? scannedExpiryDate;

        // If GS1 data contains GTIN (01), use it for product search
        if (parsedData.containsKey('01')) {
          String gtin = parsedData['01']!;
          // If 14-digit GTIN starts with '0', remove it
          if (gtin.length == 14 && gtin.startsWith('0')) {
            productCodeToSearch = gtin.substring(1);
          } else {
            productCodeToSearch = gtin;
          }
        }

        // If GS1 data contains expiry date (17), parse it
        if (parsedData.containsKey('17')) {
          try {
            final expiryStr = parsedData['17']!;
            if (expiryStr.length == 6) {
              final year = 2000 + int.parse(expiryStr.substring(0, 2));
              final month = int.parse(expiryStr.substring(2, 4));
              final day = int.parse(expiryStr.substring(4, 6));
              scannedExpiryDate = DateTime(year, month, day);
            }
          } catch (e) {
            // Invalid date format in GS1, ignore
          }
        }


        ProductInfo? foundProduct;

        // YENİ BARKOD SİSTEMİ - Doğrudan database'den tam arama yap
        foundProduct = await _repository.findProductByBarcodeExactMatch(productCodeToSearch, orderId: _selectedOrder?.id);

        // Database'den bulunan ürün order'da var mı kontrol et - out-of-order flag zaten database'den geliyor

        if (foundProduct != null) {
          final productSelected = await selectProduct(foundProduct, context: context);
          
          if (!productSelected) {
            return false; // Ürün seçimi iptal edildi
          }

          // Auto-fill expiry date if found in GS1 barcode
          if (scannedExpiryDate != null) {
            // Validate that the scanned expiry date is not in the past
            final today = DateTime.now();
            final todayOnly = DateTime(today.year, today.month, today.day);

            if (scannedExpiryDate.isBefore(todayOnly)) {
              _error = 'goods_receiving_screen.error_expiry_date_past_scanned'.tr(
                namedArgs: {'date': DateFormat('dd/MM/yyyy').format(scannedExpiryDate)}
              );
            } else {
              // Auto-fill the expiry date field
              expiryDateController.text = DateFormat('dd/MM/yyyy').format(scannedExpiryDate);
              // Move focus to quantity field
              WidgetsBinding.instance.addPostFrameCallback((_) {
                quantityFocusNode.requestFocus();
              });
            }
          } else {
            // No expiry date in barcode, focus on expiry date field
            WidgetsBinding.instance.addPostFrameCallback((_) {
              expiryDateFocusNode.requestFocus();
            });
          }
        } else {
          productController.clear();
          _selectedProduct = null;
          _error = 'goods_receiving_screen.error_product_not_found'.tr(namedArgs: {'scannedData': data});
          return false; // Ürün bulunamadı
        }
        return true; // Başarıyla işlendi
      default:
        return false; // Bilinmeyen field
    }
  }

  Future<bool> selectProduct(ProductInfo product, {VoidCallback? onProductSelected, BuildContext? context}) async {
    // Sipariş dışı ürün kontrolü
    if (product.isOutOfOrder && context != null) {
      final selectedProductWithUnit = await showOutOfOrderProductModal(context, product);
      if (selectedProductWithUnit == null) {
        return false; // Modal'da iptal'e basıldı, ürün seçilmedi
      }
      // Seçilen birimle birlikte ürünü güncelle
      product = selectedProductWithUnit;
    }
    
    _selectedProduct = product;
    
    // Ürünün tüm birimlerini getir
    try {
      _availableUnitsForSelectedProduct = await DatabaseHelper.instance.getAllUnitsForProduct(product.stockCode);
      
      // Mevcut seçili birimi işaretle
      if (product.birimKey != null) {
        debugPrint('Selected product birim_key: ${product.birimKey}');
        _availableUnitsForSelectedProduct = _availableUnitsForSelectedProduct.map((unit) {
          if (unit['birim_key'] == product.birimKey || unit['_key'] == product.birimKey) {
            return {...unit, 'selected': true};
          }
          return {...unit, 'selected': false};
        }).toList();
      }
      
      debugPrint('Available units for ${product.stockCode}: ${_availableUnitsForSelectedProduct.length}');
      for (var unit in _availableUnitsForSelectedProduct) {
        debugPrint('  - Unit: ${unit['birimadi']} (${unit['birimkod']}), key: ${unit['birim_key'] ?? unit['_key']}, selected: ${unit['selected'] ?? false}');
      }
    } catch (e) {
      debugPrint('Error getting units for product: $e');
      _availableUnitsForSelectedProduct = [];
    }
    
    // Product field'a barkod ve stok kodunu yaz
    final barcode = product.displayBarcode;
    final stockCode = product.stockCode;
    productController.text = barcode != 'N/A' ? '$barcode ($stockCode)' : stockCode;
    
    _productSearchResults.clear(); // Clear search results when a product is selected
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        expiryDateFocusNode.requestFocus();
        // Callback çağır (date picker açmak için)
        onProductSelected?.call();
      }
    });
    return true; // Ürün başarıyla seçildi
  }

  Timer? _debounce;

  void onProductTextChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.isEmpty) {
        _productSearchResults.clear();
        _selectedProduct = null;
        notifyListeners();
        return;
      }

      try {
        _productSearchResults = await _repository.searchProducts(query, orderId: _selectedOrder?.id);
      } catch (e) {
        _error = 'Failed to search products: $e';
        _productSearchResults = [];
      }
      notifyListeners();
    });
  }

  void onExpiryDateEntered() {
    if (expiryDateController.text.isNotEmpty && _selectedProduct != null) {
      notifyListeners(); // Refresh to enable quantity field
      WidgetsBinding.instance.addPostFrameCallback((_) {
        quantityFocusNode.requestFocus();
      });
    }
  }

  /// Dropdown'dan birim seçildiğinde selected product'ı günceller
  void updateSelectedProduct(ProductInfo updatedProduct) {
    debugPrint("🔄 Updating selected product:");
    debugPrint("  - Old product: ${_selectedProduct?.name} - ${_selectedProduct?.displayUnitName}");
    debugPrint("  - Old source type: ${_selectedProduct?.birimInfo?['source_type']}");
    debugPrint("  - Old is out of order: ${_selectedProduct?.isOutOfOrder}");
    debugPrint("  - New birim_key: ${updatedProduct.birimKey}");
    debugPrint("  - New unit name: ${updatedProduct.displayUnitName}");
    debugPrint("  - New is out of order: ${updatedProduct.isOutOfOrder}");
    debugPrint("  - New source type: ${updatedProduct.birimInfo?['source_type']}");
    debugPrint("  - New order quantity: ${updatedProduct.orderQuantity}");
    
    _selectedProduct = updatedProduct;
    
    // Ürünün tüm birimlerini güncelle
    _availableUnitsForSelectedProduct = _availableUnitsForSelectedProduct.map((unit) {
      if (unit['birim_key'] == updatedProduct.birimKey || unit['_key'] == updatedProduct.birimKey) {
        // Seçilen birimi işaretle
        return {...unit, 'selected': true};
      }
      return {...unit, 'selected': false};
    }).toList();
    
    // Hata durumunu temizle 
    _error = null;
    
    debugPrint("🔄 Selected product updated successfully. Notifying listeners...");
    notifyListeners();
  }

  Future<void> addItemToList(BuildContext context) async {
    final quantity = double.tryParse(quantityController.text);
    if (_selectedProduct == null || quantity == null || quantity <= 0) {
      _error = 'goods_receiving_screen.error_select_product_and_quantity'.tr();
      notifyListeners();
      return;
    }

    // Check expiry date is provided (now mandatory)
    if (expiryDateController.text.isEmpty) {
      _error = 'goods_receiving_screen.error_expiry_date_required'.tr();
      notifyListeners();
      return;
    }

    if (isOrderBased && _selectedProduct?.isOutOfOrder != true) {
      if (_isOrderDetailsLoading) {
        _error = 'goods_receiving_screen.error_loading_order_details'.tr();
        notifyListeners();
        return;
      }
      final orderItem = _orderItems.firstWhere((item) => item.productId == _selectedProduct!.key);
      final alreadyAddedInUI = _addedItems.where((item) => item.product.key == _selectedProduct!.key).map((item) => item.quantity).fold(0.0, (prev, qty) => prev + qty);
      final totalPreviouslyReceived = orderItem.receivedQuantity;
      final remainingQuantity = orderItem.expectedQuantity - totalPreviouslyReceived - alreadyAddedInUI;

      // Check if quantity exceeds expected amount and ask for confirmation
      if (quantity > remainingQuantity + 0.001) {
        final shouldProceed = await _showQuantityExceedsConfirmation(
          context,
          quantity, 
          remainingQuantity, 
          orderItem.unit ?? ''
        );
        
        if (!shouldProceed) {
          return;
        }
      }
    }

    // Parse expiry date (now mandatory)
    DateTime? expiryDate;
    try {
      final parts = expiryDateController.text.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        expiryDate = DateTime(year, month, day);
      }
    } catch (e) {
      _error = 'goods_receiving_screen.validator_expiry_date_format'.tr();
      notifyListeners();
      return;
    }

    if (expiryDate == null) {
      _error = 'goods_receiving_screen.validator_expiry_date_format'.tr();
      notifyListeners();
      return;
    }

    // Validate that expiry date is not before today
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (expiryDate.isBefore(todayOnly)) {
      _error = 'goods_receiving_screen.error_expiry_date_past'.tr();
      notifyListeners();
      return;
    }

    _addedItems.insert(0, ReceiptItemDraft(
      product: _selectedProduct!,
      quantity: quantity,
      palletBarcode: _receivingMode == ReceivingMode.palet && palletIdController.text.isNotEmpty ? palletIdController.text : null,
      expiryDate: expiryDate,
    ));
    _successMessage = 'goods_receiving_screen.success_item_added'.tr(namedArgs: {'productName': _selectedProduct!.name});

    _clearEntryFields(clearPallet: false);

    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      productFocusNode.requestFocus();
    });
  }

  void removeItemFromList(int index) {
    final removedItemName = _addedItems[index].product.name;
    _addedItems.removeAt(index);
    _successMessage = 'goods_receiving_screen.success_item_removed'.tr(namedArgs: {'removedItemName': removedItemName});
    notifyListeners();
  }

  Future<bool> saveAndConfirm(ConfirmationAction action) async {
    _syncService.startUserOperation();

    _isSaving = true;
    notifyListeners();

    try {
      if (_addedItems.isNotEmpty) {
        await _executeSave();
      }

      switch (action) {
        case ConfirmationAction.saveAndContinue:
          _successMessage = 'goods_receiving_screen.success_saved'.tr();
          _handleSuccessfulSave(shouldNavigateBack: true);
          break;
        case ConfirmationAction.saveAndComplete:
           _successMessage = 'goods_receiving_screen.success_receipt_saved'.tr();
           _handleSuccessfulSave(shouldNavigateBack: true);
          break;
        case ConfirmationAction.forceClose:
          if (_selectedOrder != null) {
            await _repository.markOrderAsComplete(_selectedOrder!.id);
            _successMessage = 'orders.dialog.force_close_success'.tr(namedArgs: {'poId': _selectedOrder!.poId ?? ''});
            _navigateBack = true;
          }
          break;
      }

      // Arka planda senkronizasyonu tetikle, ama sonucunu bekleme.
      // Hata olursa (örn. offline), SyncService bunu daha sonra tekrar deneyecek.
      _syncService.uploadPendingOperations().catchError((e) {
        debugPrint("Offline sync attempt failed for goods receipt, will retry later: $e");
      });

      return true;

    } catch (e) {
      _error = 'goods_receiving_screen.error_saving'.tr(namedArgs: {'error': e.toString()});
      return false;
    } finally {
      _isSaving = false;
      _syncService.endUserOperation();
      notifyListeners();
    }
  }

  Future<void> _executeSave() async {
    if (_isDisposed) return;

    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getInt('user_id');
    if (employeeId == null) throw Exception('common_labels.user_id_not_found'.tr());

    final payload = GoodsReceiptPayload(
      header: GoodsReceiptHeader(
        siparisId: _selectedOrder?.id,
        invoiceNumber: _selectedOrder?.poId,
        deliveryNoteNumber: deliveryNoteController.text.isNotEmpty ? deliveryNoteController.text : null,
        receiptDate: DateTime.now(),
        employeeId: employeeId,
      ),
      items: _addedItems.map((draft) {
        // KRITIK DEBUG: birimKey değerini logla
        debugPrint('GOODS_RECEIPT DEBUG: Creating item payload for product ${draft.product.key}');
        debugPrint('  - Product name: ${draft.product.name}');
        debugPrint('  - birimKey: ${draft.product.birimKey}');
        debugPrint('  - birimInfo: ${draft.product.birimInfo}');
        debugPrint('  - isOutOfOrder: ${draft.product.isOutOfOrder}');
        
        return GoodsReceiptItemPayload(
          productId: draft.product.key, // _key değeri kullanılıyor
          birimKey: draft.product.birimKey, // Birim _key değeri eklendi
          quantity: draft.quantity,
          palletBarcode: draft.palletBarcode,
          barcode: draft.product.productBarcode, // Okutulan barcode bilgisi
          expiryDate: draft.expiryDate, // Now always has a value
          isFree: draft.product.isOutOfOrder, // Sipariş dışı ürün bilgisi
        );
      }).toList(),
    );
    await _repository.saveGoodsReceipt(payload);
  }

  void _handleSuccessfulSave({required bool shouldNavigateBack}) {
    if (_isDisposed) return;

    if (isOrderBased) {
      _navigateBack = shouldNavigateBack;
      _addedItems.clear();
      _clearEntryFields(clearPallet: true);
      if (!shouldNavigateBack && _selectedOrder != null) {
        _loadOrderDetails(_selectedOrder!.id);
      }
    } else {
      _addedItems.clear();
      _clearEntryFields(clearPallet: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) {
          productFocusNode.requestFocus();
        }
      });
    }
  }

  void _clearEntryFields({required bool clearPallet}) {
    productController.clear();
    quantityController.clear();
    expiryDateController.clear();
    _selectedProduct = null;
    _productSearchResults.clear();
    if (clearPallet) {
      palletIdController.clear();
    }
  }

  String? validateProduct(String? value) {
    if (areFieldsEnabled && (value == null || value.isEmpty || _selectedProduct == null)) {
      return 'goods_receiving_screen.validator_select_product'.tr();
    }
    return null;
  }

  String? validateQuantity(String? value) {
    if (!areFieldsEnabled) return null;
    if (value == null || value.isEmpty) return 'goods_receiving_screen.validator_enter_quantity'.tr();
    final number = double.tryParse(value);
    if (number == null || number <= 0) return 'goods_receiving_screen.validator_enter_valid_quantity'.tr();
    return null;
  }

  String? validatePalletId(String? value) {
    if (!areFieldsEnabled) return null;
    if (_receivingMode == ReceivingMode.palet && (value == null || value.isEmpty)) {
      return 'goods_receiving_screen.validator_pallet_barcode'.tr();
    }
    return null;
  }

  String? validateExpiryDate(String? value) {
    if (!areFieldsEnabled) return null;

    // Expiry date is now mandatory
    if (value == null || value.isEmpty) {
      return 'goods_receiving_screen.validator_expiry_date_required'.tr();
    }

    // Use the comprehensive validation helper
    bool isValid = _isValidDateString(value);
    debugPrint('ViewModel validation - Date: $value, IsValid: $isValid'); // Debug
    if (!isValid) {
      // Give specific error message based on the problem
      return _getDateValidationError(value);
    }

    return null;
  }

  // Helper function to validate date strings
  bool _isValidDateString(String dateString) {
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dateString)) {
      return false;
    }
    
    try {
      final parts = dateString.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      
      // Basic year check - must be current year or later
      final currentYear = DateTime.now().year;
      if (year < currentYear) {
        return false;
      }
      
      // Create DateTime - it will adjust invalid dates automatically
      final date = DateTime(year, month, day);
      
      // DateTime constructor adjusts invalid dates, so check if it's still the same
      if (date.day != day || date.month != month || date.year != year) {
        return false;
      }
      
      // Check if date is not in the past
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      
      return !date.isBefore(todayDate);
    } catch (e) {
      return false;
    }
  }

  // Helper function to get specific validation error message
  String _getDateValidationError(String dateString) {
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dateString)) {
      return 'goods_receiving_screen.validator_expiry_date_format'.tr();
    }
    
    try {
      final parts = dateString.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      
      // Basic structure check
      if (month < 1 || month > 12 || day < 1) {
        return 'goods_receiving_screen.validator_expiry_date_format'.tr();
      }
      
      // Create DateTime to check if date is valid
      final date = DateTime(year, month, day);
      
      // Check if date was adjusted (invalid date like Feb 30)
      if (date.day != day || date.month != month || date.year != year) {
        return 'goods_receiving_screen.validator_expiry_date_format'.tr();
      }
      
      // Check if date is in the past
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      
      if (date.isBefore(todayDate)) {
        return 'goods_receiving_screen.validator_expiry_date_future'.tr();
      }
      
      return 'goods_receiving_screen.validator_expiry_date_format'.tr();
    } catch (e) {
      return 'goods_receiving_screen.validator_expiry_date_format'.tr();
    }
  }

  void clearError() {
    _error = null;
  }

  void clearSuccessMessage() {
    _successMessage = null;
  }

  void clearNavigateBack() {
    _navigateBack = false;
  }

  Future<bool> _showQuantityExceedsConfirmation(BuildContext context, double enteredQuantity, double remainingQuantity, String unit) async {
    // Format numbers as integers if they are whole numbers, otherwise show minimal decimals
    String formatQuantity(double value) {
      if (value == value.roundToDouble()) {
        return value.toInt().toString();
      } else {
        return value.toStringAsFixed(value.truncateToDouble() != value ? 2 : 0);
      }
    }

    final theme = Theme.of(context);
    
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
            size: 32,
          ),
          title: Text(
            'goods_receiving_screen.confirm_quantity_exceeds_title'.tr(),
            style: TextStyle(color: theme.colorScheme.error),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Expected:', style: theme.textTheme.bodyMedium),
                        Text(
                          '${formatQuantity(remainingQuantity)} $unit',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Entering:', style: theme.textTheme.bodyMedium),
                        Text(
                          '${formatQuantity(enteredQuantity)} $unit',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Excess:', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '+${formatQuantity(enteredQuantity - remainingQuantity)} $unit',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to continue?',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: Text('common.confirm'.tr()),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Sipariş dışı ürün kabul modal'ı
  Future<ProductInfo?> showOutOfOrderProductModal(
    BuildContext context,
    ProductInfo product,
  ) async {
    final theme = Theme.of(context);
    
    // Ürünün tüm birimlerini getir
    List<Map<String, dynamic>> availableUnits = [];
    try {
      availableUnits = await DatabaseHelper.instance.getAllUnitsForProduct(product.stockCode);
    } catch (e) {
      debugPrint('Error getting units for product: $e');
      availableUnits = [];
    }
    
    return await showDialog<ProductInfo>(
      context: context,
      builder: (BuildContext context) {
        return _OutOfOrderProductDialog(
          product: product,
          availableUnits: availableUnits,
          theme: theme,
          orderItems: orderItems, // Order items'ı da gönder
        );
      },
    );
  }

  /// Birim değiştiğinde product text field'ını günceller
  void updateProductFieldWithNewBarcode(String newBarcode) {
    if (_selectedProduct != null) {
      final stockCode = _selectedProduct!.stockCode;
      final displayBarcode = newBarcode.isNotEmpty ? newBarcode : 'N/A';
      productController.text = displayBarcode != 'N/A' ? '$displayBarcode ($stockCode)' : stockCode;
      notifyListeners();
    }
  }
}

class _OutOfOrderProductDialog extends StatefulWidget {
  final ProductInfo product;
  final List<Map<String, dynamic>> availableUnits;
  final ThemeData theme;
  final List<PurchaseOrderItem> orderItems;

  const _OutOfOrderProductDialog({
    required this.product,
    required this.availableUnits,
    required this.theme,
    required this.orderItems,
  });

  @override
  State<_OutOfOrderProductDialog> createState() => _OutOfOrderProductDialogState();
}

class _OutOfOrderProductDialogState extends State<_OutOfOrderProductDialog> {
  int? selectedUnitIndex;

  @override
  void initState() {
    super.initState();
    // Mevcut ürünün birimini seç (eğer varsa)
    if (widget.availableUnits.isNotEmpty) {
      // Birim anahtarına göre mevcut birimi ara
      final currentBirimKey = widget.product.birimKey;
      debugPrint("🎯 Modal opening - looking for birim_key: $currentBirimKey");
      debugPrint("  - Available units: ${widget.availableUnits.map((u) => '${u['birimadi']} (key: ${u['birim_key']})').join(', ')}");
      
      if (currentBirimKey != null) {
        selectedUnitIndex = widget.availableUnits.indexWhere(
          (unit) => unit['birim_key'] == currentBirimKey || unit['_key'] == currentBirimKey,
        );
        debugPrint("  - Found at index: $selectedUnitIndex");
        
        if (selectedUnitIndex == -1) {
          // Bulamazsa ilkini seç
          selectedUnitIndex = 0;
          debugPrint("  - Not found, defaulting to index 0");
        }
      } else {
        selectedUnitIndex = 0; // İlkini seç
        debugPrint("  - No birim_key, defaulting to index 0");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.warning_rounded,
        color: Colors.orange,
        size: 32,
      ),
      title: Text(
        'goods_receiving_screen.out_of_order_product_title'.tr(),
        style: TextStyle(color: Colors.orange.shade800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.product.name,
                          style: widget.theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('goods_receiving_screen.out_of_order_product_stock_code'.tr(), 
                           style: widget.theme.textTheme.bodyMedium?.copyWith(
                             color: widget.theme.colorScheme.onSurfaceVariant,
                           )),
                      Text(
                        widget.product.stockCode,
                        style: widget.theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Birim seçimi dropdown'u
                  if (widget.availableUnits.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('goods_receiving_screen.out_of_order_product_unit'.tr(), 
                             style: widget.theme.textTheme.bodyMedium?.copyWith(
                               color: widget.theme.colorScheme.onSurfaceVariant,
                             )),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: DropdownButtonFormField<int>(
                              value: selectedUnitIndex,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              items: widget.availableUnits.asMap().entries.map((entry) {
                                final index = entry.key;
                                final unit = entry.value;
                                return DropdownMenuItem<int>(
                                  value: index,
                                  child: Text(
                                    unit['birimadi'] ?? '',
                                    style: widget.theme.textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (int? newIndex) {
                                setState(() {
                                  selectedUnitIndex = newIndex;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('goods_receiving_screen.out_of_order_product_unit'.tr(), 
                             style: widget.theme.textTheme.bodyMedium?.copyWith(
                               color: widget.theme.colorScheme.onSurfaceVariant,
                             )),
                        Text(
                          widget.product.displayUnitName ?? 'N/A',
                          style: widget.theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'goods_receiving_screen.out_of_order_product_message'.tr(),
                      style: widget.theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.justify,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'goods_receiving_screen.out_of_order_product_confirm'.tr(),
              style: widget.theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('goods_receiving_screen.out_of_order_product_cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: () {
            if (selectedUnitIndex != null && selectedUnitIndex! < widget.availableUnits.length) {
              final selectedUnit = widget.availableUnits[selectedUnitIndex!];
              final selectedBirimKey = selectedUnit['birim_key'];
              debugPrint("✅ Modal accepted with unit: ${selectedUnit['birimadi']} (key: $selectedBirimKey)");
              
              // Seçilen birimin sipariş içi mi dışı mı olduğunu kontrol et
              bool isOrderUnit = false;
              String sourceType = 'out_of_order';
              
              for (var orderItem in widget.orderItems) {
                final orderBirimKey = orderItem.product?.birimKey;
                final orderStockCode = orderItem.product?.stockCode;
                
                if (orderStockCode == widget.product.stockCode && 
                    orderBirimKey == selectedBirimKey) {
                  isOrderUnit = true;
                  sourceType = 'order';
                  debugPrint("  ✅ Selected unit is IN ORDER");
                  break;
                }
              }
              
              if (!isOrderUnit) {
                debugPrint("  ❌ Selected unit is OUT OF ORDER");
              }
              
              // Seçilen birimle güncellenmiş ProductInfo oluştur
              final updatedProduct = ProductInfo.fromDbMap({
                ...widget.product.toJson(),
                'birimadi': selectedUnit['birimadi'],
                'birimkod': selectedUnit['birimkod'],
                'barkod': selectedUnit['barkod'],
                'birim_key': selectedBirimKey,
                '_key': widget.product.productKey,
                'UrunId': widget.product.id,
                'UrunAdi': widget.product.name,
                'StokKodu': widget.product.stockCode,
                'aktif': widget.product.isActive ? 1 : 0,
                'source_type': sourceType, // Dinamik olarak belirlenen source_type
                'is_order_unit': isOrderUnit ? 1 : 0, // Dinamik olarak belirlenen is_order_unit
              });
              Navigator.of(context).pop(updatedProduct);
            } else {
              // Eğer birim seçilmediyse ve mevcut üründe birim_key yoksa, ilk birimi kullan
              if (widget.product.birimKey == null && widget.availableUnits.isNotEmpty) {
                final firstUnit = widget.availableUnits.first;
                final firstBirimKey = firstUnit['birim_key'];
                debugPrint("⚠️ No selection, using first unit: ${firstUnit['birimadi']} (key: $firstBirimKey)");
                
                // İlk birimin sipariş içi mi dışı mı olduğunu kontrol et
                bool isOrderUnit = false;
                String sourceType = 'out_of_order';
                
                for (var orderItem in widget.orderItems) {
                  final orderBirimKey = orderItem.product?.birimKey;
                  final orderStockCode = orderItem.product?.stockCode;
                  
                  if (orderStockCode == widget.product.stockCode && 
                      orderBirimKey == firstBirimKey) {
                    isOrderUnit = true;
                    sourceType = 'order';
                    break;
                  }
                }
                
                final updatedProduct = ProductInfo.fromDbMap({
                  ...widget.product.toJson(),
                  'birimadi': firstUnit['birimadi'],
                  'birimkod': firstUnit['birimkod'],
                  'barkod': firstUnit['barkod'],
                  'birim_key': firstBirimKey,
                  '_key': widget.product.productKey,
                  'UrunId': widget.product.id,
                  'UrunAdi': widget.product.name,
                  'StokKodu': widget.product.stockCode,
                  'aktif': widget.product.isActive ? 1 : 0,
                  'source_type': sourceType,
                  'is_order_unit': isOrderUnit ? 1 : 0,
                });
                Navigator.of(context).pop(updatedProduct);
              } else {
                Navigator.of(context).pop(widget.product);
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.theme.colorScheme.primary,
            foregroundColor: widget.theme.colorScheme.onPrimary,
          ),
          child: Text('goods_receiving_screen.out_of_order_product_accept'.tr()),
        ),
      ],
    );
  }
}
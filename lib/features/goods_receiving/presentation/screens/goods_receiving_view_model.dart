import 'dart:async';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
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
  final productController = TextEditingController();
  final quantityController = TextEditingController();

  // Focus nodes
  final palletIdFocusNode = FocusNode();
  final productFocusNode = FocusNode();
  final quantityFocusNode = FocusNode();

  // State variables
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOrderDetailsLoading = false;
  bool _isDisposed = false;
  ReceivingMode _receivingMode = ReceivingMode.palet;
  
  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
  List<ProductInfo> _availableProducts = [];
  ProductInfo? _selectedProduct;
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

  ReceivingMode get receivingMode => _receivingMode;
  PurchaseOrder? get selectedOrder => _selectedOrder;
  List<PurchaseOrderItem> get orderItems => _orderItems;
  List<ProductInfo> get availableProducts => _availableProducts;
  ProductInfo? get selectedProduct => _selectedProduct;
  List<ReceiptItemDraft> get addedItems => _addedItems;
  
  String? get error => _error;
  String? get successMessage => _successMessage;
  bool get navigateBack => _navigateBack;

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
    palletIdFocusNode.dispose();
    productFocusNode.dispose();
    quantityFocusNode.dispose();
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
      if (!isOrderBased) {
        _availableProducts = await _repository.searchProducts('');
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

  void changeReceivingMode(ReceivingMode newMode) {
    if (_isSaving) return;
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
    
    if (palletIdFocusNode.hasFocus) {
      processScannedData('pallet', code);
    } else if (productFocusNode.hasFocus) {
      processScannedData('product', code);
    } else {
      if (_receivingMode == ReceivingMode.palet && palletIdController.text.isEmpty) {
        processScannedData('pallet', code);
      } else if (_selectedProduct == null) {
        productFocusNode.requestFocus();
        processScannedData('product', code);
      }
    }
  }

  void processScannedData(String field, String data) {
    if (data.isEmpty) return;

    switch (field) {
      case 'pallet':
        palletIdController.text = data;
        productFocusNode.requestFocus();
        break;
      case 'product':
        final productSource = isOrderBased
            ? _orderItems.map((item) => item.product).whereType<ProductInfo>().toList()
            : _availableProducts;

        ProductInfo? foundProduct;
        try {
          foundProduct = productSource.firstWhere((p) =>
            p.stockCode.toLowerCase() == data.toLowerCase() || (p.barcode1?.toLowerCase() == data.toLowerCase()));
        } catch (e) {
          foundProduct = null;
        }

        if (foundProduct != null) {
          selectProduct(foundProduct);
        } else {
          productController.clear();
          _selectedProduct = null;
          _error = 'goods_receiving_screen.error_product_not_found'.tr(namedArgs: {'scannedData': data});
        }
        break;
    }
    notifyListeners();
  }

  void selectProduct(ProductInfo product) {
    _selectedProduct = product;
    productController.text = "${product.name} (${product.stockCode})";
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      quantityFocusNode.requestFocus();
    });
  }

  void addItemToList() {
    final quantity = double.tryParse(quantityController.text);
    if (_selectedProduct == null || quantity == null || quantity <= 0) {
      _error = 'goods_receiving_screen.error_select_product_and_quantity'.tr();
      notifyListeners();
      return;
    }

    if (isOrderBased) {
      if (_isOrderDetailsLoading) {
        _error = 'goods_receiving_screen.error_loading_order_details'.tr();
        notifyListeners();
        return;
      }
      final orderItem = _orderItems.firstWhere((item) => item.product?.id == _selectedProduct!.id);
      final alreadyAddedInUI = _addedItems.where((item) => item.product.id == _selectedProduct!.id).map((item) => item.quantity).fold(0.0, (prev, qty) => prev + qty);
      final totalPreviouslyReceived = orderItem.receivedQuantity;
      final remainingQuantity = orderItem.expectedQuantity - totalPreviouslyReceived - alreadyAddedInUI;

      if (quantity > remainingQuantity + 0.001) {
        _error = 'goods_receiving_screen.error_quantity_exceeds_order'.tr(namedArgs: {'remainingQuantity': remainingQuantity.toStringAsFixed(2), 'unit': orderItem.unit ?? ''});
        notifyListeners();
        return;
      }
    }

    _addedItems.insert(0, ReceiptItemDraft(
      product: _selectedProduct!,
      quantity: quantity,
      palletBarcode: _receivingMode == ReceivingMode.palet && palletIdController.text.isNotEmpty ? palletIdController.text : null,
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
          _handleSuccessfulSave(shouldNavigateBack: false);
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
        receiptDate: DateTime.now(),
        employeeId: employeeId,
      ),
      items: _addedItems.map((draft) => GoodsReceiptItemPayload(
        urunId: draft.product.id,
        quantity: draft.quantity,
        palletBarcode: draft.palletBarcode,
      )).toList(),
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
    _selectedProduct = null;
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
  
  void clearError() {
    _error = null;
  }
  
  void clearSuccessMessage() {
    _successMessage = null;
  }
  
  void clearNavigateBack() {
    _navigateBack = false;
  }
} 
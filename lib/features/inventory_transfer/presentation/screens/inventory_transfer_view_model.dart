import 'dart:async';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';

class InventoryTransferViewModel extends ChangeNotifier {
  final InventoryTransferRepository _repository;
  final SyncService _syncService;
  final BarcodeIntentService _barcodeService;

  // Controllers
  TextEditingController sourceLocationController = TextEditingController();
  TextEditingController targetLocationController = TextEditingController();
  TextEditingController scannedContainerIdController = TextEditingController();

  // Focus nodes
  FocusNode sourceLocationFocusNode = FocusNode();
  FocusNode targetLocationFocusNode = FocusNode();
  FocusNode containerFocusNode = FocusNode();

  // State variables
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;
  bool _isPalletOpening = false;
  bool _isDisposed = false;
  bool _isInitialized = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;
  
  Map<String, int> _availableSourceLocations = {};
  String? _selectedSourceLocationName;
  
  Map<String, int> _availableTargetLocations = {};
  String? _selectedTargetLocationName;
  
  List<dynamic> _availableContainers = [];
  dynamic _selectedContainer;
  
  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};

  // Subscriptions
  StreamSubscription<String>? _intentSub;

  // Error handling
  String? _lastError;
  String? get lastError => _lastError;

  // Getters
  bool get isLoadingInitialData => _isLoadingInitialData;
  bool get isLoadingContainerContents => _isLoadingContainerContents;
  bool get isSaving => _isSaving;
  bool get isPalletOpening => _isPalletOpening;
  bool get areFieldsEnabled => !_isLoadingInitialData && !_isSaving;
  bool get isInitialized => _isInitialized;

  AssignmentMode get selectedMode => _selectedMode;
  Map<String, int> get availableSourceLocations => _availableSourceLocations;
  String? get selectedSourceLocationName => _selectedSourceLocationName;
  Map<String, int> get availableTargetLocations => _availableTargetLocations;
  String? get selectedTargetLocationName => _selectedTargetLocationName;
  List<dynamic> get availableContainers => _availableContainers;
  dynamic get selectedContainer => _selectedContainer;
  List<ProductItem> get productsInContainer => _productsInContainer;
  Map<int, TextEditingController> get productQuantityControllers => _productQuantityControllers;
  Map<int, FocusNode> get productQuantityFocusNodes => _productQuantityFocusNodes;

  PurchaseOrder? get selectedOrder => _selectedOrder;
  // Bu ViewModel'in sipariş bazlı bir yerleştirme işlemi için kullanılıp kullanılmadığını belirtir.
  bool get isPutawayMode => _selectedOrder != null;

  AssignmentMode get finalOperationMode => _selectedMode == AssignmentMode.pallet
        ? (_isPalletOpening ? AssignmentMode.boxFromPallet : AssignmentMode.pallet)
        : AssignmentMode.box;

  PurchaseOrder? _selectedOrder;

  InventoryTransferViewModel({
    required InventoryTransferRepository repository,
    required SyncService syncService,
    required BarcodeIntentService barcodeService,
  }) : _repository = repository,
       _syncService = syncService,
       _barcodeService = barcodeService;
  
  void init(PurchaseOrder? order) {
    // Eğer zaten başlatılmışsa veya dispose edilmişse, tekrar başlatma
    if (_isInitialized || _isDisposed) {
      return;
    }
    
    _isInitialized = true; // Başlatıldı olarak işaretle
    _selectedOrder = order;
    
    // Controllers ve focus nodes'ları oluştur
    sourceLocationController = TextEditingController();
    targetLocationController = TextEditingController();
    scannedContainerIdController = TextEditingController();
    sourceLocationFocusNode = FocusNode();
    targetLocationFocusNode = FocusNode();
    containerFocusNode = FocusNode();
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
    
    _initializeListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _loadInitialData();
      }
    });
  }

  @override
  void dispose() {
    if (_isDisposed) return; // Prevent double disposal
    _isDisposed = true; // Set flag at the beginning
    _isInitialized = false;

    _intentSub?.cancel();
    sourceLocationFocusNode.removeListener(_onFocusChange);
    containerFocusNode.removeListener(_onFocusChange);
    targetLocationFocusNode.removeListener(_onFocusChange);
    sourceLocationController.dispose();
    targetLocationController.dispose();
    scannedContainerIdController.dispose();
    sourceLocationFocusNode.dispose();
    targetLocationFocusNode.dispose();
    containerFocusNode.dispose();
    _clearProductControllers();
    super.dispose();
  }

  void _initializeListeners() {
    if (_isDisposed) return; // Dispose edilmişse listener ekleme
    
    sourceLocationFocusNode.addListener(_onFocusChange);
    containerFocusNode.addListener(_onFocusChange);
    targetLocationFocusNode.addListener(_onFocusChange);

    _intentSub?.cancel();
    _intentSub = _barcodeService.stream.listen(_handleBarcode, onError: (e) {
      if (!_isDisposed) { // Dispose kontrolü
        showError('common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()}));
      }
    });

    _barcodeService.getInitialBarcode().then((code) {
      if (code != null && code.isNotEmpty && !_isDisposed) { // Dispose kontrolü
        _handleBarcode(code);
      }
    });
  }

  void _onFocusChange() {
    if (sourceLocationFocusNode.hasFocus && sourceLocationController.text.isNotEmpty) {
      sourceLocationController.selection = TextSelection(
        baseOffset: 0, 
        extentOffset: sourceLocationController.text.length
      );
    }
    if (containerFocusNode.hasFocus && scannedContainerIdController.text.isNotEmpty) {
      scannedContainerIdController.selection = TextSelection(
        baseOffset: 0, 
        extentOffset: scannedContainerIdController.text.length
      );
    }
    if (targetLocationFocusNode.hasFocus && targetLocationController.text.isNotEmpty) {
      targetLocationController.selection = TextSelection(
        baseOffset: 0, 
        extentOffset: targetLocationController.text.length
      );
    }
  }

  Future<void> _loadInitialData() async {
    if (_isDisposed) return; // Dispose edilmişse işlem yapma
    
    _isLoadingInitialData = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getSourceLocations(),
        _repository.getTargetLocations(),
      ]);
      
      if (_isDisposed) return; // Async işlem sırasında dispose edilmiş olabilir
      
      _availableSourceLocations = results[0];
      _availableTargetLocations = results[1];
      
      _isLoadingInitialData = false;
      notifyListeners();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) { // Dispose kontrolü
          sourceLocationFocusNode.requestFocus();
        }
      });
    } catch (e) {
      if (_isDisposed) return; // Hata durumunda da kontrol
      
      _isLoadingInitialData = false;
      showError('inventory_transfer.error_generic'.tr(namedArgs: {'error': e.toString()}));
      notifyListeners();
    }
  }

  void changeMode(AssignmentMode newMode) {
    if (_isSaving) return;
    
    _selectedMode = newMode;
    _isPalletOpening = false;
    resetForm(resetAll: false);
    
    if (_selectedSourceLocationName != null) {
      _loadContainersForLocation();
    } else {
      sourceLocationFocusNode.requestFocus();
    }
    
    notifyListeners();
  }

  void setPalletOpening(bool value) {
    if (_productsInContainer.isEmpty) return;
    
    _isPalletOpening = value;
    
    if (!value) {
      // Reset all quantities to maximum when disabling pallet opening
      for (var product in _productsInContainer) {
        final initialQty = product.currentQuantity;
        final initialQtyText = initialQty == initialQty.truncate()
            ? initialQty.toInt().toString()
            : initialQty.toString();
        _productQuantityControllers[product.id]?.text = initialQtyText;
      }
    }
    
    notifyListeners();
  }

  void showError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
  }

  Future<void> processScannedData(String field, String data) async {
    final cleanData = data.trim();
    if (cleanData.isEmpty) return;

    switch (field) {
      case 'source':
      case 'target':
        final location = await _repository.findLocationByCode(cleanData);
        if (location != null) {
          final bool isValidSource = field == 'source' && _availableSourceLocations.containsKey(location.key);
          final bool isValidTarget = field == 'target' && _availableTargetLocations.containsKey(location.key);

          if (isValidSource) {
            handleSourceSelection(location.key);
          } else if (isValidTarget) {
            handleTargetSelection(location.key);
          } else {
            if (field == 'source') sourceLocationController.clear();
            if (field == 'target') targetLocationController.clear();
            showError('inventory_transfer.error_invalid_location_for_operation'.tr(namedArgs: {'location': location.key, 'field': field}));
          }
        } else {
          if (field == 'source') sourceLocationController.clear();
          if (field == 'target') targetLocationController.clear();
          showError('inventory_transfer.error_invalid_location_code'.tr(namedArgs: {'code': cleanData}));
        }
        break;

      case 'container':
        dynamic foundItem;
        if (_selectedMode == AssignmentMode.pallet) {
          foundItem = _availableContainers.cast<String?>().firstWhere(
            (id) => id?.toLowerCase() == cleanData.toLowerCase(), 
            orElse: () => null
          );
        } else {
          // Önce mevcut listede ara
          foundItem = _availableContainers.cast<BoxItem?>().firstWhere(
            (box) => box?.productCode.toLowerCase() == cleanData.toLowerCase() || 
                    box?.barcode1?.toLowerCase() == cleanData.toLowerCase(), 
            orElse: () => null
          );

          // Mevcut listede bulunamazsa, veritabanında bu lokasyon için anlık sorgu yap
          if (foundItem == null) {
            debugPrint("Ürün '$cleanData' mevcut listede bulunamadı. Veritabanında anlık olarak aranıyor...");
            final locationId = _availableSourceLocations[_selectedSourceLocationName];
            if (locationId != null) {
              
              // HEDEF ODAKLI DÜZELTME:
              // Kaynak lokasyonun Mal Kabul Alanı olup olmadığını kontrol et
              final malKabulLocationName = _availableSourceLocations.entries
                  .firstWhere((entry) => entry.value == 1, // Varsayılan mal kabul ID'si 1
                      orElse: () => const MapEntry('', -1)).key;
              
              List<String> statusesToSearch = ['available'];
              if (_selectedSourceLocationName == malKabulLocationName) {
                statusesToSearch.add('receiving');
              }
              
              // Güncellenmiş repozitör metodunu doğru parametrelerle çağır
              foundItem = await _repository.findBoxByCodeAtLocation(cleanData, locationId, stockStatuses: statusesToSearch);
            }
          }
        }

        if (foundItem != null) {
          handleContainerSelection(foundItem);
        } else {
          scannedContainerIdController.clear();
          showError('inventory_transfer.error_item_not_found'.tr(namedArgs: {'data': cleanData}));
        }
        break;
    }
  }

  void handleSourceSelection(String? locationName) {
    if (locationName == null || locationName == _selectedSourceLocationName) return;
    
    _selectedSourceLocationName = locationName;
    sourceLocationController.text = locationName;
    _resetContainerAndProducts();
    _selectedTargetLocationName = null;
    targetLocationController.clear();
    
    notifyListeners();
    
    _loadContainersForLocation();
    containerFocusNode.requestFocus();
  }

  Future<void> handleContainerSelection(dynamic selectedItem) async {
    if (selectedItem == null) return;
    
    _selectedContainer = selectedItem;
    scannedContainerIdController.text = (selectedItem is BoxItem)
        ? '${selectedItem.productName} (${selectedItem.productCode})'
        : selectedItem.toString();
    
    notifyListeners();
    
    await _fetchContainerContents();
    targetLocationFocusNode.requestFocus();
  }

  void handleTargetSelection(String? locationName) {
    if (locationName == null) return;
    
    _selectedTargetLocationName = locationName;
    targetLocationController.text = locationName;
    notifyListeners();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _loadContainersForLocation() async {
    if (_selectedSourceLocationName == null || _isDisposed) return;
    
    final locationId = _availableSourceLocations[_selectedSourceLocationName];
    if (locationId == null) return;

    _isLoadingContainerContents = true;
    _resetContainerAndProducts();
    notifyListeners();

    try {
      // Sipariş bazlı modda (yerleştirme) "receiving" stoğunu, değilse "available" stoğunu getir.
      final String stockStatus = isPutawayMode ? 'receiving' : 'available';

      if (_selectedMode == AssignmentMode.pallet) {
        _availableContainers = await _repository.getPalletIdsAtLocation(locationId, stockStatus: stockStatus);
      } else {
        _availableContainers = await _repository.getBoxesAtLocation(locationId, stockStatus: stockStatus);
      }
      
      if (_isDisposed) return; // Async işlem sonrası kontrol
    } catch (e) {
      if (!_isDisposed) {
        showError('inventory_transfer.error_loading_containers'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (!_isDisposed) {
        _isLoadingContainerContents = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchContainerContents() async {
    final container = _selectedContainer;
    if (container == null || _isDisposed) return;

    final locationId = _availableSourceLocations[_selectedSourceLocationName!];
    if (locationId == null) {
      if (!_isDisposed) {
        showError('inventory_transfer.error_source_location_not_found'.tr());
      }
      return;
    }

    _isLoadingContainerContents = true;
    _productsInContainer = [];
    _clearProductControllers();
    notifyListeners();

    try {
      final String stockStatus = isPutawayMode ? 'receiving' : 'available';
      List<ProductItem> contents = [];
      if (_selectedMode == AssignmentMode.pallet && container is String) {
        contents = await _repository.getPalletContents(container, locationId, stockStatus: stockStatus);
      } else if (_selectedMode == AssignmentMode.box && container is BoxItem) {
        contents = [ProductItem.fromBoxItem(container)];
      }

      if (_isDisposed) return; // Async işlem sonrası kontrol
      
      _productsInContainer = contents;
      for (var product in contents) {
        final initialQty = product.currentQuantity;
        final initialQtyText = initialQty == initialQty.truncate()
            ? initialQty.toInt().toString()
            : initialQty.toString();
        _productQuantityControllers[product.id] = TextEditingController(text: initialQtyText);
        _productQuantityFocusNodes[product.id] = FocusNode();
      }
    } catch (e) {
      if (!_isDisposed) {
        showError('inventory_transfer.error_loading_content'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (!_isDisposed) {
        _isLoadingContainerContents = false;
        notifyListeners();
      }
    }
  }

  String? validateSourceLocation(String? value) {
    if (value == null || value.isEmpty) {
      return 'inventory_transfer.validator_required_field'.tr();
    }
    return null;
  }

  String? validateTargetLocation(String? value) {
    if (value == null || value.isEmpty) {
      return 'inventory_transfer.validator_required_field'.tr();
    }
    if (value == sourceLocationController.text) {
      return 'inventory_transfer.validator_target_cannot_be_source'.tr();
    }
    return null;
  }

  String? validateContainer(String? value) {
    if (value == null || value.isEmpty) {
      return 'inventory_transfer.validator_required_field'.tr();
    }
    return null;
  }

  String? validateProductQuantity(String? value, ProductItem product) {
    if (value == null || value.isEmpty) {
      return 'inventory_transfer.validator_required'.tr();
    }
    final qty = double.tryParse(value);
    if (qty == null) {
      return 'inventory_transfer.validator_invalid'.tr();
    }
    if (qty > product.currentQuantity + 0.001) {
      return 'inventory_transfer.validator_max'.tr();
    }
    if (qty < 0) {
      return 'inventory_transfer.validator_negative'.tr();
    }
    return null;
  }

  Future<bool> confirmAndSave() async {
    // Kullanıcı işlemi başladığını sync service'e bildir
    _syncService.startUserOperation();
    
    _isSaving = true;
    notifyListeners();
    try {
      final itemsToTransfer = getTransferItems();
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');
      final sourceId = _availableSourceLocations[_selectedSourceLocationName!];
      final targetId = _availableTargetLocations[_selectedTargetLocationName!];

      if (sourceId == null || targetId == null || employeeId == null) {
        showError('inventory_transfer.error_location_id_not_found'.tr());
        return false;
      }

      final header = TransferOperationHeader(
        employeeId: employeeId,
        operationType: finalOperationMode,
        sourceLocationName: _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
        containerId: (_selectedContainer is String) 
            ? _selectedContainer 
            : (_selectedContainer as BoxItem?)?.productCode,
        transferDate: DateTime.now(),
        siparisId: _selectedOrder?.id,
      );

      await _repository.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);

      // Bu bir sipariş yerleştirmeyse, tamamlanıp tamamlanmadığını kontrol et
      if (isPutawayMode && _selectedOrder != null) {
        await _repository.checkAndCompletePutaway(_selectedOrder!.id);
      }

      // İşlem başarılı, şimdi sync yapabiliriz
      _syncService.uploadPendingOperations();

      resetForm(resetAll: true);
      return true;
    } catch (e) {
      showError('inventory_transfer.error_saving'.tr(namedArgs: {'error': e.toString()}));
      return false;
    } finally {
      _isSaving = false;
      // Kullanıcı işlemi bittiğini sync service'e bildir
      _syncService.endUserOperation();
      notifyListeners();
    }
  }

  void _resetContainerAndProducts() {
    scannedContainerIdController.clear();
    _productsInContainer = [];
    _selectedContainer = null;
    _clearProductControllers();
    _availableContainers = [];
  }

  void resetForm({bool resetAll = false}) {
    _resetContainerAndProducts();
    _selectedTargetLocationName = null;
    targetLocationController.clear();

    if (resetAll) {
      _selectedSourceLocationName = null;
      sourceLocationController.clear();
    }

    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (resetAll) {
        sourceLocationFocusNode.requestFocus();
      } else {
        containerFocusNode.requestFocus();
      }
    });
  }

  void _clearProductControllers() {
    _productQuantityControllers.forEach((_, controller) => controller.dispose());
    _productQuantityFocusNodes.forEach((_, focusNode) => focusNode.dispose());
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
  }

  void _handleBarcode(String code) {
    if (_isDisposed) return; // Dispose edilmişse işlem yapma
    
    if (sourceLocationFocusNode.hasFocus) {
      processScannedData('source', code);
    } else if (containerFocusNode.hasFocus) {
      processScannedData('container', code);
    } else if (targetLocationFocusNode.hasFocus) {
      processScannedData('target', code);
    } else {
      if (_selectedSourceLocationName == null) {
        sourceLocationFocusNode.requestFocus();
        processScannedData('source', code);
      } else if (_selectedContainer == null) {
        containerFocusNode.requestFocus();
        processScannedData('container', code);
      } else {
        targetLocationFocusNode.requestFocus();
        processScannedData('target', code);
      }
    }
  }
  
  void focusNextProductOrTarget(int currentProductId) {
    final productIds = _productQuantityFocusNodes.keys.toList();
    final currentIndex = productIds.indexOf(currentProductId);
    if (currentIndex < productIds.length - 1) {
      _productQuantityFocusNodes[productIds[currentIndex + 1]]?.requestFocus();
    } else {
      targetLocationFocusNode.requestFocus();
    }
  }

  List<TransferItemDetail> getTransferItems() {
    final List<TransferItemDetail> items = [];
    
    for (var product in _productsInContainer) {
      final qtyText = _productQuantityControllers[product.id]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;
      if (qty > 0) {
        items.add(TransferItemDetail(
          productId: product.id,
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          palletId: _selectedMode == AssignmentMode.pallet ? (_selectedContainer as String) : null,
          targetLocationId: _availableTargetLocations[_selectedTargetLocationName!],
          targetLocationName: _selectedTargetLocationName!,
          stockStatus: product.stockStatus,
          siparisId: product.siparisId,
        ));
      }
    }
    return items;
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
} 
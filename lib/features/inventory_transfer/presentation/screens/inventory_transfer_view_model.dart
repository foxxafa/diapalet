import 'dart:async';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ANA GÜNCELLEME: Bu ViewModel artık hem "Serbest Transfer" hem de "Rafa Kaldırma" işlemlerini yönetiyor.
class InventoryTransferViewModel extends ChangeNotifier {
  final InventoryTransferRepository _repository;
  final SyncService _syncService;
  final BarcodeIntentService _barcodeService;

  // Controllers & Focus Nodes
  late TextEditingController sourceLocationController;
  late TextEditingController targetLocationController;
  late TextEditingController scannedContainerIdController;
  late FocusNode sourceLocationFocusNode;
  late FocusNode targetLocationFocusNode;
  late FocusNode containerFocusNode;

  // State
  bool _isLoadingInitialData = true, _isLoadingContainerContents = false, _isSaving = false, _isPalletOpening = false;
  bool _isDisposed = false, _isInitialized = false, _navigateBack = false;
  
  AssignmentMode _selectedMode = AssignmentMode.pallet;
  Map<String, int> _availableSourceLocations = {}, _availableTargetLocations = {};
  String? _selectedSourceLocationName, _selectedTargetLocationName;
  
  // GÜNCELLEME: Veri tipi `TransferableContainer` olarak değiştirildi.
  List<TransferableContainer> _availableContainers = [];
  TransferableContainer? _selectedContainer;
  
  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};
  
  StreamSubscription<String>? _intentSub;
  String? _lastError;
  PurchaseOrder? _selectedOrder;

  // GÜNCELLEME: UI olayları için state'ler eklendi.
  String? _error;
  String? _successMessage;

  // Getters
  bool get isLoadingInitialData => _isLoadingInitialData;
  bool get isLoadingContainerContents => _isLoadingContainerContents;
  bool get isSaving => _isSaving;
  bool get isPalletOpening => _isPalletOpening;
  bool get areFieldsEnabled => !_isLoadingInitialData && !_isSaving;
  bool get isInitialized => _isInitialized;
  bool get navigateBack => _navigateBack;
  AssignmentMode get selectedMode => _selectedMode;
  Map<String, int> get availableSourceLocations => _availableSourceLocations;
  String? get selectedSourceLocationName => _selectedSourceLocationName;
  Map<String, int> get availableTargetLocations => _availableTargetLocations;
  String? get selectedTargetLocationName => _selectedTargetLocationName;
  
  // GÜNCELLEME: Veri tipi `TransferableContainer` olarak değiştirildi.
  List<TransferableContainer> get availableContainers => _availableContainers;
  TransferableContainer? get selectedContainer => _selectedContainer;
  
  List<ProductItem> get productsInContainer => _productsInContainer;
  Map<int, TextEditingController> get productQuantityControllers => _productQuantityControllers;
  Map<int, FocusNode> get productQuantityFocusNodes => _productQuantityFocusNodes;
  String? get lastError => _lastError;
  PurchaseOrder? get selectedOrder => _selectedOrder;
  
  // DÜZELTME: Rafa kaldırma modunu belirleyen getter.
  bool get isPutawayMode => _selectedOrder != null;

  AssignmentMode get finalOperationMode => _selectedMode == AssignmentMode.pallet
      ? (_isPalletOpening ? AssignmentMode.boxFromPallet : AssignmentMode.pallet)
      : AssignmentMode.box;

  // Getters for UI events
  String? get error => _error;
  String? get successMessage => _successMessage;

  InventoryTransferViewModel({
    required InventoryTransferRepository repository,
    required SyncService syncService,
    required BarcodeIntentService barcodeService,
  }) : _repository = repository,
       _syncService = syncService,
       _barcodeService = barcodeService;
  
  void init(PurchaseOrder? order) {
    if (_isInitialized || _isDisposed) return;
    
    _isInitialized = true;
    _selectedOrder = order;
    
    sourceLocationController = TextEditingController();
    targetLocationController = TextEditingController();
    scannedContainerIdController = TextEditingController();
    sourceLocationFocusNode = FocusNode();
    targetLocationFocusNode = FocusNode();
    containerFocusNode = FocusNode();
    
    _initializeListeners();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    _isLoadingInitialData = true;
    notifyListeners();
    try {
      // Hedef lokasyonları her zaman yükle.
      _availableTargetLocations = await _repository.getTargetLocations();

      if (isPutawayMode) {
        // Rafa kaldırma modunda, kaynak lokasyon sabittir (Mal Kabul Alanı).
        // Konteynerler bu sanal alandan (`locationId: null`) ve siparişe göre yüklenir.
        _selectedSourceLocationName = 'common_labels.goods_receiving_area'.tr();
        sourceLocationController.text = _selectedSourceLocationName!;
        await _loadContainers();
      } else {
        // Serbest transferde kaynak lokasyonlar kullanıcı tarafından seçilmek üzere yüklenir.
        _availableSourceLocations = await _repository.getSourceLocations();
      }
    } catch (e) {
      _setError('inventory_transfer.error_loading_locations', e);
    } finally {
      if (!_isDisposed) {
        _isLoadingInitialData = false;
        notifyListeners();
        // Serbest transferde, başlangıçta kaynak lokasyona odaklan.
        if (!isPutawayMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            sourceLocationFocusNode.requestFocus();
          });
        }
      }
    }
  }
  
  Future<bool> confirmAndSave() async {
    _syncService.startUserOperation();
    _isSaving = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');
      final sourceId = isPutawayMode ? null : _availableSourceLocations[_selectedSourceLocationName!];
      final targetId = _availableTargetLocations[_selectedTargetLocationName!];

      if ((!isPutawayMode && sourceId == null) || targetId == null || employeeId == null) {
        _setError('inventory_transfer.error_location_id_not_found'.tr());
        return false;
      }
      
      final header = TransferOperationHeader(
        employeeId: employeeId,
        transferDate: DateTime.now(),
        operationType: finalOperationMode,
        sourceLocationName: isPutawayMode ? 'Mal Kabul Alanı' : _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
      );

      final itemsToTransfer = getTransferItems();
      
      await _repository.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);

      if (isPutawayMode && _selectedOrder != null) {
        await _repository.checkAndCompletePutaway(_selectedOrder!.id);
      }

      _syncService.uploadPendingOperations();

      _successMessage = 'inventory_transfer.success_transfer_saved'.tr();
      _navigateBack = true;
      return true;
    } catch (e) {
      _setError('inventory_transfer.error_saving'.tr(namedArgs: {'error': e.toString()}));
      return false;
    } finally {
      _isSaving = false;
      _syncService.endUserOperation();
      notifyListeners();
    }
  }
  
  // Listener and Dispose Methods
  void _initializeListeners() {
    _intentSub = _barcodeService.stream.listen(_handleBarcodeScan);
    sourceLocationFocusNode.addListener(_onFocusChange);
    targetLocationFocusNode.addListener(_onFocusChange);
    containerFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _intentSub?.cancel();
    sourceLocationController.dispose();
    targetLocationController.dispose();
    scannedContainerIdController.dispose();
    sourceLocationFocusNode.removeListener(_onFocusChange);
    sourceLocationFocusNode.dispose();
    targetLocationFocusNode.removeListener(_onFocusChange);
    targetLocationFocusNode.dispose();
    containerFocusNode.removeListener(_onFocusChange);
    containerFocusNode.dispose();
    _productQuantityControllers.forEach((_, controller) => controller.dispose());
    _productQuantityFocusNodes.forEach((_, node) => node.dispose());
    super.dispose();
  }

  // Event Handlers (Barcode, Focus, Selection)
  void _onFocusChange() {
    notifyListeners();
  }

  void _handleBarcodeScan(String barcode) {
    if (_isDisposed) return;

    if (sourceLocationFocusNode.hasFocus) {
      _findLocationAndSet(barcode, isSource: true);
    } else if (targetLocationFocusNode.hasFocus) {
      _findLocationAndSet(barcode, isSource: false);
    } else if (containerFocusNode.hasFocus) {
      _findContainerAndSet(barcode);
    } else {
      final focusedProductNode = _productQuantityFocusNodes.entries
          .firstWhere((entry) => entry.value.hasFocus, orElse: () => MapEntry(-1, FocusNode()));
      if (focusedProductNode.key != -1) {
        _setError('inventory_transfer.error_barcode_in_quantity_field');
      } else {
         _findContainerAndSet(barcode);
      }
    }
  }

  void handleSourceSelection(String? selection) {
    if (selection == null || selection == _selectedSourceLocationName) return;
    
    _selectedSourceLocationName = selection;
    sourceLocationController.text = selection;
    
    _resetContainerAndProducts();
    _loadContainers();
    notifyListeners();
  }

  void handleTargetSelection(String? selection) {
    if (selection == null) return;
    _selectedTargetLocationName = selection;
    targetLocationController.text = selection;
    notifyListeners();
  }
  
  void handleContainerSelection(TransferableContainer? selection) {
    if (selection == null) return;
    
    _selectedContainer = selection;
    scannedContainerIdController.text = selection.displayName;
    _loadContainerContents();
    notifyListeners();
  }

  void togglePalletOpening(bool value) {
    if (_isPalletOpening == value || productsInContainer.isEmpty) return;
    _isPalletOpening = value;
    
    // Eğer palet açma kapatılıyorsa, miktarları sıfırla.
    if (!value) {
      _productsInContainer.forEach((product) {
        final initialQty = product.currentQuantity;
        _productQuantityControllers[product.id]?.text = initialQty.toStringAsFixed(initialQty.truncateToDouble() == initialQty ? 0 : 2);
      });
    }
    notifyListeners();
  }
  
  void changeAssignmentMode(AssignmentMode newMode) {
    if (_selectedMode == newMode) return;
    _selectedMode = newMode;
    // Mod değiştiğinde konteyner ve ürün listesini sıfırla ve yeniden yükle.
    _resetContainerAndProducts();
    _loadContainers(); 
    notifyListeners();
  }

  // Data Loading & Processing
  Future<void> _loadContainers() async {
    // Rafa kaldırma modunda locationId null, serbest transferde ise seçili olmalı.
    final locationId = isPutawayMode ? null : _availableSourceLocations[_selectedSourceLocationName];
    if (locationId == null && !isPutawayMode) return;

    _isLoadingContainerContents = true;
    _resetContainerAndProducts();
    notifyListeners();
    
    try {
      // GÜNCELLEME: Yeni birleşik metod kullanılıyor.
      _availableContainers = await _repository.getTransferableContainers(locationId, orderId: _selectedOrder?.id);
    } catch (e) {
      _setError('inventory_transfer.error_loading_containers', e);
      _availableContainers = [];
    } finally {
      if (!_isDisposed) {
        _isLoadingContainerContents = false;
        notifyListeners();
      }
    }
  }
  
  void _loadContainerContents() {
    _clearProducts();
    if (_selectedContainer == null) return;

    // `TransferableContainer` içindeki `TransferableItem`'ları `ProductItem`'lara dönüştür.
    final products = _selectedContainer!.items.map((item) {
      return ProductItem(
        id: item.product.id,
        name: item.product.name,
        productCode: item.product.stockCode,
        barcode1: item.product.barcode1,
        currentQuantity: item.quantity,
        stockStatus: 'available', // Bu bilgi TransferableItem'da yok, gerekirse eklenmeli
        siparisId: _selectedOrder?.id,
      );
    }).toList();

    _productsInContainer = products;
    _initializeProductControllers();
    notifyListeners();
  }
  
  void _initializeProductControllers() {
    _clearProductControllers();
    for (var product in _productsInContainer) {
      final qty = product.currentQuantity;
      _productQuantityControllers[product.id] = TextEditingController(text: qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2));
      _productQuantityFocusNodes[product.id] = FocusNode();
    }
  }
  
  // Field Handling (Find, Set, Clear)
  Future<void> _findLocationAndSet(String barcode, {required bool isSource}) async {
    final location = await _repository.findLocationByCode(barcode);
    if (location != null) {
      if (isSource) {
        if (_availableSourceLocations.containsKey(location.key)) {
          handleSourceSelection(location.key);
        } else {
          _setError('inventory_transfer.error_location_not_in_source_list');
        }
      } else {
        if (_availableTargetLocations.containsKey(location.key)) {
          handleTargetSelection(location.key);
        } else {
          _setError('inventory_transfer.error_location_not_in_target_list');
        }
      }
    } else {
      _setError('inventory_transfer.error_location_not_found');
    }
  }

  void _findContainerAndSet(String barcode) {
    final found = _availableContainers.where((c) => c.id.toLowerCase() == barcode.toLowerCase()).toList();
    if (found.isNotEmpty) {
      handleContainerSelection(found.first);
    } else {
      scannedContainerIdController.text = barcode;
      _setError('inventory_transfer.error_container_not_found');
    }
  }
  
  void _resetContainerAndProducts() {
    _selectedContainer = null;
    scannedContainerIdController.clear();
    _availableContainers = [];
    _clearProducts();
  }

  void _clearProducts() {
    _productsInContainer = [];
    _clearProductControllers();
    _isPalletOpening = false;
  }

  void _clearProductControllers() {
    _productQuantityControllers.forEach((_, controller) => controller.dispose());
    _productQuantityFocusNodes.forEach((_, node) => node.dispose());
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
  }

  // Validation
  bool _validateForm() {
    if (isPutawayMode) {
      // In putaway mode, source location is implicit
      if (_selectedTargetLocationName == null) {
        _setError('inventory_transfer.validation_select_target');
        return false;
      }
    } else {
      // In free transfer mode, both are required
      if (_selectedSourceLocationName == null || _selectedTargetLocationName == null) {
        _setError('inventory_transfer.validation_select_source_and_target');
        return false;
      }
    }
    if (_selectedContainer == null) {
      _setError('inventory_transfer.validation_select_container');
      return false;
    }
    return true;
  }

  String? validateSourceLocation(String? value) {
    if (value == null || value.isEmpty) return 'validation.field_required'.tr();
    if (!_availableSourceLocations.containsKey(value)) return 'validation.invalid_selection'.tr();
    _selectedSourceLocationName = value;
    return null;
  }

  String? validateTargetLocation(String? value) {
    if (value == null || value.isEmpty) return 'validation.field_required'.tr();
    if (!_availableTargetLocations.containsKey(value)) return 'validation.invalid_selection'.tr();
     _selectedTargetLocationName = value;
    return null;
  }

  String? validateContainer(dynamic value) {
    if (value == null) return 'validation.field_required'.tr();
    if (value is String) {
       if (value.isEmpty) return 'validation.field_required'.tr();
    }
    if (_selectedContainer == null) return 'validation.invalid_selection'.tr();
    return null;
  }

  // Error Handling & State Update
  void _setError(String? messageKey, [Object? e]) {
    if (e != null) {
      debugPrint("Error in InventoryTransferViewModel: $e");
      // Hata mesajına göre doğru parametreleri belirle
      if (messageKey?.contains('error_invalid_location_code') == true) {
        _lastError = messageKey?.tr(namedArgs: {'code': e.toString()});
      } else if (messageKey?.contains('error_invalid_location_for_operation') == true) {
        _lastError = messageKey?.tr(namedArgs: {'location': e.toString(), 'field': 'location'});
      } else if (messageKey?.contains('error_item_not_found') == true) {
        _lastError = messageKey?.tr(namedArgs: {'data': e.toString()});
      } else {
        _lastError = messageKey?.tr(namedArgs: {'error': e.toString()});
      }
    } else {
      _lastError = messageKey?.tr();
    }
    notifyListeners();
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

  // Eksik metodları ekle
  void changeMode(AssignmentMode newMode) {
    if (_isSaving) return;
    
    _selectedMode = newMode;
    _isPalletOpening = false;
    _resetContainerAndProducts();
    
    if (_selectedSourceLocationName != null) {
      _loadContainers();
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
            _setError('inventory_transfer.error_invalid_location_for_operation', location.key);
          }
        } else {
          if (field == 'source') sourceLocationController.clear();
          if (field == 'target') targetLocationController.clear();
          _setError('inventory_transfer.error_invalid_location_code', cleanData);
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
          // Box mode için BoxItem arama
          foundItem = _availableContainers.cast<BoxItem?>().firstWhere(
            (box) => box?.productCode.toLowerCase() == cleanData.toLowerCase() || 
                    box?.barcode1?.toLowerCase() == cleanData.toLowerCase(), 
            orElse: () => null
          );

          // Mevcut listede bulunamazsa, veritabanında bu lokasyon için anlık sorgu yap
          if (foundItem == null) {
            final locationId = _availableSourceLocations[_selectedSourceLocationName];
            if (locationId != null) {
              List<String> statusesToSearch = ['available'];
              if (_selectedSourceLocationName == 'Goods Receiving Area') {
                statusesToSearch.add('receiving');
              }
              
              foundItem = await _repository.findBoxByCodeAtLocation(cleanData, locationId, stockStatuses: statusesToSearch);
            }
          }
        }

        if (foundItem != null) {
          handleContainerSelection(foundItem);
        } else {
          scannedContainerIdController.clear();
          _setError('inventory_transfer.error_item_not_found', cleanData);
        }
        break;
    }
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
          palletId: _selectedMode == AssignmentMode.pallet ? (_selectedContainer as String?) : null,
          targetLocationId: _availableTargetLocations[_selectedTargetLocationName!],
          targetLocationName: _selectedTargetLocationName!,
          stockStatus: product.stockStatus,
          siparisId: product.siparisId,
        ));
      }
    }
    return items;
  }
} 
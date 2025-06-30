import 'dart:async';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';

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
  List<TransferableContainer> _availableContainers = [];
  TransferableContainer? _selectedContainer;
  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};
  
  StreamSubscription<String>? _intentSub;
  String? _lastError;
  PurchaseOrder? _selectedOrder;

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
      if (isPutawayMode) {
        // Rafa kaldırma modunda, kaynak lokasyon sabittir (Mal Kabul Alanı)
        // ve konteynerler (paletler/kutular) bu sanal alandan yüklenir.
        _selectedSourceLocationName = 'common_labels.goods_receiving_area'.tr();
        sourceLocationController.text = _selectedSourceLocationName!;
        await _loadContainersForLocation(null, orderId: _selectedOrder!.id); 
      } else {
        // Serbest transferde kaynak lokasyonlar yüklenir.
        _availableSourceLocations = await _repository.getSourceLocations();
      }
      _availableTargetLocations = await _repository.getTargetLocations();
    } catch (e) {
      _setError('inventory_transfer.error_loading_locations', e);
    } finally {
      _isLoadingInitialData = false;
      if (!_isDisposed) notifyListeners();
    }
  }
  
  Future<bool> confirmAndSave() async {
    _setError(null);
    if (!_validateForm()) return false;

    _isSaving = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id') ?? 0;

      final header = TransferOperationHeader(
        employeeId: employeeId,
        transferDate: DateTime.now(),
        operationType: finalOperationMode,
        sourceLocationName: isPutawayMode ? 'Mal Kabul Alanı' : _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
      );

      final itemsToTransfer = _collectItemsToTransfer();
      if (itemsToTransfer.isEmpty) {
        _setError('inventory_transfer.error_no_items_to_transfer');
        return false;
      }
      
      final sourceId = isPutawayMode ? null : _availableSourceLocations[_selectedSourceLocationName!];
      final targetId = _availableTargetLocations[_selectedTargetLocationName!];

      if (targetId == null) {
         _setError('inventory_transfer.error_no_target_location');
         return false;
      }

      await _repository.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);
      
      if (isPutawayMode) {
        await _repository.checkAndCompletePutaway(_selectedOrder!.id);
      }
      
      await _syncService.uploadPendingOperations();

      _navigateBack = true;
      notifyListeners();
      return true;

    } catch (e) {
      _setError('inventory_transfer.error_saving_transfer', e);
      return false;
    } finally {
      _isSaving = false;
      if (!_isDisposed) notifyListeners();
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
      _findLocationAndSet(barcode, 'source');
    } else if (targetLocationFocusNode.hasFocus) {
      _findLocationAndSet(barcode, 'target');
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
    final locationId = _availableSourceLocations[selection];

    _clearContainerAndProducts();
    _loadContainersForLocation(locationId);
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
    if (_isPalletOpening == value) return;
    _isPalletOpening = value;
    notifyListeners();
  }
  
  void changeAssignmentMode(AssignmentMode newMode) {
    if (_selectedMode == newMode) return;
    _selectedMode = newMode;
    _clearContainerAndProducts();
    notifyListeners();
  }

  // Data Loading & Processing
  Future<void> _loadContainersForLocation(int? locationId, {int? orderId}) async {
    _isLoadingContainerContents = true;
    notifyListeners();
    try {
      _availableContainers = await _repository.getTransferableContainers(locationId, orderId: orderId);
    } catch (e) {
      _setError('inventory_transfer.error_loading_containers', e);
      _availableContainers = [];
    } finally {
      _isLoadingContainerContents = false;
      if (!_isDisposed) notifyListeners();
    }
  }
  
  void _loadContainerContents() {
    _clearProducts();
    if (_selectedContainer == null) return;

    final products = _selectedContainer!.items.map((item) {
      return ProductItem(
        id: item.product.id,
        name: item.product.name,
        productCode: item.product.stockCode,
        barcode1: item.product.barcode1,
        currentQuantity: item.quantity,
        stockStatus: 'available', // Default status since ProductInfo doesn't have stockStatus
        siparisId: null, // ProductInfo doesn't have siparisId
      );
    }).toList();

    _productsInContainer = products;
    _initializeProductControllers();
    notifyListeners();
  }
  
  void _initializeProductControllers() {
    _productQuantityControllers.forEach((_, controller) => controller.dispose());
    _productQuantityFocusNodes.forEach((_, node) => node.dispose());
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();

    for (var product in _productsInContainer) {
      _productQuantityControllers[product.id] = TextEditingController(text: product.currentQuantity.toString());
      _productQuantityFocusNodes[product.id] = FocusNode();
    }
  }
  
  List<TransferItemDetail> _collectItemsToTransfer() {
    final itemsToTransfer = <TransferItemDetail>[];
    for (final product in _productsInContainer) {
      final controller = _productQuantityControllers[product.id];
      final qty = double.tryParse(controller?.text ?? '0') ?? 0;
      if (qty > 0) {
        itemsToTransfer.add(TransferItemDetail(
          productId: product.id,
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          palletId: product.barcode1, // Using barcode1 as pallet identifier
          stockStatus: product.stockStatus,
          siparisId: product.siparisId,
        ));
      }
    }
    return itemsToTransfer;
  }
  
  // Field Handling (Find, Set, Clear)
  Future<void> _findLocationAndSet(String barcode, String field) async {
    final location = await _repository.findLocationByCode(barcode);
    if (location != null) {
      if (field == 'source' && !isPutawayMode) {
        if (_availableSourceLocations.containsKey(location.key)) {
          handleSourceSelection(location.key);
        } else {
          _setError('inventory_transfer.error_location_not_in_source_list');
        }
      } else if (field == 'target') {
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
    final found = _availableContainers.where((c) => c.id.toLowerCase() == barcode.toLowerCase() || c.displayName.toLowerCase().contains(barcode.toLowerCase())).toList();
    if (found.isNotEmpty) {
      handleContainerSelection(found.first);
    } else {
       scannedContainerIdController.text = barcode;
      _setError('inventory_transfer.error_container_not_found');
    }
  }
  
  void _clearContainerAndProducts() {
    _selectedContainer = null;
    scannedContainerIdController.clear();
    _availableContainers = [];
    _clearProducts();
  }

  void _clearProducts() {
    _productsInContainer = [];
    _productQuantityControllers.forEach((_, c) => c.dispose());
    _productQuantityFocusNodes.forEach((_, n) => n.dispose());
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
    _isPalletOpening = false;
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
      _lastError = messageKey?.tr(namedArgs: {'error': e.toString()});
    } else {
      _lastError = messageKey?.tr();
    }
    notifyListeners();
  }
  
  void clearError() {
    _lastError = null;
    // No need to notify, typically called before another state change
  }

  void clearNavigateBack() {
    _navigateBack = false;
  }
} 
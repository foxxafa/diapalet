import 'dart:async';
import 'package:diapalet/core/constants/warehouse_receiving_mode.dart';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/services/telegram_logger_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diapalet/features/inventory_transfer/constants/inventory_transfer_constants.dart';


class InventoryTransferViewModel extends ChangeNotifier {
  final InventoryTransferRepository _repo;
  final SyncService _syncService;
  final BarcodeIntentService _barcodeService;
  final PurchaseOrder? _initialOrder;

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
  Map<String, int?> _availableSourceLocationsMap = {};
  Map<String, int?> _availableTargetLocationsMap = {};
  String? _selectedSourceLocationName, _selectedTargetLocationName;

  // GÜNCELLEME: Veri tipi `TransferableContainer` olarak değiştirildi.
  List<TransferableContainer> _availableContainers = [];
  TransferableContainer? _selectedContainer;

  List<ProductItem> _productsInContainer = [];
  final Map<String, TextEditingController> _productQuantityControllers = {};
  final Map<String, FocusNode> _productQuantityFocusNodes = {};

  StreamSubscription<String>? _intentSub;
  String? _lastError;
  PurchaseOrder? _selectedOrder;
  String? _deliveryNoteNumber; // Free receipt için delivery note

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

  List<MapEntry<String, int?>> get availableSourceLocations => _availableSourceLocationsMap.entries.toList();
  String? get selectedSourceLocationName => _selectedSourceLocationName;
  List<MapEntry<String, int?>> get availableTargetLocations => _availableTargetLocationsMap.entries.where((entry) {
    // For shelf-to-shelf transfers, exclude the selected source location from target options
    return isPutawayMode || entry.key != _selectedSourceLocationName;
  }).toList();
  String? get selectedTargetLocationName => _selectedTargetLocationName;

  List<TransferableContainer> get availableContainers => _availableContainers;
  TransferableContainer? get selectedContainer => _selectedContainer;

  List<ProductItem> get productsInContainer => _productsInContainer;
  Map<String, TextEditingController> get productQuantityControllers => _productQuantityControllers;
  Map<String, FocusNode> get productQuantityFocusNodes => _productQuantityFocusNodes;
  String? get lastError => _lastError;
  PurchaseOrder? get selectedOrder => _selectedOrder;

  bool get isPutawayMode => _initialOrder != null;
  String? get deliveryNoteNumber => _deliveryNoteNumber;

  /// Warehouse receiving mode'unu SharedPreferences'dan okur
  Future<WarehouseReceivingMode> get warehouseReceivingMode async {
    final prefs = await SharedPreferences.getInstance();
    final receivingMode = prefs.getInt('receiving_mode') ?? 2; // Default: mixed
    return WarehouseReceivingMode.fromValue(receivingMode);
  }

  /// UI'de mode selector'ü gösterilmeli mi kontrol eder
  Future<bool> get shouldShowModeSelector async {
    final warehouseMode = await warehouseReceivingMode;
    return warehouseMode == WarehouseReceivingMode.mixed;
  }

  void setDeliveryNote(String? deliveryNote) {
    _deliveryNoteNumber = deliveryNote;
  }

  AssignmentMode get finalOperationMode => _selectedMode == AssignmentMode.pallet
      ? (_isPalletOpening ? AssignmentMode.productFromPallet : AssignmentMode.pallet)
      : AssignmentMode.product;

  String? get error => _error;
  String? get successMessage => _successMessage;

  InventoryTransferViewModel({
    required InventoryTransferRepository repository,
    required SyncService syncService,
    required BarcodeIntentService barcodeService,
    required PurchaseOrder? initialOrder,
  }) : _repo = repository,
       _syncService = syncService,
       _barcodeService = barcodeService,
       _initialOrder = initialOrder;

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
      // FIX: For putaway operations, exclude receiving area from target locations
      _availableTargetLocationsMap = await _repo.getTargetLocations(excludeReceivingArea: isPutawayMode);

      if (isPutawayMode) {
        _selectedSourceLocationName = InventoryTransferConstants.receivingAreaCode;
        sourceLocationController.text = _selectedSourceLocationName!;
        await _loadContainers();
      } else {
        // FIX: For shelf-to-shelf transfers, exclude receiving area from source locations
        _availableSourceLocationsMap = await _repo.getSourceLocations(includeReceivingArea: false);
      }
    } catch (e) {
      _setError('inventory_transfer.error_loading_locations', e);
    } finally {
      if (!_isDisposed) {
        _isLoadingInitialData = false;
        notifyListeners();

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
      final sourceId = isPutawayMode ? null : _availableSourceLocationsMap[_selectedSourceLocationName];
      final targetId = _availableTargetLocationsMap[_selectedTargetLocationName];

      if ((!isPutawayMode && sourceId == null) || targetId == null || employeeId == null) {
        _setError('inventory_transfer.error_location_id_not_found');
        return false;
      }

      final header = TransferOperationHeader(
        employeeId: employeeId,
        transferDate: DateTime.now(),
        operationType: finalOperationMode,
        sourceLocationName: isPutawayMode ? InventoryTransferConstants.receivingAreaCode : _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
      );

      final itemsToTransfer = getTransferItems();

      await _repo.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);

      if (isPutawayMode && _selectedOrder != null) {
        await _repo.checkAndCompletePutaway(_selectedOrder!.id);
      }

      _syncService.uploadPendingOperations();

      _successMessage = 'inventory_transfer.success_transfer_saved'.tr();
      _navigateBack = true;
      return true;
    } catch (e, stackTrace) {
      // Log to database (ERROR level - saved to SQLite for manual review)
      try {
        final prefs = await SharedPreferences.getInstance();
        final employeeId = prefs.getInt('user_id');
        final employeeName = prefs.getString('user_name');

        await TelegramLoggerService.logError(
          'Inventory Transfer Save Failed (ViewModel)',
          'Failed to save inventory transfer: $e',
          stackTrace: stackTrace,
          context: {
            'operation_type': finalOperationMode.toString(),
            'source_location': _selectedSourceLocationName,
            'target_location': _selectedTargetLocationName,
            'items_count': getTransferItems().length,
            'is_putaway': isPutawayMode.toString(),
            'order_id': _selectedOrder?.id,
            'delivery_note': _deliveryNoteNumber,
          },
          employeeId: employeeId,
          employeeName: employeeName,
        );
      } catch (logError) {
        debugPrint('⚠️ Failed to log error: $logError');
      }

      _setError('inventory_transfer.error_saving', e);
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
    for (var controller in _productQuantityControllers.values) {
      controller.dispose();
    }
    for (var node in _productQuantityFocusNodes.values) {
      node.dispose();
    }
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
    super.dispose();
  }

  // Event Handlers (Barcode, Focus, Selection)
  void _onFocusChange() {
    notifyListeners();
  }

  void _handleBarcodeScan(String barcode) {
    if (_isDisposed) return;

    // Sadece container/pallet alanına barcode girişine izin ver
    if (containerFocusNode.hasFocus) {
      _findContainerAndSet(barcode);
    } else {
      final focusedProductNode = _productQuantityFocusNodes.entries
          .firstWhere((entry) => entry.value.hasFocus, orElse: () => MapEntry('', FocusNode()));
      if (focusedProductNode.key != '') {
        _setError('inventory_transfer.error_barcode_in_quantity_field');
      } else {
        // Hiçbir uygun alan focus'ta değilse container alanına odaklan ve veriyi gir
        containerFocusNode.requestFocus();
        _findContainerAndSet(barcode);
      }
    }
  }

  void handleSourceSelection(String? selection) {
    if (selection == null || selection == _selectedSourceLocationName) return;

    _selectedSourceLocationName = selection;
    sourceLocationController.text = selection;

    // Clear target location if it would become invalid (same as source)
    if (_selectedTargetLocationName == selection) {
      _selectedTargetLocationName = null;
      targetLocationController.clear();
    }

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

    if (!value) {
      for (var product in _productsInContainer) {
        final initialQty = product.currentQuantity;
        _productQuantityControllers[product.key]?.text = initialQty.toStringAsFixed(initialQty.truncateToDouble() == initialQty ? 0 : 2);
      }
    }
    notifyListeners();
  }

  void changeAssignmentMode(AssignmentMode newMode) async {
    if (_selectedMode == newMode) return;

    // Check if the new mode is supported by the warehouse
    final warehouseMode = await warehouseReceivingMode;

    // AssignmentMode'u ReceivingMode'a dönüştür
    final bool isNewModeSupported;
    switch (newMode) {
      case AssignmentMode.pallet:
        isNewModeSupported = warehouseMode.isPaletEnabled;
        break;
      case AssignmentMode.product:
      case AssignmentMode.productFromPallet:
        isNewModeSupported = warehouseMode.isProductEnabled;
        break;
    }

    if (!isNewModeSupported) {
      return; // Don't change mode if not supported by warehouse
    }

    _selectedMode = newMode;
    _resetContainerAndProducts();
    _loadContainers();
    notifyListeners();
  }

  // Data Loading & Processing
  Future<void> _loadContainers() async {
    final locationId = isPutawayMode ? null : _availableSourceLocationsMap[_selectedSourceLocationName];
    if (locationId == null && !isPutawayMode) return;

    _isLoadingContainerContents = true;
    _resetContainerAndProducts();
    notifyListeners();

    try {
      _availableContainers = await _repo.getTransferableContainers(
        locationId,
        orderId: _selectedOrder?.id,
        deliveryNoteNumber: _deliveryNoteNumber,
      );
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

    final products = _selectedContainer!.items.map((item) {
      return ProductItem(
        productKey: item.product.key,
        birimKey: item.product.birimKey, // KRITIK FIX: birimKey eklendi
        name: item.product.name,
        productCode: item.product.stockCode,
        currentQuantity: item.quantity,
        expiryDate: item.expiryDate,
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
      _productQuantityControllers[product.key] = TextEditingController(text: qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 2));
      _productQuantityFocusNodes[product.key] = FocusNode();
    }
  }

  // Field Handling (Find, Set, Clear)

  void _findContainerAndSet(String barcode) {
    final found = _availableContainers.where((c) => c.id.toLowerCase() == barcode.toLowerCase() || c.displayName.toLowerCase() == barcode.toLowerCase()).toList();
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
    for (var controller in _productQuantityControllers.values) {
      controller.dispose();
    }
    _productQuantityControllers.clear();
  }

  // Validation
  String? validateSourceLocation(String? value) {
    if (value == null || value.isEmpty) return 'validation.field_required'.tr();
    if (!_availableSourceLocationsMap.containsKey(value)) return 'validation.invalid_selection'.tr();
    _selectedSourceLocationName = value;
    return null;
  }

  String? validateTargetLocation(String? value) {
    if (value == null || value.isEmpty) return 'validation.field_required'.tr();
    if (!_availableTargetLocationsMap.containsKey(value)) return 'validation.invalid_selection'.tr();
    if (value == _selectedSourceLocationName) return 'inventory_transfer.validator_target_cannot_be_source'.tr();
    _selectedTargetLocationName = value;
    return null;
  }

  String? validateContainer(dynamic value) {
    if (value == null) return 'validation.field_required'.tr();
    if (value is String && value.isEmpty) return 'validation.field_required'.tr();
    if (_selectedContainer == null) return 'validation.invalid_selection'.tr();
    return null;
  }

  // Error Handling & State Update
  void _setError(String? messageKey, [Object? e]) {
    if (e != null) {
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
      for (var product in _productsInContainer) {
        final initialQty = product.currentQuantity;
        final initialQtyText = initialQty == initialQty.truncate()
            ? initialQty.toInt().toString()
            : initialQty.toString();
        _productQuantityControllers[product.key]?.text = initialQtyText;
      }
    }

    notifyListeners();
  }

  Future<void> processScannedData(String field, String data) async {
    final cleanData = data.trim();
    if (cleanData.isEmpty) return;

    switch (field) {
      case 'container':
        _findContainerAndSet(cleanData);
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

  void focusNextProductOrTarget(String currentProductKey) {
    final productKeys = _productQuantityFocusNodes.keys.toList();
    final currentIndex = productKeys.indexOf(currentProductKey);
    if (currentIndex < productKeys.length - 1) {
      _productQuantityFocusNodes[productKeys[currentIndex + 1]]?.requestFocus();
    } else {
      targetLocationFocusNode.requestFocus();
    }
  }

  List<TransferItemDetail> getTransferItems() {
    final List<TransferItemDetail> items = [];

    for (var product in _productsInContainer) {
      final qtyText = _productQuantityControllers[product.key]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;
      if (qty > 0) {
        items.add(TransferItemDetail(
          productKey: product.key, // _key değeri kullanılıyor
          birimKey: product.birimKey, // KRITIK FIX: birimKey eklendi
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          palletId: _selectedMode == AssignmentMode.pallet ? _selectedContainer?.id : null,
          expiryDate: product.expiryDate,
          targetLocationId: _availableTargetLocationsMap[_selectedTargetLocationName],
          targetLocationName: _selectedTargetLocationName!,
        ));
      }
    }
    return items;
  }

  // Product Search State and Methods
  List<ProductInfo> _searchResults = [];
  bool _isSearching = false;
  String _lastSearchQuery = '';

  List<ProductInfo> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String get lastSearchQuery => _lastSearchQuery;

  /// Context-aware product search for transfer operations
  Future<void> searchProductsForTransfer(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _lastSearchQuery = '';
      notifyListeners();
      return;
    }

    if (query == _lastSearchQuery) return; // Avoid duplicate searches

    _isSearching = true;
    _lastSearchQuery = query;
    notifyListeners();

    try {
      // Determine search context based on current state
      int? orderId;
      String? deliveryNoteNumber;
      int? locationId;
      List<String> stockStatuses = [InventoryTransferConstants.stockStatusAvailable, InventoryTransferConstants.stockStatusReceiving];

      if (_selectedOrder != null) {
        // Order-based transfer (putaway from order)
        orderId = _selectedOrder!.id;
        stockStatuses = [InventoryTransferConstants.stockStatusReceiving]; // Only search receiving items for putaway
      } else if (_deliveryNoteNumber != null && _deliveryNoteNumber!.isNotEmpty) {
        // Free receipt transfer (putaway from delivery note)
        deliveryNoteNumber = _deliveryNoteNumber;
        stockStatuses = [InventoryTransferConstants.stockStatusReceiving]; // Only search receiving items for putaway
      } else if (_selectedSourceLocationName != null && _selectedSourceLocationName != InventoryTransferConstants.receivingAreaCode) {
        // Shelf-to-shelf transfer
        locationId = _availableSourceLocationsMap[_selectedSourceLocationName];
        stockStatuses = [InventoryTransferConstants.stockStatusAvailable]; // Only search available items for shelf transfer
      }
      // Otherwise search all available products

      _searchResults = await _repo.searchProductsForTransfer(
        query,
        orderId: orderId,
        deliveryNoteNumber: deliveryNoteNumber,
        locationId: locationId,
        stockStatuses: stockStatuses,
      );
    } catch (e) {
      _setError('inventory_transfer.error_searching_products', e);
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearProductSearch() {
    _searchResults = [];
    _lastSearchQuery = '';
    _isSearching = false;
    notifyListeners();
  }
}
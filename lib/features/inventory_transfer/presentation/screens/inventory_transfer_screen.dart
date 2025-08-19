// lib/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart
import 'package:diapalet/core/constants/warehouse_receiving_mode.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';

class InventoryTransferScreen extends StatefulWidget {
  final PurchaseOrder? selectedOrder;
  final bool isFreePutAway;
  final String? selectedDeliveryNote;

  const InventoryTransferScreen({
    super.key,
    this.selectedOrder,
    this.isFreePutAway = false,
    this.selectedDeliveryNote,
  });

  @override
  State<InventoryTransferScreen> createState() => _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  // --- Sabitler ve Stil Değişkenleri ---
  static const double _gap = 12.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

  // --- State ve Controller'lar ---
  final _formKey = GlobalKey<FormState>();
  late InventoryTransferRepository _repo;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;
  int? _goodsReceiptId; // FIX: To hold the ID for free putaway operations
  bool _isPalletOpening = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;
  bool _isPalletModeAvailable = true;
  bool _isBoxModeAvailable = true;

  Map<String, int?> _availableSourceLocations = {};
  String? _selectedSourceLocationName;
  final _sourceLocationController = TextEditingController();
  final _sourceLocationFocusNode = FocusNode();

  Map<String, int?> _availableTargetLocations = {};
  String? _selectedTargetLocationName;
  final _targetLocationController = TextEditingController();
  final _targetLocationFocusNode = FocusNode();
  bool _isTargetLocationValid = false;
  bool _isSourceLocationValid = false;

  List<dynamic> _availableContainers = [];
  dynamic _selectedContainer;
  final _scannedContainerIdController = TextEditingController();
  final _containerFocusNode = FocusNode();

  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};

  // Product search state
  List<ProductInfo> _productSearchResults = [];
  bool _isSearchingProducts = false;
  final _productSearchController = TextEditingController();
  final _productSearchFocusNode = FocusNode();

  // Barcode service
  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    _sourceLocationFocusNode.addListener(_onFocusChange);
    _containerFocusNode.addListener(_onFocusChange);
    _targetLocationFocusNode.addListener(_onFocusChange);

    // Target location controller listener to reset validity when text changes
    _targetLocationController.addListener(() {
      // Only reset validity if the controller is not being updated programmatically
      // and the text is empty but validation was previously true
      if (_targetLocationController.text.isEmpty &&
          _isTargetLocationValid &&
          _targetLocationFocusNode.hasFocus) {
        setState(() => _isTargetLocationValid = false);
      }
    });

    // Source location controller listener to reset validity when text changes
    _sourceLocationController.addListener(() {
      // Only reset validity if the controller is not being updated programmatically
      // and the text is empty but validation was previously true
      if (_sourceLocationController.text.isEmpty &&
          _isSourceLocationValid &&
          _sourceLocationFocusNode.hasFocus) {
        setState(() => _isSourceLocationValid = false);
      }
    });

    _barcodeService = BarcodeIntentService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _sourceLocationFocusNode.removeListener(_onFocusChange);
    _containerFocusNode.removeListener(_onFocusChange);
    _targetLocationFocusNode.removeListener(_onFocusChange);
    _sourceLocationController.dispose();
    _targetLocationController.dispose();
    _scannedContainerIdController.dispose();
    _productSearchController.dispose();
    _sourceLocationFocusNode.dispose();
    _targetLocationFocusNode.dispose();
    _containerFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _clearProductControllers();
    super.dispose();
  }

  void _onFocusChange() {
    if (_sourceLocationFocusNode.hasFocus && _sourceLocationController.text.isNotEmpty) {
      _sourceLocationController.selection = TextSelection(baseOffset: 0, extentOffset: _sourceLocationController.text.length);
    }
    if (_containerFocusNode.hasFocus && _scannedContainerIdController.text.isNotEmpty) {
      _scannedContainerIdController.selection = TextSelection(baseOffset: 0, extentOffset: _scannedContainerIdController.text.length);
    }
    if (_targetLocationFocusNode.hasFocus && _targetLocationController.text.isNotEmpty) {
      _targetLocationController.selection = TextSelection(baseOffset: 0, extentOffset: _targetLocationController.text.length);
    }
  }

  void _clearProductControllers() {
    _productQuantityControllers.forEach((_, controller) => controller.dispose());
    _productQuantityFocusNodes.forEach((_, focusNode) => focusNode.dispose());
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
  }

  // DÜZELTME: Veri yükleme akışı daha sıralı ve güvenilir hale getirildi.
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoadingInitialData = true);
    try {
      final targetLocationsFuture = _repo.getTargetLocations(excludeReceivingArea: true);
      // FIX: For shelf-to-shelf transfers, exclude receiving area from source locations too
      final sourceLocationsFuture = _repo.getSourceLocations(includeReceivingArea: widget.selectedOrder != null || widget.isFreePutAway);

      final results = await Future.wait([sourceLocationsFuture, targetLocationsFuture]);
      if (!mounted) return;

      _availableSourceLocations = results[0];
      _availableTargetLocations = results[1];

      if (widget.selectedOrder != null || widget.isFreePutAway) {
        _selectedSourceLocationName = '000';
        _sourceLocationController.text = '000';
        _isSourceLocationValid = true; // Mark as valid for order/free putaway
        if (widget.isFreePutAway && widget.selectedDeliveryNote != null) {
          // FIX: Fetch the goods_receipt_id for the free receipt to use in the transfer payload.
          _goodsReceiptId = await _repo.getGoodsReceiptIdByDeliveryNote(widget.selectedDeliveryNote!);
        }
      }

      if (widget.selectedOrder != null) {
        await _checkAvailableModesForOrder();
      } else if (widget.isFreePutAway) {
        await _checkAvailableModesForFreeReceipt();
      }

      if (mounted) {
        // _loadContainersForLocation'ı bekle ve sonra setState çağır.
        await _loadContainersForLocation();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusScope.of(context).requestFocus(
              (widget.selectedOrder != null || widget.isFreePutAway)
                  ? _containerFocusNode
                  : _sourceLocationFocusNode);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('inventory_transfer.error_generic'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _checkAvailableModesForOrder() async {
    if (widget.selectedOrder == null) return;
    await _updateModeAvailability(
      palletCheck: () => _repo.hasOrderReceivedWithPallets(widget.selectedOrder!.id),
      boxCheck: () => _repo.hasOrderReceivedWithProducts(widget.selectedOrder!.id),
    );
  }

  Future<void> _checkAvailableModesForFreeReceipt() async {
    if (!widget.isFreePutAway || widget.selectedDeliveryNote == null) return;
    await _updateModeAvailability(
      palletCheck: () async => (await _repo.getPalletIdsAtLocation(null, stockStatuses: ['receiving'], deliveryNoteNumber: widget.selectedDeliveryNote)).isNotEmpty,
      boxCheck: () async => (await _repo.getProductsAtLocation(null, stockStatuses: ['receiving'], deliveryNoteNumber: widget.selectedDeliveryNote)).isNotEmpty,
    );
  }

  Future<void> _updateModeAvailability({
    required Future<bool> Function() palletCheck,
    required Future<bool> Function() boxCheck,
  }) async {
    try {
      final results = await Future.wait([palletCheck(), boxCheck()]);
      if (mounted) {
        _isPalletModeAvailable = results[0];
        _isBoxModeAvailable = results[1];

        if (!_isModeAvailable(_selectedMode)) {
          _selectedMode = _isPalletModeAvailable ? AssignmentMode.pallet : AssignmentMode.product;
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('inventory_transfer.error_checking_modes'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  bool _isModeAvailable(AssignmentMode mode) {
    switch (mode) {
      case AssignmentMode.pallet:
        return _isPalletModeAvailable;
      case AssignmentMode.product:
      case AssignmentMode.productFromPallet:
        return _isBoxModeAvailable;
    }
  }


  Future<void> _processScannedData(String field, String data) async {
    final cleanData = data.trim();
    if (cleanData.isEmpty) return;

    switch (field) {
      case 'source':
      case 'target':
  final location = await _repo.findLocationByCode(cleanData);
  if (!mounted) return; // Async gap sonrası context kullanımı için güvenlik
        if (location != null) {
          final bool isValidSource = field == 'source' && _availableSourceLocations.containsKey(location.key);
          final bool isValidTarget = field == 'target' && _availableTargetLocations.containsKey(location.key);

          if (isValidSource) {
            _handleSourceSelection(location.key);
          } else if (isValidTarget) {
            _handleTargetSelection(location.key);
          } else {
            // Invalid for this operation: clear previous selection and mark invalid
            if (field == 'source') {
              _selectedSourceLocationName = null;
              _sourceLocationController.text = cleanData;
              setState(() => _isSourceLocationValid = false);
              FocusScope.of(context).requestFocus(_sourceLocationFocusNode);
            }
            if (field == 'target') {
              _selectedTargetLocationName = null;
              _targetLocationController.text = cleanData;
              setState(() => _isTargetLocationValid = false);
              FocusScope.of(context).requestFocus(_targetLocationFocusNode);
            }
            _showErrorSnackBar('inventory_transfer.error_invalid_location_for_operation'
              .tr(namedArgs: {'location': location.key, 'field': field}));
          }
        } else {
          if (field == 'source') {
            _sourceLocationController.text = cleanData;
            setState(() => _isSourceLocationValid = false);
          }
          if (field == 'target') {
            _targetLocationController.text = cleanData;
            setState(() => _isTargetLocationValid = false);
          }
          _showErrorSnackBar('inventory_transfer.error_invalid_location_code'.tr(namedArgs: {'code': cleanData}));
        }
        break;

      case 'container':
        dynamic foundItem;
        if (_selectedMode == AssignmentMode.pallet) {
          foundItem = _availableContainers.cast<String?>().firstWhere((id) => id?.toLowerCase() == cleanData.toLowerCase(), orElse: () => null);
        } else {
          // Product mode - search by barcode only (barcode1)
          foundItem = _availableContainers.where((container) {
            return container.items.any((item) =>
              (item.product.barcode1?.toLowerCase() == cleanData.toLowerCase()));
          }).firstOrNull;
        }

        if (foundItem != null) {
          _handleContainerSelection(foundItem);
        } else {
          _scannedContainerIdController.clear();
          _showErrorSnackBar('inventory_transfer.error_item_not_found'.tr(namedArgs: {'data': cleanData}));
        }
        break;
    }
  }

  // Product search functionality
  Future<void> _searchProductsForTransfer(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _productSearchResults = [];
        _isSearchingProducts = false;
      });
      return;
    }

    setState(() => _isSearchingProducts = true);

    try {
      // Determine search context based on current state
      int? orderId;
      String? deliveryNoteNumber;
      int? locationId;
      List<String> stockStatuses = ['available', 'receiving'];

      if (widget.selectedOrder != null) {
        // Order-based transfer (putaway from order)
        orderId = widget.selectedOrder!.id;
        stockStatuses = ['receiving']; // Only search receiving items for putaway
      } else if (widget.isFreePutAway && widget.selectedDeliveryNote != null) {
        // Free receipt transfer (putaway from delivery note)
        deliveryNoteNumber = widget.selectedDeliveryNote;
        stockStatuses = ['receiving']; // Only search receiving items for putaway
      } else if (_selectedSourceLocationName != null && _selectedSourceLocationName != '000') {
        // Shelf-to-shelf transfer
        locationId = _availableSourceLocations[_selectedSourceLocationName];
        stockStatuses = ['available']; // Only search available items for shelf transfer
      }

      final results = await _repo.searchProductsForTransfer(
        query,
        orderId: orderId,
        deliveryNoteNumber: deliveryNoteNumber,
        locationId: locationId,
        stockStatuses: stockStatuses,
      );

      if (mounted) {
        setState(() {
          _productSearchResults = results;
          _isSearchingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _productSearchResults = [];
          _isSearchingProducts = false;
        });
        _showErrorSnackBar('inventory_transfer.error_searching_products'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  void _selectProductFromSearch(ProductInfo product) {
    // Create a synthetic container from the selected product
    _scannedContainerIdController.text = '${product.name} (${product.stockCode})';
    setState(() {
      _productSearchResults = [];
    });
    
    // Find the matching container in available containers or create one
    final foundContainer = _availableContainers.where((container) {
      if (container is TransferableContainer) {
        return container.items.any((item) => item.product.id == product.id);
      }
      return false;
    }).cast<TransferableContainer?>().firstWhere((element) => element != null, orElse: () => null);
    
    if (foundContainer != null) {
      _handleContainerSelection(foundContainer);
    } else {
      _showErrorSnackBar('inventory_transfer.error_product_not_in_containers'.tr());
    }
  }

  void _handleSourceSelection(String? locationName) {
    if (locationName == null) return;
    // Always apply selection to ensure validity is updated, even if same as before
    setState(() {
      _selectedSourceLocationName = locationName;
      _sourceLocationController.text = locationName;
      _isSourceLocationValid = true; // Mark as valid when location is found
      _resetContainerAndProducts();
      _selectedTargetLocationName = null;
      _targetLocationController.clear();
      _isTargetLocationValid = false; // Reset target validity when source changes
    });
    _loadContainersForLocation();
    _containerFocusNode.requestFocus();
  }

  Future<void> _handleContainerSelection(dynamic selectedItem) async {
    if (selectedItem == null) return;
    setState(() {
      _selectedContainer = selectedItem;
      _scannedContainerIdController.text = selectedItem is TransferableContainer
          ? selectedItem.displayName
          : selectedItem.toString();
    });
    await _fetchContainerContents();
    _targetLocationFocusNode.requestFocus();
  }

  void _handleTargetSelection(String? locationName) {
    if (locationName == null) return;
    setState(() {
      _selectedTargetLocationName = locationName;
      _targetLocationController.text = locationName;
      _isTargetLocationValid = true; // Mark as valid when location is found
    });
    FocusScope.of(context).unfocus();
  }

  // DÜZELTME: Bu fonksiyon artık setState içermiyor, sadece veri getiriyor.
  Future<void> _loadContainersForLocation() async {
    // Serbest mal kabul modu ise konum ID'si null olarak ayarlanır, aksi halde seçilen kaynaktan alınır
    int? locationId;
    if (widget.isFreePutAway) {
      locationId = null;
    } else {
      if (_selectedSourceLocationName == null) return;
      locationId = _availableSourceLocations[_selectedSourceLocationName];
      if (locationId == null) return;
    }

    setState(() {
      _isLoadingContainerContents = true;
      _resetContainerAndProducts();
    });
    try {
      final repo = _repo;
      // Mal kabul alanı (receiving area) kontrolü
      final bool isReceivingArea = widget.isFreePutAway || locationId == 0;

      List<String> statusesToQuery;
      String? deliveryNoteNumber;

      if (widget.selectedOrder != null) {
        statusesToQuery = ['receiving'];
      } else if (widget.isFreePutAway) {
        statusesToQuery = ['receiving'];
        deliveryNoteNumber = widget.selectedDeliveryNote;
      }
      else {
        statusesToQuery = ['available'];
      }

      List<dynamic> containers;
      if (_selectedMode == AssignmentMode.pallet) {
        containers = await repo.getPalletIdsAtLocation(
          isReceivingArea ? null : locationId,
          stockStatuses: statusesToQuery,
          deliveryNoteNumber: deliveryNoteNumber,
        );
      } else {
        // DÜZELTME: Product mode için getTransferableContainers kullan
        final transferableContainers = await repo.getTransferableContainers(
          isReceivingArea ? null : locationId,
          orderId: widget.selectedOrder?.id,
          deliveryNoteNumber: deliveryNoteNumber,
        );
        // Sadece palet olmayan container'ları filtrele
        containers = transferableContainers.where((container) => !container.isPallet).toList();
      }

      if(mounted) {
        setState(() {
          _availableContainers = containers;
        });
      }

    } catch (e) {
      if (mounted) _showErrorSnackBar('inventory_transfer.error_loading_containers'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }

  Future<void> _fetchContainerContents() async {
    final container = _selectedContainer;
    if (container == null) return;

    // Serbest mal kabul modu için konum ID'si null, aksi halde seçilen kaynak lokasyon ID'si
    int? locationId;
    if (widget.isFreePutAway) {
      locationId = null;
    } else {
      if (_selectedSourceLocationName == null) {
        _showErrorSnackBar('inventory_transfer.error_source_location_not_found'.tr());
        return;
      }
      locationId = _availableSourceLocations[_selectedSourceLocationName!];
      if (locationId == null) {
        _showErrorSnackBar('inventory_transfer.error_source_location_not_found'.tr());
        return;
      }
    }

    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
      _clearProductControllers();
    });

    try {
      List<ProductItem> contents = [];
      final stockStatus = (widget.selectedOrder != null || widget.isFreePutAway)
          ? 'receiving'
          : 'available';

      if (_selectedMode == AssignmentMode.pallet && container is String) {
        contents = await _repo.getPalletContents(
          container,
          locationId == 0 ? null : locationId,
          stockStatus: stockStatus,
          siparisId: widget.selectedOrder?.id,
          deliveryNoteNumber: widget.isFreePutAway ? widget.selectedDeliveryNote : null,
        );
      } else if (_selectedMode == AssignmentMode.product && container is TransferableContainer) {
        contents = container.items.map((transferableItem) => ProductItem(
          id: transferableItem.product.id,
          name: transferableItem.product.name,
          productCode: transferableItem.product.stockCode,
          currentQuantity: transferableItem.quantity,
          expiryDate: transferableItem.expiryDate,
        )).toList();
      }

      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        for (var product in contents) {
          final initialQty = product.currentQuantity;
          final initialQtyText = initialQty == initialQty.truncate()
              ? initialQty.toInt().toString()
              : initialQty.toString();
          _productQuantityControllers[product.id] = TextEditingController(text: initialQtyText);
          _productQuantityFocusNodes[product.id] = FocusNode();
        }
      });
    } catch (e, s) {
      debugPrint('Error fetching container contents: $e\n$s');
      if (mounted) _showErrorSnackBar('inventory_transfer.error_loading_content'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showErrorSnackBar('inventory_transfer.error_fill_required_fields'.tr());
      return;
    }

    final List<TransferItemDetail> itemsToTransfer = [];

    for (var product in _productsInContainer) {
      final qtyText = _productQuantityControllers[product.id]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;
      if (qty > 0) {
        itemsToTransfer.add(TransferItemDetail(
          productId: product.id,
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          palletId: _selectedMode == AssignmentMode.pallet ? (_selectedContainer as String) : null,
          targetLocationId: _availableTargetLocations[_selectedTargetLocationName!],
          targetLocationName: _selectedTargetLocationName!,
          expiryDate: product.expiryDate,
        ));
      }
    }

    if (itemsToTransfer.isEmpty) {
      _showErrorSnackBar('inventory_transfer.error_no_items_to_transfer'.tr());
      return;
    }

    final finalOperationMode = _selectedMode == AssignmentMode.pallet
        ? (_isPalletOpening ? AssignmentMode.productFromPallet : AssignmentMode.pallet)
        : AssignmentMode.product;

    final confirm = await _showConfirmationDialog(itemsToTransfer, finalOperationMode);
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getInt('user_id');

    final sourceId = _availableSourceLocations[_selectedSourceLocationName!];
    final targetId = _availableTargetLocations[_selectedTargetLocationName!];

    if ((widget.selectedOrder == null && !widget.isFreePutAway && sourceId == null) || targetId == null || employeeId == null) {
      _showErrorSnackBar('inventory_transfer.error_location_id_not_found'.tr());
      return;
    }

    setState(() => _isSaving = true);
    try {
      final header = TransferOperationHeader(
        employeeId: employeeId,
        operationType: finalOperationMode,
        sourceLocationName: _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
        containerId: (_selectedContainer is String) ? _selectedContainer : (_selectedContainer as TransferableContainer?)?.id,
        transferDate: DateTime.now(),
        siparisId: widget.selectedOrder?.id,
        deliveryNoteNumber: widget.selectedDeliveryNote,
        goodsReceiptId: _goodsReceiptId,
      );

      await _repo.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);

      if (mounted) {
        context.read<SyncService>().uploadPendingOperations();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('inventory_transfer.success_transfer_saved'.tr()),
            backgroundColor: Colors.green,
          ),
        );

        // If it was a free put away, pop with a result to refresh the previous screen
        if(widget.isFreePutAway){
          Navigator.of(context).pop(true);
        } else {
          _resetForm(resetAll: true);
        }
      }
    } catch (e, s) {
      debugPrint('Lokal transfer veya senkronizasyon hatası: $e\n$s');
      if (mounted) _showErrorSnackBar('inventory_transfer.error_saving'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetContainerAndProducts() {
    _scannedContainerIdController.clear();
    _productSearchController.clear();
    _productSearchResults = [];
    _isSearchingProducts = false;
    _productsInContainer = [];
    _selectedContainer = null;
    _clearProductControllers();
    _availableContainers = [];
  }

  void _resetForm({bool resetAll = false}) {
    setState(() {
      _resetContainerAndProducts();
      _selectedTargetLocationName = null;
      _targetLocationController.clear();
      _isTargetLocationValid = false;

      if (resetAll) {
        if (!widget.isFreePutAway && widget.selectedOrder == null) {
          _selectedSourceLocationName = null;
          _sourceLocationController.clear();
          _isSourceLocationValid = false;
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.reset();
        FocusScope.of(context).requestFocus(resetAll ? _sourceLocationFocusNode : _containerFocusNode);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: 'inventory_transfer.title'.tr()),
      bottomNavigationBar: _buildBottomBar(),
      body: SafeArea(
        child: _isLoadingInitialData
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.disabled,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.selectedOrder != null) ...[
                    OrderInfoCard(order: widget.selectedOrder!),
                    const SizedBox(height: _gap),
                  ] else if (widget.isFreePutAway) ...[
                    _buildFreeReceiptInfoCard(),
                    const SizedBox(height: _gap),
                  ],
                  _buildModeSelector(),
                  const SizedBox(height: _gap),
                  if (_selectedMode == AssignmentMode.pallet && !widget.isFreePutAway) ...[
                    _buildPalletOpeningSwitch(),
                    const SizedBox(height: _gap),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _sourceLocationController,
                          focusNode: _sourceLocationFocusNode,
                          enabled: !(widget.selectedOrder != null || widget.isFreePutAway),
                          decoration: _inputDecoration(
                            'inventory_transfer.label_source_location'.tr(),
                            isValid: _isSourceLocationValid,
                          ),
                          validator: (val) => (val == null || val.isEmpty) ? 'inventory_transfer.validator_required_field'.tr() : null,
                          onFieldSubmitted: (value) async {
                            if (value.trim().isNotEmpty) {
                              await _processScannedData('source', value.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: _smallGap),
                      SizedBox(
                        height: 56,
                        child: !(widget.selectedOrder != null || widget.isFreePutAway) ? _QrButton(
                          onTap: () async {
                            final result = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(builder: (context) => const QrScannerScreen())
                            );
                            if (result != null && result.isNotEmpty) {
                              await _processScannedData('source', result);
                            }
                          },
                        ) : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: _gap),
                  _buildContainerOrProductField(),
                  const SizedBox(height: _gap),
                  if (_isLoadingContainerContents)
                    const Padding(padding: EdgeInsets.symmetric(vertical: _gap), child: Center(child: CircularProgressIndicator()))
                  else if (_productsInContainer.isNotEmpty)
                    _buildProductsList(),
                  const SizedBox(height: _gap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _targetLocationController,
                          focusNode: _targetLocationFocusNode,
                          decoration: _inputDecoration(
                            'inventory_transfer.label_target_location'.tr(),
                            isValid: _isTargetLocationValid,
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'inventory_transfer.validator_required_field'.tr();
                            if (val == _sourceLocationController.text) {
                              return 'inventory_transfer.validator_target_cannot_be_source'.tr();
                            }
                            return null;
                          },
                          onFieldSubmitted: (value) async {
                            if (value.trim().isNotEmpty) {
                              await _processScannedData('target', value.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: _smallGap),
                      SizedBox(
                        height: 56,
                        child: _QrButton(
                          onTap: () async {
                            final result = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(builder: (context) => const QrScannerScreen())
                            );
                            if (result != null && result.isNotEmpty) {
                              await _processScannedData('target', result);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: _gap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFreeReceiptInfoCard() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primaryContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'inventory_transfer.delivery_note_info_title'.tr(),
              style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.selectedDeliveryNote ?? 'common_labels.not_available'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Barcode Handling ---
  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final first = await _barcodeService.getInitialBarcode();
      if (first != null && first.isNotEmpty) _handleBarcode(first);
    } catch(e) {
      debugPrint("Initial barcode error: $e");
    }

    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _showErrorSnackBar('common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()})));
  }

  void _handleBarcode(String code) {
    if (!mounted) return;

    if (_sourceLocationFocusNode.hasFocus) {
      _processScannedData('source', code);
    } else if (_containerFocusNode.hasFocus) {
      _processScannedData('container', code);
    } else if (_targetLocationFocusNode.hasFocus) {
      _processScannedData('target', code);
    } else {
      if (_selectedSourceLocationName == null) {
        _sourceLocationFocusNode.requestFocus();
        _processScannedData('source', code);
      } else if (_selectedContainer == null) {
        _containerFocusNode.requestFocus();
        _processScannedData('container', code);
      } else {
        _targetLocationFocusNode.requestFocus();
        _processScannedData('target', code);
      }
    }
  }

  Widget _buildModeSelector() {
    return FutureBuilder<bool>(
      future: _shouldShowModeSelector(),
      builder: (context, snapshot) {
        // Eğer warehouse mixed mode değilse, mode selector'ü gösterme
        if (snapshot.hasData && !snapshot.data!) {
          return const SizedBox.shrink();
        }

        return Center(
          child: SegmentedButton<AssignmentMode>(
            segments: [
              ButtonSegment(
                  value: AssignmentMode.pallet,
                  label: Text('inventory_transfer.mode_pallet'.tr()),
                  icon: const Icon(Icons.pallet),
                  enabled: _isPalletModeAvailable
              ),
              ButtonSegment(
                  value: AssignmentMode.product,
                  label: Text('inventory_transfer.mode_product'.tr()),
                  icon: const Icon(Icons.inventory_2_outlined),
                  enabled: _isBoxModeAvailable
              ),
            ],
            selected: {_selectedMode},
        onSelectionChanged: (newSelection) {
          final newMode = newSelection.first;
          if (_isModeAvailable(newMode)) {
            setState(() {
              _selectedMode = newMode;
              _isPalletOpening = false;

              // Clear all input fields and validity flags when switching between pallet/product modes
              _sourceLocationController.clear();
              _isSourceLocationValid = false;
              _scannedContainerIdController.clear();
              _productSearchController.clear();
              _productSearchResults = [];
              _isSearchingProducts = false;
              _clearProductControllers();
              _productsInContainer.clear();
              _targetLocationController.clear();
              _isTargetLocationValid = false;

              // Reset form state and load containers
              _resetForm(resetAll: false);
              if (_selectedSourceLocationName != null) {
                _loadContainersForLocation();
              } else {
                _sourceLocationFocusNode.requestFocus();
              }
            });
          }
        },
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.comfortable,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
          ),
        );
      },
    );
  }

  /// Warehouse mode'unu SharedPreferences'dan okuyup mode selector gösterilmeli mi kontrol eder
  Future<bool> _shouldShowModeSelector() async {
    final prefs = await SharedPreferences.getInstance();
    final receivingMode = prefs.getInt('receiving_mode') ?? 2; // Default: mixed
    final warehouseMode = WarehouseReceivingMode.fromValue(receivingMode);
    return warehouseMode == WarehouseReceivingMode.mixed;
  }

  Widget _buildPalletOpeningSwitch() {
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: _borderRadius,
      color: Theme.of(context).colorScheme.secondary.withAlpha(26),
      child: SwitchListTile(
        title: Text('inventory_transfer.label_break_pallet'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
        value: _isPalletOpening,
        onChanged: _productsInContainer.isNotEmpty ? (bool value) {
          setState(() {
            _isPalletOpening = value;
            if (!value) {
              for (var product in _productsInContainer) {
                final initialQty = product.currentQuantity;
                final initialQtyText = initialQty == initialQty.truncate()
                    ? initialQty.toInt().toString()
                    : initialQty.toString();
                _productQuantityControllers[product.id]?.text = initialQtyText;
              }
            }
          });
        } : null,
        secondary: const Icon(Icons.inventory_2_outlined),
  // Flutter M3'te activeThumbColor kaldırıldı; yerine activeColor/thumbColor kullanılır.
  activeColor: Theme.of(context).colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
      ),
    );
  }



  Widget _buildProductsList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: _borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
            child: Text(
              'inventory_transfer.content_title'.tr(namedArgs: {'containerId': _scannedContainerIdController.text}),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(_smallGap),
            itemCount: _productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(height: _smallGap, indent: 16, endIndent: 16, thickness: 0.2),
            itemBuilder: (context, index) {
              final product = _productsInContainer[index];
              final controller = _productQuantityControllers[product.id]!;
              final focusNode = _productQuantityFocusNodes[product.id]!;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: Theme.of(context).textTheme.bodyLarge, overflow: TextOverflow.ellipsis),
                          Text(
                              'inventory_transfer.label_current_quantity'.tr(
                                  namedArgs: {'productCode': product.productCode, 'quantity': product.currentQuantity.toStringAsFixed(product.currentQuantity.truncateToDouble() == product.currentQuantity ? 0 : 2)}),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !(_selectedMode == AssignmentMode.pallet && !_isPalletOpening),
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        decoration: _inputDecoration('inventory_transfer.label_quantity'.tr()),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'inventory_transfer.validator_required'.tr();
                          final qty = double.tryParse(value);
                          if (qty == null) return 'inventory_transfer.validator_invalid'.tr();
                          if (qty > product.currentQuantity + 0.001) return 'inventory_transfer.validator_max'.tr();
                          if (qty < 0) return 'inventory_transfer.validator_negative'.tr();
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          final productIds = _productQuantityFocusNodes.keys.toList();
                          final currentIndex = productIds.indexOf(product.id);
                          if (currentIndex < productIds.length - 1) {
                            _productQuantityFocusNodes[productIds[currentIndex + 1]]?.requestFocus();
                          } else {
                            _targetLocationFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_isLoadingInitialData) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ElevatedButton.icon(
          onPressed: _isSaving || _productsInContainer.isEmpty ? null : _onConfirmSave,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: FittedBox(child: Text('inventory_transfer.button_save'.tr())),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true, bool isValid = false}) {
    final theme = Theme.of(context);
    final borderColor = isValid ? Colors.green : theme.dividerColor;
    final focusedBorderColor = isValid ? Colors.green : theme.colorScheme.primary;
    final borderWidth = isValid ? 2.5 : 1.0; // Kalın yeşil border

    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.disabledColor.withAlpha(20),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: borderColor, width: borderWidth)),
      focusedBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: focusedBorderColor, width: borderWidth + 0.5)),
      errorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 11),
    );
  }  Future<bool?> _showConfirmationDialog(List<TransferItemDetail> items, AssignmentMode mode) async {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _InventoryConfirmationPage(
          items: items,
          mode: mode,
          sourceLocationName: _selectedSourceLocationName ?? '',
          targetLocationName: _selectedTargetLocationName ?? '',
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    debugPrint("Snackbar Error: $message");
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }

  Widget _buildContainerOrProductField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _selectedMode == AssignmentMode.product ? _productSearchController : _scannedContainerIdController,
                focusNode: _selectedMode == AssignmentMode.product ? _productSearchFocusNode : _containerFocusNode,
                decoration: _inputDecoration(
                  _selectedMode == AssignmentMode.pallet ? 'inventory_transfer.label_pallet'.tr() : 'inventory_transfer.label_product'.tr(),
                  suffixIcon: _selectedMode == AssignmentMode.product && _isSearchingProducts
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'inventory_transfer.validator_required_field'.tr() : null,
                onChanged: _selectedMode == AssignmentMode.product 
                    ? (value) {
                        if (value.isEmpty) {
                          setState(() {
                            _productSearchResults = [];
                          });
                        } else {
                          _searchProductsForTransfer(value);
                        }
                      }
                    : null,
                onFieldSubmitted: (value) async {
                  if (value.trim().isNotEmpty) {
                    if (_selectedMode == AssignmentMode.product && _productSearchResults.isNotEmpty) {
                      _selectProductFromSearch(_productSearchResults.first);
                    } else {
                      await _processScannedData('container', value.trim());
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: _smallGap),
            SizedBox(
              height: 56,
              child: _QrButton(
                onTap: () async {
                  final result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (context) => const QrScannerScreen())
                  );
                  if (result != null && result.isNotEmpty) {
                    if (_selectedMode == AssignmentMode.product) {
                      _productSearchController.text = result;
                      _searchProductsForTransfer(result);
                    } else {
                      await _processScannedData('container', result);
                    }
                  }
                },
              ),
            ),
          ],
        ),
        // Product search results dropdown
        if (_selectedMode == AssignmentMode.product && _productSearchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: _borderRadius,
            ),
            child: Column(
              children: _productSearchResults.take(5).map((product) {
                return ListTile(
                  dense: true,
                  title: Text(
                    product.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    'Barkod: ${product.productBarcode ?? 'N/A'} | Stok Kodu: ${product.stockCode}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () {
                    _selectProductFromSearch(product);
                    _productSearchFocusNode.unfocus();
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;

  const _QrButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconSize = constraints.maxHeight * 0.6;
            return Icon(Icons.qr_code_scanner, size: iconSize);
          },
        ),
      ),
    );
  }
}

class _InventoryConfirmationPage extends StatelessWidget {
  final List<TransferItemDetail> items;
  final AssignmentMode mode;
  final String sourceLocationName;
  final String targetLocationName;

  const _InventoryConfirmationPage({
    required this.items,
    required this.mode,
    required this.sourceLocationName,
    required this.targetLocationName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('inventory_transfer.dialog_confirm_transfer_title'.tr(namedArgs: {'mode': mode.apiName})),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            'inventory_transfer.dialog_confirm_transfer_body'.tr(
              namedArgs: {'source': sourceLocationName, 'target': targetLocationName},
            ),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const Divider(height: 24),
          ...items.map((item) => ListTile(
            title: Text(item.productName),
            subtitle: Text(item.productCode),
            trailing: Text(
              item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 2),
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('inventory_transfer.dialog_button_confirm'.tr()),
          ),
        ),
      ),
    );
  }
}

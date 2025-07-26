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
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';

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
  final _deliveryNoteController = TextEditingController();
  final _deliveryNoteFocusNode = FocusNode();
  String? _selectedDeliveryNote;
  late InventoryTransferRepository _repo;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;
  bool _isPalletOpening = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;
  bool _isPalletModeAvailable = true;
  bool _isBoxModeAvailable = true;

  Map<String, int> _availableSourceLocations = {};
  String? _selectedSourceLocationName;
  final _sourceLocationController = TextEditingController();
  final _sourceLocationFocusNode = FocusNode();

  Map<String, int> _availableTargetLocations = {};
  String? _selectedTargetLocationName;
  final _targetLocationController = TextEditingController();
  final _targetLocationFocusNode = FocusNode();

  List<dynamic> _availableContainers = [];
  dynamic _selectedContainer;
  final _scannedContainerIdController = TextEditingController();
  final _containerFocusNode = FocusNode();

  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};

  // Barcode service
  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    _sourceLocationFocusNode.addListener(_onFocusChange);
    _containerFocusNode.addListener(_onFocusChange);
    _targetLocationFocusNode.addListener(_onFocusChange);
    _barcodeService = BarcodeIntentService();

    // Set selected delivery note if provided
    if (widget.selectedDeliveryNote != null) {
      _selectedDeliveryNote = widget.selectedDeliveryNote;
      _deliveryNoteController.text = widget.selectedDeliveryNote!;
    }

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
    _sourceLocationFocusNode.dispose();
    _targetLocationFocusNode.dispose();
    _containerFocusNode.dispose();
    _clearProductControllers();
    _deliveryNoteController.dispose();
    _deliveryNoteFocusNode.dispose();
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

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoadingInitialData = true);
    try {
      late Future<Map<String, int>> sourceLocationsFuture;
      late Future<Map<String, int>> targetLocationsFuture;

      if (widget.selectedOrder != null) {
        // Put away from order: Kaynak sadece mal kabul alanı (000), hedef tüm raflar
        sourceLocationsFuture = _repo.getSourceLocations(includeReceivingArea: true);
        targetLocationsFuture = _repo.getTargetLocations(excludeReceivingArea: true);
      } else if (widget.isFreePutAway) {
        // Put away from free receipt: Kaynak sadece mal kabul alanı (000), hedef tüm raflar
        sourceLocationsFuture = _repo.getSourceLocations(includeReceivingArea: true);
        targetLocationsFuture = _repo.getTargetLocations(excludeReceivingArea: true);
      } else {
        // Shelf to shelf: Kaynak ve hedef tüm raflar (000 hariç)
        sourceLocationsFuture = _repo.getSourceLocations(includeReceivingArea: false);
        targetLocationsFuture = _repo.getTargetLocations(excludeReceivingArea: true);
      }

      final results = await Future.wait([
        sourceLocationsFuture,
        targetLocationsFuture,
      ]);
      if (!mounted) return;
      setState(() {
        _availableSourceLocations = results[0];
        _availableTargetLocations = results[1];

        // If this is order-based transfer or free putaway, automatically set source to goods receiving area
        if (widget.selectedOrder != null || widget.isFreePutAway) {
          _selectedSourceLocationName = '000';
          _sourceLocationController.text = '000';
          if (!widget.isFreePutAway) {
            _loadContainersForLocation();
          }
        }
      });

      // For order-based putaway, check available modes
      if (widget.selectedOrder != null) {
        await _checkAvailableModes();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.selectedOrder != null || widget.isFreePutAway) {
          // For order-based transfer or free putaway, focus on container selection
          if (widget.isFreePutAway) {
            // For free putaway, focus on delivery note first
            FocusScope.of(context).requestFocus(_deliveryNoteFocusNode);
          } else {
            FocusScope.of(context).requestFocus(_containerFocusNode);
          }
        } else {
          // For shelf to shelf, focus on source location
          FocusScope.of(context).requestFocus(_sourceLocationFocusNode);
        }
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('inventory_transfer.error_generic'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _checkAvailableModes() async {
    if (widget.selectedOrder == null) return;

    try {
      final results = await Future.wait([
        _repo.hasOrderReceivedWithPallets(widget.selectedOrder!.id),
        _repo.hasOrderReceivedWithBoxes(widget.selectedOrder!.id),
      ]);

      if (mounted) {
        setState(() {
          _isPalletModeAvailable = results[0];
          _isBoxModeAvailable = results[1];

          // If current mode is not available, switch to available one
          if (!_isPalletModeAvailable && _selectedMode == AssignmentMode.pallet) {
            _selectedMode = AssignmentMode.box;
          } else if (!_isBoxModeAvailable && _selectedMode == AssignmentMode.box) {
            _selectedMode = AssignmentMode.pallet;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('inventory_transfer.error_checking_modes'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  Future<void> _processScannedData(String field, String data) async {
    final cleanData = data.trim();
    if (cleanData.isEmpty) return;

    switch (field) {
      case 'source':
      case 'target':
        final location = await _repo.findLocationByCode(cleanData);
        if (location != null) {
          final bool isValidSource = field == 'source' && _availableSourceLocations.containsKey(location.key);
          final bool isValidTarget = field == 'target' && _availableTargetLocations.containsKey(location.key);

          if (isValidSource) {
            _handleSourceSelection(location.key);
          } else if (isValidTarget) {
            _handleTargetSelection(location.key);
          } else {
            _showErrorSnackBar('inventory_transfer.error_invalid_location_for_operation'.tr(namedArgs: {'location': location.key, 'field': field}));
          }
        } else {
          if (field == 'source') _sourceLocationController.clear();
          if (field == 'target') _targetLocationController.clear();
          _showErrorSnackBar('inventory_transfer.error_invalid_location_code'.tr(namedArgs: {'code': cleanData}));
        }
        break;

      case 'container':
        dynamic foundItem;
        if (_selectedMode == AssignmentMode.pallet) {
          foundItem = _availableContainers.cast<String?>().firstWhere((id) => id?.toLowerCase() == cleanData.toLowerCase(), orElse: () => null);
        } else {
          foundItem = _availableContainers.cast<BoxItem?>().firstWhere((box) => box?.productCode.toLowerCase() == cleanData.toLowerCase() || box?.barcode1?.toLowerCase() == cleanData.toLowerCase(), orElse: () => null);
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

  void _handleSourceSelection(String? locationName) {
    if (locationName == null || locationName == _selectedSourceLocationName) return;
    setState(() {
      _selectedSourceLocationName = locationName;
      _sourceLocationController.text = locationName;
      _resetContainerAndProducts();
      _selectedTargetLocationName = null;
      _targetLocationController.clear();
    });
    _loadContainersForLocation();
    _containerFocusNode.requestFocus();
  }

  Future<void> _handleContainerSelection(dynamic selectedItem) async {
    if (selectedItem == null) return;
    setState(() {
      _selectedContainer = selectedItem;
      _scannedContainerIdController.text = (selectedItem is BoxItem)
          ? '${selectedItem.productName} (${selectedItem.productCode})'
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
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _loadContainersForLocation() async {
    if (_selectedSourceLocationName == null) return;
    final locationId = _availableSourceLocations[_selectedSourceLocationName];
    if (locationId == null) return;

    setState(() {
      _isLoadingContainerContents = true;
      _resetContainerAndProducts();
    });
    try {
      final repo = _repo as dynamic; // Cast to access helper methods
      final bool isReceivingArea = locationId == 0;

      List<String> statusesToQuery;
      String? deliveryNoteNumber;

      if (widget.selectedOrder != null) {
        // Rafa Kaldırma Modu: Sadece 'receiving' statüsündeki ürünler.
        statusesToQuery = ['receiving'];
      } else if (widget.isFreePutAway) {
        // Serbest Mal Kabulden Rafa Kaldırma: 'receiving' statüsündeki ve fiş numarası eşleşenler
        statusesToQuery = ['receiving'];
        deliveryNoteNumber = _selectedDeliveryNote;
      }
      else {
        // Serbest Transfer Modu: Sadece 'available' statüsündeki ürünler gösterilir
        statusesToQuery = ['available'];
      }

      if (_selectedMode == AssignmentMode.pallet) {
        _availableContainers = await repo.getPalletIdsAtLocation(
          isReceivingArea ? null : locationId,
          stockStatuses: statusesToQuery,
          deliveryNoteNumber: deliveryNoteNumber,
        );
      } else {
        _availableContainers = await repo.getBoxesAtLocation(
          isReceivingArea ? null : locationId,
          stockStatuses: statusesToQuery,
          deliveryNoteNumber: deliveryNoteNumber,
        );
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

    final locationId = _availableSourceLocations[_selectedSourceLocationName!];
    if (locationId == null) {
      _showErrorSnackBar('inventory_transfer.error_source_location_not_found'.tr());
      return;
    }

    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
      _clearProductControllers();
    });

    try {
      List<ProductItem> contents = [];
      final stockStatus = widget.selectedOrder != null ? 'receiving' : 'available';

      if (_selectedMode == AssignmentMode.pallet && container is String) {
        contents = await _repo.getPalletContents(
          container,
          locationId == 0 ? null : locationId,
          stockStatus: stockStatus,
          siparisId: widget.selectedOrder?.id,
        );
      } else if (_selectedMode == AssignmentMode.box && container is BoxItem) {
        contents = [ProductItem.fromBoxItem(container)];
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
        ));
      }
    }

    if (itemsToTransfer.isEmpty) {
      _showErrorSnackBar('inventory_transfer.error_no_items_to_transfer'.tr());
      return;
    }

    final finalOperationMode = _selectedMode == AssignmentMode.pallet
        ? (_isPalletOpening ? AssignmentMode.boxFromPallet : AssignmentMode.pallet)
        : AssignmentMode.box;

    final confirm = await _showConfirmationDialog(itemsToTransfer, finalOperationMode);
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getInt('user_id');

    final sourceId = _availableSourceLocations[_selectedSourceLocationName!];
    final targetId = _availableTargetLocations[_selectedTargetLocationName!];

    if (sourceId == null || targetId == null || employeeId == null) {
      _showErrorSnackBar('inventory_transfer.error_location_id_not_found'.tr());
      return;
    }

    setState(() => _isSaving = true);
    // Önce lokal kaydı dene
    try {
      final header = TransferOperationHeader(
        employeeId: employeeId,
        operationType: finalOperationMode,
        sourceLocationName: _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
        containerId: (_selectedContainer is String) ? _selectedContainer : (_selectedContainer as BoxItem?)?.productCode,
        transferDate: DateTime.now(),
        siparisId: widget.selectedOrder?.id,
        deliveryNoteNumber: _deliveryNoteController.text.isNotEmpty ? _deliveryNoteController.text : null,
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
        _resetForm(resetAll: true);
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

      if (resetAll) {
        _selectedSourceLocationName = null;
        _sourceLocationController.clear();
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
                  ],
                  _buildModeSelector(),
                  const SizedBox(height: _gap),
                  if (widget.isFreePutAway && widget.selectedDeliveryNote != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_long, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'inventory_transfer.selected_delivery_note'.tr(),
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                  Text(
                                    widget.selectedDeliveryNote!,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: _gap),
                  ],
                  if (_selectedMode == AssignmentMode.pallet) ...[
                    _buildPalletOpeningSwitch(),
                    const SizedBox(height: _gap),
                  ],
                  _buildHybridDropdownWithQr<String>(
                    controller: _sourceLocationController,
                    focusNode: _sourceLocationFocusNode,
                    label: 'inventory_transfer.label_source_location'.tr(),
                    fieldIdentifier: 'source',
                    items: _availableSourceLocations.keys.toList(),
                    itemToString: (item) => item,
                    onItemSelected: _handleSourceSelection,
                    filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                    validator: (val) => (val == null || val.isEmpty) ? 'inventory_transfer.validator_required_field'.tr() : null,
                  ),
                  const SizedBox(height: _gap),
                  _buildHybridDropdownWithQr<dynamic>(
                    controller: _scannedContainerIdController,
                    focusNode: _containerFocusNode,
                    label: _selectedMode == AssignmentMode.pallet ? 'inventory_transfer.label_pallet'.tr() : 'inventory_transfer.label_product'.tr(),
                    fieldIdentifier: 'container',
                    items: _availableContainers,
                    itemToString: (item) {
                      if (item is String) return item;
                      if (item is BoxItem) return '${item.productName} (${item.productCode})';
                      return '';
                    },
                    onItemSelected: _handleContainerSelection,
                    filterCondition: (item, query) {
                      final lowerQuery = query.toLowerCase();
                      if (item is String) return item.toLowerCase().contains(lowerQuery);
                      if (item is BoxItem) {
                        return item.productName.toLowerCase().contains(lowerQuery) ||
                            item.productCode.toLowerCase().contains(lowerQuery) ||
                            (item.barcode1?.toLowerCase().contains(lowerQuery) ?? false);
                      }
                      return false;
                    },
                    validator: (val) => (val == null || val.isEmpty) ? 'inventory_transfer.validator_required_field'.tr() : null,
                  ),
                  const SizedBox(height: _gap),
                  if (_isLoadingContainerContents)
                    const Padding(padding: EdgeInsets.symmetric(vertical: _gap), child: Center(child: CircularProgressIndicator()))
                  else if (_productsInContainer.isNotEmpty)
                    _buildProductsList(),
                  const SizedBox(height: _gap),
                  _buildHybridDropdownWithQr<String>(
                    controller: _targetLocationController,
                    focusNode: _targetLocationFocusNode,
                    label: 'inventory_transfer.label_target_location'.tr(),
                    fieldIdentifier: 'target',
                    items: _availableTargetLocations.keys.toList(),
                    itemToString: (item) => item,
                    onItemSelected: _handleTargetSelection,
                    filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'inventory_transfer.validator_required_field'.tr();
                      if (val == _sourceLocationController.text) {
                        return 'inventory_transfer.validator_target_cannot_be_source'.tr();
                      }
                      return null;
                    },
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
      // Aktif bir odak yoksa, mantıksal bir sıra izle
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
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: [
          ButtonSegment(
              value: AssignmentMode.pallet,
              label: Text('inventory_transfer.mode_pallet'.tr()),
              icon: const Icon(Icons.pallet),
              enabled: widget.selectedOrder != null ? _isPalletModeAvailable : true),
          ButtonSegment(
              value: AssignmentMode.box,
              label: Text('inventory_transfer.mode_box'.tr()),
              icon: const Icon(Icons.inventory_2_outlined),
              enabled: widget.selectedOrder != null ? _isBoxModeAvailable : true),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (newSelection) {
          final newMode = newSelection.first;

          // Check if the new mode is available for orders
          if (widget.selectedOrder != null) {
            if (newMode == AssignmentMode.pallet && !_isPalletModeAvailable) return;
            if (newMode == AssignmentMode.box && !_isBoxModeAvailable) return;
          }

          setState(() {
            _selectedMode = newMode;
            _isPalletOpening = false;
            // Keep source location, but reset container and target.
            _resetForm(resetAll: false);

            // Reload containers for the new mode if a source location is selected.
            if (_selectedSourceLocationName != null) {
              _loadContainersForLocation();
            } else {
              // If no source is selected, ensure focus is on the source field.
              _sourceLocationFocusNode.requestFocus();
            }
          });
        },
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.comfortable,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
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
        activeThumbColor: Theme.of(context).colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
      ),
    );
  }

  Widget _buildHybridDropdownWithQr<T>({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String fieldIdentifier,
    required List<T> items,
    required String Function(T item) itemToString,
    required void Function(T? item) onItemSelected,
    required bool Function(T item, String query) filterCondition,
    required FormFieldValidator<String>? validator,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Hata mesajı için hizalama
      children: [
        Expanded(
          child: TextFormField(
            readOnly: true,
            controller: controller,
            focusNode: focusNode,
            decoration: _inputDecoration(
              label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            onTap: () async {
              FocusScope.of(context).unfocus();

              final T? selectedItem = await _showSearchableDropdownDialog<T>(
                title: label,
                items: items,
                itemToString: itemToString,
                filterCondition: filterCondition,
              );
              if (selectedItem != null) {
                onItemSelected(selectedItem);
              }
            },
            validator: validator,
          ),
        ),
        const SizedBox(width: _smallGap),
        SizedBox(
          height: 56, // TextFormField ile aynı yükseklik
          child: _QrButton(
            onTap: () async {
              final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
              if (result != null && result.isNotEmpty) {
                _processScannedData(fieldIdentifier, result);
              }
            },
          ),
        ),
      ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ElevatedButton.icon(
        onPressed: _isSaving || _productsInContainer.isEmpty ? null : _onConfirmSave,
        icon: _isSaving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle_outline),
        label: FittedBox(child: Text('inventory_transfer.button_save'.tr())),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.disabledColor.withAlpha(20),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.dividerColor)),
      focusedBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 11),
    );
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
  }) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _InventorySearchPage<T>(
          title: title,
          items: items,
          itemToString: itemToString,
          filterCondition: filterCondition,
        ),
      ),
    );
  }

  Future<bool?> _showConfirmationDialog(List<TransferItemDetail> items, AssignmentMode mode) async {
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

class _InventorySearchPage<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemToString;
  final bool Function(T, String) filterCondition;

  const _InventorySearchPage({
    required this.title,
    required this.items,
    required this.itemToString,
    required this.filterCondition,
  });

  @override
  State<_InventorySearchPage<T>> createState() => _InventorySearchPageState<T>();
}

class _InventorySearchPageState<T> extends State<_InventorySearchPage<T>> {
  String _searchQuery = '';
  late List<T> _filteredItems;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query;
      _filteredItems = widget.items
          .where((item) => widget.filterCondition(item, _searchQuery))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.appBarTheme.titleTextStyle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'inventory_transfer.dialog_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: _filterItems,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(child: Text('inventory_transfer.dialog_search_no_results'.tr()))
                  : ListView.separated(
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return ListTile(
                    title: Text(widget.itemToString(item)),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 24.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('inventory_transfer.dialog_button_confirm'.tr()),
        ),
      ),
    );
  }
}

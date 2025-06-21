// lib/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';

class InventoryTransferScreen extends StatefulWidget {
  const InventoryTransferScreen({super.key});

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

  AssignmentMode _selectedMode = AssignmentMode.pallet;

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

  @override
  void initState() {
    super.initState();
    _sourceLocationFocusNode.addListener(_onFocusChange);
    _containerFocusNode.addListener(_onFocusChange);
    _targetLocationFocusNode.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    // HATA DÜZELTMESİ: Bu satır, widget ağaçtan kaldırıldığında çökme hatasına neden oluyordu.
    // FocusNode'ların dispose edilmesi yeterlidir.
    // FocusScope.of(context).unfocus();

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
      final results = await Future.wait([
        _repo.getSourceLocations(),
        _repo.getTargetLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _availableSourceLocations = results[0];
        _availableTargetLocations = results[1];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_sourceLocationFocusNode);
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('inventory_transfer.error_generic'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _processScannedData(String field, String data) async {
    switch (field) {
      case 'source':
        final locationName = _availableSourceLocations.keys.firstWhere((k) => k.toLowerCase() == data.toLowerCase(), orElse: () => '');
        if (locationName.isNotEmpty) {
          _handleSourceSelection(locationName);
        } else {
          _sourceLocationController.clear();
          _showErrorSnackBar('inventory_transfer.error_invalid_source_location'.tr(namedArgs: {'data': data}));
        }
        break;
      case 'container':
        dynamic foundItem;
        if (_selectedMode == AssignmentMode.pallet) {
          foundItem = _availableContainers.cast<String?>().firstWhere((id) => id?.toLowerCase() == data.toLowerCase(), orElse: () => null);
        } else {
          foundItem = _availableContainers.cast<BoxItem?>().firstWhere((box) => box?.productCode.toLowerCase() == data.toLowerCase() || box?.barcode1?.toLowerCase() == data.toLowerCase(), orElse: () => null);
        }

        if (foundItem != null) {
          _handleContainerSelection(foundItem);
        } else {
          _scannedContainerIdController.clear();
          _showErrorSnackBar('inventory_transfer.error_item_not_found'.tr(namedArgs: {'data': data}));
        }
        break;
      case 'target':
        final locationName = _availableTargetLocations.keys.firstWhere((k) => k.toLowerCase() == data.toLowerCase(), orElse: () => '');
        if (locationName.isNotEmpty) {
          _handleTargetSelection(locationName);
        } else {
          _targetLocationController.clear();
          _showErrorSnackBar('inventory_transfer.error_invalid_target_location'.tr(namedArgs: {'data': data}));
        }
        break;
    }
  }

  void _handleSourceSelection(String? locationName) {
    if (locationName == null || locationName == _selectedSourceLocationName) return;
    setState(() {
      _selectedSourceLocationName = locationName;
      _sourceLocationController.text = locationName;
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
      if (_selectedMode == AssignmentMode.pallet) {
        _availableContainers = await _repo.getPalletIdsAtLocation(locationId);
      } else {
        _availableContainers = await _repo.getBoxesAtLocation(locationId);
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

    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
      _clearProductControllers();
    });

    try {
      List<ProductItem> contents = [];
      if (_selectedMode == AssignmentMode.pallet && container is String) {
        contents = await _repo.getPalletContents(container);
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
    } catch (e) {
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
    bool isFullPalletTransfer = _selectedMode == AssignmentMode.pallet;

    for (var product in _productsInContainer) {
      final qtyText = _productQuantityControllers[product.id]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;
      if (qty > 0) {
        if (qty != product.currentQuantity) {
          isFullPalletTransfer = false;
        }
        itemsToTransfer.add(TransferItemDetail(
          productId: product.id,
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          palletId: _selectedMode == AssignmentMode.pallet ? (_selectedContainer as String) : null,
          sourcePalletBarcode: _selectedMode == AssignmentMode.pallet ? (_selectedContainer as String) : null,
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
        ? (isFullPalletTransfer ? AssignmentMode.pallet : AssignmentMode.box_from_pallet)
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
    try {
      final header = TransferOperationHeader(
        employeeId: employeeId,
        operationType: finalOperationMode,
        sourceLocationName: _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
        containerId: (_selectedContainer is String) ? _selectedContainer : (_selectedContainer as BoxItem?)?.productCode,
        transferDate: DateTime.now(),
      );
      await _repo.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);
      if (mounted) {
        _showSuccessSnackBar('inventory_transfer.success_transfer_saved'.tr());
        _resetForm(resetAll: true);
      }
    } catch (e) {
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
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: SharedAppBar(title: 'inventory_transfer.title'.tr()),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(),
      body: SafeArea(
        child: _isLoadingInitialData
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModeSelector(),
                  const SizedBox(height: _gap),
                  _buildHybridDropdownWithQr<String>(
                    controller: _sourceLocationController,
                    focusNode: _sourceLocationFocusNode,
                    label: 'inventory_transfer.label_source_location'.tr(),
                    fieldIdentifier: 'source',
                    items: _availableSourceLocations.keys.toList(),
                    itemToString: (item) => item,
                    onItemSelected: _handleSourceSelection,
                    filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
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

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: [
          ButtonSegment(
              value: AssignmentMode.pallet,
              label: Text('inventory_transfer.mode_pallet'.tr()),
              icon: const Icon(Icons.pallet)),
          ButtonSegment(
              value: AssignmentMode.box,
              label: Text('inventory_transfer.mode_box'.tr()),
              icon: const Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (newSelection) {
          setState(() {
            _selectedMode = newSelection.first;
            _resetContainerAndProducts();
            if (_selectedSourceLocationName != null) {
              _loadContainersForLocation();
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

  Widget _buildHybridDropdownWithQr<T>({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String fieldIdentifier,
    required List<T> items,
    required String Function(T item) itemToString,
    required void Function(T? item) onItemSelected,
    required bool Function(T item, String query) filterCondition,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            decoration: _inputDecoration(
              label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) {
                _processScannedData(fieldIdentifier, value);
              }
            },
            onTap: () async {
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
            validator: (val) {
              if (val == null || val.isEmpty) return 'inventory_transfer.validator_required_field'.tr();
              if (fieldIdentifier == 'target' && val == _sourceLocationController.text) {
                return 'inventory_transfer.validator_target_cannot_be_source'.tr();
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(
          onTap: () async {
            final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
            if (result != null && result.isNotEmpty) {
              _processScannedData(fieldIdentifier, result);
            }
          },
        ),
      ],
    );
  }

  Widget _buildProductsList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        borderRadius: _borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
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
          textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.colorScheme.onSurface.withOpacity(0.04),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 10),
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
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isEnabled;

  const _QrButton({required this.onTap, this.isEnabled = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: 56,
      child: ElevatedButton(
        onPressed: isEnabled ? onTap : null,
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
    super.key,
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
    super.key,
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
        title: Text('inventory_transfer.dialog_confirm_transfer_title'.tr(namedArgs: {'mode': mode.name})),
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
        padding: const EdgeInsets.all(16.0),
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
// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Intent;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() => _OrderTransferScreenState();
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
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
  bool _isPalletOpening = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;

  // Kaynak lokasyon sipariş bazlı transferde her zaman "Mal Kabul Alanı"
  final String _sourceLocationName = '000';
  final _sourceLocationController = TextEditingController();

  Map<String, int> _availableTargetLocations = {};
  String? _selectedTargetLocationName;
  final _targetLocationController = TextEditingController();
  final _targetLocationFocusNode = FocusNode();

  // GÜNCELLEME: Tüm konteynerler ve mod bazlı filtrelenmiş konteynerler
  List<TransferableContainer> _allContainers = [];
  List<TransferableContainer> _availableContainers = [];
  TransferableContainer? _selectedContainer;
  final _scannedContainerIdController = TextEditingController();
  final _containerFocusNode = FocusNode();

  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};

  // GÜNCELLEME: Mod durumları
  bool _hasPalletContainers = false;
  bool _hasBoxContainers = false;

  // Barcode service
  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    _containerFocusNode.addListener(_onFocusChange);
    _targetLocationFocusNode.addListener(_onFocusChange);
    
    // Kaynak lokasyon her zaman "Mal Kabul Alanı"
    _sourceLocationController.text = '000';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _sourceLocationController.dispose();
    _targetLocationController.dispose();
    _scannedContainerIdController.dispose();
    _targetLocationFocusNode.dispose();
    _containerFocusNode.dispose();
    _clearProductControllers();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_containerFocusNode.hasFocus && _scannedContainerIdController.text.isNotEmpty) {
      _scannedContainerIdController.selection = TextSelection(
        baseOffset: 0, 
        extentOffset: _scannedContainerIdController.text.length
      );
    }
    if (_targetLocationFocusNode.hasFocus && _targetLocationController.text.isNotEmpty) {
      _targetLocationController.selection = TextSelection(
        baseOffset: 0, 
        extentOffset: _targetLocationController.text.length
      );
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
      final targetLocations = await _repo.getTargetLocations();
      if (!mounted) return;
      
      setState(() {
        _availableTargetLocations = targetLocations;
      });
      
      await _loadAllContainers();
      if (!mounted) return;
      
      // GÜNCELLEME: Eğer hiç konteyner yoksa geri dön
      if (_allContainers.isEmpty) {
        if (mounted) {
          _showErrorSnackBar('order_transfer.all_items_transferred'.tr());
          Navigator.of(context).pop(true);
        }
        return;
      }
      
      // GÜNCELLEME: Mod durumlarını kontrol et
      _updateModeAvailability();
      
      // GÜNCELLEME: Mevcut olmayan modda başladıysak geçerli moda geç
      if (!_isModeAvailable(_selectedMode)) {
        _selectedMode = _hasPalletContainers ? AssignmentMode.pallet : AssignmentMode.box;
      }
      
      _filterContainersByMode();
      
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusScope.of(context).requestFocus(_containerFocusNode);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('order_transfer.error_loading_data'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  // GÜNCELLEME: Tüm konteynerleri yükle
  Future<void> _loadAllContainers() async {
    try {
      _allContainers = await _repo.getTransferableContainers(null, orderId: widget.order.id);
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('order_transfer.error_loading_containers'.tr(namedArgs: {'error': e.toString()}));
      }
      _allContainers = [];
    }
  }

  // GÜNCELLEME: Mod durumlarını güncelle
  void _updateModeAvailability() {
    _hasPalletContainers = _allContainers.any((container) => !container.id.startsWith('PALETSIZ_'));
    _hasBoxContainers = _allContainers.any((container) => container.id.startsWith('PALETSIZ_'));
  }

  // GÜNCELLEME: Modun mevcut olup olmadığını kontrol et
  bool _isModeAvailable(AssignmentMode mode) {
    switch (mode) {
      case AssignmentMode.pallet:
        return _hasPalletContainers;
      case AssignmentMode.box:
      case AssignmentMode.boxFromPallet:
        return _hasBoxContainers;
    }
  }

  // GÜNCELLEME: Konteynerleri moda göre filtrele
  void _filterContainersByMode() {
    if (_selectedMode == AssignmentMode.pallet) {
      _availableContainers = _allContainers.where((container) => 
        !container.id.startsWith('PALETSIZ_')
      ).toList();
    } else {
      _availableContainers = _allContainers.where((container) => 
        container.id.startsWith('PALETSIZ_')
      ).toList();
    }
  }

  Future<void> _processScannedData(String field, String data) async {
    final cleanData = data.trim();
    if (cleanData.isEmpty) return;

    switch (field) {
      case 'target':
        final location = await _repo.findLocationByCode(cleanData);
        if (location != null) {
          if (_availableTargetLocations.containsKey(location.key)) {
            _handleTargetSelection(location.key);
          } else {
            _showErrorSnackBar('order_transfer.error_invalid_location_for_operation'.tr());
          }
        } else {
          _targetLocationController.clear();
          _showErrorSnackBar('order_transfer.error_invalid_location_code'.tr(namedArgs: {'code': cleanData}));
        }
        break;

      case 'container':
        final foundContainer = _availableContainers.where((container) {
          return container.id.toLowerCase() == cleanData.toLowerCase() ||
                 container.displayName.toLowerCase().contains(cleanData.toLowerCase());
        }).firstOrNull;

        if (foundContainer != null) {
          _handleContainerSelection(foundContainer);
        } else {
          _scannedContainerIdController.clear();
          _showErrorSnackBar('order_transfer.error_container_not_found'.tr(namedArgs: {'data': cleanData}));
        }
        break;
    }
  }

  void _handleContainerSelection(TransferableContainer? selectedContainer) {
    if (selectedContainer == null) return;
    
    setState(() {
      _selectedContainer = selectedContainer;
      _scannedContainerIdController.text = selectedContainer.displayName;
    });
    
    _fetchContainerContents();
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

  Future<void> _fetchContainerContents() async {
    final container = _selectedContainer;
    if (container == null) return;

    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
      _clearProductControllers();
    });

    try {
      final products = container.items.map((item) {
        return ProductItem(
          id: item.product.id,
          name: item.product.name,
          productCode: item.product.stockCode,
          currentQuantity: item.quantity,
          expiryDate: item.expiryDate,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _productsInContainer = products;
        for (var product in products) {
          final initialQty = product.currentQuantity;
          final initialQtyText = initialQty == initialQty.truncate()
              ? initialQty.toInt().toString()
              : initialQty.toString();
          _productQuantityControllers[product.id] = TextEditingController(text: initialQtyText);
          _productQuantityFocusNodes[product.id] = FocusNode();
        }
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('order_transfer.error_loading_content'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }

  void _resetContainerAndProducts() {
    _scannedContainerIdController.clear();
    _productsInContainer = [];
    _selectedContainer = null;
    _clearProductControllers();
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: SharedAppBar(title: 'order_transfer.title'.tr()),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(),
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
                  // Sipariş Bilgi Kartı
                  OrderInfoCard(order: widget.order),
                  const SizedBox(height: _gap),
                  
                  // Mod Seçimi
                  _buildModeSelector(),
                  const SizedBox(height: _gap),
                  
                  // GÜNCELLEME: Mod durumu bilgisi
                  if (!_isModeAvailable(_selectedMode))
                    _buildModeUnavailableMessage(),
                  
                  // Palet Açma Seçeneği - Commented out as requested
                  // if (_selectedMode == AssignmentMode.pallet && _isModeAvailable(_selectedMode)) ...[
                  //   _buildPalletOpeningSwitch(),
                  //   const SizedBox(height: _gap),
                  // ],
                  
                  // Kaynak Lokasyon (Disabled - Her zaman Mal Kabul Alanı)
                  TextFormField(
                    controller: _sourceLocationController,
                    enabled: false,
                    decoration: _inputDecoration('order_transfer.label_source_location'.tr(), enabled: false),
                  ),
                  const SizedBox(height: _gap),
                  
                  // Konteyner Seçimi
                  if (_isModeAvailable(_selectedMode))
                    _buildHybridDropdownWithQr<TransferableContainer>(
                      controller: _scannedContainerIdController,
                      focusNode: _containerFocusNode,
                      label: _selectedMode == AssignmentMode.pallet 
                          ? 'order_transfer.label_pallet'.tr() 
                          : 'order_transfer.label_product'.tr(),
                      fieldIdentifier: 'container',
                      items: _availableContainers,
                      itemToString: (item) => item.displayName,
                      onItemSelected: _handleContainerSelection,
                      filterCondition: (item, query) {
                        final lowerQuery = query.toLowerCase();
                        return item.displayName.toLowerCase().contains(lowerQuery) ||
                               item.id.toLowerCase().contains(lowerQuery);
                      },
                      validator: (val) => (val == null || val.isEmpty) 
                          ? 'order_transfer.validator_required_field'.tr() 
                          : null,
                    ),
                  const SizedBox(height: _gap),
                  
                  // Konteyner İçeriği
                  if (_isLoadingContainerContents)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: _gap), 
                      child: Center(child: CircularProgressIndicator())
                    )
                  else if (_productsInContainer.isNotEmpty)
                    _buildProductsList(),
                  const SizedBox(height: _gap),
                  
                  // Hedef Lokasyon Seçimi
                  if (_isModeAvailable(_selectedMode))
                    _buildHybridDropdownWithQr<String>(
                      controller: _targetLocationController,
                      focusNode: _targetLocationFocusNode,
                      label: 'order_transfer.label_target_location'.tr(),
                      fieldIdentifier: 'target',
                      items: _availableTargetLocations.keys.toList(),
                      itemToString: (item) => item,
                      onItemSelected: _handleTargetSelection,
                      filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                      validator: (val) => (val == null || val.isEmpty) 
                          ? 'order_transfer.validator_required_field'.tr() 
                          : null,
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
            label: Text('order_transfer.mode_pallet'.tr()),
            icon: const Icon(Icons.pallet),
            enabled: _hasPalletContainers, // GÜNCELLEME: Dinamik enable/disable
          ),
          ButtonSegment(
            value: AssignmentMode.box,
            label: Text('order_transfer.mode_box'.tr()),
            icon: const Icon(Icons.inventory_2_outlined),
            enabled: _hasBoxContainers, // GÜNCELLEME: Dinamik enable/disable
          ),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (newSelection) {
          final newMode = newSelection.first;
          if (_isModeAvailable(newMode)) {
            setState(() {
              _selectedMode = newMode;
              _isPalletOpening = false;
              _resetContainerAndProducts();
              _filterContainersByMode();
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
  }

  // GÜNCELLEME: Mod mevcut değilse gösterilecek mesaj
  Widget _buildModeUnavailableMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: _gap),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withAlpha(50),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).colorScheme.error.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedMode == AssignmentMode.pallet
                  ? 'order_transfer.no_pallets_available'.tr()
                  : 'order_transfer.no_boxes_available'.tr(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget _buildPalletOpeningSwitch() {
  //   return Material(
  //     clipBehavior: Clip.antiAlias,
  //     borderRadius: _borderRadius,
  //     color: Theme.of(context).colorScheme.secondary.withAlpha(26),
  //     child: SwitchListTile(
  //       title: Text('order_transfer.label_break_pallet'.tr(), 
  //                  style: const TextStyle(fontWeight: FontWeight.bold)),
  //       value: _isPalletOpening,
  //       onChanged: _productsInContainer.isNotEmpty ? (bool value) {
  //         setState(() {
  //           _isPalletOpening = value;
  //           if (!value) {
  //             for (var product in _productsInContainer) {
  //               final initialQty = product.currentQuantity;
  //               final initialQtyText = initialQty == initialQty.truncate()
  //                   ? initialQty.toInt().toString()
  //                   : initialQty.toString();
  //               _productQuantityControllers[product.id]?.text = initialQtyText;
  //             }
  //           }
  //         });
  //       } : null,
  //       secondary: const Icon(Icons.inventory_2_outlined),
  //       activeThumbColor: Theme.of(context).colorScheme.primary,
  //       shape: RoundedRectangleBorder(borderRadius: _borderRadius),
  //     ),
  //   );
  // }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showErrorSnackBar('order_transfer.error_fill_required_fields'.tr());
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
          palletId: _selectedMode == AssignmentMode.pallet ? _selectedContainer?.id : null,
          targetLocationId: _availableTargetLocations[_selectedTargetLocationName!],
          targetLocationName: _selectedTargetLocationName!,
          expiryDate: product.expiryDate,
        ));
      }
    }

    if (itemsToTransfer.isEmpty) {
      _showErrorSnackBar('order_transfer.error_no_items_to_transfer'.tr());
      return;
    }

    final finalOperationMode = _selectedMode == AssignmentMode.pallet
        ? (_isPalletOpening ? AssignmentMode.boxFromPallet : AssignmentMode.pallet)
        : AssignmentMode.box;

    final confirm = await _showConfirmationDialog(itemsToTransfer, finalOperationMode);
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getInt('user_id');
    final targetId = _availableTargetLocations[_selectedTargetLocationName!];

    if (targetId == null || employeeId == null) {
      _showErrorSnackBar('order_transfer.error_location_id_not_found'.tr());
      return;
    }

    setState(() => _isSaving = true);
    try {
      final header = TransferOperationHeader(
        employeeId: employeeId,
        operationType: finalOperationMode,
        sourceLocationName: _sourceLocationName,
        targetLocationName: _selectedTargetLocationName!,
        containerId: _selectedContainer?.id,
        transferDate: DateTime.now(),
        siparisId: widget.order.id,
      );
      
      // Kaynak lokasyon sipariş bazlı transferde her zaman null (Mal Kabul Alanı)
      await _repo.recordTransferOperation(header, itemsToTransfer, null, targetId);

      if (mounted) {
        context.read<SyncService>().uploadPendingOperations();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('order_transfer.success_transfer_saved'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('order_transfer.error_saving'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
              final result = await Navigator.push<String>(
                context, 
                MaterialPageRoute(builder: (context) => const QrScannerScreen())
              );
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
              'order_transfer.content_title'.tr(namedArgs: {'containerId': _scannedContainerIdController.text}),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(_smallGap),
            itemCount: _productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(
              height: _smallGap, 
              indent: 16, 
              endIndent: 16, 
              thickness: 0.2
            ),
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
                          Text(
                            product.name, 
                            style: Theme.of(context).textTheme.bodyLarge, 
                            overflow: TextOverflow.ellipsis
                          ),
                          Text(
                            'order_transfer.label_current_quantity'.tr(namedArgs: {
                              'productCode': product.productCode, 
                              'quantity': product.currentQuantity.toStringAsFixed(
                                product.currentQuantity.truncateToDouble() == product.currentQuantity ? 0 : 2
                              )
                            }),
                            style: Theme.of(context).textTheme.bodySmall
                          ),
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
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                        ],
                        decoration: _inputDecoration('order_transfer.label_quantity'.tr()),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'order_transfer.validator_required'.tr();
                          final qty = double.tryParse(value);
                          if (qty == null) return 'order_transfer.validator_invalid'.tr();
                          if (qty > product.currentQuantity + 0.001) return 'order_transfer.validator_max'.tr();
                          if (qty < 0) return 'order_transfer.validator_negative'.tr();
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
        onPressed: _isSaving || _productsInContainer.isEmpty || !_isModeAvailable(_selectedMode) ? null : _onConfirmSave,
        icon: _isSaving
            ? const SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
              )
            : const Icon(Icons.check_circle_outline),
        label: FittedBox(child: Text('order_transfer.button_save'.tr())),
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
      enabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius, 
        borderSide: BorderSide(color: theme.dividerColor)
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _borderRadius, 
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _borderRadius, 
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1)
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _borderRadius, 
        borderSide: BorderSide(color: theme.colorScheme.error, width: 2)
      ),
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
        builder: (context) => _SearchPage<T>(
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
        builder: (context) => _ConfirmationPage(
          items: items,
          mode: mode,
          sourceLocationName: _sourceLocationName,
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

  // --- Barcode Handling ---
  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;

    _barcodeService = BarcodeIntentService();

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

    if (_containerFocusNode.hasFocus) {
      _processScannedData('container', code);
    } else if (_targetLocationFocusNode.hasFocus) {
      _processScannedData('target', code);
    } else {
      // Aktif bir odak yoksa, mantıksal bir sıra izle
      if (_selectedContainer == null) {
        _containerFocusNode.requestFocus();
        _processScannedData('container', code);
      } else {
        _targetLocationFocusNode.requestFocus();
        _processScannedData('target', code);
      }
    }
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

class _SearchPage<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemToString;
  final bool Function(T, String) filterCondition;

  const _SearchPage({
    required this.title,
    required this.items,
    required this.itemToString,
    required this.filterCondition,
  });

  @override
  State<_SearchPage<T>> createState() => _SearchPageState<T>();
}

class _SearchPageState<T> extends State<_SearchPage<T>> {
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
                hintText: 'order_transfer.dialog_search_hint'.tr(),
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
                  ? Center(child: Text('order_transfer.dialog_search_no_results'.tr()))
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

class _ConfirmationPage extends StatelessWidget {
  final List<TransferItemDetail> items;
  final AssignmentMode mode;
  final String sourceLocationName;
  final String targetLocationName;

  const _ConfirmationPage({
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
        title: Text('order_transfer.dialog_confirm_transfer_title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            'order_transfer.dialog_confirm_transfer_body'.tr(
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
          child: Text('order_transfer.dialog_button_confirm'.tr()),
        ),
      ),
    );
  }
}

// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/utils/keyboard_utils.dart';
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
import 'package:diapalet/features/inventory_transfer/constants/inventory_transfer_constants.dart';

class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() {
    return _OrderTransferScreenState();
  }
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
  // --- Sabitler ve Stil Değişkenleri ---
  static const double _gap = InventoryTransferConstants.standardGap;
  static const double _smallGap = InventoryTransferConstants.smallGap;
  final _borderRadius = BorderRadius.circular(InventoryTransferConstants.borderRadius);

  // --- State ve Controller'lar ---
  final _formKey = GlobalKey<FormState>();
  late InventoryTransferRepository _repo;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;
  bool _isPalletOpening = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;

  // Kaynak lokasyon sipariş bazlı transferde her zaman "Mal Kabul Alanı"
  final String _sourceLocationName = InventoryTransferConstants.receivingAreaCode;
  final _sourceLocationController = TextEditingController();

  Map<String, int?> _availableTargetLocations = {};
  String? _selectedTargetLocationName;
  final _targetLocationController = TextEditingController();
  final _targetLocationFocusNode = FocusNode();
  bool _isTargetLocationValid = false;

  // GÜNCELLEME: Tüm konteynerler ve mod bazlı filtrelenmiş konteynerler
  List<TransferableContainer> _allContainers = [];
  List<TransferableContainer> _availableContainers = [];
  TransferableContainer? _selectedContainer;
  final _scannedContainerIdController = TextEditingController();
  final _containerFocusNode = FocusNode();
  String? _dynamicProductLabel; // Dinamik product label için

  List<ProductItem> _productsInContainer = [];
  final Map<String, TextEditingController> _productQuantityControllers = {};
  final Map<String, FocusNode> _productQuantityFocusNodes = {};

  // GÜNCELLEME: Mod durumları
  bool _hasPalletContainers = false;
  bool _hasBoxContainers = false;

  // Container search results for inline display
  List<TransferableContainer> _containerSearchResults = [];

  // Barcode service
  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    
    _containerFocusNode.addListener(_onFocusChange);
    _targetLocationFocusNode.addListener(_onFocusChange);
    _barcodeService = BarcodeIntentService();

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

    // Kaynak lokasyon her zaman "Mal Kabul Alanı"
    _sourceLocationController.text = InventoryTransferConstants.receivingAreaCode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    
    // Clear product data and controllers with isDisposing flag
    _clearProductControllers(isDisposing: true);
    
    // Then dispose focus nodes and controllers
    if (_targetLocationFocusNode.hasFocus) _targetLocationFocusNode.unfocus();
    if (_containerFocusNode.hasFocus) _containerFocusNode.unfocus();
    
    _targetLocationFocusNode.dispose();
    _containerFocusNode.dispose();
    
    _sourceLocationController.dispose();
    _targetLocationController.dispose();
    _scannedContainerIdController.dispose();
    
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

  void _clearProductControllers({bool isDisposing = false}) {
    // First clear maps to prevent widgets from accessing disposed nodes
    final controllersToDispose = Map<String, TextEditingController>.from(_productQuantityControllers);
    final focusNodesToDispose = Map<String, FocusNode>.from(_productQuantityFocusNodes);
    
    // Clear maps immediately to prevent widget access
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
    
    // Only call setState if not disposing (widget is still active)
    if (!isDisposing && mounted) {
      setState(() {
        _productsInContainer.clear();
      });
    } else {
      // If disposing, just clear the list without setState
      _productsInContainer.clear();
    }
    
    // Dispose controllers and focus nodes
    if (isDisposing) {
      // Dispose immediately when called from dispose()
      controllersToDispose.forEach((_, controller) {
        try {
          controller.dispose();
        } catch (e) {
          // Already disposed, ignore
        }
      });
      
      focusNodesToDispose.forEach((_, focusNode) {
        try {
          if (focusNode.hasFocus) {
            focusNode.unfocus();
          }
          focusNode.dispose();
        } catch (e) {
          // Already disposed, ignore
        }
      });
    } else {
      // Dispose asynchronously when called during normal operation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controllersToDispose.forEach((_, controller) {
          try {
            controller.dispose();
          } catch (e) {
            // Already disposed, ignore
          }
        });
        
        focusNodesToDispose.forEach((_, focusNode) {
          try {
            if (focusNode.hasFocus) {
              focusNode.unfocus();
            }
            focusNode.dispose();
          } catch (e) {
            // Already disposed, ignore
          }
        });
      });
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoadingInitialData = true);
    try {
      // FIX: For putaway operations, exclude receiving area from target locations
      final targetLocations = await _repo.getTargetLocations(excludeReceivingArea: true);
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
        _selectedMode = _hasPalletContainers ? AssignmentMode.pallet : AssignmentMode.product;
      }

      _filterContainersByMode();

      // Sayfa yüklendiğinde otomatik klavye açılmasını engelle
      // Kullanıcı manuel olarak tıkladığında klavye açılacak
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
    _hasPalletContainers = _allContainers.any((container) => container.isPallet);
    _hasBoxContainers = _allContainers.any((container) => !container.isPallet);
  }

  // GÜNCELLEME: Modun mevcut olup olmadığını kontrol et
  bool _isModeAvailable(AssignmentMode mode) {
    switch (mode) {
      case AssignmentMode.pallet:
        return _hasPalletContainers;
      case AssignmentMode.product:
      case AssignmentMode.productFromPallet:
        return _hasBoxContainers;
    }
  }

  // GÜNCELLEME: Konteynerleri moda göre filtrele
  void _filterContainersByMode() {
    if (_selectedMode == AssignmentMode.pallet) {
      _availableContainers = _allContainers.where((container) =>
        container.isPallet
      ).toList();
    } else {
      _availableContainers = _allContainers.where((container) =>
        !container.isPallet
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
            _targetLocationController.text = cleanData;
            setState(() => _isTargetLocationValid = false);
            _showErrorSnackBar('order_transfer.error_invalid_location_for_operation'.tr());
          }
        } else {
          _targetLocationController.text = cleanData;
          setState(() => _isTargetLocationValid = false);
          _showErrorSnackBar('order_transfer.error_invalid_location_code'.tr(namedArgs: {'code': cleanData}));
        }
        break;

      case 'container':
        // First try to find by container ID or display name
        final foundContainer = _availableContainers.where((container) {
          return container.id.toLowerCase() == cleanData.toLowerCase() ||
                 container.displayName.toLowerCase().contains(cleanData.toLowerCase());
        }).firstOrNull;

        if (foundContainer != null) {
          _handleContainerSelection(foundContainer);
        } else {
          // If not found, try barcode search
          await _searchByBarcode(cleanData);
        }
        break;
    }
  }

  void _handleContainerSelection(TransferableContainer? selectedContainer) {
    if (selectedContainer == null) return;

    setState(() {
      _selectedContainer = selectedContainer;
      // Show barcode for products, pallet ID for pallets
      if (selectedContainer.isPallet) {
        _scannedContainerIdController.text = selectedContainer.id;
        _dynamicProductLabel = null; // Pallet için label değişmez
      } else {
        // For products, show only barcode
        final product = selectedContainer.items.first.product;
        // barkod field'ı barkodlar tablosundan geliyor
        final barcode = product.productBarcode ?? product.stockCode;
        _scannedContainerIdController.text = barcode;
        // Label'ı ürün adıyla güncelle
        _dynamicProductLabel = selectedContainer.displayName;
      }
      _containerSearchResults = []; // Clear search results
    });

    _fetchContainerContents();
    // Otomatik focus yapma - kullanıcı manuel geçiş yapsın
    // _targetLocationFocusNode.requestFocus();
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

  Future<void> _searchByBarcode(String barcode) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final product = await dbHelper.getProductByBarcode(barcode, orderId: widget.order.id);
      
      if (product != null) {
        // Try to find a matching container in available containers
        final matchingContainer = _availableContainers.where((container) {
          if (container.isPallet) return false;
          
          final containerProduct = container.items.first.product;
          return containerProduct.stockCode == product['StokKodu'] ||
                 containerProduct.productBarcode == barcode;
        }).firstOrNull;
        
        if (matchingContainer != null) {
          _handleContainerSelection(matchingContainer);
        } else {
          _scannedContainerIdController.clear();
          _showErrorSnackBar('order_transfer.error_container_not_found'.tr(namedArgs: {'data': barcode}));
        }
      } else {
        _scannedContainerIdController.clear();
        _showErrorSnackBar('order_transfer.error_container_not_found'.tr(namedArgs: {'data': barcode}));
      }
    } catch (e) {
      _scannedContainerIdController.clear();
      _showErrorSnackBar('order_transfer.error_container_not_found'.tr(namedArgs: {'data': barcode}));
    }
  }

  Future<void> _fetchContainerContents() async {
    final container = _selectedContainer;
    if (container == null) return;

    // Clear product controllers first, outside setState
    _clearProductControllers();
    
    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
    });

    try {
      final products = container.items.map((item) {
        return ProductItem(
          productKey: item.product.productKey ?? item.product.id.toString(),
          birimKey: item.product.birimKey, // KRITIK FIX: birimKey eklendi
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
          _productQuantityControllers[product.key] = TextEditingController(text: initialQtyText);
          _productQuantityFocusNodes[product.key] = FocusNode();
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
    _containerSearchResults = []; // Clear search results
    _dynamicProductLabel = null; // Label'ı da temizle
    _clearProductControllers();
  }

  // GÜNCELLEME: Bu metod artık doğrudan konteynerin kendi displayName'ini kullanıyor
  String _getContainerDisplayName(TransferableContainer container) {
    return container.displayName;
  }

  // Birim key'den birim adını getir
  Future<String?> _getUnitName(String? birimKey) async {
    if (birimKey == null || birimKey.isEmpty) return null;
    
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      
      final result = await db.query(
        'birimler',
        columns: ['birimadi'],
        where: '_key = ?',
        whereArgs: [birimKey],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        return result.first['birimadi'] as String?;
      }
    } catch (e) {
      // Error getting unit name for birimKey
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: SharedAppBar(title: 'order_transfer.title'.tr()),
      resizeToAvoidBottomInset: false, // Klavye animasyon problemini çözmek için
      bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(),
      body: SafeArea(
        child: _isLoadingInitialData
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Loading order ${widget.order.id}...'),
                  ],
                ),
              )
            : GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.only(
                    bottom: isKeyboardVisible ? MediaQuery.of(context).viewInsets.bottom : 0,
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.disabled,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: InventoryTransferConstants.largePadding, vertical: InventoryTransferConstants.standardGap),
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
                            _buildContainerSelectionWithInlineResults(),
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _targetLocationController,
                                    focusNode: _targetLocationFocusNode,
                                    decoration: _inputDecoration(
                                      'order_transfer.label_target_location'.tr(),
                                      isValid: _isTargetLocationValid,
                                    ),
                                    validator: (val) => (val == null || val.isEmpty)
                                        ? 'order_transfer.validator_required_field'.tr()
                                        : null,
                                    onFieldSubmitted: (value) async {
                                      if (value.trim().isNotEmpty) {
                                        await _processScannedData('target', value.trim());
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: _smallGap),
                                _QrButton(
                                    onTap: () async {
                                      // Gelişmiş klavye kapatma
                                      await KeyboardUtils.prepareForQrScanner(context, focusNodes: [_targetLocationFocusNode]);
                                      
                                      final result = await Navigator.push<String>(
                                        context,
                                        MaterialPageRoute(builder: (context) => const QrScannerScreen())
                                      );
                                      if (result != null && result.isNotEmpty) {
                                        // Text alanına yaz ama focus yapma
                                        _targetLocationController.text = result;
                                        await _processScannedData('target', result);
                                      }
                                    },
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
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<AssignmentMode>(
          segments: [
            ButtonSegment(
              value: AssignmentMode.product,
              label: Text('order_transfer.mode_box'.tr()),
              icon: const Icon(Icons.inventory_2),
              enabled: _hasBoxContainers, // GÜNCELLEME: Dinamik enable/disable
            ),
            ButtonSegment(
              value: AssignmentMode.pallet,
              label: Text('order_transfer.mode_pallet'.tr()),
              icon: const Icon(Icons.pallet),
              enabled: _hasPalletContainers, // GÜNCELLEME: Dinamik enable/disable
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
        ),
      ],
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
  //               _productQuantityControllers[product.key]?.text = initialQtyText;
  //             }
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
      final qtyText = _productQuantityControllers[product.key]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;
      if (qty > 0) {
        itemsToTransfer.add(TransferItemDetail(
          productKey: product.productKey, // KRITIK FIX: Sadece urun_key, composite key değil!
          birimKey: product.birimKey, // KRITIK FIX: birimKey eklendi
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
        ? (_isPalletOpening ? AssignmentMode.productFromPallet : AssignmentMode.pallet)
        : AssignmentMode.product;

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

        // Transfer başarılı, yeni transfer için formu temizle
        _resetContainerAndProducts();
        _selectedTargetLocationName = null;
        _targetLocationController.clear();
        _isTargetLocationValid = false;
        
        // Container listelerini yenile (stok değişti)
        await _loadAllContainers();
        _filterContainersByMode();
        
        // Transfer tamamlandı - klavye açmadan bekle
        // Kullanıcı field'a tıkladığında klavye açılacak
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('order_transfer.error_saving'.tr(namedArgs: {'error': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildContainerSelectionWithInlineResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start, // Text field ile QR buton hizalama
          children: [
            Expanded(
              child: TextFormField(
                controller: _scannedContainerIdController,
                focusNode: _containerFocusNode,
                enabled: true,
                maxLines: 1,
                decoration: _inputDecoration(
                  _selectedMode == AssignmentMode.pallet
                      ? 'order_transfer.label_pallet'.tr()
                      : _dynamicProductLabel ?? 'order_transfer.label_product'.tr(),
                  enabled: true,
                  suffixIcon: _scannedContainerIdController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            setState(() {
                              _scannedContainerIdController.clear();
                              _containerSearchResults = [];
                              _dynamicProductLabel = null;
                              _resetContainerAndProducts();
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      : null,
                ),
                onChanged: (value) {
                  _onContainerTextChanged(value);
                },
                onFieldSubmitted: (value) async {
                  if (value.isNotEmpty) {
                    // Eğer search sonuçları varsa ilk sonucu seç
                    if (_containerSearchResults.isNotEmpty) {
                      _handleContainerSelection(_containerSearchResults.first);
                    } else {
                      // Search sonuçları yoksa barkod olarak işle
                      await _processScannedData('container', value);
                    }
                  }
                },
                textInputAction: TextInputAction.search,
                validator: (val) => (val == null || val.isEmpty)
                    ? 'order_transfer.validator_required_field'.tr()
                    : null,
              ),
            ),
            const SizedBox(width: _smallGap),
            _QrButton(
                onTap: () async {
                  // Gelişmiş klavye kapatma  
                  await KeyboardUtils.prepareForQrScanner(context, focusNodes: [_containerFocusNode]);
                  
                  final result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (context) => const QrScannerScreen())
                  );
                  
                  if (result != null && result.isNotEmpty) {
                    // Text alanına yaz ama focus yapma
                    _scannedContainerIdController.text = result;
                    await _processScannedData('container', result);
                  }
                },
            ),
          ],
        ),
        if (_containerSearchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: _borderRadius,
            ),
            child: Column(
              children: _containerSearchResults.take(5).map((container) {
                return ListTile(
                  dense: true,
                  title: Text(
                    _getContainerDisplayName(container),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: container.isPallet 
                    ? Text(
                        "Palet ID: ${container.id}",
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : Text(
                        "Barkod: ${container.items.first.product.productBarcode ?? 'N/A'} | Stok Kodu: ${container.items.first.product.stockCode}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  onTap: () {
                    _handleContainerSelection(container);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  void _onContainerTextChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _containerSearchResults = [];
        _dynamicProductLabel = null; // Text temizlendiğinde label'ı da temizle
      });
      return;
    }
    
    // Önce mevcut container'larda ara
    final lowerQuery = value.toLowerCase();
    final localResults = _availableContainers.where((container) {
      if (container.isPallet) {
        return container.id.toLowerCase().contains(lowerQuery);
      } else {
        final product = container.items.first.product;
        return product.name.toLowerCase().contains(lowerQuery) ||
               product.stockCode.toLowerCase().contains(lowerQuery) ||
               (product.productBarcode?.toLowerCase().contains(lowerQuery) ?? false);
      }
    }).toList();
    
    setState(() {
      _containerSearchResults = localResults;
    });
    
    // Eğer tam barkod gibi görünüyorsa (5+ karakter), database'de de ara
    if (value.length >= 5) {
      _performBarcodeSearch(value);
    }
  }
  
  Future<void> _performBarcodeSearch(String query) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final products = await dbHelper.searchProductsByBarcode(query, orderId: widget.order.id);
      
      if (products.isNotEmpty) {
        // Database sonuçlarını mevcut container'larla eşleştir
        final matchingContainers = <TransferableContainer>[];
        for (final product in products) {
          final matching = _availableContainers.where((container) {
            if (container.isPallet) return false;
            final containerProduct = container.items.first.product;
            return containerProduct.stockCode == product['StokKodu'];
          });
          matchingContainers.addAll(matching);
        }
        
        // Duplicate'leri kaldır ve mevcut sonuçlarla birleştir
        final combinedResults = <TransferableContainer>[
          ..._containerSearchResults,
          ...matchingContainers.where((container) => 
            !_containerSearchResults.any((existing) => existing.id == container.id)
          )
        ];
        
        setState(() {
          _containerSearchResults = combinedResults;
        });
      }
    } catch (e) {
      // Database barcode search error handled
    }
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
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: _smallGap, vertical: 8),
            itemCount: _productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(
              height: 10,
              indent: 16,
              endIndent: 16,
              thickness: 0.2
            ),
            itemBuilder: (context, index) {
              final product = _productsInContainer[index];
              final controller = _productQuantityControllers[product.key];
              final focusNode = _productQuantityFocusNodes[product.key];
              
              // Safety check: if controllers are null, skip this item
              if (controller == null || focusNode == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: InventoryTransferConstants.smallGap, vertical: 6),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ürün adı
                            Text(
                              product.name,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                            // Expiry Date ve Stok Kodu
                            if (product.expiryDate != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('dd.MM.yyyy').format(product.expiryDate!),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${product.productCode}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !(_selectedMode == AssignmentMode.pallet && !_isPalletOpening),
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                        ],
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                        decoration: _inputDecoration(
                          'order_transfer.label_quantity'.tr(),
                          hintText: product.currentQuantity.toStringAsFixed(product.currentQuantity.truncateToDouble() == product.currentQuantity ? 0 : 2),
                          verticalPadding: 8,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'order_transfer.validator_required'.tr();
                          final qty = double.tryParse(value);
                          if (qty == null) return 'order_transfer.validator_invalid'.tr();
                          if (qty > product.currentQuantity + 0.001) return 'order_transfer.validator_max'.tr();
                          if (qty < 0) return 'order_transfer.validator_negative'.tr();
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          if (!mounted || _productQuantityFocusNodes.isEmpty) return;
                          
                          try {
                            final productIds = _productQuantityFocusNodes.keys.toList();
                            final currentIndex = productIds.indexOf(product.key);
                            if (currentIndex >= 0 && currentIndex < productIds.length - 1) {
                              final nextKey = productIds[currentIndex + 1];
                              final nextFocusNode = _productQuantityFocusNodes[nextKey];
                              if (nextFocusNode != null && nextFocusNode.canRequestFocus) {
                                nextFocusNode.requestFocus();
                              }
                            } else {
                              // Last item, focus on target location
                              try {
                                if (mounted) {
                                  _targetLocationFocusNode.requestFocus();
                                }
                              } catch (e) {
                                // Focus node might be disposed, ignore
                              }
                            }
                          } catch (e) {
                            // Focus node disposed or other error, ignore
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Birim adı için alan
                    FutureBuilder<String?>(
                      future: _getUnitName(product.birimKey),
                      builder: (context, snapshot) {
                        final unitName = snapshot.data ?? '';
                        return SizedBox(
                          width: 35,
                          child: Center(
                            child: Text(
                              unitName,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold, // Birim adını kalın yap
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
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

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true, bool isValid = false, String? hintText, double? verticalPadding}) {
    final theme = Theme.of(context);
    final borderColor = isValid ? Colors.green : theme.dividerColor;
    final focusedBorderColor = isValid ? Colors.green : theme.colorScheme.primary;
    final borderWidth = isValid ? 2.5 : 1.0; // Kalın yeşil border
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.disabledColor.withAlpha(20),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: borderColor, width: borderWidth)),
      focusedBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: focusedBorderColor, width: borderWidth + 0.5)),
      errorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 2)),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalPadding ?? 16), // QrTextField ile tutarlı yükseklik
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 11),
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

    try {
      final first = await _barcodeService.getInitialBarcode();
      if (first != null && first.isNotEmpty) _handleBarcode(first);
    } catch(e) {
      // Initial barcode error handled
    }

    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _showErrorSnackBar('common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()})));
  }

  void _handleBarcode(String code) {
    if (!mounted) return;

    if (_containerFocusNode.hasFocus) {
      setState(() {
        _scannedContainerIdController.text = code;
      });
      _processScannedData('container', code);
    } else if (_targetLocationFocusNode.hasFocus) {
      setState(() {
        _targetLocationController.text = code;
      });
      _processScannedData('target', code);
    } else {
      // Aktif bir odak yoksa, mantıksal bir sıra izle
      if (_selectedContainer == null) {
        _containerFocusNode.requestFocus();
        setState(() {
          _scannedContainerIdController.text = code;
        });
        _processScannedData('container', code);
      } else {
        _targetLocationFocusNode.requestFocus();
        setState(() {
          _targetLocationController.text = code;
        });
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
      height: 56, // Text field ile aynı yükseklik
      width: 56,  // Kare yapı
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(InventoryTransferConstants.borderRadius)),
          padding: EdgeInsets.zero,
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28), // Tutarlı 28 boyutunda icon
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
        padding: const EdgeInsets.all(InventoryTransferConstants.largePadding),
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
        padding: const EdgeInsets.all(InventoryTransferConstants.largePadding),
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
        padding: const EdgeInsets.all(InventoryTransferConstants.largePadding).copyWith(bottom: 24.0),
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

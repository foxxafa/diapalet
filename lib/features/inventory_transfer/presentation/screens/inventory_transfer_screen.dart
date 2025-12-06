// lib/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart
import 'package:diapalet/core/constants/warehouse_receiving_mode.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/qr_text_field.dart';
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
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/utils/keyboard_utils.dart';
import 'package:diapalet/features/inventory_transfer/constants/inventory_transfer_constants.dart';
import 'package:diapalet/core/widgets/shared_input_decoration.dart';

class InventoryTransferScreen extends StatefulWidget {
  final PurchaseOrder? selectedOrder;
  final bool isFreePutAway;
  final String? selectedDeliveryNote; // delivery_note_number (UUID-based queries)
  final String? deliveryNoteDisplayName; // Ekranda gösterim için (NULL ise FREE-{UUID})

  const InventoryTransferScreen({
    super.key,
    this.selectedOrder,
    this.isFreePutAway = false,
    this.selectedDeliveryNote,
    this.deliveryNoteDisplayName,
  });

  @override
  State<InventoryTransferScreen> createState() => _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
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
  String? _dynamicProductLabel; // Dinamik product label için

  List<ProductItem> _productsInContainer = [];
  final Map<String, TextEditingController> _productQuantityControllers = {};
  final Map<String, FocusNode> _productQuantityFocusNodes = {};

  // Product search state
  List<ProductInfo> _productSearchResults = [];
  bool _isSearchingProducts = false;
  final _productSearchController = TextEditingController();
  final _productSearchFocusNode = FocusNode();

  // Pallet search state
  List<String> _palletSearchResults = [];

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
    // TextSelection'ları kaldırıldı - klavye açılmasını önlemek için
    // if (_sourceLocationFocusNode.hasFocus && _sourceLocationController.text.isNotEmpty) {
    //   _sourceLocationController.selection = TextSelection(baseOffset: 0, extentOffset: _sourceLocationController.text.length);
    // }
    // if (_containerFocusNode.hasFocus && _scannedContainerIdController.text.isNotEmpty) {
    //   _scannedContainerIdController.selection = TextSelection(baseOffset: 0, extentOffset: _scannedContainerIdController.text.length);
    // }
    // if (_targetLocationFocusNode.hasFocus && _targetLocationController.text.isNotEmpty) {
    //   _targetLocationController.selection = TextSelection(baseOffset: 0, extentOffset: _targetLocationController.text.length);
    // }
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
        _selectedSourceLocationName = InventoryTransferConstants.receivingAreaCode;
        _sourceLocationController.text = InventoryTransferConstants.receivingAreaCode;
        _isSourceLocationValid = true; // Mark as valid for order/free putaway
        if (widget.isFreePutAway && widget.selectedDeliveryNote != null) {
          // KRITIK FIX: selectedDeliveryNote artık goods_receipt_id değerini tutuyor (string olarak)
          final parsedId = int.tryParse(widget.selectedDeliveryNote!);
          if (parsedId != null) {
            // Numeric ise direkt goods_receipt_id olarak kullan
            _goodsReceiptId = parsedId;
          } else {
            // String ise gerçek delivery note number, ID'yi bul
            _goodsReceiptId = await _repo.getGoodsReceiptIdByDeliveryNote(widget.selectedDeliveryNote!);
          }
          debugPrint('✅ FREE RECEIPT INIT: goods_receipt_id = $_goodsReceiptId');
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

        // Sayfa açılışında otomatik focus yapma - klavye açılmasını önle
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   if (mounted) {
        //     FocusScope.of(context).requestFocus(
        //       (widget.selectedOrder != null || widget.isFreePutAway)
        //           ? _containerFocusNode
        //           : _sourceLocationFocusNode);
        //   }
        // });
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

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🔍 FREE RECEIPT DEBUG - Delivery Note: ${widget.selectedDeliveryNote}');
    debugPrint('═══════════════════════════════════════════════════════════');

    // Get goods receipt details
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      // 1. Goods receipt bilgileri
      debugPrint('🔎 Looking for delivery note: ${widget.selectedDeliveryNote}');

      final receiptQuery = await db.rawQuery('''
        SELECT
          gr.operation_unique_id,
          gr.delivery_note_number,
          gr.siparis_id,
          gr.receipt_date
        FROM goods_receipts gr
        WHERE gr.delivery_note_number = ?
           OR gr.delivery_note_number IS NULL
        ORDER BY gr.created_at DESC
        LIMIT 1
      ''', [widget.selectedDeliveryNote]);

      if (receiptQuery.isNotEmpty) {
        final receipt = receiptQuery.first;
        debugPrint('📋 GOODS RECEIPT:');
        debugPrint('   - UUID: ${receipt['operation_unique_id']}');
        debugPrint('   - Delivery Note: ${receipt['delivery_note_number']}');
        debugPrint('   - Sipariş ID: ${receipt['siparis_id']}');
        debugPrint('   - Tarih: ${receipt['receipt_date']}');

        final operationUuid = receipt['operation_unique_id'] as String?;

        if (operationUuid != null) {
          // 2. Goods receipt items (mal kabul kalemleri)
          final itemsQuery = await db.rawQuery('''
            SELECT
              gri.item_uuid,
              gri.urun_key,
              gri.quantity_received,
              gri.pallet_barcode,
              gri.expiry_date,
              u.StokKodu,
              u.UrunAdi
            FROM goods_receipt_items gri
            LEFT JOIN urunler u ON u._key = gri.urun_key
            WHERE gri.operation_unique_id = ?
            ORDER BY gri.item_uuid
          ''', [operationUuid]);

          debugPrint('');
          debugPrint('📦 GOODS RECEIPT ITEMS (${itemsQuery.length} kalem):');
          for (var item in itemsQuery) {
            debugPrint('   ─────────────────────────────────────────────');
            debugPrint('   Item ID: ${item['id']}');
            debugPrint('   Item UUID: ${item['item_uuid']}');
            debugPrint('   Ürün: ${item['StokKodu']} - ${item['UrunAdi']}');
            debugPrint('   Miktar: ${item['quantity_received']}');
            debugPrint('   Palet: ${item['pallet_barcode'] ?? 'YOK'}');
            debugPrint('   SKT: ${item['expiry_date'] ?? 'YOK'}');
          }

          // 3. Inventory stock (stok kayıtları)
          final stockQuery = await db.rawQuery('''
            SELECT
              ist.stock_uuid,
              ist.urun_key,
              ist.quantity,
              ist.pallet_barcode,
              ist.expiry_date,
              ist.stock_status,
              ist.location_id,
              u.StokKodu,
              u.UrunAdi,
              l.name as location_name
            FROM inventory_stock ist
            LEFT JOIN urunler u ON u._key = ist.urun_key
            LEFT JOIN shelfs l ON l.id = ist.location_id
            WHERE ist.receipt_operation_uuid = ?
            ORDER BY ist.created_at
          ''', [operationUuid]);

          debugPrint('');
          debugPrint('📊 INVENTORY STOCK (${stockQuery.length} kayıt):');
          for (var stock in stockQuery) {
            debugPrint('   ─────────────────────────────────────────────');
            debugPrint('   Stock ID: ${stock['id']}');
            debugPrint('   Stock UUID: ${stock['stock_uuid']}');
            debugPrint('   Ürün: ${stock['StokKodu']} - ${stock['UrunAdi']}');
            debugPrint('   Miktar: ${stock['quantity']}');
            debugPrint('   Palet: ${stock['pallet_barcode'] ?? 'YOK'}');
            debugPrint('   SKT: ${stock['expiry_date'] ?? 'YOK'}');
            debugPrint('   Durum: ${stock['stock_status']}');
            debugPrint('   Lokasyon: ${stock['location_name'] ?? 'MAL KABUL ALANI'}');
          }
        }
      } else {
        debugPrint('⚠️  Goods receipt bulunamadı!');
      }

      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('');
    } catch (e) {
      debugPrint('❌ DEBUG hatası: $e');
    }

    // Check for pallets and products in the specific delivery note
    await _updateModeAvailability(
      palletCheck: () async {
        final pallets = await _repo.getPalletIdsAtLocation(
          null,
          stockStatuses: [InventoryTransferConstants.stockStatusReceiving],
          deliveryNoteNumber: widget.selectedDeliveryNote
        );
        debugPrint('🔧 MODE CHECK: Palet sayısı = ${pallets.length}');
        return pallets.isNotEmpty;
      },
      boxCheck: () async {
        // Get transferable containers (non-pallet items) for this delivery note
        final containers = await _repo.getTransferableContainers(
          null,
          deliveryNoteNumber: widget.selectedDeliveryNote,
        );
        debugPrint('🔧 MODE CHECK: Container sayısı = ${containers.length}');
        final nonPalletCount = containers.where((c) => !c.isPallet).length;
        debugPrint('🔧 MODE CHECK: Paletsiz container sayısı = $nonPalletCount');
        // Check if there are any non-pallet containers
        return containers.any((container) => !container.isPallet);
      },
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
              // Hata durumunda otomatik focus yapma - klavye açılmasını önle
              // FocusScope.of(context).requestFocus(_sourceLocationFocusNode);
            }
            if (field == 'target') {
              _selectedTargetLocationName = null;
              _targetLocationController.text = cleanData;
              setState(() => _isTargetLocationValid = false);
              // Hata durumunda otomatik focus yapma - klavye açılmasını önle
              // FocusScope.of(context).requestFocus(_targetLocationFocusNode);
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
          // Product mode - search by barcode only
          foundItem = _availableContainers.where((container) {
            return container.items.any((item) =>
              (item.product.productBarcode?.toLowerCase() == cleanData.toLowerCase()));
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
      List<String> stockStatuses = [InventoryTransferConstants.stockStatusAvailable, InventoryTransferConstants.stockStatusReceiving];

      if (widget.selectedOrder != null) {
        // Order-based transfer (putaway from order)
        orderId = widget.selectedOrder!.id;
        stockStatuses = [InventoryTransferConstants.stockStatusReceiving]; // Only search receiving items for putaway
      } else if (widget.isFreePutAway && widget.selectedDeliveryNote != null) {
        // Free receipt transfer (putaway from delivery note)
        deliveryNoteNumber = widget.selectedDeliveryNote;
        stockStatuses = [InventoryTransferConstants.stockStatusReceiving]; // Only search receiving items for putaway
      } else if (_selectedSourceLocationName != null && _selectedSourceLocationName != InventoryTransferConstants.receivingAreaCode) {
        // Shelf-to-shelf transfer
        locationId = _availableSourceLocations[_selectedSourceLocationName];
        stockStatuses = [InventoryTransferConstants.stockStatusAvailable]; // Only search available items for shelf transfer
      }

      final results = await _repo.searchProductsForTransfer(
        query,
        orderId: orderId,
        deliveryNoteNumber: deliveryNoteNumber,
        locationId: locationId,
        stockStatuses: stockStatuses,
        excludePalletizedProducts: true, // YENI: Product Mode'da paletin içindeki ürünleri hariç tut
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

  // Pallet search functionality
  Future<void> _searchPalletsForTransfer(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _palletSearchResults = [];
      });
      return;
    }


    try {
      // Search through available containers for matching pallets
      final filteredPallets = _availableContainers
          .cast<String>()
          .where((palletId) => palletId.toLowerCase().contains(query.toLowerCase()))
          .toList();

      if (mounted) {
        setState(() {
          _palletSearchResults = filteredPallets;
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _palletSearchResults = [];
          });
        _showErrorSnackBar('inventory_transfer.error_searching_pallets'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  void _selectPalletFromSearch(String palletId) {
    _scannedContainerIdController.text = palletId;
    setState(() {
      _palletSearchResults = [];
    });
    _handleContainerSelection(palletId);
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

  void _selectProductFromSearch(ProductInfo product) async {
    // Show product barcode in the field and update label with product name
    final barcode = product.productBarcode ?? product.stockCode;
    _scannedContainerIdController.text = barcode;
    setState(() {
      _productSearchResults = [];
      _dynamicProductLabel = product.name; // Update label with product name
    });
    
    // Find the matching container in available containers
    final foundContainer = _availableContainers.where((container) {
      if (container is TransferableContainer) {
        return container.items.any((item) => item.product.key == product.key);
      }
      return false;
    }).cast<TransferableContainer?>().firstWhere((element) => element != null, orElse: () => null);
    
    if (foundContainer != null) {
      _handleContainerSelection(foundContainer);
    } else {
      // If not found in current containers, create a synthetic container for this product
      try {
        // Create a synthetic TransferableContainer for the selected product
        // This is needed because the product exists in inventory but wasn't loaded
        // in the current container filter (e.g., different delivery note)
        
        final db = await DatabaseHelper.instance.database;
        
        // Get the actual stock records for this product that match our search criteria
        String whereClause;
        List<dynamic> whereArgs;
        
        if (widget.selectedOrder != null) {
          // Order-based putaway
          whereClause = 'urun_key = ? AND siparis_id = ? AND stock_status = ?';
          whereArgs = [product.key, widget.selectedOrder!.id, InventoryTransferConstants.stockStatusReceiving];
        } else if (widget.isFreePutAway) {
          // Free putaway - get all receiving items for this product
          whereClause = 'urun_key = ? AND stock_status = ?';
          whereArgs = [product.key, InventoryTransferConstants.stockStatusReceiving];
        } else if (_selectedSourceLocationName != null && _selectedSourceLocationName != InventoryTransferConstants.receivingAreaCode) {
          // Shelf-to-shelf transfer
          final locationId = _availableSourceLocations[_selectedSourceLocationName];
          whereClause = 'urun_key = ? AND location_id = ? AND stock_status = ?';
          whereArgs = [product.key, locationId, InventoryTransferConstants.stockStatusAvailable];
        } else {
          // Receiving area transfer
          whereClause = 'urun_key = ? AND location_id IS NULL AND stock_status = ?';
          whereArgs = [product.key, InventoryTransferConstants.stockStatusAvailable];
        }
        
        final stockMaps = await db.query('inventory_stock', 
          where: whereClause, 
          whereArgs: whereArgs
        );
        
        if (stockMaps.isNotEmpty) {
          // Create transferable items from stock records
          final items = stockMaps.map((stock) {
            final pallet = stock['pallet_barcode'] as String?;
            final expiryDate = stock['expiry_date'] != null ? DateTime.tryParse(stock['expiry_date'].toString()) : null;
            final quantity = (stock['quantity'] as num).toDouble();
            
            return TransferableItem(
              product: product,
              quantity: quantity,
              sourcePalletBarcode: pallet,
              expiryDate: expiryDate,
            );
          }).toList();
          
          // Create synthetic container
          final containerId = 'synthetic_${product.stockCode}';
          final syntheticContainer = TransferableContainer(
            id: containerId,
            items: items,
            isPallet: false,
          );
          
          // Add to available containers and select it
          setState(() {
            _availableContainers.add(syntheticContainer);
          });
          
          _handleContainerSelection(syntheticContainer);
        } else {
          _showErrorSnackBar('inventory_transfer.error_product_not_available'.tr());
        }
      } catch (e) {
        _showErrorSnackBar('inventory_transfer.error_loading_product_container'.tr(namedArgs: {'error': e.toString()}));
      }
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
    // Otomatik focus yapma - kullanıcı manuel seçsin
    // _containerFocusNode.requestFocus();
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
    // Otomatik focus yapma - kullanıcı manuel tıklayana kadar bekle
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

  // DÜZELTME: Bu fonksiyon artık setState içermiyor, sadece veri getiriyor.
  Future<void> _loadContainersForLocation({bool preserveSelection = false}) async {
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
      // Only reset if not preserving selection (i.e., not reloading after transfer)
      if (!preserveSelection) {
        _resetContainerAndProducts();
      }
    });
    try {
      final repo = _repo;
      // Mal kabul alanı (receiving area) kontrolü
      final bool isReceivingArea = widget.isFreePutAway || locationId == 0;

      List<String> statusesToQuery;
      String? deliveryNoteNumber;

      if (widget.selectedOrder != null) {
        statusesToQuery = [InventoryTransferConstants.stockStatusReceiving];
      } else if (widget.isFreePutAway) {
        statusesToQuery = [InventoryTransferConstants.stockStatusReceiving];
        deliveryNoteNumber = widget.selectedDeliveryNote;
      }
      else {
        statusesToQuery = [InventoryTransferConstants.stockStatusAvailable];
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
          ? InventoryTransferConstants.stockStatusReceiving
          : InventoryTransferConstants.stockStatusAvailable;

      if (_selectedMode == AssignmentMode.pallet && container is String) {
        debugPrint('🔍 PALET İÇERİĞİ YÜKLEME: container=$container, locationId=$locationId, stockStatus=$stockStatus, deliveryNoteNumber=${widget.selectedDeliveryNote}');
        contents = await _repo.getPalletContents(
          container,
          locationId == 0 ? null : locationId,
          stockStatus: stockStatus,
          siparisId: widget.selectedOrder?.id,
          deliveryNoteNumber: widget.isFreePutAway ? widget.selectedDeliveryNote : null,
        );
        debugPrint('🔍 PALET İÇERİĞİ SONUÇ: ${contents.length} ürün bulundu');
      } else if (_selectedMode == AssignmentMode.product && container is TransferableContainer) {
        // KRITIK FIX: Veritabanından güncel miktar bilgilerini çek (cache yerine)
        debugPrint('🔍 PRODUCT CONTAINER İÇERİĞİ YÜKLEME: containerId=${container.id}, locationId=$locationId, stockStatus=$stockStatus');
        contents = await _repo.getProductContainerContents(
          container.id,
          locationId == 0 ? null : locationId,
          stockStatus: stockStatus,
          siparisId: widget.selectedOrder?.id,
          deliveryNoteNumber: widget.isFreePutAway ? widget.selectedDeliveryNote : null,
        );
        debugPrint('🔍 PRODUCT CONTAINER İÇERİĞİ SONUÇ: ${contents.length} ürün bulundu');
      }

      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        for (var product in contents) {
          final initialQty = product.currentQuantity;
          final initialQtyText = initialQty == initialQty.truncate()
              ? initialQty.toInt().toString()
              : initialQty.toString();
          _productQuantityControllers[product.key] = TextEditingController(text: initialQtyText);
          _productQuantityFocusNodes[product.key] = FocusNode();
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

    // Validate target location is selected
    if (_selectedTargetLocationName == null) {
      _showErrorSnackBar('Please select a target location');
      return;
    }

    // Validate source location is selected (except for free put away mode)
    if (!widget.isFreePutAway && _selectedSourceLocationName == null) {
      _showErrorSnackBar('Please select a source location');
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
        // KRITIK FIX: Serbest mal kabul için UUID'yi receiptOperationUuid olarak geç
        // Bu sayede _updateStockForTransfer doğru stoğu bulacak
        receiptOperationUuid: widget.isFreePutAway ? widget.selectedDeliveryNote : null,
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

        // Check if there are still items to transfer before closing the screen
        if(widget.isFreePutAway || widget.selectedOrder != null){
          // Reload containers to check if there are more items to transfer
          // Use preserveSelection: true to avoid clearing the container list during reload
          await _loadContainersForLocation(preserveSelection: true);

          // Only pop if there are no more containers available
          if (_availableContainers.isEmpty) {
            // For order-based or free putaway, go back when done
            Navigator.of(context).pop(true);
          } else {
            // Reset form (selection only - containers already reloaded)
            _resetForm(resetAll: true, preserveContainers: true);
          }
        } else {
          // For shelf-to-shelf transfers, just reset the form
          _resetForm(resetAll: true);
        }
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('inventory_transfer.error_saving'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetContainerAndProducts({bool preserveContainers = false}) {
    _scannedContainerIdController.clear();
    _productSearchController.clear();
    _productSearchResults = [];
    _isSearchingProducts = false;
    _palletSearchResults = [];
    _productsInContainer = [];
    _selectedContainer = null;
    _dynamicProductLabel = null; // Label'ı da temizle
    _clearProductControllers();

    // Only clear containers if not preserving them
    if (!preserveContainers) {
      _availableContainers = [];
    }
  }

  void _resetForm({bool resetAll = false, bool preserveContainers = false}) {
    setState(() {
      _resetContainerAndProducts(preserveContainers: preserveContainers);
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
        // Otomatik focus yapma - kullanıcı manuel tıklayana kadar bekle
        // FocusScope.of(context).requestFocus(resetAll ? _sourceLocationFocusNode : _containerFocusNode);
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
              padding: const EdgeInsets.symmetric(horizontal: InventoryTransferConstants.largePadding, vertical: InventoryTransferConstants.standardGap),
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
                  // Source location - grup halinde hizalama
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _sourceLocationController,
                          focusNode: _sourceLocationFocusNode,
                          enabled: !(widget.selectedOrder != null || widget.isFreePutAway),
                          decoration: SharedInputDecoration.create(
                            context,
                            'inventory_transfer.label_source_location'.tr(),
                            isValid: _isSourceLocationValid,
                            borderRadius: InventoryTransferConstants.borderRadius,
                            horizontalPadding: InventoryTransferConstants.largePadding,
                            verticalPadding: InventoryTransferConstants.largePadding,
                          ),
                          validator: (val) {
                            // Skip validation if field is disabled (free putaway or order-based)
                            if (widget.selectedOrder != null || widget.isFreePutAway) {
                              return null;
                            }
                            return (val == null || val.isEmpty) ? 'inventory_transfer.validator_required_field'.tr() : null;
                          },
                          onFieldSubmitted: (value) async {
                            if (value.trim().isNotEmpty) {
                              await _processScannedData('source', value.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: _smallGap),
                      // QR butonu - sadece enabled durumda göster
                      !(widget.selectedOrder != null || widget.isFreePutAway) 
                        ? _QrButton(
                            onTap: () async {
                              // Gelişmiş klavye kapatma
                              await KeyboardUtils.prepareForQrScanner(context, focusNodes: [_sourceLocationFocusNode]);
                              
                              final result = await Navigator.push<String>(
                                context,
                                MaterialPageRoute(builder: (context) => const QrScannerScreen())
                              );
                              if (result != null && result.isNotEmpty) {
                                _sourceLocationController.text = result;
                                await _processScannedData('source', result);
                              }
                            },
                          )
                        : const SizedBox(width: 56), // Boşluk bırak ki hizalama bozulmasın
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
                        child: QrTextField(
                          controller: _targetLocationController,
                          focusNode: _targetLocationFocusNode,
                          labelText: 'inventory_transfer.label_target_location'.tr(),
                          isValid: _isTargetLocationValid,
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
                          onQrScanned: (result) async {
                            await _processScannedData('target', result);
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(InventoryTransferConstants.borderRadius),
      ),
      padding: const EdgeInsets.all(InventoryTransferConstants.standardGap),
      child: Text(
        widget.deliveryNoteDisplayName ?? widget.selectedDeliveryNote ?? 'common_labels.not_available'.tr(),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onPrimaryContainer,
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
      // Initial barcode error handled
    }

    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _showErrorSnackBar('common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()})));
  }

  void _handleBarcode(String code) {
    if (!mounted) return;

    if (_sourceLocationFocusNode.hasFocus) {
      _sourceLocationController.text = code;
      _processScannedData('source', code);
    } else if (_containerFocusNode.hasFocus) {
      if (_selectedMode == AssignmentMode.product) {
        _productSearchController.text = code;
        _searchProductsForTransfer(code);
      } else {
        _scannedContainerIdController.text = code;
        _processScannedData('container', code);
      }
    } else if (_targetLocationFocusNode.hasFocus) {
      _targetLocationController.text = code;
      _processScannedData('target', code);
    } else {
      // Otomatik focus yapmayı kaldır - sadece veriyi işle
      if (_selectedSourceLocationName == null) {
        // _sourceLocationFocusNode.requestFocus(); // Klavye açar - kaldırıldı
        _sourceLocationController.text = code;
        _processScannedData('source', code);
      } else if (_selectedContainer == null) {
        // _containerFocusNode.requestFocus(); // Klavye açar - kaldırıldı
        if (_selectedMode == AssignmentMode.product) {
          _productSearchController.text = code;
          _searchProductsForTransfer(code);
        } else {
          _scannedContainerIdController.text = code;
          _processScannedData('container', code);
        }
      } else {
        // _targetLocationFocusNode.requestFocus(); // Klavye açar - kaldırıldı
        _targetLocationController.text = code;
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

        return SegmentedButton<AssignmentMode>(
          segments: [
            ButtonSegment(
              value: AssignmentMode.product,
              label: Text('inventory_transfer.mode_product'.tr()),
              icon: const Icon(Icons.inventory_2),
              enabled: _isBoxModeAvailable
            ),
            ButtonSegment(
              value: AssignmentMode.pallet,
              label: Text('inventory_transfer.mode_pallet'.tr()),
              icon: const Icon(Icons.pallet),
              enabled: _isPalletModeAvailable
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

                // Reload containers with new mode
                if (_selectedSourceLocationName != null || widget.isFreePutAway || widget.selectedOrder != null) {
                  _loadContainersForLocation();
                }
              });
            }
          },
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
            if (value) {
              // Break pallet açıldığında tüm miktarları 0 yap
              for (var product in _productsInContainer) {
                _productQuantityControllers[product.key]?.text = '0';
              }
            } else {
              // Break pallet kapatıldığında miktarları geri yükle
              for (var product in _productsInContainer) {
                final initialQty = product.currentQuantity;
                final initialQtyText = initialQty == initialQty.truncate()
                    ? initialQty.toInt().toString()
                    : initialQty.toString();
                _productQuantityControllers[product.key]?.text = initialQtyText;
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
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: _smallGap, vertical: 8),
            itemCount: _productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(height: 10, indent: 16, endIndent: 16, thickness: 0.2),
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

                            // Expiry Date (SKT Bilgisi) ve Stok Kodu
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
                                  // Sadece raftan rafa transferde Qty göster
                                  // if (widget.selectedOrder == null && !widget.isFreePutAway) ...[
                                  //   const SizedBox(width: 8),
                                  //   Text(
                                  //     'Qty: ${product.currentQuantity.toStringAsFixed(product.currentQuantity.truncateToDouble() == product.currentQuantity ? 0 : 2)}',
                                  //     style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  //       fontWeight: FontWeight.bold,
                                  //       fontSize: 12
                                  //     ),
                                  //   ),
                                  // ],
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
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                          decoration: SharedInputDecoration.create(
                            context,
                            'inventory_transfer.label_quantity'.tr(),
                            hintText: product.currentQuantity.toStringAsFixed(product.currentQuantity.truncateToDouble() == product.currentQuantity ? 0 : 2),
                            borderRadius: InventoryTransferConstants.borderRadius,
                            verticalPadding: 8,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'inventory_transfer.validator_required'.tr();
                            final qty = double.tryParse(value);
                            if (qty == null) return 'inventory_transfer.validator_invalid'.tr();
                            if (qty > product.currentQuantity + 0.001) return 'inventory_transfer.validator_max'.tr();
                            if (qty < 0) return 'inventory_transfer.validator_negative'.tr();
                            return null;
                          },
                          onFieldSubmitted: (value) {
                            // Sadece klavyeyi kapat
                            FocusScope.of(context).unfocus();
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
                decoration: SharedInputDecoration.create(
                  context,
                  _selectedMode == AssignmentMode.pallet 
                      ? 'inventory_transfer.label_pallet'.tr() 
                      : _dynamicProductLabel ?? 'inventory_transfer.label_product'.tr(),
                  suffixIcon: _selectedMode == AssignmentMode.product && _isSearchingProducts
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  borderRadius: InventoryTransferConstants.borderRadius,
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'inventory_transfer.validator_required_field'.tr() : null,
                onChanged: _selectedMode == AssignmentMode.product 
                    ? (value) {
                        if (value.isEmpty) {
                          setState(() {
                            _productSearchResults = [];
                            _dynamicProductLabel = null; // Clear label when text is cleared
                          });
                        } else {
                          _searchProductsForTransfer(value);
                        }
                      }
                    : _selectedMode == AssignmentMode.pallet
                        ? (value) {
                            if (value.isEmpty) {
                              setState(() {
                                _palletSearchResults = [];
                              });
                            } else {
                              _searchPalletsForTransfer(value);
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
            _QrButton(
                onTap: () async {
                  // Gelişmiş klavye kapatma - hem container hem product focus'u temizle
                  await KeyboardUtils.prepareForQrScanner(context, focusNodes: [_containerFocusNode, _productSearchFocusNode]);
                  
                  final result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (context) => const QrScannerScreen())
                  );
                  if (result != null && result.isNotEmpty) {
                    setState(() {
                      if (_selectedMode == AssignmentMode.product) {
                        _productSearchController.text = result;
                      } else {
                        _scannedContainerIdController.text = result;
                      }
                    });
                    
                    // Process after UI update
                    if (_selectedMode == AssignmentMode.product) {
                      // Önce arama yap
                      await _searchProductsForTransfer(result);

                      // Eğer arama sonuçları varsa, ilk sonucu otomatik seç (Enter'a basma etkisi)
                      if (_productSearchResults.isNotEmpty) {
                        // Kısa bir gecikme ekle ki UI güncellensin
                        await Future.delayed(const Duration(milliseconds: 100));
                        _selectProductFromSearch(_productSearchResults.first);
                      }
                    } else {
                      await _processScannedData('container', result);
                    }
                  }
                },
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
        // Pallet search results dropdown
        if (_selectedMode == AssignmentMode.pallet && _palletSearchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: _borderRadius,
            ),
            child: Column(
              children: _palletSearchResults.take(5).map((palletId) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.pallet),
                  title: Text(
                    palletId,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () {
                    _selectPalletFromSearch(palletId);
                    _containerFocusNode.unfocus();
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
      height: 56, // Text field ile aynı yükseklik
      width: 56,  // Kare yapı
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(InventoryTransferConstants.borderRadius)),
          padding: EdgeInsets.zero,
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28), // 28 boyutunda icon
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('inventory_transfer.dialog_confirm_transfer'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(InventoryTransferConstants.largePadding),
        children: [
          Text(
            'inventory_transfer.dialog_confirm_transfer_body'.tr(
              namedArgs: {'source': sourceLocationName, 'target': targetLocationName},
            ),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const Divider(height: 24),
          ...items.map((item) => FutureBuilder<String?>(
            future: _getUnitName(item.birimKey),
            builder: (context, snapshot) {
              final unitName = snapshot.data ?? '';
              return ListTile(
                title: Text(item.productName),
                subtitle: Text(item.productCode),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 2),
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (unitName.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        unitName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: InventoryTransferConstants.largePadding),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(InventoryTransferConstants.borderRadius)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('inventory_transfer.dialog_button_confirm'.tr()),
          ),
        ),
      ),
    );
  }
}

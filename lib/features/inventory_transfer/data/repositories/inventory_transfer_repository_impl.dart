// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/inventory_transfer/constants/inventory_transfer_constants.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Helper class to hold stock query information
class _StockQueryInfo {
  final String whereClause;
  final List<dynamic> whereArgs;
  
  _StockQueryInfo(this.whereClause, this.whereArgs);
}

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;

  InventoryTransferRepositoryImpl({required this.dbHelper, required this.dio});

  @override
  Future<Map<String, int?>> getSourceLocations({bool includeReceivingArea = true}) async {
    final db = await dbHelper.database;

    // DÜZELTME: Tüm aktif rafları getir - stok kontrolü container yükleme sırasında yapılacak
    // Bu sayede kullanıcı tüm rafları görebilir, boş rafta container yoksa zaten transfer yapamaz
    final query = '''
      SELECT ${DbColumns.id}, ${DbColumns.locationsName}
      FROM ${DbTables.locations}
      WHERE ${DbColumns.isActive} = 1
      ORDER BY ${DbColumns.locationsName}
    ''';

    final maps = await db.rawQuery(query);
    final result = <String, int?>{};

    if (includeReceivingArea) {
      // Mal kabul alanını ekle
      result[InventoryTransferConstants.receivingAreaCode] = null;
    }

    for (var map in maps) {
      result[map[DbColumns.locationsName] as String] = map[DbColumns.id] as int;
    }
    return result;
  }

  @override
  Future<Map<String, int?>> getTargetLocations({bool excludeReceivingArea = false}) async {
    final db = await dbHelper.database;
    final maps = await db.query(DbTables.locations, where: '${DbColumns.isActive} = 1');
    final result = <String, int?>{};

    if (!excludeReceivingArea) {
      result[InventoryTransferConstants.receivingAreaCode] = null; // Goods receiving area - artık direkt null
    }

    for (var map in maps) {
      result[map[DbColumns.locationsName] as String] = map[DbColumns.id] as int;
    }
    return result;
  }

  @override
  Future<List<String>> getPalletIdsAtLocation(
    int? locationId, {
    List<String> stockStatuses = const [InventoryTransferConstants.stockStatusAvailable],
    String? deliveryNoteNumber,
  }) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereClauses.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    // KRITIK FIX: goods_receipts tablosu sync sonrası silindiği için doğrudan goods_receipt_id kullanıyoruz
    // deliveryNoteNumber parametresi artık goods_receipt_id değerini tutuyor (string olarak)
    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      whereClauses.add('s.goods_receipt_id = ?');
      whereArgs.add(int.parse(deliveryNoteNumber)); // String'den int'e çevir
    }

    final query = '''
      SELECT DISTINCT s.pallet_barcode
      FROM inventory_stock s
      WHERE s.pallet_barcode IS NOT NULL AND ${whereClauses.join(' AND ')}
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  @Deprecated('Use getProductsAtLocation instead')
  Future<List<ProductItem>> getBoxesAtLocation(
    int? locationId, {
    List<String> stockStatuses = const [InventoryTransferConstants.stockStatusAvailable],
    String? deliveryNoteNumber,
  }) async {
    // Delegate to the new method
    return getProductsAtLocation(locationId, stockStatuses: stockStatuses, deliveryNoteNumber: deliveryNoteNumber);
  }

  @override
  Future<List<ProductItem>> getProductsAtLocation(
    int? locationId, {
    List<String> stockStatuses = const [InventoryTransferConstants.stockStatusAvailable],
    String? deliveryNoteNumber,
  }) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      final placeholders = stockStatuses.map((_) => '?').join(', ');
      whereClauses.add('s.stock_status IN ($placeholders)');
      whereArgs.addAll(stockStatuses);
    }

    // KRITIK FIX: goods_receipts tablosu sync sonrası silindiği için doğrudan goods_receipt_id kullanıyoruz
    // deliveryNoteNumber parametresi artık goods_receipt_id değerini tutuyor (string olarak)
    if (deliveryNoteNumber != null) {
      whereClauses.add('s.goods_receipt_id = ?');
      whereArgs.add(int.parse(deliveryNoteNumber)); // String'den int'e çevir
    }

    final query = '''
      SELECT
        s.id as stock_id,
        u._key as product_id,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        (SELECT bark.barkod FROM barkodlar bark WHERE bark._key_scf_stokkart_birimleri = s.birim_key LIMIT 1) as barcode,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_key = u._key
      WHERE ${whereClauses.join(' AND ')} AND s.pallet_barcode IS NULL
      GROUP BY u._key, u.UrunAdi, u.StokKodu, s.birim_key
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    // Convert to ProductItem using the fromJson factory
    return maps.map((map) => ProductItem.fromJson({
      'productKey': map['product_id']?.toString() ?? '',
      'name': map['product_name']?.toString() ?? '',
      'productCode': map['product_code']?.toString() ?? '',
      'barcode': map['barcode']?.toString(),
      'currentQuantity': map['quantity'],
    })).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletBarcode, int? locationId, {String stockStatus = InventoryTransferConstants.stockStatusAvailable, int? siparisId, String? deliveryNoteNumber}) async {
    final db = await dbHelper.database;

    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    whereParts.add('s.pallet_barcode = ?');
    whereArgs.add(palletBarcode);

    if (locationId == null) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    whereParts.add('s.stock_status = ?');
    whereArgs.add(stockStatus);

    if (siparisId != null) {
      whereParts.add('s.siparis_id = ?');
      whereArgs.add(siparisId);
    }

    // Free receipt için delivery note kontrolü
    // KRITIK FIX: deliveryNoteNumber parametresi artık goods_receipt_id değerini tutuyor (string olarak)
    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      // Önce numeric ID olup olmadığını kontrol et
      final parsedId = int.tryParse(deliveryNoteNumber);
      if (parsedId != null) {
        // Numeric ise direkt goods_receipt_id olarak kullan
        whereParts.add('s.goods_receipt_id = ?');
        whereArgs.add(parsedId);
      } else {
        // String ise gerçek delivery note number, ID'yi bul
        final goodsReceiptId = await getGoodsReceiptIdByDeliveryNote(deliveryNoteNumber);
        if (goodsReceiptId != null) {
          whereParts.add('s.goods_receipt_id = ?');
          whereArgs.add(goodsReceiptId);
        } else {
          // Delivery note bulunamazsa boş liste döndür
          return [];
        }
      }
    }

    final query = '''
      SELECT
        u._key as productKey,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        s.birim_key,
        (SELECT bark.barkod FROM barkodlar bark WHERE bark._key_scf_stokkart_birimleri = s.birim_key LIMIT 1) as barcode,
        s.quantity as currentQuantity,
        s.expiry_date as expiryDate
      FROM inventory_stock s
      JOIN urunler u ON s.urun_key = u._key
      WHERE ${whereParts.join(' AND ')}
      ORDER BY u.UrunAdi
    ''';

    final maps = await db.rawQuery(query, whereArgs);

    final result = maps.map((map) => ProductItem.fromJson(map)).toList();

    return result;
  }

  @override
  Future<void> recordTransferOperation(
    TransferOperationHeader header,
    List<TransferItemDetail> items,
    int? sourceLocationId,
    int targetLocationId,
  ) async {
    final db = await dbHelper.database;
    try {
      // Validate transfer items before processing
      _validateTransferItems(items);
      
      await db.transaction((txn) async {
        await _executeTransferTransaction(
          txn,
          header,
          items,
          sourceLocationId,
          targetLocationId,
        );
      });
    } catch (e) {
      throw Exception('Lokal veritabanına transfer kaydedilirken hata oluştu: $e');
    }
  }

  /// Validates transfer items before processing the transfer operation.
  /// Ensures all items have valid product information and required fields.
  void _validateTransferItems(List<TransferItemDetail> items) {
    // Product information validation - can be expanded as needed
    // Current implementation assumes items are pre-validated
    if (items.isEmpty) {
      throw ArgumentError('Transfer items list cannot be empty');
    }
  }

  /// Executes the complete transfer transaction with all necessary steps.
  /// Handles stock updates, transfer records, and pending operations.
  Future<void> _executeTransferTransaction(
    DatabaseExecutor txn,
    TransferOperationHeader header,
    List<TransferItemDetail> items,
    int? sourceLocationId,
    int targetLocationId,
  ) async {
    // Generate unique operation ID
    final pendingOp = PendingOperation.create(
      type: PendingOperationType.inventoryTransfer,
      data: "{}", // Temporary
      createdAt: DateTime.now().toUtc(),
    );
    final String operationUniqueId = pendingOp.uniqueId;
    
    // Process all transfer items
    final itemsForJson = await _processTransferItems(
      txn,
      items,
      header,
      sourceLocationId,
      targetLocationId,
      operationUniqueId,
    );

    // Get purchase order ID if available
    String? poId;
    if (header.siparisId != null) {
      final maps = await txn.query(
        DbTables.orders,
        columns: ['fisno'],
        where: 'id = ?',
        whereArgs: [header.siparisId],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        poId = maps.first['fisno'] as String?;
      }
    }

    // Prepare header JSON
    final headerJson = header.toApiJson(sourceLocationId ?? 0, targetLocationId);
    if (poId != null) {
      headerJson['fisno'] = poId;
    }

    // Save pending operation
    final finalPendingOp = PendingOperation.create(
      uniqueId: operationUniqueId,
      type: PendingOperationType.inventoryTransfer,
      data: jsonEncode({
        'operation_unique_id': operationUniqueId,
        'header': headerJson,
        'items': itemsForJson,
      }),
      createdAt: pendingOp.createdAt,
    );

    await txn.insert(DbTables.pendingOperations, finalPendingOp.toDbMap());

    // Complete putaway if necessary
    if (header.siparisId != null) {
      await checkAndCompletePutaway(header.siparisId!);
    }
  }

  /// Processes all transfer items by updating stock and creating transfer records.
  /// Returns a list of processed items for API synchronization.
  Future<List<Map<String, dynamic>>> _processTransferItems(
    DatabaseExecutor txn,
    List<TransferItemDetail> items,
    TransferOperationHeader header,
    int? sourceLocationId,
    int targetLocationId,
    String operationUniqueId,
  ) async {
    final List<Map<String, dynamic>> itemsForJson = [];

    for (final item in items) {
      // Generate UUID for new stock record
      const uuid = Uuid();
      final transferStockUuid = uuid.v4();

      // Update stock for this transfer item
      await _updateStockForTransfer(
        txn,
        item,
        header,
        sourceLocationId,
        targetLocationId,
        transferStockUuid,
      );

      // Create transfer record
      final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;
      await txn.insert(DbTables.inventoryTransfers, {
        'operation_unique_id': operationUniqueId,
        'urun_key': item.productKey,
        'birim_key': item.birimKey,
        'from_location_id': sourceLocationId,
        'to_location_id': targetLocationId,
        'quantity': item.quantity,
        'from_pallet_barcode': item.palletId,
        'pallet_barcode': targetPalletId,
        'employee_id': header.employeeId,
        'transfer_date': header.transferDate.toIso8601String(),
      });

      // Handle putaway-specific logic
      if (sourceLocationId == null && header.siparisId != null) {
        await txn.query(
          DbTables.orderLines,
          columns: ['id'],
          where: 'siparisler_id = ? AND urun_key = ? AND turu = ?',
          whereArgs: [header.siparisId, item.productKey, '1'],
          limit: 1,
        );
      }

      // Prepare item for API sync
      final itemWithUuid = TransferItemDetail(
        productKey: item.productKey,
        birimKey: item.birimKey,
        productName: item.productName,
        productCode: item.productCode,
        quantity: item.quantity,
        palletId: item.palletId,
        expiryDate: item.expiryDate,
        stockUuid: transferStockUuid,
        targetLocationId: item.targetLocationId,
        targetLocationName: item.targetLocationName,
      );
      itemsForJson.add(itemWithUuid.toApiJson());
    }

    return itemsForJson;
  }

  /// Updates stock for a single transfer item by decrementing source and incrementing target.
  /// Handles source stock identification and maintains data consistency.
  Future<void> _updateStockForTransfer(
    DatabaseExecutor txn,
    TransferItemDetail item,
    TransferOperationHeader header,
    int? sourceLocationId,
    int targetLocationId,
    String transferStockUuid,
  ) async {
    // Find source stock information
    String sourceWhereClause = 'urun_key = ? AND stock_status = ?';
    List<dynamic> sourceWhereArgs = [
      item.productKey,
      (sourceLocationId == null || sourceLocationId == 0) 
          ? InventoryTransferConstants.stockStatusReceiving 
          : InventoryTransferConstants.stockStatusAvailable
    ];
    
    // Add constraints for birim_key
    if (item.birimKey == null) {
      sourceWhereClause += ' AND birim_key IS NULL';
    } else {
      sourceWhereClause += ' AND birim_key = ?';
      sourceWhereArgs.add(item.birimKey);
    }
    
    // Add constraints for location_id
    if (sourceLocationId == null || sourceLocationId == 0) {
      sourceWhereClause += ' AND location_id IS NULL';
    } else {
      sourceWhereClause += ' AND location_id = ?';
      sourceWhereArgs.add(sourceLocationId);
    }
    
    // Add constraints for pallet_barcode
    if (item.palletId == null) {
      sourceWhereClause += ' AND pallet_barcode IS NULL';
    } else {
      sourceWhereClause += ' AND pallet_barcode = ?';
      sourceWhereArgs.add(item.palletId);
    }
    
    // Add order/goods_receipt filter for putaway operations
    if (sourceLocationId == null || sourceLocationId == 0) {
      if (header.siparisId != null) {
        sourceWhereClause += ' AND siparis_id = ?';
        sourceWhereArgs.add(header.siparisId);
      } else if (header.goodsReceiptId != null) {
        // KRITIK FIX: Free receipt için goods_receipt_id filtresi ekle
        sourceWhereClause += ' AND goods_receipt_id = ?';
        sourceWhereArgs.add(header.goodsReceiptId);
      }
    }
    
    // Get source stock info
    debugPrint('🔄 TRANSFER SOURCE QUERY: WHERE $sourceWhereClause, ARGS: $sourceWhereArgs');
    final sourceStockQuery = await txn.query(
      'inventory_stock',
      where: sourceWhereClause,
      whereArgs: sourceWhereArgs,
      limit: 1,
    );
    debugPrint('🔄 TRANSFER SOURCE RESULT: ${sourceStockQuery.length} kayıt bulundu');

    int? sourceSiparisId;
    int? sourceGoodsReceiptId;

    if (sourceStockQuery.isNotEmpty) {
      sourceSiparisId = sourceStockQuery.first['siparis_id'] as int?;
      sourceGoodsReceiptId = sourceStockQuery.first['goods_receipt_id'] as int?;
      debugPrint('🔄 TRANSFER SOURCE INFO: id=${sourceStockQuery.first['id']}, siparis_id=$sourceSiparisId, goods_receipt_id=$sourceGoodsReceiptId, pallet=${sourceStockQuery.first['pallet_barcode']}, qty=${sourceStockQuery.first['quantity']}');
    }

    // Decrement source stock
    await _updateStockSmart(
      txn,
      productId: item.productKey,
      birimKey: item.birimKey,
      locationId: sourceLocationId,
      quantityChange: -item.quantity,
      palletId: item.palletId,
      status: (sourceLocationId == null) 
          ? InventoryTransferConstants.stockStatusReceiving 
          : InventoryTransferConstants.stockStatusAvailable,
      siparisIdForAddition: sourceSiparisId,
      goodsReceiptIdForAddition: sourceGoodsReceiptId,
      expiryDateForAddition: item.expiryDate,
      isTransferOperation: false,
    );

    // Increment target stock
    final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;
    await _updateStockSmart(
      txn,
      productId: item.productKey,
      birimKey: item.birimKey,
      locationId: targetLocationId,
      quantityChange: item.quantity,
      palletId: targetPalletId,
      status: InventoryTransferConstants.stockStatusAvailable,
      siparisIdForAddition: null, // Available status uses null for consolidation
      goodsReceiptIdForAddition: null, // Available status uses null for consolidation
      expiryDateForAddition: item.expiryDate,
      isTransferOperation: false,
      stockUuid: transferStockUuid,
    );
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer() async {
    final db = await dbHelper.database;
    final prefs = await SharedPreferences.getInstance();

    // Get warehouse name from SharedPreferences
    final warehouseName = prefs.getString('warehouse_name');
    
    // If warehouse not found, don't filter by warehouse (temporary solution)
    if (warehouseName == null) {
      // Warehouse name not found for this code, getting all orders
    }

    // FIX: Show orders that have either inventory_stock OR goods_receipt_items for put-away
    final maps = await db.rawQuery('''
      SELECT DISTINCT
        o.id,
        o.fisno,
        o.tarih,
        o.notlar,
        ? as warehouse_name,
        o.status,
        o.created_at,
        o.updated_at,
        t.tedarikci_adi as supplierName
      FROM siparisler o
      LEFT JOIN inventory_stock i ON i.siparis_id = o.id AND i.stock_status = '${InventoryTransferConstants.stockStatusReceiving}' AND i.quantity > 0
      LEFT JOIN siparis_ayrintili s ON s.siparisler_id = o.id AND s.turu = '1'
      LEFT JOIN tedarikci t ON t.tedarikci_kodu = o.__carikodu
      WHERE o.status = 2
        AND i.id IS NOT NULL
      GROUP BY o.id, o.fisno, o.tarih, o.notlar, o.status, o.created_at, o.updated_at, t.tedarikci_adi
      ORDER BY o.created_at DESC
    ''', [warehouseName ?? 'N/A']);
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int? locationId, {int? orderId, String? deliveryNoteNumber}) async {
    final db = await dbHelper.database;
    final isPutaway = orderId != null || deliveryNoteNumber != null;

    final List<Map<String, dynamic>> stockMaps;

    if (isPutaway) {
      if (orderId != null) {
        // BASIT YAKLAŞIM: Sadece inventory_stock'taki miktarı kullan
        // Transfer hesaplaması şimdilik devre dışı - sadece mevcut stok miktarını göster
        stockMaps = await db.rawQuery('''
          SELECT 
            i.id,
            i.urun_key,
            i.birim_key,
            i.location_id,
            i.pallet_barcode,
            i.expiry_date,
            i.stock_status,
            i.siparis_id,
            i.goods_receipt_id,
            i.quantity
          FROM inventory_stock i
          WHERE i.stock_status = '${InventoryTransferConstants.stockStatusReceiving}'
            AND i.siparis_id = ?
            AND i.quantity > 0
        ''', [orderId]);
      } else if (deliveryNoteNumber != null) {
        // Free receipt putaway - find stocks by delivery note
        // KRITIK FIX: deliveryNoteNumber artık goods_receipt_id değerini tutuyor (string olarak)
        final parsedId = int.tryParse(deliveryNoteNumber);
        final int? goodsReceiptId;

        if (parsedId != null) {
          // Numeric ise direkt goods_receipt_id olarak kullan
          goodsReceiptId = parsedId;
        } else {
          // String ise gerçek delivery note number, ID'yi bul
          goodsReceiptId = await getGoodsReceiptIdByDeliveryNote(deliveryNoteNumber);
        }

        if (goodsReceiptId == null) {
          return [];
        }
        // KRITIK FIX: Serbest mal kabul için siparis_id IS NULL olmalı
        // Sadece goods_receipt_id dolu VE siparis_id NULL olan receiving stoklarını göster
        stockMaps = await db.query(DbTables.inventoryStock, where: 'goods_receipt_id = ? AND siparis_id IS NULL AND stock_status = ? AND quantity > 0', whereArgs: [goodsReceiptId, InventoryTransferConstants.stockStatusReceiving]);
      } else {
        stockMaps = [];
      }
    } else {
      // KRITIK FIX: Serbest transfer için sipariş bazlı stokları hariç tut
      // Sadece siparis_id = NULL olan stokları göster (serbest stoklar)
      if (locationId == null) {
        stockMaps = await db.query(DbTables.inventoryStock, where: 'location_id IS NULL AND siparis_id IS NULL AND stock_status = ? AND quantity > 0', whereArgs: [InventoryTransferConstants.stockStatusAvailable]);
      } else {
        stockMaps = await db.query(DbTables.inventoryStock, where: 'location_id = ? AND siparis_id IS NULL AND stock_status = ? AND quantity > 0', whereArgs: [locationId, InventoryTransferConstants.stockStatusAvailable]);
      }
    }

    if (stockMaps.isEmpty) {
      return [];
    }

    final productIds = stockMaps.map((e) => e['urun_key'] as String).toSet();
    
    final productsQuery = await db.rawQuery('''
      SELECT 
        u.*,
        MAX(bark.barkod) as barkod,
        b._key as birim_key,
        b.birimadi as birimadi,
        b.birimkod as birimkod
      FROM urunler u
      LEFT JOIN birimler b ON b.StokKodu = u.StokKodu
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE u._key IN (${productIds.map((_) => '?').join(',')})
      GROUP BY u._key
    ''', productIds.toList());
    final productDetails = <String, ProductInfo>{};
    for (var p in productsQuery) {
      final productMap = Map<String, dynamic>.from(p);
      if (productMap['barkod'] != null) {
        productMap['barkod_info'] = {'barkod': productMap['barkod']};
      }
      
      final productInfo = ProductInfo.fromDbMap(productMap);
      productDetails[p['_key'] as String] = productInfo;
    }

    final Map<String, Map<String, TransferableItem>> aggregatedItems = {};

    for (final stock in stockMaps) {
      final productId = stock['urun_key'] as String;
      var productInfo = productDetails[productId];
      if (productInfo == null) continue;
      
      // KRITIK FIX: inventory_stock'taki birim_key değerini kullan
      final stockBirimKey = stock['birim_key'] as String?;
      if (stockBirimKey != null) {
        // ProductInfo'nun birimInfo'sunu güncelle
        final updatedBirimInfo = Map<String, dynamic>.from(productInfo.birimInfo ?? {});
        updatedBirimInfo['birim_key'] = stockBirimKey;
        
        productInfo = ProductInfo(
          id: productInfo.id,
          productKey: productInfo.productKey,
          name: productInfo.name,
          stockCode: productInfo.stockCode,
          isActive: productInfo.isActive,
          birimInfo: updatedBirimInfo,
          barkodInfo: productInfo.barkodInfo,
          isOutOfOrder: productInfo.isOutOfOrder,
          quantityReceived: productInfo.quantityReceived,
        );
      }

      final pallet = stock['pallet_barcode'] as String?;
      final expiryDate = stock['expiry_date'] != null ? DateTime.tryParse(stock['expiry_date'].toString()) : null;
      final containerId = pallet ?? 'box_${productInfo.stockCode}';

      // KRITIK FIX: Paletin içindeki ve serbest ürünleri ayırmak için containerId kullan
      // Normal transfer için de container bazında grupla (pallet var mı yok mu diye)
      final groupingKey = containerId;

      aggregatedItems.putIfAbsent(groupingKey, () => {});

      if (aggregatedItems[groupingKey]!.containsKey(productId)) {
        final existingItem = aggregatedItems[groupingKey]![productId]!;
        aggregatedItems[groupingKey]![productId] = TransferableItem(
          product: existingItem.product,
          quantity: existingItem.quantity + (stock['quantity'] as num).toDouble(),
          sourcePalletBarcode: pallet,
          expiryDate: existingItem.expiryDate,
        );
      } else {
        aggregatedItems[groupingKey]![productId] = TransferableItem(
          product: productInfo,
          quantity: (stock['quantity'] as num).toDouble(),
          sourcePalletBarcode: pallet,
          expiryDate: expiryDate,
        );
      }
    }

    final result = aggregatedItems.entries.map((entry) {
      final containerId = entry.key;
      final itemsMap = entry.value;
      final isPallet = itemsMap.values.first.sourcePalletBarcode != null;

      return TransferableContainer(
        id: containerId,
        isPallet: isPallet,
        items: itemsMap.values.toList(),
      );
    }).toList();

    return result;
  }

  @override
  Future<Set<int>> getOrderIdsWithTransferableItems(List<int> orderIds) async {
    if (orderIds.isEmpty) {
      return {};
    }
    final db = await dbHelper.database;
    final idList = orderIds.map((id) => '?').join(',');
    final query = '''
      SELECT DISTINCT siparis_id
      FROM inventory_stock
      WHERE siparis_id IN ($idList)
      AND stock_status = '${InventoryTransferConstants.stockStatusReceiving}'
      AND quantity > 0
    ''';
    final result = await db.rawQuery(query, orderIds);
    return result.map((row) => row['siparis_id'] as int).toSet();
  }

  @override
  Future<MapEntry<String, int?>?> findLocationByCode(String code) async {
    final db = await dbHelper.database;
    final cleanCode = code.toLowerCase().trim();

    if (cleanCode.contains('kabul') || cleanCode.contains('receiving') || cleanCode == '0' || cleanCode == InventoryTransferConstants.receivingAreaCode) {
      return const MapEntry(InventoryTransferConstants.receivingAreaCode, null); // Artık null döndürüyoruz
    }

    final maps = await db.query(
      'shelfs',
      where: 'LOWER(code) = ? AND is_active = 1',
      whereArgs: [cleanCode],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return MapEntry(maps.first['name'] as String, maps.first['id'] as int);
    }
    return null;
  }

  @override
  Future<void> checkAndCompletePutaway(int orderId, {Transaction? txn}) async {
    // Rafa yerleştirme artık sipariş statusunu değiştirmiyor
    // Status sadece mal kabul aşamasında belirleniyor (0,1,2,3)
    // Bu metod artık sadece putaway takibi için kullanılıyor, status güncellemesi yapmıyor
  }

  @override
  Future<List<ProductInfo>> getProductInfoByBarcode(String barcode) async {
    // Yeni barkodlar tablosunu kullan
    final result = await dbHelper.getProductByBarcode(barcode);
    if (result != null) {
      return [ProductInfo.fromDbMap(result)];
    }
    return [];
  }

  @override
  @Deprecated('Use findProductByCodeAtLocation instead')
  Future<ProductItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']}) async {
    // Delegate to the new method
    return findProductByCodeAtLocation(productCodeOrBarcode, locationId, stockStatuses: stockStatuses);
  }

  @override
  Future<ProductItem?> findProductByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;

    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereParts.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    // Sadece barkodlar tablosundan ara
    final productResult = await dbHelper.getProductByBarcode(productCodeOrBarcode);
    if (productResult == null) {
      // Barkod bulunamadı, null döndür
      return null;
    }
    
    // Barkod ile bulunan ürünün _key'ini kullan
    whereParts.add('u._key = ?');
    whereArgs.add(productResult['_key']);

    whereParts.add('s.pallet_barcode IS NULL');

    final query = '''
      SELECT
        s.id as stock_id,
        u._key as product_id,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        (SELECT bark.barkod FROM barkodlar bark WHERE bark._key_scf_stokkart_birimleri = s.birim_key LIMIT 1) as barcode,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_key = u._key
      WHERE ${whereParts.join(' AND ')}
      GROUP BY u._key, u.UrunAdi, u.StokKodu, s.birim_key
      LIMIT 1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    if (maps.isNotEmpty) {
      // Convert to ProductItem
      final map = maps.first;
      return ProductItem.fromJson({
        'productKey': map['product_id']?.toString() ?? '',
        'name': map['product_name']?.toString() ?? '',
        'productCode': map['product_code']?.toString() ?? '',
        'barcode': map['barcode']?.toString(),
        'currentQuantity': map['quantity'],
      });
    }
    return null;
  }

  Future<void> _updateStockSmart(
    DatabaseExecutor txn, {
    required String productId, // urun_key değeri String olarak
    String? birimKey, // birim_key değeri
    required int? locationId,
    required double quantityChange,
    required String? palletId,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
    DateTime? expiryDateForAddition,
    bool isTransferOperation = false, // YENI: Transfer işlemi olup olmadığını belirler
    String? stockUuid, // KRITIK FIX: Phone-generated UUID
  }) async {
    if (quantityChange == 0) return;

    final isDecrement = quantityChange < 0;

    if (isDecrement) {
      await _processStockDecrement(
        txn,
        productId: productId,
        birimKey: birimKey,
        locationId: locationId,
        quantityChange: quantityChange,
        palletId: palletId,
        status: status,
        siparisIdForAddition: siparisIdForAddition,
        goodsReceiptIdForAddition: goodsReceiptIdForAddition,
      );
    } else {
      await _processStockIncrement(
        txn,
        productId: productId,
        birimKey: birimKey,
        locationId: locationId,
        quantityChange: quantityChange,
        palletId: palletId,
        status: status,
        siparisIdForAddition: siparisIdForAddition,
        goodsReceiptIdForAddition: goodsReceiptIdForAddition,
        expiryDateForAddition: expiryDateForAddition,
        isTransferOperation: isTransferOperation,
        stockUuid: stockUuid,
      );
    }
  }

  /// Builds a WHERE clause and arguments for stock queries based on the provided criteria.
  /// Returns a StockQueryInfo object containing the clause and arguments.
  _StockQueryInfo _buildStockQuery({
    required String productId,
    String? birimKey,
    required int? locationId,
    required String? palletId,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
    DateTime? expiryDateForAddition,
    bool includeOrderFilters = false,
  }) {
    String whereClause = 'urun_key = ? AND stock_status = ?';
    List<dynamic> whereArgs = [productId, status];
    
    // birim_key kontrolü
    if (birimKey == null) {
      whereClause += ' AND birim_key IS NULL';
    } else {
      whereClause += ' AND birim_key = ?';
      whereArgs.add(birimKey);
    }
    
    // Location_id kontrolü
    if (locationId == null) {
      whereClause += ' AND location_id IS NULL';
    } else {
      whereClause += ' AND location_id = ?';
      whereArgs.add(locationId);
    }
    
    // Pallet_barcode kontrolü
    if (palletId == null) {
      whereClause += ' AND pallet_barcode IS NULL';
    } else {
      whereClause += ' AND pallet_barcode = ?';
      whereArgs.add(palletId);
    }
    
    // Include order-related filters if requested
    if (includeOrderFilters) {
      // KRITIK FIX: İki farklı strateji (Backend ile uyumlu)
      // 1. Sipariş bazlı mal kabul (siparis_id dolu): siparis_id ile filtrele
      // 2. Serbest mal kabul (siparis_id NULL): goods_receipt_id ile filtrele
      if (status == 'receiving') {
        if (siparisIdForAddition != null) {
          // Sipariş bazlı: Sadece siparis_id ile filtrele
          whereClause += ' AND siparis_id = ?';
          whereArgs.add(siparisIdForAddition);
        } else if (goodsReceiptIdForAddition != null) {
          // Serbest mal kabul: Sadece goods_receipt_id ile filtrele
          whereClause += ' AND goods_receipt_id = ?';
          whereArgs.add(goodsReceiptIdForAddition);
        }
      }
    }

    return _StockQueryInfo(whereClause, whereArgs);
  }

  /// Processes stock increment (addition) operations with consolidation logic.
  /// Handles both new stock creation and updating existing stock records.
  Future<void> _processStockIncrement(
    DatabaseExecutor txn, {
    required String productId,
    String? birimKey,
    required int? locationId,
    required double quantityChange,
    required String? palletId,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
    DateTime? expiryDateForAddition,
    bool isTransferOperation = false,
    String? stockUuid,
  }) async {
    // KRITIK FIX: expiry_date'i normalize et - konsolidasyon için consistent format gerekli
    final expiryDateStr = expiryDateForAddition != null 
      ? DateTime(expiryDateForAddition.year, expiryDateForAddition.month, expiryDateForAddition.day).toIso8601String().split('T')[0]
      : null;

    // Build query for existing stock consolidation
    final queryInfo = _buildStockQuery(
      productId: productId,
      birimKey: birimKey,
      locationId: locationId,
      palletId: palletId,
      status: status,
      siparisIdForAddition: siparisIdForAddition,
      goodsReceiptIdForAddition: goodsReceiptIdForAddition,
      expiryDateForAddition: expiryDateForAddition,
    );
    
    String existingWhereClause = queryInfo.whereClause;
    List<dynamic> existingWhereArgs = queryInfo.whereArgs;
      
    // Expiry date kontrolü (siparis_id ve goods_receipt_id artık unique constraint'te yok)
    if (expiryDateStr == null) {
      existingWhereClause += ' AND expiry_date IS NULL';
    } else {
      existingWhereClause += ' AND expiry_date = ?';
      existingWhereArgs.add(expiryDateStr);
    }

    // Handle consolidation logic based on status and transfer type
    final existingStock = await _consolidateStocks(
      txn,
      existingWhereClause: existingWhereClause,
      existingWhereArgs: existingWhereArgs,
      status: status,
      siparisIdForAddition: siparisIdForAddition,
      goodsReceiptIdForAddition: goodsReceiptIdForAddition,
      isTransferOperation: isTransferOperation,
    );

    if (existingStock.isNotEmpty) {
      // Update existing stock - KRITIK FIX: UUID bazlı güncelleme
      final currentQty = (existingStock.first['quantity'] as num).toDouble();
      final newQty = currentQty + quantityChange;
      final stockUuid = existingStock.first['stock_uuid'] as String;
      await txn.update(
        'inventory_stock',
        {'quantity': newQty, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'stock_uuid = ?',
        whereArgs: [stockUuid],
      );
    } else {
      // Create new stock record
      final finalStockUuid = stockUuid ?? const Uuid().v4();
      
      await txn.insert(DbTables.inventoryStock, {
        'stock_uuid': finalStockUuid, // Phone-generated UUID (parametreli)
        'urun_key': productId,
        'birim_key': birimKey,
        'location_id': locationId, // Artık null ise null kalıyor
        'quantity': quantityChange,
        'pallet_barcode': palletId,
        'stock_status': status,
        'siparis_id': siparisIdForAddition,
        'goods_receipt_id': goodsReceiptIdForAddition,
        'created_at': DateTime.now().toUtc().toIso8601String(), // DÜZELTME: created_at eklendi
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'expiry_date': expiryDateStr,
      });
    }
  }

  /// Processes stock decrement (reduction) operations using FIFO logic.
  /// Handles partial and complete stock removal with proper error checking.
  Future<void> _processStockDecrement(
    DatabaseExecutor txn, {
    required String productId,
    String? birimKey,
    required int? locationId,
    required double quantityChange,
    required String? palletId,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
  }) async {
    double remainingToDecrement = quantityChange.abs();

    // Build query for finding source stock
    final queryInfo = _buildStockQuery(
      productId: productId,
      birimKey: birimKey,
      locationId: locationId,
      palletId: palletId,
      status: status,
      siparisIdForAddition: siparisIdForAddition,
      goodsReceiptIdForAddition: goodsReceiptIdForAddition,
      includeOrderFilters: true,
    );

    final stockEntries = await txn.query(
      'inventory_stock',
      where: queryInfo.whereClause,
      whereArgs: queryInfo.whereArgs,
      orderBy: 'expiry_date ASC', // FIFO
    );

    if (stockEntries.isEmpty) {
      throw Exception('Kaynakta stok bulunamadı. Ürün ID: $productId, Lokasyon: $locationId');
    }

    for (final stock in stockEntries) {
      final stockUuid = stock['stock_uuid'] as String;
      final currentQty = (stock['quantity'] as num).toDouble();

      if (currentQty >= remainingToDecrement) {
        final newQty = currentQty - remainingToDecrement;
        if (newQty > 0.001) {
          // KRITIK FIX: UUID bazlı güncelleme
          await txn.update(DbTables.inventoryStock, {
            'quantity': newQty,
            'updated_at': DateTime.now().toUtc().toIso8601String()
          }, where: 'stock_uuid = ?', whereArgs: [stockUuid]);
        } else {
          // KRITIK FIX: UUID bazlı silme
          await txn.delete(DbTables.inventoryStock, where: 'stock_uuid = ?', whereArgs: [stockUuid]);
        }
        remainingToDecrement = 0;
        break;
      } else {
        remainingToDecrement -= currentQty;
        // KRITIK FIX: UUID bazlı silme
        await txn.delete(DbTables.inventoryStock, where: 'stock_uuid = ?', whereArgs: [stockUuid]);
      }
    }

    if (remainingToDecrement > 0.001) {
      throw Exception('Kaynakta yeterli stok bulunamadı. İstenen: ${quantityChange.abs()}, Eksik: $remainingToDecrement');
    }
  }

  /// Handles stock consolidation logic based on status and operation type.
  /// Returns existing stock records that can be consolidated or empty list for new records.
  Future<List<Map<String, Object?>>> _consolidateStocks(
    DatabaseExecutor txn, {
    required String existingWhereClause,
    required List<dynamic> existingWhereArgs,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
    bool isTransferOperation = false,
  }) async {
    // KRITIK FIX: Transfer işlemlerinde konsolidasyon YAPMAMA - her transfer yeni kayıt oluştursun
    // Transfer sırasında sadece birebir kayıt oluştur, konsolide etme
    if (isTransferOperation) {
      // Transfer edilen kayıtlar için konsolidasyon yapma - her zaman yeni kayıt oluştur
      // Bu sayede çift sayma önlenir
      return [];
    } else if (status == 'available') {
      // Normal available stoklarda konsolidasyon yap (transfer dışı durumlar)
      if (siparisIdForAddition == null) {
        existingWhereClause += ' AND siparis_id IS NULL';
      } else {
        existingWhereClause += ' AND siparis_id = ?';
        existingWhereArgs.add(siparisIdForAddition);
      }
      
      if (goodsReceiptIdForAddition == null) {
        existingWhereClause += ' AND goods_receipt_id IS NULL';
      } else {
        existingWhereClause += ' AND goods_receipt_id = ?';
        existingWhereArgs.add(goodsReceiptIdForAddition);
      }
    } else if (status == 'receiving') {
      // KRITIK FIX: İki farklı strateji (Backend ile uyumlu)
      // 1. Sipariş bazlı mal kabul (siparis_id dolu): siparis_id ile grupla, goods_receipt_id KULLANMA
      // 2. Serbest mal kabul (siparis_id NULL): goods_receipt_id ile grupla
      if (siparisIdForAddition != null) {
        // Sipariş bazlı: Sadece siparis_id kontrolü yap
        existingWhereClause += ' AND siparis_id = ?';
        existingWhereArgs.add(siparisIdForAddition);
        // goods_receipt_id kontrolü YOK - farklı delivery note'lar birleşir
      } else {
        // Serbest mal kabul: Sadece goods_receipt_id kontrolü yap
        if (goodsReceiptIdForAddition == null) {
          existingWhereClause += ' AND goods_receipt_id IS NULL';
        } else {
          existingWhereClause += ' AND goods_receipt_id = ?';
          existingWhereArgs.add(goodsReceiptIdForAddition);
        }
        // siparis_id kontrolü YOK (zaten NULL)
      }
    }

    // Transfer işlemi değilse konsolidasyon kontrolü yap
    return await txn.query(
      'inventory_stock',
      where: existingWhereClause,
      whereArgs: existingWhereArgs,
      limit: 1,
    );
  }

  @override
  Future<List<String>> getFreeReceiptDeliveryNotes() async {
    final db = await dbHelper.database;

    // KRITIK FIX: goods_receipts tablosu sync sonrası silindiği için doğrudan inventory_stock'tan alalım
    // Artık goods_receipt_id döndürüyoruz (string olarak)
    const query = '''
      SELECT DISTINCT CAST(s.goods_receipt_id AS TEXT) as delivery_note_number
      FROM inventory_stock s
      WHERE s.siparis_id IS NULL
        AND s.goods_receipt_id IS NOT NULL
        AND s.stock_status = '${InventoryTransferConstants.stockStatusReceiving}'
        AND s.quantity > 0
      ORDER BY s.goods_receipt_id DESC
    ''';

    final maps = await db.rawQuery(query);
    return maps.map((map) => map['delivery_note_number'] as String).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getFreeReceiptsForPutaway() async {
    return await dbHelper.getFreeReceiptsForPutaway();
  }

  @override
  Future<bool> hasOrderReceivedWithPallets(int orderId) async {
    final db = await dbHelper.database;
    const query = '''
      SELECT COUNT(*) as count
      FROM inventory_stock
      WHERE siparis_id = ?
        AND stock_status = '${InventoryTransferConstants.stockStatusReceiving}'
        AND pallet_barcode IS NOT NULL
        AND quantity > 0
    ''';
    final result = await db.rawQuery(query, [orderId]);
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  @override
  Future<bool> hasOrderReceivedWithProducts(int orderId) async {
    final db = await dbHelper.database;
    const query = '''
      SELECT COUNT(*) as count
      FROM inventory_stock
      WHERE siparis_id = ?
        AND stock_status = '${InventoryTransferConstants.stockStatusReceiving}'
        AND pallet_barcode IS NULL
        AND quantity > 0
    ''';
    final result = await db.rawQuery(query, [orderId]);
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  @override
  Future<int?> getGoodsReceiptIdByDeliveryNote(String deliveryNoteNumber) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'goods_receipts',
      columns: ['goods_receipt_id'],
      where: 'delivery_note_number = ?',
      whereArgs: [deliveryNoteNumber],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['goods_receipt_id'] as int?;
    }
    return null;
  }

  @override
  Future<List<ProductInfo>> searchProductsForTransfer(String query, {
    int? orderId,
    String? deliveryNoteNumber, 
    int? locationId,
    List<String> stockStatuses = const [InventoryTransferConstants.stockStatusAvailable, InventoryTransferConstants.stockStatusReceiving],
    bool excludePalletizedProducts = false, // YENI: Paletin içindeki ürünleri hariç tut
  }) async {
    final db = await dbHelper.database;
    
    // Build WHERE clauses based on context
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];
    
    // Search by barcode or StokKodu (moved to WHERE clause for LEFT JOIN compatibility)
    // Will be handled separately in SQL query
    
    // Add stock status filter
    if (stockStatuses.isNotEmpty) {
      whereClauses.add('s.stock_status IN (${stockStatuses.map((_) => '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }
    
    // YENI: Paletin içindeki ürünleri hariç tut (Product Mode için)
    if (excludePalletizedProducts) {
      whereClauses.add('s.pallet_barcode IS NULL');
    }
    
    // Add context-specific filters
    if (orderId != null) {
      // Search products related to specific order
      whereClauses.add('s.siparis_id = ?');
      whereArgs.add(orderId);
    } else if (deliveryNoteNumber != null) {
      // KRITIK FIX: deliveryNoteNumber artık goods_receipt_id değerini tutuyor
      whereClauses.add('s.goods_receipt_id = ?');
      whereArgs.add(int.parse(deliveryNoteNumber));
    } else if (locationId != null) {
      // Search products at specific location
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    } else {
      // Search all available products (no additional filter)
    }

    // Add search parameters for barcode and StokKodu
    // KRITIK FIX: Türkçe karakter ve büyük/küçük harf duyarsız arama için LOWER() kullan
    final searchPattern = '%${query.toLowerCase()}%';
    whereArgs.insert(0, searchPattern);  // For StokKodu search
    whereArgs.insert(0, searchPattern);  // For barcode search

    final whereClause = whereClauses.isNotEmpty ? ' AND ' + whereClauses.join(' AND ') : '';

    final sql = '''
      SELECT
        u._key,
        u.UrunAdi,
        u.StokKodu,
        u.aktif,
        bark.barkod
      FROM urunler u
      INNER JOIN inventory_stock s ON s.urun_key = u._key
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = s.birim_key
      WHERE (LOWER(bark.barkod) LIKE ? OR LOWER(u.StokKodu) LIKE ?) $whereClause AND s.quantity > 0
      GROUP BY u._key, u.UrunAdi, u.StokKodu, u.aktif, bark.barkod
      ORDER BY u.UrunAdi ASC
    ''';
    
    final maps = await db.rawQuery(sql, whereArgs);
    final results = maps.map((map) => ProductInfo.fromDbMap(map)).toList();
    return results;
  }
}

import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;
  final SyncService syncService;

  GoodsReceivingRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
    required this.syncService,
  });

  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    debugPrint("--- Mal Kabul Kaydı Başlatılıyor ---");
    debugPrint("Header: ${jsonEncode(payload.header.toJson())}");
    debugPrint("Items: ${jsonEncode(payload.items.map((e) => e.toJson()).toList())}");
    debugPrint("------------------------------------");
    await _saveGoodsReceiptLocally(payload);
  }

  Future<void> _saveGoodsReceiptLocally(GoodsReceiptPayload payload) async {
    final db = await dbHelper.database;

    try {
      await db.transaction((txn) async {
        // 1. ADIM: UNIQUE ID'Yİ ÖNCEDEN AL
        final pendingOp = PendingOperation.create(
          type: PendingOperationType.goodsReceipt,
          data: "{}",
          createdAt: DateTime.now().toUtc(),
        );
        final String operationUniqueId = pendingOp.uniqueId;

        // 2. ADIM: GOODS RECEIPT KAYDINI ETİKETLE
        final receiptHeaderData = {
          'operation_unique_id': operationUniqueId, // Tag and Replace reconciliation için
          'siparis_id': payload.header.siparisId,
          'invoice_number': payload.header.invoiceNumber,
          'delivery_note_number': payload.header.deliveryNoteNumber,
          'employee_id': payload.header.employeeId,
          'receipt_date': payload.header.receiptDate.toIso8601String(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        final receiptId = await txn.insert(DbTables.goodsReceipts, receiptHeaderData);

        const stockStatus = 'receiving';

        debugPrint("Processing ${payload.items.length} items...");
        
        // KRITIK FIX: Her item için UUID'leri önceden üret ve sakla
        final Map<int, String> itemStockUuids = {};
        
        for (var i = 0; i < payload.items.length; i++) {
          final item = payload.items[i];
          debugPrint("Inserting item: ${item.productId}, qty: ${item.quantity}");
          // KRITIK DEBUG: birimKey değerini kontrol et
          debugPrint("GOODS_RECEIPT_REPO DEBUG: birimKey = ${item.birimKey}");
          
          // Her item için UUID üret
          const uuid = Uuid();
          final stockUuid = uuid.v4();
          itemStockUuids[i] = stockUuid;
          
          final itemId = await txn.insert(DbTables.goodsReceiptItems, {
            'receipt_id': receiptId,
            'urun_key': item.productId, // _key değeri direkt kullanılıyor
            'birim_key': item.birimKey, // Birim _key değeri
            'quantity_received': item.quantity,
            'pallet_barcode': item.palletBarcode,
            'barcode': item.barcode, // DÜZELTME: barcode alanı eklendi
            'expiry_date': item.expiryDate?.toIso8601String(),
            'free': item.isFree ? 1 : 0, // Sipariş dışı ürün işaretleme
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
          debugPrint("Item inserted with ID: $itemId");

          debugPrint("Updating stock for: ${item.productId} with UUID: ${stockUuid}");
          await _updateStockWithKey(
              txn,
              item.productId, // _key değeri string olarak
              item.birimKey, // birim_key değeri
              null, // locationId is null for receiving area
              item.quantity,
              item.palletBarcode,
              stockStatus,
              payload.header.siparisId,
              item.expiryDate?.toIso8601String(),
              receiptId,
              stockUuid); // KRITIK: Stock UUID'yi geçir
          debugPrint("Stock updated for: ${item.productId}");
        }

        if (payload.header.siparisId != null) {
          await _checkAndUpdateOrderStatus(txn, payload.header.siparisId!);
        }

        final enrichedData = await _createEnrichedGoodsReceiptData(txn, payload, itemStockUuids);
        // Tag and Replace reconciliation için operation_unique_id ekle
        enrichedData['operation_unique_id'] = operationUniqueId;

        final pendingOpForSync = PendingOperation.create(
          type: PendingOperationType.goodsReceipt,
          data: jsonEncode(enrichedData),
          createdAt: DateTime.now().toUtc(),
        );
        // Unique ID'yi override et - aynı olmalı
        final finalPendingOp = PendingOperation(
          id: pendingOpForSync.id,
          uniqueId: operationUniqueId, // Aynı unique ID kullan
          type: pendingOpForSync.type,
          data: pendingOpForSync.data,
          status: pendingOpForSync.status,
          createdAt: pendingOpForSync.createdAt,
          errorMessage: pendingOpForSync.errorMessage,
        );
        await txn.insert(DbTables.pendingOperations, finalPendingOp.toDbMap());

        // inventory_stock'lar normal table sync ile backend'den mobile'a gelecek
        // Pending operation sync gereksiz ve duplicate veri trafiği yaratır
        // await _createInventoryStockPendingOperation(txn, receiptId); // REMOVED
      });
      debugPrint("Mal kabul işlemi ve sipariş durumu başarıyla lokale kaydedildi.");
    } catch (e) {
      debugPrint("Lokal mal kabul kaydı hatası: $e");
      throw Exception("Lokal veritabanına kaydederken bir hata oluştu: $e");
    }
  }

  Future<Map<String, dynamic>> _createEnrichedGoodsReceiptData(Transaction txn, GoodsReceiptPayload payload, Map<int, String> itemStockUuids) async {
    final apiData = payload.toApiJson();

    if (payload.header.siparisId != null) {
      final poResult = await txn.query(
        DbTables.orders,
        columns: [DbColumns.ordersFisno],
        where: '${DbColumns.id} = ?',
        whereArgs: [payload.header.siparisId],
        limit: 1,
      );
      if (poResult.isNotEmpty) {
        apiData['header']['fisno'] = poResult.first[DbColumns.ordersFisno];
      }
    }

    final enrichedItems = <Map<String, dynamic>>[];
    if (payload.items.isNotEmpty) {
      for (var i = 0; i < payload.items.length; i++) {
        final item = payload.items[i];
        final itemData = item.toJson();
        
        // KRITIK FIX: Önceden üretilen Stock UUID'yi payload'a ekle
        final stockUuid = itemStockUuids[i];
        if (stockUuid != null) {
          itemData['stock_uuid'] = stockUuid;
        }
        
        final productResult = await txn.query(
          DbTables.products,
          columns: [DbColumns.productsName, DbColumns.productsCode],
          where: '${DbColumns.productsId} = ?',
          whereArgs: [item.productId],
          limit: 1,
        );
        if (productResult.isNotEmpty) {
          itemData['product_name'] = productResult.first[DbColumns.productsName];
          itemData['product_code'] = productResult.first[DbColumns.productsCode];
        }
        enrichedItems.add(itemData);
      }
      apiData['items'] = enrichedItems;
    }
    return apiData;
  }

  // DEPRECATED: Stock management moved to backend only to prevent duplicate entries
  // This method is kept for reference but should not be used
  Future<void> _updateStockWithKey(Transaction txn, String urunKey, String? birimKey, int? locationId, double quantityChange, String? palletBarcode, String stockStatus, [int? siparisId, String? expiryDate, int? goodsReceiptId, String? stockUuid]) async {
    // NULL-safe WHERE clause construction
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];
    
    whereClauses.add('urun_key = ?');
    whereArgs.add(urunKey);
    
    whereClauses.add('stock_status = ?');
    whereArgs.add(stockStatus);
    
    if (birimKey == null) {
      whereClauses.add('birim_key IS NULL');
    } else {
      whereClauses.add('birim_key = ?');
      whereArgs.add(birimKey);
    }
    
    if (locationId == null) {
      whereClauses.add('location_id IS NULL');
    } else {
      whereClauses.add('location_id = ?');
      whereArgs.add(locationId);
    }
    
    if (palletBarcode == null) {
      whereClauses.add('pallet_barcode IS NULL');
    } else {
      whereClauses.add('pallet_barcode = ?');
      whereArgs.add(palletBarcode);
    }
    
    // KRITIK FIX: Backend mantığı ile aynı
    // 'receiving' durumunda siparis_id'yi dahil et - farklı siparişler ayrı tutulmalı
    // 'available' durumunda siparis_id'yi dahil etme - konsolidasyon için
    if (stockStatus == 'receiving') {
      if (siparisId == null) {
        whereClauses.add('siparis_id IS NULL');
      } else {
        whereClauses.add('siparis_id = ?');
        whereArgs.add(siparisId);
      }
    }
    // 'available' durumunda siparis_id kontrolü YOK - konsolidasyon için
    
    if (expiryDate == null) {
      whereClauses.add('expiry_date IS NULL');
    } else {
      // KRITIK FIX: Expiry date format normalization
      // Backend'de "2025-12-12", telefonda "2025-12-12T00:00:00.000"
      // DATE() function ile normalize et
      whereClauses.add('DATE(expiry_date) = DATE(?)');
      whereArgs.add(expiryDate);
    }
    
    // KRITIK FIX: Backend'de goods_receipt_id kontrol edilmiyor
    // Farklı goods receipt'ler aynı koşullarda birleştirilmeli
    // goods_receipt_id kontrolü kaldırıldı

    final whereClause = whereClauses.join(' AND ');
    final existingStock = await txn.query('inventory_stock',
        where: whereClause,
        whereArgs: whereArgs);

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final oldQty = (currentStock['quantity'] as num).toDouble();
      final newQty = oldQty + quantityChange;
      
      if (newQty > 0.001) {
        await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id = ?', whereArgs: [currentStock['id']]);
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [currentStock['id']]);
      }
    } else if (quantityChange > 0) {
      // UUID kullan (parametre olarak gelmişse) veya yeni üret
      final finalStockUuid = stockUuid ?? () {
        const uuid = Uuid();
        return uuid.v4();
      }();
      
      await txn.insert('inventory_stock', {
        'stock_uuid': finalStockUuid,
        'urun_key': urunKey,
        'birim_key': birimKey,
        'location_id': locationId,
        'quantity': quantityChange,
        'pallet_barcode': palletBarcode,
        'stock_status': stockStatus,
        'siparis_id': siparisId,
        'expiry_date': expiryDate,
        'goods_receipt_id': goodsReceiptId, // DÜZELTME: goods_receipt_id mal kabulde kaydedilmeli
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await dbHelper.database;
    final openOrdersMaps = await db.rawQuery('''
      SELECT DISTINCT
        o.${DbColumns.id},
        o.${DbColumns.ordersFisno},
        o.${DbColumns.ordersDate},
        o.${DbColumns.ordersNotes},
        o.${DbColumns.status},
        o.${DbColumns.createdAt},
        o.${DbColumns.updatedAt},
        t.${DbColumns.suppliersName} as supplierName
      FROM ${DbTables.orders} o
      LEFT JOIN ${DbTables.suppliers} t ON t.${DbColumns.suppliersCode} = o.${DbColumns.ordersSupplierCode}
      WHERE o.${DbColumns.status} IN (0, 1)
      ORDER BY o.${DbColumns.createdAt} DESC
    ''');
    return openOrdersMaps.map((orderMap) => PurchaseOrder.fromMap(orderMap)).toList();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    debugPrint("DEBUG: Getting items for order ID: $orderId");

    // FIX: DISTINCT kullanarak duplike kayıtları engelle
    // Barkod JOIN'ini kaldıralım, sadece temel bilgileri alalım
    final orderLines = await db.rawQuery('''
      SELECT DISTINCT
        sa.*,
        u.UrunAdi,
        u.StokKodu,
        u._key as urun_key,
        b.birimadi,
        b._key as birim_key,
        bark.barkod
      FROM siparis_ayrintili sa
      JOIN urunler u ON sa.kartkodu = u.StokKodu
      LEFT JOIN birimler b ON CAST(sa.sipbirimkey AS TEXT) = b._key
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE sa.siparisler_id = ? AND sa.turu = '1'
      ORDER BY sa.id
    ''', [orderId]);

    final items = <PurchaseOrderItem>[];
    
    // Her sipariş satırı için zaten doğru birim bilgisi mevcut
    for (final line in orderLines) {
      final urunKey = line['urun_key'] as String?;
      final productCode = line['StokKodu'] as String?;
      
      if (urunKey == null || productCode == null) {
        debugPrint("DEBUG: Skipping order line due to missing keys. Line ID: ${line['id']}");
        continue;
      }

      debugPrint("DEBUG: Processing order line - Product: $productCode, Unit: ${line['birimadi']}, Ordered: ${line['miktar']}");
      debugPrint("DEBUG: sipbirimkey: ${line['sipbirimkey']}, birim_key: ${line['birim_key']}");

      // Alınan miktarı hesapla - bulunan urunKey'i kullan
      final receivedQuantityResult = await db.rawQuery('''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE gr.siparis_id = ? AND gri.urun_key = ?
      ''', [orderId, urunKey]);

      final receivedQuantity = receivedQuantityResult.isNotEmpty 
          ? (receivedQuantityResult.first['total_received'] as num).toDouble() 
          : 0.0;

      // Yerleştirme miktarını al
      final putawayResult = await db.query(
        'wms_putaway_status',
        columns: ['putaway_quantity'],
        where: 'purchase_order_line_id = ?',
        whereArgs: [line['id']],
        limit: 1,
      );

      final transferredQuantity = putawayResult.isNotEmpty 
          ? (putawayResult.first['putaway_quantity'] as num).toDouble() 
          : 0.0;

      // Enriched map oluştur - line zaten tüm JOIN bilgilerini içeriyor
      final enrichedMap = Map<String, dynamic>.from(line);
      enrichedMap['receivedQuantity'] = receivedQuantity;
      enrichedMap['transferredQuantity'] = transferredQuantity;
      
      // Debug: Hangi birimin hangi miktarda sipariş edildiğini göster
      debugPrint("DEBUG: Order line - Product: $productCode, Unit: ${line['birimadi']}, sipbirimkey: ${line['sipbirimkey']}, Expected: ${line['miktar']}");
      
      items.add(PurchaseOrderItem.fromDb(enrichedMap));
    }

    debugPrint("DEBUG: Found ${items.length} items for order $orderId");
    return items;
  }

  @override
  Future<List<PurchaseOrder>> getReceivablePurchaseOrders() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DbTables.orders,
      where: '${DbColumns.status} = ?',
      whereArgs: [1], // Partially received
      orderBy: '${DbColumns.ordersDate} DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, int newStatus) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final poResult = await txn.query(DbTables.orders,
          columns: ['fisno'], where: 'id = ?', limit: 1, whereArgs: [orderId]);
      final fisno = poResult.isNotEmpty ? poResult.first[DbColumns.ordersFisno] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'fisno': fisno, 'status': newStatus}),
          createdAt: DateTime.now());
      await txn.insert(DbTables.pendingOperations, pendingOp.toDbMap());

      await txn.update(
        DbTables.orders,
        {'status': newStatus},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
    debugPrint("Sipariş #$orderId lokal durumu $newStatus olarak güncellendi ve senkronizasyon için sıraya alındı.");
  }

  @override
  Future<void> markOrderAsComplete(int orderId) async {
    final db = await dbHelper.database;

    await db.transaction((txn) async {
      final poResult = await txn.query(
          DbTables.orders,
          columns: ['fisno'],
          where: 'id = ?',
          limit: 1,
          whereArgs: [orderId]
      );
      final fisno = poResult.isNotEmpty ? poResult.first[DbColumns.ordersFisno] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'fisno': fisno}),
          createdAt: DateTime.now()
      );
      await txn.insert(DbTables.pendingOperations, pendingOp.toDbMap());

      await txn.update(
        DbTables.orders,
        {'status': 2}, // Status 2: Manually Closed
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });

    debugPrint("Sipariş #$orderId lokal olarak manuel kapatıldı (status 2) ve senkronizasyon için sıraya alındı.");
  }

  @override
  Future<List<ProductInfo>> searchProducts(String query, {int? orderId}) async {
    // TEST: İlk aramada siparişteki tüm barkodları listele
    if (orderId != null) {
      await dbHelper.debugOrderBarcodes(orderId);
    }
    
    final results = await dbHelper.searchProductsByBarcode(query, orderId: orderId);
    return results.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductInfo>> getAllActiveProducts() async {
    final db = await dbHelper.database;
    const query = '''
      SELECT
        u.*,
        MAX(bark.barkod) as barcode
      FROM urunler u
      LEFT JOIN birimler b ON u.StokKodu = b.StokKodu
      LEFT JOIN barkodlar bark ON b._key = bark._key_scf_stokkart_birimleri
      GROUP BY u.UrunId
      ORDER BY u.UrunAdi ASC
    ''';
    final maps = await db.rawQuery(query);
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<ProductInfo?> findProductByExactMatch(String code) async {
    // Sadece barkod ile arama yap
    return findProductByBarcodeExactMatch(code);
  }

  @override
  Future<ProductInfo?> findProductByBarcodeExactMatch(String barcode, {int? orderId}) async {
    debugPrint("🔍 DEBUG: findProductByBarcodeExactMatch aranan barkod: '$barcode', orderId: $orderId");

    if (orderId != null) {
      // Sipariş bazlı arama: Tüm birimleri al ve önceliği siparişli birimlere ver
      final results = await dbHelper.getAllProductsByBarcode(barcode, orderId: orderId);
      
      if (results.isNotEmpty) {
        // Önce siparişli birim (source_type = 'order') varsa onu tercih et
        final orderUnits = results.where((r) => r['source_type'] == 'order');
        if (orderUnits.isNotEmpty) {
          final orderUnit = orderUnits.first;
          debugPrint("✅ DEBUG: Sipariş içi birim bulundu: ${orderUnit['birimadi']}, miktar: ${orderUnit['miktar']}");
          return ProductInfo.fromDbMap(orderUnit);
        }
        
        // Sipariş dışı birim varsa (source_type = 'out_of_order')
        final outOfOrderUnits = results.where((r) => r['source_type'] == 'out_of_order');
        if (outOfOrderUnits.isNotEmpty) {
          final outOfOrderUnit = outOfOrderUnits.first;
          debugPrint("⚠️ DEBUG: Sipariş dışı birim bulundu: ${outOfOrderUnit['birimadi']}, miktar: 0 (sipariş dışı)");
          return ProductInfo.fromDbMap(outOfOrderUnit);
        }
      }
    }

    // Genel arama (orderId null ise)
    final result = await dbHelper.getProductByBarcode(barcode); // orderId: null
    
    if (result != null) {
      debugPrint("✅ DEBUG: Genel aramada bulunan ürün: $result");
      return ProductInfo.fromDbMap(result);
    } else {
      debugPrint("❌ DEBUG: Barkod ile ürün bulunamadı: '$barcode'");
      return null;
    }
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query(DbTables.locations, where: '${DbColumns.isActive} = 1');
    return maps.map((map) => LocationInfo.fromMap(map)).toList();
  }

  Future<void> _checkAndUpdateOrderStatus(Transaction txn, int siparisId) async {
    final orderLines = await txn.rawQuery('''
      SELECT
        sol.${DbColumns.id},
        u.${DbColumns.productsId} as product_id,
        sol.${DbColumns.orderLinesQuantity} as ordered_quantity,
        COALESCE(SUM(gri.quantity_received), 0) as total_received
      FROM ${DbTables.orderLines} sol
      JOIN ${DbTables.products} u ON u.${DbColumns.productsCode} = sol.${DbColumns.orderLinesProductCode}
      LEFT JOIN ${DbTables.goodsReceiptItems} gri ON gri.${DbColumns.orderLinesProductId} = u.${DbColumns.productsId}
      LEFT JOIN ${DbTables.goodsReceipts} gr ON gr.goods_receipt_id = gri.receipt_id AND gr.siparis_id = sol.${DbColumns.orderLinesOrderId}
      WHERE sol.${DbColumns.orderLinesOrderId} = ? AND sol.${DbColumns.orderLinesType} = '${DbColumns.orderLinesTypeValue}'
      GROUP BY sol.${DbColumns.id}, u.${DbColumns.productsId}, sol.${DbColumns.orderLinesQuantity}
    ''', [siparisId]);

    if (orderLines.isEmpty) return;

    bool anyLineReceived = false;

    for (final line in orderLines) {
      final receivedQty = (line['total_received'] as num).toDouble();

      if (receivedQty > 0) {
        anyLineReceived = true;
        break; // Herhangi bir satırda kabul varsa yeterli
      }
    }

    // Sadece kısmi kabul (status 1) veya hiç kabul yok (status 0) durumları
    int newStatus = anyLineReceived ? 1 : 0;

    await txn.update(
      DbTables.orders,
      {DbColumns.status: newStatus, DbColumns.updatedAt: DateTime.now().toUtc().toIso8601String()},
      where: '${DbColumns.id} = ?',
      whereArgs: [siparisId],
    );
  }

  // Duplicate functions removed - they already exist in the file

  /// DEBUG: Manuel olarak free değerini güncelle  
  @override
  Future<void> debugUpdateFreeValues(int orderId, String urunKey) async {
    await dbHelper.debugUpdateFreeValues(orderId, urunKey);
  }

  @override
  Future<List<ProductInfo>> getOutOfOrderReceiptItems(int orderId) async {
    final db = await dbHelper.database;
    
    // DEBUG: Önce bu sipariş için tüm receipt items'ları kontrol et
    final allItems = await db.rawQuery('''
      SELECT gri.*, gr.siparis_id, gri.free
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      WHERE gr.siparis_id = ?
    ''', [orderId]);
    
    debugPrint("DEBUG: All receipt items for order $orderId:");
    for (final item in allItems) {
      debugPrint("  - ID: ${item['receipt_id']}, urun_key: ${item['urun_key']}, quantity: ${item['quantity_received']}, free: ${item['free']}");
    }
    
    // DEBUG: Özellikle free=1 olan items'ları kontrol et
    final freeItems = await db.rawQuery('''
      SELECT gri.*, gr.siparis_id, gri.free
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      WHERE gr.siparis_id = ? AND gri.free = 1
    ''', [orderId]);
    
    debugPrint("DEBUG: Items with free=1 for order $orderId: ${freeItems.length}");
    for (final item in freeItems) {
      debugPrint("  - FREE ITEM: ID: ${item['receipt_id']}, urun_key: ${item['urun_key']}, quantity: ${item['quantity_received']}");
    }
    
    // DEBUG: 99488 key'li items'ları özel kontrol et  
    final items99488 = allItems.where((item) => item['urun_key'] == '99488').toList();
    debugPrint("DEBUG: Items with urun_key=99488: ${items99488.length}");
    for (final item in items99488) {
      debugPrint("  - 99488 ITEM: ID: ${item['receipt_id']}, free: ${item['free']}, quantity: ${item['quantity_received']}");
    }
    
    // Sipariş dışı kabul edilen ürünleri al (free = 1) - JOIN'leri kaldır duplicate count'u önlemek için
    final outOfOrderMaps = await db.rawQuery('''
      SELECT 
        u.*,
        u._key as product_key,
        u.UrunAdi as name,
        u.StokKodu as code,
        SUM(gri.quantity_received) as quantity_received,
        MAX(gri.free) as free,
        'out_of_order' as source_type
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      JOIN urunler u ON u._key = gri.urun_key
      WHERE gr.siparis_id = ? AND gri.free = 1
      GROUP BY u._key, u.UrunAdi, u.StokKodu
      ORDER BY MAX(gri.receipt_id) DESC
    ''', [orderId]);
    
    debugPrint("DEBUG: Found ${outOfOrderMaps.length} out-of-order receipt items for order $orderId");
    
    // DEBUG: Her bir out-of-order item'ın detaylarını göster
    for (final map in outOfOrderMaps) {
      debugPrint("DEBUG: OUT-OF-ORDER ITEM - urun_key: ${map['product_key']}, name: ${map['name']}, quantity_received: ${map['quantity_received']}, birimadi: ${map['birimadi']}");
    }
    
    return outOfOrderMaps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  // Inventory stock pending operation sync removed - normal table sync kullanılacak
}

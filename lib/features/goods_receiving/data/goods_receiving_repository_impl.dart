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
        final receiptHeaderData = {
          'siparis_id': payload.header.siparisId,
          'invoice_number': payload.header.invoiceNumber,
          'delivery_note_number': payload.header.deliveryNoteNumber,
          'employee_id': payload.header.employeeId,
          'receipt_date': payload.header.receiptDate.toIso8601String(),
          DbColumns.createdAt: DateTime.now().toIso8601String(),
        };
        final receiptId = await txn.insert(DbTables.goodsReceipts, receiptHeaderData);

        const stockStatus = 'receiving';

        for (final item in payload.items) {
          await txn.insert(DbTables.goodsReceiptItems, {
            'receipt_id': receiptId,
            DbColumns.orderLinesProductId: item.urunId,
            'quantity_received': item.quantity,
            DbColumns.stockPalletBarcode: item.palletBarcode,
            DbColumns.stockExpiryDate: item.expiryDate?.toIso8601String(),
          });

          await _updateStock(
              txn,
              item.urunId,
              null, // locationId is null for receiving area
              item.quantity,
              item.palletBarcode,
              stockStatus,
              payload.header.siparisId,
              item.expiryDate?.toIso8601String(),
              receiptId);
        }

        if (payload.header.siparisId != null) {
          await _checkAndUpdateOrderStatus(txn, payload.header.siparisId!);
        }

        final enrichedData = await _createEnrichedGoodsReceiptData(txn, payload);

        final pendingOp = PendingOperation.create(
          type: PendingOperationType.goodsReceipt,
          data: jsonEncode(enrichedData),
          createdAt: DateTime.now(),
        );
        await txn.insert(DbTables.pendingOperations, pendingOp.toDbMap());
      });
      debugPrint("Mal kabul işlemi ve sipariş durumu başarıyla lokale kaydedildi.");
    } catch (e) {
      debugPrint("Lokal mal kabul kaydı hatası: $e");
      throw Exception("Lokal veritabanına kaydederken bir hata oluştu: $e");
    }
  }

  Future<Map<String, dynamic>> _createEnrichedGoodsReceiptData(Transaction txn, GoodsReceiptPayload payload) async {
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
      for (final item in payload.items) {
        final itemData = item.toJson();
        final productResult = await txn.query(
          DbTables.products,
          columns: [DbColumns.productsName, DbColumns.productsCode],
          where: '${DbColumns.productsId} = ?',
          whereArgs: [item.urunId],
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

  Future<void> _updateStock(Transaction txn, int urunId, int? locationId, double quantityChange, String? palletBarcode, String stockStatus, [int? siparisId, String? expiryDate, int? goodsReceiptId]) async {
    String locationWhereClause = locationId == null ? 'location_id IS NULL' : 'location_id = ?';
    String palletWhereClause = palletBarcode == null ? 'pallet_barcode IS NULL' : 'pallet_barcode = ?';
    String siparisWhereClause = siparisId == null ? 'siparis_id IS NULL' : 'siparis_id = ?';
    String expiryWhereClause = expiryDate == null ? 'expiry_date IS NULL' : 'expiry_date = ?';
    String goodsReceiptWhereClause = goodsReceiptId == null ? 'goods_receipt_id IS NULL' : 'goods_receipt_id = ?';

    List<dynamic> whereArgs = [urunId, stockStatus];
    if (locationId != null) whereArgs.add(locationId);
    if (palletBarcode != null) whereArgs.add(palletBarcode);
    if (siparisId != null) whereArgs.add(siparisId);
    if (expiryDate != null) whereArgs.add(expiryDate);
    if (goodsReceiptId != null) whereArgs.add(goodsReceiptId);

    final existingStock = await txn.query('inventory_stock',
        where: 'urun_id = ? AND stock_status = ? AND $locationWhereClause AND $palletWhereClause AND $siparisWhereClause AND $expiryWhereClause AND $goodsReceiptWhereClause',
        whereArgs: whereArgs);

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final newQty = (currentStock['quantity'] as num) + quantityChange;
      if (newQty > 0.001) {
        await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [currentStock['id']]);
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [currentStock['id']]);
      }
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': quantityChange,
        'pallet_barcode': palletBarcode,
        'updated_at': DateTime.now().toIso8601String(),
        'stock_status': stockStatus,
        'siparis_id': siparisId,
        'expiry_date': expiryDate,
        'goods_receipt_id': goodsReceiptId
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
      ORDER BY o.${DbColumns.ordersDate} DESC
    ''');
    return openOrdersMaps.map((orderMap) => PurchaseOrder.fromMap(orderMap)).toList();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    debugPrint("DEBUG: Getting items for order ID: $orderId");

    // Önce temel sipariş satırlarını alalım
    final orderLines = await db.query(
      'siparis_ayrintili',
      where: 'siparisler_id = ? AND turu = ?',
      whereArgs: [orderId, '1'],
    );

    final items = <PurchaseOrderItem>[];
    
    // Her bir satır için ürün ve barkod bilgilerini ayrı ayrı alalım
    for (final line in orderLines) {
      // HATA DÜZELTMESİ: urun_id null ise kartkodu ile ürün ID'sini bul
      int? urunId = line['urun_id'] as int?;
      final productCode = line['kartkodu'] as String?;
      
      if (urunId == null && productCode != null) {
        debugPrint("DEBUG: urun_id is null, trying to find via productCode: $productCode. Line ID: ${line['id']}");
        final productResult = await db.query(
          'urunler',
          columns: ['UrunId'],
          where: 'StokKodu = ?',
          whereArgs: [productCode],
          limit: 1,
        );
        if (productResult.isNotEmpty) {
          urunId = productResult.first['UrunId'] as int?;
          debugPrint("DEBUG: Found urun_id $urunId for productCode $productCode");
        }
      }
      
      if (urunId == null) {
        debugPrint("DEBUG: Skipping order line because urun_id could not be resolved. Line ID: ${line['id']}");
        continue;
      }
      if (productCode == null) continue;

      // Ürün bilgisini al - UrunId kullanarak sorgula (daha güvenilir)
      final productResult = await db.query(
        'urunler',
        where: 'UrunId = ?',
        whereArgs: [urunId],
        limit: 1,
      );

      if (productResult.isEmpty) {
        continue;
      }
      final productMap = productResult.first;

      // GET BARCODE CORRECTLY ACCORDING TO ORDER UNIT
      final unitCode = line['anabirimi'] as String?;
      String? barcode;
      
      if (unitCode != null) {
        final barcodeResult = await db.rawQuery('''
          SELECT bark.barkod 
          FROM birimler b 
          JOIN barkodlar bark ON b._key = bark._key_scf_stokkart_birimleri
          WHERE b.StokKodu = ? AND b.birimkod = ?
          LIMIT 1
        ''', [productCode, unitCode]);

        if (barcodeResult.isNotEmpty) {
          barcode = barcodeResult.first['barkod'] as String?;
        }
      }

      // Alınan miktarı hesapla - bulunan urunId'yi kullan
      final receivedQuantityResult = await db.rawQuery('''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE gr.siparis_id = ? AND gri.urun_id = ?
      ''', [orderId, urunId]);

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

      // Tüm bilgileri birleştirelim
      final enrichedMap = Map<String, dynamic>.from(line);
      enrichedMap.addAll(productMap);
      enrichedMap['receivedQuantity'] = receivedQuantity;
      enrichedMap['transferredQuantity'] = transferredQuantity;
      
      // HATA DÜZELTMESİ: Bulunan urun_id'yi kullan
      debugPrint("DEBUG: Using resolved urun_id: $urunId, Product UrunId: ${productMap['UrunId']}");
      enrichedMap['urun_id'] = urunId;
      
      // Barkod bilgisini ekleyelim
      if (barcode != null) {
        enrichedMap['barkod'] = barcode;
      }

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
  Future<ProductInfo?> findProductByBarcodeExactMatch(String barcode) async {
    debugPrint("🔍 DEBUG: findProductByBarcodeExactMatch aranan barkod: '$barcode'");

    final result = await dbHelper.getProductByBarcode(barcode);
    
    if (result != null) {
      debugPrint("✅ DEBUG: Barkod ile bulunan ürün: $result");
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

    bool allLinesCompleted = true;
    bool anyLineReceived = false;

    for (final line in orderLines) {
      final orderedQty = (line['ordered_quantity'] as num).toDouble();
      final receivedQty = (line['total_received'] as num).toDouble();

      if (receivedQty > 0) {
        anyLineReceived = true;
      }

      if (receivedQty < orderedQty) {
        allLinesCompleted = false;
      }
    }

    int newStatus;
    if (allLinesCompleted && anyLineReceived) {
      newStatus = 3; // Tamamen kabul edildi
    } else if (anyLineReceived) {
      newStatus = 1; // Kısmi kabul
    } else {
      newStatus = 0; // Hiç kabul yapılmamış
    }

    await txn.update(
      DbTables.orders,
      {DbColumns.status: newStatus, DbColumns.updatedAt: DateTime.now().toIso8601String()},
      where: '${DbColumns.id} = ?',
      whereArgs: [siparisId],
    );
  }
}

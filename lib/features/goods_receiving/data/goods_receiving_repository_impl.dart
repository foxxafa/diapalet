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
import 'package:shared_preferences/shared_preferences.dart';

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

        // FIX: All received goods, regardless of type (order-based or free),
        // should have a 'receiving' status initially. They become 'available'
        // only after a put-away transfer.
        const stockStatus = 'receiving';

        for (final item in payload.items) {
          await txn.insert(DbTables.goodsReceiptItems, {
            'receipt_id': receiptId,
            DbColumns.orderLinesProductId: item.urunId,
            'quantity_received': item.quantity,
            DbColumns.stockPalletBarcode: item.palletBarcode,
            DbColumns.stockExpiryDate: item.expiryDate?.toIso8601String(),
          });
          // FIX: Pass the new receiptId to _updateStock so the stock record
          // is correctly linked to the goods_receipts entry. This is crucial
          // for finding items by delivery_note_number later.
          await _updateStock(
              txn,
              item.urunId,
              null, // locationId is null for receiving area
              item.quantity,
              item.palletBarcode,
              stockStatus,
              payload.header.siparisId,
              item.expiryDate?.toIso8601String(),
              receiptId); // <-- Pass receiptId here
        }

        if (payload.header.siparisId != null) {
          // Sipariş durumunu kontrol et ve gerekirse status 3 yap
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
    } catch (e, s) {
      debugPrint("Lokal mal kabul kaydı hatası: $e\n$s");
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

  // FIX: Added goodsReceiptId parameter to correctly link stock to its receipt.
  Future<void> _updateStock(Transaction txn, int urunId, int? locationId, double quantityChange, String? palletBarcode, String stockStatus, [int? siparisId, String? expiryDate, int? goodsReceiptId]) async {
    String locationWhereClause = locationId == null ? 'location_id IS NULL' : 'location_id = ?';
    String palletWhereClause = palletBarcode == null ? 'pallet_barcode IS NULL' : 'pallet_barcode = ?';
    String siparisWhereClause = siparisId == null ? 'siparis_id IS NULL' : 'siparis_id = ?';
    String expiryWhereClause = expiryDate == null ? 'expiry_date IS NULL' : 'expiry_date = ?';
    // FIX: Added where clause for goods_receipt_id
    String goodsReceiptWhereClause = goodsReceiptId == null ? 'goods_receipt_id IS NULL' : 'goods_receipt_id = ?';

    List<dynamic> whereArgs = [urunId, stockStatus];
    if (locationId != null) whereArgs.add(locationId);
    if (palletBarcode != null) whereArgs.add(palletBarcode);
    if (siparisId != null) whereArgs.add(siparisId);
    if (expiryDate != null) whereArgs.add(expiryDate);
    // FIX: Added argument for goods_receipt_id
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
        // FIX: Save the goods_receipt_id with the new stock record.
        'goods_receipt_id': goodsReceiptId
      });
    }
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await dbHelper.database;
    final prefs = await SharedPreferences.getInstance();
    final warehouseCode = prefs.getString('warehouse_code');

    debugPrint("DEBUG: Warehouse Code from SharedPreferences: $warehouseCode");

    // Warehouse bilgileri SharedPreferences'ta tutuluyor, tablo sorgusu gerek yok
    // Tüm açık siparişleri getir - warehouse filtreleme backend'de yapılıyor
    debugPrint("DEBUG: Getting all open orders (warehouse filtering done by backend)");

    // Basit sorgu - warehouse join kaldırıldı
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

    debugPrint("DEBUG: Found ${openOrdersMaps.length} open orders");
    
    // DEBUG: Basit sipariş sayımı
    final allOrdersCount = await db.rawQuery('SELECT COUNT(*) as count FROM ${DbTables.orders}');
    final allCount = Sqflite.firstIntValue(allOrdersCount) ?? 0;
    debugPrint("DEBUG: Toplam sipariş sayısı (tüm status): $allCount");
    
    final statusOrdersCount = await db.rawQuery('SELECT COUNT(*) as count FROM ${DbTables.orders} WHERE ${DbColumns.status} IN (0, 1)');
    final statusCount = Sqflite.firstIntValue(statusOrdersCount) ?? 0;
    debugPrint("DEBUG: Status 0,1 olan sipariş sayısı: $statusCount");

    final openOrders = openOrdersMaps.map((orderMap) => PurchaseOrder.fromMap(orderMap)).toList();

    for (var order in openOrders) {
      debugPrint("DEBUG: Open Order ID: ${order.id}, PO ID: ${order.poId}, Status: ${order.status}");
    }

    debugPrint("Mal kabul için açık siparişler: ${openOrders.length} adet bulundu");
    return openOrders;
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    debugPrint("DEBUG: Getting items for order ID: $orderId");
    
    // Debug: Önce sipariş ayrıntılı tablosunu kontrol et
    final orderLinesCheck = await db.query(
      DbTables.orderLines, 
      where: '${DbColumns.orderLinesOrderId} = ?', 
      whereArgs: [orderId]
    );
    debugPrint("DEBUG: Order lines count for order $orderId: ${orderLinesCheck.length}");
    if (orderLinesCheck.isNotEmpty) {
      for (var line in orderLinesCheck) {
        debugPrint("  - Line ID: ${line['id']}, kartkodu: '${line['kartkodu']}', turu: '${line['turu']}'");
      }
    }
    
    // Debug: Ürünler tablosunu kontrol et  
    final productsCheck = await db.query(DbTables.products, limit: 3);
    debugPrint("DEBUG: Sample products:");
    for (var product in productsCheck) {
      debugPrint("  - Product ID: ${product['UrunId']}, StokKodu: '${product['StokKodu']}'");
    }
    
    // Sipariş detayları için kompleks sorgu - iş mantığı burada
    final maps = await db.rawQuery('''
        SELECT
          s.*,
          u.${DbColumns.productsId} as urun_id,
          u.${DbColumns.productsName},
          u.${DbColumns.productsCode},
          u.${DbColumns.productsBarcode},
          u.${DbColumns.productsActive},
          COALESCE((SELECT SUM(gri.quantity_received)
                     FROM ${DbTables.goodsReceiptItems} gri
                     JOIN ${DbTables.goodsReceipts} gr ON gr.goods_receipt_id = gri.receipt_id
                     WHERE gr.siparis_id = s.${DbColumns.orderLinesOrderId} AND gri.${DbColumns.orderLinesProductId} = u.${DbColumns.productsId}), 0) as receivedQuantity,
          COALESCE(wps.putaway_quantity, 0) as transferredQuantity
        FROM ${DbTables.orderLines} s
        JOIN ${DbTables.products} u ON u.${DbColumns.productsCode} = s.${DbColumns.orderLinesProductCode}
        LEFT JOIN ${DbTables.putawayStatus} wps ON wps.purchase_order_line_id = s.${DbColumns.id}
        WHERE s.${DbColumns.orderLinesOrderId} = ? AND s.${DbColumns.orderLinesType} = '${DbColumns.orderLinesTypeValue}'
    ''', [orderId]);
    debugPrint("DEBUG: Found ${maps.length} items for order $orderId with JOIN");
    return maps.map((map) => PurchaseOrderItem.fromDb(map)).toList();
  }

  @override
  Future<List<PurchaseOrder>> getReceivablePurchaseOrders() async {
    final db = await dbHelper.database;
    // Basit sorgu - constants kullanıyoruz
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
      final poResult = await txn.query('siparisler',
          columns: ['fisno'], where: 'id = ?', limit: 1, whereArgs: [orderId]);
      final fisno = poResult.isNotEmpty ? poResult.first[DbColumns.ordersFisno] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'fisno': fisno, 'status': newStatus}),
          createdAt: DateTime.now());
      await txn.insert('pending_operation', pendingOp.toDbMap());

      await txn.update(
        'siparisler',
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
          'siparisler',
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
      await txn.insert('pending_operation', pendingOp.toDbMap());

      await txn.update(
        'siparisler',
        {'status': 2}, // Status 2: Manually Closed
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });

    debugPrint("Sipariş #$orderId lokal olarak manuel kapatıldı (status 2) ve senkronizasyon için sıraya alındı.");
  }

  @override
  Future<List<ProductInfo>> searchProducts(String query) async {
    final db = await dbHelper.database;
    // SADECE BARKOD alanlarıyla arama yap (Barcode1, Barcode2, Barcode3, Barcode4)
    final maps = await db.query(
      DbTables.products, 
      where: 'Barcode1 LIKE ? OR Barcode2 LIKE ? OR Barcode3 LIKE ? OR Barcode4 LIKE ?', 
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%']
    );
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductInfo>> getAllActiveProducts() async {
    final db = await dbHelper.database;
    // DÜZELTME: Pasif ürünlerle de işlem yapılabilmesi için aktiflik kontrolü kaldırıldı
    // Metot adı "Active" olmasına rağmen tüm ürünleri getiriyor (geriye uyumluluk için)
    final maps = await db.query(DbTables.products, orderBy: '${DbColumns.productsName} ASC');
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<ProductInfo?> findProductByExactMatch(String code) async {
    final db = await dbHelper.database;
    debugPrint("🔍 DEBUG: findProductByExactMatch aranan kod: '$code'");

    // Önce tüm urunler'i görelim
    final allProducts = await db.query(DbTables.products, limit: 10);
    debugPrint("📦 DEBUG: Veritabanında ilk 10 ürün:");
    for (var product in allProducts) {
      debugPrint("   UrunId: ${product['UrunId']}, StokKodu: '${product['StokKodu']}', Barcode1: '${product['Barcode1']}', aktif: ${product['aktif']}");
    }

    // DÜZELTME: Pasif ürünlerle de işlem yapılabilmesi için aktiflik kontrolü kaldırıldı
    final maps = await db.query(
      DbTables.products,
      where: '${DbColumns.productsCode} = ? OR ${DbColumns.productsBarcode} = ?',
      whereArgs: [code, code],
      limit: 1
    );

    debugPrint("🎯 DEBUG: Sorgu sonucu: ${maps.length} ürün bulundu");
    if (maps.isNotEmpty) {
      debugPrint("✅ DEBUG: Bulunan ürün: ${maps.first}");
    } else {
      debugPrint("❌ DEBUG: Hiç ürün bulunamadı - aranan kod: '$code'");

      // Benzer kodları arayalım
      final similarMaps = await db.query(
        DbTables.products,
        where: '${DbColumns.productsCode} LIKE ? OR Barcode1 LIKE ? OR Barcode2 LIKE ? OR Barcode3 LIKE ? OR Barcode4 LIKE ?',
        whereArgs: ['%$code%', '%$code%', '%$code%', '%$code%', '%$code%'],
        limit: 5
      );
      debugPrint("🔎 DEBUG: Benzer kodlar (LIKE arama): ${similarMaps.length} ürün");
      for (var product in similarMaps) {
        debugPrint("   StokKodu: '${product['StokKodu']}', Barcode1: '${product['Barcode1']}'");
      }
    }

    if (maps.isEmpty) return null;
    return ProductInfo.fromDbMap(maps.first);
  }

  @override
  Future<ProductInfo?> findProductByBarcodeExactMatch(String barcode) async {
    final db = await dbHelper.database;
    debugPrint("🔍 DEBUG: findProductByBarcodeExactMatch aranan barkod: '$barcode'");

    // TÜM BARKOD alanlarında tam eşleşme arama
    final maps = await db.query(
      DbTables.products,
      where: 'Barcode1 = ? OR Barcode2 = ? OR Barcode3 = ? OR Barcode4 = ?',
      whereArgs: [barcode, barcode, barcode, barcode],
      limit: 1
    );

    debugPrint("🎯 DEBUG: Barkod sorgu sonucu: ${maps.length} ürün bulundu");
    if (maps.isNotEmpty) {
      debugPrint("✅ DEBUG: Barkod ile bulunan ürün: ${maps.first}");
    } else {
      debugPrint("❌ DEBUG: Barkod ile ürün bulunamadı: '$barcode'");
    }

    if (maps.isEmpty) return null;
    return ProductInfo.fromDbMap(maps.first);
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query(DbTables.locations, where: '${DbColumns.isActive} = 1');
    return maps.map((map) => LocationInfo.fromMap(map)).toList();
  }

  /// Sipariş durumunu kontrol eder ve gerekirse status 3 (tamamen kabul edildi) yapar
  Future<void> _checkAndUpdateOrderStatus(Transaction txn, int siparisId) async {
    // Sipariş satırları ve alınan miktarları hesapla - iş mantığı
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

      // Tam eşitlik kontrolü - sipariş edilen = kabul edilen
      if (receivedQty < orderedQty) {
        allLinesCompleted = false;
      }
    }

    int newStatus;
    if (allLinesCompleted && anyLineReceived) {
      newStatus = 3; // Tamamen kabul edildi
      debugPrint("Sipariş #$siparisId tamamen kabul edildi - Status 3");
    } else if (anyLineReceived) {
      newStatus = 1; // Kısmi kabul
      debugPrint("Sipariş #$siparisId kısmi kabul edildi - Status 1");
    } else {
      newStatus = 0; // Hiç kabul yapılmamış
      debugPrint("Sipariş #$siparisId henüz kabul edilmedi - Status 0");
    }

    await txn.update(
      DbTables.orders,
      {DbColumns.status: newStatus, DbColumns.updatedAt: DateTime.now().toIso8601String()},
      where: '${DbColumns.id} = ?',
      whereArgs: [siparisId],
    );
  }
}

import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
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
          'created_at': DateTime.now().toIso8601String(),
        };
        final receiptId = await txn.insert('goods_receipts', receiptHeaderData);

        // FIX: All received goods, regardless of type (order-based or free),
        // should have a 'receiving' status initially. They become 'available'
        // only after a put-away transfer.
        const stockStatus = 'receiving';

        for (final item in payload.items) {
          await txn.insert('goods_receipt_items', {
            'receipt_id': receiptId,
            'urun_id': item.urunId,
            'quantity_received': item.quantity,
            'pallet_barcode': item.palletBarcode,
            'expiry_date': item.expiryDate?.toIso8601String(),
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
          await txn.update(
            'satin_alma_siparis_fis',
            {'status': 1}, // Mark order as partially/fully received
            where: 'id = ?',
            whereArgs: [payload.header.siparisId],
          );
        }

        final enrichedData = await _createEnrichedGoodsReceiptData(txn, payload);

        final pendingOp = PendingOperation.create(
          type: PendingOperationType.goodsReceipt,
          data: jsonEncode(enrichedData),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
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
        'satin_alma_siparis_fis',
        columns: ['po_id'],
        where: 'id = ?',
        whereArgs: [payload.header.siparisId],
        limit: 1,
      );
      if (poResult.isNotEmpty) {
        apiData['header']['po_id'] = poResult.first['po_id'];
      }
    }

    final enrichedItems = <Map<String, dynamic>>[];
    if (payload.items.isNotEmpty) {
      for (final item in payload.items) {
        final itemData = item.toJson();
        final productResult = await txn.query(
          'urunler',
          columns: ['UrunAdi', 'StokKodu'],
          where: 'id = ?',
          whereArgs: [item.urunId],
          limit: 1,
        );
        if (productResult.isNotEmpty) {
          itemData['product_name'] = productResult.first['UrunAdi'];
          itemData['product_code'] = productResult.first['StokKodu'];
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
    // FIX: The warehouse ID is stored under 'branch_id' in the satin_alma_siparis_fis table.
    // Let's use the correct key from SharedPreferences which should be 'branch_id' or find it via warehouse_id.
    // For now, assuming the logic to filter by warehouse is correct and the issue is elsewhere.
    final branchId = prefs.getInt('branch_id');


    final candidateOrdersMaps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status IN (0, 1) AND branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'tarih DESC',
    );

    final openOrders = <PurchaseOrder>[];
    for (var orderMap in candidateOrdersMaps) {
      final order = PurchaseOrder.fromMap(orderMap);
      final orderItems = await getPurchaseOrderItems(order.id);

      if (orderItems.isEmpty) continue;

      bool isFullyReceived = true;
      for (var item in orderItems) {
        if (item.receivedQuantity < item.expectedQuantity - 0.001) {
          isFullyReceived = false;
          break;
        }
      }

      if (!isFullyReceived) {
        openOrders.add(order);
      }
    }

    debugPrint("Mal kabul için açık siparişler (Branch ID: $branchId): ${openOrders.length} adet bulundu");
    return openOrders;
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
        SELECT
          s.*,
          u.UrunAdi,
          u.StokKodu,
          u.Barcode1,
          u.aktif,
          COALESCE((SELECT SUM(gri.quantity_received)
                     FROM goods_receipt_items gri
                     JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
                     WHERE gr.siparis_id = s.siparis_id AND gri.urun_id = s.urun_id), 0) as receivedQuantity,
          COALESCE(wps.putaway_quantity, 0) as transferredQuantity
        FROM satin_alma_siparis_fis_satir s
        JOIN urunler u ON u.id = s.urun_id
        LEFT JOIN wms_putaway_status wps ON wps.satinalmasiparisfissatir_id = s.id
        WHERE s.siparis_id = ?
    ''', [orderId]);
    return maps.map((map) => PurchaseOrderItem.fromDb(map)).toList();
  }

  @override
  Future<List<PurchaseOrder>> getReceivablePurchaseOrders() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status = ?',
      whereArgs: [1], // Partially received
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, int newStatus) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final poResult = await txn.query('satin_alma_siparis_fis',
          columns: ['po_id'], where: 'id = ?', limit: 1, whereArgs: [orderId]);
      final poId = poResult.isNotEmpty ? poResult.first['po_id'] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'po_id': poId, 'status': newStatus}),
          createdAt: DateTime.now());
      await txn.insert('pending_operation', pendingOp.toDbMap());

      await txn.update(
        'satin_alma_siparis_fis',
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
          'satin_alma_siparis_fis',
          columns: ['po_id'],
          where: 'id = ?',
          limit: 1,
          whereArgs: [orderId]
      );
      final poId = poResult.isNotEmpty ? poResult.first['po_id'] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'po_id': poId}),
          createdAt: DateTime.now()
      );
      await txn.insert('pending_operation', pendingOp.toDbMap());

      await txn.update(
        'satin_alma_siparis_fis',
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
    final maps = await db.query('urunler', where: 'aktif = 1 AND (UrunAdi LIKE ? OR StokKodu LIKE ? OR Barcode1 LIKE ?)', whereArgs: ['%$query%', '%$query%', '%$query%']);
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('shelfs', where: 'is_active = 1');
    return maps.map((map) => LocationInfo.fromMap(map)).toList();
  }
}

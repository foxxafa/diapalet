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
    await _saveGoodsReceiptLocally(payload);
  }

  Future<void> _saveGoodsReceiptLocally(GoodsReceiptPayload payload) async {
    // Kullanıcı işlemi başladığını sync service'e bildir
    syncService.startUserOperation();
    
    try {
      final db = await dbHelper.database;
      // Kullanıcının depo ID'sini al
      final prefs = await SharedPreferences.getInstance();
      final warehouseId = prefs.getInt('warehouse_id');
      if (warehouseId == null) {
        throw Exception("Depo bilgisi bulunamadı. Lütfen tekrar giriş yapın.");
      }
      // Dinamik olarak mal kabul lokasyon ID'sini al
      final malKabulLocationId = await dbHelper.getReceivingLocationId(warehouseId);
      if (malKabulLocationId == null) {
        throw Exception("Bu depo için Mal Kabul Alanı tanımlanmamış.");
      }
      await db.transaction((txn) async {
        final receiptHeaderData = {
          'siparis_id': payload.header.siparisId,
          'invoice_number': payload.header.invoiceNumber,
          'employee_id': payload.header.employeeId,
          'receipt_date': payload.header.receiptDate.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        };
        final receiptId = await txn.insert('goods_receipts', receiptHeaderData);

        for (final item in payload.items) {
          await txn.insert('goods_receipt_items', {
            'receipt_id': receiptId, 'urun_id': item.urunId,
            'quantity_received': item.quantity, 'pallet_barcode': item.palletBarcode,
          });
          await _updateStock(txn, item.urunId, malKabulLocationId, item.quantity, item.palletBarcode, 'receiving', payload.header.siparisId);
        }

        // Mal kabul yapıldığında siparişin durumunu 2 (İşlemde) yap.
        if (payload.header.siparisId != null) {
          await txn.update(
            'satin_alma_siparis_fis',
            {'status': 2},
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
    } finally {
      // Kullanıcı işlemi bittiğini sync service'e bildir
      syncService.endUserOperation();
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

  Future<void> _updateStock(Transaction txn, int urunId, int locationId, double quantityChange, String? palletBarcode, String stockStatus, [int? siparisId]) async {
    String palletWhereClause = palletBarcode == null ? 'pallet_barcode IS NULL' : 'pallet_barcode = ?';
    String siparisWhereClause = siparisId == null ? 'siparis_id IS NULL' : 'siparis_id = ?';
    List<dynamic> whereArgs = [urunId, locationId, stockStatus];
    if (palletBarcode != null) whereArgs.add(palletBarcode);
    if (siparisId != null) whereArgs.add(siparisId);
    
    final existingStock = await txn.query('inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND stock_status = ? AND $palletWhereClause AND $siparisWhereClause',
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
        'urun_id': urunId, 'location_id': locationId, 'quantity': quantityChange,
        'pallet_barcode': palletBarcode, 'updated_at': DateTime.now().toIso8601String(),
        'stock_status': stockStatus,
        'siparis_id': siparisId
      });
    }
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await dbHelper.database;
    // Kullanıcının depo ID'sini al
    final prefs = await SharedPreferences.getInstance();
    final warehouseId = prefs.getInt('warehouse_id');
    
    // Durumu 1 (Onaylandı) veya 2 (İşlemde) olan ve kullanıcının deposundaki siparişleri getir.
    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status IN (?, ?) AND lokasyon_id = ?',
      whereArgs: [1, 2, warehouseId],
      orderBy: 'tarih DESC',
    );
    debugPrint("Açık siparişler (Depo ID: $warehouseId): ${maps.length} adet bulundu");
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
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
                      JOIN goods_receipts gr ON gr.id = gri.receipt_id 
                      WHERE gr.siparis_id = s.siparis_id AND gri.urun_id = s.urun_id), 0) as receivedQuantity,
            COALESCE(wps.putaway_quantity, 0) as transferredQuantity
        FROM satin_alma_siparis_fis_satir s
        JOIN urunler u ON u.id = s.urun_id
        LEFT JOIN wms_putaway_status wps ON wps.satin_alma_siparis_fis_satir_id = s.id
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
      whereArgs: [2], // Durumu 2 (Mal Kabulde/Kısmi Kabul) olanlar
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, int status) async {
    final db = await dbHelper.database;
    await db.update(
      'satin_alma_siparis_fis',
      {'status': status},
      where: 'id = ?',
      whereArgs: [orderId],
    );
    // TODO: Bu durum değişikliğini sunucuya göndermek için bir pending_operation eklenebilir.
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

      // 1. Senkronizasyon için bekleyen işlem oluştur
      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'po_id': poId}),
          createdAt: DateTime.now()
      );
      await txn.insert('pending_operation', pendingOp.toDbMap());

      // 2. Siparişin LOKAL durumunu 3 (Manuel Kapatıldı) yap.
      await txn.update(
        'satin_alma_siparis_fis',
        {'status': 3}, 
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });

    debugPrint("Sipariş #$orderId lokal olarak manuel kapatıldı (status 3) ve senkronizasyon için sıraya alındı.");
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
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1');
    return maps.map((map) => LocationInfo.fromMap(map)).toList();
  }
}

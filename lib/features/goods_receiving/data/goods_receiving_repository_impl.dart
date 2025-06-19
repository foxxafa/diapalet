// lib/features/goods_receiving/data/goods_receiving_repository_impl.dart
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
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

  static const int malKabulLocationId = 1;

  GoodsReceivingRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  });

  // =================== ANA DEĞİŞİKLİK BURADA ===================
  // Bu fonksiyon artık yeni ve temiz veri modelimiz olan GoodsReceiptPayload'u kullanıyor.
  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    // Gelen payload'ı direkt olarak lokal kaydetme fonksiyonuna iletiyoruz.
    await _saveGoodsReceiptLocally(payload);
  }

  /// Gelen mal kabul verisini önce lokal veritabanına, sonra da
  /// senkronize edilmek üzere 'pending_operation' tablosuna kaydeder.
  Future<void> _saveGoodsReceiptLocally(GoodsReceiptPayload payload) async {
    final db = await dbHelper.database;
    try {
      await db.transaction((txn) async {
        // 1. Mal kabul başlık bilgisi (employee_id dahil) veritabanına ekleniyor.
        final receiptHeaderData = {
          'siparis_id': payload.header.siparisId,
          'invoice_number': payload.header.invoiceNumber,
          'employee_id': payload.header.employeeId, // <-- ARTIK DOĞRU DEĞER GELİYOR
          'receipt_date': payload.header.receiptDate.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        };
        final receiptId = await txn.insert('goods_receipts', receiptHeaderData);

        // 2. Mal kabul kalemleri (ürünler) veritabanına ekleniyor ve stok güncelleniyor.
        for (final item in payload.items) {
          await txn.insert('goods_receipt_items', {
            'receipt_id': receiptId, 'urun_id': item.urunId,
            'quantity_received': item.quantity, 'pallet_barcode': item.palletBarcode,
          });
          await _updateStock(txn, item.urunId, malKabulLocationId, item.quantity, item.palletBarcode);
        }

        // 3. Tüm bu işlem (başlık ve kalemler), sunucuya gönderilmek üzere
        // "bekleyen işlem" olarak sıraya alınıyor.
        final pendingOp = PendingOperation(
          type: PendingOperationType.goodsReceipt,
          data: jsonEncode(payload.toApiJson()), // payload'un tamamı JSON'a çevrilip saklanıyor
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
      });
      debugPrint("Mal kabul işlemi başarıyla lokale kaydedildi.");
    } catch (e, s) {
      debugPrint("Lokal mal kabul kaydı hatası: $e\n$s");
      throw Exception("Lokal veritabanına kaydederken bir hata oluştu: $e");
    }
  }
  // =============================================================

  Future<void> _updateStock(Transaction txn, int urunId, int locationId, double quantityChange, String? palletBarcode) async {
    final existingStock = await txn.query('inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND pallet_barcode ${palletBarcode == null ? 'IS NULL' : '= ?'}',
        whereArgs: palletBarcode == null ? [urunId, locationId] : [urunId, locationId, palletBarcode]
    );

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final newQty = (currentStock['quantity'] as num) + quantityChange;
      await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [currentStock['id']]);
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId, 'location_id': locationId, 'quantity': quantityChange,
        'pallet_barcode': palletBarcode, 'updated_at': DateTime.now().toIso8601String()
      });
    }
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status IN (?, ?)',
      whereArgs: [1, 2], // 1: Onaylandı, 2: Kısmi Kabul
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
        SELECT s.*, u.UrunAdi, u.StokKodu, u.Barcode1, u.aktif,
               COALESCE((SELECT SUM(gri.quantity_received) 
                         FROM goods_receipt_items gri 
                         JOIN goods_receipts gr ON gr.id = gri.receipt_id 
                         WHERE gr.siparis_id = s.siparis_id AND gri.urun_id = s.urun_id), 0) as receivedQuantity
        FROM satin_alma_siparis_fis_satir s
        JOIN urunler u ON u.id = s.urun_id
        WHERE s.siparis_id = ?
    ''', [orderId]);
    return maps.map((map) => PurchaseOrderItem.fromDb(map)).toList();
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
    final maps = await db.query('locations', where: 'is_active = 1');
    return maps.map((map) => LocationInfo.fromMap(map)).toList();
  }
}

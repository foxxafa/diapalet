// lib/features/goods_receiving/data/goods_receiving_repository_impl.dart

import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
// [DÜZELTME] Eksik import eklendi.
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:collection/collection.dart';

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

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    return _getOpenPurchaseOrdersFromLocal();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    return _getPurchaseOrderItemsFromLocal(orderId);
  }

  @override
  Future<List<ProductInfo>> searchProducts(String query) async {
    return _searchProductsFromLocal(query);
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('locations');
    return List.generate(maps.length, (i) => LocationInfo.fromMap(maps[i]));
  }

  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    await _saveGoodsReceiptLocally(payload);
  }

  Future<void> _saveGoodsReceiptLocally(GoodsReceiptPayload payload) async {
    final db = await dbHelper.database;
    try {
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
            'receipt_id': receiptId,
            'urun_id': item.urunId,
            'quantity_received': item.quantity,
            'pallet_barcode': item.palletBarcode,
          });

          String whereClause;
          List<dynamic> whereArgs;
          if (item.palletBarcode == null) {
            whereClause = 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL';
            whereArgs = [item.urunId, malKabulLocationId];
          } else {
            whereClause = 'urun_id = ? AND location_id = ? AND pallet_barcode = ?';
            whereArgs = [item.urunId, malKabulLocationId, item.palletBarcode];
          }

          final existingStock = await txn.query('inventory_stock', where: whereClause, whereArgs: whereArgs);
          if (existingStock.isNotEmpty) {
            final currentQuantity = (existingStock.first['quantity'] as num).toDouble();
            await txn.update(
              'inventory_stock',
              {'quantity': currentQuantity + item.quantity, 'updated_at': DateTime.now().toIso8601String()},
              where: 'id = ?',
              whereArgs: [existingStock.first['id']],
            );
          } else {
            await txn.insert('inventory_stock', {
              'urun_id': item.urunId,
              'location_id': malKabulLocationId,
              'quantity': item.quantity,
              'pallet_barcode': item.palletBarcode,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        }
        final pendingOp = PendingOperation(
          type: PendingOperationType.goodsReceipt,
          data: jsonEncode(payload.toApiJson()),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
      });
      debugPrint("Mal kabul işlemi başarıyla lokale kaydedildi ve senkronizasyon için sıraya alındı.");
    } catch (e) {
      debugPrint("Lokal mal kabul kaydı sırasında kritik hata: $e");
      throw Exception("Lokal veritabanına kaydederken bir hata oluştu: $e");
    }
  }

  Future<List<PurchaseOrder>> _getOpenPurchaseOrdersFromLocal() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('satin_alma_siparis_fis', where: 'status = ?', whereArgs: [0], orderBy: 'tarih DESC');
    return List.generate(maps.length, (i) => PurchaseOrder.fromMap(maps[i]));
  }

  Future<List<ProductInfo>> _searchProductsFromLocal(String query) async {
    final db = await dbHelper.database;
    List<Map<String, dynamic>> maps;
    if (query.isNotEmpty) {
      maps = await db.query('urunler', where: 'aktif = 1 AND (UrunAdi LIKE ? OR StokKodu LIKE ? OR Barcode1 LIKE ?)', whereArgs: ['%$query%', '%$query%', '%$query%'], limit: 50);
    } else {
      maps = await db.query('urunler', where: 'aktif = 1', limit: 50);
    }
    return List.generate(maps.length, (i) => ProductInfo.fromDbMap(maps[i]));
  }

  Future<List<PurchaseOrderItem>> _getPurchaseOrderItemsFromLocal(int orderId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.id, s.siparis_id, s.urun_id, s.miktar, s.birim, u.UrunAdi, u.StokKodu, u.Barcode1, u.aktif,
             COALESCE(gri.total_received, 0) as receivedQuantity
      FROM satin_alma_siparis_fis_satir AS s
      JOIN urunler AS u ON u.UrunId = s.urun_id
      LEFT JOIN (
        SELECT gr.siparis_id, gri.urun_id, SUM(gri.quantity_received) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.id = gri.receipt_id
        WHERE gr.siparis_id = ?
        GROUP BY gr.siparis_id, gri.urun_id
      ) AS gri ON gri.siparis_id = s.siparis_id AND gri.urun_id = s.urun_id
      WHERE s.siparis_id = ?
    ''', [orderId, orderId]);
    return List.generate(maps.length, (i) {
      final map = maps[i];
      return PurchaseOrderItem(
        id: map['id'] as int,
        orderId: map['siparis_id'] as int,
        productId: map['urun_id'] as int,
        expectedQuantity: (map['miktar'] as num? ?? 0).toDouble(),
        receivedQuantity: (map['receivedQuantity'] as num? ?? 0).toDouble(),
        unit: map['birim'] as String?,
        product: ProductInfo(
          id: map['urun_id'] as int,
          name: map['UrunAdi'] as String,
          stockCode: map['StokKodu'] as String,
          barcode1: map['Barcode1'] as String?,
          isActive: (map['aktif'] as int? ?? 1) == 1,
        ),
      );
    });
  }
}

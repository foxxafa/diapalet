// lib/features/goods_receiving/data/goods_receiving_repository_impl.dart

import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
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
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status = ?',
      whereArgs: [0],
      orderBy: 'tarih DESC',
    );
    return List.generate(maps.length, (i) => PurchaseOrder.fromMap(maps[i]));
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        satir.id,
        satir.siparis_id,
        satir.urun_id,
        satir.miktar,
        satir.birim,
        urun.UrunAdi,
        urun.StokKodu
      FROM satin_alma_siparis_fis_satir AS satir
      JOIN urunler AS urun ON urun.UrunId = satir.urun_id
      WHERE satir.siparis_id = ?
    ''', [orderId]);
    return List.generate(maps.length, (i) => PurchaseOrderItem.fromDbJoinMap(maps[i]));
  }

  @override
  Future<List<ProductInfo>> searchProducts(String query) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'urunler',
      where: 'UrunAdi LIKE ? OR StokKodu LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      limit: 50,
    );
    return List.generate(maps.length, (i) => ProductInfo.fromDbMap(maps[i]));
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('locations');
    return List.generate(maps.length, (i) => LocationInfo.fromMap(maps[i]));
  }

  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    final isConnected = await networkInfo.isConnected;

    if (isConnected) {
      try {
        debugPrint("Online mode: Sending goods receipt to API...");
        await dio.post(ApiConfig.goodsReceipts, data: payload.toApiJson());
        await _updateLocalStock(payload);
        debugPrint("API call successful. Local stock also updated.");
      } on DioException catch (e) {
        debugPrint("API call failed: ${e.message}. Saving to pending operations queue.");
        await _saveAsPendingOperation(payload);
      } catch (e) {
        debugPrint("An unexpected error occurred: $e. Saving to pending operations queue.");
        await _saveAsPendingOperation(payload);
      }
    } else {
      debugPrint("Offline mode: Saving to pending operations queue.");
      await _saveAsPendingOperation(payload);
    }
  }

  Future<void> _saveAsPendingOperation(GoodsReceiptPayload payload) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final operation = PendingOperation(
          id: 0,
          operationType: 'goods_receipt',
          operationData: payload.toApiJson(),
          createdAt: DateTime.now(),
          status: 'pending',
          tableName: 'goods_receipts'
      );
      await txn.insert(
        'pending_operation',
        operation.toMapForDb(),
      );
      await _updateLocalStock(payload, txn: txn);
    });
    debugPrint("Saved goods receipt as pending operation and updated local stock.");
  }

  Future<void> _updateLocalStock(GoodsReceiptPayload payload, {DatabaseExecutor? txn}) async {
    final db = txn ?? await dbHelper.database;
    for (final item in payload.items) {
      await _upsertStock(
        db,
        urunId: item.urunId,
        locationId: malKabulLocationId,
        qtyChange: item.quantity,
        palletBarcode: item.palletBarcode,
      );
    }
  }

  Future<void> _upsertStock(
      DatabaseExecutor txn, {
        required int urunId,
        required int locationId,
        required double qtyChange,
        String? palletBarcode,
      }) async {
    final palletWhereClause = palletBarcode != null ? "pallet_barcode = ?" : "pallet_barcode IS NULL";
    final whereArgs = palletBarcode != null ? [urunId, locationId, palletBarcode] : [urunId, locationId];

    final List<Map<String, dynamic>> existing = await txn.query(
      'inventory_stock',
      where: 'urun_id = ? AND location_id = ? AND $palletWhereClause',
      whereArgs: whereArgs,
    );

    if (existing.isNotEmpty) {
      final currentQty = (existing.first['quantity'] as num).toDouble();
      final newQty = currentQty + qtyChange;

      if (newQty > 0.001) {
        await txn.update(
          'inventory_stock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [existing.first['id']]);
      }
    } else if (qtyChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': qtyChange,
        'pallet_barcode': palletBarcode,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
}

// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:sqflite/sqflite.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;

  InventoryTransferRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  });

  @override
  Future<void> recordTransferOperation(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) async {
    final apiPayload = _buildApiPayload(header, items, sourceLocationId, targetLocationId);
    await _saveForSync(apiPayload, header, items, sourceLocationId, targetLocationId);
  }

  Future<void> _saveForSync(
      Map<String, dynamic> apiPayload,
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId) async {
    final db = await dbHelper.database;
    try {
      await db.transaction((txn) async {
        for (final item in items) {
          // HATA DÜZELTMESİ: `palletTransfer` yerine `pallet` enum değeri kullanıldı.
          final palletBarcode = header.operationType == AssignmentMode.pallet ? item.palletId : null;
          await _updateStock(txn, item.productId, sourceLocationId, -item.quantity, palletBarcode);
          await _updateStock(txn, item.productId, targetLocationId, item.quantity, palletBarcode);

          await txn.insert('inventory_transfers', {
            'urun_id': item.productId,
            'from_location_id': sourceLocationId,
            'to_location_id': targetLocationId,
            'quantity': item.quantity,
            'pallet_barcode': palletBarcode,
            'employee_id': header.employeeId,
            'transfer_date': header.transferDate.toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        final pendingOp = PendingOperation(
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode(apiPayload),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
      });
      debugPrint("Transfer işlemi başarıyla lokale kaydedildi.");
    } catch (e, s) {
      debugPrint("Lokal transfer kaydı hatası: $e\n$s");
      throw Exception("Lokal veritabanına transfer kaydedilirken hata oluştu: $e");
    }
  }

  Future<void> _updateStock(Transaction txn, int urunId, int locationId, double quantityChange, String? palletBarcode) async {
    final condition = palletBarcode == null
        ? 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL'
        : 'urun_id = ? AND location_id = ? AND pallet_barcode = ?';
    final args = palletBarcode == null ? [urunId, locationId] : [urunId, locationId, palletBarcode];

    final existingStock = await txn.query('inventory_stock', where: condition, whereArgs: args);

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final currentQty = (currentStock['quantity'] as num);
      final newQty = currentQty + quantityChange;

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
      });
    } else {
      debugPrint("UYARI: Kaynak lokasyonda ($locationId) bulunmayan bir stok (Ürün ID: $urunId, Palet: $palletBarcode) düşülmeye çalışıldı. İşlem atlandı.");
    }
  }

  Map<String, dynamic> _buildApiPayload(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) {
    return {
      "header": header.toApiJson(sourceLocationId, targetLocationId),
      "items": items.map((item) => item.toApiJson()).toList(),
    };
  }

  @override
  Future<Map<String, int>> getSourceLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('locations', where: 'is_active = 1');
    return {for (var map in maps) map['name'] as String: map['id'] as int};
  }

  @override
  Future<Map<String, int>> getTargetLocations() async => getSourceLocations();

  @override
  Future<List<String>> getPalletIdsAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery(
        'SELECT DISTINCT pallet_barcode FROM inventory_stock WHERE location_id = ? AND pallet_barcode IS NOT NULL', [locationId]);
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT u.id as productId, u.UrunAdi as productName, u.StokKodu as productCode, u.Barcode1 as barcode1, SUM(s.quantity) as quantity 
      FROM inventory_stock s 
      JOIN urunler u ON u.id = s.urun_id 
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL 
      GROUP BY u.id
    ''', [locationId]);
    return maps.map((map) => BoxItem.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT u.id, u.UrunAdi as name, u.StokKodu as code, s.quantity as currentQuantity 
      FROM inventory_stock s 
      JOIN urunler u ON u.id = s.urun_id 
      WHERE s.pallet_barcode = ?
    ''', [palletId]);
    return maps.map((map) => ProductItem.fromMap(map)).toList();
  }
}

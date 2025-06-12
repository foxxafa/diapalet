// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart

import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  InventoryTransferRepositoryImpl({required DatabaseHelper dbHelper}) : _dbHelper = dbHelper;

  @override
  Future<List<String>> getSourceLocations() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location',
      where: 'is_active = 1',
      orderBy: 'name',
    );
    return List.generate(maps.length, (i) => maps[i]['name'] as String);
  }

  @override
  Future<List<String>> getTargetLocations() async {
    return getSourceLocations();
  }

  @override
  Future<List<String>> getPalletIdsAtLocation(String locationName) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT T2.pallet_barcode
      FROM location T1
      JOIN inventory_stock T2 ON T1.id = T2.location_id
      WHERE T1.name = ? AND T2.pallet_barcode IS NOT NULL
    ''', [locationName]);
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) => maps[i]['pallet_barcode'] as String);
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(String locationName) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        p.id as productId,
        p.name as productName,
        p.code as productCode,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN product p ON p.id = s.urun_id
      JOIN location l ON l.id = s.location_id
      WHERE l.name = ? AND s.pallet_barcode IS NULL
      GROUP BY p.id, p.name, p.code
    ''', [locationName]);
    return List.generate(maps.length, (i) => BoxItem.fromMap(maps[i]));
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        p.id,
        p.name,
        p.code as productCode,
        s.quantity as currentQuantity
      FROM inventory_stock s
      JOIN product p ON p.id = s.urun_id
      WHERE s.pallet_barcode = ?
    ''', [palletId]);
    return List.generate(maps.length, (i) => ProductItem.fromMap(maps[i]));
  }

  @override
  Future<void> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await _dbHelper.database;
    final localId = _uuid.v4();

    final sourceLocationMap = (await db.query('location', where: 'name = ?', whereArgs: [header.sourceLocationName])).first;
    final targetLocationMap = (await db.query('location', where: 'name = ?', whereArgs: [header.targetLocationName])).first;
    final int sourceLocationId = sourceLocationMap['id'] as int;
    final int targetLocationId = targetLocationMap['id'] as int;

    await db.transaction((txn) async {
      final transferTimestamp = DateTime.now();
      
      for (final item in items) {
        await _upsertStock(txn, item.productId, sourceLocationId, -item.quantity, item.sourcePalletBarcode);
        await _upsertStock(txn, item.productId, targetLocationId, item.quantity, item.targetPalletBarcode);
      }

      final payload = {
        'header': header.toMap(),
        'items': items.map((item) => item.toMap()).toList(),
      };
      
      await txn.insert('pending_operation', {
        'type': 'transfer',
        'data': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      });
    });
  }

  Future<void> _upsertStock(DatabaseExecutor txn, int urunId, int locationId, double qtyChange, String? palletBarcode) async {
      final palletClause = palletBarcode != null ? "pallet_barcode = ?" : "pallet_barcode IS NULL";
      final whereArgs = palletBarcode != null ? [urunId, locationId, palletBarcode] : [urunId, locationId];

      final List<Map<String, dynamic>> existing = await txn.query(
          'inventory_stock',
          where: 'urun_id = ? AND location_id = ? AND $palletClause',
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
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
          });
      }
  }
}

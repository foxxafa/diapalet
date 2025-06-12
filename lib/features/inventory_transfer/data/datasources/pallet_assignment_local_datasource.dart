// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';

abstract class PalletAssignmentLocalDataSource {
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items, {bool createPendingOperation});
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<List<LocationInfo>> getDistinctLocations();
  Future<List<String>> getContainerIdsByLocation(int locationId, AssignmentMode mode);
  Future<List<ProductItem>> getContainerContent(String containerId, AssignmentMode mode);
  Future<List<BoxItem>> getBoxesAtLocation(int locationId);
  Future<void> markTransferOperationAsSynced(int operationId);
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;
  final SyncService syncService;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper, required this.syncService});
  
  @override
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items, {bool createPendingOperation = true}) async {
    final db = await dbHelper.database;
    late int opId;

    await db.transaction((txn) async {
      opId = await txn.insert('transfer_operation', header.toMapForDb());

      for (final item in items) {
        await txn.insert('transfer_item', {
          'operation_id': opId,
          'product_id': item.productId,
          'quantity': item.quantity,
        });

        if (header.operationType == AssignmentMode.pallet) {
          await txn.update(
            'inventory_stock',
            {'location_id': header.targetLocationId},
            where: 'pallet_barcode = ? AND location_id = ?',
            whereArgs: [header.containerId, header.sourceLocationId],
          );
        } else {
          await _updateInventory(txn, item.productId, header.sourceLocationId, -item.quantity);
          await _updateInventory(txn, item.productId, header.targetLocationId, item.quantity);
        }
      }

      if (createPendingOperation) {
        final pendingPayload = {
          "header": header.toMap(),
          "items": items.map((it) => it.toMap()).toList(),
        };
        await txn.insert('pending_operation', {
          'operation_type': header.operationType == AssignmentMode.pallet ? 'pallet_transfer' : 'box_transfer',
          'payload': jsonEncode(pendingPayload),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    });
    return opId;
  }

  Future<void> _updateInventory(DatabaseExecutor txn, int productId, int locationId, int quantityChange) async {
    // This logic handles stock changes for both pallet and box transfers within a transaction
    final existing = await txn.query('inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL',
        whereArgs: [productId, locationId],
        limit: 1);

    if (existing.isNotEmpty) {
      final currentQty = (existing.first['quantity'] as num? ?? 0);
      final newQty = currentQty + quantityChange;
      if (newQty > 0) {
        await txn.update('inventory_stock', {'quantity': newQty}, where: 'id = ?', whereArgs: [existing.first['id']]);
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [existing.first['id']]);
      }
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': productId,
        'location_id': locationId,
        'quantity': quantityChange,
      });
    }
  }

  @override
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations() async {
    final db = await dbHelper.database;
    final rows = await db.query('transfer_operation', where: 'synced = 0', orderBy: 'id DESC');
    return rows.map((e) => TransferOperationHeader.fromMap(e)).toList();
  }

  @override
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId) async {
    final db = await dbHelper.database;
    final rows = await db.query('transfer_item', where: 'operation_id = ?', whereArgs: [operationId]);
    return rows.map((e) => TransferItemDetail.fromMap(e)).toList();
  }

  @override
  Future<List<LocationInfo>> getDistinctLocations() async {
    final db = await dbHelper.database;
    // Query locations that actually have stock
    final rows = await db.rawQuery('''
      SELECT DISTINCT l.id, l.name, l.code
      FROM location l
      JOIN inventory_stock s ON s.location_id = l.id
      WHERE s.quantity > 0
      ORDER BY l.name
    ''');
    if (rows.isNotEmpty) {
      return rows.map((e) => LocationInfo.fromMap(e)).toList();
    }
    // Fallback to all locations if none have stock
    final allLocations = await db.query('location', orderBy: 'name');
    return allLocations.map((e) => LocationInfo.fromMap(e)).toList();
  }

  @override
  Future<List<String>> getContainerIdsByLocation(int locationId, AssignmentMode mode) async {
    final db = await dbHelper.database;
    if (mode == AssignmentMode.pallet) {
      // Fetch pallet barcodes for a given location
      final palletRows = await db.query('inventory_stock',
        columns: ['pallet_barcode'],
        distinct: true,
        where: 'location_id = ? AND pallet_barcode IS NOT NULL AND quantity > 0',
        whereArgs: [locationId]
      );
      return palletRows.map((e) => e['pallet_barcode'] as String).toList();
    } else { // Box mode
      // Box items are just stock records without a pallet barcode
      final boxRows = await db.query('inventory_stock',
        columns: ['urun_id'], // Using product ID as a representative "box" id
        where: 'location_id = ? AND pallet_barcode IS NULL AND quantity > 0',
        whereArgs: [locationId]
      );
      // We return product IDs as strings
      return boxRows.map((e) => (e['urun_id'] as int).toString()).toList();
    }
  }

  @override
  Future<List<ProductItem>> getContainerContent(String containerId, AssignmentMode mode) async {
    final db = await dbHelper.database;
    if (mode == AssignmentMode.pallet) {
      final palletItems = await db.rawQuery('''
        SELECT s.urun_id as product_id, p.name as product_name, p.code as product_code, s.quantity
        FROM inventory_stock s
        JOIN product p ON p.id = s.urun_id
        WHERE s.pallet_barcode = ?
      ''', [containerId]);
      return palletItems.map((e) => ProductItem.fromMap(e)).toList();
    } else { // Box mode assumes containerId is the product_id
      final productId = int.tryParse(containerId);
      if (productId != null) {
        final boxItems = await db.rawQuery('''
          SELECT s.urun_id as product_id, p.name as product_name, p.code as product_code, s.quantity
          FROM inventory_stock s
          JOIN product p ON p.id = s.urun_id
          WHERE s.urun_id = ? AND s.pallet_barcode IS NULL
        ''', [productId]);
        return boxItems.map((e) => ProductItem.fromMap(e)).toList();
      }
    }
    return [];
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        s.id as box_id,
        s.urun_id,
        p.name as product_name,
        p.code as product_code,
        s.quantity
      FROM inventory_stock s
      JOIN product p ON p.id = s.urun_id
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL AND s.quantity > 0
    ''', [locationId]);
    return rows.map((e) => BoxItem.fromMap(e)).toList();
  }

  @override
  Future<void> markTransferOperationAsSynced(int operationId) async {
    final db = await dbHelper.database;
    await db.update('transfer_operation', {'synced': 1}, where: 'id = ?', whereArgs: [operationId]);
  }
}

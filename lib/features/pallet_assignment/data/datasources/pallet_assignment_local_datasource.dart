// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';

abstract class PalletAssignmentLocalDataSource {
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<List<LocationInfo>> getDistinctLocations();
  Future<List<String>> getContainerIdsByLocation(int locationId);
  Future<List<ProductItem>> getContainerContent(String containerId);
  Future<List<BoxItem>> getBoxesAtLocation(int locationId);
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper});

  @override
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await dbHelper.database;
    late int opId;

    await db.transaction((txn) async {
      // 1. Save the operation header to get an ID
      opId = await txn.insert('transfer_operation', {
        'operation_type': header.operationType.name,
        'source_location_id': header.sourceLocationId,
        'target_location_id': header.targetLocationId,
        'pallet_id': header.containerId,
        'transfer_date': header.transferDate.toIso8601String(),
        'synced': 0, // Always start as unsynced
      });

      // 2. Save the items for this operation
      for (final item in items) {
        await txn.insert('transfer_item', {
          'operation_id': opId,
          'product_id': item.productId,
          'quantity': item.quantity,
        });

        // 3. Update local inventory based on transfer type
        if (header.operationType == AssignmentMode.pallet) {
          // For pallets, just update the pallet's location
          await txn.update('pallet', {'location_id': header.targetLocationId},
              where: 'id = ?', whereArgs: [header.containerId]);
        } else { // Box transfer
          // Decrement stock from source
          await _updateInventory(txn, item.productId, header.sourceLocationId, -item.quantity);
          // Increment stock at target
          await _updateInventory(txn, item.productId, header.targetLocationId, item.quantity);
        }
      }

      // 4. Create pending operation for sync service
      final pendingPayload = {
        'source_location_id': header.sourceLocationId,
        'target_location_id': header.targetLocationId,
        'pallet_id': header.containerId, // Container ID is the pallet ID
        'transfer_date': header.transferDate.toIso8601String(),
        'items': items.map((it) => {
          'product_id': it.productId,
          'quantity': it.quantity,
        }).toList(),
      };

      await txn.insert('pending_operation', {
        'operation_type': header.operationType == AssignmentMode.pallet ? 'pallet_transfer' : 'box_transfer',
        'payload': jsonEncode(pendingPayload),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    return opId;
  }
  
  Future<void> _updateInventory(DatabaseExecutor txn, int productId, int locationId, int quantityChange) async {
      final existing = await txn.query(
        'inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL',
        whereArgs: [productId, locationId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final currentQty = existing.first['quantity'] as int;
        final newQty = currentQty + quantityChange;
        if (newQty > 0) {
           await txn.update(
             'inventory_stock', 
             {'quantity': newQty}, 
             where: 'id = ?', 
             whereArgs: [existing.first['id']]);
        } else {
           await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [existing.first['id']]);
        }
      } else if (quantityChange > 0) {
        await txn.insert('inventory_stock', {
          'urun_id': productId,
          'location_id': locationId,
          'quantity': quantityChange,
          'pallet_barcode': null,
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
    final rows = await db.rawQuery('''
      SELECT ti.id, ti.operation_id, ti.product_id, ti.quantity,
             p.name AS product_name, p.code AS product_code
      FROM transfer_item ti
      JOIN product p ON p.id = ti.product_id
      WHERE ti.operation_id = ?
    ''', [operationId]);
    return rows.map((e) => TransferItemDetail.fromMap(e)).toList();
  }

  @override
  Future<List<LocationInfo>> getDistinctLocations() async {
    final db = await dbHelper.database;
    final rows = await db.query('location', orderBy: 'name');
    return rows.map((e) => LocationInfo.fromMap(e)).toList();
  }

  @override
  Future<List<String>> getContainerIdsByLocation(int locationId) async {
    final db = await dbHelper.database;
    final ids = <String>[];

    // Get Pallet IDs
    final palletRows = await db.query('pallet', where: 'location_id = ?', columns: ['id'], whereArgs: [locationId]);
    ids.addAll(palletRows.map((e) => e['id'] as String));

    // Get Box IDs (from inventory_stock, not goods_receipt_item anymore)
    final boxRows = await db.query(
      'inventory_stock',
      columns: ['id'],
      where: 'location_id = ? AND pallet_barcode IS NULL AND quantity > 0',
      whereArgs: [locationId]
    );
    // Box IDs are integers, convert them to string to have a unified list
    ids.addAll(boxRows.map((e) => (e['id'] as int).toString()));

    return ids;
  }

  @override
  Future<List<ProductItem>> getContainerContent(String containerId) async {
    final db = await dbHelper.database;

    // Try to see if it's a pallet ID (string)
    final palletItems = await db.rawQuery('''
      SELECT p.id AS product_id, p.name AS product_name, p.code AS product_code, pi.quantity
      FROM pallet_item pi
      JOIN product p ON p.id = pi.product_id
      WHERE pi.pallet_id = ?
    ''', [containerId]);
    
    if (palletItems.isNotEmpty) {
      return palletItems.map((e) => ProductItem.fromMap(e)).toList();
    }

    // If not a pallet, try to see if it's a box ID (integer) from inventory_stock
    final boxId = int.tryParse(containerId);
    if (boxId != null) {
      final boxItems = await db.rawQuery('''
        SELECT s.urun_id AS product_id, p.name as product_name, p.code as product_code, s.quantity
        FROM inventory_stock s
        JOIN product p ON p.id = s.urun_id
        WHERE s.id = ?
      ''', [boxId]);
      return boxItems.map((e) => ProductItem.fromMap(e)).toList();
    }

    return [];
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT s.id AS box_id, s.urun_id, p.name AS product_name, p.code AS product_code, s.quantity
      FROM inventory_stock s
      JOIN product p ON p.id = s.urun_id
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL
      ORDER BY s.id DESC
    ''', [locationId]);
    return rows.map((e) => BoxItem.fromMap(e)).toList();
  }
}

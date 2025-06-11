// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'package:flutter/foundation.dart';
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
  Future<void> saveTransferOperationToLocalDB(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<void> queueTransferOperationForSync(TransferOperationHeader header, List<TransferItemDetail> items);
  
  Future<List<LocationInfo>> getDistinctLocations();
  Future<List<String>> getContainerIdsByLocation(int locationId, AssignmentMode mode);
  Future<List<ProductItem>> getContainerContent(String containerId, AssignmentMode mode);
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;
  final SyncService syncService;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper, required this.syncService});
  
  @override
  Future<void> saveTransferOperationToLocalDB(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      int opId = await txn.insert('transfer_operation', header.toMap());

      for (final item in items) {
        await txn.insert('transfer_item', {
          ...item.toMap(),
          'operation_id': opId,
        });

        // Update local inventory based on the transfer
        await _updateInventoryInTransaction(txn, item.productId, header.sourceLocationId, -item.quantity, header.containerId);
        await _updateInventoryInTransaction(txn, item.productId, header.targetLocationId, item.quantity, header.containerId);
      }
    });
    debugPrint("Saved transfer operation to local DB (Online Mode).");
  }

  @override
  Future<void> queueTransferOperationForSync(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final payload = {
      "header": header.toMap(),
      "items": items.map((item) => item.toMap()).toList(),
    };
    final opType = header.operationType == AssignmentMode.pallet ? 'pallet_transfer' : 'box_transfer';
    await syncService.addPendingOperation(opType, payload);
    debugPrint("Queued transfer operation for sync (Offline Mode).");
  }

  Future<void> _updateInventoryInTransaction(DatabaseExecutor txn, int productId, int locationId, int quantityChange, String? palletBarcode) async {
    // This logic handles stock changes for both pallet and box transfers within a transaction
    final existing = await txn.query('inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND pallet_barcode ${palletBarcode == null ? 'IS NULL' : '= ?'}',
        whereArgs: palletBarcode == null ? [productId, locationId] : [productId, locationId, palletBarcode],
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
        'pallet_barcode': palletBarcode,
      });
    }
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
}

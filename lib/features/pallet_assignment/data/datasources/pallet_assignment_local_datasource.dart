// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/local/database_helper.dart'; // Assuming 'diapalet' is your project name
// Corrected entity imports
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
// AssignmentMode is imported via TransferOperationHeader, but explicit import is also fine if needed directly.
// import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';


abstract class PalletAssignmentLocalDataSource {
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<void> markTransferOperationAsSynced(int operationId);
  Future<void> updateContainerLocation(String containerId, String newLocation, DateTime updateTime);
  Future<String?> getContainerLocation(String containerId);
  Future<void> clearSyncedTransferOperations();
  Future<List<String>> getDistinctContainerLocations();
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper});

  @override
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await dbHelper.database;
    late int operationId; // Will hold the ID of the saved header

    await db.transaction((txn) async {
      // Save the header first to get its ID
      // The header passed in might have synced=0 or 1 depending on prior API attempt.
      // The toMap() method should correctly serialize it.
      operationId = await txn.insert(
        'transfer_operation', // Make sure this table name matches your DatabaseHelper
        header.toMap()..remove('id'), // DB generates 'id' for the header
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint("Saved transfer_operation with id: $operationId. Synced status: ${header.synced}");

      // Now save each item, linking it to the header's operationId
      for (var item in items) {
        // Create a new TransferItemDetail with the obtained operationId
        final itemToSave = TransferItemDetail(
          // id: item.id, // If items can be updated, otherwise DB generates new ID
          operationId: operationId, // Link to the saved header
          productCode: item.productCode,
          productName: item.productName,
          quantity: item.quantity,
        );
        await txn.insert(
          'transfer_item', // Make sure this table name matches your DatabaseHelper
          itemToSave.toMap()..remove('id'), // DB generates 'id' for the item
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        debugPrint("Saved transfer_item for operation_id: $operationId, product: ${item.productCode}");
      }
    });
    return operationId; // Return the ID of the saved header
  }

  @override
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transfer_operation',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id DESC',
    );
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) {
      return TransferOperationHeader.fromMap(maps[i]);
    });
  }

  @override
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transfer_item',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) {
      return TransferItemDetail.fromMap(maps[i]);
    });
  }

  @override
  Future<void> markTransferOperationAsSynced(int operationId) async {
    final db = await dbHelper.database;
    final count = await db.update(
      'transfer_operation',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [operationId],
    );
    debugPrint("Marked transfer_operation id $operationId as synced. Rows affected: $count");
  }

  @override
  Future<void> updateContainerLocation(String containerId, String newLocation, DateTime updateTime) async {
    final db = await dbHelper.database;
    await db.insert(
      'container_location', // Make sure this table name matches your DatabaseHelper
      {'container_id': containerId, 'location': newLocation, 'last_updated': updateTime.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint("Updated/Inserted location for container $containerId to $newLocation.");
  }

  @override
  Future<String?> getContainerLocation(String containerId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'container_location',
      columns: ['location'],
      where: 'container_id = ?',
      whereArgs: [containerId],
    );
    if (maps.isNotEmpty) {
      return maps.first['location'] as String?;
    }
    return null;
  }

  @override
  Future<void> clearSyncedTransferOperations() async {
    final db = await dbHelper.database;
    // Consider deleting associated items as well, or use ON DELETE CASCADE in DB schema
    final count = await db.delete(
      'transfer_operation',
      where: 'synced = ?',
      whereArgs: [1],
    );
    debugPrint("Cleared $count synced transfer operations.");
  }

  @override
  Future<List<String>> getDistinctContainerLocations() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT location FROM container_location ORDER BY location',
    );
    return rows.map((e) => e['location'] as String).toList();
  }
}

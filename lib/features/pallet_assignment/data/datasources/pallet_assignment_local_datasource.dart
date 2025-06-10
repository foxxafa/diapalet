// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'package:sqflite/sqflite.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';

abstract class PalletAssignmentLocalDataSource {
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<void> markTransferOperationAsSynced(int operationId);
  Future<void> clearSyncedTransferOperations();
  Future<List<String>> getDistinctLocations();
  Future<List<String>> getProductIdsByLocation(String location);
  Future<List<ProductItem>> getProductInfo(String productId, String location);
  Future<List<BoxItem>> getBoxesAtLocation(String location);
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper});

  Future<void> _ensureLocation(DatabaseExecutor txn, String location) async {
    await txn.insert('location', {'name': location},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await dbHelper.database;
    late int opId;
    await db.transaction((txn) async {
      await _ensureLocation(txn, header.sourceLocation);
      await _ensureLocation(txn, header.targetLocation);
      opId = await txn.insert('transfer_operation', {
        'operation_type': header.operationType.name,
        'source_location': header.sourceLocation,
        'target_location': header.targetLocation,
        'pallet_id': header.containerId,
        'transfer_date': header.transferDate.toIso8601String(),
        'synced': header.synced,
      });
      for (final item in items) {
        await txn.insert('transfer_item', {
          'operation_id': opId,
          'product_id': item.productId,
          'quantity': item.quantity,
        });
        if (header.operationType == AssignmentMode.box) {
          final sourceBoxId = int.tryParse(header.containerId);
          if (sourceBoxId == null) {
            throw Exception("Invalid source box ID: ${header.containerId}");
          }

          final sourceBox = await txn.query('goods_receipt_item', where: 'id = ?', whereArgs: [sourceBoxId]);

          if (sourceBox.isEmpty) {
            throw Exception("Source box not found with ID: $sourceBoxId");
          }

          final sourceQuantity = sourceBox.first['quantity'] as int;
          final newSourceQuantity = sourceQuantity - item.quantity;

          if (newSourceQuantity < 0) {
            throw Exception("Transfer quantity is greater than source quantity.");
          }

          if (newSourceQuantity == 0) {
            await txn.delete('goods_receipt_item', where: 'id = ?', whereArgs: [sourceBoxId]);
          } else {
            await txn.update('goods_receipt_item', {'quantity': newSourceQuantity}, where: 'id = ?', whereArgs: [sourceBoxId]);
          }

          final targetBoxes = await txn.query(
            'goods_receipt_item',
            where: 'location = ? AND product_id = ? AND pallet_id IS NULL',
            whereArgs: [header.targetLocation, item.productId],
          );

          if (targetBoxes.isNotEmpty) {
            final targetBox = targetBoxes.first;
            final targetBoxId = targetBox['id'] as int;
            final targetQuantity = targetBox['quantity'] as int;
            final newTargetQuantity = targetQuantity + item.quantity;
            await txn.update('goods_receipt_item', {'quantity': newTargetQuantity}, where: 'id = ?', whereArgs: [targetBoxId]);
          } else {
            final sourceReceiptId = sourceBox.first['receipt_id'];
            await txn.insert('goods_receipt_item', {
              'receipt_id': sourceReceiptId,
              'product_id': item.productId,
              'quantity': item.quantity,
              'location': header.targetLocation,
              'pallet_id': null,
            });
          }
        }
      }

      if (header.operationType == AssignmentMode.pallet) {
        await txn.update('pallet', {'location': header.targetLocation},
            where: 'id = ?', whereArgs: [header.containerId]);
      }
    });
    return opId;
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
  Future<void> markTransferOperationAsSynced(int operationId) async {
    final db = await dbHelper.database;
    await db.update('transfer_operation', {'synced': 1}, where: 'id = ?', whereArgs: [operationId]);
  }

  @override
  Future<void> clearSyncedTransferOperations() async {
    final db = await dbHelper.database;
    await db.delete('transfer_operation', where: 'synced = 1');
  }

  @override
  Future<List<String>> getDistinctLocations() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('SELECT name FROM location ORDER BY name');
    return rows.map((e) => e['name'] as String).toList();
  }

  @override
  Future<List<String>> getProductIdsByLocation(String location) async {
    final db = await dbHelper.database;
    final palletRows =
        await db.rawQuery('SELECT id FROM pallet WHERE location = ? ORDER BY id', [location]);
    final ids = <String>[];
    ids.addAll(palletRows.map((e) => e['id'].toString()));
    return ids;
  }

  @override
  Future<List<ProductItem>> getProductInfo(String productId, String location) async {
    final db = await dbHelper.database;

    final pallet = await db.query('pallet', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (pallet.isNotEmpty) {
      final rows = await db.rawQuery('''
        SELECT p.id AS product_id, p.name AS product_name, p.code AS product_code, pi.quantity
        FROM pallet_item pi
        JOIN product p ON p.id = pi.product_id
        WHERE pi.pallet_id = ?
      ''', [productId]);
      return rows
          .map((e) => ProductItem(
                id: e['product_id'].toString(),
                name: (e['product_name'] ?? '').toString(),
                productCode: (e['product_code'] ?? '').toString(),
                currentQuantity: (e['quantity'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    }

    final rows = await db.rawQuery('''
      SELECT p.id AS product_id, p.name AS product_name, p.code AS product_code, gri.quantity
      FROM goods_receipt_item gri
      JOIN product p ON p.id = gri.product_id
      WHERE gri.id = ? AND gri.location = ? 
    ''', [int.tryParse(productId), location]);

    return rows
        .map((e) => ProductItem(
              id: e['product_id'].toString(),
              name: (e['product_name'] ?? '').toString(),
              productCode: (e['product_code'] ?? '').toString(),
              currentQuantity: (e['quantity'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(String location) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT gri.id AS box_id, gri.product_id, p.name AS product_name, p.code AS product_code, gri.quantity
      FROM goods_receipt_item gri
      JOIN product p ON p.id = gri.product_id
      WHERE gri.location = ? AND gri.pallet_id IS NULL
      ORDER BY gri.id DESC
    ''', [location]);
    return rows
        .map((e) => BoxItem(
              boxId: (e['box_id'] as int),
              productId: e['product_id'].toString(),
              productName: (e['product_name'] ?? '').toString(),
              productCode: (e['product_code'] ?? '').toString(),
              quantity: (e['quantity'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }
}

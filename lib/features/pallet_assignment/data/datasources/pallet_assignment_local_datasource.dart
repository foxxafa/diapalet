// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'package:sqflite/sqflite.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';

abstract class PalletAssignmentLocalDataSource {
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<void> markTransferOperationAsSynced(int operationId);
  Future<void> clearSyncedTransferOperations();
  Future<List<String>> getDistinctLocations();
  Future<List<String>> getProductIdsByLocation(String location);
  Future<List<ProductItem>> getProductInfo(String productId, String location);
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper});

  Future<void> _updateStock(DatabaseExecutor txn, String productId, String location, int delta) async {
    final existing = await txn.query('stock_location', where: 'product_id = ? AND location = ?', whereArgs: [productId, location]);
    if (existing.isEmpty) {
      if (delta > 0) {
        await txn.insert('stock_location', {
          'product_id': productId,
          'location': location,
          'quantity': delta,
        });
      }
    } else {
      final id = existing.first['id'] as int;
      final qty = existing.first['quantity'] as int? ?? 0;
      final newQty = qty + delta;
      if (newQty <= 0) {
        await txn.delete('stock_location', where: 'id = ?', whereArgs: [id]);
      } else {
        await txn.update('stock_location', {'quantity': newQty}, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  @override
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await dbHelper.database;
    late int opId;
    await db.transaction((txn) async {
      opId = await txn.insert('transfer_operation', {
        'operation_type': header.operationType.name,
        'source_location': header.sourceLocation,
        'target_location': header.targetLocation,
        'transfer_date': header.transferDate.toIso8601String(),
        'synced': header.synced,
      });
      for (final item in items) {
        await txn.insert('transfer_item', {
          'operation_id': opId,
          'product_id': item.productId,
          'quantity': item.quantity,
        });
        await _updateStock(txn, item.productId, header.sourceLocation, -item.quantity);
        await _updateStock(txn, item.productId, header.targetLocation, item.quantity);
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
    final rows = await db.rawQuery('SELECT DISTINCT location FROM stock_location ORDER BY location');
    return rows.map((e) => e['location'] as String).toList();
  }

  @override
  Future<List<String>> getProductIdsByLocation(String location) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('SELECT DISTINCT product_id FROM stock_location WHERE location = ? ORDER BY product_id', [location]);
    return rows.map((e) => e['product_id'] as String).toList();
  }

  @override
  Future<List<ProductItem>> getProductInfo(String productId, String location) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS product_id, p.name AS product_name, p.code AS product_code, sl.quantity
      FROM stock_location sl
      JOIN product p ON p.id = sl.product_id
      WHERE sl.product_id = ? AND sl.location = ?
    ''', [productId, location]);
    return rows.map((e) => ProductItem(
          id: e['product_id'] as String,
          name: e['product_name'] as String,
          productCode: e['product_code'] as String,
          currentQuantity: e['quantity'] as int? ?? 0,
        )).toList();
  }
}

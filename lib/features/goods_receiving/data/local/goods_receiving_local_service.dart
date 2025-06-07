// lib/features/goods_receiving/data/local/goods_receiving_local_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/local/database_helper.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/entities/product_info.dart';

abstract class GoodsReceivingLocalDataSource {
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items);
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts();
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId);
  Future<void> markGoodsReceiptAsSynced(int receiptId);
  Future<ProductInfo?> getProductInfoById(String productId);
  Future<List<String>> getInvoiceNumbers();
  Future<List<ProductInfo>> getProductsForDropdown();
  Future<void> updateStock(String productId, String location, int qty);
}

class GoodsReceivingLocalDataSourceImpl implements GoodsReceivingLocalDataSource {
  final DatabaseHelper dbHelper;

  GoodsReceivingLocalDataSourceImpl({required this.dbHelper});

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    final db = await dbHelper.database;
    late int headerId;
    await db.transaction((txn) async {
      headerId = await txn.insert(
        'goods_receipt',
        header.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Assuming externalId is part of GoodsReceipt and its toMap() method
      debugPrint("Saved goods_receipt header with id: $headerId, external_id: ${header.externalId}");

      for (var item in items) {
        await txn.insert(
          'product',
          {
            'id': item.product.id,
            'name': item.product.name,
            'code': item.product.stockCode,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final itemMap = {
          'receipt_id': headerId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'location': item.location,
        };
        await txn.insert(
          'goods_receipt_item',
          itemMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await updateStock(item.product.id, item.location, item.quantity);
        debugPrint("Saved goods_receipt_item for receipt_id: $headerId, product: ${item.product.name}, location: ${item.location}");
      }
    });
    return headerId;
  }

  @override
  Future<void> updateStock(String productId, String location, int qty) async {
    final db = await dbHelper.database;
    final existing = await db.query('stock_location',
        where: 'product_id = ? AND location = ?',
        whereArgs: [productId, location],
        limit: 1);
    if (existing.isEmpty) {
      await db.insert('stock_location', {
        'product_id': productId,
        'location': location,
        'quantity': qty,
      });
    } else {
      final current = existing.first['quantity'] as int? ?? 0;
      await db.update('stock_location', {
        'quantity': current + qty,
      }, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  @override
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'goods_receipt',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'receipt_date DESC',
    );
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) => GoodsReceipt.fromMap(maps[i]));
  }

  @override
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT gri.id, gri.receipt_id, gri.product_id,
             p.name AS product_name, p.code AS product_code,
             gri.quantity, gri.location
      FROM goods_receipt_item gri
      JOIN product p ON p.id = gri.product_id
      WHERE gri.receipt_id = ?
    ''', [receiptId]);
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) => GoodsReceiptItem.fromMap(maps[i]));
  }

  @override
  Future<void> markGoodsReceiptAsSynced(int receiptId) async {
    final db = await dbHelper.database;
    final count = await db.update(
      'goods_receipt',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [receiptId],
    );
    debugPrint("Marked goods_receipt id $receiptId as synced. Rows affected: $count");
  }

  @override
  Future<ProductInfo?> getProductInfoById(String productId) async {
    debugPrint("LocalDataSource: getProductInfoById for $productId (not fully implemented for separate table).");
    return null;
  }

  @override
  Future<List<String>> getInvoiceNumbers() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT invoice_number FROM goods_receipt ORDER BY invoice_number DESC LIMIT 50',
    );
    return rows.map((e) => e['invoice_number'] as String).toList();
  }

  @override

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT id, name, code
      FROM product
      ORDER BY name LIMIT 100
    ''');
    return rows
        .map((e) => ProductInfo(
      id: e['id'] as String,
      name: e['name'] as String,
      stockCode: e['code'] as String,
    ))
        .toList();
  }

}

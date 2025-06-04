// lib/features/goods_receiving/data/local/goods_receiving_local_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/local/database_helper.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/entities/product_info.dart'; // ProductInfo için

abstract class GoodsReceivingLocalDataSource {
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items);
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts();
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId);
  Future<void> markGoodsReceiptAsSynced(int receiptId);
  Future<ProductInfo?> getProductInfoById(String productId);
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
      debugPrint("Saved goods_receipt header with id: $headerId");

      for (var item in items) {
        final itemMap = item.toMap()..remove('id');
        itemMap['receipt_id'] = headerId;
        await txn.insert(
          'goods_receipt_item',
          itemMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        debugPrint("Saved goods_receipt_item for receipt_id: $headerId, product: ${item.product.name}");
      }
    });
    return headerId;
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
    final List<Map<String, dynamic>> maps = await db.query(
      'goods_receipt_item',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    if (maps.isEmpty) return [];

    List<GoodsReceiptItem> items = [];
    for (var map in maps) {
      // GoodsReceiptItem.fromMap fabrika kurucu metodu artık ProductInfo oluşturmayı kendi içinde hallediyor.
      // Bu yüzden buradaki yerel 'product' değişkenine fromMap çağrısı için gerek kalmadı.
      // final product = ProductInfo(
      //   id: map['product_id'] as String,
      //   name: map['product_name'] as String,
      //   stockCode: map['product_code'] as String,
      // );
      items.add(GoodsReceiptItem.fromMap(map)); // Sadece map'i gönderin
    }
    return items;
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
}

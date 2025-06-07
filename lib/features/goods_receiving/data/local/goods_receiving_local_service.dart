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
}

class GoodsReceivingLocalDataSourceImpl implements GoodsReceivingLocalDataSource {
  final DatabaseHelper dbHelper;

  GoodsReceivingLocalDataSourceImpl({required this.dbHelper});

  Future<void> _ensureLocation(DatabaseExecutor txn, String location) async {
    await txn.insert('location', {'name': location},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Veritabanı transaction'ı veya direkt bağlantı üzerinde stok güncellemesi yapan genel bir metod.
  /// Hem `db.transaction` bloğu içinden `txn` nesnesi ile hem de direkt `db` nesnesi ile çağrılabilir.
  Future<void> _updateStock(DatabaseExecutor dbOrTxn, String productId, String location, int qty) async {
    await _ensureLocation(dbOrTxn, location);
    final existing = await dbOrTxn.query('stock_location',
        where: 'product_id = ? AND location = ?',
        whereArgs: [productId, location],
        limit: 1);

    if (existing.isEmpty) {
      await dbOrTxn.insert('stock_location', {
        'product_id': productId,
        'location': location,
        'quantity': qty,
      });
    } else {
      final currentQty = existing.first['quantity'] as int? ?? 0;
      await dbOrTxn.update(
        'stock_location',
        {'quantity': currentQty + qty},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    final db = await dbHelper.database;
    late int headerId;

    // Tüm veritabanı yazma işlemlerini tek bir transaction içinde toplayarak
    // veri bütünlüğünü sağlıyor ve kilitlenmeleri önlüyoruz.
    await db.transaction((txn) async {
      // 1. Mal kabul başlığını (header) veritabanına ekle ve ID'sini al.
      headerId = await txn.insert(
        'goods_receipt',
        header.toMap()..remove('id'), // id'yi kaldırarak otomatik artmasını sağlıyoruz.
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint("Saved goods_receipt header with id: $headerId, external_id: ${header.externalId}");

      // 2. Her bir ürün kalemi için işlemleri yap.
      for (var item in items) {
        await _ensureLocation(txn, item.location);
        // a. Ürün bilgisini 'product' tablosuna ekle (varsa görmezden gel).
        await txn.insert(
          'product',
          {
            'id': item.product.id,
            'name': item.product.name,
            'code': item.product.stockCode,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        // b. Mal kabul kalemini (item) veritabanına ekle.
        final itemMap = {
          'receipt_id': headerId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'location': item.location,
          'pallet_id': item.containerId,
        };
        await txn.insert(
          'goods_receipt_item',
          itemMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (item.containerId != null && item.containerId!.isNotEmpty) {
          // Palet kaydı
          await _ensureLocation(txn, item.location);
          await txn.insert(
            'pallet',
            {'id': item.containerId, 'location': item.location},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          final existing = await txn.query(
            'pallet_item',
            where: 'pallet_id = ? AND product_id = ?',
            whereArgs: [item.containerId, item.product.id],
          );
          if (existing.isEmpty) {
            await txn.insert('pallet_item', {
              'pallet_id': item.containerId,
              'product_id': item.product.id,
              'quantity': item.quantity,
            });
          } else {
            final qty = existing.first['quantity'] as int? ?? 0;
            await txn.update(
              'pallet_item',
              {'quantity': qty + item.quantity},
              where: 'pallet_id = ? AND product_id = ?',
              whereArgs: [item.containerId, item.product.id],
            );
          }
        } else {
          // Kutu akışı
          await _updateStock(txn, item.product.id, item.location, item.quantity);
        }

        debugPrint("Saved goods_receipt_item for receipt_id: $headerId, product: ${item.product.name}, location: ${item.location}");
      }
    });
    return headerId;
  }

  /// Stok güncellemek için kullanılan public metod.
  /// Kendi başına bir işlem olarak çalışır.
  Future<void> updateStock(String productId, String location, int qty) async {
    final db = await dbHelper.database;
    // _updateStock metodu DatabaseExecutor kabul ettiği için 'db' nesnesi ile direkt çalışabilir.
    await _updateStock(db, productId, location, qty);
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
             gri.quantity, gri.location, gri.pallet_id
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
    // Gerekirse burada 'product' tablosundan sorgu yapılabilir.
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
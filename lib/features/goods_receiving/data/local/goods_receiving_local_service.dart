// lib/features/goods_receiving/data/local/goods_receiving_local_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import '../../../../core/local/database_helper.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/entities/location_info.dart';
import '../../domain/entities/product_info.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_item.dart';
import 'dart:convert';

abstract class GoodsReceivingLocalDataSource {
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items, {bool createPendingOperation});
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts();
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId);
  Future<void> markGoodsReceiptAsSynced(int receiptId);
  Future<ProductInfo?> getProductInfoById(int productId);
  Future<List<String>> getInvoiceNumbers();
  Future<List<ProductInfo>> getProductsForDropdown();
  Future<List<LocationInfo>> getLocationsForDropdown();
  Future<List<PurchaseOrder>> getOpenPurchaseOrders();
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId);

  // Caching methods
  Future<void> cacheProducts(List<ProductInfo> products);
  Future<void> cacheLocations(List<LocationInfo> locations);
}

class GoodsReceivingLocalDataSourceImpl implements GoodsReceivingLocalDataSource {
  final DatabaseHelper dbHelper;
  final SyncService syncService;

  GoodsReceivingLocalDataSourceImpl({required this.dbHelper, required this.syncService});

  /// Veritabanı transaction'ı veya direkt bağlantı üzerinde stok güncellemesi yapan genel bir metod.
  Future<void> _updateStock(DatabaseExecutor dbOrTxn, int productId, int locationId, int qty, {String? palletId}) async {
    // Paletlenmemiş ürünler için stok güncellemesi
    if (palletId == null || palletId.isEmpty) {
      final existing = await dbOrTxn.query('inventory_stock',
          where: 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL',
          whereArgs: [productId, locationId],
          limit: 1);

      if (existing.isEmpty) {
        await dbOrTxn.insert('inventory_stock', {
          'urun_id': productId,
          'location_id': locationId,
          'quantity': qty,
        });
      } else {
        final currentQty = existing.first['quantity'] as int? ?? 0;
        await dbOrTxn.update(
          'inventory_stock',
          {'quantity': currentQty + qty},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      }
    }
    // Paletli ürünler için stok kaydı zaten palet_item tablosunda tutuluyor,
    // inventory_stock tablosunda ayrıca tutulmasına gerek yok. 
    // Sunucu tarafında bu ayrım yapılacak.
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items, {bool createPendingOperation = true}) async {
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
        /*
        // PALLET TABLE IS NOT USED ON SERVER and causes foreign key issues if locations are not synced.
        // Pallet info is stored in inventory_stock and goods_receipt_item via pallet_id/barcode.
        if (item.containerId != null && item.containerId!.isNotEmpty) {
          // Palet kaydı - önce palet tablosunda var olduğundan emin ol
          await txn.insert(
            'pallet',
            {'id': item.containerId, 'location_id': item.locationId},
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
        }
        */

        final itemMap = {
          'receipt_id': headerId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'location_id': item.locationId,
          'pallet_id': item.containerId,
        };
        await txn.insert(
          'goods_receipt_item',
          itemMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Stok güncellemesini yeni şemaya göre yap
        await _updateStock(txn, item.product.id, item.locationId, item.quantity, palletId: item.containerId);

        debugPrint("Saved goods_receipt_item for receipt_id: $headerId, product: ${item.product.name}, location_id: ${item.locationId}");
      }

      if (createPendingOperation) {
        // -------------------- PENDING QUEUE ---------------------------------
        final pendingPayload = {
          'header': header.toMap(),
          'items': items.map((i) => i.toMap()).toList(),
        };

        await txn.insert('pending_operation', {
          'operation_type': 'goods_receipt',
          'payload': jsonEncode(pendingPayload),
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint("Created pending_operation for goods receipt.");
      }
    });
    return headerId;
  }

  /// Stok güncellemek için kullanılan public metod.
  /// Kendi başına bir işlem olarak çalışır.
  Future<void> updateStock(String productId, String location, int qty) async {
    final db = await dbHelper.database;
    final pId = int.tryParse(productId);
    if (pId == null) {
      debugPrint('Error: Product ID is not a valid integer: $productId');
      return;
    }

    final locations = await db.query('location', where: 'name = ?', whereArgs: [location], limit: 1);
    if (locations.isEmpty) {
      debugPrint('Error: Location not found: $location');
      return;
    }
    
    final locationId = locations.first['id'] as int;

    // _updateStock metodu DatabaseExecutor kabul ettiği için 'db' nesnesi ile direkt çalışabilir.
    await _updateStock(db, pId, locationId, qty);
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
             gri.quantity, gri.location_id, l.name as location_name, gri.pallet_id
      FROM goods_receipt_item gri
      JOIN product p ON p.id = gri.product_id
      JOIN location l ON l.id = gri.location_id
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
  Future<ProductInfo?> getProductInfoById(int productId) async {
    final db = await dbHelper.database;
    final rows = await db.query('product', where: 'id = ?', whereArgs: [productId]);
    if (rows.isNotEmpty) {
      final e = rows.first;
      return ProductInfo(
        id: e['id'] as int,
        name: e['name'] as String,
        stockCode: e['code'] as String,
        isActive: true,
      );
    }
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
      id: e['id'] as int,
      name: e['name'] as String,
      stockCode: e['code'] as String,
      isActive: true,
    ))
        .toList();
  }

  @override
  Future<List<LocationInfo>> getLocationsForDropdown() async {
    final db = await dbHelper.database;
    final rows = await db.query('location', orderBy: 'name');
    return rows
        .map((e) => LocationInfo(
              id: e['id'] as int,
              name: e['name'] as String,
              code: e['code'] as String? ?? '',
            ))
        .toList();
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await dbHelper.database;
    final maps = await db.query('purchase_order', where: 'status = ?', whereArgs: [0], orderBy: 'tarih DESC');
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
    final maps = await db.query('purchase_order_item', where: 'siparis_id = ?', whereArgs: [orderId]);
    return maps.map((map) => PurchaseOrderItem.fromMap(map)).toList();
  }

  @override
  Future<void> cacheProducts(List<ProductInfo> products) async {
    final db = await dbHelper.database;
    final batch = db.batch();
    for (final product in products) {
      batch.insert(
        'product',
        {
          'id': product.id,
          'name': product.name,
          'code': product.stockCode,
          'is_active': product.isActive ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint("Cached ${products.length} products locally.");
  }

  @override
  Future<void> cacheLocations(List<LocationInfo> locations) async {
    final db = await dbHelper.database;
    final batch = db.batch();
    for (final location in locations) {
      batch.insert(
        'location',
        location.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint("Cached ${locations.length} locations locally.");
  }
}
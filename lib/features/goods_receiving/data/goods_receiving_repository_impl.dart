import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_log_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  // "MAL KABUL" lokasyonunun ID'sinin 1 olduğunu varsayıyoruz.
  // Gerçek bir uygulamada bu, yapılandırmadan veya veritabanından alınabilir.
  static const int malKabulLocationId = 1;

  GoodsReceivingRepositoryImpl({required DatabaseHelper dbHelper}) : _dbHelper = dbHelper;

  @override
  Future<List<LocationInfo>> getLocations({String? filter}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location', 
      where: filter != null && filter.isNotEmpty ? 'name LIKE ?' : null,
      whereArgs: filter != null && filter.isNotEmpty ? ['%$filter%'] : null,
      orderBy: 'name'
    );
    return List.generate(maps.length, (i) => LocationInfo.fromMap(maps[i]));
  }

  @override
  Future<List<ProductInfo>> getProducts({String? filter}) async {
    final db = await _dbHelper.database;
    String whereClause = 'is_active = 1';
    List<dynamic> whereArgs = [];
    if (filter != null && filter.isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR code LIKE ?)';
      whereArgs.addAll(['%$filter%', '%$filter%']);
    }

    final List<Map<String, dynamic>> maps = await db.query('product', where: whereClause, whereArgs: whereArgs, orderBy: 'name');
    return List.generate(maps.length, (i) {
      return ProductInfo.fromMap(maps[i]);
    });
  }

  @override
  Future<List<ProductInfo>> getAllProducts() {
    return getProducts();
  }

  @override
  Future<List<GoodsReceiptLogItem>> getRecentReceipts({int limit = 50}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        l.id, l.urun_id, l.location_id, l.quantity, l.container_id, l.created_at,
        p.name as urun_name,
        loc.name as location_name
      FROM goods_receipt_log l
      JOIN product p ON p.id = l.urun_id
      JOIN location loc ON loc.id = l.location_id
      ORDER BY l.created_at DESC
      LIMIT ?
    ''', [limit]);
    return List.generate(maps.length, (i) {
      return GoodsReceiptLogItem.fromMap(maps[i]);
    });
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_order',
      where: 'status = 0',
      orderBy: 'tarih DESC',
    );
    return List.generate(maps.length, (i) => PurchaseOrder.fromMap(maps[i]));
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        poi.id,
        poi.urun_id as productId,
        p.name as productName,
        poi.miktar as orderedQuantity,
        poi.birim as unit
      FROM purchase_order_item poi
      JOIN product p ON p.id = poi.urun_id
      WHERE poi.siparis_id = ?
    ''', [orderId]);
    return List.generate(maps.length, (i) => PurchaseOrderItem.fromMap(maps[i]));
  }

  @override
  Future<void> recordGoodsReceipt({
    required int? purchaseOrderId,
    String? invoiceNumber,
    required List<GoodsReceiptLogItem> receivedItems,
  }) async {
    final db = await _dbHelper.database;
    final localId = _uuid.v4();

    await db.transaction((txn) async {
      // 1. Create goods_receipts header for local log
      final receiptId = await txn.insert('goods_receipts', {
        'local_id': localId,
        'siparis_id': purchaseOrderId,
        'invoice_number': invoiceNumber,
        'employee_id': 1, // Replace with actual logged-in user ID
        'receipt_date': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Insert items and update stock for each item
      for (final item in receivedItems) {
        await txn.insert('goods_receipt_items', {
          'receipt_id': receiptId,
          'urun_id': item.urunId,
          'quantity_received': item.quantity,
          'pallet_barcode': item.containerId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Add received items to stock at the "MAL KABUL" location
        await _upsertStock(txn, item.urunId, malKabulLocationId, item.quantity, item.containerId);
      }

      // 3. Queue for upload
      final payload = {
        'header': {
          'siparis_id': purchaseOrderId,
          'invoice_number': invoiceNumber,
          'employee_id': 1, // FAKE ID
          'receipt_date': DateTime.now().toIso8601String(),
        },
        'items': receivedItems.map((item) => {
          'urun_id': item.urunId,
          'quantity': item.quantity,
          'pallet_barcode': item.containerId,
        }).toList(),
      };
      
      await txn.insert('pending_operation', {
        'type': 'goods_receipt', // Using string as per previous logic. Enum is better.
        'data': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      });
    });
  }

  @override
  Future<void> saveGoodsReceipt({
    required int productId,
    required int locationId,
    required double quantity,
    String? palletBarcode,
  }) async {
    final db = await _dbHelper.database;
    final timestamp = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert('goods_receipt_log', {
        'urun_id': productId,
        'location_id': locationId,
        'quantity': quantity,
        'container_id': palletBarcode,
        'created_at': timestamp,
      });

      await _upsertStock(txn, productId, locationId, quantity, palletBarcode);

      final payload = {
        'product_id': productId,
        'location_id': locationId,
        'quantity': quantity,
        'pallet_barcode': palletBarcode,
        'receipt_date': timestamp,
      };

      await txn.insert('pending_operation', {
        'type': 'goods_receipt',
        'data': jsonEncode(payload),
        'created_at': timestamp,
        'status': 'pending',
      });
    });
  }

  Future<void> _upsertStock(DatabaseExecutor txn, int urunId, int locationId, double qtyChange, String? palletBarcode) async {
    final palletClause = palletBarcode != null ? "pallet_barcode = ?" : "pallet_barcode IS NULL";
    final whereArgs = palletBarcode != null ? [urunId, locationId, palletBarcode] : [urunId, locationId];

    final List<Map<String, dynamic>> existing = await txn.query(
      'inventory_stock',
      where: 'urun_id = ? AND location_id = ? AND $palletClause',
      whereArgs: whereArgs,
    );

    if (existing.isNotEmpty) {
      final currentQty = (existing.first['quantity'] as num).toDouble();
      final newQty = currentQty + qtyChange;
      
      await txn.update(
        'inventory_stock',
        {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': qtyChange,
        'pallet_barcode': palletBarcode,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
} 
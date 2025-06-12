import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/recent_receipt_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final DatabaseHelper dbHelper;
  final Uuid _uuid = const Uuid();

  // "MAL KABUL" lokasyonunun ID'sinin 1 olduğunu varsayıyoruz.
  // Gerçek bir uygulamada bu, yapılandırmadan veya veritabanından alınabilir.
  static const int malKabulLocationId = 1;

  GoodsReceivingRepositoryImpl({required this.dbHelper});

  @override
  Future<List<LocationInfo>> getLocations({String? filter}) async {
    final db = await dbHelper.database;
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
    final db = await dbHelper.database;
    String whereClause = 'is_active = 1';
    List<dynamic> whereArgs = [];
    if (filter != null && filter.isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR code LIKE ?)';
      whereArgs.addAll(['%$filter%', '%$filter%']);
    }

    final List<Map<String, dynamic>> maps = await db.query('product', where: whereClause, whereArgs: whereArgs, orderBy: 'name');
    return List.generate(maps.length, (i) => ProductInfo.fromMap(maps[i]));
  }

  @override
  Future<List<ProductInfo>> getAllProducts() {
    return getProducts();
  }

  @override
  Future<List<RecentReceiptItem>> getRecentReceipts({int limit = 50}) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        gri.id, 
        gri.quantity_received, 
        gri.pallet_barcode, 
        gr.created_at,
        p.name as productName
      FROM goods_receipt_item gri
      JOIN goods_receipt gr ON gr.local_id = gri.receipt_local_id
      JOIN product p ON p.id = gri.urun_id
      ORDER BY gr.created_at DESC
      LIMIT ?
    ''', [limit]);
    return List.generate(maps.length, (i) => RecentReceiptItem.fromMap(maps[i]));
  }

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('purchase_orders');
    return List.generate(maps.length, (i) {
      return PurchaseOrder.fromJson(maps[i]);
    });
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    // Bu metot getPurchaseOrders ile aynı işi yapabilir veya status'e göre filtreleyebilir.
    // Şimdilik getPurchaseOrders'ı çağıralım.
    return getPurchaseOrders();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;
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
  Future<void> saveGoodsReceipt(GoodsReceipt receipt) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final receiptId = await txn.insert('goods_receipts', receipt.toJson());
      for (var item in receipt.items) {
        await txn.insert('goods_receipt_items', item.copyWith(goodsReceiptId: receiptId.toInt()).toJson());
      }
    });
  }

  @override
  Future<List<ProductInfo>> searchProducts(String query) async {
    // Implement product search logic
    return [];
  }

  @override
  Future<ProductInfo?> getProductDetails(String barcode) async {
    // Implement get product details logic
    return null;
  }

  @override
  Future<LocationInfo?> getLocationDetails(String barcode) async {
    // Implement get location details logic
    return null;
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
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
} 
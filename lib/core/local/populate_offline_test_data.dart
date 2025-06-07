import 'package:diapalet/core/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';

Future<void> populateTestData() async {
  final dbHelper = DatabaseHelper();
  final db = await dbHelper.database;

  // Tek seferlik ekleme kontrolü
  const sentinelId = 'OFFLINE-INIT';
  final check = await db.query(
    'goods_receipt',
    where: 'external_id = ?',
    whereArgs: [sentinelId],
  );
  if (check.isNotEmpty) {
    // Daha önce test verisi eklenmiş
    return;
  }

  DateTime now = DateTime.now();

  Future<void> addProduct(String id, String name, String code) async {
    await db.insert('product', {
      'id': id,
      'name': name,
      'code': code,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> addReceipt(String extId, String invoice) async {
    return await db.insert('goods_receipt', {
      'external_id': extId,
      'invoice_number': invoice,
      'receipt_date': now.toIso8601String(),
      'synced': 0,
    });
  }

  Future<void> updateStock(String productId, String location, int qty) async {
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
      await db.update(
        'stock_location',
        {'quantity': current + qty},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // Products
  await addProduct('PROD-A', 'Coca Cola 1L', 'A100');
  await addProduct('PROD-B', 'Pepsi 330ml', 'B200');
  await addProduct('PROD-C', 'Fanta 1L', 'C300');
  await addProduct('PROD-D', 'Sprite 1.5L', 'D400');
  await addProduct('PROD-E', 'Coca Cola 1L', 'E500');
  await addProduct('PROD-F', 'Pepsi 330ml', 'F600');

  // Receipt 1 - MAL KABUL
  final r1 = await addReceipt(sentinelId, 'INV-001');
  await db.insert('goods_receipt_item', {
    'receipt_id': r1,
    'product_id': 'PROD-A',
    'quantity': 10,
    'location': 'MAL KABUL'
  });
  await updateStock('PROD-A', 'MAL KABUL', 10);
  await db.insert('goods_receipt_item', {
    'receipt_id': r1,
    'product_id': 'PROD-B',
    'quantity': 15,
    'location': 'MAL KABUL'
  });
  await updateStock('PROD-B', 'MAL KABUL', 15);

  // Receipt 2 - Location 10A21
  final r2 = await addReceipt('OFFLINE-R2', 'INV-002');
  await db.insert('goods_receipt_item', {
    'receipt_id': r2,
    'product_id': 'PROD-B',
    'quantity': 20,
    'location': '10A21'
  });
  await updateStock('PROD-B', '10A21', 20);
  await db.insert('goods_receipt_item', {
    'receipt_id': r2,
    'product_id': 'PROD-C',
    'quantity': 30,
    'location': '10A21'
  });
  await updateStock('PROD-C', '10A21', 30);

  // Receipt 3 - Location 5C2
  final r3 = await addReceipt('OFFLINE-R3', 'INV-003');
  await db.insert('goods_receipt_item', {
    'receipt_id': r3,
    'product_id': 'PROD-D',
    'quantity': 12,
    'location': '5C2'
  });
  await updateStock('PROD-D', '5C2', 12);
  await db.insert('goods_receipt_item', {
    'receipt_id': r3,
    'product_id': 'PROD-A',
    'quantity': 25,
    'location': '5C2'
  });
  await updateStock('PROD-A', '5C2', 25);

  // Receipt 4 - MAL KABUL
  final b1 = await addReceipt('OFFLINE-R4', 'INV-004');
  await db.insert('goods_receipt_item', {
    'receipt_id': b1,
    'product_id': 'PROD-E',
    'quantity': 5,
    'location': 'MAL KABUL'
  });
  await updateStock('PROD-E', 'MAL KABUL', 5);

  // Receipt 5 - 5B3
  final b2 = await addReceipt('OFFLINE-R5', 'INV-005');
  await db.insert('goods_receipt_item', {
    'receipt_id': b2,
    'product_id': 'PROD-F',
    'quantity': 8,
    'location': '5B3'
  });
  await updateStock('PROD-F', '5B3', 8);

  // Receipt 6 - KASA
  final b3 = await addReceipt('OFFLINE-R6', 'INV-006');
  await db.insert('goods_receipt_item', {
    'receipt_id': b3,
    'product_id': 'PROD-C',
    'quantity': 50,
    'location': 'KASA'
  });
  await updateStock('PROD-C', 'KASA', 50);
}

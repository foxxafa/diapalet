// core/local/populate_offline_test_data.dart
import 'package:diapalet/core/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';

Future<void> populateTestData() async {
  final db = await DatabaseHelper().database;

  // tekrar çalışmasın
  if ((await db.query('goods_receipt', limit: 1)).isNotEmpty) return;

  // ---------- helpers ----------
  Future<void> addProduct(String id, String name, String code) async =>
      db.insert('product', {'id': id, 'name': name, 'code': code},
          conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> addLocation(String loc) async =>
      db.insert('location', {'name': loc},
          conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<int> addReceipt(String ext, String inv) async =>
      db.insert('goods_receipt', {
        'external_id': ext,
        'invoice_number': inv,
        'receipt_date': DateTime.now().toIso8601String()
      });

  Future<void> incStock(String prod, String loc, int qty) async {
    final row = await db.query('stock_location',
        where: 'product_id=? AND location=?', whereArgs: [prod, loc], limit: 1);
    if (row.isEmpty) {
      await db.insert('stock_location',
          {'product_id': prod, 'location': loc, 'quantity': qty});
    } else {
      final id  = row.first['id'];
      final cur = row.first['quantity'] as int? ?? 0;
      await db
          .update('stock_location', {'quantity': cur + qty}, where: 'id=?', whereArgs: [id]);
    }
  }

  // ---------- master data ----------
  for (final p in [
    ['PROD-A', 'Coca Cola 1L', 'A100'],
    ['PROD-B', 'Pepsi 330ml', 'B200'],
    ['PROD-C', 'Fanta 1L', 'C300'],
    ['PROD-D', 'Sprite 1.5L', 'D400'],
    ['PROD-E', 'Coca Cola 1L', 'E500'],
    ['PROD-F', 'Pepsi 330ml', 'F600'],
  ]) {
    await addProduct(p[0], p[1], p[2]);
  }

  for (final l in ['MAL KABUL', 'KASA', '10A21', '5C2', '5B3']) {
    await addLocation(l);
  }

  // ---------- pallet example ----------
  await db.insert('pallet', {'id': 'PALET-001', 'location': 'MAL KABUL'});
  await db.insert('pallet_item',
      {'pallet_id': 'PALET-001', 'product_id': 'PROD-A', 'quantity': 100});
  await incStock('PROD-A', 'MAL KABUL', 100);

  // ---------- box (stock) examples ----------
  final r1 = await addReceipt('OFFLINE-INIT', 'INV-001');
  await db.insert('goods_receipt_item',
      {'receipt_id': r1, 'product_id': 'PROD-B', 'quantity': 50, 'location': 'MAL KABUL'});
  await incStock('PROD-B', 'MAL KABUL', 50);

  final r2 = await addReceipt('OFFLINE-R2', 'INV-002');
  await db.insert('goods_receipt_item',
      {'receipt_id': r2, 'product_id': 'PROD-C', 'quantity': 30, 'location': '10A21'});
  await incStock('PROD-C', '10A21', 30);
}

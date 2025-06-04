import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import 'package:diapalet/core/local/database_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper dbHelper;

  setUp(() async {
    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'app_main_database.db');
    if (File(path).existsSync()) {
      await File(path).delete();
    }
    dbHelper = DatabaseHelper();
    await dbHelper.database; // Ensure DB is initialized
  });

  tearDown(() async {
    await dbHelper.close();
  });

  test('deleting goods_receipt cascades to goods_receipt_item', () async {
    final db = await dbHelper.database;

    final receiptId = await db.insert('goods_receipt', {
      'invoice_number': 'INV1',
      'receipt_date': DateTime.now().toIso8601String(),
      'mode': 'palet',
      'synced': 0,
    });

    await db.insert('goods_receipt_item', {
      'receipt_id': receiptId,
      'pallet_or_box_id': 'P1',
      'product_id': 'PR1',
      'product_name': 'Prod 1',
      'product_code': 'P1',
      'quantity': 1,
    });

    final before = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM goods_receipt_item WHERE receipt_id=?',
        [receiptId]));
    expect(before, 1);

    await db.delete('goods_receipt', where: 'id=?', whereArgs: [receiptId]);

    final after = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM goods_receipt_item WHERE receipt_id=?',
        [receiptId]));
    expect(after, 0);
  });
}

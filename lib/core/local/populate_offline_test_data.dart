import 'package:diapalet/core/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';

Future<void> populateTestData() async {
  final dbHelper = DatabaseHelper();
  final db = await dbHelper.database;

  // UNIQUE constraint'i korumak için eklemeden önce bak!
  const externalId = 'GR-001';
  final check = await db.query(
    'goods_receipt',
    where: 'external_id = ?',
    whereArgs: [externalId],
  );
  if (check.isNotEmpty) {
    // Test datası zaten eklenmiş.
    return;
  }

  // Goods receipt
  final receiptId = await db.insert('goods_receipt', {
    'external_id': externalId,
    'invoice_number': 'INV-TEST',
    'receipt_date': DateTime.now().toIso8601String(),
    'mode': 'palet',
    'synced': 0,
  });

  await db.insert('goods_receipt_item', {
    'receipt_id': receiptId,
    'pallet_or_box_id': 'PALET-123',
    'product_id': 'PROD-1',
    'product_name': 'Test Ürün A',
    'product_code': 'A100',
    'quantity': 5,
  });

  await db.insert('goods_receipt_item', {
    'receipt_id': receiptId,
    'pallet_or_box_id': 'PALET-123',
    'product_id': 'PROD-2',
    'product_name': 'Test Ürün B',
    'product_code': 'B200',
    'quantity': 10,
  });

  // Palet transferi
  final transferId = await db.insert('transfer_operation', {
    'operation_type': 'transfer',
    'source_location': 'Giris',
    'container_id': 'PALET-123',
    'target_location': 'Raf-10',
    'transfer_date': DateTime.now().toIso8601String(),
    'synced': 0,
  });

  await db.insert('transfer_item', {
    'operation_id': transferId,
    'product_code': 'A100',
    'product_name': 'Test Ürün A',
    'quantity': 2,
  });

  await db.insert('transfer_item', {
    'operation_id': transferId,
    'product_code': 'B200',
    'product_name': 'Test Ürün B',
    'quantity': 5,
  });

  // Container location
  await db.insert('container_location', {
    'container_id': 'PALET-123',
    'location': 'Raf-10',
    'last_updated': DateTime.now().toIso8601String(),
  });
}

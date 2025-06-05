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

  // Additional pallet located at MAL KABUL
  final palletReceiptId = await db.insert('goods_receipt', {
    'external_id': 'GR-002',
    'invoice_number': 'INV-PAL',
    'receipt_date': DateTime.now().toIso8601String(),
    'mode': 'palet',
    'synced': 0,
  });

  await db.insert('goods_receipt_item', {
    'receipt_id': palletReceiptId,
    'pallet_or_box_id': 'PALET-MK1',
    'product_id': 'PROD-3',
    'product_name': 'Test Ürün C',
    'product_code': 'C300',
    'quantity': 7,
  });

  await db.insert('container_location', {
    'container_id': 'PALET-MK1',
    'location': 'MAL KABUL',
    'last_updated': DateTime.now().toIso8601String(),
  });

  // Box located at MAL KABUL
  final boxReceiptId = await db.insert('goods_receipt', {
    'external_id': 'GR-003',
    'invoice_number': 'INV-BOX',
    'receipt_date': DateTime.now().toIso8601String(),
    'mode': 'kutu',
    'synced': 0,
  });

  await db.insert('goods_receipt_item', {
    'receipt_id': boxReceiptId,
    'pallet_or_box_id': 'KUTU-MK1',
    'product_id': 'PROD-4',
    'product_name': 'Test Ürün D',
    'product_code': 'D400',
    'quantity': 3,
  });

  await db.insert('container_location', {
    'container_id': 'KUTU-MK1',
    'location': 'MAL KABUL',
    'last_updated': DateTime.now().toIso8601String(),
  });
}

import 'package:diapalet/core/local/database_helper.dart';

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

  Future<int> addReceipt(String extId, String invoice, String mode) async {
    return await db.insert('goods_receipt', {
      'external_id': extId,
      'invoice_number': invoice,
      'receipt_date': now.toIso8601String(),
      'mode': mode,
      'synced': 0,
    });
  }

  // Pallet 1 - MAL KABUL
  final r1 = await addReceipt(sentinelId, 'INV-PAL1', 'palet');
  await db.insert('goods_receipt_item', {
    'receipt_id': r1,
    'pallet_or_box_id': 'PALET-001',
    'product_id': 'PROD-A',
    'product_name': 'Coca Cola 1L',
    'product_code': 'A100',
    'quantity': 10,
  });
  await db.insert('goods_receipt_item', {
    'receipt_id': r1,
    'pallet_or_box_id': 'PALET-001',
    'product_id': 'PROD-B',
    'product_name': 'Pepsi 330ml',
    'product_code': 'B200',
    'quantity': 15,
  });
  await db.insert('container_location', {
    'container_id': 'PALET-001',
    'location': 'MAL KABUL',
    'last_updated': now.toIso8601String(),
  });

  // Pallet 2 - MAL KABUL
  final r2 = await addReceipt('OFFLINE-PAL2', 'INV-PAL2', 'palet');
  await db.insert('goods_receipt_item', {
    'receipt_id': r2,
    'pallet_or_box_id': 'PALET-002',
    'product_id': 'PROD-B',
    'product_name': 'Pepsi 330ml',
    'product_code': 'B200',
    'quantity': 20,
  });
  await db.insert('goods_receipt_item', {
    'receipt_id': r2,
    'pallet_or_box_id': 'PALET-002',
    'product_id': 'PROD-C',
    'product_name': 'Fanta 1L',
    'product_code': 'C300',
    'quantity': 30,
  });
  await db.insert('container_location', {
    'container_id': 'PALET-002',
    'location': '10A21',
    'last_updated': now.toIso8601String(),
  });

  // Pallet 3 - MAL KABUL
  final r3 = await addReceipt('OFFLINE-PAL3', 'INV-PAL3', 'palet');
  await db.insert('goods_receipt_item', {
    'receipt_id': r3,
    'pallet_or_box_id': 'PALET-003',
    'product_id': 'PROD-D',
    'product_name': 'Sprite 1.5L',
    'product_code': 'D400',
    'quantity': 12,
  });
  await db.insert('goods_receipt_item', {
    'receipt_id': r3,
    'pallet_or_box_id': 'PALET-003',
    'product_id': 'PROD-A',
    'product_name': 'Coca Cola 1L',
    'product_code': 'A100',
    'quantity': 25,
  });
  await db.insert('container_location', {
    'container_id': 'PALET-003',
    'location': '5C2',
    'last_updated': now.toIso8601String(),
  });

  // Box 1 - MAL KABUL (single product)
  final b1 = await addReceipt('OFFLINE-BOX1', 'INV-BOX1', 'kutu');
  await db.insert('goods_receipt_item', {
    'receipt_id': b1,
    'pallet_or_box_id': 'BOX-001',
    'product_id': 'PROD-E',
    'product_name': 'Coca Cola 1L',
    'product_code': 'E500',
    'quantity': 5,
  });
  await db.insert('container_location', {
    'container_id': 'BOX-001',
    'location': 'MAL KABUL',
    'last_updated': now.toIso8601String(),
  });

  // Box 2 - MAL KABUL
  final b2 = await addReceipt('OFFLINE-BOX2', 'INV-BOX2', 'kutu');
  await db.insert('goods_receipt_item', {
    'receipt_id': b2,
    'pallet_or_box_id': 'BOX-002',
    'product_id': 'PROD-F',
    'product_name': 'Pepsi 330ml',
    'product_code': 'F600',
    'quantity': 8,
  });
  await db.insert('container_location', {
    'container_id': 'BOX-002',
    'location': '5B3',
    'last_updated': now.toIso8601String(),
  });

  // Box 3 - MAL KABUL
  final b3 = await addReceipt('OFFLINE-BOX3', 'INV-BOX3', 'kutu');
  await db.insert('goods_receipt_item', {
    'receipt_id': b3,
    'pallet_or_box_id': 'BOX-003',
    'product_id': 'PROD-C',
    'product_name': 'Fanta 1L',
    'product_code': 'C300',
    'quantity': 50,
  });
  await db.insert('container_location', {
    'container_id': 'BOX-003',
    'location': 'KASA',
    'last_updated': now.toIso8601String(),
  });
}

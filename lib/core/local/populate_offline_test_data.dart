import 'package:diapalet/core/local/database_helper.dart';

Future<void> populateTestData() async {
  final dbHelper = DatabaseHelper();
  final db = await dbHelper.database;

  const seedCheck = 'SEED-V2';
  final existing = await db.query('goods_receipt', where: 'external_id = ?', whereArgs: [seedCheck]);
  if (existing.isNotEmpty) {
    return;
  }

  Future<int> _insertReceipt(String externalId, String invoice, String mode) {
    return db.insert('goods_receipt', {
      'external_id': externalId,
      'invoice_number': invoice,
      'receipt_date': DateTime.now().toIso8601String(),
      'mode': mode,
      'synced': 0,
    });
  }

  Future<void> _insertItem(int receiptId, String container, String prodId,
      String prodName, String prodCode, int qty) async {
    await db.insert('goods_receipt_item', {
      'receipt_id': receiptId,
      'pallet_or_box_id': container,
      'product_id': prodId,
      'product_name': prodName,
      'product_code': prodCode,
      'quantity': qty,
    });
  }

  Future<void> _setLocation(String container, String location) async {
    await db.insert('container_location', {
      'container_id': container,
      'location': location,
      'last_updated': DateTime.now().toIso8601String(),
    });
  }

  // Pallet in MAL KABUL with two products
  final r1 = await _insertReceipt(seedCheck, 'INV-P1', 'palet');
  await _insertItem(r1, 'PALLET-MK1', 'PRD-1', 'Çay 1kg', 'CAY1', 20);
  await _insertItem(r1, 'PALLET-MK1', 'PRD-2', 'Şeker 1kg', 'SEKER1', 30);
  await _setLocation('PALLET-MK1', 'MAL KABUL');

  // Pallet in 10A21 with multiple products
  final r2 = await _insertReceipt('SEED-V2-P2', 'INV-P2', 'palet');
  await _insertItem(r2, 'PALLET-10A21', 'PRD-3', 'Un 2kg', 'UN2', 15);
  await _insertItem(r2, 'PALLET-10A21', 'PRD-4', 'Makarna 500g', 'MAK500', 25);
  await _setLocation('PALLET-10A21', '10A21');

  // Pallet in 5C3
  final r3 = await _insertReceipt('SEED-V2-P3', 'INV-P3', 'palet');
  await _insertItem(r3, 'PALLET-5C3', 'PRD-1', 'Çay 1kg', 'CAY1', 10);
  await _insertItem(r3, 'PALLET-5C3', 'PRD-5', 'Zeytin 1kg', 'ZEYTIN1', 40);
  await _setLocation('PALLET-5C3', '5C3');

  // Box in MAL KABUL with single product
  final r4 = await _insertReceipt('SEED-V2-B1', 'INV-B1', 'kutu');
  await _insertItem(r4, 'BOX-MK1', 'PRD-2', 'Şeker 1kg', 'SEKER1', 40);
  await _setLocation('BOX-MK1', 'MAL KABUL');

  // Box in KASA with single product
  final r5 = await _insertReceipt('SEED-V2-B2', 'INV-B2', 'kutu');
  await _insertItem(r5, 'BOX-KASA1', 'PRD-3', 'Un 2kg', 'UN2', 5);
  await _setLocation('BOX-KASA1', 'KASA');

  // Box in 10A21 with single product
  final r6 = await _insertReceipt('SEED-V2-B3', 'INV-B3', 'kutu');
  await _insertItem(r6, 'BOX-10A21', 'PRD-4', 'Makarna 500g', 'MAK500', 8);
  await _setLocation('BOX-10A21', '10A21');
}

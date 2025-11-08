// Test kodu - main.dart'a veya bir debug sayfasına ekleyin
// Bu kod telefondaki inventory_stock kayıtlarının receipt_operation_uuid değerlerini kontrol eder

import 'package:diapalet/core/local/database_helper.dart';

Future<void> testReceiptOperationUuid() async {
  final dbHelper = DatabaseHelper.instance;
  final db = await dbHelper.database;

  // 1. deneme000a12 paletinin durumu
  print('═══════════════════════════════════════════════════════');
  print('🔍 TEST: deneme000a12 paletinin receipt_operation_uuid değeri');
  print('═══════════════════════════════════════════════════════');

  final palletRecords = await db.rawQuery('''
    SELECT
      id,
      stock_uuid,
      receipt_operation_uuid,
      pallet_barcode,
      quantity,
      stock_status
    FROM inventory_stock
    WHERE pallet_barcode = ?
  ''', ['deneme000a12']);

  if (palletRecords.isEmpty) {
    print('❌ deneme000a12 paleti inventory_stock tablosunda bulunamadı!');
  } else {
    for (var record in palletRecords) {
      print('📦 Palet Kaydı:');
      print('   - id: ${record['id']}');
      print('   - stock_uuid: ${record['stock_uuid']}');
      print('   - receipt_operation_uuid: ${record['receipt_operation_uuid']}');
      print('   - quantity: ${record['quantity']}');
      print('   - stock_status: ${record['stock_status']}');

      if (record['receipt_operation_uuid'] == null) {
        print('   ⚠️  WARNING: receipt_operation_uuid NULL!');
      }
    }
  }

  // 2. Receiving durumundaki tüm kayıtların UUID durumu
  print('');
  print('═══════════════════════════════════════════════════════');
  print('📊 GENEL İSTATİSTİK: Receiving durumundaki stoklar');
  print('═══════════════════════════════════════════════════════');

  final stats = await db.rawQuery('''
    SELECT
      COUNT(*) as total,
      SUM(CASE WHEN receipt_operation_uuid IS NULL THEN 1 ELSE 0 END) as null_count,
      SUM(CASE WHEN receipt_operation_uuid IS NOT NULL THEN 1 ELSE 0 END) as has_uuid_count
    FROM inventory_stock
    WHERE stock_status = 'receiving'
  ''');

  if (stats.isNotEmpty) {
    final stat = stats.first;
    print('📊 Total receiving stocks: ${stat['total']}');
    print('   - NULL receipt_operation_uuid: ${stat['null_count']}');
    print('   - Has receipt_operation_uuid: ${stat['has_uuid_count']}');

    if ((stat['null_count'] as int) > 0) {
      print('   ⚠️  ${stat['null_count']} kayıtta receipt_operation_uuid NULL!');
      print('   💡 Çözüm: Full sync yapın veya backend fix ile çalışacak');
    }
  }

  // 3. Eğer UUID varsa, goods_receipts ile ilişkisini kontrol et
  if (palletRecords.isNotEmpty && palletRecords.first['receipt_operation_uuid'] != null) {
    print('');
    print('═══════════════════════════════════════════════════════');
    print('🔗 GOODS RECEIPTS İLİŞKİSİ');
    print('═══════════════════════════════════════════════════════');

    final receiptUuid = palletRecords.first['receipt_operation_uuid'];
    final goodsReceipt = await db.rawQuery('''
      SELECT
        goods_receipt_id,
        operation_unique_id,
        delivery_note_number,
        siparis_id
      FROM goods_receipts
      WHERE operation_unique_id = ?
    ''', [receiptUuid]);

    if (goodsReceipt.isEmpty) {
      print('❌ goods_receipts tablosunda UUID bulunamadı: $receiptUuid');
    } else {
      final receipt = goodsReceipt.first;
      print('✅ Goods Receipt bulundu:');
      print('   - goods_receipt_id: ${receipt['goods_receipt_id']}');
      print('   - operation_unique_id: ${receipt['operation_unique_id']}');
      print('   - delivery_note_number: ${receipt['delivery_note_number']}');
      print('   - siparis_id: ${receipt['siparis_id']}');
    }
  }

  print('═══════════════════════════════════════════════════════');
}

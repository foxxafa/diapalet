
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/inventory_inquiry/domain/entities/product_location.dart';
import 'package:diapalet/features/inventory_inquiry/domain/repositories/inventory_inquiry_repository.dart';

class InventoryInquiryRepositoryImpl implements InventoryInquiryRepository {
  final DatabaseHelper dbHelper;

  InventoryInquiryRepositoryImpl({required this.dbHelper});

  @override
  Future<List<ProductLocation>> findProductLocationsByBarcode(String barcode) async {
    final db = await dbHelper.database;
    
    // 1. Barkoda, ürün adına veya stok koduna göre ürünü bul
    final productQuery = await db.query(
      'urunler',
      where: 'Barcode1 = ? OR UrunAdi LIKE ? OR StokKodu LIKE ?',
      whereArgs: [barcode, '%$barcode%', '%$barcode%'],
      limit: 1,
    );

    if (productQuery.isEmpty) {
      return [];
    }
    final productId = productQuery.first['id'] as int;

    // 2. Ürün ID'sine göre stok lokasyonlarını bul
    const sql = '''
      SELECT 
        s.urun_id,
        u.UrunAdi,
        u.StokKodu,
        s.quantity,
        s.pallet_barcode,
        s.expiry_date,
        s.location_id,
        sh.name as location_name,
        sh.code as location_code
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      LEFT JOIN shelfs sh ON sh.id = s.location_id
      WHERE s.urun_id = ? AND s.stock_status = 'available'
      ORDER BY s.expiry_date ASC, s.updated_at ASC
    ''';

    final results = await db.rawQuery(sql, [productId]);
    
    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }
} 
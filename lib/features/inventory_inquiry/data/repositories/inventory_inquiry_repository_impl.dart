
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/utils/gs1_parser.dart';
import 'package:diapalet/features/inventory_inquiry/domain/entities/product_location.dart';
import 'package:diapalet/features/inventory_inquiry/domain/repositories/inventory_inquiry_repository.dart';

class InventoryInquiryRepositoryImpl implements InventoryInquiryRepository {
  final DatabaseHelper dbHelper;

  InventoryInquiryRepositoryImpl({required this.dbHelper});

  @override
  Future<List<ProductLocation>> findProductLocationsByBarcode(String barcode) async {
    final db = await dbHelper.database;
    final parsedData = GS1Parser.parse(barcode);

    // Aranacak potansiyel kodları bir listeye topla
    final searchTerms = <String>{}; // Benzersizliği korumak için Set kullan

    // 1. Sadece GS1 GTIN (01) kodunu ara
    if (parsedData.containsKey('01')) {
      final gtin = parsedData['01']!;
      searchTerms.add(gtin);
      // Eğer GTIN-14 ise ve '0' ile başlıyorsa, baştaki '0'ı atıp GTIN-13 olarak da ekle
      if (gtin.length == 14 && gtin.startsWith('0')) {
        searchTerms.add(gtin.substring(1));
      }
    } else {
      // Ayrıştırılmış bir GTIN yoksa, manuel girilen barkodu kullan
      searchTerms.add(barcode.trim());
    }

    if (searchTerms.isEmpty) return [];

    // Sorgu için parametre listesi ve yer tutucuları oluştur
    final placeholders = ('?' * searchTerms.length).split('').join(',');
    final whereArgs = searchTerms.toList();

    // 1. Barkod, ürün adı veya stok koduna göre ürünü bul
    final productQuery = await db.query(
      'urunler',
      where: 'Barcode1 IN ($placeholders) OR UrunAdi IN ($placeholders) OR StokKodu IN ($placeholders)',
      whereArgs: [...whereArgs, ...whereArgs, ...whereArgs],
      limit: 1,
    );

    if (productQuery.isEmpty) {
      return [];
    }
    final productId = productQuery.first['UrunId'] as int;

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
      JOIN urunler u ON u.UrunId = s.urun_id
      LEFT JOIN shelfs sh ON sh.id = s.location_id
      WHERE s.urun_id = ? AND s.stock_status = 'available'
      ORDER BY s.expiry_date ASC, s.updated_at ASC
    ''';

    final results = await db.rawQuery(sql, [productId]);

    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }
}
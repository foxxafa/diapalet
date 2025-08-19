
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
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

    // 1. Yeni barkod sistemi: Önce barkod araması yap
    final productByBarcode = await dbHelper.getProductByBarcode(searchTerms.first);
    if (productByBarcode != null) {
      final productId = productByBarcode['UrunId'] as int;
      
      // 2. Bu ürünün stok durumunu getir
      final stockQuery = await db.query(
        DbTables.inventoryStock,
        where: '${DbColumns.stockProductId} = ?',
        whereArgs: [productId],
      );
      
      return stockQuery.map((map) => ProductLocation.fromMap(map)).toList();
    }
    
    // Barkod bulunamazsa ürün adı veya stok koduna göre ara
    final productQuery = await db.query(
      DbTables.products,
      where: '${DbColumns.productsName} IN ($placeholders) OR ${DbColumns.productsCode} IN ($placeholders)',
      whereArgs: [...whereArgs, ...whereArgs],
      limit: 1,
    );

    if (productQuery.isEmpty) {
      return [];
    }
    final productId = productQuery.first[DbColumns.productsId] as int;

    // 2. Ürün lokasyonları - iş mantığına özel kompleks sorgu
    final sql = '''
      SELECT
        s.${DbColumns.stockProductId},
        u.${DbColumns.productsName},
        u.${DbColumns.productsCode},
        s.${DbColumns.stockQuantity},
        s.${DbColumns.stockPalletBarcode},
        s.${DbColumns.stockExpiryDate},
        s.${DbColumns.stockLocationId},
        sh.${DbColumns.locationsName} as location_name,
        sh.${DbColumns.locationsCode} as location_code
      FROM ${DbTables.inventoryStock} s
      JOIN ${DbTables.products} u ON u.${DbColumns.productsId} = s.${DbColumns.stockProductId}
      LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
      WHERE s.${DbColumns.stockProductId} = ? AND s.${DbColumns.stockStatus} = '${DbColumns.stockStatusAvailable}'
      ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.updatedAt} ASC
    ''';

    final results = await db.rawQuery(sql, [productId]);

    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }
}
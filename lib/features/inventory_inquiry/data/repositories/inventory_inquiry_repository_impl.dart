
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

    // 1. Yeni barkod sistemi: Her search term için barkod araması yap
    for (final searchTerm in searchTerms) {
      final productByBarcode = await dbHelper.getProductByBarcode(searchTerm);
      if (productByBarcode != null) {
        final productId = productByBarcode['UrunId'] as int;
        
        // 2. Bu ürünün stok durumunu detaylı bilgilerle getir
        final sql = '''
          SELECT
            s.${DbColumns.stockProductId} as urun_id,
            u.${DbColumns.productsName} as UrunAdi,
            u.${DbColumns.productsCode} as StokKodu,
            s.${DbColumns.stockQuantity} as quantity,
            s.${DbColumns.stockPalletBarcode} as pallet_barcode,
            s.${DbColumns.stockExpiryDate} as expiry_date,
            s.${DbColumns.stockLocationId} as location_id,
            sh.${DbColumns.locationsName} as location_name,
            sh.${DbColumns.locationsCode} as location_code
          FROM ${DbTables.inventoryStock} s
          JOIN ${DbTables.products} u ON u.${DbColumns.productsId} = s.${DbColumns.stockProductId}
          LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
          WHERE s.${DbColumns.stockProductId} = ? AND s.${DbColumns.stockStatus} = '${DbColumns.stockStatusAvailable}'
          ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.updatedAt} ASC
        ''';
        
        final stockResults = await db.rawQuery(sql, [productId]);
        return stockResults.map((map) => ProductLocation.fromMap(map)).toList();
      }
    }
    
    // Yeni barkod sisteminde barkod bulunamadıysa sonuç yok
    return [];
  }
}
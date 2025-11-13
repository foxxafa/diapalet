
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:diapalet/core/utils/gs1_parser.dart';
import 'package:diapalet/features/inventory_inquiry/constants/inventory_inquiry_constants.dart';
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
    if (parsedData.containsKey(InventoryInquiryConstants.gs1GtinKey)) {
      final gtin = parsedData[InventoryInquiryConstants.gs1GtinKey]!;
      searchTerms.add(gtin);
      // Eğer GTIN-14 ise ve '0' ile başlıyorsa, baştaki '0'ı atıp GTIN-13 olarak da ekle
      if (gtin.length == InventoryInquiryConstants.gtin14Length && gtin.startsWith(InventoryInquiryConstants.gtinLeadingZero)) {
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
        final productKey = productByBarcode['_key'] as String;
        
        // 2. Bu ürünün stok durumunu detaylı bilgilerle getir
        final sql = '''
          SELECT
            s.urun_key,
            u.${DbColumns.productsName} as UrunAdi,
            u.${DbColumns.productsCode} as StokKodu,
            unit.BirimAdi as unit_name,
            s.${DbColumns.stockQuantity} as quantity,
            s.${DbColumns.stockPalletBarcode} as pallet_barcode,
            s.${DbColumns.stockExpiryDate} as expiry_date,
            s.${DbColumns.stockLocationId} as location_id,
            sh.${DbColumns.locationsName} as location_name,
            sh.${DbColumns.locationsCode} as location_code
          FROM ${DbTables.inventoryStock} s
          JOIN ${DbTables.products} u ON u._key = s.urun_key
          LEFT JOIN birimler unit ON unit._key = s.birim_key
          LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
          WHERE s.urun_key = ? AND s.${DbColumns.stockStatus} = '${InventoryInquiryConstants.stockAvailableStatus}'
          ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.updatedAt} ASC
        ''';
        
        final stockResults = await db.rawQuery(sql, [productKey]);
        return stockResults.map((map) => ProductLocation.fromMap(map)).toList();
      }
    }
    
    // Yeni barkod sisteminde barkod bulunamadıysa sonuç yok
    return [];
  }

  @override
  Future<List<ProductLocation>> searchProductLocationsByStockCode(String query) async {
    final db = await dbHelper.database;
    
    final sql = '''
      SELECT DISTINCT
        s.urun_key,
        u.${DbColumns.productsName} as UrunAdi,
        u.${DbColumns.productsCode} as StokKodu,
        unit.BirimAdi as unit_name,
        s.${DbColumns.stockQuantity} as quantity,
        s.${DbColumns.stockPalletBarcode} as pallet_barcode,
        s.${DbColumns.stockExpiryDate} as expiry_date,
        s.${DbColumns.stockLocationId} as location_id,
        sh.${DbColumns.locationsName} as location_name,
        sh.${DbColumns.locationsCode} as location_code
      FROM ${DbTables.inventoryStock} s
      JOIN ${DbTables.products} u ON u._key = s.urun_key
      LEFT JOIN birimler unit ON unit._key = s.birim_key
      LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
      WHERE s.stock_uuid IN (
        SELECT DISTINCT s2.stock_uuid
        FROM ${DbTables.inventoryStock} s2
        JOIN ${DbTables.products} u2 ON u2._key = s2.urun_key
        LEFT JOIN birimler b ON b.StokKodu = u2.${DbColumns.productsCode}
        LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
        WHERE (u2.${DbColumns.productsCode} LIKE ? OR bark.barkod LIKE ?)
      )
        AND s.${DbColumns.stockStatus} = '${InventoryInquiryConstants.stockAvailableStatus}'
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
        AND s.${DbColumns.stockLocationId} IS NOT NULL
      ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.createdAt} ASC, u.${DbColumns.productsCode} ASC
    ''';
    
    final results = await db.rawQuery(sql, ['${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}', '${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}']);
    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getProductSuggestions(String query) async {
    final db = await dbHelper.database;
    
    final sql = '''
      SELECT DISTINCT
        u._key as urun_key,
        u.${DbColumns.productsName} as UrunAdi,
        u.${DbColumns.productsCode} as StokKodu,
        bark.barkod as barcode,
        unit.BirimAdi as unit_name
      FROM ${DbTables.inventoryStock} s
      JOIN ${DbTables.products} u ON u._key = s.urun_key
      LEFT JOIN birimler unit ON unit._key = s.birim_key
      LEFT JOIN birimler b ON b.StokKodu = u.${DbColumns.productsCode}
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE (u.${DbColumns.productsCode} LIKE ? OR bark.barkod LIKE ?)
        AND s.${DbColumns.stockStatus} = '${InventoryInquiryConstants.stockAvailableStatus}'
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
        AND s.${DbColumns.stockLocationId} IS NOT NULL
      ORDER BY u.${DbColumns.productsCode} ASC
      LIMIT ${InventoryInquiryConstants.maxProductSuggestions}
    ''';
    
    return await db.rawQuery(sql, ['${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}', '${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}']);
  }
}
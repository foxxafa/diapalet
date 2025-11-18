
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
        WHERE u2.${DbColumns.productsCode} LIKE ?
      )
        AND s.${DbColumns.stockStatus} = '${InventoryInquiryConstants.stockAvailableStatus}'
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
        AND s.${DbColumns.stockLocationId} IS NOT NULL
      ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.createdAt} ASC, u.${DbColumns.productsCode} ASC
    ''';

    final searchPattern = '${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}';
    final results = await db.rawQuery(sql, [searchPattern]);
    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }

  @override
  Future<List<ProductLocation>> searchProductLocationsByProductName(String query) async {
    final db = await dbHelper.database;

    // Kelimeleri ayır (goods_receiving mantığı)
    final keywords = query
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (keywords.isEmpty) return [];

    // Tek kelime ise: başlayan veya içeren ürünleri bul
    if (keywords.length == 1) {
      final searchTerm = keywords.first;

      final sql = '''
        SELECT DISTINCT
          s.urun_key,
          u.UrunAdi as UrunAdi,
          u.StokKodu as StokKodu,
          unit.BirimAdi as unit_name,
          s.quantity as quantity,
          s.pallet_barcode as pallet_barcode,
          s.expiry_date as expiry_date,
          s.location_id as location_id,
          sh.location_name as location_name,
          sh.location_code as location_code,
          CASE
            WHEN UPPER(u.UrunAdi) LIKE ? THEN 1
            ELSE 2
          END as priority
        FROM inventory_stock s
        JOIN urunler u ON u._key = s.urun_key
        LEFT JOIN birimler unit ON unit._key = s.birim_key
        LEFT JOIN shelfs sh ON sh.id = s.location_id
        WHERE (UPPER(u.UrunAdi) LIKE ? OR UPPER(u.UrunAdi) LIKE ?)
          AND s.status = 'available'
          AND s.quantity > 0
          AND s.location_id IS NOT NULL
        ORDER BY priority ASC, u.UrunAdi ASC, s.expiry_date ASC
      ''';

      final results = await db.rawQuery(sql, ['$searchTerm%', '$searchTerm%', '%$searchTerm%']);
      return results.map((map) => ProductLocation.fromMap(map)).toList();
    }

    // Çoklu kelime: İlk önce başlayan kelimeleri ara (FIZZ 12 için UPPER(UrunAdi) LIKE 'FIZZ%' AND UPPER(UrunAdi) LIKE '12%')
    var nameConditions = keywords.map((_) => 'UPPER(u.UrunAdi) LIKE ?').join(' AND ');
    var nameParams = keywords.map((k) => '$k%').toList();

    var sql = '''
      SELECT DISTINCT
        s.urun_key,
        u.UrunAdi as UrunAdi,
        u.StokKodu as StokKodu,
        unit.BirimAdi as unit_name,
        s.quantity as quantity,
        s.pallet_barcode as pallet_barcode,
        s.expiry_date as expiry_date,
        s.location_id as location_id,
        sh.location_name as location_name,
        sh.location_code as location_code
      FROM inventory_stock s
      JOIN urunler u ON u._key = s.urun_key
      LEFT JOIN birimler unit ON unit._key = s.birim_key
      LEFT JOIN shelfs sh ON sh.id = s.location_id
      WHERE $nameConditions
        AND s.status = 'available'
        AND s.quantity > 0
        AND s.location_id IS NOT NULL
      ORDER BY u.UrunAdi ASC, s.expiry_date ASC, s.created_at ASC
    ''';

    var results = await db.rawQuery(sql, nameParams);

    // Eğer yeterli sonuç yoksa, içeren kelimeleri ara (FIZZ 12 için UPPER(UrunAdi) LIKE '%FIZZ%' AND UPPER(UrunAdi) LIKE '%12%')
    if (results.length < 5) {
      nameConditions = keywords.map((_) => 'UPPER(u.UrunAdi) LIKE ?').join(' AND ');
      nameParams = keywords.map((k) => '%$k%').toList();

      sql = '''
        SELECT DISTINCT
          s.urun_key,
          u.UrunAdi as UrunAdi,
          u.StokKodu as StokKodu,
          unit.BirimAdi as unit_name,
          s.quantity as quantity,
          s.pallet_barcode as pallet_barcode,
          s.expiry_date as expiry_date,
          s.location_id as location_id,
          sh.location_name as location_name,
          sh.location_code as location_code
        FROM inventory_stock s
        JOIN urunler u ON u._key = s.urun_key
        LEFT JOIN birimler unit ON unit._key = s.birim_key
        LEFT JOIN shelfs sh ON sh.id = s.location_id
        WHERE $nameConditions
          AND s.status = 'available'
          AND s.quantity > 0
          AND s.location_id IS NOT NULL
        ORDER BY u.UrunAdi ASC, s.expiry_date ASC, s.created_at ASC
      ''';

      results = await db.rawQuery(sql, nameParams);
    }

    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }

  @override
  Future<List<ProductLocation>> searchProductLocationsByPalletBarcode(String palletBarcode) async {
    final db = await dbHelper.database;

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
      WHERE s.${DbColumns.stockPalletBarcode} = ?
        AND s.${DbColumns.stockStatus} = '${InventoryInquiryConstants.stockAvailableStatus}'
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
      ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.updatedAt} ASC
    ''';

    final results = await db.rawQuery(sql, [palletBarcode]);
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
        s.${DbColumns.stockPalletBarcode} as pallet_barcode,
        unit.BirimAdi as unit_name
      FROM ${DbTables.inventoryStock} s
      JOIN ${DbTables.products} u ON u._key = s.urun_key
      LEFT JOIN birimler unit ON unit._key = s.birim_key
      LEFT JOIN birimler b ON b.StokKodu = u.${DbColumns.productsCode}
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE (u.${DbColumns.productsCode} LIKE ? OR bark.barkod LIKE ? OR u.${DbColumns.productsName} LIKE ? OR s.${DbColumns.stockPalletBarcode} LIKE ?)
        AND s.${DbColumns.stockStatus} = '${InventoryInquiryConstants.stockAvailableStatus}'
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
        AND s.${DbColumns.stockLocationId} IS NOT NULL
      ORDER BY u.${DbColumns.productsCode} ASC
      LIMIT ${InventoryInquiryConstants.maxProductSuggestions}
    ''';

    final searchPattern = '${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}';
    return await db.rawQuery(sql, [searchPattern, searchPattern, searchPattern, searchPattern]);
  }
}
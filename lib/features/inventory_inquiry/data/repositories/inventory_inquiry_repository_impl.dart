
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
        
        // 2. Bu ürünün stok durumunu detaylı bilgilerle getir (available ve receiving)
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
            sh.${DbColumns.locationsCode} as location_code,
            s.receipt_operation_uuid,
            gr.delivery_note_number,
            sip.fisno as order_number
          FROM ${DbTables.inventoryStock} s
          JOIN ${DbTables.products} u ON u._key = s.urun_key
          LEFT JOIN birimler unit ON unit._key = s.birim_key
          LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
          LEFT JOIN goods_receipts gr ON gr.operation_unique_id = s.receipt_operation_uuid
          LEFT JOIN siparisler sip ON sip.id = gr.siparis_id
          WHERE s.urun_key = ? AND s.${DbColumns.stockStatus} IN ('${InventoryInquiryConstants.stockAvailableStatus}', 'receiving')
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
        sh.${DbColumns.locationsCode} as location_code,
        s.receipt_operation_uuid,
        gr.delivery_note_number,
        sip.fisno as order_number
      FROM ${DbTables.inventoryStock} s
      JOIN ${DbTables.products} u ON u._key = s.urun_key
      LEFT JOIN birimler unit ON unit._key = s.birim_key
      LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
      LEFT JOIN goods_receipts gr ON gr.operation_unique_id = s.receipt_operation_uuid
      LEFT JOIN siparisler sip ON sip.id = gr.siparis_id
      WHERE s.stock_uuid IN (
        SELECT DISTINCT s2.stock_uuid
        FROM ${DbTables.inventoryStock} s2
        JOIN ${DbTables.products} u2 ON u2._key = s2.urun_key
        WHERE u2.${DbColumns.productsCode} LIKE ?
      )
        AND s.${DbColumns.stockStatus} IN ('${InventoryInquiryConstants.stockAvailableStatus}', 'receiving')
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
      ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.createdAt} ASC, u.${DbColumns.productsCode} ASC
    ''';

    final searchPattern = '${InventoryInquiryConstants.wildcardPrefix}$query${InventoryInquiryConstants.wildcardSuffix}';
    final results = await db.rawQuery(sql, [searchPattern]);
    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }

  @override
  Future<List<ProductLocation>> searchProductLocationsByProductName(String query) async {
    final db = await dbHelper.database;
    final keywords = query
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (keywords.isEmpty) {
      return [];
    }

    // Sadece ürün adına göre arama yap
    final whereClause = keywords.map((k) => 'UPPER(u.${DbColumns.productsName}) LIKE ?').join(' AND ');
    final params = keywords.map((k) => '%$k%').toList();

    final sql = '''
          SELECT
            s.urun_key,
            u.${DbColumns.productsName} as UrunAdi,
            u.${DbColumns.productsCode} as StokKodu,
            bark.barkod as barcode,
            unit.BirimAdi as unit_name,
            s.${DbColumns.stockQuantity} as quantity,
            s.${DbColumns.stockPalletBarcode} as pallet_barcode,
            s.${DbColumns.stockExpiryDate} as expiry_date,
            s.${DbColumns.stockLocationId} as location_id,
            sh.${DbColumns.locationsName} as location_name,
            sh.${DbColumns.locationsCode} as location_code,
            s.receipt_operation_uuid,
            gr.delivery_note_number,
            sip.fisno as order_number
          FROM ${DbTables.inventoryStock} s
          JOIN ${DbTables.products} u ON u._key = s.urun_key
          LEFT JOIN birimler unit ON unit._key = s.birim_key
          LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
          LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = unit._key
          LEFT JOIN goods_receipts gr ON gr.operation_unique_id = s.receipt_operation_uuid
          LEFT JOIN siparisler sip ON sip.id = gr.siparis_id
          WHERE $whereClause
            AND s.${DbColumns.stockStatus} IN ('${InventoryInquiryConstants.stockAvailableStatus}', 'receiving')
            AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
          ORDER BY u.${DbColumns.productsName} ASC, s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.createdAt} ASC
        ''';

    final results = await db.rawQuery(sql, params);
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
        sh.${DbColumns.locationsCode} as location_code,
        s.receipt_operation_uuid,
        gr.delivery_note_number,
        sip.fisno as order_number
      FROM ${DbTables.inventoryStock} s
      JOIN ${DbTables.products} u ON u._key = s.urun_key
      LEFT JOIN birimler unit ON unit._key = s.birim_key
      LEFT JOIN ${DbTables.locations} sh ON sh.${DbColumns.id} = s.${DbColumns.stockLocationId}
      LEFT JOIN goods_receipts gr ON gr.operation_unique_id = s.receipt_operation_uuid
      LEFT JOIN siparisler sip ON sip.id = gr.siparis_id
      WHERE s.${DbColumns.stockPalletBarcode} = ?
        AND s.${DbColumns.stockStatus} IN ('${InventoryInquiryConstants.stockAvailableStatus}', 'receiving')
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
      ORDER BY s.${DbColumns.stockExpiryDate} ASC, s.${DbColumns.updatedAt} ASC
    ''';

    final results = await db.rawQuery(sql, [palletBarcode]);
    return results.map((map) => ProductLocation.fromMap(map)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getProductSuggestions(String query, SuggestionSearchType searchType) async {
    final db = await dbHelper.database;
    final String searchTerm = query.trim().toUpperCase();

    if (searchTerm.isEmpty) {
      return [];
    }

    String whereClause;
    List<dynamic> whereParams;
    String orderByClause;
    List<dynamic> orderByParams;

    switch (searchType) {
      case SuggestionSearchType.pallet:
        // Sadece pallet barcode'a göre ara
        whereClause = "s.${DbColumns.stockPalletBarcode} IS NOT NULL AND UPPER(s.${DbColumns.stockPalletBarcode}) LIKE ?";
        whereParams = ['%$searchTerm%'];
        orderByClause = '''
          CASE
            WHEN UPPER(s.${DbColumns.stockPalletBarcode}) = ? THEN 1
            WHEN UPPER(s.${DbColumns.stockPalletBarcode}) LIKE ? THEN 2
            ELSE 3
          END,
          s.${DbColumns.stockPalletBarcode} ASC
        ''';
        orderByParams = [searchTerm, '$searchTerm%'];
        break;

      case SuggestionSearchType.barcode:
        // Sadece barkod'a göre ara
        whereClause = "UPPER(bark.barkod) LIKE ?";
        whereParams = ['%$searchTerm%'];
        orderByClause = '''
          CASE
            WHEN UPPER(bark.barkod) = ? THEN 1
            WHEN UPPER(bark.barkod) LIKE ? THEN 2
            ELSE 3
          END,
          bark.barkod ASC
        ''';
        orderByParams = [searchTerm, '$searchTerm%'];
        break;

      case SuggestionSearchType.stockCode:
        // Sadece stok kodu'na göre ara
        whereClause = "UPPER(u.${DbColumns.productsCode}) LIKE ?";
        whereParams = ['%$searchTerm%'];
        orderByClause = '''
          CASE
            WHEN UPPER(u.${DbColumns.productsCode}) = ? THEN 1
            WHEN UPPER(u.${DbColumns.productsCode}) LIKE ? THEN 2
            ELSE 3
          END,
          u.${DbColumns.productsCode} ASC
        ''';
        orderByParams = [searchTerm, '$searchTerm%'];
        break;

      case SuggestionSearchType.productName:
        // Ürün adına göre ara (çoklu kelime desteği)
        final keywords = searchTerm.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        final List<String> nameConditions = [];
        whereParams = [];

        for (final keyword in keywords) {
          nameConditions.add("UPPER(u.${DbColumns.productsName}) LIKE ?");
          whereParams.add('%$keyword%');
        }

        whereClause = nameConditions.join(' AND ');
        orderByClause = '''
          CASE
            WHEN UPPER(u.${DbColumns.productsName}) = ? THEN 1
            WHEN UPPER(u.${DbColumns.productsName}) LIKE ? THEN 2
            ELSE 3
          END,
          u.${DbColumns.productsName} ASC
        ''';
        orderByParams = [searchTerm, '$searchTerm%'];
        break;
    }

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
      WHERE $whereClause
        AND s.${DbColumns.stockStatus} IN ('${InventoryInquiryConstants.stockAvailableStatus}', 'receiving')
        AND s.${DbColumns.stockQuantity} > ${InventoryInquiryConstants.minStockQuantity}
      ORDER BY $orderByClause
      LIMIT ${InventoryInquiryConstants.maxProductSuggestions}
    ''';

    final allParams = [...whereParams, ...orderByParams];
    return await db.rawQuery(sql, allParams);
  }
}
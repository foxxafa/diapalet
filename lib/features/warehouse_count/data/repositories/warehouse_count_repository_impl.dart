// lib/features/warehouse_count/data/repositories/warehouse_count_repository_impl.dart

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/services/telegram_logger_service.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/warehouse_count/constants/warehouse_count_constants.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';
import 'package:diapalet/features/warehouse_count/domain/repositories/warehouse_count_repository.dart';

class WarehouseCountRepositoryImpl implements WarehouseCountRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;

  WarehouseCountRepositoryImpl({
    required this.dbHelper,
    required this.dio,
  });

  @override
  Future<List<CountSheet>> getCountSheetsByWarehouse(String warehouseCode) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'count_sheets',
      where: 'warehouse_code = ?',
      whereArgs: [warehouseCode],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => CountSheet.fromMap(map)).toList();
  }

  @override
  Future<CountSheet?> getCountSheetById(int id) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'count_sheets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return CountSheet.fromMap(maps.first);
  }

  @override
  Future<List<CountItem>> getCountItemsBySheetId(int countSheetId) async {
    final db = await dbHelper.database;

    // First get the operation_unique_id from count_sheets
    final sheetResult = await db.query(
      'count_sheets',
      columns: ['operation_unique_id'],
      where: 'id = ?',
      whereArgs: [countSheetId],
      limit: 1,
    );

    if (sheetResult.isEmpty) {
      return [];
    }

    final operationUniqueId = sheetResult.first['operation_unique_id'] as String;

    // JOIN with birimler table to get birimadi
    // Use operation_unique_id for relation (no more count_sheet_id FK)
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        ci.*,
        b.birimadi as birim_adi
      FROM count_items ci
      LEFT JOIN birimler b ON ci.birim_key = b._key
      WHERE ci.operation_unique_id = ?
      ORDER BY ci.created_at ASC
    ''', [operationUniqueId]);

    // Debug: Print detailed info to verify JOIN is working
    debugPrint('🔍 Retrieved ${maps.length} count items for operation_unique_id: $operationUniqueId');
    for (var map in maps) {
      debugPrint('📦 CountItem: birim_key=${map['birim_key']}, birim_adi=${map['birim_adi']}, stokKodu=${map['StokKodu']}');

      // Extra debug: Check if birim exists in birimler table
      if (map['birim_adi'] == null && map['birim_key'] != null) {
        final birimCheck = await db.query(
          'birimler',
          where: '_key = ?',
          whereArgs: [map['birim_key']],
          limit: 1,
        );
        debugPrint('⚠️ Birim lookup failed. birim_key=${map['birim_key']}, Found in birimler: ${birimCheck.isNotEmpty}');
        if (birimCheck.isNotEmpty) {
          debugPrint('   Found birim: ${birimCheck.first}');
        }
      }
    }

    return maps.map((map) => CountItem.fromMap(map)).toList();
  }

  @override
  Future<CountSheet> createCountSheet(CountSheet sheet) async {
    final db = await dbHelper.database;
    final id = await db.insert(
      'count_sheets',
      sheet.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return sheet.copyWith(id: id);
  }

  @override
  Future<void> updateCountSheet(CountSheet sheet) async {
    final db = await dbHelper.database;
    await db.update(
      'count_sheets',
      sheet.toMap(),
      where: 'id = ?',
      whereArgs: [sheet.id],
    );
  }

  @override
  Future<void> completeCountSheet(int countSheetId) async {
    final db = await dbHelper.database;
    final now = DateTime.now().toUtc();
    await db.update(
      'count_sheets',
      {
        'status': WarehouseCountConstants.statusCompleted,
        'complete_date': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [countSheetId],
    );
  }

  @override
  Future<CountItem> addCountItem(CountItem item) async {
    final db = await dbHelper.database;

    try {
      final id = await db.insert(
        'count_items',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort, // Changed from replace to abort
      );

      return item.copyWith(id: id);
    } catch (e) {
      // If duplicate UUID error, log it and rethrow
      if (e.toString().contains('UNIQUE constraint failed')) {
        debugPrint('❌ DUPLICATE UUID ERROR: ${item.itemUuid} already exists!');
        debugPrint('   Item details: StokKodu=${item.stokKodu}, Qty=${item.quantityCounted}');
        rethrow;
      }
      rethrow;
    }
  }

  @override
  Future<void> updateCountItem(CountItem item) async {
    final db = await dbHelper.database;
    await db.update(
      'count_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  @override
  Future<void> deleteCountItem(int itemId) async {
    final db = await dbHelper.database;
    await db.delete(
      'count_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  @override
  Future<void> deleteAllItemsForSheet(int countSheetId) async {
    final db = await dbHelper.database;

    // Get operation_unique_id first
    final sheetResult = await db.query(
      'count_sheets',
      columns: ['operation_unique_id'],
      where: 'id = ?',
      whereArgs: [countSheetId],
      limit: 1,
    );

    if (sheetResult.isEmpty) {
      return;
    }

    final operationUniqueId = sheetResult.first['operation_unique_id'] as String;

    await db.delete(
      'count_items',
      where: 'operation_unique_id = ?',
      whereArgs: [operationUniqueId],
    );
  }

  @override
  Future<bool> saveCountSheetToServer(CountSheet sheet, List<CountItem> items) async {
    try {
      debugPrint('🌐 Attempting to save count sheet to server (Save & Continue)...');

      final payload = {
        'header': sheet.toJson(),  // Backend expects 'header', not 'sheet'
        'items': items.map((item) => item.toJson()).toList(),
      };

      final response = await dio.post(
        '/index.php?r=terminal/warehouse-count-save',
        data: payload,
      );

      if (response.statusCode == 200 && response.data['status'] == 200) {
        debugPrint('✅ Count sheet saved to server successfully');

        // Update local updated_at timestamp
        final db = await dbHelper.database;
        await db.update(
          'count_sheets',
          {'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [sheet.id],
        );

        return true;
      } else {
        debugPrint('⚠️ Server returned non-success status: ${response.data}');
        return false;
      }
    } on DioException catch (e, stackTrace) {
      debugPrint('❌ Failed to save count sheet to server: ${e.message}');

      TelegramLoggerService.logError(
        'Warehouse Count Server Save Failed',
        e.message ?? e.toString(),
        stackTrace: stackTrace,
        context: {
          'repository': 'WarehouseCountRepositoryImpl',
          'method': 'saveCountSheetToServer',
          'sheet_number': sheet.sheetNumber,
          'item_count': items.length.toString(),
        },
      );

      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ Unexpected error saving count sheet: $e');

      TelegramLoggerService.logError(
        'Warehouse Count Unexpected Error',
        e.toString(),
        stackTrace: stackTrace,
        context: {
          'repository': 'WarehouseCountRepositoryImpl',
          'method': 'saveCountSheetToServer',
          'sheet_number': sheet.sheetNumber,
        },
      );

      return false;
    }
  }

  @override
  Future<void> queueCountSheetForSync(CountSheet sheet, List<CountItem> items) async {
    debugPrint('📤 Queueing count sheet for sync (Save & Finish)...');

    final payload = {
      'header': sheet.toJson(),  // Backend expects 'header', not 'sheet'
      'items': items.map((item) => item.toJson()).toList(),
    };

    final pendingOperation = PendingOperation.create(
      type: PendingOperationType.warehouseCount,
      data: jsonEncode(payload),
      createdAt: DateTime.now(),
    );

    final db = await dbHelper.database;
    await db.insert('pending_operation', pendingOperation.toDbMap());

    debugPrint('✅ Count sheet queued for sync with UUID: ${pendingOperation.uniqueId}');
  }

  @override
  String generateSheetNumber(int employeeId) {
    final now = DateTime.now();
    // Yılın son 2 hanesi + ay (2) + gün (2) = 6 karakter
    final yearShort = (now.year % 100).toString().padLeft(2, '0'); // Son 2 hane
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final dateStr = '$yearShort$month$day'; // Örn: 251009

    final uuid = const Uuid().v4().split('-').first.toUpperCase(); // First segment of UUID

    // Format: CNT + YYMMDD + EmployeeID + UUID
    // Örnek: CNT251009488FC2C581
    return '${WarehouseCountConstants.sheetNumberPrefix}$dateStr$employeeId$uuid';
  }

  @override
  Future<Map<String, dynamic>?> searchProductByBarcode(String barcode) async {
    final db = await dbHelper.database;

    // Barkod ile ürün ara (barkodlar tablosundan)
    // İLİŞKİ: barkodlar._key_scf_stokkart_birimleri = birimler._key
    //         birimler._key_scf_stokkart = urunler._key
    final barcodeResult = await db.rawQuery('''
      SELECT
        b.barkod,
        b._key_scf_stokkart_birimleri as birim_key,
        bi.birimadi,
        bi.StokKodu,
        u._key as urun_key,
        u.UrunAdi,
        u.UrunId
      FROM barkodlar b
      INNER JOIN birimler bi ON b._key_scf_stokkart_birimleri = bi._key
      INNER JOIN urunler u ON bi._key_scf_stokkart = u._key
      WHERE b.barkod = ?
      LIMIT 1
    ''', [barcode]);

    if (barcodeResult.isNotEmpty) {
      return barcodeResult.first;
    }

    // Barkod bulunamadıysa, direkt StokKodu olabilir mi dene
    // İLİŞKİ: birimler._key_scf_stokkart = urunler._key
    final stockCodeResult = await db.rawQuery('''
      SELECT
        u.StokKodu as barkod,
        bi._key as birim_key,
        bi.birimadi,
        bi.StokKodu,
        u._key as urun_key,
        u.UrunAdi,
        u.UrunId
      FROM urunler u
      LEFT JOIN birimler bi ON bi._key_scf_stokkart = u._key
      WHERE u.StokKodu = ?
      LIMIT 1
    ''', [barcode]);

    if (stockCodeResult.isNotEmpty) {
      return stockCodeResult.first;
    }

    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> searchProductsPartial(String query) async {
    final db = await dbHelper.database;
    final stopwatch = Stopwatch()..start();

    final keywords = query
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (keywords.isEmpty) {
      return [];
    }

    debugPrint('🔍 Arama kelimeleri: $keywords');

    // Tek kelime ise barkod/stok kodu/ürün adı olabilir
    final isSingleKeyword = keywords.length == 1;

    if (isSingleKeyword) {
      final searchTerm = keywords.first;

      // 🔥 YENİ YAKLAŞIM: Üç alanda da aynı anda ara (UNION ile)
      // Barkod: Tamamen sayı (örn: 5382241, 203278)
      // StokKodu: Harf + sayı karışık (örn: CC05782, A-3135)
      // ÜrünAdı: Harf + sayı karışık (örn: HALLEY, *CTR UKF...)

      // Priority based search with UNION ALL
      // 1. Exact barcode match (highest priority)
      // 2. Exact stock code match
      // 3. Stock code starts with
      // 4. Product name starts with
      // 5. Product name contains (wildcard search)
      final unifiedQuery = '''
        SELECT * FROM (
          -- 1. Exact barcode match (highest priority)
          SELECT
            1 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as urun_key,
            u.UrunAdi,
            u.UrunId
          FROM barkodlar b
          INNER JOIN birimler bi ON b._key_scf_stokkart_birimleri = bi._key
          INNER JOIN urunler u ON bi._key_scf_stokkart = u._key
          WHERE u.aktif = 1 AND b.barkod = ?

          UNION ALL

          -- 2. Barcode starts with
          SELECT
            2 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as urun_key,
            u.UrunAdi,
            u.UrunId
          FROM barkodlar b
          INNER JOIN birimler bi ON b._key_scf_stokkart_birimleri = bi._key
          INNER JOIN urunler u ON bi._key_scf_stokkart = u._key
          WHERE u.aktif = 1 AND b.barkod LIKE ? AND b.barkod != ?

          UNION ALL

          -- 3. Exact stock code match
          SELECT
            3 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as urun_key,
            u.UrunAdi,
            u.UrunId
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.StokKodu = ?

          UNION ALL

          -- 4. Stock code starts with
          SELECT
            4 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as urun_key,
            u.UrunAdi,
            u.UrunId
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.StokKodu LIKE ? AND u.StokKodu != ?

          UNION ALL

          -- 5. Product name starts with
          SELECT
            5 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as urun_key,
            u.UrunAdi,
            u.UrunId
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.UrunAdi LIKE ?

          UNION ALL

          -- 6. Product name contains (wildcard)
          SELECT
            6 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as urun_key,
            u.UrunAdi,
            u.UrunId
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.UrunAdi LIKE ?
        )
        GROUP BY urun_key, birim_key
        ORDER BY priority ASC, UrunAdi ASC
        LIMIT 20
      ''';

      final searchResults = await db.rawQuery(unifiedQuery, [
        searchTerm,              // 1. Exact barcode
        '$searchTerm%',          // 2. Barcode starts with
        searchTerm,              // 2. Exclude exact match (already in #1)
        searchTerm,              // 3. Exact stock code
        '$searchTerm%',          // 4. Stock code starts with
        searchTerm,              // 4. Exclude exact match (already in #3)
        '$searchTerm%',          // 5. Product name starts with
        '%$searchTerm%',         // 6. Product name contains
      ]);

      stopwatch.stop();
      debugPrint('🔍 Birleşik arama: ${searchResults.length} sonuç, ${stopwatch.elapsedMilliseconds}ms');

      // Debug: İlk 3 sonucu göster
      for (int i = 0; i < searchResults.length && i < 3; i++) {
        final result = searchResults[i];
        debugPrint('   ${i+1}. ${result['UrunAdi']} (StokKodu: ${result['StokKodu']}, Barkod: ${result['barkod']}, Priority: ${result['priority']})');
      }

      return searchResults;
    }

    // Çoklu kelime veya harf içeriyor - UrunAdi'nde ara
    final List<String> conditions = [];
    final List<String> params = [];

    for (final keyword in keywords) {
      conditions.add('u.UrunAdi LIKE ?');
      params.add('$keyword%');
    }

    final whereClause = conditions.join(' AND ');

    final simpleQuery = '''
      SELECT
        b.barkod,
        bi._key as birim_key,
        bi.birimadi,
        u.StokKodu,
        u._key as urun_key,
        u.UrunAdi,
        u.UrunId
      FROM urunler u
      INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
      LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
      WHERE u.aktif = 1 AND $whereClause
      ORDER BY u.UrunAdi ASC
      LIMIT 20
    ''';

    var searchResults = await db.rawQuery(simpleQuery, params);

    debugPrint('⚡ UrunAdi araması: ${searchResults.length} sonuç, ${stopwatch.elapsedMilliseconds}ms');

    // Yeterli sonuç yoksa genel arama
    if (searchResults.length < 5) {
      debugPrint('🔍 Genel arama yapılıyor...');

      final List<String> generalCond = [];
      final List<String> generalParams = [];

      for (final keyword in keywords) {
        generalCond.add('u.UrunAdi LIKE ?');
        generalParams.add('%$keyword%');
      }

      final generalWhere = generalCond.join(' AND ');

      final generalQuery = '''
        SELECT
          b.barkod,
          bi._key as birim_key,
          bi.birimadi,
          u.StokKodu,
          u._key as urun_key,
          u.UrunAdi,
          u.UrunId
        FROM urunler u
        INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
        LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
        WHERE u.aktif = 1 AND $generalWhere
        ORDER BY u.UrunAdi ASC
        LIMIT 20
      ''';

      searchResults = await db.rawQuery(generalQuery, generalParams);
    }

    stopwatch.stop();
    debugPrint('🔍 Toplam: ${searchResults.length} sonuç, ${stopwatch.elapsedMilliseconds}ms');

    return searchResults;
  }

  @override
  Future<bool> validateShelfCode(String shelfCode) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'shelfs',
      where: 'name = ? AND is_active = 1',
      whereArgs: [shelfCode],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  @override
  Future<int?> getLocationIdByShelfCode(String shelfCode) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'shelfs',
      columns: ['id'],
      where: 'name = ? AND is_active = 1',
      whereArgs: [shelfCode],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['id'] as int?;
    }
    return null;
  }
}

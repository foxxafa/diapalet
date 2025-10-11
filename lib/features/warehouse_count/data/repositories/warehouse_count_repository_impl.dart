// lib/features/warehouse_count/data/repositories/warehouse_count_repository_impl.dart

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:diapalet/core/local/database_helper.dart';
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
    final id = await db.insert(
      'count_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return item.copyWith(id: id);
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
    } on DioException catch (e) {
      debugPrint('❌ Failed to save count sheet to server: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error saving count sheet: $e');
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

    // İLİŞKİ: barkodlar._key_scf_stokkart_birimleri = birimler._key
    //         birimler._key_scf_stokkart = urunler._key
    final searchResults = await db.rawQuery('''
      SELECT DISTINCT
        b.barkod,
        bi._key as birim_key,
        bi.birimadi,
        bi.StokKodu,
        u._key as urun_key,
        u.UrunAdi,
        u.UrunId
      FROM barkodlar b
      INNER JOIN birimler bi ON b._key_scf_stokkart_birimleri = bi._key
      INNER JOIN urunler u ON bi._key_scf_stokkart = u._key
      WHERE b.barkod LIKE ? OR u.StokKodu LIKE ? OR u.UrunAdi LIKE ?
      ORDER BY
        CASE
          WHEN u.StokKodu LIKE ? THEN 1  -- Stok kodu eşleşmesi (ÖNCELİKLİ)
          WHEN b.barkod LIKE ? THEN 2    -- Barkod eşleşmesi
          WHEN u.UrunAdi LIKE ? THEN 3   -- Ürün adı eşleşmesi
          ELSE 4
        END,
        u.UrunAdi ASC
      LIMIT 5
    ''', ['%$query%', '%$query%', '%$query%', '%$query%', '%$query%', '%$query%']);

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

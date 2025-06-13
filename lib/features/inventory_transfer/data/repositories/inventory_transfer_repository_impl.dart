import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;

  InventoryTransferRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  });

  @override
  Future<Map<String, int>> getSourceLocations() async {
    if (await networkInfo.isConnected) {
      try {
        final response = await dio.get(ApiConfig.locations);
        if (response.statusCode == 200 && response.data is List) {
          final locations = response.data as List;
          return {for (var loc in locations) (loc['name'] as String): (loc['id'] as int)};
        }
      } catch (e) {
        debugPrint("API getSourceLocations failed, fallback to local DB. Error: $e");
      }
    }

    debugPrint("Fetching source locations from local database.");
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'locations',
      columns: ['id', 'name'],
      where: 'is_active = 1',
      orderBy: 'name',
    );
    return {for (var map in maps) (map['name'] as String): (map['id'] as int)};
  }

  @override
  Future<Map<String, int>> getTargetLocations() async {
    return getSourceLocations();
  }

  @override
  Future<List<String>> getPalletIdsAtLocation(int locationId) async {
    if (await networkInfo.isConnected) {
      try {
        final response = await dio.get(
          '${ApiConfig.sanitizedBaseUrl}/containers/$locationId/ids',
          queryParameters: {'mode': 'pallet'},
        );
        if (response.statusCode == 200 && response.data is List) {
          debugPrint("Fetched pallet IDs from API for location $locationId.");
          return List<String>.from(response.data);
        }
      } catch (e) {
        debugPrint("API getPalletIdsAtLocation failed, fallback to local DB. Error: $e");
      }
    }

    debugPrint("Fetching pallet IDs from local DB for location $locationId.");
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT pallet_barcode
      FROM inventory_stock
      WHERE location_id = ? AND pallet_barcode IS NOT NULL
    ''', [locationId]);
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    if (await networkInfo.isConnected) {
      try {
        final response = await dio.get(
          '${ApiConfig.sanitizedBaseUrl}/containers/$locationId/ids',
          queryParameters: {'mode': 'box'},
        );
        if (response.statusCode == 200 && response.data is List) {
          debugPrint("Fetched box items from API for location $locationId.");
          return (response.data as List)
              .map((item) => BoxItem.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        debugPrint("API getBoxesAtLocation failed, fallback to local DB. Error: $e");
      }
    }

    debugPrint("Fetching box items from local DB for location $locationId.");
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        u.UrunId as productId,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON u.UrunId = s.urun_id
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL
      GROUP BY u.UrunId, u.UrunAdi, u.StokKodu
    ''', [locationId]);
    return maps.map((map) => BoxItem.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletId) async {
    if (await networkInfo.isConnected) {
      try {
        final response = await dio.get('${ApiConfig.sanitizedBaseUrl}/containers/$palletId/contents');
        if (response.statusCode == 200 && response.data is List) {
          debugPrint("Fetched pallet contents from API for pallet $palletId.");
          return (response.data as List)
              .map((item) => ProductItem.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        debugPrint("API getPalletContents failed, fallback to local DB. Error: $e");
      }
    }

    debugPrint("Fetching pallet contents from local DB for pallet $palletId.");
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        u.UrunId AS id,
        u.UrunAdi AS name,
        u.StokKodu AS code,
        s.quantity AS currentQuantity
      FROM inventory_stock s
      JOIN urunler u ON u.UrunId = s.urun_id
      WHERE s.pallet_barcode = ?
    ''', [palletId]);
    return maps.map((map) => ProductItem.fromMap(map)).toList();
  }

  @override
  Future<void> recordTransferOperation(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) async {
    // GÜNCELLEME: Sadece online modda çalışacak şekilde yeniden düzenlendi.
    // Lokal veritabanı işlemleri (kontrol ve kayıt) geçici olarak kaldırıldı.
    if (!await networkInfo.isConnected) {
      throw Exception("İnternet bağlantısı yok. İşlem yalnızca online modda yapılabilir.");
    }

    final transferDateString = DateFormat('yyyy-MM-dd HH:mm:ss').format(header.transferDate);

    final apiPayload = {
      "header": {
        "operation_type": header.operationType.apiName,
        "source_location_id": sourceLocationId,
        "target_location_id": targetLocationId,
        "transfer_date": transferDateString,
        "employee_id": 1, // Placeholder
      },
      "items": items.map((item) => {
        "product_id": item.productId,
        "quantity": item.quantity,
        "pallet_id": item.sourcePalletBarcode,
      }).toList(),
    };

    try {
      debugPrint("Transfer API'sine gönderiliyor: ${jsonEncode(apiPayload)}");
      final response = await dio.post(ApiConfig.transfers, data: apiPayload);

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("Transfer işlemi başarıyla API'ye gönderildi.");
      } else {
        // API'den 2xx dışında bir status kodu gelirse hata fırlat.
        final errorDetail = response.data is Map ? response.data['error'] : response.data;
        debugPrint("API Hatası: Sunucu ${response.statusCode} koduyla yanıt verdi. Yanıt: $errorDetail");
        throw Exception("Sunucu hatası (${response.statusCode}): $errorDetail");
      }
    } on DioError catch (e) {
      // Dio kaynaklı hataları (network, timeout vb.) yakala ve daha anlaşılır bir hata fırlat.
      final errorDetail = e.response?.data is Map ? e.response?.data['error'] : e.response?.data;
      debugPrint("Dio Hatası: ${e.message}. Sunucu Yanıtı: $errorDetail");
      throw Exception("Ağ hatası: Sunucuya ulaşılamadı. Detay: ${errorDetail ?? e.message}");
    } catch (e) {
      // Diğer beklenmedik hataları yakala.
      debugPrint("Beklenmedik bir hata oluştu: $e");
      throw Exception("İşlem sırasında beklenmedik bir hata oluştu: $e");
    }
  }

  // Bu metodlar şimdilik çağrılmıyor ama ileride kullanılmak üzere bırakıldı.
  Future<void> _savePendingOperation(String type, Map<String, dynamic> data) async {
    final db = await dbHelper.database;
    await db.insert('pending_operation', {
      'type': type,
      'data': jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
    debugPrint("Transfer bekleyen işlemlere kaydedildi (type: $type).");
  }

  Future<void> _applyLocalTransfer(
      int sourceLocationId,
      int targetLocationId,
      AssignmentMode mode,
      List<TransferItemDetail> items,
      ) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      for (final item in items) {
        final sourcePallet = (mode == AssignmentMode.box) ? null : item.sourcePalletBarcode;
        await _upsertStock(txn, item.productId, sourceLocationId, -item.quantity, sourcePallet);

        final targetPallet = (mode == AssignmentMode.pallet) ? item.sourcePalletBarcode : null;
        await _upsertStock(txn, item.productId, targetLocationId, item.quantity, targetPallet);
      }
    });
    debugPrint("Lokal veritabanı transfer detayları ile güncellendi.");
  }

  Future<void> _upsertStock(DatabaseExecutor txn, int urunId, int locationId, double qtyChange, String? palletBarcode) async {
    final palletClause = palletBarcode != null ? "pallet_barcode = ?" : "pallet_barcode IS NULL";
    final whereArgs = palletBarcode != null ? [urunId, locationId, palletBarcode] : [urunId, locationId];

    final List<Map<String, dynamic>> existing = await txn.query(
      'inventory_stock',
      where: 'urun_id = ? AND location_id = ? AND $palletClause',
      whereArgs: whereArgs,
    );

    if (existing.isNotEmpty) {
      final currentQty = (existing.first['quantity'] as num).toDouble();
      final newQty = currentQty + qtyChange;
      if (newQty > 0.001) {
        await txn.update(
          'inventory_stock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [existing.first['id']]);
      }
    } else if (qtyChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': qtyChange,
        'pallet_barcode': palletBarcode,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
}

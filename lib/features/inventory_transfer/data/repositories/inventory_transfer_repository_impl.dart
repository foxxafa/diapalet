// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:sqflite/sqflite.dart';

// [DÜZELTME] Sınıf adı, dosyanın amacıyla eşleşecek ve isim çakışmasını
// önleyecek şekilde 'InventoryTransferRepositoryImpl' olarak değiştirildi.
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
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('locations',
        columns: ['id', 'name'], where: 'is_active = 1', orderBy: 'name');
    return {for (var map in maps) (map['name'] as String): (map['id'] as int)};
  }

  @override
  Future<Map<String, int>> getTargetLocations() async => getSourceLocations();

  @override
  Future<List<String>> getPalletIdsAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT pallet_barcode
      FROM inventory_stock
      WHERE location_id = ? AND pallet_barcode IS NOT NULL AND quantity > 0
    ''', [locationId]);
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        u.UrunId as productId,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON u.UrunId = s.urun_id
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL AND s.quantity > 0
      GROUP BY u.UrunId, u.UrunAdi, u.StokKodu, u.Barcode1
    ''', [locationId]);
    return maps.map((map) => BoxItem.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletId) async {
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
    final apiPayload = _buildApiPayload(header, items, sourceLocationId, targetLocationId);
    await _saveForSync(apiPayload);
  }

  Future<void> _saveForSync(Map<String, dynamic> apiPayload) async {
    final db = await dbHelper.database;
    try {
      await db.transaction((txn) async {
        await _performLocalStockUpdate(txn, apiPayload, createTransferRecord: true);

        final pendingOp = PendingOperation(
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode(apiPayload),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
      });
      debugPrint("Transfer işlemi başarıyla lokale kaydedildi ve senkronizasyon için sıraya alındı.");
    } catch (e) {
      debugPrint("Lokal transfer kaydı sırasında kritik hata: $e");
      throw Exception("Lokal veritabanına transfer kaydedilirken bir hata oluştu: $e");
    }
  }

  Future<void> _performLocalStockUpdate(
      Transaction txn, Map<String, dynamic> apiPayload,
      {required bool createTransferRecord}) async {
    final headerData = apiPayload['header'] as Map<String, dynamic>;
    final itemsData = apiPayload['items'] as List<dynamic>;
    final sourceLocationId = headerData['source_location_id'] as int;
    final targetLocationId = headerData['target_location_id'] as int;
    final operationType = AssignmentMode.values.firstWhere(
            (e) => e.apiName == headerData['operation_type'],
        orElse: () => AssignmentMode.box);

    for (final itemDynamic in itemsData) {
      final itemMap = itemDynamic as Map<String, dynamic>;
      final int productId = itemMap['product_id'] as int;
      final double quantity = (itemMap['quantity'] as num).toDouble();
      final String? sourcePalletBarcode = itemMap['pallet_id'] as String?;

      if (createTransferRecord) {
        await txn.insert('inventory_transfers', {
          'urun_id': productId,
          'from_location_id': sourceLocationId,
          'to_location_id': targetLocationId,
          'quantity': quantity,
          'pallet_barcode': sourcePalletBarcode,
          'employee_id': headerData['employee_id'] as int,
          'transfer_date': headerData['transfer_date'] as String,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await _updateStockInTransaction(
        txn,
        urunId: productId,
        locationId: sourceLocationId,
        quantityChange: -quantity,
        palletBarcode: sourcePalletBarcode,
      );

      final String? targetPalletBarcode = (operationType == AssignmentMode.pallet) ? sourcePalletBarcode : null;
      await _updateStockInTransaction(
        txn,
        urunId: productId,
        locationId: targetLocationId,
        quantityChange: quantity,
        palletBarcode: targetPalletBarcode,
      );
    }
  }

  Future<void> _updateStockInTransaction(
      Transaction txn, {
        required int urunId,
        required int locationId,
        required double quantityChange,
        String? palletBarcode,
      }) async {
    final palletClause = palletBarcode != null && palletBarcode.isNotEmpty
        ? "pallet_barcode = ?"
        : "pallet_barcode IS NULL";
    final params = palletBarcode != null && palletBarcode.isNotEmpty
        ? [urunId, locationId, palletBarcode]
        : [urunId, locationId];

    final List<Map<String, dynamic>> existingStock = await txn.query(
      'inventory_stock',
      where: 'urun_id = ? AND location_id = ? AND $palletClause',
      whereArgs: params,
    );

    if (existingStock.isNotEmpty) {
      final stock = existingStock.first;
      final currentQuantity = (stock['quantity'] as num).toDouble();
      final newQuantity = currentQuantity + quantityChange;

      if (newQuantity > 0.001) {
        await txn.update(
          'inventory_stock',
          {'quantity': newQuantity, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [stock['id']],
        );
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [stock['id']]);
      }
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId, 'location_id': locationId, 'quantity': quantityChange,
        'pallet_barcode': palletBarcode, 'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      debugPrint("UYARI: Kaynak lokasyonda ($locationId) bulunmayan bir stok (Ürün ID: $urunId, Palet: $palletBarcode) düşülmeye çalışıldı. İşlem atlandı.");
    }
  }

  Map<String, dynamic> _buildApiPayload(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) {
    return {
      "header": {
        "operation_type": header.operationType.apiName,
        "source_location_id": sourceLocationId,
        "target_location_id": targetLocationId,
        "transfer_date": header.transferDate.toIso8601String(),
        "employee_id": 1, // Placeholder
      },
      "items": items.map((item) => {
        "product_id": item.productId,
        "quantity": item.quantity,
        "pallet_id": item.sourcePalletBarcode,
      }).toList(),
    };
  }
}

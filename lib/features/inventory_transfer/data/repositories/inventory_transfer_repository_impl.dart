// ----- lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart (GÜNCELLENDİ) -----
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../goods_receiving/domain/repositories/goods_receiving_repository.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;
  final GoodsReceivingRepository goodsReceivingRepo;

  static const int malKabulLocationId = 1;

  InventoryTransferRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
    required this.goodsReceivingRepo,
  });

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, int status) async {
    await goodsReceivingRepo.updatePurchaseOrderStatus(orderId, status);
  }

  @override
  Future<MapEntry<String, int>?> findLocationByCode(String code) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'warehouses_shelfs',
      columns: ['id', 'name'],
      where: 'LOWER(code) = ? AND is_active = 1',
      whereArgs: [code.toLowerCase().trim()],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      final map = maps.first;
      return MapEntry(map['name'] as String, map['id'] as int);
    }
    return null;
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer() async {
    final db = await dbHelper.database;
    
    // Get the current user's warehouse_id from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final warehouseId = prefs.getInt('warehouse_id');
    
    if (warehouseId == null) {
      debugPrint("Warning: No warehouse_id found in preferences. Returning empty list.");
      return [];
    }
    
    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status = ? AND lokasyon_id = ?',
      whereArgs: [2, warehouseId],
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int orderId) async {
    final db = await dbHelper.database;
    final receiptItemsForOrder = await db.rawQuery('''
      SELECT DISTINCT gri.urun_id, gri.pallet_barcode
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.id = gri.receipt_id
      WHERE gr.siparis_id = ?
    ''', [orderId]);

    if (receiptItemsForOrder.isEmpty) return [];

    final stockInReceiptArea = await db.rawQuery('''
      SELECT s.urun_id, s.quantity, s.pallet_barcode, u.id, u.UrunAdi, u.StokKodu, u.Barcode1, u.aktif
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      WHERE s.location_id = ?
    ''', [malKabulLocationId]);

    final relevantStock = stockInReceiptArea.where((stock) {
      return receiptItemsForOrder.any((receiptItem) {
        bool isSameProduct = stock['urun_id'] == receiptItem['urun_id'];
        bool isSamePallet = stock['pallet_barcode'] == receiptItem['pallet_barcode'];
        return isSameProduct && isSamePallet;
      });
    }).toList();

    if (relevantStock.isEmpty) return [];

    final containers = <String, List<Map<String, dynamic>>>{};
    for (var stockItem in relevantStock) {
      final pallet = stockItem['pallet_barcode'] as String?;
      final key = pallet ?? 'PALETSIZ_${stockItem['urun_id']}';
      containers.putIfAbsent(key, () => []).add(stockItem);
    }

    final result = <TransferableContainer>[];
    for (var entry in containers.entries) {
      final firstItem = entry.value.first;
      final displayName = (firstItem['pallet_barcode'] as String?) != null
          ? "Palet: ${firstItem['pallet_barcode']}"
          : "Paletsiz: ${firstItem['UrunAdi']}";

      result.add(
        TransferableContainer(
          id: entry.key,
          displayName: displayName,
          items: entry.value.map((item) {
            return TransferableItem(
              product: ProductInfo.fromDbMap(item),
              quantity: (item['quantity'] as num).toDouble(),
              sourcePalletBarcode: item['pallet_barcode'] as String?,
            );
          }).toList(),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> recordTransferOperation(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) async {
    final apiPayload = _buildApiPayload(header, items, sourceLocationId, targetLocationId);
    await _saveForSync(apiPayload, header, items, sourceLocationId, targetLocationId);
  }

  Map<String, dynamic> _buildApiPayload(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) {
    return {
      "header": header.toApiJson(sourceLocationId, targetLocationId),
      "items": items.map((item) => item.toApiJson()).toList(),
    };
  }

  Future<void> _saveForSync(
      Map<String, dynamic> apiPayload,
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      ) async {
    final db = await dbHelper.database;
    try {
      await db.transaction((txn) async {
        for (final item in items) {
          String? sourcePallet;
          String? targetPallet;

          switch (header.operationType) {
            case AssignmentMode.pallet:
              // Tam palet transferi: Kaynak ve hedef palet aynıdır.
              sourcePallet = item.sourcePalletBarcode;
              targetPallet = item.sourcePalletBarcode;
              break;
            case AssignmentMode.boxFromPallet:
              // Palet bozma: Kaynaktan paletli stok düş, hedefe paletsiz ekle.
              sourcePallet = item.sourcePalletBarcode;
              targetPallet = null;
              break;
            case AssignmentMode.box:
              // Koli/kutu transferi: Kaynak ve hedefte palet yoktur.
              sourcePallet = null;
              targetPallet = null;
              break;
            default:
              throw Exception('Bilinmeyen veya desteklenmeyen transfer tipi: ${header.operationType}');
          }

          // Kaynak lokasyondan stok düşümü
          await _updateStock(txn, item.productId, sourceLocationId, -item.quantity, sourcePallet);
          // Hedef lokasyona stok eklemesi
          await _updateStock(txn, item.productId, targetLocationId, item.quantity, targetPallet);

          // Transfer hareketini kaydet
          await txn.insert('inventory_transfers', {
            'urun_id': item.productId,
            'from_location_id': sourceLocationId,
            'to_location_id': targetLocationId,
            'quantity': item.quantity,
            'from_pallet_barcode': sourcePallet,
            'pallet_barcode': targetPallet,
            'employee_id': header.employeeId,
            'transfer_date': header.transferDate.toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        final pendingOp = PendingOperation(
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode(apiPayload),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
      });
      debugPrint("Transfer işlemi başarıyla lokale kaydedildi.");
    } catch (e, s) {
      debugPrint("Lokal transfer kaydı hatası: $e\n$s");
      throw Exception("Lokal veritabanına transfer kaydedilirken hata oluştu: $e");
    }
  }

  Future<void> _updateStock(Transaction txn, int urunId, int locationId, double quantityChange, String? palletBarcode) async {
    final existingStock = await txn.query('inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND pallet_barcode ${palletBarcode == null ? 'IS NULL' : '= ?'}',
        whereArgs: palletBarcode == null ? [urunId, locationId] : [urunId, locationId, palletBarcode]
    );

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final currentQty = (currentStock['quantity'] as num);
      final newQty = currentQty + quantityChange;

      if (newQty > 0.001) {
        await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [currentStock['id']]);
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [currentStock['id']]);
      }
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': quantityChange,
        'pallet_barcode': palletBarcode,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      final errorMessage = "Kaynakta stok bulunamadı (Lokasyon: $locationId, Ürün: $urunId, Palet: ${palletBarcode ?? 'YOK'}). İşlem iptal edildi.";
      debugPrint(errorMessage);
      throw Exception(errorMessage);
    }
  }

  @override
  Future<Map<String, int>> getSourceLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1');
    return {for (var map in maps) map['name'] as String: map['id'] as int};
  }

  @override
  Future<Map<String, int>> getTargetLocations() async => getSourceLocations();

  @override
  Future<List<String>> getPalletIdsAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT DISTINCT s.pallet_barcode
      FROM inventory_stock s
      WHERE s.location_id = ? 
        AND s.pallet_barcode IS NOT NULL
        AND (
          -- Mal kabul lokasyonundaysa, sipariş durumu 3 olmalı
          s.location_id = 1 AND EXISTS (
            SELECT 1 FROM goods_receipt_items gri
            JOIN goods_receipts gr ON gr.id = gri.receipt_id
            JOIN satin_alma_siparis_fis sasf ON sasf.id = gr.siparis_id
            WHERE gri.urun_id = s.urun_id AND gri.pallet_barcode = s.pallet_barcode AND sasf.status = 3
          )
          -- Diğer lokasyonlardaysa, kısıtlama yok (şimdilik)
          OR s.location_id != 1
        )
    ''', [locationId]);
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT u.id as productId, u.UrunAdi as productName, u.StokKodu as productCode, u.Barcode1 as barcode1, SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      WHERE s.location_id = ? 
        AND s.pallet_barcode IS NULL
        AND (
          s.location_id = 1 AND EXISTS (
            SELECT 1 FROM goods_receipt_items gri
            JOIN goods_receipts gr ON gr.id = gri.receipt_id
            JOIN satin_alma_siparis_fis sasf ON sasf.id = gr.siparis_id
            WHERE gri.urun_id = s.urun_id AND sasf.status = 3
          )
          OR s.location_id != 1
        )
      GROUP BY u.id, u.UrunAdi, u.StokKodu, u.Barcode1
    ''', [locationId]);
    return maps.map((map) => BoxItem.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT u.id, u.UrunAdi as name, u.StokKodu as code, s.quantity as currentQuantity 
      FROM inventory_stock s 
      JOIN urunler u ON u.id = s.urun_id 
      WHERE s.pallet_barcode = ?
    ''', [palletId]);
    return maps.map((map) => ProductItem.fromMap(map)).toList();
  }

  @override
  Future<List<MapEntry<String, int>>> getAllLocations(int warehouseId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'warehouses_shelfs',
      columns: ['id', 'name'],
      where: 'is_active = 1 AND id != ? AND warehouse_id = ?',
      whereArgs: [malKabulLocationId, warehouseId],
      orderBy: 'name ASC',
    );

    if (maps.isEmpty) {
      return [];
    }

    return List.generate(maps.length, (i) {
      final id = maps[i]['id'] as int;
      final name = maps[i]['name'] as String;
      return MapEntry(name, id);
    });
  }
}
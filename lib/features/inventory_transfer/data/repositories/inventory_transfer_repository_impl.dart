// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
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
import 'package:sqflite/sqflite.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;
  final SyncService syncService;

  static const int malKabulLocationId = 1;

  InventoryTransferRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
    required this.syncService,
  });

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, int status) async {
    final db = await dbHelper.database;
    await db.update(
      'satin_alma_siparis_fis',
      {'status': status},
      where: 'id = ?',
      whereArgs: [orderId],
    );
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
    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status IN (?, ?)',
      whereArgs: [2, 4],
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int orderId) async {
    final db = await dbHelper.database;
    final stockInReceivingArea = await db.rawQuery('''
        SELECT s.urun_id, s.quantity, s.pallet_barcode, s.stock_status, u.UrunAdi, u.StokKodu, u.Barcode1, u.aktif, u.id
        FROM inventory_stock s
        JOIN urunler u ON u.id = s.urun_id
        WHERE s.location_id = ? AND s.stock_status = 'receiving'
    ''', [malKabulLocationId]);

    if (stockInReceivingArea.isEmpty) return [];

    final receiptItemsForOrder = await db.rawQuery('''
        SELECT DISTINCT gri.urun_id, gri.pallet_barcode
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.id = gri.receipt_id
        WHERE gr.siparis_id = ?
    ''', [orderId]);

    final relevantStock = stockInReceivingArea.where((stock) {
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
    
    final db = await dbHelper.database;
    try {
      await db.transaction((txn) async {
        final isPutawayOperation = sourceLocationId == malKabulLocationId && header.siparisId != null;

        for (final item in items) {
          // 1. Kaynak stoktan düşür.
          await _updateStock(
              txn, item.productId, sourceLocationId, -item.quantity, item.palletId,
              isPutawayOperation ? 'receiving' : 'available');

          // 2. Hedefteki palet durumunu belirle.
          final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;
          
          // 3. Hedef stoka doğru palet durumuyla ekle.
          await _updateStock(
              txn, item.productId, targetLocationId, item.quantity, targetPalletId,
              'available');

          // 4. Transfer işlemini logla.
          await txn.insert('inventory_transfers', {
            'urun_id': item.productId,
            'from_location_id': sourceLocationId,
            'to_location_id': targetLocationId,
            'quantity': item.quantity,
            'from_pallet_barcode': item.palletId,
            'pallet_barcode': targetPalletId,
            'employee_id': header.employeeId,
            'transfer_date': header.transferDate.toIso8601String(),
          });

          // 5. EĞER BU BİR RAFA KALDIRMA İŞLEMİ İSE, wms_putaway_status'u GÜNCELLE
          if (isPutawayOperation) {
            final orderLine = await txn.query(
              'satin_alma_siparis_fis_satir',
              columns: ['id'],
              where: 'siparis_id = ? AND urun_id = ?',
              whereArgs: [header.siparisId, item.productId],
              limit: 1,
            );
            if (orderLine.isNotEmpty) {
              final lineId = orderLine.first['id'] as int;
              
              final existingPutaway = await txn.query(
                'wms_putaway_status',
                where: 'satin_alma_siparis_fis_satir_id = ?',
                whereArgs: [lineId],
                limit: 1,
              );

              if (existingPutaway.isNotEmpty) {
                final currentPutawayQty = existingPutaway.first['putaway_quantity'] as num;
                await txn.update(
                  'wms_putaway_status',
                  {
                    'putaway_quantity': currentPutawayQty + item.quantity,
                    'updated_at': DateTime.now().toIso8601String(),
                  },
                  where: 'satin_alma_siparis_fis_satir_id = ?',
                  whereArgs: [lineId],
                );
              } else {
                await txn.insert('wms_putaway_status', {
                  'satin_alma_siparis_fis_satir_id': lineId,
                  'putaway_quantity': item.quantity,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                });
              }
            }
          }
        }

        // 6. İşlemi senkronizasyon için kuyruğa ekle (zenginleştirilmiş veri ile).
        final enrichedData = await _createEnrichedTransferData(txn, apiPayload, items);
        final pendingOp = PendingOperation(
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode(enrichedData),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());
      });
      
      // İnternet varsa anında sync başlat
      if (await networkInfo.isConnected) {
        debugPrint("Transfer kaydedildi, anında sync başlatılıyor...");
        syncService.uploadPendingOperations();
      }
    } catch (e, s) {
      debugPrint("Lokal transfer kaydı hatası: $e\n$s");
      throw Exception("Lokal veritabanına transfer kaydedilirken hata oluştu: $e");
    }
  }

  Future<Map<String, dynamic>> _createEnrichedTransferData(
    Transaction txn,
    Map<String, dynamic> apiPayload,
    List<TransferItemDetail> items,
  ) async {
    final header = apiPayload['header'] as Map<String, dynamic>;
    final sourceLocationId = header['source_location_id'];
    final targetLocationId = header['target_location_id'];

    if (sourceLocationId != null) {
      final sourceResult = await txn.query('warehouses_shelfs', columns: ['name'], where: 'id = ?', whereArgs: [sourceLocationId]);
      if (sourceResult.isNotEmpty) apiPayload['header']['source_location_name'] = sourceResult.first['name'];
    }
    if (targetLocationId != null) {
      final targetResult = await txn.query('warehouses_shelfs', columns: ['name'], where: 'id = ?', whereArgs: [targetLocationId]);
      if (targetResult.isNotEmpty) apiPayload['header']['target_location_name'] = targetResult.first['name'];
    }

    final enrichedItems = <Map<String, dynamic>>[];
    for (int i = 0; i < items.length; i++) {
      final itemDetail = items[i];
      final itemPayload = (apiPayload['items'] as List)[i] as Map<String, dynamic>;
      final productResult = await txn.query(
        'urunler',
        columns: ['UrunAdi', 'StokKodu'],
        where: 'id = ?',
        whereArgs: [itemDetail.productId],
        limit: 1,
      );
      if (productResult.isNotEmpty) {
        itemPayload['product_name'] = productResult.first['UrunAdi'];
        itemPayload['product_code'] = productResult.first['StokKodu'];
      }
      enrichedItems.add(itemPayload);
    }
    apiPayload['items'] = enrichedItems;

    return apiPayload;
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
  
  Future<void> _updateStock(Transaction txn, int urunId, int locationId,
      double quantityChange, String? palletBarcode, String stockStatus) async {
    String palletWhereClause = palletBarcode == null ? 'pallet_barcode IS NULL' : 'pallet_barcode = ?';
    List<dynamic> whereArgs = [urunId, locationId, stockStatus];
    if (palletBarcode != null) {
      whereArgs.add(palletBarcode);
    }

    final existingStock = await txn.query('inventory_stock',
        where: 'urun_id = ? AND location_id = ? AND stock_status = ? AND $palletWhereClause',
        whereArgs: whereArgs);

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final newQty = (currentStock['quantity'] as num) + quantityChange;
      if (newQty > 0.001) {
        await txn.update('inventory_stock', {'quantity': newQty},
            where: 'id = ?', whereArgs: [currentStock['id']]);
      } else {
        await txn.delete('inventory_stock',
            where: 'id = ?', whereArgs: [currentStock['id']]);
      }
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': quantityChange,
        'pallet_barcode': palletBarcode,
        'stock_status': stockStatus
      });
    } else {
      final errorMessage = "Kaynakta stok bulunamadı veya düşülecek miktar yetersiz (Lokasyon: $locationId, Ürün: $urunId, Statü: $stockStatus).";
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
  Future<Map<String, int>> getTargetLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1 AND id != ?', whereArgs: [malKabulLocationId]);
    return {for (var map in maps) map['name'] as String: map['id'] as int};
  }

  @override
  Future<List<String>> getPalletIdsAtLocation(int locationId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT DISTINCT pallet_barcode FROM inventory_stock
      WHERE location_id = ? AND pallet_barcode IS NOT NULL AND stock_status = 'available'
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
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL AND s.stock_status = 'available'
      GROUP BY u.id, u.UrunAdi, u.StokKodu, u.Barcode1
    ''', [locationId]);
    return maps.map((map) => BoxItem.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletId, int locationId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        u.id,
        u.StokKodu as code,
        u.UrunAdi as name,
        s.quantity as currentQuantity,
        s.pallet_barcode as pallet_barcode,
        u.Barcode1 as barcode1
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.id
      WHERE s.pallet_barcode = ? AND s.location_id = ? AND s.stock_status = 'available'
    ''', [palletId, locationId]);

    return List.generate(maps.length, (i) {
      return ProductItem.fromMap(maps[i]);
    });
  }

  @override
  Future<List<MapEntry<String, int>>> getAllLocations(int warehouseId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'warehouses_shelfs',
      columns: ['id', 'name'],
      where: 'is_active = 1 AND warehouse_id = ?',
      whereArgs: [warehouseId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => MapEntry(map['name'] as String, map['id'] as int)).toList();
  }

  @override
  Future<List<TransferOperationHeader>> getPendingTransfers() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pending_operation',
      where: 'type = ?',
      whereArgs: [PendingOperationType.inventoryTransfer.name],
      orderBy: 'created_at DESC',
    );

    final List<TransferOperationHeader> headers = [];
    for (var map in maps) {
      final data = jsonDecode(map['data'] as String);
      final headerMap = data['header'] as Map<String, dynamic>?;

      if (headerMap != null) {
        final operationTypeString = headerMap['operationType'] as String?;
        final mode = AssignmentMode.values.firstWhere(
              (e) => e.name == operationTypeString,
          orElse: () => AssignmentMode.box,
        );

        headers.add(
          TransferOperationHeader(
            employeeId: headerMap['employee_id'] as int,
            operationType: mode,
            sourceLocationName: headerMap['source_location_name'] as String,
            targetLocationName: headerMap['target_location_name'] as String,
            containerId: headerMap['container_id'] as String?,
            transferDate: DateTime.parse(headerMap['transfer_date'] as String),
          ),
        );
      }
    }
    return headers;
  }
}
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
import 'package:shared_preferences/shared_preferences.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;
  final SyncService syncService;

  InventoryTransferRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
    required this.syncService,
  });

  @override
  Future<MapEntry<String, int>?> findLocationByCode(String code) async {
    final db = await dbHelper.database;
    final cleanCode = code.toLowerCase().trim();
    
    // Check for "Mal Kabul Alanı" keywords
    if (cleanCode.contains('kabul') || cleanCode.contains('receiving') || cleanCode == '0') {
      return const MapEntry('Mal Kabul Alanı', 0);
    }
    
    final maps = await db.query(
      'warehouses_shelfs',
      columns: ['id', 'name'],
      where: 'is_active = 1 AND (LOWER(name) = ? OR LOWER(code) = ?)',
      whereArgs: [cleanCode, cleanCode],
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      return MapEntry(maps.first['name'] as String, maps.first['id'] as int);
    }
    return null;
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer() async {
    final db = await dbHelper.database;
    final prefs = await SharedPreferences.getInstance();
    final warehouseId = prefs.getInt('warehouse_id');
    
    // ANA DÜZELTME: Rafa kaldırılmayı bekleyen ürünleri olan siparişleri getir.
    // Durum 2 (İşlemde) olmalı ve `inventory_stock`'ta 'receiving' durumunda en az bir kaydı olmalı.
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT T1.*
      FROM satin_alma_siparis_fis AS T1
      INNER JOIN inventory_stock AS T2 ON T1.id = T2.siparis_id
      WHERE T2.stock_status = 'receiving' AND T1.status = 2 AND T1.branch_id = ?
      ORDER BY T1.tarih DESC
    ''', [warehouseId]);
    debugPrint("Transfer için açık siparişler (Depo ID: $warehouseId): ${maps.length} adet bulundu");
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int? locationId, {int? orderId}) async {
    final db = await dbHelper.database;
    String whereClause;
    List<Object?> whereArgs;

    // ANA GÜNCELLEME: `orderId` varlığına göre sorgu mantığı değişiyor.
    if (orderId != null) {
      // Siparişe bağlı yerleştirme (PUTAWAY): `location_id` NULL olan, `receiving` statüsündeki ve o siparişe ait stokları getir.
      whereClause = 's.location_id IS NULL AND s.stock_status = ? AND s.siparis_id = ?';
      whereArgs = ['receiving', orderId];
    } else {
      // Serbest Transfer: Belirli bir lokasyondaki 'available' statüsündeki stokları getir.
      if (locationId == null) return []; // Serbest transfer için lokasyon zorunlu
      whereClause = 's.location_id = ? AND s.stock_status = ?';
      whereArgs = [locationId, 'available'];
    }

    String rawQuerySql = '''
      SELECT 
        s.urun_id, s.location_id, s.siparis_id, s.quantity, s.pallet_barcode, s.stock_status, s.updated_at,
        u.UrunAdi, u.StokKodu, u.Barcode1, u.aktif, u.id as UrunId
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.id
      WHERE $whereClause
    ''';
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(rawQuerySql, whereArgs);

    if (maps.isEmpty) return [];

    final containers = <String, List<Map<String, dynamic>>>{};
    for (var stockItem in maps) {
      final pallet = stockItem['pallet_barcode'] as String?;
      // Paletsiz ürünler, ürün ID'sine göre gruplanır.
      final key = pallet ?? 'PALETSIZ_${stockItem['urun_id']}';
      containers.putIfAbsent(key, () => []).add(stockItem);
    }

    final result = <TransferableContainer>[];
    for (var entry in containers.entries) {
      final firstItem = entry.value.first;
      final isPallet = (firstItem['pallet_barcode'] as String?) != null;
      final displayName = isPallet
          ? "Palet: ${firstItem['pallet_barcode']}"
          : "${firstItem['UrunAdi']}";

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
      int? sourceLocationId,
      int targetLocationId,
      ) async {
    
    final db = await dbHelper.database;
    try {
      await db.transaction((txn) async {
        for (final item in items) {
          // 1. Kaynak stoktan düşür (sourceLocationId null olabilir - mal kabul alanı).
          await _updateStock(
            txn, item.productId, sourceLocationId, -item.quantity, item.palletId,
            item.stockStatus, item.siparisId);

          // 2. Hedefteki palet durumunu belirle.
          final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;
          
          // 3. Hedef stoka doğru palet durumuyla ekle. Hedefe giden tüm ürünler 'available' ve siparişsiz olur.
          await _updateStock(
              txn, item.productId, targetLocationId, item.quantity, targetPalletId,
              'available', null);

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
          if ((item.stockStatus == 'receiving' || sourceLocationId == null) && item.siparisId != null) {
            final orderLine = await txn.query(
              'satin_alma_siparis_fis_satir',
              columns: ['id'],
              where: 'siparis_id = ? AND urun_id = ?',
              whereArgs: [item.siparisId, item.productId],
              limit: 1,
            );
            if (orderLine.isNotEmpty) {
              final lineId = orderLine.first['id'] as int;
              
              await txn.rawInsert('''
                INSERT INTO wms_putaway_status (satinalmasiparisfissatir_id, putaway_quantity, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(satinalmasiparisfissatir_id) DO UPDATE SET
                putaway_quantity = putaway_quantity + excluded.putaway_quantity,
                updated_at = excluded.updated_at
              ''', [lineId, item.quantity, DateTime.now().toIso8601String(), DateTime.now().toIso8601String()]);
            }
          }
        }

        // 6. İşlemi senkronizasyon için kuyruğa ekle.
        final apiPayload = _buildApiPayload(header, items, sourceLocationId, targetLocationId);
        final enrichedData = await _createEnrichedTransferData(txn, apiPayload, items);
        final pendingOp = PendingOperation.create(
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode(enrichedData),
          createdAt: DateTime.now(),
        );
        await txn.insert('pending_operation', pendingOp.toDbMap());

        debugPrint("Lokal transfer işlemi kuyruğa eklendi.");
      });
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
    } else {
      // NULL location_id means "Goods Receiving Area"
      apiPayload['header']['source_location_name'] = 'Mal Kabul Alanı';
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
      int? sourceLocationId,
      int targetLocationId,
      ) {
    return {
      "header": header.toApiJson(sourceLocationId, targetLocationId),
      "items": items.map((item) => item.toApiJson()).toList(),
    };
  }
  
  Future<void> _updateStock(Transaction txn, int urunId, int? locationId,
      double quantityChange, String? palletBarcode, String stockStatus, int? siparisId) async {
          
      // Bu fonksiyon hem mal kabul hem de transferde kullanıldığı için
      // daha sağlam hale getiriliyor.
      var whereClause = 'urun_id = ? AND stock_status = ?';
      var whereArgs = <dynamic>[urunId, stockStatus];

      if (locationId == null) {
          whereClause += ' AND location_id IS NULL';
      } else {
          whereClause += ' AND location_id = ?';
          whereArgs.add(locationId);
      }

      if (palletBarcode == null) {
          whereClause += ' AND pallet_barcode IS NULL';
      } else {
          whereClause += ' AND pallet_barcode = ?';
          whereArgs.add(palletBarcode);
      }

      if (siparisId == null) {
          whereClause += ' AND siparis_id IS NULL';
      } else {
          whereClause += ' AND siparis_id = ?';
          whereArgs.add(siparisId);
      }

      final existingStock = await txn.query('inventory_stock',
          where: whereClause,
          whereArgs: whereArgs);

      if (existingStock.isNotEmpty) {
          final currentStock = existingStock.first;
          final newQty = (currentStock['quantity'] as num) + quantityChange;
          if (newQty > 0.001) { // Kayan nokta hatalarına karşı tolerans
              await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
                  where: 'id = ?', whereArgs: [currentStock['id']]);
          } else {
              await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [currentStock['id']]);
          }
      } else if (quantityChange > 0) {
          await txn.insert('inventory_stock', {
              'urun_id': urunId, 'location_id': locationId, 'quantity': quantityChange,
              'pallet_barcode': palletBarcode, 'updated_at': DateTime.now().toIso8601String(),
              'stock_status': stockStatus,
              'siparis_id': siparisId
          });
      } else {
          // Hatanın kaynağını daha net göstermek için log mesajını zenginleştirelim.
          final errorMessage = "Kaynakta stok bulunamadı veya düşülecek miktar yetersiz. Aranan: {urun_id: $urunId, location_id: $locationId, status: $stockStatus, pallet: $palletBarcode, siparis_id: $siparisId}";
          debugPrint(errorMessage);
          throw Exception(errorMessage);
      }
  }

  @override
  Future<Map<String, int>> getSourceLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1');
    // Add the virtual "Goods Receiving Area" with ID 0 to represent NULL location_id
    final result = <String, int>{'Mal Kabul Alanı': 0};
    for (var map in maps) {
      result[map['name'] as String] = map['id'] as int;
    }
    return result;
  }

  @override
  Future<Map<String, int>> getTargetLocations() async {
    final db = await dbHelper.database;
    // Return all active locations as potential targets
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1');
    return {for (var map in maps) map['name'] as String: map['id'] as int};
  }

  // Helper methods for the existing screen interface
  @override
  Future<List<String>> getPalletIdsAtLocation(int? locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereClauses.add('location_id IS NULL');
    } else {
      whereClauses.add('location_id = ?');
      whereArgs.add(locationId);
    }
    
    final placeholders = List.filled(stockStatuses.length, '?').join(',');
    whereClauses.add('stock_status IN ($placeholders)');
    whereArgs.addAll(stockStatuses);
    whereClauses.add('pallet_barcode IS NOT NULL');

    final results = await db.query(
      'inventory_stock',
      distinct: true,
      columns: ['pallet_barcode'],
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
    );

    return results.map((row) => row['pallet_barcode'] as String).toList();
  }

  Future<List<BoxItem>> getBoxesAtLocation(int? locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;

    final placeholders = List.filled(stockStatuses.length, '?').join(',');

    String whereClause;
    List<dynamic> whereArgs;
    
    if (locationId == null || locationId == 0) {
      // NULL location_id represents the goods receiving area
      whereClause = 's.location_id IS NULL AND s.pallet_barcode IS NULL AND s.stock_status IN ($placeholders)';
      whereArgs = stockStatuses;
    } else {
      whereClause = 's.location_id = ? AND s.pallet_barcode IS NULL AND s.stock_status IN ($placeholders)';
      whereArgs = [locationId, ...stockStatuses];
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.urun_id, s.quantity, u.UrunAdi, u.StokKodu, u.Barcode1, s.stock_status, s.siparis_id
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      WHERE $whereClause
    ''', whereArgs);
    return maps.map((map) => BoxItem.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletBarcode, int? locationId, {String stockStatus = 'available', int? siparisId}) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[
      's.pallet_barcode = ?',
      's.stock_status = ?'
    ];
    final whereArgs = <dynamic>[palletBarcode, stockStatus];

    if (locationId == null) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }
    
    // Sipariş ID'si verilmişse, sorguya ekle
    if (siparisId != null) {
        whereClauses.add('s.siparis_id = ?');
        whereArgs.add(siparisId);
    }

    final query = '''
      SELECT 
        s.urun_id as id,
        u.UrunAdi as name,
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        s.quantity as currentQuantity,
        s.siparis_id as siparisId,
        s.stock_status as stockStatus
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      WHERE ${whereClauses.join(' AND ')}
    ''';
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => ProductItem.fromMap(map)).toList();
  }

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

  @override
  Future<void> checkAndCompletePutaway(int orderId) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      // 1. Siparişteki tüm satırların toplam istenen miktarını al
      final orderLines = await txn.query(
        'satin_alma_siparis_fis_satir',
        columns: ['id', 'miktar'],
        where: 'siparis_id = ?',
        whereArgs: [orderId],
      );

      if (orderLines.isEmpty) return;

      double totalOrdered = orderLines.fold(0.0, (sum, row) => sum + (row['miktar'] as num));

      // 2. Bu sipariş için rafa yerleştirilmiş toplam miktarı al
      final lineIds = orderLines.map((row) => row['id'] as int).toList();
      final placeholders = List.generate(lineIds.length, (_) => '?').join(',');
      final putawayResult = await txn.rawQuery('''
        SELECT SUM(putaway_quantity) as total_putaway
        FROM wms_putaway_status
        WHERE satinalmasiparisfissatir_id IN ($placeholders)
      ''', lineIds);
      
      double totalPutaway = 0;
      if (putawayResult.isNotEmpty && putawayResult.first['total_putaway'] != null) {
        totalPutaway = (putawayResult.first['total_putaway'] as num).toDouble();
      }

      // 3. Karşılaştır ve gerekirse durumu 4 (Tamamlandı) yap.
      if (totalPutaway >= totalOrdered - 0.001) { // Tolerans payı
        await txn.update(
          'satin_alma_siparis_fis',
          {'status': 4}, // 4: Otomatik Tamamlandı
          where: 'id = ?',
          whereArgs: [orderId],
        );
        debugPrint("Sipariş #$orderId rafa yerleştirme işlemi tamamlandı ve durumu 4 (Otomatik Tamamlandı) olarak güncellendi.");
      }
    });
  }

  @override
  Future<List<ProductInfo>> getProductInfoByBarcode(String barcode) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'urunler',
      where: 'aktif = 1 AND (Barcode1 = ? OR StokKodu = ?)',
      whereArgs: [barcode, barcode],
    );
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<BoxItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;
    final cleanCode = productCodeOrBarcode.toLowerCase().trim();
    
    final placeholders = List.filled(stockStatuses.length, '?').join(',');
    
    String whereClause;
    List<dynamic> args;
    
    if (locationId == 0) {
      // NULL location_id represents the goods receiving area
      whereClause = 's.location_id IS NULL AND s.pallet_barcode IS NULL AND s.stock_status IN ($placeholders) AND (LOWER(u.StokKodu) = ? OR LOWER(u.Barcode1) = ?)';
      args = [...stockStatuses, cleanCode, cleanCode];
    } else {
      whereClause = 's.location_id = ? AND s.pallet_barcode IS NULL AND s.stock_status IN ($placeholders) AND (LOWER(u.StokKodu) = ? OR LOWER(u.Barcode1) = ?)';
      args = [locationId, ...stockStatuses, cleanCode, cleanCode];
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.urun_id, s.quantity, u.UrunAdi, u.StokKodu, u.Barcode1, s.stock_status, s.siparis_id
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      WHERE $whereClause
      LIMIT 1
    ''', args);

    if (maps.isNotEmpty) {
      return BoxItem.fromDbMap(maps.first);
    }
    return null;
  }

}
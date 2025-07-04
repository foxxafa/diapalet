// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
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
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;

  InventoryTransferRepositoryImpl({required this.dbHelper, required this.dio});

  @override
  Future<Map<String, int>> getSourceLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1');
    final result = <String, int>{'000': 0}; // "Mal Kabul Alanı"
    for (var map in maps) {
      result[map['name'] as String] = map['id'] as int;
    }
    return result;
  }

  @override
  Future<Map<String, int>> getTargetLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('warehouses_shelfs', where: 'is_active = 1');
    final result = <String, int>{};
    for (var map in maps) {
      result[map['name'] as String] = map['id'] as int;
    }
    return result;
  }

  @override
  Future<List<String>> getPalletIdsAtLocation(int? locationId,
      {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null || locationId == 0) {
      whereClauses.add('location_id IS NULL');
    } else {
      whereClauses.add('location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereClauses.add('stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    final maps = await db.query(
      'inventory_stock',
      distinct: true,
      columns: ['pallet_barcode'],
      where: 'pallet_barcode IS NOT NULL AND ${whereClauses.join(' AND ')}',
      whereArgs: whereArgs,
    );
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int? locationId,
      {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null || locationId == 0) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereClauses.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    final query = '''
      SELECT 
        u.id as productId, 
        u.UrunAdi as productName, 
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.id
      WHERE ${whereClauses.join(' AND ')} AND s.pallet_barcode IS NULL
      GROUP BY u.id, u.UrunAdi, u.StokKodu, u.Barcode1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => BoxItem.fromJson(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletBarcode, int? locationId, {String stockStatus = 'available', int? siparisId}) async {
    final db = await dbHelper.database;
    
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];
    
    // Palet kodu ile filtrele
    whereParts.add('s.pallet_barcode = ?');
    whereArgs.add(palletBarcode);
    
    // Lokasyon ile filtrele
    if (locationId == null || locationId == 0) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }
    
    // Stok durumu ile filtrele
    whereParts.add('s.stock_status = ?');
    whereArgs.add(stockStatus);
    
    // Sipariş ID ile filtrele (eğer verilmişse)
    if (siparisId != null) {
      whereParts.add('s.siparis_id = ?');
      whereArgs.add(siparisId);
    }

    final query = '''
      SELECT 
        u.id as productId,
        u.UrunAdi as productName, 
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        s.quantity as currentQuantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.id
      WHERE ${whereParts.join(' AND ')}
      ORDER BY u.UrunAdi
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    debugPrint("Palet '$palletBarcode' içinde ${maps.length} ürün bulundu");
    
    final result = maps.map((map) => ProductItem(
      id: map['productId'] as int,
      name: map['productName'] as String,
      productCode: map['productCode'] as String,
      barcode1: map['barcode1'] as String?,
      currentQuantity: (map['currentQuantity'] as num).toDouble(),
    )).toList();
    
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
        final String opId = const Uuid().v4();
        final List<Map<String, dynamic>> itemsForJson = [];

        for (final item in items) {
          // 1. Kaynak stoktan düşür
          await _updateStock(
            txn,
            item.productId,
            sourceLocationId,
            -item.quantity,
            item.palletId,
            (sourceLocationId == null && header.siparisId != null) ? 'receiving' : 'available',
            (sourceLocationId == null && header.siparisId != null) ? header.siparisId : null,
          );

          // 2. Hedefteki palet durumunu belirle
          final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;

          // 3. Hedefe ekle
          await _updateStock(
            txn,
            item.productId,
            targetLocationId,
            item.quantity,
            targetPalletId,
            'available',
            null,
          );

          // 4. Transfer işlemini logla
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
          
          // 5. Rafa kaldırma ise wms_putaway_status'u güncelle
          if (sourceLocationId == null && header.siparisId != null) {
            final orderLine = await txn.query(
              'satin_alma_siparis_fis_satir',
              columns: ['id'],
              where: 'siparis_id = ? AND urun_id = ?',
              whereArgs: [header.siparisId, item.productId],
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

          itemsForJson.add(item.toApiJson());
        }

        final pendingOp = PendingOperation(
          uniqueId: opId,
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode({
            'header': header.toApiJson(sourceLocationId ?? 0, targetLocationId),
            'items': itemsForJson,
          }),
          createdAt: DateTime.now(),
        );

        await txn.insert('pending_operation', pendingOp.toDbMap());

        if (header.siparisId != null) {
          await checkAndCompletePutaway(header.siparisId!, txn: txn);
        }
      });
    } catch (e) {
      debugPrint('Lokal transfer kaydı hatası: $e');
      throw Exception('Lokal veritabanına transfer kaydedilirken hata oluştu: $e');
    }
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer() async {
    final db = await dbHelper.database;
    final maps = await db.query('satin_alma_siparis_fis', where: 'status = ?', whereArgs: [2]); // Kısmi Kabul
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int? locationId, {int? orderId}) async {
    final db = await dbHelper.database;
    final isPutaway = orderId != null;

    debugPrint("=== getTransferableContainers ===");
    debugPrint("locationId: $locationId, orderId: $orderId, isPutaway: $isPutaway");

    final List<Map<String, dynamic>> stockMaps;

    if (isPutaway) {
      // Siparişli yerleştirme: Mal kabul alanındaki (location_id IS NULL) ilgili siparişin stoğunu al
      stockMaps = await db.query('inventory_stock', where: 'siparis_id = ? AND stock_status = ?', whereArgs: [orderId, 'receiving']);
      debugPrint("Stok kayıtları (sipariş $orderId): ${stockMaps.length}");
    } else {
      // Serbest Transfer
      if (locationId == null || locationId == 0) {
        // Mal kabul alanından serbest transfer: Hem 'receiving' hem 'available' stokları al
        stockMaps = await db.query('inventory_stock', where: 'location_id IS NULL AND (stock_status = ? OR stock_status = ?)', whereArgs: ['receiving', 'available']);
        debugPrint("Stok kayıtları (mal kabul alanı): ${stockMaps.length}");
      } else {
        // Belirli bir raftan serbest transfer: Sadece 'available' stokları al
        stockMaps = await db.query('inventory_stock', where: 'location_id = ? AND stock_status = ?', whereArgs: [locationId, 'available']);
        debugPrint("Stok kayıtları (raf $locationId): ${stockMaps.length}");
      }
    }

    if (stockMaps.isEmpty) {
      debugPrint("Hiç stok bulunamadı");
      return [];
    }

    final productIds = stockMaps.map((e) => e['urun_id'] as int).toSet();
    final productsQuery = await db.query('urunler', where: 'id IN (${productIds.map((_) => '?').join(',')})', whereArgs: productIds.toList());
    final productDetails = {for (var p in productsQuery) p['id'] as int: ProductInfo.fromDbMap(p)};
    
    final Map<String, List<TransferableItem>> groupedByContainer = {};

    for (final stock in stockMaps) {
      final productId = stock['urun_id'] as int;
      final productInfo = productDetails[productId];
      if (productInfo == null) {
        debugPrint("UYARI: productId $productId için ürün bilgisi bulunamadı!");
        continue;
      }

      final pallet = stock['pallet_barcode'] as String?;
      final containerId = pallet ?? 'PALETSIZ_$productId';

      groupedByContainer.putIfAbsent(containerId, () => []);
      groupedByContainer[containerId]!.add(TransferableItem(
        product: productInfo,
        quantity: (stock['quantity'] as num).toDouble(),
        sourcePalletBarcode: pallet,
      ));
    }

    final result = groupedByContainer.entries.map((entry) {
      final id = entry.key;
      final items = entry.value;
      final displayName = id.startsWith('PALETSIZ_')
          ? items.first.product.name // Paletsiz ise ürün adını göster
          : 'Palet: $id';
      return TransferableContainer(id: id, displayName: displayName, items: items);
    }).toList();

    debugPrint("Sonuç konteyner sayısı: ${result.length}");
    
    return result;
  }

  @override
  Future<MapEntry<String, int>?> findLocationByCode(String code) async {
    final db = await dbHelper.database;
    final cleanCode = code.toLowerCase().trim();
    
    if (cleanCode.contains('kabul') || cleanCode.contains('receiving') || cleanCode == '0' || cleanCode == '000') {
      return const MapEntry('000', 0);
    }
    
    final maps = await db.query(
      'warehouses_shelfs',
      where: 'LOWER(code) = ? AND is_active = 1',
      whereArgs: [cleanCode],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return MapEntry(maps.first['name'] as String, maps.first['id'] as int);
    }
    return null;
  }

  @override
  Future<void> checkAndCompletePutaway(int orderId, {Transaction? txn}) async {
    final db = txn ?? await dbHelper.database;
    
    final orderLinesQuery = await db.query(
      'satin_alma_siparis_fis_satir',
      columns: ['id', 'miktar'],
      where: 'siparis_id = ?',
      whereArgs: [orderId],
    );

    if (orderLinesQuery.isEmpty) return;

    final putawayStatusQuery = await db.query(
      'wms_putaway_status',
      columns: ['satinalmasiparisfissatir_id', 'putaway_quantity'],
      where: 'satinalmasiparisfissatir_id IN (${orderLinesQuery.map((e) => e['id']).join(',')})'
    );
    final putawayMap = {for (var e in putawayStatusQuery) e['satinalmasiparisfissatir_id']: (e['putaway_quantity'] as num).toDouble()};

    bool allCompleted = true;
    for (final line in orderLinesQuery) {
      final ordered = (line['miktar'] as num).toDouble();
      final putaway = putawayMap[line['id']] ?? 0.0;
      if (putaway < ordered - 0.001) {
        allCompleted = false;
        break;
      }
    }

    if (allCompleted) {
      await db.update('satin_alma_siparis_fis', {'status': 4}, where: 'id = ?', whereArgs: [orderId]);
    }
  }

  @override
  Future<List<ProductInfo>> getProductInfoByBarcode(String barcode) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'urunler',
      where: 'Barcode1 = ? AND aktif = 1',
      whereArgs: [barcode],
    );
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<BoxItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;
    
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];
    
    // Lokasyon filtresi
    if (locationId == 0) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }
    
    // Stok durumu filtresi
    if (stockStatuses.isNotEmpty) {
      whereParts.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }
    
    // Ürün kodu veya barkod filtresi
    whereParts.add('(u.StokKodu = ? OR u.Barcode1 = ?)');
    whereArgs.add(productCodeOrBarcode);
    whereArgs.add(productCodeOrBarcode);
    
    // Paletsiz ürünler
    whereParts.add('s.pallet_barcode IS NULL');

    final query = '''
      SELECT 
        u.id as productId, 
        u.UrunAdi as productName, 
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.id
      WHERE ${whereParts.join(' AND ')}
      GROUP BY u.id, u.UrunAdi, u.StokKodu, u.Barcode1
      LIMIT 1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    if (maps.isNotEmpty) {
      return BoxItem.fromJson(maps.first);
    }
    return null;
  }

  Future<void> _updateStock(
    DatabaseExecutor txn,
    int productId,
    int? locationId,
    double quantityChange,
    String? palletId,
    String status,
    int? siparisId,
  ) async {
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    whereParts.add('urun_id = ?');
    whereArgs.add(productId);

    if (palletId == null) {
      whereParts.add('pallet_barcode IS NULL');
    } else {
      whereParts.add('pallet_barcode = ?');
      whereArgs.add(palletId);
    }

    if (locationId == null) {
      whereParts.add('location_id IS NULL');
    } else {
      whereParts.add('location_id = ?');
      whereArgs.add(locationId);
    }

    whereParts.add('stock_status = ?');
    whereArgs.add(status);

    if (siparisId == null) {
      whereParts.add('siparis_id IS NULL');
    } else {
      whereParts.add('siparis_id = ?');
      whereArgs.add(siparisId);
    }

    final existing = await txn.query(
      'inventory_stock',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final currentQty = (existing.first['quantity'] as num).toDouble();
      final newQty = currentQty + quantityChange;
      
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
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': productId,
        'location_id': locationId,
        'quantity': quantityChange,
        'pallet_barcode': palletId,
        'stock_status': status,
        'siparis_id': siparisId,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      debugPrint("ERROR: Kaynakta stok bulunamadı - urun_id: $productId, location_id: $locationId, status: $status, pallet: $palletId, siparis_id: $siparisId");
      throw Exception('Kaynakta stok bulunamadı veya düşülecek miktar yetersiz. Aranan: {urun_id: $productId, location_id: $locationId, status: $status, pallet: $palletId, siparis_id: $siparisId}');
    }
  }
}
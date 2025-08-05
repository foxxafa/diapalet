// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_stock_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;

  InventoryTransferRepositoryImpl({required this.dbHelper, required this.dio});

  @override
  Future<Map<String, int?>> getSourceLocations({bool includeReceivingArea = true}) async {
    final db = await dbHelper.database;

    // Sadece stokta ürün bulunan lokasyonları getir
    const query = '''
      SELECT DISTINCT s.id, s.name
      FROM shelfs s
      INNER JOIN inventory_stock i ON s.id = i.location_id
      WHERE s.is_active = 1 AND i.stock_status = 'available' AND i.quantity > 0
      ORDER BY s.name
    ''';

    final maps = await db.rawQuery(query);
    final result = <String, int?>{};

    if (includeReceivingArea) {
      // Mal kabul alanında stok var mı kontrol et
      final receivingStockQuery = await db.query(
        'inventory_stock',
        where: 'location_id IS NULL AND stock_status = ? AND quantity > 0',
        whereArgs: ['receiving']
      );
      if (receivingStockQuery.isNotEmpty) {
        result['000'] = null; // Artık direkt null kullanıyoruz
      }
    }

    for (var map in maps) {
      result[map['name'] as String] = map['id'] as int;
    }
    return result;
  }

  @override
  Future<Map<String, int?>> getTargetLocations({bool excludeReceivingArea = false}) async {
    final db = await dbHelper.database;
    final maps = await db.query('shelfs', where: 'is_active = 1');
    final result = <String, int?>{};

    if (!excludeReceivingArea) {
      result['000'] = null; // Goods receiving area - artık direkt null
    }

    for (var map in maps) {
      result[map['name'] as String] = map['id'] as int;
    }
    return result;
  }

  @override
  Future<List<String>> getPalletIdsAtLocation(
    int? locationId, {
    List<String> stockStatuses = const ['available'],
    String? deliveryNoteNumber,
  }) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereClauses.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    // DÜZELTME: Eğer deliveryNoteNumber varsa, goods_receipts tablosuyla INNER JOIN yapmak daha güvenilirdir.
    // Bu, stok kaydının kesinlikle geçerli bir mal kabule bağlı olmasını sağlar.
    final joinClause = deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty
        ? 'INNER JOIN goods_receipts gr ON s.goods_receipt_id = gr.goods_receipt_id'
        : '';

    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      whereClauses.add('gr.delivery_note_number = ?');
      whereArgs.add(deliveryNoteNumber);
    }

    final query = '''
      SELECT DISTINCT s.pallet_barcode
      FROM inventory_stock s
      $joinClause
      WHERE s.pallet_barcode IS NOT NULL AND ${whereClauses.join(' AND ')}
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => map['pallet_barcode'] as String).toList();
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(
    int? locationId, {
    List<String> stockStatuses = const ['available'],
    String? deliveryNoteNumber,
  }) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereClauses.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    // DÜZELTME: Eğer deliveryNoteNumber varsa, goods_receipts tablosuyla INNER JOIN yapmak daha güvenilirdir.
    // Bu, stok kaydının kesinlikle geçerli bir mal kabule bağlı olmasını sağlar.
    final joinClause = deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty
        ? 'INNER JOIN goods_receipts gr ON s.goods_receipt_id = gr.goods_receipt_id'
        : '';

    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      whereClauses.add('gr.delivery_note_number = ?');
      whereArgs.add(deliveryNoteNumber);
    }

    final query = '''
      SELECT
        u.UrunId as productId,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.UrunId
      $joinClause
      WHERE ${whereClauses.join(' AND ')} AND s.pallet_barcode IS NULL
      GROUP BY u.UrunId, u.UrunAdi, u.StokKodu, u.Barcode1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => BoxItem.fromJson(map)).toList();
  }

  @override
  Future<List<ProductStockItem>> getProductsAtLocation(
    int? locationId, {
    List<String> stockStatuses = const ['available'],
    String? deliveryNoteNumber,
  }) async {
    final db = await dbHelper.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereClauses.add('s.location_id IS NULL');
    } else {
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      final placeholders = stockStatuses.map((_) => '?').join(', ');
      whereClauses.add('s.stock_status IN ($placeholders)');
      whereArgs.addAll(stockStatuses);
    }

    String joinClause = '';
    if (deliveryNoteNumber != null) {
      joinClause = 'JOIN goods_receipts gr ON s.goods_receipt_id = gr.goods_receipt_id';
      whereClauses.add('gr.delivery_note_number = ?');
      whereArgs.add(deliveryNoteNumber);
    }

    final query = '''
      SELECT
        s.id as stock_id,
        u.UrunId as product_id,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.UrunId
      $joinClause
      WHERE ${whereClauses.join(' AND ')} AND s.pallet_barcode IS NULL
      GROUP BY u.UrunId, u.UrunAdi, u.StokKodu, u.Barcode1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => ProductStockItem.fromJson(map)).toList();
  }

  @override
  Future<List<ProductItem>> getPalletContents(String palletBarcode, int? locationId, {String stockStatus = 'available', int? siparisId, String? deliveryNoteNumber}) async {
    final db = await dbHelper.database;

    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    whereParts.add('s.pallet_barcode = ?');
    whereArgs.add(palletBarcode);

    if (locationId == null) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    whereParts.add('s.stock_status = ?');
    whereArgs.add(stockStatus);

    if (siparisId != null) {
      whereParts.add('s.siparis_id = ?');
      whereArgs.add(siparisId);
    }

    // Free receipt için delivery note kontrolü
    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      final goodsReceiptId = await getGoodsReceiptIdByDeliveryNote(deliveryNoteNumber);
      if (goodsReceiptId != null) {
        whereParts.add('s.goods_receipt_id = ?');
        whereArgs.add(goodsReceiptId);
      } else {
        // Delivery note bulunamazsa boş liste döndür
        return [];
      }
    }

    final query = '''
      SELECT
        u.UrunId as productId,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        s.quantity as currentQuantity,
        s.expiry_date as expiryDate
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.UrunId
      WHERE ${whereParts.join(' AND ')}
      ORDER BY u.UrunAdi
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    debugPrint("Palet '$palletBarcode' içinde ${maps.length} ürün bulundu");

    final result = maps.map((map) => ProductItem.fromJson(map)).toList();

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
          // 1. Azaltma işleminden önce kaynak stok kaydını/kayıtlarını bul.
          // Bu kayıtlardaki siparis_id ve goods_receipt_id aynı olmalıdır.
          final sourceStockQuery = await txn.query(
            'inventory_stock',
            where: 'urun_id = ? AND (location_id = ? OR (? IS NULL AND location_id IS NULL)) AND (pallet_barcode = ? OR (? IS NULL AND pallet_barcode IS NULL)) AND stock_status = ?',
            whereArgs: [
              item.productId,
              sourceLocationId,
              sourceLocationId,
              item.palletId,
              item.palletId,
              (sourceLocationId == null || sourceLocationId == 0) ? 'receiving' : 'available'
            ],
            limit: 1, // Sadece bir tane bulmamız yeterli
          );

          int? sourceSiparisId;
          int? sourceGoodsReceiptId;

          if (sourceStockQuery.isNotEmpty) {
            sourceSiparisId = sourceStockQuery.first['siparis_id'] as int?;
            sourceGoodsReceiptId = sourceStockQuery.first['goods_receipt_id'] as int?;
          }

          // 2. Stoğu kaynaktan azalt
          await _updateStockSmart(
            txn,
            productId: item.productId,
            locationId: sourceLocationId,
            quantityChange: -item.quantity,
            palletId: item.palletId,
            status: (sourceLocationId == null) ? 'receiving' : 'available',
            siparisIdForAddition: null, // Azaltma için null
            goodsReceiptIdForAddition: null, // Azaltma için null
            expiryDateForAddition: item.expiryDate,
          );

          final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;

          // 3. Stoğu hedefe ekle (yeni ID'lerle birlikte)
          await _updateStockSmart(
            txn,
            productId: item.productId,
            locationId: targetLocationId,
            quantityChange: item.quantity,
            palletId: targetPalletId,
            status: 'available',
            siparisIdForAddition: sourceSiparisId, // YENİ: Kaynaktan gelen ID'yi aktar
            goodsReceiptIdForAddition: sourceGoodsReceiptId, // YENİ: Kaynaktan gelen ID'yi aktar
            expiryDateForAddition: item.expiryDate,
          );

          await txn.insert('inventory_transfers', {
            'urun_id': item.productId,
            'from_location_id': sourceLocationId, // Artık null ise null kalıyor
            'to_location_id': targetLocationId,
            'quantity': item.quantity,
            'from_pallet_barcode': item.palletId,
            'pallet_barcode': targetPalletId,
            'employee_id': header.employeeId,
            'transfer_date': header.transferDate.toIso8601String(),
          });

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
                INSERT INTO wms_putaway_status (purchase_order_line_id, putaway_quantity, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(purchase_order_line_id) DO UPDATE SET
                putaway_quantity = putaway_quantity + excluded.putaway_quantity,
                updated_at = excluded.updated_at
              ''', [lineId, item.quantity, DateTime.now().toIso8601String(), DateTime.now().toIso8601String()]);
            }
          }

          itemsForJson.add(item.toApiJson());
        }

        String? poId;
        if (header.siparisId != null) {
          final maps = await txn.query(
            'satin_alma_siparis_fis',
            columns: ['po_id'],
            where: 'id = ?',
            whereArgs: [header.siparisId],
            limit: 1,
          );
          if (maps.isNotEmpty) {
            poId = maps.first['po_id'] as String?;
          }
        }

        final headerJson = header.toApiJson(sourceLocationId ?? 0, targetLocationId);
        if (poId != null) {
          headerJson['po_id'] = poId;
        }

        final pendingOp = PendingOperation(
          uniqueId: opId,
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode({
            'header': headerJson,
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
    final prefs = await SharedPreferences.getInstance();
    final warehouseCode = prefs.getString('warehouse_code');

    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status IN (1, 2, 3) AND warehouse_code = ?',
      whereArgs: [warehouseCode],
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int? locationId, {int? orderId, String? deliveryNoteNumber}) async {
    final db = await dbHelper.database;
    final isPutaway = orderId != null || deliveryNoteNumber != null;

    final List<Map<String, dynamic>> stockMaps;

    if (isPutaway) {
      if (orderId != null) {
        // Order-based putaway
        stockMaps = await db.query('inventory_stock', where: 'siparis_id = ? AND stock_status = ?', whereArgs: [orderId, 'receiving']);
      } else if (deliveryNoteNumber != null) {
        // Free receipt putaway - find stocks by delivery note
        final goodsReceiptId = await getGoodsReceiptIdByDeliveryNote(deliveryNoteNumber);
        if (goodsReceiptId == null) {
          return [];
        }
        stockMaps = await db.query('inventory_stock', where: 'goods_receipt_id = ? AND stock_status = ?', whereArgs: [goodsReceiptId, 'receiving']);
      } else {
        stockMaps = [];
      }
    } else {
      if (locationId == null) {
        stockMaps = await db.query('inventory_stock', where: 'location_id IS NULL AND stock_status = ?', whereArgs: ['available']);
      } else {
        stockMaps = await db.query('inventory_stock', where: 'location_id = ? AND stock_status = ?', whereArgs: [locationId, 'available']);
      }
    }

    if (stockMaps.isEmpty) {
      return [];
    }

    final productIds = stockMaps.map((e) => e['urun_id'] as int).toSet();
    final productsQuery = await db.query('urunler', where: 'UrunId IN (${productIds.map((_) => '?').join(',')})', whereArgs: productIds.toList());
    final productDetails = {for (var p in productsQuery) p['UrunId'] as int: ProductInfo.fromDbMap(p)};

    final Map<String, Map<int, TransferableItem>> aggregatedItems = {};

    for (final stock in stockMaps) {
      final productId = stock['urun_id'] as int;
      final productInfo = productDetails[productId];
      if (productInfo == null) continue;

      final pallet = stock['pallet_barcode'] as String?;
      final expiryDate = stock['expiry_date'] != null ? DateTime.tryParse(stock['expiry_date'].toString()) : null;
      final containerId = pallet ?? 'box_${productInfo.stockCode}';

      final groupingKey = containerId;

      aggregatedItems.putIfAbsent(groupingKey, () => {});

      if (aggregatedItems[groupingKey]!.containsKey(productId)) {
        final existingItem = aggregatedItems[groupingKey]![productId]!;
        aggregatedItems[groupingKey]![productId] = TransferableItem(
          product: existingItem.product,
          quantity: existingItem.quantity + (stock['quantity'] as num).toDouble(),
          sourcePalletBarcode: pallet,
          expiryDate: existingItem.expiryDate,
        );
      } else {
        aggregatedItems[groupingKey]![productId] = TransferableItem(
          product: productInfo,
          quantity: (stock['quantity'] as num).toDouble(),
          sourcePalletBarcode: pallet,
          expiryDate: expiryDate,
        );
      }
    }

    final result = aggregatedItems.entries.map((entry) {
      final containerId = entry.key;
      final itemsMap = entry.value;
      final isPallet = itemsMap.values.first.sourcePalletBarcode != null;

      return TransferableContainer(
        id: containerId,
        isPallet: isPallet,
        items: itemsMap.values.toList(),
      );
    }).toList();

    return result;
  }

  @override
  Future<Set<int>> getOrderIdsWithTransferableItems(List<int> orderIds) async {
    if (orderIds.isEmpty) {
      return {};
    }
    final db = await dbHelper.database;
    final idList = orderIds.map((id) => '?').join(',');
    final query = '''
      SELECT DISTINCT siparis_id
      FROM inventory_stock
      WHERE siparis_id IN ($idList)
      AND stock_status = 'receiving'
      AND quantity > 0
    ''';
    final result = await db.rawQuery(query, orderIds);
    return result.map((row) => row['siparis_id'] as int).toSet();
  }

  @override
  Future<MapEntry<String, int?>?> findLocationByCode(String code) async {
    final db = await dbHelper.database;
    final cleanCode = code.toLowerCase().trim();

    if (cleanCode.contains('kabul') || cleanCode.contains('receiving') || cleanCode == '0' || cleanCode == '000') {
      return const MapEntry('000', null); // Artık null döndürüyoruz
    }

    final maps = await db.query(
      'shelfs',
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
    // Rafa yerleştirme artık sipariş statusunu değiştirmiyor
    // Status sadece mal kabul aşamasında belirleniyor (0,1,2,3)
    // Bu metod artık sadece putaway takibi için kullanılıyor, status güncellemesi yapmıyor
    debugPrint("Putaway check için orderId: $orderId - Status güncellemesi devre dışı");
  }

  @override
  Future<List<ProductInfo>> getProductInfoByBarcode(String barcode) async {
    final db = await dbHelper.database;
    // DÜZELTME: Pasif ürünlerle de transfer işlemi yapılabilmesi için aktiflik kontrolü kaldırıldı
    final maps = await db.query(
      'urunler',
      where: 'Barcode1 = ?',
      whereArgs: [barcode],
    );
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<BoxItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;

    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereParts.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    whereParts.add('(u.StokKodu = ? OR u.Barcode1 = ?)');
    whereArgs.add(productCodeOrBarcode);
    whereArgs.add(productCodeOrBarcode);

    whereParts.add('s.pallet_barcode IS NULL');

    final query = '''
      SELECT
        u.UrunId as productId,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.UrunId
      WHERE ${whereParts.join(' AND ')}
      GROUP BY u.UrunId, u.UrunAdi, u.StokKodu, u.Barcode1
      LIMIT 1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    if (maps.isNotEmpty) {
      return BoxItem.fromJson(maps.first);
    }
    return null;
  }

  @override
  Future<ProductStockItem?> findProductByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']}) async {
    final db = await dbHelper.database;

    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (locationId == null) {
      whereParts.add('s.location_id IS NULL');
    } else {
      whereParts.add('s.location_id = ?');
      whereArgs.add(locationId);
    }

    if (stockStatuses.isNotEmpty) {
      whereParts.add('s.stock_status IN (${List.filled(stockStatuses.length, '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }

    whereParts.add('(u.StokKodu = ? OR u.Barcode1 = ?)');
    whereArgs.add(productCodeOrBarcode);
    whereArgs.add(productCodeOrBarcode);

    whereParts.add('s.pallet_barcode IS NULL');

    final query = '''
      SELECT
        s.id as stock_id,
        u.UrunId as product_id,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        u.Barcode1 as barcode1,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_id = u.UrunId
      WHERE ${whereParts.join(' AND ')}
      GROUP BY u.UrunId, u.UrunAdi, u.StokKodu, u.Barcode1
      LIMIT 1
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    if (maps.isNotEmpty) {
      return ProductStockItem.fromJson(maps.first);
    }
    return null;
  }

  Future<void> _updateStockSmart(
    DatabaseExecutor txn, {
    required int productId,
    required int? locationId,
    required double quantityChange,
    required String? palletId,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
    DateTime? expiryDateForAddition,
  }) async {
    if (quantityChange == 0) return;

    final isDecrement = quantityChange < 0;

    if (isDecrement) {
      double remainingToDecrement = quantityChange.abs();

      final whereClause = 'urun_id = ? AND ${locationId == null ? 'location_id IS NULL' : 'location_id = ?'} AND (pallet_barcode = ? OR (? IS NULL AND pallet_barcode IS NULL)) AND stock_status = ?';
      final whereArgs = locationId == null
        ? [productId, palletId, palletId, status]
        : [productId, locationId, palletId, palletId, status];

      debugPrint("DEBUG: SQL sorgusu: $whereClause");
      debugPrint("DEBUG: SQL parametreleri: $whereArgs");

      final stockEntries = await txn.query(
        'inventory_stock',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'expiry_date ASC',
      );

      if (stockEntries.isEmpty) {
        debugPrint("HATA: _updateStockSmart - Düşürme için kaynak stok bulunamadı.");
        debugPrint("Aranan parametreler: Ürün ID: $productId, Lokasyon ID: $locationId, Palet: $palletId, Durum: $status");

        // Hangi lokasyonlarda bu ürün var, kontrol edelim
        final availableStocks = await txn.query(
          'inventory_stock',
          where: 'urun_id = ? AND stock_status = ? AND quantity > 0',
          whereArgs: [productId, status],
        );
        debugPrint("Bu ürün için mevcut stoklar: ${availableStocks.length} kayıt");
        for (var stock in availableStocks) {
          debugPrint("Lokasyon: ${stock['location_id']}, Miktar: ${stock['quantity']}, Palet: ${stock['pallet_barcode']}");
        }

        throw Exception('Kaynakta stok bulunamadı. Ürün ID: $productId, Lokasyon: $locationId');
      }

      for (final stock in stockEntries) {
        final stockId = stock['id'] as int;
        final currentQty = (stock['quantity'] as num).toDouble();

        if (currentQty >= remainingToDecrement) {
          final newQty = currentQty - remainingToDecrement;
          if (newQty > 0.001) {
            await txn.update('inventory_stock', {'quantity': newQty}, where: 'id = ?', whereArgs: [stockId]);
          } else {
            await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [stockId]);
          }
          remainingToDecrement = 0;
          break;
        } else {
          remainingToDecrement -= currentQty;
          await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [stockId]);
        }
      }

      if (remainingToDecrement > 0.001) {
        debugPrint("HATA: _updateStockSmart - Yetersiz stok. Kalan: $remainingToDecrement");
        throw Exception('Kaynakta yeterli stok bulunamadı. İstenen: ${quantityChange.abs()}, Eksik: $remainingToDecrement');
      }
    } else {
      final expiryDateStr = expiryDateForAddition?.toIso8601String();

      final existing = await txn.query(
        'inventory_stock',
        where: 'urun_id = ? AND ${locationId == null ? 'location_id IS NULL' : 'location_id = ?'} AND (pallet_barcode = ? OR (? IS NULL AND pallet_barcode IS NULL)) AND stock_status = ? AND (siparis_id = ? OR (? IS NULL AND siparis_id IS NULL)) AND (expiry_date = ? OR (? IS NULL AND expiry_date IS NULL))',
        whereArgs: locationId == null
          ? [productId, palletId, palletId, status, siparisIdForAddition, siparisIdForAddition, expiryDateStr, expiryDateStr]
          : [productId, locationId, palletId, palletId, status, siparisIdForAddition, siparisIdForAddition, expiryDateStr, expiryDateStr],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final currentQty = (existing.first['quantity'] as num).toDouble();
        final newQty = currentQty + quantityChange;
        await txn.update(
          'inventory_stock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.insert('inventory_stock', {
          'urun_id': productId,
          'location_id': locationId, // Artık null ise null kalıyor
          'quantity': quantityChange,
          'pallet_barcode': palletId,
          'stock_status': status,
          'siparis_id': siparisIdForAddition,
          'goods_receipt_id': goodsReceiptIdForAddition,
          'updated_at': DateTime.now().toIso8601String(),
          'expiry_date': expiryDateStr,
        });
      }
    }
  }

  @override
  Future<List<String>> getFreeReceiptDeliveryNotes() async {
    final db = await dbHelper.database;

    const query = '''
      SELECT DISTINCT gr.delivery_note_number
      FROM goods_receipts gr
      JOIN inventory_stock s ON gr.goods_receipt_id = s.goods_receipt_id
      WHERE gr.siparis_id IS NULL
        AND gr.delivery_note_number IS NOT NULL
        AND gr.delivery_note_number != ''
        AND s.stock_status = 'receiving'
        AND s.quantity > 0
      ORDER BY gr.receipt_date DESC
    ''';

    final maps = await db.rawQuery(query);
    return maps.map((map) => map['delivery_note_number'] as String).toList();
  }

  @override
  Future<bool> hasOrderReceivedWithPallets(int orderId) async {
    final db = await dbHelper.database;
    const query = '''
      SELECT COUNT(*) as count
      FROM inventory_stock
      WHERE siparis_id = ?
        AND stock_status = 'receiving'
        AND pallet_barcode IS NOT NULL
        AND quantity > 0
    ''';
    final result = await db.rawQuery(query, [orderId]);
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  @override
  Future<bool> hasOrderReceivedWithBoxes(int orderId) async {
    final db = await dbHelper.database;
    const query = '''
      SELECT COUNT(*) as count
      FROM inventory_stock
      WHERE siparis_id = ?
        AND stock_status = 'receiving'
        AND pallet_barcode IS NULL
        AND quantity > 0
    ''';
    final result = await db.rawQuery(query, [orderId]);
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  @override
  Future<int?> getGoodsReceiptIdByDeliveryNote(String deliveryNoteNumber) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'goods_receipts',
      columns: ['goods_receipt_id'],
      where: 'delivery_note_number = ?',
      whereArgs: [deliveryNoteNumber],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['goods_receipt_id'] as int?;
    }
    return null;
  }
}

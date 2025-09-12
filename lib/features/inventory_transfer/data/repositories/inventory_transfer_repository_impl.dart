// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_stock_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;

  InventoryTransferRepositoryImpl({required this.dbHelper, required this.dio});

  @override
  Future<Map<String, int?>> getSourceLocations({bool includeReceivingArea = true}) async {
    final db = await dbHelper.database;

    // Stoklu lokasyonları getir - iş mantığına özel kompleks sorgu
    final query = '''
      SELECT DISTINCT s.${DbColumns.id}, s.${DbColumns.locationsName}
      FROM ${DbTables.locations} s
      INNER JOIN inventory_stock i ON s.${DbColumns.id} = i.${DbColumns.stockLocationId}
      WHERE s.${DbColumns.isActive} = 1 AND i.${DbColumns.stockStatus} = '${DbColumns.stockStatusAvailable}' AND i.${DbColumns.stockQuantity} > 0
      ORDER BY s.${DbColumns.locationsName}
    ''';

    final maps = await db.rawQuery(query);
    final result = <String, int?>{};

    if (includeReceivingArea) {
      // Mal kabul alanında stok var mı kontrol et
      final receivingStockQuery = await db.query(
        DbTables.inventoryStock,
        where: '${DbColumns.stockLocationId} IS NULL AND ${DbColumns.stockStatus} = ? AND ${DbColumns.stockQuantity} > 0',
        whereArgs: [DbColumns.stockStatusReceiving]
      );
      if (receivingStockQuery.isNotEmpty) {
        result['000'] = null; // Artık direkt null kullanıyoruz
      }
    }

    for (var map in maps) {
      result[map[DbColumns.locationsName] as String] = map[DbColumns.id] as int;
    }
    return result;
  }

  @override
  Future<Map<String, int?>> getTargetLocations({bool excludeReceivingArea = false}) async {
    final db = await dbHelper.database;
    final maps = await db.query(DbTables.locations, where: '${DbColumns.isActive} = 1');
    final result = <String, int?>{};

    if (!excludeReceivingArea) {
      result['000'] = null; // Goods receiving area - artık direkt null
    }

    for (var map in maps) {
      result[map[DbColumns.locationsName] as String] = map[DbColumns.id] as int;
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
  @Deprecated('Use getProductsAtLocation instead')
  Future<List<ProductStockItem>> getBoxesAtLocation(
    int? locationId, {
    List<String> stockStatuses = const ['available'],
    String? deliveryNoteNumber,
  }) async {
    // Delegate to the new method
    return getProductsAtLocation(locationId, stockStatuses: stockStatuses, deliveryNoteNumber: deliveryNoteNumber);
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
        u._key as product_id,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        (SELECT bark.barkod FROM barkodlar bark JOIN birimler b ON bark._key_scf_stokkart_birimleri = b._key WHERE b.StokKodu = u.StokKodu LIMIT 1) as barcode,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_key = u._key
      $joinClause
      WHERE ${whereClauses.join(' AND ')} AND s.pallet_barcode IS NULL
      GROUP BY u._key, u.UrunAdi, u.StokKodu
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
        u._key as productKey,
        u.UrunAdi as productName,
        u.StokKodu as productCode,
        s.birim_key,
        (SELECT bark.barkod FROM barkodlar bark JOIN birimler b ON bark._key_scf_stokkart_birimleri = b._key WHERE b.StokKodu = u.StokKodu LIMIT 1) as barcode,
        s.quantity as currentQuantity,
        s.expiry_date as expiryDate
      FROM inventory_stock s
      JOIN urunler u ON s.urun_key = u._key
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
      // KRITIK DEBUG: Transfer öncesi birimKey kontrolü
      for (var item in items) {
        debugPrint("DEBUG Transfer Item - productKey: ${item.productKey}, birimKey: ${item.birimKey}, quantity: ${item.quantity}");
      }
      
      await db.transaction((txn) async {
        // 1. ADIM: UNIQUE ID'Yİ ÖNCEDEN AL
        final pendingOp = PendingOperation.create(
          type: PendingOperationType.inventoryTransfer,
          data: "{}", // Geçici
          createdAt: DateTime.now().toUtc(),
        );
        final String operationUniqueId = pendingOp.uniqueId;
        
        final List<Map<String, dynamic>> itemsForJson = [];

        for (final item in items) {
          // KRITIK FIX: Transfer sonrası yeni stok kaydı için UUID üret
          const uuid = Uuid();
          final transferStockUuid = uuid.v4();
          debugPrint('🔄 Transfer UUID üretildi: $transferStockUuid - ${item.productKey}');

          // 1. Azaltma işleminden önce kaynak stok kaydını/kayıtlarını bul.
          // Bu kayıtlardaki siparis_id ve goods_receipt_id aynı olmalıdır.
          // NULL-safe kaynak stok sorgusu
          String sourceWhereClause = 'urun_key = ? AND stock_status = ?';
          List<dynamic> sourceWhereArgs = [
            item.productKey,
            (sourceLocationId == null || sourceLocationId == 0) ? 'receiving' : 'available'
          ];
          
          // birim_key kontrolü
          if (item.birimKey == null) {
            sourceWhereClause += ' AND birim_key IS NULL';
          } else {
            sourceWhereClause += ' AND birim_key = ?';
            sourceWhereArgs.add(item.birimKey);
          }
          
          // Location_id kontrolü
          if (sourceLocationId == null || sourceLocationId == 0) {
            sourceWhereClause += ' AND location_id IS NULL';
          } else {
            sourceWhereClause += ' AND location_id = ?';
            sourceWhereArgs.add(sourceLocationId);
          }
          
          // Pallet_barcode kontrolü
          if (item.palletId == null) {
            sourceWhereClause += ' AND pallet_barcode IS NULL';
          } else {
            sourceWhereClause += ' AND pallet_barcode = ?';
            sourceWhereArgs.add(item.palletId);
          }
          
          // KRITIK FIX: Putaway işlemleri (receiving → available) için siparis_id filtresi
          if (sourceLocationId == null || sourceLocationId == 0) {
            // Bu receiving area'dan putaway işlemi, siparis_id ile filtrelemek gerekli
            if (header.siparisId != null) {
              sourceWhereClause += ' AND siparis_id = ?';
              sourceWhereArgs.add(header.siparisId);
            }
          }
          
          final sourceStockQuery = await txn.query(
            'inventory_stock',
            where: sourceWhereClause,
            whereArgs: sourceWhereArgs,
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
            productId: item.productKey,
            birimKey: item.birimKey,
            locationId: sourceLocationId,
            quantityChange: -item.quantity,
            palletId: item.palletId,
            status: (sourceLocationId == null) ? 'receiving' : 'available',
            siparisIdForAddition: sourceSiparisId, // KRITIK FIX: Receiving'de siparis_id ile match et
            goodsReceiptIdForAddition: sourceGoodsReceiptId, // KRITIK FIX: Receiving'de goods_receipt_id ile match et
            expiryDateForAddition: item.expiryDate,
            isTransferOperation: false, // DÜZELTME: FIFO mantığının düzgün çalışması için false olmalı
          );

          final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;

          // 3. Stoğu hedefe ekle 
          // KRITIK FIX: 'available' durumunda siparis_id ve goods_receipt_id NULL olmalı (konsolidasyon için)
          await _updateStockSmart(
            txn,
            productId: item.productKey,
            birimKey: item.birimKey,
            locationId: targetLocationId,
            quantityChange: item.quantity,
            palletId: targetPalletId,
            status: 'available',
            siparisIdForAddition: null, // ÇÖZÜM: Available durumunda NULL - konsolidasyon için
            goodsReceiptIdForAddition: null, // ÇÖZÜM: Available durumunda NULL - konsolidasyon için
            expiryDateForAddition: item.expiryDate,
            isTransferOperation: false, // DÜZELTME: Konsolidasyon yapması için false olmalı
            stockUuid: transferStockUuid, // KRITIK FIX: Phone-generated UUID
          );

          // 2. ADIM: TRANSFER KAYDINI ETİKETLE
          await txn.insert(DbTables.inventoryTransfers, {
            'operation_unique_id': operationUniqueId, // BU SATIRI EKLE
            'urun_key': item.productKey,
            'birim_key': item.birimKey, // KRITIK FIX: birim_key'i de kaydet
            'from_location_id': sourceLocationId, // Artık null ise null kalıyor
            'to_location_id': targetLocationId,
            'quantity': item.quantity,
            'from_pallet_barcode': item.palletId,
            'pallet_barcode': targetPalletId,
            'employee_id': header.employeeId,
            'transfer_date': header.transferDate.toIso8601String(),
          });

          if (sourceLocationId == null && header.siparisId != null) {
            await txn.query(
              DbTables.orderLines,
              columns: ['id'],
              where: 'siparisler_id = ? AND urun_key = ? AND turu = ?',
              whereArgs: [header.siparisId, item.productKey, '1'],
              limit: 1,
            );
            // wms_putaway_status tablosu kaldırıldı - yerleştirme durumunu inventory_stock'tan takip edebiliriz
          }

          // KRITIK FIX: UUID içeren yeni TransferItemDetail oluştur ve sunucuya gönder
          final itemWithUuid = TransferItemDetail(
            productKey: item.productKey,
            birimKey: item.birimKey,
            productName: item.productName,
            productCode: item.productCode,
            quantity: item.quantity,
            palletId: item.palletId,
            expiryDate: item.expiryDate,
            stockUuid: transferStockUuid, // KRITIK FIX: Phone-generated UUID
            targetLocationId: item.targetLocationId,
            targetLocationName: item.targetLocationName,
          );
          itemsForJson.add(itemWithUuid.toApiJson());
        }

        String? poId;
        if (header.siparisId != null) {
          final maps = await txn.query(
            DbTables.orders,
            columns: ['fisno'],
            where: 'id = ?',
            whereArgs: [header.siparisId],
            limit: 1,
          );
          if (maps.isNotEmpty) {
            poId = maps.first['fisno'] as String?;
          }
        }

        final headerJson = header.toApiJson(sourceLocationId ?? 0, targetLocationId);
        if (poId != null) {
          headerJson['fisno'] = poId;
        }

        // 3. ADIM: NİHAİ PENDING OPERATION'I AYNI ID İLE KAYDET
        final finalPendingOp = PendingOperation.create(
          uniqueId: operationUniqueId, // AYNI ID'Yİ KULLAN
          type: PendingOperationType.inventoryTransfer,
          data: jsonEncode({
            'operation_unique_id': operationUniqueId, // BU SATIR EKSİKTİ!
            'header': headerJson,
            'items': itemsForJson,
          }),
          createdAt: pendingOp.createdAt,
        );

        await txn.insert(DbTables.pendingOperations, finalPendingOp.toDbMap());

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

    // Get warehouse name from SharedPreferences
    final warehouseName = prefs.getString('warehouse_name');
    
    // If warehouse not found, don't filter by warehouse (temporary solution)
    if (warehouseName == null) {
      debugPrint("WARNING: Warehouse name not found for code $warehouseCode, getting all orders");
    }

    // FIX: Show orders that have either inventory_stock OR goods_receipt_items for put-away
    final maps = await db.rawQuery('''
      SELECT DISTINCT
        o.id,
        o.fisno,
        o.tarih,
        o.notlar,
        ? as warehouse_name,
        o.status,
        o.created_at,
        o.updated_at,
        t.tedarikci_adi as supplierName
      FROM siparisler o
      LEFT JOIN inventory_stock i ON i.siparis_id = o.id AND i.stock_status = 'receiving' AND i.quantity > 0
      LEFT JOIN goods_receipts gr ON gr.siparis_id = o.id
      LEFT JOIN goods_receipt_items gri ON gri.receipt_id = gr.goods_receipt_id AND gri.quantity_received > 0
      LEFT JOIN siparis_ayrintili s ON s.siparisler_id = o.id AND s.turu = '1'
      LEFT JOIN tedarikci t ON t.tedarikci_kodu = o.__carikodu
      WHERE o.status = 2
        AND (i.id IS NOT NULL OR gri.id IS NOT NULL)
      GROUP BY o.id, o.fisno, o.tarih, o.notlar, o.status, o.created_at, o.updated_at, t.tedarikci_adi
      ORDER BY o.created_at DESC
    ''', [warehouseName ?? 'N/A']);
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<List<TransferableContainer>> getTransferableContainers(int? locationId, {int? orderId, String? deliveryNoteNumber}) async {
    final db = await dbHelper.database;
    final isPutaway = orderId != null || deliveryNoteNumber != null;

    final List<Map<String, dynamic>> stockMaps;

    if (isPutaway) {
      if (orderId != null) {
        // BASIT YAKLAŞIM: Sadece inventory_stock'taki miktarı kullan
        // Transfer hesaplaması şimdilik devre dışı - sadece mevcut stok miktarını göster
        stockMaps = await db.rawQuery('''
          SELECT 
            i.id,
            i.urun_key,
            i.birim_key,
            i.location_id,
            i.pallet_barcode,
            i.expiry_date,
            i.stock_status,
            i.siparis_id,
            i.goods_receipt_id,
            i.quantity
          FROM inventory_stock i
          WHERE i.stock_status = 'receiving'
            AND i.siparis_id = ?
            AND i.quantity > 0
        ''', [orderId]);
      } else if (deliveryNoteNumber != null) {
        // Free receipt putaway - find stocks by delivery note
        final goodsReceiptId = await getGoodsReceiptIdByDeliveryNote(deliveryNoteNumber);
        if (goodsReceiptId == null) {
          return [];
        }
        stockMaps = await db.query(DbTables.inventoryStock, where: 'goods_receipt_id = ? AND stock_status = ? AND quantity > 0', whereArgs: [goodsReceiptId, 'receiving']);
      } else {
        stockMaps = [];
      }
    } else {
      if (locationId == null) {
        stockMaps = await db.query(DbTables.inventoryStock, where: 'location_id IS NULL AND stock_status = ? AND quantity > 0', whereArgs: ['available']);
      } else {
        stockMaps = await db.query(DbTables.inventoryStock, where: 'location_id = ? AND stock_status = ? AND quantity > 0', whereArgs: [locationId, 'available']);
      }
    }

    if (stockMaps.isEmpty) {
      return [];
    }

    final productIds = stockMaps.map((e) => e['urun_key'] as String).toSet();
    
    final productsQuery = await db.rawQuery('''
      SELECT 
        u.*,
        MAX(bark.barkod) as barkod,
        b._key as birim_key,
        b.birimadi as birimadi,
        b.birimkod as birimkod
      FROM urunler u
      LEFT JOIN birimler b ON b.StokKodu = u.StokKodu
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE u._key IN (${productIds.map((_) => '?').join(',')})
      GROUP BY u._key
    ''', productIds.toList());
    final productDetails = <String, ProductInfo>{};
    for (var p in productsQuery) {
      final productMap = Map<String, dynamic>.from(p);
      if (productMap['barkod'] != null) {
        productMap['barkod_info'] = {'barkod': productMap['barkod']};
      }
      
      final productInfo = ProductInfo.fromDbMap(productMap);
      productDetails[p['_key'] as String] = productInfo;
    }

    final Map<String, Map<String, TransferableItem>> aggregatedItems = {};

    for (final stock in stockMaps) {
      final productId = stock['urun_key'] as String;
      var productInfo = productDetails[productId];
      if (productInfo == null) continue;
      
      // KRITIK FIX: inventory_stock'taki birim_key değerini kullan
      final stockBirimKey = stock['birim_key'] as String?;
      if (stockBirimKey != null) {
        // ProductInfo'nun birimInfo'sunu güncelle
        final updatedBirimInfo = Map<String, dynamic>.from(productInfo.birimInfo ?? {});
        updatedBirimInfo['birim_key'] = stockBirimKey;
        
        productInfo = ProductInfo(
          id: productInfo.id,
          productKey: productInfo.productKey,
          name: productInfo.name,
          stockCode: productInfo.stockCode,
          isActive: productInfo.isActive,
          birimInfo: updatedBirimInfo,
          barkodInfo: productInfo.barkodInfo,
          isOutOfOrder: productInfo.isOutOfOrder,
          quantityReceived: productInfo.quantityReceived,
        );
      }

      final pallet = stock['pallet_barcode'] as String?;
      final expiryDate = stock['expiry_date'] != null ? DateTime.tryParse(stock['expiry_date'].toString()) : null;
      final containerId = pallet ?? 'box_${productInfo.stockCode}';

      // KRITIK FIX: Paletin içindeki ve serbest ürünleri ayırmak için containerId kullan
      // Normal transfer için de container bazında grupla (pallet var mı yok mu diye)
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
    // Yeni barkodlar tablosunu kullan
    final result = await dbHelper.getProductByBarcode(barcode);
    if (result != null) {
      return [ProductInfo.fromDbMap(result)];
    }
    return [];
  }

  @override
  @Deprecated('Use findProductByCodeAtLocation instead')
  Future<ProductStockItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']}) async {
    // Delegate to the new method
    return findProductByCodeAtLocation(productCodeOrBarcode, locationId, stockStatuses: stockStatuses);
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

    // Sadece barkodlar tablosundan ara
    final productResult = await dbHelper.getProductByBarcode(productCodeOrBarcode);
    if (productResult == null) {
      // Barkod bulunamadı, null döndür
      return null;
    }
    
    // Barkod ile bulunan ürünün _key'ini kullan
    whereParts.add('u._key = ?');
    whereArgs.add(productResult['_key']);

    whereParts.add('s.pallet_barcode IS NULL');

    final query = '''
      SELECT
        s.id as stock_id,
        u._key as product_id,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        (SELECT bark.barkod FROM barkodlar bark JOIN birimler b ON bark._key_scf_stokkart_birimleri = b._key WHERE b.StokKodu = u.StokKodu LIMIT 1) as barcode,
        SUM(s.quantity) as quantity
      FROM inventory_stock s
      JOIN urunler u ON s.urun_key = u._key
      WHERE ${whereParts.join(' AND ')}
      GROUP BY u._key, u.UrunAdi, u.StokKodu
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
    required String productId, // urun_key değeri String olarak
    String? birimKey, // birim_key değeri
    required int? locationId,
    required double quantityChange,
    required String? palletId,
    required String status,
    int? siparisIdForAddition,
    int? goodsReceiptIdForAddition,
    DateTime? expiryDateForAddition,
    bool isTransferOperation = false, // YENI: Transfer işlemi olup olmadığını belirler
    String? stockUuid, // KRITIK FIX: Phone-generated UUID
  }) async {
    if (quantityChange == 0) return;

    final isDecrement = quantityChange < 0;

    if (isDecrement) {
      double remainingToDecrement = quantityChange.abs();

      // NULL-safe SQL sorgusu oluştur
      String whereClause = 'urun_key = ? AND stock_status = ?';
      List<dynamic> whereArgs = [productId, status];
      
      // birim_key kontrolü
      if (birimKey == null) {
        whereClause += ' AND birim_key IS NULL';
      } else {
        whereClause += ' AND birim_key = ?';
        whereArgs.add(birimKey);
      }
      
      // Location_id kontrolü
      if (locationId == null) {
        whereClause += ' AND location_id IS NULL';
      } else {
        whereClause += ' AND location_id = ?';
        whereArgs.add(locationId);
      }
      
      // Pallet_barcode kontrolü
      if (palletId == null) {
        whereClause += ' AND pallet_barcode IS NULL';
      } else {
        whereClause += ' AND pallet_barcode = ?';
        whereArgs.add(palletId);
      }
      
      // KRITIK FIX: Receiving durumunda siparis_id ile match et
      if (status == 'receiving' && siparisIdForAddition != null) {
        whereClause += ' AND siparis_id = ?';
        whereArgs.add(siparisIdForAddition);
      }
      
      // KRITIK FIX: Receiving durumunda goods_receipt_id ile match et
      if (status == 'receiving' && goodsReceiptIdForAddition != null) {
        whereClause += ' AND goods_receipt_id = ?';
        whereArgs.add(goodsReceiptIdForAddition);
      }

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
          where: 'urun_key = ? AND stock_status = ? AND quantity > 0',
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
            await txn.update(DbTables.inventoryStock, {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [stockId]);
          } else {
            // KRITIK FIX: Silinen stock'ın UUID'sini kaydet - tombstone için
            final stockUuid = stock['stock_uuid'] as String?;
            await txn.delete(DbTables.inventoryStock, where: 'id = ?', whereArgs: [stockId]);
            debugPrint('🗑️ Transfer sırasında stock silindi: ID=$stockId, UUID=$stockUuid');
          }
          remainingToDecrement = 0;
          break;
        } else {
          remainingToDecrement -= currentQty;
          // KRITIK FIX: Silinen stock'ın UUID'sini kaydet - tombstone için  
          final stockUuid = stock['stock_uuid'] as String?;
          await txn.delete(DbTables.inventoryStock, where: 'id = ?', whereArgs: [stockId]);
          debugPrint('🗑️ Transfer sırasında stock silindi: ID=$stockId, UUID=$stockUuid');
        }
      }

      if (remainingToDecrement > 0.001) {
        debugPrint("HATA: _updateStockSmart - Yetersiz stok. Kalan: $remainingToDecrement");
        throw Exception('Kaynakta yeterli stok bulunamadı. İstenen: ${quantityChange.abs()}, Eksik: $remainingToDecrement');
      }
    } else {
      // KRITIK FIX: expiry_date'i normalize et - konsolidasyon için consistent format gerekli
      final expiryDateStr = expiryDateForAddition != null 
        ? DateTime(expiryDateForAddition.year, expiryDateForAddition.month, expiryDateForAddition.day).toIso8601String().split('T')[0]
        : null;

      // NULL-safe existing stock sorgusu
      String existingWhereClause = 'urun_key = ? AND stock_status = ?';
      List<dynamic> existingWhereArgs = [productId, status];
      
      // birim_key kontrolü
      if (birimKey == null) {
        existingWhereClause += ' AND birim_key IS NULL';
      } else {
        existingWhereClause += ' AND birim_key = ?';
        existingWhereArgs.add(birimKey);
      }
      
      // Location ID kontrolü
      if (locationId == null) {
        existingWhereClause += ' AND location_id IS NULL';
      } else {
        existingWhereClause += ' AND location_id = ?';
        existingWhereArgs.add(locationId);
      }
      
      // Pallet barcode kontrolü
      if (palletId == null) {
        existingWhereClause += ' AND pallet_barcode IS NULL';
      } else {
        existingWhereClause += ' AND pallet_barcode = ?';
        existingWhereArgs.add(palletId);
      }
      
      // Expiry date kontrolü (siparis_id ve goods_receipt_id artık unique constraint'te yok)
      if (expiryDateStr == null) {
        existingWhereClause += ' AND expiry_date IS NULL';
      } else {
        existingWhereClause += ' AND expiry_date = ?';
        existingWhereArgs.add(expiryDateStr);
      }

      // KRITIK FIX: Transfer işlemlerinde konsolidasyon YAPMAMA - her transfer yeni kayıt oluştursun
      // Transfer sırasında sadece birebir kayıt oluştur, konsolide etme
      if (isTransferOperation) {
        // Transfer edilen kayıtlar için konsolidasyon yapma - her zaman yeni kayıt oluştur
        // Bu sayede çift sayma önlenir
      } else if (status == 'available') {
        // Normal available stoklarda konsolidasyon yap (transfer dışı durumlar)
        if (siparisIdForAddition == null) {
          existingWhereClause += ' AND siparis_id IS NULL';
        } else {
          existingWhereClause += ' AND siparis_id = ?';
          existingWhereArgs.add(siparisIdForAddition);
        }
        
        if (goodsReceiptIdForAddition == null) {
          existingWhereClause += ' AND goods_receipt_id IS NULL';
        } else {
          existingWhereClause += ' AND goods_receipt_id = ?';
          existingWhereArgs.add(goodsReceiptIdForAddition);
        }
      } else if (status == 'receiving') {
        // KRITIK FIX: 'receiving' durumunda siparis_id'yi de kontrol et - farklı siparişler ayrı tutulmalı
        if (siparisIdForAddition == null) {
          existingWhereClause += ' AND siparis_id IS NULL';
        } else {
          existingWhereClause += ' AND siparis_id = ?';
          existingWhereArgs.add(siparisIdForAddition);
        }
        
        // Receiving durumunda goods_receipt_id kontrolü de yapılmalı
        if (goodsReceiptIdForAddition == null) {
          existingWhereClause += ' AND goods_receipt_id IS NULL';
        } else {
          existingWhereClause += ' AND goods_receipt_id = ?';
          existingWhereArgs.add(goodsReceiptIdForAddition);
        }
      }

      // KRITIK FIX: Transfer durumunda existing sorgusu yapmama - her zaman yeni kayıt oluştur
      List<Map<String, Object?>> existing = [];
      
      // Transfer işlemi değilse konsolidasyon kontrolü yap
      if (!isTransferOperation) {
        existing = await txn.query(
          'inventory_stock',
          where: existingWhereClause,
          whereArgs: existingWhereArgs,
          limit: 1,
        );
      }

      if (existing.isNotEmpty) {
        final currentQty = (existing.first['quantity'] as num).toDouble();
        final newQty = currentQty + quantityChange;
        debugPrint('🔄 KONSOLIDASYON: Mevcut stok bulundu ID=${existing.first['id']}, quantity=$currentQty → $newQty');
        await txn.update(
          'inventory_stock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        debugPrint('➕ YENİ STOK: Konsolidasyon için eşleşme bulunamadı, yeni kayıt oluşturuluyor');
        debugPrint('   Parametreler: status=$status, location=$locationId, siparis=$siparisIdForAddition, quantity=$quantityChange');
        
        // KRITIK FIX: Transfer işlemlerinde phone-generated UUID kullan
        final finalStockUuid = stockUuid ?? const Uuid().v4();
        
        await txn.insert(DbTables.inventoryStock, {
          'stock_uuid': finalStockUuid, // Phone-generated UUID (parametreli)
          'urun_key': productId,
          'birim_key': birimKey,
          'location_id': locationId, // Artık null ise null kalıyor
          'quantity': quantityChange,
          'pallet_barcode': palletId,
          'stock_status': status,
          'siparis_id': siparisIdForAddition,
          'goods_receipt_id': goodsReceiptIdForAddition,
          'created_at': DateTime.now().toIso8601String(), // DÜZELTME: created_at eklendi
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
  Future<List<Map<String, dynamic>>> getFreeReceiptsForPutaway() async {
    return await dbHelper.getFreeReceiptsForPutaway();
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
  Future<bool> hasOrderReceivedWithProducts(int orderId) async {
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

  @override
  Future<List<ProductInfo>> searchProductsForTransfer(String query, {
    int? orderId,
    String? deliveryNoteNumber, 
    int? locationId,
    List<String> stockStatuses = const ['available', 'receiving'],
    bool excludePalletizedProducts = false, // YENI: Paletin içindeki ürünleri hariç tut
  }) async {
    final db = await dbHelper.database;
    
    // Build WHERE clauses based on context
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];
    
    // Search by barcode or StokKodu (moved to WHERE clause for LEFT JOIN compatibility)
    // Will be handled separately in SQL query
    
    // Add stock status filter
    if (stockStatuses.isNotEmpty) {
      whereClauses.add('s.stock_status IN (${stockStatuses.map((_) => '?').join(',')})');
      whereArgs.addAll(stockStatuses);
    }
    
    // YENI: Paletin içindeki ürünleri hariç tut (Product Mode için)
    if (excludePalletizedProducts) {
      whereClauses.add('s.pallet_barcode IS NULL');
    }
    
    // Add context-specific filters
    if (orderId != null) {
      // Search products related to specific order
      whereClauses.add('s.siparis_id = ?');
      whereArgs.add(orderId);
    } else if (deliveryNoteNumber != null) {
      // Search products from specific delivery note
      whereClauses.add('gr.delivery_note_number = ?');
      whereArgs.add(deliveryNoteNumber);
    } else if (locationId != null) {
      // Search products at specific location
      whereClauses.add('s.location_id = ?');
      whereArgs.add(locationId);
    } else {
      // Search all available products (no additional filter)
    }
    
    // Add search parameters for barcode and StokKodu
    whereArgs.insert(0, '%$query%');  // For StokKodu search
    whereArgs.insert(0, '%$query%');  // For barcode search
    
    final whereClause = whereClauses.isNotEmpty ? ' AND ' + whereClauses.join(' AND ') : '';
    
    final sql = '''
      SELECT DISTINCT
        u._key,
        u.UrunAdi,
        u.StokKodu,
        u.aktif,
        bark.barkod
      FROM urunler u
      INNER JOIN inventory_stock s ON s.urun_key = u._key
      LEFT JOIN birimler b ON b.StokKodu = u.StokKodu
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      ${deliveryNoteNumber != null ? 'INNER JOIN goods_receipts gr ON gr.goods_receipt_id = s.goods_receipt_id' : ''}
      WHERE (bark.barkod LIKE ? OR u.StokKodu LIKE ?) $whereClause AND s.quantity > 0
      ORDER BY u.UrunAdi ASC
    ''';
    
    final maps = await db.rawQuery(sql, whereArgs);
    final results = maps.map((map) => ProductInfo.fromDbMap(map)).toList();
    return results;
  }
}

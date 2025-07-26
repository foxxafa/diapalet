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
import 'package:shared_preferences/shared_preferences.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;

  InventoryTransferRepositoryImpl({required this.dbHelper, required this.dio});

  @override
  Future<Map<String, int>> getSourceLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('shelfs', where: 'is_active = 1');
    final result = <String, int>{'000': 0}; // Goods receiving area
    for (var map in maps) {
      result[map['name'] as String] = map['id'] as int;
    }
    return result;
  }

  @override
  Future<Map<String, int>> getTargetLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query('shelfs', where: 'is_active = 1');
    final result = <String, int>{};
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

    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      whereClauses.add('gr.delivery_note_number = ?');
      whereArgs.add(deliveryNoteNumber);
    }

    final query = '''
      SELECT DISTINCT s.pallet_barcode
      FROM inventory_stock s
      LEFT JOIN goods_receipts gr ON s.goods_receipt_id = gr.goods_receipt_id
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

    if (deliveryNoteNumber != null && deliveryNoteNumber.isNotEmpty) {
      whereClauses.add('gr.delivery_note_number = ?');
      whereArgs.add(deliveryNoteNumber);
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
      LEFT JOIN goods_receipts gr ON s.goods_receipt_id = gr.goods_receipt_id
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
          await _updateStockSmart(
            txn,
            productId: item.productId,
            locationId: sourceLocationId,
            quantityChange: -item.quantity,
            palletId: item.palletId,
            status: (sourceLocationId == null && header.siparisId != null) ? 'receiving' : 'available',
            siparisId: (sourceLocationId == null && header.siparisId != null) ? header.siparisId : null,
            expiryDateForAddition: item.expiryDate,
          );

          // 2. Hedefteki palet durumunu belirle
          final targetPalletId = header.operationType == AssignmentMode.pallet ? item.palletId : null;

          // 3. Hedefe ekle
          await _updateStockSmart(
            txn,
            productId: item.productId,
            locationId: targetLocationId,
            quantityChange: item.quantity,
            palletId: targetPalletId,
            status: 'available',
            siparisId: null,
            expiryDateForAddition: item.expiryDate,
          );

          // 4. Transfer işlemini logla
          await txn.insert('inventory_transfers', {
            'urun_id': item.productId,
            'from_location_id': (sourceLocationId == 0) ? null : sourceLocationId,
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
    final warehouseId = prefs.getInt('warehouse_id');

    // DÜZELTME: Mal kabulü yapılmış (1) veya manuel kapatılmış (2) siparişler transfer edilebilir.
    final maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status IN (1, 2) AND branch_id = ?',
      whereArgs: [warehouseId],
      orderBy: 'tarih DESC',
    );
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
      // Serbest Transfer: Sadece 'available' statüsündeki ürünler gösterilir
      if (locationId == null || locationId == 0) {
        // Mal kabul alanından serbest transfer: Sadece 'available' stokları al
        stockMaps = await db.query('inventory_stock', where: 'location_id IS NULL AND stock_status = ?', whereArgs: ['available']);
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

    // final Map<String, List<TransferableItem>> groupedByContainer = {};
    // GÜNCELLEME: Aynı ürünü (farklı SKT'lerle) tek kalemde toplamak için yeni bir map.
    final Map<String, Map<int, TransferableItem>> aggregatedItems = {};


    for (final stock in stockMaps) {
      final productId = stock['urun_id'] as int;
      final productInfo = productDetails[productId];
      if (productInfo == null) continue;

      final pallet = stock['pallet_barcode'] as String?;
      final expiryDate = stock['expiry_date'] != null ? DateTime.tryParse(stock['expiry_date']) : null;
      // Paletsiz ürünler için `urun_id`'yi anahtar olarak kullan.
      final containerId = pallet ?? 'box_$productId';

      // Gruplama için anahtar: Palet veya Kutu ID'si
      final groupingKey = containerId;

      // Toplama map'ini hazırla
      aggregatedItems.putIfAbsent(groupingKey, () => {});

      if (aggregatedItems[groupingKey]!.containsKey(productId)) {
        // Eğer ürün bu konteynerde zaten varsa, miktarını artır.
        final existingItem = aggregatedItems[groupingKey]![productId]!;
        aggregatedItems[groupingKey]![productId] = TransferableItem(
          product: existingItem.product,
          quantity: existingItem.quantity + (stock['quantity'] as num).toDouble(),
          sourcePalletBarcode: pallet,
          // Not: SKT'ler farklı olabileceğinden, burada ilk bulunanı koruyoruz.
          // Arayüzde SKT'ye göre ayırmadığımız için bu kabul edilebilir.
          expiryDate: existingItem.expiryDate,
        );
      } else {
        // Eğer ürün bu konteynerde ilk kez ekleniyorsa, yeni bir kalem oluştur.
        aggregatedItems[groupingKey]![productId] = TransferableItem(
          product: productInfo,
          quantity: (stock['quantity'] as num).toDouble(),
          sourcePalletBarcode: pallet,
          expiryDate: expiryDate,
        );
      }
    }

    // Toplanmış verileri `TransferableContainer` listesine dönüştür.
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

    debugPrint("Sonuç konteyner sayısı: ${result.length}");

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
  Future<MapEntry<String, int>?> findLocationByCode(String code) async {
    final db = await dbHelper.database;
    final cleanCode = code.toLowerCase().trim();

    if (cleanCode.contains('kabul') || cleanCode.contains('receiving') || cleanCode == '0' || cleanCode == '000') {
      return const MapEntry('000', 0);
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
      await db.update('satin_alma_siparis_fis', {'status': 3}, where: 'id = ?', whereArgs: [orderId]);
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

  /// GÜNCELLEME: Bu metod artık kullanılmıyor ve yerini _updateStockSmart'a bıraktı.
  /*
  Future<void> _updateStock(
    DatabaseExecutor txn,
    int productId,
    int? locationId,
    double quantityChange,
    String? palletId,
    String status,
    int? siparisId,
    DateTime? expiryDate,
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

    if (locationId == null || locationId == 0) {
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

    if (expiryDate == null) {
      whereParts.add('expiry_date IS NULL');
    } else {
      whereParts.add('expiry_date = ?');
      whereArgs.add(expiryDate.toIso8601String());
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
        'expiry_date': expiryDate?.toIso8601String(),
      });
    } else {
      debugPrint("ERROR: Kaynakta stok bulunamadı - urun_id: $productId, location_id: $locationId, status: $status, pallet: $palletId, siparis_id: $siparisId, expiry_date: ${expiryDate?.toIso8601String()}");
      throw Exception('Kaynakta stok bulunamadı veya düşülecek miktar yetersiz. Aranan: {urun_id: $productId, location_id: $locationId, status: $status, pallet: $palletId, siparis_id: $siparisId, expiry_date: ${expiryDate?.toIso8601String()}}');
    }
  }
  */

  // ANA GÜNCELLEME: Akıllı Stok Güncelleme Fonksiyonu
  // Bu fonksiyon, bir ürün için miktar değişikliğini (artırma/azaltma) FIFO'ya
  // (İlk Giren İlk Çıkar) göre yönetir. Miktar düşüşlerinde en eski son kullanma
  // tarihli stoktan başlar.
  Future<void> _updateStockSmart(
    DatabaseExecutor txn, {
    required int productId,
    required int? locationId,
    required double quantityChange,
    required String? palletId,
    required String status,
    required int? siparisId,
    // Düşürme işlemi için SKT'ye gerek yok, FIFO uygulanacak.
    // Ekleme işlemi için ise SKT zorunludur.
    DateTime? expiryDateForAddition,
  }) async {
    if (quantityChange == 0) return;

    final isDecrement = quantityChange < 0;

    if (isDecrement) {
      // --- Stok Düşürme Mantığı (FIFO) ---
      double remainingToDecrement = quantityChange.abs();

      // İlgili stokları SKT'ye göre (NULL'lar en sona) artan sırada çek.
      final stockEntries = await txn.query(
        'inventory_stock',
        where: 'urun_id = ? AND (location_id = ? OR (? IS NULL AND location_id IS NULL)) AND (pallet_barcode = ? OR (? IS NULL AND pallet_barcode IS NULL)) AND stock_status = ? AND (siparis_id = ? OR (? IS NULL AND siparis_id IS NULL))',
        whereArgs: [productId, locationId, locationId, palletId, palletId, status, siparisId, siparisId],
        orderBy: 'expiry_date ASC', // NULLS LAST by default in SQLite
      );

      if (stockEntries.isEmpty) {
        debugPrint("HATA: _updateStockSmart - Düşürme için kaynak stok bulunamadı.");
        throw Exception('Kaynakta stok bulunamadı. Ürün ID: $productId');
      }

      for (final stock in stockEntries) {
        final stockId = stock['id'] as int;
        final currentQty = (stock['quantity'] as num).toDouble();

        if (currentQty >= remainingToDecrement) {
          // Bu stok kalemi yeterli, miktarını azalt ve döngüyü bitir.
          final newQty = currentQty - remainingToDecrement;
          if (newQty > 0.001) {
            await txn.update('inventory_stock', {'quantity': newQty}, where: 'id = ?', whereArgs: [stockId]);
          } else {
            await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [stockId]);
          }
          remainingToDecrement = 0;
          break;
        } else {
          // Bu stok kalemi yeterli değil, tamamını sil ve kalanı bir sonrakinden düş.
          remainingToDecrement -= currentQty;
          await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [stockId]);
        }
      }

      if (remainingToDecrement > 0.001) {
        // Döngü bitti ama hala düşülecek miktar kaldıysa, stok yetersizdir.
        debugPrint("HATA: _updateStockSmart - Yetersiz stok. Kalan: $remainingToDecrement");
        throw Exception('Kaynakta yeterli stok bulunamadı. İstenen: ${quantityChange.abs()}, Eksik: $remainingToDecrement');
      }
    } else {
      // --- Stok Ekleme Mantığı ---
      if (expiryDateForAddition == null) {
        // Not: SKT'siz ürünler de olabilir, bu yüzden hata fırlatmak yerine null kabul edelim.
        // throw Exception('Stok ekleme işlemi için son kullanma tarihi (expiryDateForAddition) gereklidir.');
      }

      final expiryDateStr = expiryDateForAddition?.toIso8601String();

      // Tam olarak aynı özelliklere sahip bir stok kalemi var mı kontrol et.
      final existing = await txn.query(
        'inventory_stock',
        where: 'urun_id = ? AND (location_id = ? OR (? IS NULL AND location_id IS NULL)) AND (pallet_barcode = ? OR (? IS NULL AND pallet_barcode IS NULL)) AND stock_status = ? AND (siparis_id = ? OR (? IS NULL AND siparis_id IS NULL)) AND (expiry_date = ? OR (? IS NULL AND expiry_date IS NULL))',
        whereArgs: [productId, locationId, locationId, palletId, palletId, status, siparisId, siparisId, expiryDateStr, expiryDateStr],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Varsa, miktarını artır.
        final currentQty = (existing.first['quantity'] as num).toDouble();
        final newQty = currentQty + quantityChange;
        await txn.update(
          'inventory_stock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        // Yoksa, yeni bir stok kalemi oluştur.
        await txn.insert('inventory_stock', {
          'urun_id': productId,
          'location_id': locationId,
          'quantity': quantityChange,
          'pallet_barcode': palletId,
          'stock_status': status,
          'siparis_id': siparisId,
          'updated_at': DateTime.now().toIso8601String(),
          'expiry_date': expiryDateStr,
        });
      }
    }
  }
}
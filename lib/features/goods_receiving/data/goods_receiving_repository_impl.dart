import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/services/telegram_logger_service.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:dio/dio.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/constants/goods_receiving_constants.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;
  final SyncService syncService;

  GoodsReceivingRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
    required this.syncService,
  });

  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    await _saveGoodsReceiptLocally(payload);
  }

  Future<void> _saveGoodsReceiptLocally(GoodsReceiptPayload payload) async {
    final db = await dbHelper.database;

    // Items'ları delivery note'lara göre gruplandır
    final Map<String?, List<GoodsReceiptItemPayload>> deliveryNoteGroups = {};
    
    for (final item in payload.items) {
      // Item'daki delivery note varsa onu kullan, yoksa header'daki
      final deliveryNote = item.deliveryNoteNumber ?? payload.header.deliveryNoteNumber;
      deliveryNoteGroups.putIfAbsent(deliveryNote, () => []).add(item);
    }


    try {
      debugPrint('💾 _saveGoodsReceiptLocally BAŞLADI - ${deliveryNoteGroups.length} delivery note grubu');
      await db.transaction((txn) async {
        // Her delivery note grubu için ayrı goods_receipt kaydı oluştur
        for (final entry in deliveryNoteGroups.entries) {
          final deliveryNote = entry.key;
          final items = entry.value;
          
          
          // 1. ADIM: Bu grup için UNIQUE ID'Yİ AL
          final pendingOp = PendingOperation.create(
            type: PendingOperationType.goodsReceipt,
            data: "{}",
            createdAt: DateTime.now().toUtc(),
          );
          final String operationUniqueId = pendingOp.uniqueId;

          // 2. ADIM: Bu delivery note için GOODS RECEIPT KAYDINI OLUŞTUR
          final receiptHeaderData = {
            'operation_unique_id': operationUniqueId,
            'siparis_id': payload.header.siparisId,
            'invoice_number': payload.header.invoiceNumber,
            'delivery_note_number': deliveryNote, // Bu grubun delivery note'u
            'employee_id': payload.header.employeeId,
            'receipt_date': payload.header.receiptDate.toIso8601String(),
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
          
          // DEBUG: operation_unique_id kontrolü
          debugPrint('🔧 DEBUG: goods_receipt insert - operation_unique_id: $operationUniqueId');
          debugPrint('🔧 DEBUG: receiptHeaderData: $receiptHeaderData');

          // CRITICAL FIX: Verify database schema before insert
          try {
            final schemaCheck = await txn.rawQuery("PRAGMA table_info(goods_receipts)");
            final hasOperationUniqueId = schemaCheck.any((column) => column['name'] == 'operation_unique_id');
            debugPrint('🔧 SCHEMA CHECK: goods_receipts.operation_unique_id exists: $hasOperationUniqueId');

            if (!hasOperationUniqueId) {
              debugPrint('❌ CRITICAL: operation_unique_id column missing! Adding column...');
              await txn.execute('ALTER TABLE goods_receipts ADD COLUMN operation_unique_id TEXT');
            }
          } catch (e) {
            debugPrint('🔧 Schema check error: $e');
          }

          final receiptId = await txn.insert(DbTables.goodsReceipts, receiptHeaderData);
          debugPrint('🔧 DEBUG: goods_receipt inserted with ID: $receiptId');

          // 3. ADIM: Bu gruptaki items'ları kaydet
          final Map<int, String> itemStockUuids = {};
          final Map<int, String> itemUuids = {};

          for (var i = 0; i < items.length; i++) {
            final item = items[i];

            // Her item için UUID üret
            const uuid = Uuid();
            final stockUuid = uuid.v4();
            final itemUuid = uuid.v4();
            itemStockUuids[i] = stockUuid;
            itemUuids[i] = itemUuid;
            
            // DEBUG: item UUID kontrolü
            debugPrint('🔧 DEBUG: goods_receipt_item insert - item_uuid: $itemUuid');
            debugPrint('🔧 DEBUG: goods_receipt_item insert - operation_unique_id: $operationUniqueId');

            // CRITICAL FIX: Verify database schema for goods_receipt_items before insert
            try {
              final schemaCheck = await txn.rawQuery("PRAGMA table_info(goods_receipt_items)");
              final hasOperationUniqueId = schemaCheck.any((column) => column['name'] == 'operation_unique_id');
              final hasItemUuid = schemaCheck.any((column) => column['name'] == 'item_uuid');
              debugPrint('🔧 SCHEMA CHECK: goods_receipt_items.operation_unique_id exists: $hasOperationUniqueId');
              debugPrint('🔧 SCHEMA CHECK: goods_receipt_items.item_uuid exists: $hasItemUuid');

              if (!hasOperationUniqueId) {
                debugPrint('❌ CRITICAL: operation_unique_id column missing in goods_receipt_items! Adding column...');
                await txn.execute('ALTER TABLE goods_receipt_items ADD COLUMN operation_unique_id TEXT');
              }

              if (!hasItemUuid) {
                debugPrint('❌ CRITICAL: item_uuid column missing in goods_receipt_items! Adding column...');
                await txn.execute('ALTER TABLE goods_receipt_items ADD COLUMN item_uuid TEXT UNIQUE');
              }
            } catch (e) {
              debugPrint('🔧 goods_receipt_items schema check error: $e');
            }

            final itemData = {
              'receipt_id': receiptId,
              'operation_unique_id': operationUniqueId,
              'item_uuid': itemUuid,
              'urun_key': item.productId,
              'birim_key': item.birimKey,
              'quantity_received': item.quantity,
              'pallet_barcode': item.palletBarcode,
              'barcode': item.barcode,
              'expiry_date': item.expiryDate?.toIso8601String(),
              'free': item.isFree ? 1 : 0,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            };

            debugPrint('🔧 DEBUG: goods_receipt_item data: $itemData');

            try {
              final itemId = await txn.insert(DbTables.goodsReceiptItems, itemData);
              debugPrint('✅ DEBUG: goods_receipt_item inserted with ID: $itemId');
            } catch (insertError, stackTrace) {
              debugPrint('❌ CRITICAL ERROR: goods_receipt_item insert FAILED!');
              debugPrint('   Error: $insertError');
              debugPrint('   Item Data: $itemData');
              debugPrint('   Stack Trace: $stackTrace');

              // Log to database (ERROR level - saved to SQLite for manual review)
              final prefs = await SharedPreferences.getInstance();
              final employeeId = prefs.getInt('user_id');
              final employeeName = prefs.getString('user_name');

              await TelegramLoggerService.logError(
                'Goods Receipt Item Insert Failed',
                'Failed to insert goods_receipt_item to database: $insertError',
                stackTrace: stackTrace,
                context: {
                  'operation_unique_id': operationUniqueId,
                  'item_uuid': itemUuid,
                  'receipt_id': receiptId,
                  'product_id': item.productId,
                  'birim_key': item.birimKey,
                  'quantity': item.quantity,
                  'item_data': itemData.toString(),
                },
                employeeId: employeeId,
                employeeName: employeeName,
              );

              rethrow;
            }

            // KRITIK FIX: Offline çalışabilmek için mobilde de inventory_stock oluştur
            // Backend ile aynı UPSERT mantığı: Aynı ürün/birim/palet/SKT için AYNI KAYDI GÜNCELLE (3+4=7)
            try {

              // Mevcut stok kaydını bul (Backend ile aynı çift strateji)
              // KRITIK FIX: İki farklı strateji
              // 1. Sipariş bazlı mal kabul (siparis_id dolu): siparis_id ile grupla, goods_receipt_id KULLANMA
              // 2. Serbest mal kabul (siparis_id NULL): goods_receipt_id ile grupla, siparis_id KULLANMA
              final String consolidationCondition;
              if (payload.header.siparisId != null) {
                // Sipariş bazlı: siparis_id kontrolü yap, goods_receipt_id'ye bakma
                consolidationCondition = 'AND siparis_id = ?';
              } else {
                // Serbest mal kabul: goods_receipt_id kontrolü yap
                consolidationCondition = 'AND goods_receipt_id = ?';
              }

              final existingStockQuery = '''
                SELECT id, quantity FROM ${DbTables.inventoryStock}
                WHERE urun_key = ?
                  AND stock_status = 'receiving'
                  ${item.birimKey != null ? 'AND birim_key = ?' : 'AND birim_key IS NULL'}
                  ${item.palletBarcode != null ? 'AND pallet_barcode = ?' : 'AND pallet_barcode IS NULL'}
                  ${item.expiryDate != null ? 'AND expiry_date = ?' : 'AND expiry_date IS NULL'}
                  $consolidationCondition
                LIMIT 1
              ''';

              final queryArgs = <dynamic>[item.productId];
              if (item.birimKey != null) queryArgs.add(item.birimKey);
              if (item.palletBarcode != null) queryArgs.add(item.palletBarcode);
              if (item.expiryDate != null) queryArgs.add(item.expiryDate?.toIso8601String());
              // Strateji: siparis_id varsa onu ekle, yoksa goods_receipt_id ekle
              if (payload.header.siparisId != null) {
                queryArgs.add(payload.header.siparisId);
              } else {
                queryArgs.add(receiptId);
              }

              final existingStock = await txn.query(
                DbTables.inventoryStock,
                where: '''
                  urun_key = ?
                  AND stock_status = 'receiving'
                  ${item.birimKey != null ? 'AND birim_key = ?' : 'AND birim_key IS NULL'}
                  ${item.palletBarcode != null ? 'AND pallet_barcode = ?' : 'AND pallet_barcode IS NULL'}
                  ${item.expiryDate != null ? 'AND expiry_date = ?' : 'AND expiry_date IS NULL'}
                  $consolidationCondition
                ''',
                whereArgs: queryArgs,
                limit: 1,
              );

              if (existingStock.isNotEmpty) {
                // MEVCUT KAYIT VAR - UPSERT (3+4=7)
                final existingId = existingStock.first['id'] as int;
                final existingQty = (existingStock.first['quantity'] as num).toDouble();
                final newQty = existingQty + item.quantity;

                await txn.update(
                  DbTables.inventoryStock,
                  {
                    'quantity': newQty,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                  where: 'id = ?',
                  whereArgs: [existingId],
                );

                debugPrint('✅ DEBUG: inventory_stock UPDATED - ID: $existingId, Old: $existingQty, New: $newQty (stock_uuid: $stockUuid)');
              } else {
                // YENİ KAYIT OLUŞTUR
                // NOT: warehouse_code kolonu mobil database'de yok - backend sync sırasında eklenecek
                final inventoryStockData = <String, dynamic>{
                  'stock_uuid': stockUuid,
                  'urun_key': item.productId,
                  'birim_key': item.birimKey,
                  'location_id': null,
                  'siparis_id': payload.header.siparisId, // Sipariş bazlı mal kabullerde dolu, serbest mal kabullerde NULL
                  'quantity': item.quantity,
                  'pallet_barcode': item.palletBarcode,
                  'stock_status': 'receiving',
                  'expiry_date': item.expiryDate?.toIso8601String(),
                  // KRITIK FIX: İki strateji
                  // 1. Sipariş bazlı mal kabul (siparis_id dolu): goods_receipt_id NULL -> Aynı sipariş için farklı irsaliyeler BİRLEŞİR (3+4=7)
                  // 2. Serbest mal kabul (siparis_id NULL): goods_receipt_id dolu -> Farklı irsaliyeler AYRI KALIR (3, 4 ayrı satırlar)
                  // 3. Transfer sonrası (her ikisi NULL): Tam konsolidasyon
                  'goods_receipt_id': payload.header.siparisId == null ? receiptId : null,
                  'created_at': DateTime.now().toUtc().toIso8601String(),
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                };

                await txn.insert(DbTables.inventoryStock, inventoryStockData);
                debugPrint('✅ DEBUG: inventory_stock CREATED - quantity: ${item.quantity} (stock_uuid: $stockUuid)');
              }
            } catch (stockError, stackTrace) {
              debugPrint('❌ ERROR: inventory_stock operation failed: $stockError');
              debugPrint('   Stack Trace: $stackTrace');
              // Inventory_stock oluşturulamazsa da mal kabul işlemi devam eder
              // Backend senkronizasyonu sırasında düzeltilecek
            }
          }

          // 4. ADIM: Bu grup için enriched data oluştur ve pending operation ekle
          final groupPayload = GoodsReceiptPayload(
            header: GoodsReceiptHeader(
              siparisId: payload.header.siparisId,
              invoiceNumber: payload.header.invoiceNumber,
              deliveryNoteNumber: deliveryNote,
              employeeId: payload.header.employeeId,
              receiptDate: payload.header.receiptDate,
            ),
            items: items,
          );
          
          final enrichedData = await _createEnrichedGoodsReceiptData(txn, groupPayload, itemStockUuids, itemUuids);
          enrichedData['operation_unique_id'] = operationUniqueId;

          final pendingOpForSync = PendingOperation.create(
            type: PendingOperationType.goodsReceipt,
            data: jsonEncode(enrichedData),
            createdAt: DateTime.now().toUtc(),
          );
          
          final finalPendingOp = PendingOperation(
            id: pendingOpForSync.id,
            uniqueId: operationUniqueId,
            type: pendingOpForSync.type,
            data: pendingOpForSync.data,
            status: pendingOpForSync.status,
            createdAt: pendingOpForSync.createdAt,
            errorMessage: pendingOpForSync.errorMessage,
          );
          await txn.insert(DbTables.pendingOperations, finalPendingOp.toDbMap());
        }

        // 5. ADIM: Sipariş durumunu kontrol et (sadece bir kez)
        if (payload.header.siparisId != null) {
          await _checkAndUpdateOrderStatus(txn, payload.header.siparisId!);
        }
      });

      debugPrint('✅ _saveGoodsReceiptLocally TAMAMLANDI - Başarıyla kaydedildi');
    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR: _saveGoodsReceiptLocally FAILED!');
      debugPrint('   Error: $e');
      debugPrint('   Stack Trace: $stackTrace');

      // Log to database (ERROR level - saved to SQLite for manual review)
      try {
        final prefs = await SharedPreferences.getInstance();
        final employeeId = prefs.getInt('user_id');
        final employeeName = prefs.getString('user_name');

        await TelegramLoggerService.logError(
          'Goods Receipt Save Failed',
          'Failed to save goods receipt to local database: $e',
          stackTrace: stackTrace,
          context: {
            'siparis_id': payload.header.siparisId,
            'delivery_note': payload.header.deliveryNoteNumber,
            'items_count': payload.items.length,
            'delivery_note_groups': deliveryNoteGroups.length,
          },
          employeeId: employeeId,
          employeeName: employeeName,
        );
      } catch (logError) {
        debugPrint('⚠️ Failed to log error: $logError');
      }

      throw Exception("Lokal veritabanına kaydederken bir hata oluştu: $e");
    }
  }

  Future<Map<String, dynamic>> _createEnrichedGoodsReceiptData(Transaction txn, GoodsReceiptPayload payload, Map<int, String> itemStockUuids, Map<int, String> itemUuids) async {
    final apiData = payload.toApiJson();

    if (payload.header.siparisId != null) {
      final poResult = await txn.query(
        DbTables.orders,
        columns: [DbColumns.ordersFisno],
        where: '${DbColumns.id} = ?',
        whereArgs: [payload.header.siparisId],
        limit: 1,
      );
      if (poResult.isNotEmpty) {
        apiData['header']['fisno'] = poResult.first[DbColumns.ordersFisno];
      }
    }

    final enrichedItems = <Map<String, dynamic>>[];
    if (payload.items.isNotEmpty) {
      for (var i = 0; i < payload.items.length; i++) {
        final item = payload.items[i];
        final itemData = item.toJson();
        
        // KRITIK FIX: Önceden üretilen Stock UUID ve item UUID'yi payload'a ekle
        final stockUuid = itemStockUuids[i];
        if (stockUuid != null) {
          itemData['stock_uuid'] = stockUuid;
        }

        final itemUuid = itemUuids[i];
        if (itemUuid != null) {
          itemData['item_uuid'] = itemUuid;
        }
        
        final productResult = await txn.query(
          DbTables.products,
          columns: [DbColumns.productsName, DbColumns.productsCode],
          where: '${DbColumns.productsId} = ?',
          whereArgs: [item.productId],
          limit: 1,
        );
        if (productResult.isNotEmpty) {
          itemData['product_name'] = productResult.first[DbColumns.productsName];
          itemData['product_code'] = productResult.first[DbColumns.productsCode];
        }
        enrichedItems.add(itemData);
      }
      apiData['items'] = enrichedItems;
    }
    return apiData;
  }


  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    final db = await dbHelper.database;
    final openOrdersMaps = await db.rawQuery('''
      SELECT DISTINCT
        o.${DbColumns.id},
        o.${DbColumns.ordersFisno},
        o.${DbColumns.ordersDate},
        o.${DbColumns.ordersNotes},
        o.${DbColumns.status},
        o.${DbColumns.createdAt},
        o.${DbColumns.updatedAt},
        t.${DbColumns.suppliersName} as supplierName
      FROM ${DbTables.orders} o
      LEFT JOIN ${DbTables.suppliers} t ON t.${DbColumns.suppliersCode} = o.${DbColumns.ordersSupplierCode}
      WHERE o.${DbColumns.status} IN (0, 1)
      ORDER BY o.${DbColumns.createdAt} DESC
    ''');
    return openOrdersMaps.map((orderMap) => PurchaseOrder.fromMap(orderMap)).toList();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    final db = await dbHelper.database;

    // FIX: Aynı ürün ve birim için miktarları toplama
    // Sunucuda aynı ürün ve birim için birden fazla satır olabiliyor
    final orderLines = await db.rawQuery('''
      SELECT
        MIN(sa.id) as id,
        sa.siparisler_id,
        u.UrunAdi,
        u.StokKodu,
        sa.kartkodu,
        u._key as urun_key,
        b.birimadi,
        b._key as birim_key,
        sa.sipbirimi,
        sa.sipbirimkey,
        SUM(sa.miktar) as miktar,
        MIN(sa.created_at) as created_at,
        MAX(sa.updated_at) as updated_at,
        sa.status,
        sa.turu,
        bark.barkod,
        u.UrunId,
        u.aktif,
        u._key as _key
      FROM siparis_ayrintili sa
      JOIN urunler u ON sa.kartkodu = u.StokKodu
      LEFT JOIN birimler b ON CAST(sa.sipbirimkey AS TEXT) = b._key
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE sa.siparisler_id = ? AND sa.turu = '1'
      GROUP BY u.StokKodu, sa.sipbirimkey, u._key, b._key
      ORDER BY MIN(sa.id)
    ''', [orderId]);

    final items = <PurchaseOrderItem>[];

    // Her sipariş satırı için zaten doğru birim bilgisi mevcut
    for (final line in orderLines) {
      final urunKey = line['urun_key'] as String?;
      final productCode = line['StokKodu'] as String?;

      if (urunKey == null || productCode == null) {
        continue;
      }

      // Alınan miktarı hesapla - operation_unique_id üzerinden JOIN yapıyoruz
      final receivedQuantityResult = await db.rawQuery('''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.operation_unique_id = gri.operation_unique_id
        WHERE gr.siparis_id = ? AND gri.urun_key = ?
      ''', [orderId, urunKey]);

      final receivedQuantity = receivedQuantityResult.isNotEmpty
          ? (receivedQuantityResult.first['total_received'] as num).toDouble()
          : 0.0;

      // Yerleştirme miktarını inventory_stock'tan hesaplayabiliriz
      final transferredQuantity = 0.0;

      // Enriched map oluştur - line zaten tüm JOIN bilgilerini içeriyor
      final enrichedMap = Map<String, dynamic>.from(line);
      enrichedMap['receivedQuantity'] = receivedQuantity;
      enrichedMap['transferredQuantity'] = transferredQuantity;

      items.add(PurchaseOrderItem.fromDb(enrichedMap));
    }

    return items;
  }

  @override
  Future<List<PurchaseOrder>> getReceivablePurchaseOrders() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DbTables.orders,
      where: '${DbColumns.status} = ?',
      whereArgs: [1], // Partially received
      orderBy: '${DbColumns.ordersDate} DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, int newStatus) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final poResult = await txn.query(DbTables.orders,
          columns: ['fisno'], where: 'id = ?', limit: 1, whereArgs: [orderId]);
      final fisno = poResult.isNotEmpty ? poResult.first[DbColumns.ordersFisno] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'fisno': fisno, 'status': newStatus}),
          createdAt: DateTime.now().toUtc());
      await txn.insert(DbTables.pendingOperations, pendingOp.toDbMap());

      await txn.update(
        DbTables.orders,
        {'status': newStatus},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  @override
  Future<void> markOrderAsComplete(int orderId) async {
    final db = await dbHelper.database;

    await db.transaction((txn) async {
      final poResult = await txn.query(
          DbTables.orders,
          columns: ['fisno'],
          where: 'id = ?',
          limit: 1,
          whereArgs: [orderId]
      );
      final fisno = poResult.isNotEmpty ? poResult.first[DbColumns.ordersFisno] as String? : null;

      final pendingOp = PendingOperation.create(
          type: PendingOperationType.forceCloseOrder,
          data: jsonEncode({'siparis_id': orderId, 'fisno': fisno}),
          createdAt: DateTime.now().toUtc()
      );
      await txn.insert(DbTables.pendingOperations, pendingOp.toDbMap());

      await txn.update(
        DbTables.orders,
        {'status': 2}, // Status 2: Manually Closed
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });

  }

  @override
  Future<List<ProductInfo>> searchProducts(String query, {int? orderId}) async {
    final db = await dbHelper.database;
    final stopwatch = Stopwatch()..start();

    final keywords = query
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (keywords.isEmpty) {
      return [];
    }

    debugPrint('🔍 Arama kelimeleri: $keywords');

    // Tek kelime ise barkod/stok kodu/ürün adı olabilir
    final isSingleKeyword = keywords.length == 1;

    if (isSingleKeyword) {
      final searchTerm = keywords.first;

      // Priority based search with UNION ALL (warehouse_count mantığı)
      final unifiedQuery = '''
        SELECT * FROM (
          -- 1. Exact barcode match (highest priority)
          SELECT
            1 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as _key,
            u.UrunAdi,
            u.UrunId,
            u.aktif
          FROM barkodlar b
          INNER JOIN birimler bi ON b._key_scf_stokkart_birimleri = bi._key
          INNER JOIN urunler u ON bi._key_scf_stokkart = u._key
          WHERE u.aktif = 1 AND b.barkod = ?

          UNION ALL

          -- 2. Barcode starts with
          SELECT
            2 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as _key,
            u.UrunAdi,
            u.UrunId,
            u.aktif
          FROM barkodlar b
          INNER JOIN birimler bi ON b._key_scf_stokkart_birimleri = bi._key
          INNER JOIN urunler u ON bi._key_scf_stokkart = u._key
          WHERE u.aktif = 1 AND b.barkod LIKE ? AND b.barkod != ?

          UNION ALL

          -- 3. Exact stock code match
          SELECT
            3 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as _key,
            u.UrunAdi,
            u.UrunId,
            u.aktif
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.StokKodu = ?

          UNION ALL

          -- 4. Stock code starts with
          SELECT
            4 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as _key,
            u.UrunAdi,
            u.UrunId,
            u.aktif
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.StokKodu LIKE ? AND u.StokKodu != ?

          UNION ALL

          -- 5. Product name starts with
          SELECT
            5 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as _key,
            u.UrunAdi,
            u.UrunId,
            u.aktif
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.UrunAdi LIKE ?

          UNION ALL

          -- 6. Product name contains (wildcard)
          SELECT
            6 as priority,
            b.barkod,
            bi._key as birim_key,
            bi.birimadi,
            u.StokKodu,
            u._key as _key,
            u.UrunAdi,
            u.UrunId,
            u.aktif
          FROM urunler u
          INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
          LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
          WHERE u.aktif = 1 AND u.UrunAdi LIKE ?
        )
        GROUP BY _key, birim_key
        ORDER BY priority ASC, UrunAdi ASC
        LIMIT 20
      ''';

      final searchResults = await db.rawQuery(unifiedQuery, [
        searchTerm,              // 1. Exact barcode
        '$searchTerm%',          // 2. Barcode starts with
        searchTerm,              // 2. Exclude exact match (already in #1)
        searchTerm,              // 3. Exact stock code
        '$searchTerm%',          // 4. Stock code starts with
        searchTerm,              // 4. Exclude exact match (already in #3)
        '$searchTerm%',          // 5. Product name starts with
        '%$searchTerm%',         // 6. Product name contains
      ]);

      stopwatch.stop();
      debugPrint('🔍 Birleşik arama: ${searchResults.length} sonuç, ${stopwatch.elapsedMilliseconds}ms');

      // Debug: İlk 3 sonucu göster
      for (int i = 0; i < searchResults.length && i < 3; i++) {
        final result = searchResults[i];
        debugPrint('   ${i+1}. ${result['UrunAdi']} (StokKodu: ${result['StokKodu']}, Barkod: ${result['barkod']}, Priority: ${result['priority']})');
      }

      return searchResults.map((map) => ProductInfo.fromDbMap(map)).toList();
    }

    // Çoklu kelime veya harf içeriyor - UrunAdi'nde ara
    final List<String> conditions = [];
    final List<String> params = [];

    for (final keyword in keywords) {
      conditions.add('u.UrunAdi LIKE ?');
      params.add('$keyword%');
    }

    final whereClause = conditions.join(' AND ');

    final simpleQuery = '''
      SELECT
        b.barkod,
        bi._key as birim_key,
        bi.birimadi,
        u.StokKodu,
        u._key as _key,
        u.UrunAdi,
        u.UrunId,
        u.aktif
      FROM urunler u
      INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
      LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
      WHERE u.aktif = 1 AND $whereClause
      ORDER BY u.UrunAdi ASC
      LIMIT 20
    ''';

    var searchResults = await db.rawQuery(simpleQuery, params);

    debugPrint('⚡ UrunAdi araması: ${searchResults.length} sonuç, ${stopwatch.elapsedMilliseconds}ms');

    // Yeterli sonuç yoksa genel arama
    if (searchResults.length < 5) {
      debugPrint('🔍 Genel arama yapılıyor...');

      final List<String> generalCond = [];
      final List<String> generalParams = [];

      for (final keyword in keywords) {
        generalCond.add('u.UrunAdi LIKE ?');
        generalParams.add('%$keyword%');
      }

      final generalWhere = generalCond.join(' AND ');

      final generalQuery = '''
        SELECT
          b.barkod,
          bi._key as birim_key,
          bi.birimadi,
          u.StokKodu,
          u._key as _key,
          u.UrunAdi,
          u.UrunId,
          u.aktif
        FROM urunler u
        INNER JOIN birimler bi ON bi._key_scf_stokkart = u._key
        LEFT JOIN barkodlar b ON b._key_scf_stokkart_birimleri = bi._key
        WHERE u.aktif = 1 AND $generalWhere
        ORDER BY u.UrunAdi ASC
        LIMIT 20
      ''';

      searchResults = await db.rawQuery(generalQuery, generalParams);
    }

    stopwatch.stop();
    debugPrint('🔍 Toplam: ${searchResults.length} sonuç, ${stopwatch.elapsedMilliseconds}ms');

    return searchResults.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<List<ProductInfo>> getAllActiveProducts() async {
    final db = await dbHelper.database;
    const query = '''
      SELECT
        u.*,
        MAX(bark.barkod) as barcode
      FROM urunler u
      LEFT JOIN birimler b ON u.StokKodu = b.StokKodu
      LEFT JOIN barkodlar bark ON b._key = bark._key_scf_stokkart_birimleri
      GROUP BY u.UrunId
      ORDER BY u.UrunAdi ASC
    ''';
    final maps = await db.rawQuery(query);
    return maps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  @override
  Future<ProductInfo?> findProductByExactMatch(String code) async {
    // Sadece barkod ile arama yap
    return findProductByBarcodeExactMatch(code);
  }

  @override
  Future<ProductInfo?> findProductByBarcodeExactMatch(String barcode, {int? orderId}) async {

    if (orderId != null) {
      // Sipariş bazlı arama: Tüm birimleri al ve önceliği siparişli birimlere ver
      final results = await dbHelper.getAllProductsByBarcode(barcode, orderId: orderId);
      
      if (results.isNotEmpty) {
        // Önce siparişli birim (source_type = 'order') varsa onu tercih et
        final orderUnits = results.where((r) => r['source_type'] == GoodsReceivingConstants.sourceTypeOrder);
        if (orderUnits.isNotEmpty) {
          final orderUnit = orderUnits.first;
          return ProductInfo.fromDbMap(orderUnit);
        }
        
        // Sipariş dışı birim varsa (source_type = 'out_of_order')
        final outOfOrderUnits = results.where((r) => r['source_type'] == GoodsReceivingConstants.sourceTypeOutOfOrder);
        if (outOfOrderUnits.isNotEmpty) {
          final outOfOrderUnit = outOfOrderUnits.first;
          return ProductInfo.fromDbMap(outOfOrderUnit);
        }
      }
    }

    // Genel arama (orderId null ise)
    final result = await dbHelper.getProductByBarcode(barcode); // orderId: null
    
    if (result != null) {
      return ProductInfo.fromDbMap(result);
    } else {
      return null;
    }
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    final db = await dbHelper.database;
    final maps = await db.query(DbTables.locations, where: '${DbColumns.isActive} = 1');
    return maps.map((map) => LocationInfo.fromMap(map)).toList();
  }

  Future<void> _checkAndUpdateOrderStatus(Transaction txn, int siparisId) async {
    final orderLines = await txn.rawQuery('''
      SELECT
        sol.${DbColumns.id},
        u.${DbColumns.productsId} as product_id,
        sol.${DbColumns.orderLinesQuantity} as ordered_quantity,
        COALESCE(SUM(gri.quantity_received), 0) as total_received
      FROM ${DbTables.orderLines} sol
      JOIN ${DbTables.products} u ON u.${DbColumns.productsCode} = sol.${DbColumns.orderLinesProductCode}
      LEFT JOIN ${DbTables.goodsReceiptItems} gri ON gri.urun_key = u._key
      LEFT JOIN ${DbTables.goodsReceipts} gr ON gr.operation_unique_id = gri.operation_unique_id AND gr.siparis_id = sol.${DbColumns.orderLinesOrderId}
      WHERE sol.${DbColumns.orderLinesOrderId} = ? AND sol.${DbColumns.orderLinesType} = '${DbColumns.orderLinesTypeValue}'
      GROUP BY sol.${DbColumns.id}, u.${DbColumns.productsId}, sol.${DbColumns.orderLinesQuantity}
    ''', [siparisId]);

    if (orderLines.isEmpty) return;

    bool anyLineReceived = false;

    for (final line in orderLines) {
      final receivedQty = (line['total_received'] as num).toDouble();

      if (receivedQty > 0) {
        anyLineReceived = true;
        break; // Herhangi bir satırda kabul varsa yeterli
      }
    }

    // Sadece kısmi kabul (status 1) veya hiç kabul yok (status 0) durumları
    int newStatus = anyLineReceived ? 1 : 0;

    await txn.update(
      DbTables.orders,
      {DbColumns.status: newStatus, DbColumns.updatedAt: DateTime.now().toUtc().toIso8601String()},
      where: '${DbColumns.id} = ?',
      whereArgs: [siparisId],
    );
  }

  // Duplicate functions removed - they already exist in the file

  /// DEBUG: Manuel olarak free değerini güncelle  
  @override
  Future<void> debugUpdateFreeValues(int orderId, String urunKey) async {
    await dbHelper.debugUpdateFreeValues(orderId, urunKey);
  }

  @override
  Future<List<ProductInfo>> getOutOfOrderReceiptItems(int orderId) async {
    final db = await dbHelper.database;
    
    // DEBUG: Önce bu sipariş için tüm receipt items'ları kontrol et - operation_unique_id ile JOIN
    await db.rawQuery('''
      SELECT gri.*, gr.siparis_id, gri.free
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.operation_unique_id = gri.operation_unique_id
      WHERE gr.siparis_id = ?
    ''', [orderId]);


    // DEBUG: Özellikle free=1 olan items'ları kontrol et - operation_unique_id ile JOIN
    await db.rawQuery('''
      SELECT gri.*, gr.siparis_id, gri.free
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.operation_unique_id = gri.operation_unique_id
      WHERE gr.siparis_id = ? AND gri.free = 1
    ''', [orderId]);
    
    
    
    // Sipariş dışı kabul edilen ürünleri al (free = 1) - operation_unique_id ile JOIN
    final outOfOrderMaps = await db.rawQuery('''
      SELECT
        u.*,
        u._key as product_key,
        u.UrunAdi as name,
        u.StokKodu as code,
        SUM(gri.quantity_received) as quantity_received,
        MAX(gri.free) as free,
        '${GoodsReceivingConstants.sourceTypeOutOfOrder}' as source_type
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.operation_unique_id = gri.operation_unique_id
      JOIN urunler u ON u._key = gri.urun_key
      WHERE gr.siparis_id = ? AND gri.free = 1
      GROUP BY u._key, u.UrunAdi, u.StokKodu
      ORDER BY MAX(gri.receipt_id) DESC
    ''', [orderId]);
    
    
    return outOfOrderMaps.map((map) => ProductInfo.fromDbMap(map)).toList();
  }

  // Inventory stock pending operation sync removed - normal table sync kullanılacak
}

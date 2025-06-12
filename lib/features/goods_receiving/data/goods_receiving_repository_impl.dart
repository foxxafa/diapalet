// lib/features/goods_receiving/data/goods_receiving_repository_impl.dart

import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;

  static const int malKabulLocationId = 1; // Sabit: Mal Kabul lokasyon ID'si

  GoodsReceivingRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  });

  /// --- ONLINE-FIRST DATA FETCHING METHODS ---

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    // Online-first: Önce API'den çekmeyi dene.
    if (await networkInfo.isConnected) {
      try {
        final response = await dio.get(ApiConfig.purchaseOrders);
        if (response.data is List) {
          final orders = (response.data as List)
              .map((json) => PurchaseOrder.fromJson(json))
              .toList();
          return orders;
        }
        throw Exception('Unexpected response format.');
      } catch (e) {
        debugPrint("API'den siparişler çekilemedi, lokale başvuruluyor: $e");
        // Hata olursa lokale fallback yap
        return _getOpenPurchaseOrdersFromLocal();
      }
    }
    // Offline: Lokal veritabanından çek.
    return _getOpenPurchaseOrdersFromLocal();
  }

  @override
  Future<List<ProductInfo>> searchProducts(String query) async {
    // Online-first: Önce API'den çekmeyi dene.
    if (await networkInfo.isConnected) {
      try {
        // Flask endpoint'i şu anda sorgu (query) desteklemiyor, tümünü çekiyor.
        // Gerekirse endpoint'e query parametresi eklenebilir.
        final response = await dio.get(ApiConfig.productsDropdown);
        if (response.data is List) {
          final products = (response.data as List)
              .map((json) => ProductInfo.fromJson(json))
              .toList();
          // Client-side filtreleme
          if (query.isNotEmpty) {
            return products.where((p) =>
            p.name.toLowerCase().contains(query.toLowerCase()) ||
                p.stockCode.toLowerCase().contains(query.toLowerCase())
            ).toList();
          }
          return products;
        }
        throw Exception('Unexpected response format.');
      } catch (e) {
        debugPrint("API'den ürünler çekilemedi, lokale başvuruluyor: $e");
        return _searchProductsFromLocal(query);
      }
    }
    // Offline: Lokal veritabanından çek.
    return _searchProductsFromLocal(query);
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    if (await networkInfo.isConnected) {
      try {
        final response = await dio.get(ApiConfig.purchaseOrderItems(orderId));
        if (response.data is List) {
          final items = (response.data as List)
              .map((json) => PurchaseOrderItem.fromJson(json))
              .toList();
          return items;
        }
        throw Exception('Unexpected response format.');
      } catch(e) {
        debugPrint("API'den sipariş kalemleri çekilemedi, lokale başvuruluyor: $e");
        return _getPurchaseOrderItemsFromLocal(orderId);
      }
    }
    return _getPurchaseOrderItemsFromLocal(orderId);
  }

  /// --- LOCAL DATABASE FALLBACK METHODS ---

  Future<List<PurchaseOrder>> _getOpenPurchaseOrdersFromLocal() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'satin_alma_siparis_fis',
      where: 'status = ?',
      whereArgs: [0],
      orderBy: 'tarih DESC',
    );
    return List.generate(maps.length, (i) => PurchaseOrder.fromMap(maps[i]));
  }

  Future<List<ProductInfo>> _searchProductsFromLocal(String query) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'urunler',
      where: 'UrunAdi LIKE ? OR StokKodu LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      limit: 50,
    );
    return List.generate(maps.length, (i) => ProductInfo.fromDbMap(maps[i]));
  }

  Future<List<PurchaseOrderItem>> _getPurchaseOrderItemsFromLocal(int orderId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        satir.id,
        satir.siparis_id,
        satir.urun_id,
        satir.miktar,
        satir.birim,
        urun.UrunAdi,
        urun.StokKodu
      FROM satin_alma_siparis_fis_satir AS satir
      JOIN urunler AS urun ON urun.UrunId = satir.urun_id
      WHERE satir.siparis_id = ?
    ''', [orderId]);
    return List.generate(maps.length, (i) => PurchaseOrderItem.fromDbJoinMap(maps[i]));
  }

  @override
  Future<List<LocationInfo>> getLocations() async {
    // Lokasyonlar genellikle sabit olduğu için lokalden çekmek daha performanslı olabilir.
    // İstenirse bu da online-first yapılabilir.
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('locations');
    return List.generate(maps.length, (i) => LocationInfo.fromMap(maps[i]));
  }


  /// --- DATA SAVING AND SYNC LOGIC ---

  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    final isConnected = await networkInfo.isConnected;

    if (isConnected) {
      try {
        debugPrint("Online mod: Mal kabul API'ye gönderiliyor...");
        // Flask sunucusu /v1/goods-receipts endpoint'ini bekliyor.
        await dio.post(ApiConfig.goodsReceipts, data: payload.toApiJson());

        // API'ye başarıyla kaydedildikten sonra, UI'ın güncel kalması için
        // lokal veritabanını da hemen güncelliyoruz.
        // Bir sonraki senkronizasyonda bu veri sunucudan tekrar gelecektir,
        // bu geçici bir UI güncellemesidir.
        await _updateLocalStockAndOrderStatus(payload);
        debugPrint("API çağrısı başarılı. Lokal stok ve sipariş durumu güncellendi.");

      } on DioException catch (e) {
        debugPrint("API çağrısı başarısız oldu: ${e.message}. İşlem sıraya alınıyor.");
        await _saveAsPendingOperation(payload);
      } catch (e) {
        debugPrint("Beklenmedik bir hata oluştu: $e. İşlem sıraya alınıyor.");
        await _saveAsPendingOperation(payload);
      }
    } else {
      debugPrint("Offline mod: İşlem senkronizasyon için sıraya alınıyor.");
      await _saveAsPendingOperation(payload);
    }
  }

  Future<void> _saveAsPendingOperation(GoodsReceiptPayload payload) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final operation = PendingOperation(
          id: 0,
          operationType: 'goods_receipt',
          // JSON'a çevrilmiş payload'u string olarak saklıyoruz.
          operationData: payload.toApiJson(),
          createdAt: DateTime.now(),
          status: 'pending',
          tableName: 'goods_receipts' // Bu alan bilgi amaçlıdır
      );
      await txn.insert('pending_operation', operation.toMapForDb());

      // Offline durumda da stokların lokalde güncel görünmesi için bu işlemi yapıyoruz.
      await _updateLocalStockAndOrderStatus(payload, txn: txn);
    });
    debugPrint("Mal kabul işlemi sıraya alındı ve lokal stok/sipariş durumu güncellendi.");
  }

  /// Hem lokal stoğu günceller hem de ilgili siparişin durumunu 'tamamlandı' yapar.
  Future<void> _updateLocalStockAndOrderStatus(GoodsReceiptPayload payload, {DatabaseExecutor? txn}) async {
    final db = txn ?? await dbHelper.database;

    // Stokları güncelle
    for (final item in payload.items) {
      await _upsertStock(
        db,
        urunId: item.urunId,
        locationId: malKabulLocationId,
        qtyChange: item.quantity,
        palletBarcode: item.palletBarcode,
      );
    }

    // Sipariş durumunu güncelle
    if (payload.header.siparisId != null) {
      await db.update(
        'satin_alma_siparis_fis',
        {'status': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [payload.header.siparisId],
      );
    }
  }

  Future<void> _upsertStock(
      DatabaseExecutor txn, {
        required int urunId,
        required int locationId,
        required double qtyChange,
        String? palletBarcode,
      }) async {
    final palletWhereClause = palletBarcode != null ? "pallet_barcode = ?" : "pallet_barcode IS NULL";
    final whereArgs = palletBarcode != null ? [urunId, locationId, palletBarcode] : [urunId, locationId];

    final List<Map<String, dynamic>> existing = await txn.query(
      'inventory_stock',
      where: 'urun_id = ? AND location_id = ? AND $palletWhereClause',
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

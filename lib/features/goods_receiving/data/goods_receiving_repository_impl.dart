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
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('locations');
    return List.generate(maps.length, (i) => LocationInfo.fromMap(maps[i]));
  }


  /// --- DATA SAVING (ONLINE-ONLY) ---

  @override
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload) async {
    // GÜNCELLEME: Sadece online modda çalışacak şekilde yeniden düzenlendi.
    // Lokal veritabanı işlemleri (offline'a kaydetme, lokal stoğu güncelleme)
    // geçici olarak kaldırıldı.
    if (!await networkInfo.isConnected) {
      throw Exception("İnternet bağlantısı yok. Mal Kabul işlemi yalnızca online modda yapılabilir.");
    }

    try {
      debugPrint("Online mod: Mal kabul API'ye gönderiliyor: ${jsonEncode(payload.toApiJson())}");
      final response = await dio.post(ApiConfig.goodsReceipts, data: payload.toApiJson());

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("Mal kabul işlemi başarıyla API'ye gönderildi.");
        // Lokal veritabanına dokunmuyoruz.
      } else {
        // API'den 2xx dışında bir status kodu gelirse hata fırlat.
        final errorDetail = response.data is Map ? response.data['error'] : response.data;
        debugPrint("API Hatası: Sunucu ${response.statusCode} koduyla yanıt verdi. Yanıt: $errorDetail");
        throw Exception("Sunucu hatası (${response.statusCode}): $errorDetail");
      }
    } on DioException catch (e) {
      // Dio kaynaklı hataları (network, timeout vb.) yakala ve daha anlaşılır bir hata fırlat.
      final errorDetail = e.response?.data is Map ? e.response?.data['error'] : e.response?.data;
      debugPrint("Dio Hatası: ${e.message}. Sunucu Yanıtı: $errorDetail");
      throw Exception("Ağ hatası: Sunucuya ulaşılamadı. Detay: ${errorDetail ?? e.message}");
    } catch (e) {
      // Diğer beklenmedik hataları yakala.
      debugPrint("Beklenmedik bir hata oluştu: $e");
      throw Exception("İşlem sırasında beklenmedik bir hata oluştu: $e");
    }
  }
}


// features/goods_receiving/data/goods_receiving_composite_repository.dart
// Bu dosya GoodsReceivingRepository arayüzünü implemente eder.
// Gerçekte adı GoodsReceivingRepositoryImpl olabilir.

import 'package:flutter/foundation.dart';
import '../../../core/network/network_info.dart'; // NetworkInfo'yu import et
import '../domain/entities/goods_receipt_entities.dart';
import '../domain/entities/product_info.dart';
import '../domain/repositories/goods_receiving_repository.dart';
import './local/goods_receiving_local_service.dart';
import './remote/goods_receiving_api_service.dart';

class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final GoodsReceivingLocalDataSource localDataSource;
  final GoodsReceivingRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  GoodsReceivingRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
    required this.networkInfo,
  });

  @override
  Future<List<String>> getInvoices() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchInvoices();
      } catch (e) {
        debugPrint("API getInvoices error: $e. Returning empty list.");
        return []; // Veya lokal cache'den
      }
    }
    // Offline: Lokal cache'den veya boş liste
    debugPrint("Offline: Cannot fetch invoices from API. Returning empty list.");
    return [];
  }

  @override
  Future<List<String>> getPalletsForDropdown() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchPalletsForDropdown();
      } catch (e) {
        debugPrint("API getPalletsForDropdown error: $e. Returning empty list.");
        return [];
      }
    }
    debugPrint("Offline: Cannot fetch pallets from API. Returning empty list.");
    return [];
  }

  @override
  Future<List<String>> getBoxesForDropdown() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchBoxesForDropdown();
      } catch (e) {
        debugPrint("API getBoxesForDropdown error: $e. Returning empty list.");
        return [];
      }
    }
    debugPrint("Offline: Cannot fetch boxes from API. Returning empty list.");
    return [];
  }

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    if (await networkInfo.isConnected) {
      try {
        // API'den ürünleri çek ve lokalde de sakla/güncelle (opsiyonel)
        final products = await remoteDataSource.fetchProductsForDropdown();
        // for (var product in products) {
        //   await localDataSource.saveProductInfo(product); // Eğer lokal product tablonuz varsa
        // }
        return products;
      } catch (e) {
        debugPrint("API getProductsForDropdown error: $e. Trying local.");
        // return await localDataSource.getAllProductInfos(); // Lokal cache'den
        return [];
      }
    }
    // Offline: Lokal cache'den ürünleri getir
    debugPrint("Offline: Fetching products from local storage (not implemented in this example).");
    // return await localDataSource.getAllProductInfos();
    return [];
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    if (await networkInfo.isConnected) {
      try {
        bool apiSuccess = await remoteDataSource.sendGoodsReceipt(header, items);
        if (apiSuccess) {
          header.synced = 1; // API'ye gönderildi olarak işaretle
          final localId = await localDataSource.saveGoodsReceipt(header, items);
          debugPrint("Goods Receipt (id: $localId) recorded and synced to API.");
          return localId;
        } else {
          // API'ye gönderim başarısızsa, senkronize edilmedi olarak kaydet
          header.synced = 0;
          final localId = await localDataSource.saveGoodsReceipt(header, items);
          debugPrint("Goods Receipt (id: $localId) failed to sync to API, saved locally.");
          return localId;
        }
      } catch (e) {
        // API hatası durumunda senkronize edilmedi olarak kaydet
        debugPrint("API error during saveGoodsReceipt: $e. Saving locally.");
        header.synced = 0;
        final localId = await localDataSource.saveGoodsReceipt(header, items);
        return localId;
      }
    } else {
      // Offline ise, senkronize edilmedi olarak kaydet
      header.synced = 0;
      final localId = await localDataSource.saveGoodsReceipt(header, items);
      debugPrint("Offline: Goods Receipt (id: $localId) saved locally.");
      return localId;
    }
  }

  @override
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts() async {
    return await localDataSource.getUnsyncedGoodsReceipts();
  }

  @override
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId) async {
    return await localDataSource.getItemsForGoodsReceipt(receiptId);
  }

  @override
  Future<void> markGoodsReceiptAsSynced(int receiptId) async {
    await localDataSource.markGoodsReceiptAsSynced(receiptId);
  }

  // Senkronizasyon metodu
  Future<void> synchronizePendingGoodsReceipts() async {
    if (await networkInfo.isConnected) {
      debugPrint("Starting synchronization of pending goods receipts...");
      final unsyncedReceipts = await getUnsyncedGoodsReceipts();
      if (unsyncedReceipts.isEmpty) {
        debugPrint("No unsynced goods receipts to synchronize.");
        return;
      }
      debugPrint("Found ${unsyncedReceipts.length} unsynced goods receipts.");

      for (var header in unsyncedReceipts) {
        if (header.id == null) continue; // Geçersiz kayıtları atla

        final items = await getItemsForGoodsReceipt(header.id!);
        if (items.isEmpty && header.id != null) { // Kalemsiz başlıklar için özel durum (isteğe bağlı)
          debugPrint("Warning: Goods receipt header id ${header.id} has no items. Skipping API send or handle as needed.");
          // Belki sadece başlığı senkronize et veya logla
          // await markGoodsReceiptAsSynced(header.id!);
          continue;
        }

        try {
          bool success = await remoteDataSource.sendGoodsReceipt(header, items);
          if (success) {
            await markGoodsReceiptAsSynced(header.id!);
            debugPrint("Successfully synced goods receipt id: ${header.id}");
          } else {
            debugPrint("Failed to sync goods receipt id: ${header.id} (API returned false).");
          }
        } catch (e) {
          debugPrint("Error syncing goods receipt id: ${header.id}. Error: $e");
        }
      }
      debugPrint("Goods receipts synchronization process finished.");
    } else {
      debugPrint("Cannot synchronize goods receipts, no network connection.");
    }
  }
}

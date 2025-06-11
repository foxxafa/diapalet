// lib/features/goods_receiving/data/goods_receiving_composite_repository.dart
import 'package:flutter/foundation.dart';
import '../../../core/network/network_info.dart';
import '../domain/entities/goods_receipt_entities.dart';
import '../domain/entities/product_info.dart';
import '../domain/entities/purchase_order.dart';
import '../domain/entities/purchase_order_item.dart';
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
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    // Always fetch from the local database first for a consistent offline-first experience.
    // The SyncService is responsible for keeping this data up-to-date.
    try {
      return await localDataSource.getOpenPurchaseOrders();
    } catch (e) {
      debugPrint("Error fetching open purchase orders from local DB: $e");
      // Optionally, try to fetch from remote as a fallback if local fails,
      // but the primary strategy is to rely on the synced local data.
      if (await networkInfo.isConnected) {
        try {
          return await remoteDataSource.fetchOpenPurchaseOrders();
        } catch (remoteError) {
          debugPrint("Also failed to fetch from remote: $remoteError");
          return [];
        }
      }
      return [];
    }
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    // Similar to orders, fetch items from the local DB.
    try {
      return await localDataSource.getPurchaseOrderItems(orderId);
    } catch (e) {
      debugPrint("Error fetching purchase order items from local DB for order $orderId: $e");
       if (await networkInfo.isConnected) {
        try {
          return await remoteDataSource.fetchPurchaseOrderItems(orderId);
        } catch (remoteError) {
          debugPrint("Also failed to fetch items from remote: $remoteError");
          return [];
        }
      }
      return [];
    }
  }

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    // Products should be available offline from the master data sync.
    try {
      return await localDataSource.getProductsForDropdown();
    } catch (e) {
      debugPrint("Could not fetch products from local DB: $e");
      return [];
    }
  }

  @override
  Future<bool> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    // The location is now fixed to "MAL KABUL", ID 1.
    // We modify the items here to ensure they all point to the correct location.
    final updatedItems = items.map((item) => item.copyWith(locationId: 1)).toList();

    if (await networkInfo.isConnected) {
      // ONLINE MODE
      try {
        debugPrint("Online mode: Sending goods receipt to API and then saving locally.");
        // 1. Send to remote API first. If it fails, we don't proceed.
        bool apiSuccess = await remoteDataSource.sendGoodsReceipt(header, updatedItems);
        
        if (apiSuccess) {
          // 2. If API call is successful, save the same data to the local DB for consistency.
          // The local save also handles updating the local inventory stock.
          await localDataSource.saveGoodsReceiptToLocalDB(header, updatedItems);
          debugPrint("Successfully sent to API and saved locally.");
          return true;
        } else {
          // If the API call fails, we treat it as an offline scenario and queue it.
          debugPrint("API call failed. Switching to offline mode and queueing the operation.");
          await localDataSource.queueGoodsReceiptForSync(header, updatedItems);
          return false; // Indicate that it was not successful in real-time
        }
      } catch (e) {
        debugPrint("Error during online saveGoodsReceipt: $e. Queueing operation.");
        await localDataSource.queueGoodsReceiptForSync(header, updatedItems);
        return false; // Indicate that it was not successful in real-time
      }
    } else {
      // OFFLINE MODE
      debugPrint("Offline mode: Queueing goods receipt for later sync.");
      // Just add the operation to the pending queue.
      // No local stock updates happen here; the server will be the source of truth
      // once the operation is synced.
      await localDataSource.queueGoodsReceiptForSync(header, updatedItems);
      return true; // From the user's perspective, the operation was accepted.
    }
  }
}

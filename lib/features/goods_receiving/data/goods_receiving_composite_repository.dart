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
import '../domain/entities/location_info.dart';

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
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchOpenPurchaseOrders();
      } catch (e) {
        debugPrint("API getOpenPurchaseOrders error: $e. Falling back to local.");
        return await localDataSource.getOpenPurchaseOrders();
      }
    }
    return await localDataSource.getOpenPurchaseOrders();
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchPurchaseOrderItems(orderId);
      } catch (e) {
        debugPrint("API getPurchaseOrderItems error: $e. Falling back to local.");
        return await localDataSource.getPurchaseOrderItems(orderId);
      }
    }
    return await localDataSource.getPurchaseOrderItems(orderId);
  }
  
  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    // This data should primarily come from the local DB, which is kept in sync.
    return localDataSource.getProductsForDropdown();
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    // Per requirements, all goods receipts go to a fixed "MAL KABUL" location (ID=1)
    final updatedItems = items.map((item) => item.copyWith(locationId: 1)).toList();
    
    if (await networkInfo.isConnected) {
      try {
        bool apiSuccess = await remoteDataSource.sendGoodsReceipt(header, updatedItems);
        if (apiSuccess) {
          // ONLINE: API call was successful. Save to local DB but DO NOT create a pending operation.
          debugPrint("Online save successful. Saving to local DB without pending op.");
          final syncedHeader = header.copyWith(synced: 1);
          return await localDataSource.saveGoodsReceipt(syncedHeader, updatedItems, createPendingOperation: false);
        } else {
          // ONLINE but API failed (e.g., validation). Save to local and create pending op.
          debugPrint("Online save failed at API level. Saving to local DB WITH pending op.");
          return await localDataSource.saveGoodsReceipt(header, updatedItems, createPendingOperation: true);
        }
      } catch (e) {
        // ONLINE but exception occurred. Save to local and create pending op.
        debugPrint("Exception during online save. Saving to local DB WITH pending op. Error: $e");
        return await localDataSource.saveGoodsReceipt(header, updatedItems, createPendingOperation: true);
      }
    } else {
      // OFFLINE: Save to local DB and create a pending operation.
      debugPrint("Offline. Saving to local DB WITH pending op.");
      return await localDataSource.saveGoodsReceipt(header, updatedItems, createPendingOperation: true);
    }
  }

  // These methods are now unused due to the new SyncService logic,
  // but must be implemented to satisfy the repository interface.
  // They can be removed if the interface is updated.
  
  @override
  Future<List<String>> getInvoices() async {
    return localDataSource.getInvoiceNumbers();
  }
  
  @override
  Future<List<LocationInfo>> getLocationsForDropdown() async {
    return localDataSource.getLocationsForDropdown();
  }
  
  @override
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts() async {
    // This is now handled by SyncService. The UI should use SyncService to get pending operations.
    return localDataSource.getUnsyncedGoodsReceipts();
  }
  
  @override
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId) async {
    return localDataSource.getItemsForGoodsReceipt(receiptId);
  }
  
  @override
  Future<void> markGoodsReceiptAsSynced(int receiptId) async {
    // This is now handled by SyncService when it successfully syncs an item.
    await localDataSource.markGoodsReceiptAsSynced(receiptId);
  }
}

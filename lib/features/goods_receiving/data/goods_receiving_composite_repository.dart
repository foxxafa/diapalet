// lib/features/goods_receiving/data/goods_receiving_composite_repository.dart
import 'package:flutter/foundation.dart';

import '../../../core/network/network_info.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/entities/location_info.dart';
import '../../domain/entities/product_info.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_item.dart';
import '../../domain/repositories/goods_receiving_repository.dart';
import 'datasources/goods_receiving_local_datasource.dart';
import 'datasources/goods_receiving_remote_datasource.dart';

/// A repository that combines a remote and local data source.
/// It implements an offline-first strategy.
class GoodsReceivingRepositoryImpl implements GoodsReceivingRepository {
  final GoodsReceivingLocalDataSource localDataSource;
  final GoodsReceivingRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  GoodsReceivingRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.networkInfo,
  });

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    try {
      // Always fetch from remote, as this is for online mode.
      final remoteOrders = await remoteDataSource.getOpenPurchaseOrders();
      return remoteOrders;
    } catch (e) {
      // In a real-world scenario, you might want to handle network errors gracefully.
      throw Exception('Failed to fetch open purchase orders: $e');
    }
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    try {
      // Always fetch from remote for this specific feature.
      final remoteItems = await remoteDataSource.getPurchaseOrderItems(orderId);
      return remoteItems;
    } catch (e) {
      throw Exception('Failed to fetch purchase order items: $e');
    }
  }

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    try {
      final products = await remoteDataSource.getProductsForDropdown();
      return products;
    } catch (e) {
      throw Exception('Failed to fetch products: $e');
    }
  }

  @override
  Future<int> saveGoodsReceipt(
      GoodsReceipt receipt, List<GoodsReceiptItem> items) async {
    // For offline-first, we always save to the local database first.
    // The synchronization logic will handle uploading later.
    try {
      final receiptId = await localDataSource.saveGoodsReceipt(receipt, items);
      return receiptId;
    } catch (e) {
      throw Exception('Failed to save goods receipt locally: $e');
    }
  }

  // --- Methods that might need a more complex offline strategy ---

  @override
  Future<void> syncPendingGoodsReceipts() async {
    final unsyncedReceipts = await localDataSource.getUnsyncedGoodsReceipts();
    for (final receipt in unsyncedReceipts) {
      final items = await localDataSource.getItemsForGoodsReceipt(receipt.id!);
      try {
        final success = await remoteDataSource.postGoodsReceipt(receipt, items);
        if (success) {
          await localDataSource.markGoodsReceiptAsSynced(receipt.id!);
        }
      } catch (e) {
        // Handle sync error, maybe log it or retry later.
        print('Failed to sync receipt ${receipt.id}: $e');
      }
    }
  }

  @override
  Future<List<LocationInfo>> getLocationsForDropdown() async {
    return await remoteDataSource.getLocations();
  }

  // These methods are primarily for the sync process to check local data.
  @override
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts() {
    return localDataSource.getUnsyncedGoodsReceipts();
  }

  @override
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId) {
    return localDataSource.getItemsForGoodsReceipt(receiptId);
  }
}


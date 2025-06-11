// lib/features/goods_receiving/data/goods_receiving_composite_repository.dart
import 'package:diapalet/features/goods_receiving/data/local/goods_receiving_local_service.dart';
import 'package:diapalet/features/goods_receiving/data/remote/goods_receiving_api_service.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';

import '../../../core/network/network_info.dart';
import 'package:flutter/foundation.dart';

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
      final remoteOrders = await remoteDataSource.fetchOpenPurchaseOrders();
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
      final remoteItems = await remoteDataSource.fetchPurchaseOrderItems(orderId);
      return remoteItems;
    } catch (e) {
      throw Exception('Failed to fetch purchase order items: $e');
    }
  }

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    try {
      final products = await remoteDataSource.fetchProductsForDropdown();
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

  // This helper method is invoked by SyncService to push pending data when connectivity is restored.
  Future<void> syncPendingGoodsReceipts() async {
    final unsyncedReceipts = await localDataSource.getUnsyncedGoodsReceipts();
    for (final receipt in unsyncedReceipts) {
      final items = await localDataSource.getItemsForGoodsReceipt(receipt.id!);
      try {
        final success = await remoteDataSource.sendGoodsReceipt(receipt, items);
        if (success) {
          await localDataSource.markGoodsReceiptAsSynced(receipt.id!);
        }
      } catch (e) {
        // Handle sync error, maybe log it or retry later.
        debugPrint('Failed to sync receipt ${receipt.id}: $e');
      }
    }
  }

  @override
  Future<List<LocationInfo>> getLocationsForDropdown() async {
    return await remoteDataSource.fetchLocationsForDropdown();
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

  // Add implementation for getInvoices (online-first, fallback to local)
  @override
  Future<List<String>> getInvoices() async {
    try {
      if (await networkInfo.isConnected) {
        return await remoteDataSource.fetchInvoices();
      }
      // Offline fallback
      return await localDataSource.getInvoiceNumbers();
    } catch (e) {
      throw Exception('Failed to fetch invoices: $e');
    }
  }

  @override
  Future<void> markGoodsReceiptAsSynced(int receiptId) async {
    await localDataSource.markGoodsReceiptAsSynced(receiptId);
  }
}


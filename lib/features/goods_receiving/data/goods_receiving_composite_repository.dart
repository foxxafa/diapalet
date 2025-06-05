// lib/features/goods_receiving/data/goods_receiving_composite_repository.dart
import 'package:flutter/foundation.dart';
import '../../../core/network/network_info.dart';
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
        debugPrint("API getInvoices error: $e. Falling back to local.");
        return await localDataSource.getInvoiceNumbers();
      }
    }
    return await localDataSource.getInvoiceNumbers();
  }

  @override
  Future<List<String>> getPalletsForDropdown() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchPalletsForDropdown();
      } catch (e) {
        debugPrint("API getPalletsForDropdown error: $e. Falling back to local.");
        return await localDataSource.getPalletIds();
      }
    }
    return await localDataSource.getPalletIds();
  }

  @override
  Future<List<String>> getBoxesForDropdown() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchBoxesForDropdown();
      } catch (e) {
        debugPrint("API getBoxesForDropdown error: $e. Falling back to local.");
        return await localDataSource.getBoxIds();
      }
    }
    return await localDataSource.getBoxIds();
  }

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    if (await networkInfo.isConnected) {
      try {
        final products = await remoteDataSource.fetchProductsForDropdown();
        return products;
      } catch (e) {
        debugPrint("API getProductsForDropdown error: $e. Falling back to local.");
        return await localDataSource.getProductsForDropdown();
      }
    }
    return await localDataSource.getProductsForDropdown();
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    // Determine initial sync status based on network connectivity
    // The actual API call and sync status update will happen after local save.
    bool isOnline = await networkInfo.isConnected;
    GoodsReceipt headerToSave = header; // Use a mutable copy or ensure header.synced can be changed

    if (isOnline) {
      try {
        // Attempt to send to API first. The header ID is not known yet.
        // The remoteDataSource might need to handle a header without a local DB ID.
        // Or, save locally first, then send with ID.
        // For now, let's assume we try to send, then save locally with sync status.
        bool apiSuccess = await remoteDataSource.sendGoodsReceipt(header, items);
        if (apiSuccess) {
          headerToSave = GoodsReceipt(
            externalId: header.externalId,
            invoiceNumber: header.invoiceNumber,
            receiptDate: header.receiptDate,
            mode: header.mode,
            synced: 1, // Mark as synced if API call was successful
          );
          debugPrint("Goods Receipt data prepared for API, marked as synced.");
        } else {
          headerToSave = GoodsReceipt(
            externalId: header.externalId,
            invoiceNumber: header.invoiceNumber,
            receiptDate: header.receiptDate,
            mode: header.mode,
            synced: 0, // API call failed
          );
          debugPrint("Goods Receipt API call failed, marked as not synced.");
        }
      } catch (e) {
        debugPrint("API error during sendGoodsReceipt: $e. Marked as not synced.");
        headerToSave = GoodsReceipt(
          externalId: header.externalId,
          invoiceNumber: header.invoiceNumber,
          receiptDate: header.receiptDate,
          mode: header.mode,
          synced: 0, // API error
        );
      }
    } else {
      // Offline, mark as not synced
      headerToSave = GoodsReceipt(
        externalId: header.externalId,
        invoiceNumber: header.invoiceNumber,
        receiptDate: header.receiptDate,
        mode: header.mode,
        synced: 0,
      );
      debugPrint("Offline: Goods Receipt marked as not synced.");
    }

    // Save locally with the determined sync status
    final localId = await localDataSource.saveGoodsReceipt(headerToSave, items);
    debugPrint("Goods Receipt (local id: $localId) saved locally with synced status: ${headerToSave.synced}.");

    // Set initial location for all unique pallet/box IDs in this receipt to "MAL KABUL"
    final Set<String> uniquePalletOrBoxIds = items.map((item) => item.palletOrBoxId).toSet();
    for (String pId in uniquePalletOrBoxIds) {
      await localDataSource.setContainerInitialLocation(pId, "MAL KABUL", header.receiptDate);
    }

    return localId;
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
    // Optionally, if you need to re-send to API or confirm, you could do it here.
  }

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
        if (header.id == null) {
          debugPrint("Skipping sync for header with null ID (externalId: ${header.externalId}).");
          continue;
        }

        final items = await getItemsForGoodsReceipt(header.id!);
        // API expects items, if items list is empty for a valid header, decide how to handle.
        // For now, we'll attempt to send even if items are empty, API might reject or accept.
        // if (items.isEmpty) {
        //   debugPrint("Warning: Goods receipt header id ${header.id} has no items. Behavior depends on API.");
        // }

        try {
          // Pass the original header which might have a local ID and externalID
          bool success = await remoteDataSource.sendGoodsReceipt(header, items);
          if (success) {
            await markGoodsReceiptAsSynced(header.id!);
            debugPrint("Successfully synced goods receipt id: ${header.id} (externalId: ${header.externalId})");
          } else {
            debugPrint("Failed to sync goods receipt id: ${header.id} (externalId: ${header.externalId}) (API returned false).");
          }
        } catch (e) {
          debugPrint("Error syncing goods receipt id: ${header.id} (externalId: ${header.externalId}). Error: $e");
        }
      }
      debugPrint("Goods receipts synchronization process finished.");
    } else {
      debugPrint("Cannot synchronize goods receipts, no network connection.");
    }
  }
}

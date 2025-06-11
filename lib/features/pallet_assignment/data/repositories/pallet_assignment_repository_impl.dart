// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart


import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:flutter/foundation.dart';

class PalletAssignmentRepositoryImpl implements PalletAssignmentRepository {
  final PalletAssignmentLocalDataSource localDataSource;
  final PalletAssignmentRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  PalletAssignmentRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
    required this.networkInfo,
  });

  @override
  Future<List<LocationInfo>> getSourceLocations() async {
    // In a real-world scenario, you might fetch from remote, update local, then return from local.
    // For simplicity, we prioritize local data for offline-first approach.
    try {
        final localLocations = await localDataSource.getDistinctLocations();
        return localLocations;
    } catch (e) {
        debugPrint("Could not get locations from local data source: $e");
        return [];
    }
  }

  @override
  Future<List<LocationInfo>> getTargetLocations() async {
     try {
        final localLocations = await localDataSource.getDistinctLocations();
        return localLocations;
    } catch (e) {
        debugPrint("Could not get locations from local data source: $e");
        return [];
    }
  }

  @override
  Future<List<String>> getContainerIdsByLocation(int locationId) async {
    // Remote fetching can be added here if needed, for now it's offline-first
    return await localDataSource.getContainerIdsByLocation(locationId);
  }

  @override
  Future<List<ProductItem>> getContainerContent(String containerId) async {
    // Remote fetching can be added here if needed
    return await localDataSource.getContainerContent(containerId);
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
     // Remote fetching can be added here if needed
    return await localDataSource.getBoxesAtLocation(locationId);
  }

  @override
  Future<int> recordTransferOperation(
      TransferOperationHeader header, List<TransferItemDetail> items) async {
    // The logic to decide whether to push to remote immediately or queue it
    // is now handled by the SyncService. The local data source just saves
    // the operation to the pending queue.
    final localId = await localDataSource.saveTransferOperation(header, items);
    debugPrint("Transfer operation queued locally with temp ID: $localId.");
    return localId;
  }

  @override
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations() async {
    return await localDataSource.getUnsyncedTransferOperations();
  }

  @override
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId) async {
    return await localDataSource.getTransferItemsForOperation(operationId);
  }

  @override
  Future<void> markTransferOperationAsSynced(int operationId) async {
    await localDataSource.markTransferOperationAsSynced(operationId);
  }

  @override
  Future<void> synchronizePendingTransfers() async {
    if (await networkInfo.isConnected) {
      debugPrint("Starting synchronization of pending transfers...");
      final unsyncedOps = await getUnsyncedTransferOperations();
      if (unsyncedOps.isEmpty) {
        debugPrint("No unsynced transfers to synchronize.");
        return;
      }
      debugPrint("Found ${unsyncedOps.length} unsynced transfers.");

      for (var header in unsyncedOps) {
        if(header.id == null) {
          debugPrint("Skipping unsynced operation with null ID.");
          continue;
        }

        final items = await getTransferItemsForOperation(header.id!);
        try {
          bool success = await remoteDataSource.sendTransferOperation(header, items);
          if (success) {
            await markTransferOperationAsSynced(header.id!);
            debugPrint("Successfully synced transfer operation id: ${header.id}");
          } else {
            debugPrint("Failed to sync transfer operation id: ${header.id} (API returned false).");
          }
        } catch (e) {
          debugPrint("Error syncing transfer operation id: ${header.id}. Error: $e");
        }
      }
      debugPrint("Synchronization process finished.");
    } else {
      debugPrint("Cannot synchronize, no network connection.");
    }
  }
}

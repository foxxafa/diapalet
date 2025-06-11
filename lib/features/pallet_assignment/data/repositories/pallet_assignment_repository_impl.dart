// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart

import 'package:flutter/foundation.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import '../datasources/pallet_assignment_local_datasource.dart';
import '../datasources/pallet_assignment_remote_datasource.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';

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
    if (await networkInfo.isConnected) {
      try {
        debugPrint("ONLINE: Fetching source locations from remote.");
        final locations = await remoteDataSource.fetchSourceLocations();
        // Optional: Cache to local DB for offline access
        // await localDataSource.cacheLocations(locations);
        return locations;
      } catch (e) {
        debugPrint("ONLINE_ERROR: Failed to fetch remote source locations, falling back to local. Error: $e");
        return await localDataSource.getDistinctLocations();
      }
    } else {
      debugPrint("OFFLINE: Fetching source locations from local.");
      return await localDataSource.getDistinctLocations();
    }
  }

  @override
  Future<List<LocationInfo>> getTargetLocations() async {
    if (await networkInfo.isConnected) {
      try {
        debugPrint("ONLINE: Fetching target locations from remote.");
        final locations = await remoteDataSource.fetchTargetLocations();
        // Optional: Cache to local DB for offline access
        // await localDataSource.cacheLocations(locations);
        return locations;
      } catch (e) {
        debugPrint("ONLINE_ERROR: Failed to fetch remote target locations, falling back to local. Error: $e");
        return await localDataSource.getDistinctLocations();
      }
    } else {
      debugPrint("OFFLINE: Fetching target locations from local.");
      return await localDataSource.getDistinctLocations();
    }
  }

  @override
  Future<List<String>> getContainerIdsByLocation(int locationId, AssignmentMode mode) async {
    return await localDataSource.getContainerIdsByLocation(locationId, mode);
  }

  @override
  Future<List<ProductItem>> getContainerContent(String containerId, AssignmentMode mode) async {
    return await localDataSource.getContainerContent(containerId, mode);
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    return await localDataSource.getBoxesAtLocation(locationId);
  }

  @override
  Future<int> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    if (await networkInfo.isConnected) {
      try {
        final success = await remoteDataSource.sendTransferOperation(header, items);
        if (success) {
          debugPrint("Online transfer successful. Saving to local DB without pending op.");
          return await localDataSource.saveTransferOperation(header, items, createPendingOperation: false);
        } else {
          debugPrint("Online transfer failed at API level. Saving to local DB WITH pending op.");
          return await localDataSource.saveTransferOperation(header, items, createPendingOperation: true);
        }
      } catch (e) {
        debugPrint("Exception during online transfer. Saving to local DB WITH pending op. Error: $e");
        return await localDataSource.saveTransferOperation(header, items, createPendingOperation: true);
      }
    } else {
      debugPrint("Offline. Saving transfer to local DB WITH pending op.");
      return await localDataSource.saveTransferOperation(header, items, createPendingOperation: true);
    }
  }

  @override
  Future<void> synchronizePendingTransfers() async {
    // This is now handled by SyncService.
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
}

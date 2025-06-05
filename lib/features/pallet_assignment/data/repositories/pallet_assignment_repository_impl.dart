// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/network/network_info.dart'; // Assuming 'diapalet'

// Corrected entity and repository interface imports
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';

import '../datasources/pallet_assignment_local_datasource.dart';
import '../datasources/pallet_assignment_remote_datasource.dart';

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
  Future<List<String>> getSourceLocations() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchSourceLocations();
      } catch (e) {
        debugPrint("API getSourceLocations error: $e. Falling back to local.");
      }
    }

    final locations = await localDataSource.getDistinctContainerLocations();
    if (!locations.contains('MAL KABUL')) {
      locations.insert(0, 'MAL KABUL');
    } else {
      locations.remove('MAL KABUL');
      locations.insert(0, 'MAL KABUL');
    }
    return locations;
  }

  @override
  Future<List<String>> getTargetLocations() async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchTargetLocations();
      } catch (e) {
        debugPrint("API getTargetLocations error: $e. Falling back to local.");
      }
    }

    final locations = await localDataSource.getDistinctContainerLocations();
    if (!locations.contains('MAL KABUL')) {
      locations.insert(0, 'MAL KABUL');
    } else {
      locations.remove('MAL KABUL');
      locations.insert(0, 'MAL KABUL');
    }
    return locations;
  }

  @override
  Future<List<ProductItem>> getContentsOfContainer(String containerId, AssignmentMode mode) async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchContainerContents(containerId, mode);
      } catch (e) {
        debugPrint("API getContentsOfContainer error for $containerId: $e. Returning empty list.");
        return [];
      }
    } else {
      // Implement local fetching if needed
      debugPrint("No connection, cannot fetch container contents for $containerId from API. Returning empty list.");
      return [];
    }
  }

  @override
  Future<int> recordTransferOperation(
      TransferOperationHeader header, List<TransferItemDetail> items) async {
    TransferOperationHeader headerToSave = header; // Use a mutable copy for sync status

    if (await networkInfo.isConnected) {
      try {
        // Attempt to send to remote. If successful, mark as synced.
        // The header sent to remoteDataSource might not have an ID yet.
        // The items sent to remoteDataSource will have operationId = 0 (placeholder).
        // The remote API should handle this or the payload should be adjusted.
        bool remoteSuccess = await remoteDataSource.sendTransferOperation(header, items);
        if (remoteSuccess) {
          headerToSave = header.copyWith(synced: 1); // Mark as synced
          debugPrint("Transfer operation sent to API successfully and marked as synced.");
        } else {
          headerToSave = header.copyWith(synced: 0); // API call failed, mark as not synced
          debugPrint("Failed to send transfer operation to API. Marked as not synced.");
        }
      } catch (e) {
        debugPrint("Error sending transfer to remote API: $e. Marked as not synced.");
        headerToSave = header.copyWith(synced: 0); // Error, mark as not synced
      }
    } else {
      // Offline, mark as not synced
      headerToSave = header.copyWith(synced: 0);
      debugPrint("Offline. Transfer operation marked as not synced.");
    }

    // Always save to local data source.
    // localDataSource.saveTransferOperation will save the header and then items,
    // assigning the new header's ID to each item's operationId.
    final localId = await localDataSource.saveTransferOperation(headerToSave, items);
    debugPrint("Transfer operation saved locally with ID: $localId and synced status: ${headerToSave.synced}.");

    // Update container location locally
    await localDataSource.updateContainerLocation(
        headerToSave.containerId, headerToSave.targetLocation, headerToSave.transferDate);
    debugPrint("Local container location updated for ${headerToSave.containerId}.");

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
  Future<void> updateContainerLocation(String containerId, String newLocation) async {
    DateTime now = DateTime.now();
    await localDataSource.updateContainerLocation(containerId, newLocation, now);
    if (await networkInfo.isConnected) {
      try {
        // Placeholder for API call to update container location
        // await remoteDataSource.updateContainerLocationOnApi(containerId, newLocation);
        debugPrint("Container location update for $containerId potentially sent to API (mock).");
      } catch (e) {
        debugPrint("Failed to update container $containerId location on API: $e");
      }
    }
  }

  @override
  Future<String?> getContainerLocation(String containerId) async {
    return await localDataSource.getContainerLocation(containerId);
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
        // It's important that items here have the correct operationId (header.id)
        // which should be the case if they were fetched by getTransferItemsForOperation.

        try {
          // Send the header (which has its original local ID) and its items
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

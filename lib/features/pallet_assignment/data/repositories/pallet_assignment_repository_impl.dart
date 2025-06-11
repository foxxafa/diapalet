// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart

import 'package:flutter/foundation.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_assignment_repository.dart';
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
  Future<List<LocationInfo>> getSourceLocations() async {
    // Always fetch from local DB first for offline capability.
    // SyncService is responsible for keeping the location data fresh.
    try {
      return await localDataSource.getDistinctLocations();
    } catch (e) {
      debugPrint("Error fetching locations from local DB: $e. Returning empty list.");
      return [];
    }
  }

  @override
  Future<List<LocationInfo>> getTargetLocations() async {
    // In this design, source and target locations are the same list.
    return getSourceLocations();
  }

  @override
  Future<List<String>> getContainerIds(int locationId, AssignmentMode mode) async {
    // This must work offline, so we only query the local database.
    try {
      return await localDataSource.getContainerIdsByLocation(locationId, mode);
    } catch (e) {
      debugPrint("Error fetching container IDs from local DB: $e. Returning empty list.");
      return [];
    }
  }

  @override
  Future<List<ProductItem>> getContainerContents(String containerId, AssignmentMode mode) async {
    // This must also work offline.
    try {
      return await localDataSource.getContainerContent(containerId, mode);
    } catch (e) {
      debugPrint("Error fetching container contents from local DB: $e. Returning empty list.");
      return [];
    }
  }

  @override
  Future<bool> sendTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    if (await networkInfo.isConnected) {
      // ONLINE MODE
      try {
        debugPrint("Online mode: Sending transfer to API and then saving locally.");
        bool apiSuccess = await remoteDataSource.sendTransferOperation(header, items);

        if (apiSuccess) {
          // If the API call is successful, update the local DB to reflect the change.
          // This includes creating the transfer record and updating local inventory stock.
          await localDataSource.saveTransferOperationToLocalDB(header, items);
          debugPrint("Successfully sent transfer to API and updated local DB.");
          return true;
        } else {
          // If API fails, queue it.
          debugPrint("API call failed for transfer. Queueing operation.");
          await localDataSource.queueTransferOperationForSync(header, items);
          return false;
        }
      } catch (e) {
        debugPrint("Error during online sendTransferOperation: $e. Queueing operation.");
        await localDataSource.queueTransferOperationForSync(header, items);
        return false;
      }
    } else {
      // OFFLINE MODE
      debugPrint("Offline mode: Queueing transfer operation for later sync.");
      await localDataSource.queueTransferOperationForSync(header, items);
      return true; // Accepted for offline processing.
    }
  }
}

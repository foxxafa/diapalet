// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart


import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:flutter/material.dart'; // flutter/foundation.dart yerine material.dart debugPrint için

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
    // Öncelikli olarak API'den lokasyonları çekmeye çalış
    if (await networkInfo.isConnected) {
      try {
        final remoteLocations = await remoteDataSource.fetchSourceLocations();
        // API'den boş liste gelirse veya hata olursa yerel veriye düşebiliriz.
        // Şimdilik API'den geleni olduğu gibi döndürüyoruz. İsteğe bağlı olarak yerel ile birleştirilebilir.
        return remoteLocations;
      } catch (e) {
        debugPrint("API getSourceLocations error: $e. Falling back to local.");
        // Hata durumunda yerel veriye düş
      }
    }
    // Çevrimdışı veya API hatası durumunda yerel DB'den lokasyonları al
    final localLocations = await localDataSource.getDistinctLocations();
    // 'MAL KABUL' lokasyonunu listenin başına ekle (eğer varsa ve başta değilse)
    if (localLocations.contains('MAL KABUL')) {
      localLocations.remove('MAL KABUL');
    }
    localLocations.insert(0, 'MAL KABUL');
    return localLocations;
  }

  @override
  Future<List<String>> getTargetLocations() async {
    // Öncelikli olarak API'den lokasyonları çekmeye çalış
    if (await networkInfo.isConnected) {
      try {
        final remoteLocations = await remoteDataSource.fetchTargetLocations();
        return remoteLocations;
      } catch (e) {
        debugPrint("API getTargetLocations error: $e. Falling back to local.");
      }
    }
    // Çevrimdışı veya API hatası durumunda yerel DB'den lokasyonları al
    final localLocations = await localDataSource.getDistinctLocations();
    if (localLocations.contains('MAL KABUL')) {
      localLocations.remove('MAL KABUL');
    }
    localLocations.insert(0, 'MAL KABUL');
    return localLocations;
  }

  @override
  Future<List<String>> getProductIdsAtLocation(String location) async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchContainerIds(location, AssignmentMode.pallet);
      } catch (e) {
        debugPrint("API getProductIds error for $location: $e. Falling back to local.");
      }
    }
    return await localDataSource.getProductIdsByLocation(location);
  }

  @override
  Future<List<ProductItem>> getProductInfo(String productId, String location) async {
    // API'den içerik çekme mantığı eklenebilir, şimdilik sadece yerelden alıyoruz.
    // Kutu modunda, tek bir ürün ve onun toplam miktarı beklenir.
    // Palet modunda, birden fazla ürün ve miktarları olabilir.
    // Bu metod AssignmentMode'u doğrudan kullanmıyor gibi görünüyor, çünkü localDataSource.getContainerContents
    // sadece containerId alıyor. Bu, DB sorgusunun zaten palet/kutu ayrımı yapmadan tüm ürünleri getirdiği anlamına gelir.
    // Ekran tarafında AssignmentMode.kutu ise sadece ilk ürün gösteriliyor.
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchContainerContents(productId, AssignmentMode.pallet);
      } catch (e) {
        debugPrint("API getProductInfo error for $productId at $location: $e. Falling back to local.");
      }
    }
    return await localDataSource.getProductInfo(productId, location);
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(String location) async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchBoxesAtLocation(location);
      } catch (e) {
        debugPrint("API getBoxesAtLocation error for $location: $e. Falling back to local.");
      }
    }
    return await localDataSource.getBoxesAtLocation(location);
  }

  @override
  Future<int> recordTransferOperation(
      TransferOperationHeader header, List<TransferItemDetail> items) async {
    final bool isOnline = await networkInfo.isConnected;
    TransferOperationHeader headerToSave = header;

    if (isOnline) {
      try {
        bool remoteSuccess = await remoteDataSource.sendTransferOperation(header, items);
        if (remoteSuccess) {
          headerToSave = header.copyWith(synced: 1);
          debugPrint("Transfer operation sent to API successfully and marked as synced.");
        } else {
          headerToSave = header.copyWith(synced: 0);
          debugPrint("Failed to send transfer operation to API. Marked as not synced.");
        }
      } catch (e) {
        debugPrint("Error sending transfer to remote API: $e. Marked as not synced.");
        headerToSave = header.copyWith(synced: 0);
      }
    } else {
      headerToSave = header.copyWith(synced: 0);
      debugPrint("Offline. Transfer operation marked as not synced.");
    }

    // If we are online, skip checking local source box since it may not exist locally.
    final localId = await localDataSource.saveTransferOperation(
      headerToSave,
      items,
      checkSourceBox: !isOnline,
    );
    debugPrint("Transfer operation saved locally with ID: $localId and synced status: ${headerToSave.synced}.");

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

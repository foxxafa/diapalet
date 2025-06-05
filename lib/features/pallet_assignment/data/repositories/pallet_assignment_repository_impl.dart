// lib/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart


import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
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
    final localLocations = await localDataSource.getDistinctContainerLocations();
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
    final localLocations = await localDataSource.getDistinctContainerLocations();
    if (localLocations.contains('MAL KABUL')) {
      localLocations.remove('MAL KABUL');
    }
    localLocations.insert(0, 'MAL KABUL');
    return localLocations;
  }

  @override
  Future<List<String>> getContainerIdsAtLocation(String location, AssignmentMode mode) async {
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchContainerIds(location, mode);
      } catch (e) {
        debugPrint("API getContainerIds error for $location and mode ${mode.name}: $e. Falling back to local.");
      }
    }
    return await localDataSource.getContainerIdsByLocation(location, mode.name);
  }

  @override
  Future<List<ProductItem>> getContentsOfContainer(String containerId, AssignmentMode mode) async {
    // API'den içerik çekme mantığı eklenebilir, şimdilik sadece yerelden alıyoruz.
    // Kutu modunda, tek bir ürün ve onun toplam miktarı beklenir.
    // Palet modunda, birden fazla ürün ve miktarları olabilir.
    // Bu metod AssignmentMode'u doğrudan kullanmıyor gibi görünüyor, çünkü localDataSource.getContainerContents
    // sadece containerId alıyor. Bu, DB sorgusunun zaten palet/kutu ayrımı yapmadan tüm ürünleri getirdiği anlamına gelir.
    // Ekran tarafında AssignmentMode.kutu ise sadece ilk ürün gösteriliyor.
    if (await networkInfo.isConnected) {
      try {
        return await remoteDataSource.fetchContainerContents(containerId, mode);
      } catch (e) {
        debugPrint("API getContentsOfContainer error for $containerId and mode ${mode.name}: $e. Falling back to local.");
      }
    }
    return await localDataSource.getContainerContents(containerId);
  }

  @override
  Future<int> recordTransferOperation(
      TransferOperationHeader header, List<TransferItemDetail> items) async {
    TransferOperationHeader headerToSave = header;

    if (await networkInfo.isConnected) {
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

    final localId = await localDataSource.saveTransferOperation(headerToSave, items);
    debugPrint("Transfer operation saved locally with ID: $localId and synced status: ${headerToSave.synced}.");

    // ----- KUTU TRANSFERİ İÇİN MİKTAR AZALTMA VE LOKASYON GÜNCELLEME LOGİĞİ -----
    if (headerToSave.operationType == AssignmentMode.kutu) {
      // Kutu transferinde, orijinal kutunun lokasyonu değişmez.
      // Sadece içindeki ürün miktarı azalır.
      if (items.isNotEmpty) {
        final transferredItem = items.first; // Kutu için tek bir item olacağını varsayıyoruz.
        await localDataSource.decreaseProductQuantityInGoodsReceipt(
            headerToSave.containerId, // Kaynak kutu ID'si
            transferredItem.productCode, // Transfer edilen ürünün kodu
            transferredItem.quantity // Transfer edilen miktar
        );
        debugPrint("KUTU TRANSFERİ: ${headerToSave.containerId} ID'li kutudan ${transferredItem.productName} ürünü için ${transferredItem.quantity} adet miktar düşüldü.");

        // İsteğe bağlı: Eğer kutudaki ürün tamamen biterse (getContainerContents ile kontrol edilebilir),
        // container_location tablosundan kaydı silinebilir veya 'EMPTY' gibi bir lokasyona atanabilir.
        // Şimdilik sadece miktarı azaltıyoruz.
      }
    } else if (headerToSave.operationType == AssignmentMode.palet) {
      // Palet transferinde, paletin tamamı yeni lokasyona taşınır.
      await localDataSource.updateContainerLocation(
          headerToSave.containerId, headerToSave.targetLocation, headerToSave.transferDate);
      debugPrint("PALET TRANSFERİ: ${headerToSave.containerId} ID'li paletin lokasyonu ${headerToSave.targetLocation} olarak güncellendi.");
    }
    // ----- BİTİŞ -----

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
    // Bu metod genel bir container lokasyon güncellemesi için,
    // recordTransferOperation içindeki mantık daha spesifik.
    DateTime now = DateTime.now();
    await localDataSource.updateContainerLocation(containerId, newLocation, now);
    if (await networkInfo.isConnected) {
      try {
        // await remoteDataSource.updateContainerLocationOnApi(containerId, newLocation); // API çağrısı
        debugPrint("Genel container location update for $containerId to $newLocation potentially sent to API (mock).");
      } catch (e) {
        debugPrint("Failed to update general container $containerId location on API: $e");
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

// lib/core/sync/sync_service.dart
import 'dart:async';

import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

class SyncResult {
  final bool success;
  final String message;
  SyncResult(this.success, this.message);
}

enum SyncStatus {
  offline,
  online,
  syncing,
  upToDate,
  error,
}

class SyncService {
  final Dio dio;
  final DatabaseHelper dbHelper;
  final NetworkInfo networkInfo;

  // UYARI GİDERİLDİ: Bu alanlar private ve final yapıldı.
  final BehaviorSubject<SyncStatus> _syncStatusController = BehaviorSubject<SyncStatus>.seeded(SyncStatus.offline);
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  // UYARI GİDERİLDİ: Kullanılmayan alanlar kaldırıldı.

  SyncService({
    required this.dio,
    required this.dbHelper,
    required this.networkInfo,
  }) {
    _init();
  }

  Future<void> _init() async {
    // SharedPreferences burada başlatılabilir ama şu an kullanılmıyor.
    // _prefs = await SharedPreferences.getInstance();

    networkInfo.onConnectivityChanged.listen((isConnected) {
      _syncStatusController.add(isConnected ? SyncStatus.online : SyncStatus.offline);
      if (isConnected) {
        uploadPendingOperations();
      }
    });

    final isInitiallyConnected = await networkInfo.isConnected;
    _syncStatusController
        .add(isInitiallyConnected ? SyncStatus.online : SyncStatus.offline);
  }

  Future<SyncResult> downloadMasterData() async {
    if (!await networkInfo.isConnected) {
      return SyncResult(false, "İnternet bağlantısı yok.");
    }

    _syncStatusController.add(SyncStatus.syncing);

    try {
      final response = await dio.post(ApiConfig.syncDownload, data: {});

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        await dbHelper.replaceTables(data);
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(true, "Ana veriler başarıyla senkronize edildi.");
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(false, "Sunucu hatası: ${response.statusCode}");
      }
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      debugPrint("Ana veri indirme hatası: $e");
      return SyncResult(false, "Bir hata oluştu: $e");
    }
  }

  Future<SyncResult> uploadPendingOperations() async {
    if (!await networkInfo.isConnected) {
      return SyncResult(false, "İnternet bağlantısı yok.");
    }

    _syncStatusController.add(SyncStatus.syncing);

    final pendingOperations = await getPendingOperations();
    if (pendingOperations.isEmpty) {
      _syncStatusController.add(SyncStatus.upToDate);
      return SyncResult(true, "Senkronize edilecek bekleyen işlem yok.");
    }

    try {
      final payload = {'operations': pendingOperations.map((op) => op.toUploadPayload()).toList()};
      final response = await dio.post(ApiConfig.syncUpload, data: payload);

      if (response.statusCode == 200) {
        final results = response.data['results'] as List;
        for (var result in results) {
          final opId = result['operation']['id'];
          final bool success = result['result']['status'] == 'success';
          if (success) {
            await dbHelper.deletePendingOperation(opId);
          } else {
            await dbHelper.updatePendingOperationStatus(opId, 'failed', error: result['result']['error']);
          }
        }
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(true, "Senkronizasyon tamamlandı.");
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(false, "Sunucu hatası: ${response.statusCode}");
      }
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      debugPrint("Bekleyen işlemleri yükleme hatası: $e");
      return SyncResult(false, "Bir hata oluştu: $e");
    }
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    return dbHelper.getPendingOperations();
  }

  void dispose() {
    _syncStatusController.close();
  }
}

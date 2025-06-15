// lib/core/sync/sync_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncStatus {
  offline,
  online,
  syncing,
  upToDate,
  error,
}

class SyncService with ChangeNotifier {
  DatabaseHelper dbHelper;
  Dio dio;
  NetworkInfo networkInfo;

  bool _isSyncing = false;
  final _statusController = StreamController<SyncStatus>.broadcast();
  late final StreamSubscription _connectivitySubscription;
  Timer? _periodicSyncTimer;

  static const _lastSyncTimestampKey = 'last_sync_timestamp';

  SyncService({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  }) {
    _initialize();
  }

  void _initialize() async {
    final hasConnection = await networkInfo.isConnected;
    _statusController.add(hasConnection ? SyncStatus.online : SyncStatus.offline);

    if (hasConnection) {
      await performFullSync();
    }

    _connectivitySubscription = networkInfo.onConnectivityChanged.listen((isConnected) {
      if (isConnected) {
        _statusController.add(SyncStatus.online);
        performFullSync();
      } else {
        _statusController.add(SyncStatus.offline);
        _periodicSyncTimer?.cancel();
      }
    });
  }

  Future<void> performFullSync() async {
    if (!await networkInfo.isConnected) {
      debugPrint("SyncService: İnternet yok. Manuel senkronizasyon atlanıyor.");
      _statusController.add(SyncStatus.offline);
      await dbHelper.addSyncLog('manual_sync', 'error', 'İnternet bağlantısı olmadığı için başlatılamadı.');
      return;
    }
    if (_isSyncing) {
      debugPrint("SyncService: Zaten senkronize ediliyor. Atlanıyor.");
      return;
    }

    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    debugPrint("SyncService: Tam senkronizasyon döngüsü başlıyor...");

    try {
      await _uploadPendingOperations();
      await _downloadDataFromServer();

      final remainingOps = await dbHelper.getPendingOperations();
      if (remainingOps.isEmpty) {
        _statusController.add(SyncStatus.upToDate);
        await dbHelper.addSyncLog('sync_status', 'success', 'Cihaz güncel. Bekleyen işlem yok.');
      } else {
        _statusController.add(SyncStatus.error);
        await dbHelper.addSyncLog('sync_status', 'error', '${remainingOps.length} işlem senkronize edilemedi.');
      }
      debugPrint("SyncService: Tam senkronizasyon döngüsü tamamlandı.");

    } catch (e) {
      debugPrint("SyncService: performFullSync sırasında genel hata: $e");
      await dbHelper.addSyncLog('sync_status', 'error', 'Genel Hata: $e');
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
      _setupPeriodicSync();

      if (await networkInfo.isConnected && !_statusController.isClosed) {
        final ops = await dbHelper.getPendingOperations();
        if (ops.isEmpty) {
          if (_statusController.hasListener) _statusController.add(SyncStatus.upToDate);
        } else {
          if (_statusController.hasListener) _statusController.add(SyncStatus.online);
        }
      }
      notifyListeners();
    }
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (await networkInfo.isConnected) {
        await _downloadDataFromServer();
      } else {
        timer.cancel();
      }
    });
  }

  /// [YENİ] Sunucudan gelen ve fazladan (alias) sütun içeren veriyi temizler.
  Map<String, dynamic> _cleanServerData(Map<String, dynamic> serverData) {
    if (serverData.containsKey('urunler')) {
      final urunlerList = serverData['urunler'] as List<dynamic>;
      final cleanedUrunler = urunlerList.map((urun) {
        final Map<String, dynamic> cleanedUrun = Map.from(urun);
        // Sunucunun `SELECT *, alias as ...` sorgusundan kaynaklanan fazlalık alanları kaldır.
        cleanedUrun.remove('id');
        cleanedUrun.remove('code');
        cleanedUrun.remove('name');
        cleanedUrun.remove('is_active');
        return cleanedUrun;
      }).toList();
      serverData['urunler'] = cleanedUrunler;
    }
    // Gelecekte başka tablolarda benzer sorunlar olursa buraya eklenebilir.
    return serverData;
  }

  Future<void> _downloadDataFromServer() async {
    debugPrint("SyncService: Sunucudan veri indirme başlıyor...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncTimestampKey);

      final response = await dio.post(ApiConfig.syncDownload, data: {'last_sync': lastSync});

      if (response.statusCode == 200 && response.data['success'] == true) {
        final rawData = response.data['data'] as Map<String, dynamic>;

        // [GÜNCELLEME] Veriyi veritabanına yazmadan önce temizle.
        final cleanData = _cleanServerData(rawData);

        await dbHelper.replaceTables(cleanData);

        final newTimestamp = response.data['timestamp'] as String;
        await prefs.setString(_lastSyncTimestampKey, newTimestamp);

        final tablesCount = cleanData.keys.length;
        final message = "$tablesCount tablo sunucudan indirilip güncellendi.";
        debugPrint("SyncService: $message");
        await dbHelper.addSyncLog('download', 'success', message);
      } else {
        throw Exception("API yanıtı başarısız: ${response.data['error']}");
      }
    } catch (e) {
      final errorMessage = "Veri indirme hatası: $e";
      debugPrint("SyncService: $errorMessage");
      await dbHelper.addSyncLog('download', 'error', errorMessage);
      _statusController.add(SyncStatus.error);
    }
  }

  Future<void> _uploadPendingOperations() async {
    debugPrint("SyncService: Bekleyen operasyonlar sunucuya yükleniyor...");
    final pendingOps = await dbHelper.getPendingOperations();

    if (pendingOps.isEmpty) {
      debugPrint("SyncService: Yüklenecek bekleyen operasyon bulunmuyor.");
      return;
    }

    int successCount = 0;
    for (final op in pendingOps) {
      bool success = await _syncSingleOperation(op);
      if (success) {
        successCount++;
        await dbHelper.deletePendingOperation(op.id!);
      } else {
        await dbHelper.updatePendingOperationStatus(op.id!, 'failed', error: 'Sync failed');
      }
    }

    final message = "$successCount / ${pendingOps.length} bekleyen işlem sunucuya yüklendi.";
    debugPrint("SyncService: $message");
    await dbHelper.addSyncLog('upload', successCount == pendingOps.length ? 'success' : 'partial_error', message);
  }

  Future<bool> _syncSingleOperation(PendingOperation op) async {
    try {
      String url;
      switch (op.type) {
        case PendingOperationType.goodsReceipt:
          url = ApiConfig.goodsReceipts;
          break;
        case PendingOperationType.inventoryTransfer:
          url = ApiConfig.transfers;
          break;
      }
      final payload = jsonDecode(op.data);
      final response = await dio.post(url, data: payload);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint("Sync Error for op #${op.id}: $e");
      return false;
    }
  }

  void updateDependencies(DatabaseHelper newDb, Dio newDio, NetworkInfo newNetwork) {
    this.dbHelper = newDb;
    this.dio = newDio;
    this.networkInfo = newNetwork;
  }

  Stream<SyncStatus> get syncStatusStream => _statusController.stream;

  Future<List<PendingOperation>> getPendingOperations() => dbHelper.getPendingOperations();

  Future<List<SyncLog>> getSyncHistory() => dbHelper.getSyncLogs();

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _periodicSyncTimer?.cancel();
    _statusController.close();
    super.dispose();
  }
}

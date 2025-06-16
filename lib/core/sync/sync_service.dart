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

  void _initialize() {
    checkServerStatus();
    _connectivitySubscription = networkInfo.onConnectivityChanged.listen((_) {
      performFullSync();
    });
    _setupPeriodicSync();
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      debugPrint("Periyodik senkronizasyon tetiklendi...");
      performFullSync();
    });
  }

  Future<void> checkServerStatus() async {
    _statusController.add(SyncStatus.syncing);
    if (await _canConnectToServer()) {
      _statusController.add(SyncStatus.online);
    } else {
      _statusController.add(SyncStatus.offline);
    }
  }

  Future<bool> _canConnectToServer() async {
    try {
      final response = await dio.get(
        '${ApiConfig.host}/health',
        options: Options(sendTimeout: const Duration(seconds: 3), receiveTimeout: const Duration(seconds: 3)),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> performFullSync() async {
    if (_isSyncing) {
      debugPrint("SyncService: Zaten bir senkronizasyon işlemi devam ediyor. Atlanıyor.");
      return;
    }
    if (!await _canConnectToServer()) {
      debugPrint("SyncService: Sunucuya ulaşılamıyor. Senkronizasyon atlanıyor.");
      _statusController.add(SyncStatus.offline);
      return;
    }
    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    notifyListeners();
    try {
      await _uploadPendingOperations();
      await _downloadDataFromServer();
      final remainingOps = await dbHelper.getPendingOperations();
      if (remainingOps.isEmpty) {
        _statusController.add(SyncStatus.upToDate);
      } else {
        _statusController.add(SyncStatus.error);
      }
    } catch (e) {
      debugPrint("SyncService: performFullSync sırasında hata: $e");
      await dbHelper.addSyncLog('sync_status', 'error', 'Genel Hata: $e');
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadDataFromServer() async {
    debugPrint("SyncService: Sunucudan veri indirme başlıyor...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncTimestampKey);
      debugPrint("Son senkronizasyon zamanı: $lastSync");
      final response = await dio.post(
        ApiConfig.syncDownload,
        data: {'last_sync_timestamp': lastSync},
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        final rawData = response.data['data'] as Map<String, dynamic>;
        final tablesCount = rawData.keys.where((k) => (rawData[k] as List).isNotEmpty).length;
        if (tablesCount == 0) {
          debugPrint("SyncService: Sunucudan yeni veya güncel veri gelmedi.");
          return;
        }
        await dbHelper.applyDownloadedData(rawData, isFullSync: lastSync == null);
        final newTimestamp = response.data['timestamp'] as String;
        await prefs.setString(_lastSyncTimestampKey, newTimestamp);
        final message = "$tablesCount tablo için yeni veriler sunucudan indirilip güncellendi.";
        debugPrint("SyncService: $message");
        await dbHelper.addSyncLog('download', 'success', message);
      } else {
        throw Exception("API yanıtı başarısız: ${response.data['error']}");
      }
    } catch (e) {
      final errorMessage = "Veri indirme hatası: $e";
      debugPrint("SyncService: $errorMessage");
      await dbHelper.addSyncLog('download', 'error', errorMessage);
      rethrow;
    }
  }

  Future<void> _uploadPendingOperations() async {
    final pendingOps = await dbHelper.getPendingOperations();
    if (pendingOps.isEmpty) {
      debugPrint("SyncService: Yüklenecek bekleyen operasyon bulunmuyor.");
      return;
    }
    debugPrint("SyncService: ${pendingOps.length} bekleyen operasyon sunucuya yükleniyor...");
    try {
      final List<Map<String, dynamic>> operationsPayload = pendingOps.map((op) {
        return {"type": op.type.name, "data": jsonDecode(op.data)};
      }).toList();
      final response = await dio.post(ApiConfig.syncUpload, data: {"operations": operationsPayload});
      if (response.statusCode == 200 && response.data['success'] == true) {
        final results = List<Map<String, dynamic>>.from(response.data['results']);
        for (int i = 0; i < pendingOps.length; i++) {
          final op = pendingOps[i];
          final result = results[i]['result'];
          if (result != null && result['error'] == null) {
            await dbHelper.deletePendingOperation(op.id!);
            final successMessage = "'${op.displayTitle}' başarıyla gönderildi.";
            await dbHelper.addSyncLog('upload', 'success', successMessage);
          } else {
            final errorMsg = result?['error'] ?? 'Bilinmeyen sunucu hatası';
            await dbHelper.updatePendingOperationStatus(op.id!, 'failed', error: errorMsg);
            final failureMessage = "'${op.displayTitle}' gönderilemedi: $errorMsg";
            await dbHelper.addSyncLog('upload', 'error', failureMessage);
            debugPrint("Operasyon #${op.id} sunucuda işlenemedi: $errorMsg");
          }
        }
      } else {
        throw Exception("Toplu yükleme API yanıtı başarısız: ${response.data['error']}");
      }
    } catch (e) {
      final errorMessage = "Tüm bekleyen işlemler için genel yükleme hatası: ${e.toString()}";
      await dbHelper.addSyncLog('upload', 'error', errorMessage);
      rethrow;
    }
  }

  void updateDependencies(DatabaseHelper newDb, Dio newDio, NetworkInfo newNetwork) {
    dbHelper = newDb;
    dio = newDio;
    networkInfo = newNetwork;
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

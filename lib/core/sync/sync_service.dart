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

enum SyncStage {
  initializing,
  downloading,
  processing,
  finalizing,
  completed,
  error
}

class SyncProgress {
  final SyncStage stage;
  final String tableName;
  final double progress; // 0.0 to 1.0
  final int processedItems;
  final int totalItems;
  final String? message;

  const SyncProgress({
    required this.stage,
    required this.tableName,
    required this.progress,
    this.processedItems = 0,
    this.totalItems = 0,
    this.message,
  });
}

enum SyncStatus {
  offline,
  online,
  syncing,
  upToDate,
  error,
}

class SyncService with ChangeNotifier {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;

  bool _isSyncing = false;
  bool _userOperationInProgress = false;
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  final StreamController<SyncProgress> _progressController = StreamController<SyncProgress>.broadcast();
  late final StreamSubscription _connectivitySubscription;
  Timer? _periodicTimer;
  SyncStatus _currentStatus = SyncStatus.offline;

  // User-specific timestamp key oluştur
  String _getUserSyncTimestampKey(int userId) {
    return 'last_sync_timestamp_user_$userId';
  }

  SyncService({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  }) {
    _initialize();
  }

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get syncStatusStream => _statusController.stream;
  Stream<SyncProgress> get syncProgressStream => _progressController.stream;
  bool get isSyncing => _isSyncing;

  void _emitProgress(SyncProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  void _updateStatus(SyncStatus status) {
    if (_currentStatus == status) return;
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    notifyListeners();
  }

  void _initialize() {
    _updateStatus(SyncStatus.offline);
    networkInfo.isConnected.then((connected) {
      if (connected) {
        _updateStatus(SyncStatus.online);
        debugPrint("Başlangıçta bağlantı var, senkronizasyon başlatılıyor.");
        performFullSync();
      }
    });

    _connectivitySubscription = networkInfo.onConnectivityChanged.listen((isConnected) {
      if (isConnected) {
        _updateStatus(SyncStatus.online);
        debugPrint("Bağlantı geldi, senkronizasyon kontrol ediliyor.");
        performFullSync();
      } else {
        debugPrint("Bağlantı kesildi.");
        _updateStatus(SyncStatus.offline);
      }
    });
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      debugPrint("Periyodik senkronizasyon kontrol ediliyor...");
      if (!_userOperationInProgress) {
        performFullSync();
      } else {
        debugPrint("Kullanıcı işlemi devam ediyor, periyodik senkronizasyon atlanıyor.");
      }
    });
  }

  Future<void> performFullSync({bool force = false}) async {
    if (_isSyncing && !force) {
      debugPrint("Senkronizasyon zaten devam ediyor. Atlanıyor.");
      return;
    }

    if (_userOperationInProgress && !force) {
      debugPrint("Kullanıcı işlemi devam ediyor, senkronizasyon atlanıyor.");
      return;
    }

    _isSyncing = true;
    _updateStatus(SyncStatus.syncing);
    notifyListeners();

    if (!await networkInfo.isConnected) {
      debugPrint("İnternet bağlantısı yok. Senkronizasyon atlanıyor.");
      _updateStatus(SyncStatus.offline);
      _isSyncing = false;
      notifyListeners();
      return;
    }

    try {
      // Initializing stage
      _emitProgress(const SyncProgress(
        stage: SyncStage.initializing,
        tableName: '',
        progress: 0.0,
      ));

      await uploadPendingOperations();

      final prefs = await SharedPreferences.getInstance();
      final warehouseId = prefs.getInt('warehouse_id');
      if (warehouseId == null) {
        throw Exception("Warehouse ID bulunamadı. Lütfen tekrar giriş yapın.");
      }

      await _downloadDataFromServer(warehouseId: warehouseId);
      await dbHelper.cleanupOldSyncedOperations();

      // Ana veritabanı temizliği - eski verileri sil
      await dbHelper.performMaintenanceCleanup(days: 7);

      // Finalizing stage
      _emitProgress(const SyncProgress(
        stage: SyncStage.finalizing,
        tableName: '',
        progress: 0.95,
      ));

      final remainingOps = await dbHelper.getPendingOperations();
      if (remainingOps.isEmpty) {
        _updateStatus(SyncStatus.upToDate);
        await dbHelper.addSyncLog('sync_status', 'success', 'Senkronizasyon başarılı ve bekleyen işlem yok.');
      } else {
        _updateStatus(SyncStatus.error);
        await dbHelper.addSyncLog('sync_status', 'error', 'Senkronizasyon sonrası hala ${remainingOps.length} gönderilmeyen işlem var.');
      }

      // Completed stage
      _emitProgress(const SyncProgress(
        stage: SyncStage.completed,
        tableName: '',
        progress: 1.0,
      ));
    } catch (e, s) {
      debugPrint("performFullSync sırasında hata: $e\nStack: $s");
      await dbHelper.addSyncLog('sync_status', 'error', 'Genel Hata: $e');
      _updateStatus(SyncStatus.error);

      // Error stage
      _emitProgress(SyncProgress(
        stage: SyncStage.error,
        tableName: '',
        progress: 0.0,
        message: e.toString(),
      ));
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadDataFromServer({required int warehouseId}) async {
    debugPrint("Sunucudan veri indirme başlıyor...");

    // Start downloading stage
    _emitProgress(const SyncProgress(
      stage: SyncStage.downloading,
      tableName: '',
      progress: 0.1,
    ));

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final userTimestampKey = _getUserSyncTimestampKey(userId);
    final lastSync = prefs.getString(userTimestampKey);

    debugPrint("🔄 İnkremental Sync Bilgisi:");
    debugPrint("   User ID: $userId");
    debugPrint("   Son sync timestamp: $lastSync");
    debugPrint("   Warehouse ID: $warehouseId");

    if (lastSync != null) {
      debugPrint("   📅 İnkremental sync yapılıyor (sadece değişenler)");
    } else {
      debugPrint("   🔄 İlk sync - tüm veriler çekilecek");
    }    final response = await dio.post(
      ApiConfig.syncDownload,
      data: {'last_sync_timestamp': lastSync, 'warehouse_id': warehouseId},
    );

    if (response.statusCode == 200 && response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>;
      final newTimestamp = response.data['timestamp'] as String? ?? DateTime.now().toUtc().toIso8601String();

      // Debug: Gelen veri miktarını göster
      debugPrint("📊 Sunucudan gelen veri miktarı:");
      data.forEach((tableName, tableData) {
        if (tableData is List) {
          debugPrint("   $tableName: ${tableData.length} kayıt");
        }
      });

      // Processing stage
      _emitProgress(const SyncProgress(
        stage: SyncStage.processing,
        tableName: '',
        progress: 0.5,
      ));

      await dbHelper.applyDownloadedData(data, onTableProgress: (tableName, processed, total) {
        // Progress calculation: 0.5 to 0.9 range (40% of total progress)
        final progressPercentage = total > 0 ? processed / total : 0.0;
        final currentProgress = 0.5 + (progressPercentage * 0.4);

        _emitProgress(SyncProgress(
          stage: SyncStage.processing,
          tableName: tableName,
          progress: currentProgress,
          processedItems: processed,
          totalItems: total,
        ));
      });

      // User-specific timestamp kaydet
      await prefs.setString(userTimestampKey, newTimestamp);
      debugPrint("Veri indirme başarılı. Yeni senkronizasyon zamanı: $newTimestamp");
      debugPrint("💾 Timestamp kaydedildi: $userTimestampKey = $newTimestamp");
    } else {
      throw Exception("Sunucu veri indirme işlemini reddetti: ${response.data['error'] ?? 'Bilinmeyen Hata'}");
    }
  }

  Future<void> uploadPendingOperations() async {
    final pendingOps = await dbHelper.getPendingOperations();
    if (pendingOps.isEmpty) {
      debugPrint("Gönderilecek bekleyen işlem yok.");
      return;
    }

    debugPrint("${pendingOps.length} adet bekleyen işlem bulundu. Sunucuya gönderiliyor...");

    final operationsPayload = pendingOps.map((op) {
      return {
        'local_id': op.id,
        'idempotency_key': op.uniqueId,
        'type': op.type.name,
        'data': jsonDecode(op.data)
      };
    }).toList();

    try {
      final response = await dio.post(
        ApiConfig.syncUpload,
        data: {'operations': operationsPayload},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        await _handleSyncResults(response.data['results'] ?? []);
        await dbHelper.addSyncLog('upload', 'success', '${pendingOps.length} işlem başarıyla gönderildi.');
      } else {
        final serverError = response.data['details'] ?? response.data['error'] ?? 'Bilinmeyen sunucu hatası';
        throw Exception("Sunucu toplu işlemi reddetti: $serverError");
      }
    } catch (e) {
      await dbHelper.addSyncLog('upload', 'error', "Upload hatası: $e");
      rethrow;
    }
  }

  Future<void> _handleSyncResults(List<dynamic> results) async {
    debugPrint("_handleSyncResults çağrıldı. Results: ${jsonEncode(results)}");

    bool dataChanged = false;
    for (var res in results) {
      final id = res['local_id'];
      final resultData = res['result'];
      final status = resultData['status'];
      final message = resultData['message'];

      debugPrint("İşleniyor - opId: $id, status: $status, message: $message");

      if (id != null && status == 'success') {
        debugPrint("İşlem $id başarılı, synced olarak işaretleniyor");
        await dbHelper.markOperationAsSynced(id);
        dataChanged = true;
      } else if (id != null) {
        await dbHelper.updateOperationWithError(id, message ?? 'Bilinmeyen sunucu hatası');
      }
    }

    if (dataChanged) {
      debugPrint("Veri başarıyla yüklendi, sunucudan güncel durum indiriliyor...");
      final prefs = await SharedPreferences.getInstance();
      final warehouseId = prefs.getInt('warehouse_id');
      if (warehouseId != null) {
        await _downloadDataFromServer(warehouseId: warehouseId);
      } else {
        debugPrint("Warehouse ID SharedPreferences'ta bulunamadı, _downloadDataFromServer atlanıyor.");
        await dbHelper.addSyncLog('download', 'error', 'Warehouse ID bulunamadığı için veri indirilemedi.');
      }
    }
  }

  Future<List<PendingOperation>> getPendingOperations() => dbHelper.getPendingOperations();
  Future<List<PendingOperation>> getSyncedOperationHistory() => dbHelper.getSyncedOperations();
  Future<List<SyncLog>> getSyncLogs() => dbHelper.getSyncLogs();

  /// Kullanıcı işlemini başlatırken çağrılır - senkronizasyonu geçici olarak durdurur
  void startUserOperation() {
    _userOperationInProgress = true;
    debugPrint("Kullanıcı işlemi başladı, periyodik senkronizasyon duraklatıldı.");
  }

  /// Kullanıcı işlemi bittiğinde çağrılır - senkronizasyonu yeniden başlatır
  void endUserOperation() {
    _userOperationInProgress = false;
    debugPrint("Kullanıcı işlemi bitti, periyodik senkronizasyon tekrar aktif.");
    // NOT: Otomatik sync kaldırıldı - view model'ler kendileri çağıracak
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _periodicTimer?.cancel();
    _statusController.close();
    _progressController.close();
    super.dispose();
  }
}
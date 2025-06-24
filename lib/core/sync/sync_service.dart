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
  final StreamController<SyncStatus> _statusController =
  StreamController<SyncStatus>.broadcast();
  late final StreamSubscription _connectivitySubscription;
  Timer? _periodicSyncTimer;

  // YENİ: Anlık durumu tutmak için eklendi.
  SyncStatus _currentStatus = SyncStatus.offline;

  static const _lastSyncTimestampKey = 'last_sync_timestamp';

  SyncService({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  }) {
    _initialize();
  }

  // YENİ: Arayüzün başlangıç durumunu alabilmesi için getter eklendi.
  SyncStatus get currentStatus => _currentStatus;

  // YENİ: Stream'i ve durumu merkezi olarak güncelleyen yardımcı fonksiyon.
  void _updateStatus(SyncStatus status) {
    if (_currentStatus == status && status != SyncStatus.syncing) return;
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void updateDependencies({
    required DatabaseHelper dbHelper,
    required Dio dio,
    required NetworkInfo networkInfo,
  }) {
    this.dbHelper = dbHelper;
    this.dio = dio;
    this.networkInfo = networkInfo;
    debugPrint("SyncService: Bağımlılıklar güncellendi.");
  }

  void _initialize() {
    // Başlangıçta mevcut bağlantıyı hemen kontrol et
    networkInfo.isConnected.then((connected) {
      if (connected) {
        _updateStatus(SyncStatus.online);
        debugPrint("Başlangıçta bağlantı var, senkronizasyon tetikleniyor.");
        performFullSync();
      } else {
        _updateStatus(SyncStatus.offline);
      }
    });

    _connectivitySubscription =
        networkInfo.onConnectivityChanged.listen((isConnected) {
          if (isConnected) {
            _updateStatus(SyncStatus.online);
            debugPrint("Bağlantı geldi, senkronizasyon tetikleniyor.");
            performFullSync();
          } else {
            debugPrint("Bağlantı kesildi.");
            _updateStatus(SyncStatus.offline);
          }
        });
    _setupPeriodicSync();
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer?.cancel();
    // GÜNCELLEME: Periyodik senkronizasyon sıklığı 1 dakikaya düşürüldü.
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      debugPrint("Periyodik senkronizasyon tetiklendi...");
      performFullSync();
    });
  }

  Stream<SyncStatus> get syncStatusStream => _statusController.stream;
  bool get isSyncing => _isSyncing;

  Future<void> performFullSync({bool force = false, int? warehouseId}) async {
    if (_isSyncing && !force) {
      debugPrint("Senkronizasyon zaten devam ediyor. Atlanıyor.");
      return;
    }
    if (!await networkInfo.isConnected) {
      debugPrint("İnternet bağlantısı yok. Senkronizasyon atlanıyor.");
      _updateStatus(SyncStatus.offline);
      return;
    }

    _isSyncing = true;
    _updateStatus(SyncStatus.syncing);
    notifyListeners();

    try {
      await _uploadPendingOperations();
      await _downloadDataFromServer(warehouseId: warehouseId);

      // YENİ: Senkronizasyon sonrası eski kayıtları temizle.
      await dbHelper.cleanupOldSyncedOperations();

      final remainingOps = await dbHelper.getPendingOperations();
      if (remainingOps.isEmpty) {
        _updateStatus(SyncStatus.upToDate);
        await dbHelper.addSyncLog('sync_status', 'success',
            'Senkronizasyon başarılı ve bekleyen işlem yok.');
      } else {
        _updateStatus(SyncStatus.error);
        await dbHelper.addSyncLog('sync_status', 'error',
            'Senkronizasyon sonrası hala ${remainingOps.length} gönderilmeyen işlem var.');
      }
    } catch (e, s) {
      debugPrint("performFullSync sırasında hata: $e\nStack: $s");
      await dbHelper.addSyncLog('sync_status', 'error', 'Genel Hata: $e');
      _updateStatus(SyncStatus.error);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadDataFromServer({int? warehouseId}) async {
    debugPrint("Sunucudan veri indirme başlıyor...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncTimestampKey);
      // GÜNCELLEME: warehouseId parametre olarak gelmezse SharedPreferences'dan al.
      final finalWarehouseId = warehouseId ?? prefs.getInt('warehouse_id');

      if (finalWarehouseId == null) {
        debugPrint(
            "Veri indirmek için 'warehouse_id' gerekli. Giriş yapılmamış olabilir. Atlanıyor.");
        return;
      }

      final response = await dio.post(
        ApiConfig.syncDownload,
        data: {
          'last_sync_timestamp': lastSync,
          'warehouse_id': finalWarehouseId,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        final newTimestamp = response.data['timestamp'] as String? ??
            DateTime.now().toUtc().toIso8601String();
        await dbHelper.applyDownloadedData(data);
        await prefs.setString(_lastSyncTimestampKey, newTimestamp);
        debugPrint(
            "Veri indirme başarılı. Yeni senkronizasyon zamanı: $newTimestamp");
      } else {
        throw Exception(
            "Sunucu veri indirme işlemini reddetti: ${response.data['error'] ?? 'Bilinmeyen Hata'}");
      }
    } catch (e) {
      debugPrint("Veri indirme sırasında hata: $e");
      rethrow;
    }
  }

  /// YALNIZCA bekleyen operasyonları sunucuya yüklemeyi dener.
  /// Kullanıcı tarafından başlatılan anlık işlemler için kullanılır.
  Future<bool> uploadPendingOperations() async {
    if (!await networkInfo.isConnected) {
      debugPrint("İnternet bağlantısı yok. Yükleme atlanıyor.");
      return false;
    }
    try {
      await _uploadPendingOperations();
      return true;
    } catch (e) {
      debugPrint("uploadPendingOperations sırasında hata: $e");
      return false;
    }
  }

  Future<void> _uploadPendingOperations() async {
    final pendingOps = await dbHelper.getPendingOperations();
    if (pendingOps.isEmpty) return;

    debugPrint(
        "${pendingOps.length} adet bekleyen işlem bulundu. Sunucuya gönderiliyor...");

    for (final op in pendingOps) {
      try {
        final payload = {'type': op.type.name, 'data': jsonDecode(op.data)};
        final response =
        await dio.post(ApiConfig.syncUpload, data: {'operations': [payload]});

        if (response.statusCode == 201 || response.statusCode == 200) {
          final results = response.data['results'] as List<dynamic>?;
          final firstResult =
          results?.isNotEmpty == true ? results!.first['result'] : null;

          if (firstResult != null && firstResult['status'] == 'success') {
            // GÜNCELLEME: İşlemi silmek yerine 'synced' olarak işaretle.
            await dbHelper.markOperationAsSynced(op.id!);
            await dbHelper.addSyncLog('upload', 'success',
                'İşlem #${op.id} (${op.displayTitle}) sunucuya gönderildi.');
          } else {
            throw Exception(
                firstResult?['error'] ?? 'Bilinmeyen sunucu hatası.');
          }
        } else {
          throw Exception(
              "Sunucu işlemi reddetti. Status: ${response.statusCode}");
        }
      } catch (e) {
        final errorMessage = "İşlem #${op.id} yüklenirken hata oluştu: $e";
        debugPrint(errorMessage);
        await dbHelper.addSyncLog('upload', 'error', errorMessage);
        if (op.id != null) {
          await dbHelper.updateOperationWithError(op.id!, e.toString());
        }
        // Hata durumunda döngüyü kırarak bir sonraki senkronizasyon döngüsünü bekle.
        continue;
      }
    }
  }

  // Bekleyen işlemleri getirir.
  Future<List<PendingOperation>> getPendingOperations() =>
      dbHelper.getPendingOperations();

  // YENİ/GÜNCELLENMİŞ: Kullanıcı arayüzünün senkronize olmuş geçmişi çekmesi için.
  Future<List<PendingOperation>> getSyncedOperationHistory() =>
      dbHelper.getSyncedOperations();

  // Teknik logları getirir.
  Future<List<SyncLog>> getSyncLogs() => dbHelper.getSyncLogs();

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _periodicSyncTimer?.cancel();
    _statusController.close();
    super.dispose();
  }
}
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
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
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
    _connectivitySubscription = networkInfo.onConnectivityChanged.listen((isConnected) {
      if(isConnected) {
        _statusController.add(SyncStatus.online);
        debugPrint("Bağlantı geldi, senkronizasyon tetikleniyor.");
        performFullSync();
      } else {
        debugPrint("Bağlantı kesildi.");
        _statusController.add(SyncStatus.offline);
      }
    });
    performFullSync();
    _setupPeriodicSync();
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      debugPrint("Periyodik senkronizasyon tetiklendi...");
      performFullSync();
    });
  }

  Stream<SyncStatus> get syncStatusStream => _statusController.stream;
  bool get isSyncing => _isSyncing;

  Future<void> performFullSync({bool force = false}) async {
    if (_isSyncing && !force) {
      debugPrint("Senkronizasyon zaten devam ediyor. Atlanıyor.");
      return;
    }
    if (!await networkInfo.isConnected) {
      debugPrint("İnternet bağlantısı yok. Senkronizasyon atlanıyor.");
      _statusController.add(SyncStatus.offline);
      return;
    }

    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    notifyListeners();

    try {
      // ÖNCE YÜKLE, SONRA İNDİR
      await _uploadPendingOperations();
      await _downloadDataFromServer();

      final remainingOps = await dbHelper.getPendingOperations();
      if (remainingOps.isEmpty) {
        _statusController.add(SyncStatus.upToDate);
        await dbHelper.addSyncLog('sync_status', 'success', 'Senkronizasyon başarılı ve bekleyen işlem yok.');
      } else {
        _statusController.add(SyncStatus.error);
        await dbHelper.addSyncLog('sync_status', 'error', 'Senkronizasyon sonrası hala ${remainingOps.length} gönderilmeyen işlem var.');
      }
    } catch (e, s) {
      debugPrint("performFullSync sırasında hata: $e\nStack: $s");
      await dbHelper.addSyncLog('sync_status', 'error', 'Genel Hata: $e');
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadDataFromServer() async {
    debugPrint("Sunucudan veri indirme başlıyor...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncTimestampKey);
      final warehouseId = prefs.getInt('warehouse_id');

      if (warehouseId == null) {
        debugPrint("Veri indirmek için 'warehouse_id' gerekli. Giriş yapılmamış olabilir. Atlanıyor.");
        return;
      }

      debugPrint("Senkronizasyon isteği şu depo için gönderiliyor: warehouse_id=$warehouseId");

      final response = await dio.post(
        ApiConfig.syncDownload,
        data: {
          'last_sync_timestamp': lastSync,
          'warehouse_id': warehouseId,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        // Sunucu 'timestamp' anahtarını gönderiyorsa kullan, göndermiyorsa UTC now kullan
        final newTimestamp = response.data['timestamp'] as String? ?? DateTime.now().toUtc().toIso8601String();

        await dbHelper.applyDownloadedData(data);
        await prefs.setString(_lastSyncTimestampKey, newTimestamp);

        debugPrint("Veri indirme başarılı. Yeni senkronizasyon zamanı: $newTimestamp");
        await dbHelper.addSyncLog('download', 'success', 'Veriler sunucudan başarıyla indirildi.');

      } else {
        throw Exception("Sunucu veri indirme işlemini reddetti: ${response.data['error'] ?? 'Bilinmeyen Hata'}");
      }
    } on DioException catch (e) {
      final errorMessage = "Veri indirme hatası (Dio): ${e.response?.statusCode} - ${e.message}";
      debugPrint("$errorMessage \nResponse Data: ${e.response?.data}");
      await dbHelper.addSyncLog('download', 'error', errorMessage);
      rethrow;
    } catch (e) {
      final errorMessage = "Veri indirme sırasında beklenmedik hata: $e";
      debugPrint(errorMessage);
      await dbHelper.addSyncLog('download', 'error', errorMessage);
      rethrow;
    }
  }

  Future<void> _uploadPendingOperations() async {
    debugPrint("Bekleyen işlemleri sunucuya yükleme başlıyor...");
    final pendingOps = await dbHelper.getPendingOperations();

    if (pendingOps.isEmpty) {
      debugPrint("Yüklenecek bekleyen işlem bulunamadı.");
      return;
    }

    debugPrint("${pendingOps.length} adet bekleyen işlem bulundu. Sunucuya gönderiliyor...");

    for (final op in pendingOps) {
      try {
        final payload = {
          'type': op.type.name,
          'data': jsonDecode(op.data), // data'yı string'den Map'e çevir
        };

        // TerminalController.php'deki actionSyncUpload, 'operations' listesi bekliyor.
        final response = await dio.post(
          ApiConfig.syncUpload,
          data: {
            'operations': [payload]
          },
        );

        // PHP tarafı 201 (Created) veya 200 (OK) dönebilir.
        if (response.statusCode == 201 || response.statusCode == 200) {
          final results = response.data['results'] as List<dynamic>?;
          final firstResult = results?.isNotEmpty == true ? results!.first['result'] : null;

          if(firstResult != null && firstResult['status'] == 'success') {
            debugPrint("İşlem #${op.id} (${op.type.name}) başarıyla sunucuya yüklendi.");
            await dbHelper.deletePendingOperation(op.id!);
            await dbHelper.addSyncLog('upload', 'success', 'İşlem #${op.id} sunucuya gönderildi.');
          } else {
            final errorMessage = firstResult?['error'] ?? 'Bilinmeyen sunucu hatası.';
            throw Exception(errorMessage);
          }
        } else {
          throw Exception("Sunucu işlemi işlemeyi reddetti. Status: ${response.statusCode}, Body: ${response.data}");
        }
      } on DioException catch (e) {
        final errorMessage = "İşlem #${op.id} yüklenirken ağ hatası: ${e.response?.statusCode} - ${e.message}";
        debugPrint(errorMessage);
        await dbHelper.addSyncLog('upload', 'error', errorMessage);
        // Hata durumunda döngüden çıkıp bir sonraki senkronizasyonu beklemek daha güvenli olabilir.
        break;
      } catch (e) {
        final errorMessage = "İşlem #${op.id} yüklenirken beklenmedik hata: $e";
        debugPrint(errorMessage);
        await dbHelper.addSyncLog('upload', 'error', errorMessage);
        // Hata durumunda döngüden çık
        break;
      }
    }
  }

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

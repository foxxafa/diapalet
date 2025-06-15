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
    // Ağdaki değişiklikleri dinle ve her değişiklikte senkronizasyonu tetikle.
    _connectivitySubscription =
        networkInfo.onConnectivityChanged.listen((isConnected) {
          // Bağlantı durumu değiştiğinde yeniden senkronizasyon dene.
          performFullSync();
        });

    // Uygulama başlarken ilk senkronizasyon denemesini yap.
    performFullSync();
  }

  /// **[YENİ]** Sunucunun sağlık durumunu kontrol ederek gerçek bağlantıyı doğrular.
  Future<bool> _canConnectToServer() async {
    try {
      // Flask sunucusundaki /health endpoint'ine kısa bir zaman aşımı ile istek at.
      final response = await dio.get(
        '${ApiConfig.host}/health',
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      // Başarılı bir yanıt (200 OK) sunucunun erişilebilir olduğunu gösterir.
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Sunucu sağlık kontrolü başarısız oldu: $e");
      return false;
    }
  }

  /// **[GÜNCELLENDİ]** Ana senkronizasyon fonksiyonu artık sunucuya doğrudan bağlanabilirliği kontrol ediyor.
  Future<void> performFullSync() async {
    if (_isSyncing) {
      debugPrint("SyncService: Zaten bir senkronizasyon işlemi devam ediyor. Atlanıyor.");
      return;
    }

    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    notifyListeners(); // Buton durumunu (örn. FAB) güncellemek için

    try {
      // Genel internet yerine doğrudan sunucuya bağlanıp bağlanamadığımızı kontrol et.
      if (!await _canConnectToServer()) {
        debugPrint("SyncService: Sunucuya ulaşılamıyor. Senkronizasyon atlanıyor.");
        _statusController.add(SyncStatus.offline);
        // 'finally' bloğu çalışacağı için _isSyncing ve notifyListeners() orada yönetilecek.
        return;
      }

      // Artık sunucuyla konuşabildiğimizden eminiz.
      _statusController.add(SyncStatus.online); // Kullanıcıya online olduğumuzu gösterelim.

      await _uploadPendingOperations();
      await _downloadDataFromServer();

      // Senkronizasyon sonrası durumu kontrol et.
      final remainingOps = await dbHelper.getPendingOperations();
      if (remainingOps.isEmpty) {
        _statusController.add(SyncStatus.upToDate);
        await dbHelper.addSyncLog('sync_status', 'success', 'Cihaz güncel. Bekleyen işlem yok.');
      } else {
        // Senkronizasyon başarılı olmasına rağmen hala bekleyen işlem varsa bu bir hatadır.
        _statusController.add(SyncStatus.error);
        await dbHelper.addSyncLog('sync_status', 'error',
            '${remainingOps.length} işlem senkronize edilemedi.');
      }
    } catch (e) {
      debugPrint("SyncService: performFullSync sırasında hata: $e");
      await dbHelper.addSyncLog('sync_status', 'error', 'Genel Hata: $e');
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
      notifyListeners(); // Buton durumunu tekrar etkinleştirmek için
    }
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer =
        Timer.periodic(const Duration(minutes: 5), (timer) async {
          // Periyodik senkronizasyon da artık asıl bağlantıyı kontrol etmeli.
          if (await _canConnectToServer()) {
            await _downloadDataFromServer();
          }
        });
  }

  Future<void> _downloadDataFromServer() async {
    debugPrint("SyncService: Sunucudan veri indirme başlıyor...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncTimestampKey);

      final response = await dio
          .post(ApiConfig.syncDownload, data: {'last_sync': lastSync});

      if (response.statusCode == 200 && response.data['success'] == true) {
        final rawData = response.data['data'] as Map<String, dynamic>;

        await dbHelper.replaceTables(rawData);

        final newTimestamp = response.data['timestamp'] as String;
        await prefs.setString(_lastSyncTimestampKey, newTimestamp);

        final tablesCount = rawData.keys.length;
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
      rethrow;
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
    List<PendingOperation> failedOps = [];

    // Tüm operasyonları tek bir payload içinde gönder
    try {
      final List<Map<String, dynamic>> operationsPayload = pendingOps.map((op) {
        return {
          "type": op.type.name, // 'goodsReceipt' veya 'inventoryTransfer'
          "data": jsonDecode(op.data),
        };
      }).toList();

      final response = await dio.post(
        ApiConfig.syncUpload,
        data: {"operations": operationsPayload},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        // Sunucudan gelen sonuçları işle
        final results = List<Map<String, dynamic>>.from(response.data['results']);
        for (int i = 0; i < pendingOps.length; i++) {
          final op = pendingOps[i];
          final result = results[i]['result'];
          if (result.containsKey('error')) {
            failedOps.add(op);
            await dbHelper.updatePendingOperationStatus(op.id!, 'failed', error: result['error']);
          } else {
            successCount++;
            await dbHelper.deletePendingOperation(op.id!);
          }
        }
      } else {
        throw Exception("Toplu yükleme API yanıtı başarısız: ${response.data['error']}");
      }

    } catch(e) {
      final errorMessage = "Toplu operasyon yükleme hatası: $e";
      debugPrint(errorMessage);
      await dbHelper.addSyncLog('upload', 'error', errorMessage);
      rethrow;
    }


    final message =
        "$successCount / ${pendingOps.length} bekleyen işlem sunucuya yüklendi.";
    debugPrint("SyncService: $message");
    await dbHelper.addSyncLog('upload',
        failedOps.isEmpty ? 'success' : 'partial_error', message);

    if(failedOps.isNotEmpty) {
      throw Exception("${failedOps.length} işlem yüklenemedi.");
    }
  }

  void updateDependencies(
      DatabaseHelper newDb, Dio newDio, NetworkInfo newNetwork) {
    dbHelper = newDb;
    dio = newDio;
    networkInfo = newNetwork;
  }

  Stream<SyncStatus> get syncStatusStream => _statusController.stream;

  Future<List<PendingOperation>> getPendingOperations() =>
      dbHelper.getPendingOperations();

  Future<List<SyncLog>> getSyncHistory() => dbHelper.getSyncLogs();

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _periodicSyncTimer?.cancel();
    _statusController.close();
    super.dispose();
  }
}

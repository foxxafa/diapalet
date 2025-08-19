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
    debugPrint("🚀 Paginated sync sistemi başlatılıyor...");

    // Start downloading stage
    _emitProgress(const SyncProgress(
      stage: SyncStage.downloading,
      tableName: '',
      progress: 0.05,
    ));

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final userTimestampKey = _getUserSyncTimestampKey(userId);
    final lastSync = prefs.getString(userTimestampKey);

    debugPrint("🔄 İnkremental Sync Bilgisi:");
    debugPrint("   User ID: $userId");
    debugPrint("   Son sync timestamp: $lastSync");
    debugPrint("   Warehouse ID: $warehouseId");
    debugPrint("   📱 Cihaz zamanı (UTC): ${DateTime.now().toUtc().toIso8601String()}");
    debugPrint("   📱 Cihaz zamanı (Local): ${DateTime.now().toIso8601String()}");

    if (lastSync != null) {
      debugPrint("   📅 İnkremental sync yapılıyor (sadece değişenler)");
    } else {
      debugPrint("   🔄 İlk sync - tüm veriler çekilecek");
    }

    // STEP 1: Get table counts first
    debugPrint("📊 STEP 1: Tablo sayıları alınıyor...");
    final counts = await _getTableCounts(warehouseId, lastSync);
    
    debugPrint("📊 Toplam kayıt sayıları:");
    int totalRecords = 0;
    counts.forEach((tableName, count) {
      debugPrint("   $tableName: $count kayıt");
      totalRecords += count as int;
    });
    debugPrint("   🎯 TOPLAM: $totalRecords kayıt");

    if (totalRecords == 0) {
      debugPrint("⚠️  Sunucudan hiç veri gelmeyecek (güncel durumda)");
      // Still process empty data to trigger completion
      await dbHelper.applyDownloadedData({});
      final newTimestamp = DateTime.now().toUtc().toIso8601String();
      await prefs.setString(userTimestampKey, newTimestamp);
      return;
    }

    // STEP 2: Download data table by table with pagination
    debugPrint("📥 STEP 2: Tablolar sayfa sayfa indiriliyor...");
    
    const pageSize = 1000; // Her sayfada 1000 kayıt
    int processedRecords = 0;
    final allData = <String, List<dynamic>>{};
    
    // Define sync order (dependencies first)
    final syncOrder = [
      'urunler', 'tedarikci', 'birimler', 'barkodlar', 'employees', 'shelfs',
      'siparisler', 'siparis_ayrintili', 'goods_receipts', 'goods_receipt_items',
      'inventory_stock', 'inventory_transfers', 'wms_putaway_status'
    ];
    
    for (final tableName in syncOrder) {
      final tableCount = counts[tableName] as int? ?? 0;
      if (tableCount == 0) continue;
      
      debugPrint("📋 $tableName tablosu indiriliyor ($tableCount kayıt)...");
      allData[tableName] = [];
      
      int page = 1;
      while (true) {
        final pageData = await _downloadTablePage(
          tableName: tableName, 
          warehouseId: warehouseId, 
          lastSync: lastSync, 
          page: page, 
          limit: pageSize
        );
        
        if (pageData.isEmpty) break;
        
        allData[tableName]!.addAll(pageData);
        processedRecords += pageData.length;
        
        // Update progress
        final progress = 0.1 + (processedRecords / totalRecords) * 0.5; // 10% to 60%
        _emitProgress(SyncProgress(
          stage: SyncStage.downloading,
          tableName: tableName,
          progress: progress,
          processedItems: processedRecords,
          totalItems: totalRecords,
        ));
        
        debugPrint("   📄 Sayfa $page: ${pageData.length} kayıt (Toplam: ${allData[tableName]!.length}/$tableCount)");
        
        if (pageData.length < pageSize) break; // Son sayfa
        page++;
      }
      
      debugPrint("   ✅ $tableName tamamlandı: ${allData[tableName]!.length} kayıt");
    }

    // STEP 3: Process all data
    debugPrint("⚙️  STEP 3: Veriler işleniyor...");
    _emitProgress(const SyncProgress(
      stage: SyncStage.processing,
      tableName: '',
      progress: 0.7,
    ));

    await dbHelper.applyDownloadedData(allData, onTableProgress: (tableName, processed, total) {
      // Progress calculation: 0.7 to 0.95 range (25% of total progress)
      final progressPercentage = total > 0 ? processed / total : 0.0;
      final currentProgress = 0.7 + (progressPercentage * 0.25);

      _emitProgress(SyncProgress(
        stage: SyncStage.processing,
        tableName: tableName,
        progress: currentProgress,
        processedItems: processed,
        totalItems: total,
      ));
    });

    // STEP 4: Save timestamp
    final newTimestamp = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(userTimestampKey, newTimestamp);
    
    debugPrint("🎉 Paginated sync tamamlandı!");
    debugPrint("   📊 İşlenen toplam kayıt: $processedRecords");
    debugPrint("   💾 Yeni timestamp: $newTimestamp");
  }

  Future<Map<String, dynamic>> _getTableCounts(int warehouseId, String? lastSync) async {
    const maxRetries = 3;
    const baseDelayMs = 1000;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await dio.post(
          ApiConfig.syncCounts,
          data: {'warehouse_id': warehouseId, 'last_sync_timestamp': lastSync},
        );

        if (response.statusCode == 200 && response.data['success'] == true) {
          if (attempt > 1) {
            debugPrint("✅ Tablo sayıları başarılı (${attempt}. denemede)");
          }
          return Map<String, dynamic>.from(response.data['counts'] ?? {});
        } else {
          throw Exception("Count sorgusu başarısız: ${response.data['error'] ?? 'Bilinmeyen hata'}");
        }
      } catch (e) {
        final isLastAttempt = attempt == maxRetries;
        
        if (e is DioException) {
          debugPrint("❌ Sync-counts hatası ($attempt/$maxRetries): ${e.message}");
          
          // Authentication error - retry yapma
          if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
            throw Exception("Yetkilendirme hatası: API anahtarı geçersiz. Lütfen yeniden giriş yapın.");
          }
        }
        
        if (isLastAttempt) {
          debugPrint("💥 Tablo sayıları - Tüm denemeler başarısız ($maxRetries/$maxRetries)");
          throw Exception("Count sorgusu başarısız ($maxRetries deneme): ${e.toString()}");
        }
        
        final delayMs = baseDelayMs * (1 << (attempt - 1));
        debugPrint("⏳ Tablo sayıları - ${delayMs}ms bekleyip tekrar deneniyor...");
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    
    throw Exception("Tablo sayıları - Beklenmeyen hata");
  }

  Future<List<dynamic>> _downloadTablePage({
    required String tableName,
    required int warehouseId,
    String? lastSync,
    required int page,
    required int limit,
  }) async {
    const maxRetries = 3;
    const baseDelayMs = 1000; // 1 saniye başlangıç
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await dio.post(
          ApiConfig.syncDownload,
          data: {
            'warehouse_id': warehouseId,
            'last_sync_timestamp': lastSync,
            'table_name': tableName,
            'page': page,
            'limit': limit,
          },
        );

        if (response.statusCode == 200 && response.data['success'] == true) {
          final data = response.data['data'] as Map<String, dynamic>? ?? {};
          if (attempt > 1) {
            debugPrint("✅ $tableName sayfa $page başarılı (${attempt}. denemede)");
          }
          return data[tableName] as List<dynamic>? ?? [];
        } else {
          throw Exception("$tableName sayfa $page indirilemedi: ${response.data['error'] ?? 'Bilinmeyen hata'}");
        }
      } catch (e) {
        final isLastAttempt = attempt == maxRetries;
        
        if (e is DioException) {
          debugPrint("❌ $tableName sayfa $page hatası ($attempt/$maxRetries): ${e.message}");
          
          // Terminal hatalar - retry yapma
          if (e.response?.data is String) {
            final htmlError = e.response!.data as String;
            if (htmlError.contains('500 - Internal server error')) {
              if (isLastAttempt) {
                throw Exception("Sunucu iç hatası (500): $tableName tablosu indirilemedi. ${maxRetries} deneme başarısız.");
              }
            }
          }
          
          // Authentication error - retry yapma
          if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
            throw Exception("Yetkilendirme hatası: API anahtarı geçersiz. Lütfen yeniden giriş yapın.");
          }
        }
        
        if (isLastAttempt) {
          debugPrint("💥 $tableName sayfa $page - Tüm denemeler başarısız ($maxRetries/$maxRetries)");
          throw Exception("$tableName sayfa $page indirme hatası ($maxRetries deneme): ${e.toString()}");
        }
        
        // Exponential backoff: 1s, 2s, 4s
        final delayMs = baseDelayMs * (1 << (attempt - 1));
        debugPrint("⏳ $tableName sayfa $page - ${delayMs}ms bekleyip tekrar deneniyor...");
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    
    // Bu noktaya asla gelmemeli
    throw Exception("$tableName sayfa $page - Beklenmeyen hata");
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
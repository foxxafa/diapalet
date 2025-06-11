import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/database_helper.dart';
import '../network/network_info.dart';
import '../network/api_config.dart';
import 'package:diapalet/core/sync/pending_operation.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NetworkInfo _networkInfo = NetworkInfoImpl(Connectivity());
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _syncTimer;

  static const Duration _syncInterval = Duration(seconds: 30);
  static final String _baseUrl = ApiConfig.host;
  static const String _lastSyncPrefKey = 'last_sync_timestamp';

  String? _deviceId;
  bool _isInitialized = false;
  bool _isSyncingUpload = false;
  bool _isSyncingDownload = false;

  final StreamController<SyncStatus> _syncStatusController =
      StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _deviceId = await _getDeviceId();
    _registerDevice(); // Fire and forget

    // Listen for connectivity changes to trigger uploads
    _connectivitySubscription =
        _networkInfo.onConnectivityChanged.listen(_handleConnectivityChange);

    // Start background sync for master data
    _startBackgroundSync();
    _isInitialized = true;

    debugPrint('SyncService initialized with device ID: $_deviceId');
    
    // Perform an initial master data sync
    await downloadMasterData();
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    if (result != ConnectivityResult.none) {
      debugPrint('Device came online. Triggering pending operations upload.');
      uploadPendingOperations();
    } else {
      debugPrint('Device is offline.');
      _syncStatusController.add(SyncStatus.offline);
    }
  }

  Future<void> addPendingOperation(String type, Map<String, dynamic> payload) async {
    final db = await _dbHelper.database;
    await db.insert('pending_operation', {
      'operation_type': type,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
    debugPrint('Added pending operation: $type');
  }

  Future<SyncResult> uploadPendingOperations() async {
    if (_isSyncingUpload) {
      return SyncResult(success: false, message: 'Upload sync already in progress');
    }
    if (!await _networkInfo.isConnected) {
      _syncStatusController.add(SyncStatus.offline);
      return SyncResult(success: false, message: 'No network connection');
    }

    _isSyncingUpload = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      final pendingOperations = await _getPendingOperations();
      if (pendingOperations.isEmpty) {
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(success: true, message: 'No pending operations to upload');
      }

      debugPrint('Uploading ${pendingOperations.length} pending operations...');
      final uploadResult = await _uploadOperationsToServer(pendingOperations);

      if (uploadResult['success'] == true) {
        await _deleteSyncedOperations(pendingOperations);
        debugPrint('Successfully uploaded and cleared pending operations.');
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(success: true, message: 'Upload sync completed successfully', operationsProcessed: pendingOperations.length);
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(success: false, message: uploadResult['error'] ?? 'Upload failed');
      }
    } catch (e) {
      debugPrint('Error during upload sync: $e');
      _syncStatusController.add(SyncStatus.error);
      return SyncResult(success: false, message: 'Sync error: $e');
    } finally {
      _isSyncingUpload = false;
    }
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      if (await _networkInfo.isConnected) {
        debugPrint('Performing background master data sync...');
        await downloadMasterData();
      } else {
        debugPrint('Skipping background sync, device is offline.');
      }
    });
  }

  Future<SyncResult> downloadMasterData({bool fullSync = false}) async {
    if (_isSyncingDownload) {
      return SyncResult(success: false, message: 'Download sync already in progress.');
    }
     if (!await _networkInfo.isConnected) {
      _syncStatusController.add(SyncStatus.offline);
      return SyncResult(success: false, message: 'No network connection.');
    }

    _isSyncingDownload = true;
    _syncStatusController.add(SyncStatus.syncing);
    debugPrint("Starting master data download...");

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTimestamp = fullSync ? null : prefs.getString(_lastSyncPrefKey);
      
      debugPrint(fullSync ? 'Performing a FULL sync.' : 'Performing incremental sync since: $lastSyncTimestamp');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/sync/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': _deviceId, 'last_sync': lastSyncTimestamp}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _updateLocalDatabase(data['data'], isFullSync: fullSync);
          final newSyncTimestamp = DateTime.now().toUtc().toIso8601String();
          await prefs.setString(_lastSyncPrefKey, newSyncTimestamp);

          _syncStatusController.add(SyncStatus.upToDate);
          debugPrint("Master data download finished successfully.");
          return SyncResult(success: true, message: 'Master data downloaded successfully.');
        } else {
          throw Exception(data['error'] ?? 'Server returned failure on download');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Download error: $e');
      _syncStatusController.add(SyncStatus.error);
      return SyncResult(success: false, message: 'Download error: $e');
    } finally {
      _isSyncingDownload = false;
    }
  }

  Future<void> _updateLocalDatabase(Map<String, dynamic> data, {required bool isFullSync}) async {
    final db = await _dbHelper.database;
    
    await db.transaction((txn) async {
      if (isFullSync) {
        debugPrint("Performing full data wipe before sync.");
        // Order is critical to avoid foreign key violations
        for (final table in [
          'goods_receipt_item', 'pallet_item', 'transfer_item', 'inventory_stock', 'purchase_order_item',
          'goods_receipt', 'pallet', 'transfer_operation', 'purchase_order',
          'product', 'location'
        ]) {
          await txn.delete(table);
        }
      }

      // Upsert data using replace algorithm
      final products = data['products'] as List? ?? [];
      for (final item in products) {
        await txn.insert('product', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final locations = data['locations'] as List? ?? [];
      for (final item in locations) {
        await txn.insert('location', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final purchaseOrders = data['purchase_orders'] as List? ?? [];
      for (final item in purchaseOrders) {
        await txn.insert('purchase_order', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      
      final purchaseOrderItems = data['purchase_order_items'] as List? ?? [];
      for (final item in purchaseOrderItems) {
        await txn.insert('purchase_order_item', {
          'id': item['id'],
          'siparis_id': item['siparis_id'],
          'urun_id': item['urun_id'],
          'miktar': item['miktar'],
          'birim': item['birim'],
          'productName': item['productName'] // Populated by server query
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final goodsReceipts = data['goods_receipts'] as List? ?? [];
      for (final item in goodsReceipts) {
        await txn.insert('goods_receipt', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final goodsReceiptItems = data['goods_receipt_items'] as List? ?? [];
      for (final item in goodsReceiptItems) {
        await txn.insert('goods_receipt_item', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final inventoryStock = data['inventory_stock'] as List? ?? [];
      for (final item in inventoryStock) {
        await txn.insert('inventory_stock', item, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    debugPrint('Local database updated.');
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    return _getPendingOperations();
  }

  Future<List<PendingOperation>> _getPendingOperations() async {
    final db = await _dbHelper.database;
    final rows = await db.query('pending_operation', orderBy: 'id ASC');
    return rows.map((row) => PendingOperation.fromMap(row)).toList();
  }

  Future<Map<String, dynamic>> _uploadOperationsToServer(List<PendingOperation> operations) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/sync/upload'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': _deviceId,
          'operations': operations.map((op) => op.toUploadPayload()).toList(),
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      return {'success': false, 'error': 'HTTP ${response.statusCode}: ${response.body}'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<void> _deleteSyncedOperations(List<PendingOperation> operations) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final op in operations) {
        await txn.delete('pending_operation', where: 'id = ?', whereArgs: [op.id]);
      }
    });
  }

  Future<void> triggerFullSync() async {
    debugPrint("Manual full sync triggered...");
    // Clear last sync time to force a full download
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncPrefKey);
    await downloadMasterData(fullSync: true);
  }

  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return 'ios_${iosInfo.identifierForVendor}';
      }
      
      // Fallback
      return 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _registerDevice() async {
    try {
      if (!await _networkInfo.isConnected) return;
      
      final deviceInfo = DeviceInfoPlugin();
      String platform = 'unknown';
      String deviceName = 'Unknown Device';
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        platform = 'android';
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        platform = 'ios';
        deviceName = '${iosInfo.name} ${iosInfo.model}';
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/register_device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': _deviceId,
          'device_name': deviceName,
          'platform': platform,
          'app_version': '1.0.0',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Device registered successfully');
      } else {
        debugPrint('Failed to register device: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error registering device: $e');
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
}

enum SyncStatus {
  offline,
  syncing,
  upToDate,
  error,
}

class SyncResult {
  final bool success;
  final String message;
  int? operationsProcessed;

  SyncResult({required this.success, required this.message, this.operationsProcessed});
} 
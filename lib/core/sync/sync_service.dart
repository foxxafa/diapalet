import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../local/database_helper.dart';
import '../network/network_info.dart';
import '../network/api_config.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NetworkInfo _networkInfo = NetworkInfoImpl(Connectivity());
  Timer? _syncTimer;
  
  // Configuration
  static const Duration syncInterval = Duration(seconds: 30);
  static final String baseUrl = ApiConfig.host;
  static const String _lastSyncPrefKey = 'last_sync_timestamp';
  
  String? _deviceId;
  bool _isInitialized = false;
  bool _isSyncing = false;

  // Stream controller for sync status updates
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _deviceId = await _getDeviceId();
    // No need to await registration, can happen in background
    _registerDevice(); 
    _startBackgroundSync();
    _isInitialized = true;
    
    debugPrint('SyncService initialized with device ID: $_deviceId');
    // Perform an initial sync right away
    triggerSync();
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
        Uri.parse('$baseUrl/api/register_device'),
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

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (_) => _performBackgroundSync());
  }

  Future<void> _performBackgroundSync() async {
    if (_isSyncing || !await _networkInfo.isConnected) return;
    
    debugPrint('Performing background sync...');
    await syncPendingOperations();
    await downloadMasterData(); // Also download master data during background sync
  }

  Future<void> triggerSync() async {
    _syncStatusController.add(SyncStatus.syncing);
    debugPrint("Manual sync triggered...");
    await syncPendingOperations();
    await downloadMasterData();
    debugPrint("Manual sync finished.");
  }

  Future<SyncResult> syncPendingOperations() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
        operationsProcessed: 0,
      );
    }

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      if (!await _networkInfo.isConnected) {
        _syncStatusController.add(SyncStatus.offline);
        return SyncResult(
          success: false,
          message: 'No network connection',
          operationsProcessed: 0,
        );
      }

      // Get pending operations from local database
      final pendingOperations = await _getPendingOperations();
      
      if (pendingOperations.isEmpty) {
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(
          success: true,
          message: 'No pending operations',
          operationsProcessed: 0,
        );
      }

      // Upload operations to server
      final uploadResult = await _uploadOperations(pendingOperations);
      
      if (uploadResult['success'] == true) {
        // Mark operations as synced in local database
        await _markOperationsAsSynced(pendingOperations);
        
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(
          success: true,
          message: 'Sync completed successfully',
          operationsProcessed: pendingOperations.length,
        );
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(
          success: false,
          message: uploadResult['error'] ?? 'Upload failed',
          operationsProcessed: 0,
        );
      }
    } catch (e) {
      debugPrint('Error during sync: $e');
      _syncStatusController.add(SyncStatus.error);
      return SyncResult(
        success: false,
        message: 'Sync error: $e',
        operationsProcessed: 0,
      );
    } finally {
      _isSyncing = false;
    }
  }

  Future<List<PendingOperation>> _getPendingOperations() async {
    final db = await _dbHelper.database;

    final rows = await db.query('pending_operation', orderBy: 'id ASC');

    return rows.map((row) {
      return PendingOperation(
        id: row['id'] as int,
        localId: null,
        operationType: row['operation_type'] as String,
        operationData: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        createdAt: DateTime.parse(row['created_at'] as String),
        tableName: 'pending_operation',
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _uploadOperations(List<PendingOperation> operations) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/upload'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': _deviceId,
          'operations': operations.map((op) => {
            'operation_type': op.operationType,
            'operationData': {
              ...op.operationData,
              'device_id': _deviceId,
            },
          }).toList(),
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e'
      };
    }
  }

  Future<void> _markOperationsAsSynced(List<PendingOperation> operations) async {
    final db = await _dbHelper.database;

    // We use a transaction to ensure that if any part of the deletion fails,
    // all changes are rolled back. This prevents partial data states.
    await db.transaction((txn) async {
      for (final operation in operations) {
        await txn.delete('pending_operation', where: 'id = ?', whereArgs: [operation.id]);
      }
    });
  }

  Future<List<PendingOperation>> getPendingOperationsForUI() async {
    return await _getPendingOperations();
  }

  Future<SyncResult> downloadMasterData() async {
    _syncStatusController.add(SyncStatus.syncing);
    try {
      if (!await _networkInfo.isConnected) {
        _syncStatusController.add(SyncStatus.offline);
        return SyncResult(
          success: false,
          message: 'No network connection',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final lastSyncTimestamp = prefs.getString(_lastSyncPrefKey);

      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': _deviceId,
          'last_sync': lastSyncTimestamp,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _updateLocalMasterData(data['data']);

          // Store the current timestamp as the last sync time
          final newSyncTimestamp = DateTime.now().toIso8601String();
          await prefs.setString(_lastSyncPrefKey, newSyncTimestamp);

          _syncStatusController.add(SyncStatus.upToDate);
          return SyncResult(
            success: true,
            message: 'Master data downloaded successfully',
          );
        } else {
          _syncStatusController.add(SyncStatus.error);
          return SyncResult(
            success: false,
            message: data['error'] ?? 'Download failed',
          );
        }
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(
          success: false,
          message: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      _syncStatusController.add(SyncStatus.error);
      return SyncResult(
        success: false,
        message: 'Download error: $e',
      );
    }
  }

  Future<void> _updateLocalMasterData(Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    final isIncremental = data.containsKey('is_incremental') && data['is_incremental'] == true;

    await db.transaction((txn) async {
      // If this is a full sync, clear old data first.
      if (!isIncremental) {
        await txn.delete('product');
        await txn.delete('location');
        await txn.delete('inventory_stock');
      }

      // Upsert Products
      final products = data['products'] as List<dynamic>? ?? [];
      for (final item in products) {
        final map = item as Map<String, dynamic>;
        await txn.insert(
          'product',
          {
            'id': map['id'], // Corrected: Store as INTEGER
            'name': map['name'],
            'code': map['code'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Upsert Locations
      final locations = data['locations'] as List<dynamic>? ?? [];
      for (final item in locations) {
        final map = item as Map<String, dynamic>;
        await txn.insert(
          'location',
          {
            'id': map['id'], // Storing ID now
            'name': map['name'],
            'code': map['code'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      
      // Upsert Inventory Stock
      final stock = data['inventory_stock'] as List<dynamic>? ?? [];
       for (final item in stock) {
        final map = item as Map<String, dynamic>;
        await txn.insert(
          'inventory_stock',
          {
            'urun_id': map['urun_id'],
            'location_id': map['location_id'],
            'quantity': map['quantity'],
            'pallet_barcode': map['pallet_barcode'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    
    debugPrint('Master data updated in local DB.');
  }

  void dispose() {
    _syncTimer?.cancel();
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
  int? operationsProcessed; // Made optional

  SyncResult({
    required this.success,
    required this.message,
    this.operationsProcessed,
  });
} 
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../local/database_helper.dart';
import '../network/network_info.dart';
import 'pending_operation.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  NetworkInfo? _networkInfo;
  Timer? _syncTimer;
  
  // Configuration
  static const String baseUrl = 'http://localhost:5000'; // Change this to your server URL
  static const Duration syncInterval = Duration(seconds: 30);
  
  String? _deviceId;
  bool _isInitialized = false;
  bool _isSyncing = false;

  // Stream controller for sync status updates
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _networkInfo = NetworkInfoImpl(Connectivity());
    _deviceId = await _getDeviceId();
    await _registerDevice();
    _startBackgroundSync();
    _isInitialized = true;
    
    debugPrint('SyncService initialized with device ID: $_deviceId');
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
      if (_networkInfo == null || !(await _networkInfo!.isConnected)) return;
      
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
    if (_isSyncing || _networkInfo == null || !(await _networkInfo!.isConnected)) return;
    
    debugPrint('Performing background sync...');
    await syncPendingOperations();
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
      if (_networkInfo == null || !(await _networkInfo!.isConnected)) {
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
    
    List<PendingOperation> operations = [];
    
    // Get unsynced goods receipts
    final unsyncedReceipts = await db.query(
      'goods_receipt',
      where: 'synced = ?',
      whereArgs: [0],
    );
    
    for (final receipt in unsyncedReceipts) {
      final items = await db.query(
        'goods_receipt_item',
        where: 'receipt_id = ?',
        whereArgs: [receipt['id']],
      );
      
      operations.add(PendingOperation(
        localId: receipt['id'] as int,
        operationType: 'goods_receipt',
        operationData: {
          'external_id': receipt['external_id'],
          'invoice_number': receipt['invoice_number'],
          'receipt_date': receipt['receipt_date'],
          'items': items.map((item) => {
            'product_id': item['product_id'],
            'quantity': item['quantity'],
            'location': item['location'],
            'pallet_id': item['pallet_id'],
          }).toList(),
        },
        createdAt: DateTime.now(), // You might want to store this in the DB
        tableName: 'goods_receipt',
      ));
    }
    
    // Get unsynced transfer operations
    final unsyncedTransfers = await db.query(
      'transfer_operation',
      where: 'synced = ?',
      whereArgs: [0],
    );
    
    for (final transfer in unsyncedTransfers) {
      final items = await db.query(
        'transfer_item',
        where: 'operation_id = ?',
        whereArgs: [transfer['id']],
      );
      
      operations.add(PendingOperation(
        localId: transfer['id'] as int,
        operationType: transfer['operation_type'] as String,
        operationData: {
          'source_location': transfer['source_location'],
          'target_location': transfer['target_location'],
          'pallet_id': transfer['pallet_id'],
          'transfer_date': transfer['transfer_date'],
          'items': items.map((item) => {
            'product_id': item['product_id'],
            'quantity': item['quantity'],
          }).toList(),
        },
        createdAt: DateTime.now(),
        tableName: 'transfer_operation',
      ));
    }
    
    return operations;
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
            'operation_data': {
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
    
    for (final operation in operations) {
      await db.update(
        operation.tableName,
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [operation.localId],
      );
    }
  }

  Future<List<PendingOperation>> getPendingOperationsForUI() async {
    return await _getPendingOperations();
  }

  Future<SyncResult> downloadMasterData() async {
    try {
      if (_networkInfo == null || !(await _networkInfo!.isConnected)) {
        return SyncResult(
          success: false,
          message: 'No network connection',
          operationsProcessed: 0,
        );
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': _deviceId,
          'last_sync_timestamp': null, // You can implement incremental sync later
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _updateLocalMasterData(data['data']);
          return SyncResult(
            success: true,
            message: 'Master data downloaded successfully',
            operationsProcessed: 0,
          );
        } else {
          return SyncResult(
            success: false,
            message: data['error'] ?? 'Download failed',
            operationsProcessed: 0,
          );
        }
      } else {
        return SyncResult(
          success: false,
          message: 'HTTP ${response.statusCode}: ${response.body}',
          operationsProcessed: 0,
        );
      }
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Download error: $e',
        operationsProcessed: 0,
      );
    }
  }

  Future<void> _updateLocalMasterData(Map<String, dynamic> masterData) async {
    final db = await _dbHelper.database;
    
    // Update products
    if (masterData['products'] != null) {
      await db.delete('product'); // Clear existing
      for (final product in masterData['products']) {
        await db.insert('product', {
          'id': product['id'].toString(),
          'name': product['name'],
          'code': product['code'],
        });
      }
    }
    
    // Update locations
    if (masterData['locations'] != null) {
      await db.delete('location'); // Clear existing
      for (final location in masterData['locations']) {
        await db.insert('location', {
          'name': location['name'],
        });
      }
    }
    
    debugPrint('Master data updated successfully');
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
  final int operationsProcessed;

  SyncResult({
    required this.success,
    required this.message,
    required this.operationsProcessed,
  });
} 
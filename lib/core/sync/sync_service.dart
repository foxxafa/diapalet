import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class SyncResult {
  final bool success;
  final String message;
  SyncResult(this.success, this.message);
}

enum SyncStatus {
  offline,
  online,
  syncing,
  upToDate,
  error,
}

class SyncService {
  final Dio _dio;
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;
  static const _lastSyncKey = 'last_sync_timestamp';

  bool _isSyncingDownload = false;
  bool _isSyncingUpload = false;

  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();

  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  SyncService({
    required Dio dio,
    required DatabaseHelper dbHelper,
    required Connectivity connectivity,
  })  : _dio = dio,
        _dbHelper = dbHelper,
        _connectivity = connectivity {
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      final isConnected = result != ConnectivityResult.none;
      if (isConnected) {
        _syncStatusController.add(SyncStatus.online);
        // Automatically try to upload pending operations on reconnect
        uploadPendingOperations();
      } else {
        _syncStatusController.add(SyncStatus.offline);
      }
    });
  }

  Future<String?> _getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  Future<void> _setLastSyncTimestamp(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, timestamp);
  }

  Future<bool> _isConnected() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // --- PUBLIC API ---

  Future<SyncResult> downloadMasterData() async {
    final hasConnection = await _connectivity.checkConnectivity();
    if (hasConnection == ConnectivityResult.none) {
        return SyncResult(false, "No internet connection.");
    }

    _syncStatusController.add(SyncStatus.syncing);

    try {
      final response = await _dio.get(ApiConfig.syncDownload);

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await _dbHelper.replaceTables(data);
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(true, "Master data synced successfully.");
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(false, "Server error: ${response.statusCode}");
      }
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      debugPrint("Error during master data download: $e");
      return SyncResult(false, "An error occurred: $e");
    }
  }

  Future<SyncResult> uploadPendingOperations() async {
     final hasConnection = await _connectivity.checkConnectivity();
    if (hasConnection == ConnectivityResult.none) {
        return SyncResult(false, "No internet connection.");
    }
    
    _syncStatusController.add(SyncStatus.syncing);

    final pendingOperations = await getPendingOperations();
    if (pendingOperations.isEmpty) {
      _syncStatusController.add(SyncStatus.upToDate);
      return SyncResult(true, "No pending operations to sync.");
    }

    try {
      final response = await _dio.post(
        ApiConfig.syncUpload,
        data: jsonEncode(pendingOperations.map((op) => op.toJson()).toList()),
      );

      if (response.statusCode == 200) {
        final results = response.data['results'] as List;
        for (var result in results) {
          final int opId = result['operation_id'];
          final bool success = result['success'];
          if (success) {
            await _dbHelper.deletePendingOperation(opId);
          } else {
            await _dbHelper.updatePendingOperationStatus(opId, 'failed', error: result['error']);
          }
        }
        _syncStatusController.add(SyncStatus.upToDate);
        return SyncResult(true, "Sync process completed.");
      } else {
        _syncStatusController.add(SyncStatus.error);
        return SyncResult(false, "Server error: ${response.statusCode}");
      }
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      debugPrint("Error during pending operations upload: $e");
      return SyncResult(false, "An error occurred: $e");
    }
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    return _dbHelper.getPendingOperations();
  }

  Future<void> deleteOperation(int operationId) async {
    await _dbHelper.deletePendingOperation(operationId);
  }

  Future<void> retryOperation(int operationId) async {
    await _dbHelper.updatePendingOperationStatus(operationId, 'pending');
    // Attempt to upload immediately
    uploadPendingOperations();
  }

  void dispose() {
    _syncStatusController.close();
  }

  // --- PRIVATE HELPERS ---

  Future<void> _updateLocalDatabase(Map<String, dynamic> data) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Helper to perform batch upserts. `ConflictAlgorithm.replace` is effectively an UPSERT.
      Future<void> batchUpsert(String table, List<dynamic> records) async {
        if (records.isEmpty) return;
        
        final batch = txn.batch();
        for (var record in records) {
          // The server might send back datetimes as strings. SQLite expects strings.
          final sanitizedRecord = (record as Map<String, dynamic>).map((key, value) => MapEntry(key, value.toString()));
          batch.insert(
            table,
            sanitizedRecord,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
      
      // The order of operations is critical due to foreign key constraints.
      // 1. Master data that other tables depend on
      await batchUpsert('location', data['locations'] ?? []);
      await batchUpsert('product', data['urunler'] ?? []);
      await batchUpsert('employee', data['employees'] ?? []);
      await batchUpsert('purchase_order', data['satin_alma_siparis_fis'] ?? []);
      await batchUpsert('purchase_order_item', data['satin_alma_siparis_fis_satir'] ?? []);

      // 2. State data - It's often safer to wipe and replace state tables.
      await txn.delete('inventory_stock');
      await batchUpsert('inventory_stock', data['inventory_stock'] ?? []);

      // 3. Transactional log data (handle with care, maybe append-only logic is needed in future)
      await batchUpsert('goods_receipts', data['goods_receipts'] ?? []);
      await batchUpsert('goods_receipt_items', data['goods_receipt_items'] ?? []);
      await batchUpsert('inventory_transfers', data['inventory_transfers'] ?? []);
    });
    debugPrint("Local database updated from sync.");
  }
} 
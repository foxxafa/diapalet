import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class SyncService {
  final Dio _dio;
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;
  static const _lastSyncKey = 'last_sync_timestamp';

  bool _isSyncingDownload = false;
  bool _isSyncingUpload = false;

  SyncService({
    required Dio dio,
    required DatabaseHelper dbHelper,
    required Connectivity connectivity,
  })  : _dio = dio,
        _dbHelper = dbHelper,
        _connectivity = connectivity;

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

  Future<void> downloadMasterData({bool force = false}) async {
    if (_isSyncingDownload && !force) {
      debugPrint("Download sync already in progress.");
      return;
    }
    if (!await _isConnected()) {
      debugPrint("No internet connection for download.");
      return;
    }

    _isSyncingDownload = true;
    debugPrint("Starting master data download...");

    try {
      final lastSync = await _getLastSyncTimestamp();
      final response = await _dio.post(
        ApiConfig.syncDownload,
        data: {'last_sync': lastSync},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        await _updateLocalDatabase(data);
        final newTimestamp = response.data['timestamp'] as String?;
        if (newTimestamp != null) {
          await _setLastSyncTimestamp(newTimestamp);
        }
        debugPrint("Master data download successful.");
      } else {
        throw Exception('Failed to download data: ${response.data['error']}');
      }
    } catch (e) {
      debugPrint("Error during data download: $e");
      rethrow;
    } finally {
      _isSyncingDownload = false;
    }
  }

  Future<void> uploadPendingOperations() async {
    if (_isSyncingUpload) {
      debugPrint("Upload sync already in progress.");
      return;
    }
    if (!await _isConnected()) {
      debugPrint("No internet connection for upload.");
      return;
    }

    _isSyncingUpload = true;
    debugPrint("Starting pending operations upload...");

    final db = await _dbHelper.database;
    final pendingOps = await db.query('pending_operation', where: 'status = ?', whereArgs: ['pending']);

    if (pendingOps.isEmpty) {
      debugPrint("No pending operations to upload.");
      _isSyncingUpload = false;
      return;
    }

    final operationsPayload = pendingOps.map((op) {
      return {
        'id': op['id'],
        'type': op['type'],
        'data': jsonDecode(op['data'] as String),
      };
    }).toList();

    try {
      final response = await _dio.post(
        ApiConfig.syncUpload,
        data: {'operations': operationsPayload},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final results = response.data['results'] as List<dynamic>;
        for (final result in results) {
            final opId = result['operation']['id'];
            if (result['result']['status'] == 'success') {
                await db.delete('pending_operation', where: 'id = ?', whereArgs: [opId]);
            } else {
                await db.update(
                'pending_operation',
                {'status': 'failed', 'error_message': result['result']['error']},
                where: 'id = ?',
                whereArgs: [opId],
                );
            }
        }
        debugPrint("Pending operations uploaded successfully.");
      } else {
        throw Exception("Failed to upload operations: ${response.data['error']}");
      }
    } catch (e) {
      debugPrint("Error during data upload: $e");
      // Optionally mark ops as failed on network error
      rethrow;
    } finally {
      _isSyncingUpload = false;
    }
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
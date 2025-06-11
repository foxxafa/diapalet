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

  /// Public wrapper to manually trigger the periodic background sync timer.
  /// The timer is already started in [initialize], but some UI elements might
  /// want to restart or force-enable it (e.g., on HomeScreen init).
  void startPeriodicSync() {
    _startBackgroundSync();
  }

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

  Future<SyncResult> downloadMasterData({bool fullSync = false, bool force = false}) async {
    if (_isSyncingDownload && !force) {
      return SyncResult(success: false, message: 'Download sync already in progress.');
    }
     if (!await _networkInfo.isConnected) {
      _syncStatusController.add(SyncStatus.offline);
      return SyncResult(success: false, message: 'No network connection.');
    }

    if(force) {
      _syncTimer?.cancel(); // Stop background timer to prevent conflict
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
      if (force) {
        _startBackgroundSync(); // Restart background timer
      }
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

      // Corrected: Use singular keys as sent by the Python server
      final products = data['product'] as List? ?? [];
      for (final item in products) {
        await txn.insert('product', {
          'id': item['id'],
          'name': item['name'],
          'code': item['code'],
          'is_active': item['is_active'],
          'created_at': item['created_at'],
          'updated_at': item['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final locations = data['location'] as List? ?? [];
      for (final item in locations) {
        await txn.insert('location', {
          'id': item['id'],
          'name': item['name'],
          'code': item['code'],
          'is_active': item['is_active'],
          'latitude': item['latitude'],
          'longitude': item['longitude'],
          'address': item['address'],
          'description': item['description'],
          'created_at': item['created_at'],
          'updated_at': item['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // --- Start of Pallet Handling ---
      // Collect all unique pallet barcodes from inventory and goods receipts to pre-populate the pallet table
      final Set<String> palletBarcodes = {};
      final inventoryStock = data['inventory_stock'] as List? ?? [];
      final goodsReceiptItems = data['goods_receipt_item'] as List? ?? [];

      for (final item in inventoryStock) {
        if (item['pallet_barcode'] != null && item['pallet_barcode'].isNotEmpty) {
          palletBarcodes.add(item['pallet_barcode']);
        }
      }
      for (final item in goodsReceiptItems) {
        if (item['pallet_barcode'] != null && item['pallet_barcode'].isNotEmpty) {
          palletBarcodes.add(item['pallet_barcode']);
        }
      }
      
      // Upsert pallets. This ensures foreign key constraints will be met.
      final Map<String, int> palletLocations = {};
       for (final item in inventoryStock) {
        if (item['pallet_barcode'] != null && item['pallet_barcode'].isNotEmpty && palletLocations[item['pallet_barcode']] == null) {
          palletLocations[item['pallet_barcode']] = item['location_id'];
        }
      }

      for (final barcode in palletBarcodes) {
        final locationId = palletLocations[barcode] ?? 1;
        await txn.insert('pallet', {
          'id': barcode,
          'location_id': locationId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint("Upserted ${palletBarcodes.length} pallets.");
      // --- End of Pallet Handling ---

      final purchaseOrders = data['purchase_order'] as List? ?? [];
      for (final item in purchaseOrders) {
        await txn.insert('purchase_order', {
          'id': item['id'],
          'po_id': item['po_id'],
          'tarih': item['tarih'],
          'status': item['status'],
          'notlar': item['notlar'],
          'user': item['user'],
          'created_at': item['created_at'],
          'updated_at': item['updated_at'],
          'gun': item['gun'],
          'lokasyon_id': item['lokasyon_id'],
          'invoice': item['invoice'],
          'delivery': item['delivery'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final purchaseOrderItems = data['purchase_order_item'] as List? ?? [];
      for (final item in purchaseOrderItems) {
        await txn.insert('purchase_order_item', {
          'id': item['id'],
          'siparis_id': item['siparis_id'],
          'urun_id': item['urun_id'],
          'miktar': item['miktar'],
          'birim': item['birim'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final goodsReceipts = data['goods_receipt'] as List? ?? [];
      for (final item in goodsReceipts) {
        await txn.insert('goods_receipt', {
          'id': item['id'],
          'siparis_id': item['siparis_id'],
          'employee_id': item['employee_id'],
          'invoice_number': item['invoice_number'],
          'receipt_date': item['receipt_date'],
          'created_at': item['created_at'],
          'synced': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final item in goodsReceiptItems) {
        await txn.insert('goods_receipt_item', {
          'id': item['id'],
          'receipt_id': item['receipt_id'],
          'product_id': item['urun_id'],
          'quantity': item['quantity_received'],
          'pallet_id': item['pallet_barcode'],
          'location_id': palletLocations[item['pallet_barcode']] ?? 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      
      for (final item in inventoryStock) {
        await txn.insert('inventory_stock', {
          'id': item['id'],
          'urun_id': item['urun_id'],
          'location_id': item['location_id'],
          'quantity': item['quantity'],
          'pallet_barcode': item['pallet_barcode'],
          'updated_at': item['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      debugPrint("Local database updated successfully.");
    });
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

  Future<void> resetLocalData() async {
    await _dbHelper.resetDatabase();
    // After deletion, the DB is null. The next call to `_dbHelper.database`
    // will automatically re-initialize and call _onCreate.
    debugPrint("Local database has been reset.");
  }

  Future<SyncResult> downloadSpecifiedTables(List<String> serverTableNames) async {
    if (_isSyncingDownload) {
      return SyncResult(success: false, message: 'Download sync already in progress.');
    }
    if (!await _networkInfo.isConnected) {
      _syncStatusController.add(SyncStatus.offline);
      return SyncResult(success: false, message: 'No network connection.');
    }

    _isSyncingDownload = true;
    _syncStatusController.add(SyncStatus.syncing);
    debugPrint("Starting specified table download for: ${serverTableNames.join(', ')}");

    final db = await _dbHelper.database;

    try {
      for (final serverTableName in serverTableNames) {
        final localTableName = _mapServerToLocalTable(serverTableName);
        if (localTableName == null) {
          debugPrint("Skipping unknown table: $serverTableName");
          continue;
        }

        debugPrint("Fetching $serverTableName -> $localTableName...");
        
        final response = await http.get(
          Uri.parse('$_baseUrl/api/data/$serverTableName'),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          
          await db.transaction((txn) async {
            // Clear the local table before inserting new data
            await txn.delete(localTableName);
            debugPrint("Cleared local table: $localTableName");

            // Insert new data
            for (final item in data) {
              final mappedItem = _mapServerToLocalRecord(serverTableName, item);
              if (mappedItem != null) {
                await txn.insert(localTableName, mappedItem, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
            debugPrint("Inserted ${data.length} records into $localTableName.");
          });
        } else {
          throw Exception('Failed to download $serverTableName: HTTP ${response.statusCode}');
        }
      }

      _syncStatusController.add(SyncStatus.upToDate);
      debugPrint("Specified table download finished successfully.");
      return SyncResult(success: true, message: 'Seçilen tablolar başarıyla indirildi.');

    } catch (e) {
      debugPrint('Download error for specified tables: $e');
      _syncStatusController.add(SyncStatus.error);
      return SyncResult(success: false, message: 'Veri indirme hatası: $e');
    } finally {
      _isSyncingDownload = false;
    }
  }

  String? _mapServerToLocalTable(String serverTableName) {
    const map = {
      'urunler': 'product',
      'locations': 'location',
      'satin_alma_siparis_fis': 'purchase_order',
      'satin_alma_siparis_fis_satir': 'purchase_order_item',
      'goods_receipts': 'goods_receipt',
      'goods_receipt_items': 'goods_receipt_item',
      'inventory_stock': 'inventory_stock',
    };
    return map[serverTableName];
  }

  Map<String, dynamic>? _mapServerToLocalRecord(String serverTableName, Map<String, dynamic> serverRecord) {
    try {
      if (serverTableName == 'urunler') {
        final id   = serverRecord['UrunId'];
        final name = serverRecord['UrunAdi'];
        final code = serverRecord['StokKodu'];
        if (id == null) {
          return null; // product id is mandatory
        }
        final safeName = (name == null || (name as String).trim().isEmpty)
            ? 'Unnamed Product $id'
            : name;
        final safeCode = (code == null || (code as String).trim().isEmpty)
            ? 'UNKNOWN_$id'
            : code;
        return {
          'id': id,
          'name': safeName,
          'code': safeCode,
          'is_active': serverRecord['aktif'] ?? 1,
          'created_at': serverRecord['created_at'],
          'updated_at': serverRecord['updated_at'],
        };
      }
      if (serverTableName == 'locations') {
        return {
          'id': serverRecord['id'],
          'name': serverRecord['name'],
          'code': serverRecord['code'],
          'is_active': serverRecord['is_active'],
          'latitude': serverRecord['latitude'],
          'longitude': serverRecord['longitude'],
          'address': serverRecord['address'],
          'description': serverRecord['description'],
          'created_at': serverRecord['created_at'],
          'updated_at': serverRecord['updated_at'],
        };
      }
      if (serverTableName == 'satin_alma_siparis_fis') {
        return {
          'id': serverRecord['id'],
          'po_id': serverRecord['po_id'],
          'tarih': serverRecord['tarih'],
          'status': serverRecord['status'],
          'notlar': serverRecord['notlar'],
          'user': serverRecord['user'],
          'created_at': serverRecord['created_at'],
          'updated_at': serverRecord['updated_at'],
          'gun': serverRecord['gun'],
          'lokasyon_id': serverRecord['lokasyon_id'],
          'invoice': serverRecord['invoice'],
          'delivery': serverRecord['delivery'],
        };
      }
      if (serverTableName == 'satin_alma_siparis_fis_satir') {
        return {
          'id': serverRecord['id'],
          'siparis_id': serverRecord['siparis_id'],
          'urun_id': serverRecord['urun_id'],
          'miktar': serverRecord['miktar'],
          'birim': serverRecord['birim'],
          'productName': serverRecord['productName'] ?? 'N/A',
        };
      }
      if (serverTableName == 'goods_receipts') {
        return {
          'id': serverRecord['id'],
          'siparis_id': serverRecord['siparis_id'],
          'employee_id': serverRecord['employee_id'],
          'invoice_number': serverRecord['invoice_number'],
          'receipt_date': serverRecord['receipt_date'],
          'created_at': serverRecord['created_at'],
          'synced': 1,
        };
      }
      if (serverTableName == 'goods_receipt_items') {
        return {
          'id': serverRecord['id'],
          'receipt_id': serverRecord['receipt_id'],
          'product_id': serverRecord['urun_id'],
          'quantity': serverRecord['quantity_received'],
          'location_id': serverRecord['location_id'] ?? 1, // Default to a valid location ID
          'pallet_id': serverRecord['pallet_barcode'],
        };
      }
      if (serverTableName == 'inventory_stock') {
        return {
          'id': serverRecord['id'],
          'urun_id': serverRecord['urun_id'],
          'location_id': serverRecord['location_id'],
          'quantity': serverRecord['quantity'],
          'pallet_barcode': serverRecord['pallet_barcode'],
          'updated_at': serverRecord['updated_at'],
        };
      }
      return serverRecord;
    } catch (e) {
      debugPrint("Error mapping record for table $serverTableName: $e. Record: $serverRecord");
      return null;
    }
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
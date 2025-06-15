// lib/core/local/database_helper.dart
import 'dart:io';

import 'package:diapalet/core/sync/sync_log.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/sync/pending_operation.dart';

class DatabaseHelper {
  static const _databaseName = "Diapallet.db";
  static const _databaseVersion = 11; // Version remains the same if schema doesn't change

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    debugPrint('DB path: $path');
    return await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Upgrading database from version $oldVersion to $newVersion...");
    await _dropAllTables(db);
    await _onCreate(db);
    debugPrint("Database upgrade complete.");
  }

  Future<void> _onCreate(Database db, [int? version]) async {
    debugPrint("Creating database schema version $_databaseVersion...");

    await db.execute('''
      CREATE TABLE locations (id INTEGER PRIMARY KEY, name TEXT NOT NULL, code TEXT, is_active INTEGER DEFAULT 1, address TEXT, description TEXT, latitude REAL, longitude REAL, created_at TEXT, updated_at TEXT)
    ''');
    await db.execute('''
      CREATE TABLE employees (id INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT, location_id INTEGER, role TEXT, username TEXT, password TEXT, start_date TEXT, end_date TEXT, is_active INTEGER DEFAULT 1, created_at TEXT, updated_at TEXT, photo TEXT)
    ''');
    await db.execute('''
      CREATE TABLE urunler (UrunId INTEGER PRIMARY KEY, StokKodu TEXT UNIQUE, UrunAdi TEXT NOT NULL, AdetFiyati REAL, KutuFiyati REAL, Pm1 REAL, Pm2 REAL, Pm3 REAL, Barcode1 TEXT, Barcode2 TEXT, Barcode3 TEXT, Vat REAL, Birim1 TEXT, BirimKey1 INTEGER, Birim2 TEXT, BirimKey2 INTEGER, Barcode4 TEXT, aktif INTEGER DEFAULT 1, marka_id INTEGER, kategori_id INTEGER, grup_id INTEGER, qty INTEGER, size TEXT, unitkg REAL, palletqty INTEGER, HSCode TEXT, rafkoridor TEXT, rafno INTEGER, rafkat TEXT, rafomru INTEGER, imsrc TEXT, created_at TEXT, updated_at TEXT)
    ''');
    await db.execute('''
      CREATE TABLE satin_alma_siparis_fis (id INTEGER PRIMARY KEY, po_id TEXT, tarih TEXT, status INTEGER, notlar TEXT, user TEXT, gun INTEGER, lokasyon_id INTEGER, invoice TEXT, delivery INTEGER, created_at TEXT, updated_at TEXT)
    ''');
    await db.execute('''
      CREATE TABLE goods_receipts (id INTEGER PRIMARY KEY, siparis_id INTEGER, invoice_number TEXT, employee_id INTEGER, receipt_date TEXT, created_at TEXT, FOREIGN KEY (siparis_id) REFERENCES satin_alma_siparis_fis (id) ON DELETE SET NULL)
    ''');
    await db.execute('''
      CREATE TABLE satin_alma_siparis_fis_satir (id INTEGER PRIMARY KEY, siparis_id INTEGER, urun_id INTEGER, miktar REAL, ort_son_30 INTEGER, ort_son_60 INTEGER, ort_son_90 INTEGER, tedarikci_id INTEGER, tedarikci_fis_id INTEGER, invoice TEXT, birim TEXT, layer INTEGER, notes TEXT, FOREIGN KEY (siparis_id) REFERENCES satin_alma_siparis_fis (id) ON DELETE CASCADE, FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE CASCADE)
    ''');
    await db.execute('''
      CREATE TABLE goods_receipt_items (id INTEGER PRIMARY KEY, receipt_id INTEGER NOT NULL, urun_id INTEGER NOT NULL, quantity_received REAL NOT NULL, pallet_barcode TEXT, FOREIGN KEY (receipt_id) REFERENCES goods_receipts (id) ON DELETE CASCADE, FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE CASCADE)
    ''');
    await db.execute('''
      CREATE TABLE inventory_stock (id INTEGER PRIMARY KEY, urun_id INTEGER NOT NULL, location_id INTEGER NOT NULL, quantity REAL NOT NULL, pallet_barcode TEXT, updated_at TEXT NOT NULL, UNIQUE (urun_id, location_id, pallet_barcode), FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE CASCADE, FOREIGN KEY (location_id) REFERENCES locations (id) ON DELETE CASCADE)
    ''');
    await db.execute('''
      CREATE TABLE inventory_transfers (id INTEGER PRIMARY KEY, urun_id INTEGER NOT NULL, from_location_id INTEGER NOT NULL, to_location_id INTEGER NOT NULL, quantity REAL NOT NULL, pallet_barcode TEXT, employee_id INTEGER, transfer_date TEXT, created_at TEXT, FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE CASCADE, FOREIGN KEY (from_location_id) REFERENCES locations (id) ON DELETE CASCADE, FOREIGN KEY (to_location_id) REFERENCES locations (id) ON DELETE CASCADE)
    ''');
    await db.execute('''
      CREATE TABLE pending_operation (id INTEGER PRIMARY KEY, type TEXT NOT NULL, data TEXT NOT NULL, created_at TEXT NOT NULL, status TEXT DEFAULT 'pending', attempts INTEGER DEFAULT 0, error_message TEXT)
    ''');
    await db.execute('''
      CREATE TABLE sync_log (id INTEGER PRIMARY KEY, timestamp TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL, message TEXT)
    ''');
    debugPrint("All tables created for version $_databaseVersion.");
  }

  Future<void> _dropAllTables(Database db) {
    final tables = [
      'pending_operation', 'sync_log', 'inventory_transfers', 'inventory_stock',
      'goods_receipt_items', 'satin_alma_siparis_fis_satir', 'goods_receipts',
      'satin_alma_siparis_fis', 'urunler', 'employees', 'locations',
    ];
    return db.transaction((txn) async {
      for (final table in tables) {
        await txn.execute('DROP TABLE IF EXISTS $table');
      }
    });
  }

  Future<void> replaceTables(Map<String, dynamic> tableData) async {
    final db = await database;
    final orderedTableNames = [
      'locations', 'employees', 'urunler', 'satin_alma_siparis_fis',
      'goods_receipts', 'satin_alma_siparis_fis_satir', 'goods_receipt_items',
      'inventory_stock', 'inventory_transfers'
    ];

    await db.transaction((txn) async {
      for (final tableName in orderedTableNames.reversed) {
        if (tableData.containsKey(tableName)) {
          await txn.delete(tableName);
        }
      }

      for (final tableName in orderedTableNames) {
        if (!tableData.containsKey(tableName)) continue;

        final records = tableData[tableName] as List<dynamic>?;
        if (records == null) continue;

        for (final record in records) {
          final filteredRecord = Map<String, dynamic>.from(record);
          final tableInfo = await txn.rawQuery('PRAGMA table_info($tableName)');
          final columnNames = tableInfo.map((row) => row['name'] as String).toSet();
          filteredRecord.removeWhere((key, value) => !columnNames.contains(key));
          await txn.insert(tableName, filteredRecord, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> addSyncLog(String type, String status, String message) async {
    final db = await database;
    await db.insert('sync_log', {'timestamp': DateTime.now().toIso8601String(), 'type': type, 'status': status, 'message': message,});
  }

  Future<List<SyncLog>> getSyncLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('sync_log', orderBy: 'timestamp DESC', limit: 100);
    return maps.map((map) => SyncLog.fromMap(map)).toList();
  }

  /// [DÜZELTME] Bekleyen işlemleri "ilk giren ilk çıkar" (FIFO) mantığıyla almak
  /// için sıralama `id ASC` olarak değiştirildi.
  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pending_operation', orderBy: 'id ASC');
    return maps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<void> deletePendingOperation(int id) async {
    final db = await database;
    await db.delete('pending_operation', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePendingOperationStatus(int id, String status, {String? error}) async {
    final db = await database;
    await db.update('pending_operation', {'status': status, 'error_message': error}, where: 'id = ?', whereArgs: [id]);
  }
}

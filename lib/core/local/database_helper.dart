// lib/core/local/database_helper.dart
import 'dart:io';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const _databaseName = "Diapallet_v2.db";
  // DÜZELTME: Şema tekrar değiştiği için veritabanı versiyonunu artırıyoruz.
  // Bu, onUpgrade metodunun çalışmasını ve tabloların doğru şema ile yeniden kurulmasını sağlar.
  static const _databaseVersion = 9;

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
    debugPrint('DB Yolu: $path');
    return await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Veritabanı $oldVersion sürümünden $newVersion sürümüne yükseltiliyor...");
    await _dropAllTables(db);
    await _createAllTables(db);
    debugPrint("Veritabanı yükseltmesi tamamlandı.");
  }

  Future<void> _createAllTables(Database db) async {
    debugPrint("Veritabanı tabloları (Sürüm $_databaseVersion) oluşturuluyor...");
    final batch = db.batch();

    batch.execute(PendingOperation.createTableQuery);
    batch.execute(SyncLog.createTableQuery);

    batch.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1,
        warehouse_id INTEGER, created_at TEXT, updated_at TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT, username TEXT UNIQUE,
        password TEXT, warehouse_id INTEGER, is_active INTEGER DEFAULT 1,
        created_at TEXT, updated_at TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE urunler (
        id INTEGER PRIMARY KEY, StokKodu TEXT UNIQUE, UrunAdi TEXT, Barcode1 TEXT, aktif INTEGER,
        created_at TEXT, updated_at TEXT
      )
    ''');
    // ANA DÜZELTME: Sunucudan gelen `gun`, `invoice`, `delivery` sütunları eklendi.
    batch.execute('''
      CREATE TABLE satin_alma_siparis_fis (
        id INTEGER PRIMARY KEY, po_id TEXT, tarih TEXT, status INTEGER,
        lokasyon_id INTEGER, notlar TEXT, user TEXT, gun INTEGER, 
        invoice TEXT, delivery INTEGER,
        created_at TEXT, updated_at TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE satin_alma_siparis_fis_satir (
        id INTEGER PRIMARY KEY, siparis_id INTEGER, urun_id INTEGER, miktar REAL, birim TEXT,
        notes TEXT, status INTEGER DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE TABLE goods_receipts (
        id INTEGER PRIMARY KEY, siparis_id INTEGER, invoice_number TEXT,
        employee_id INTEGER, receipt_date TEXT, created_at TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE goods_receipt_items (
        id INTEGER PRIMARY KEY, receipt_id INTEGER, urun_id INTEGER,
        quantity_received REAL, pallet_barcode TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE inventory_stock (
        id INTEGER PRIMARY KEY, urun_id INTEGER NOT NULL, location_id INTEGER NOT NULL,
        quantity REAL NOT NULL, pallet_barcode TEXT, updated_at TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE inventory_transfers (
        id INTEGER PRIMARY KEY, urun_id INTEGER, from_location_id INTEGER, to_location_id INTEGER,
        quantity REAL, pallet_barcode TEXT, employee_id INTEGER, transfer_date TEXT, created_at TEXT
      )
    ''');

    await batch.commit(noResult: true);
    debugPrint("Tüm tablolar başarıyla oluşturuldu.");
  }

  Future<void> _dropAllTables(Database db) async {
    final tables = [
      'pending_operation', 'sync_log', 'locations', 'employees', 'urunler',
      'satin_alma_siparis_fis', 'satin_alma_siparis_fis_satir', 'goods_receipts',
      'goods_receipt_items', 'inventory_stock', 'inventory_transfers'
    ];
    await db.transaction((txn) async {
      for (final table in tables) {
        await txn.execute('DROP TABLE IF EXISTS $table');
      }
    });
    debugPrint("Yükseltme için tüm eski tablolar silindi.");
  }

  Future<void> applyDownloadedData(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();

      for (var table in data.keys) {
        if (data[table] is! List) continue;
        final records = List<Map<String, dynamic>>.from(data[table]);
        if (records.isEmpty) continue;

        final fullRefreshTables = ['employees', 'urunler', 'locations', 'satin_alma_siparis_fis', 'satin_alma_siparis_fis_satir', 'inventory_stock', 'inventory_transfers', 'goods_receipts', 'goods_receipt_items'];
        if(fullRefreshTables.contains(table)) {
          txn.delete(table);
        }

        for (final record in records) {
          final sanitizedRecord = _sanitizeRecord(table, record);
          batch.insert(table, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await batch.commit(noResult: true);
      debugPrint("${data.length} tablo başarıyla senkronize edildi.");
    });
  }

  Map<String, dynamic> _sanitizeRecord(String table, Map<String, dynamic> record) {
    final newRecord = Map<String, dynamic>.from(record);
    if (table == 'urunler' && newRecord.containsKey('UrunId')) {
      newRecord['id'] = newRecord['UrunId'];
      newRecord.remove('UrunId');
    }
    return newRecord;
  }

  Future<void> addSyncLog(String type, String status, String message) async {
    final db = await database;
    await db.insert('sync_log', {
      'timestamp': DateTime.now().toIso8601String(),
      'type': type, 'status': status, 'message': message,
    });
  }

  Future<List<SyncLog>> getSyncLogs() async {
    final db = await database;
    final maps = await db.query('sync_log', orderBy: 'timestamp DESC', limit: 100);
    return maps.map((map) => SyncLog.fromMap(map)).toList();
  }

  Future<void> addPendingOperation(PendingOperation operation) async {
    final db = await database;
    await db.insert('pending_operation', operation.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation', where: "status = 'pending'", orderBy: 'id ASC');
    return maps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<void> deletePendingOperation(int id) async {
    final db = await database;
    await db.delete('pending_operation', where: 'id = ?', whereArgs: [id]);
  }
}

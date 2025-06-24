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
  // GÜNCELLEME: Şema değişikliği nedeniyle versiyon artırıldı.
  static const _databaseVersion = 13;

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
    // Şema tamamen yeniden oluşturulacağı için eski tabloları sil ve yenilerini oluştur.
    // Bu, 'locations' tablosunun 'warehouses_shelfs' olarak yeniden adlandırılmasını sağlar.
    await _dropAllTables(db);
    await _createAllTables(db);
    debugPrint("Veritabanı yükseltmesi tamamlandı.");
  }

  Future<void> _createAllTables(Database db) async {
    debugPrint("Veritabanı tabloları (Sürüm $_databaseVersion) oluşturuluyor...");
    final batch = db.batch();

    // 1. pending_operation tablosu
    batch.execute('''
      CREATE TABLE IF NOT EXISTS pending_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL,
        error_message TEXT,
        synced_at TEXT 
      )
    ''');

    // 2. sync_log tablosu
    batch.execute(SyncLog.createTableQuery);

    // --- UYGULAMANIN DİĞER TÜM TABLOLARI ---

    // GÜNCELLEME: 'locations' tablosu, sunucuyla uyumlu olması için 'warehouses_shelfs' olarak yeniden adlandırıldı.
    batch.execute('''
      CREATE TABLE IF NOT EXISTS warehouses_shelfs (
        id INTEGER PRIMARY KEY, name TEXT, code TEXT, is_active INTEGER DEFAULT 1,
        warehouse_id INTEGER, created_at TEXT, updated_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT, username TEXT UNIQUE,
        password TEXT, warehouse_id INTEGER, is_active INTEGER DEFAULT 1,
        created_at TEXT, updated_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS urunler (
        id INTEGER PRIMARY KEY, StokKodu TEXT UNIQUE, UrunAdi TEXT, Barcode1 TEXT, aktif INTEGER,
        created_at TEXT, updated_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS satin_alma_siparis_fis (
        id INTEGER PRIMARY KEY, po_id TEXT, tarih TEXT, status INTEGER,
        lokasyon_id INTEGER, notlar TEXT, user TEXT, gun INTEGER, 
        invoice TEXT, delivery INTEGER,
        created_at TEXT, updated_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS satin_alma_siparis_fis_satir (
        id INTEGER PRIMARY KEY, siparis_id INTEGER, urun_id INTEGER, miktar REAL, birim TEXT,
        notes TEXT, status INTEGER DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS goods_receipts (
        id INTEGER PRIMARY KEY, siparis_id INTEGER, invoice_number TEXT,
        employee_id INTEGER, receipt_date TEXT, created_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS goods_receipt_items (
        id INTEGER PRIMARY KEY, receipt_id INTEGER, urun_id INTEGER,
        quantity_received REAL, pallet_barcode TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS inventory_stock (
        id INTEGER PRIMARY KEY, urun_id INTEGER NOT NULL, location_id INTEGER NOT NULL,
        quantity REAL NOT NULL, pallet_barcode TEXT, updated_at TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS inventory_transfers (
        id INTEGER PRIMARY KEY, 
        urun_id INTEGER, 
        from_location_id INTEGER, 
        to_location_id INTEGER,
        quantity REAL, 
        from_pallet_barcode TEXT,
        pallet_barcode TEXT,
        employee_id INTEGER, 
        transfer_date TEXT, 
        created_at TEXT
      )
    ''');

    await batch.commit(noResult: true);
    debugPrint("Tüm tablolar başarıyla oluşturuldu.");
  }

  Future<void> _dropAllTables(Database db) async {
    // Silinecek tüm tabloların listesi
    // GÜNCELLEME: 'locations' yerine 'warehouses_shelfs' eklendi.
    final tables = [
      'pending_operation', 'sync_log', 'warehouses_shelfs', 'employees', 'urunler',
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

        // GÜNCELLEME: 'locations' yerine 'warehouses_shelfs' eklendi.
        // GÜNCELLEME 2: 'inventory_stock' TEKRAR EKLENDİ. Sunucu artık bu veriyi gönderdiği
        // için, istemcinin de bu tabloyu tam yenilemesi gerekiyor.
        final fullRefreshTables = ['employees', 'urunler', 'warehouses_shelfs', 'satin_alma_siparis_fis', 'satin_alma_siparis_fis_satir', 'goods_receipts', 'goods_receipt_items', 'inventory_stock'];
        if(fullRefreshTables.contains(table)) {
          await txn.delete(table);
        }

        for (final record in records) {
          final sanitizedRecord = _sanitizeRecord(table, record);
          batch.insert(table, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
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

  Future<void> addPendingOperation(PendingOperation operation) async {
    final db = await database;
    await db.insert('pending_operation', operation.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation', where: "status = ?", whereArgs: ['pending'], orderBy: 'created_at DESC');
    return maps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<List<PendingOperation>> getSyncedOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation', where: "status = ?", whereArgs: ['synced'], orderBy: 'synced_at DESC', limit: 100);
    return maps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<void> markOperationAsSynced(int id) async {
    final db = await database;
    await db.update(
      'pending_operation',
      {
        'status': 'synced',
        'synced_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateOperationWithError(int id, String errorMessage) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE pending_operation 
      SET error_message = ?, attempts = attempts + 1 
      WHERE id = ?
    ''', [errorMessage, id]);
  }

  Future<void> cleanupOldSyncedOperations({int days = 7}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final count = await db.delete(
      'pending_operation',
      where: "status = ? AND synced_at < ?",
      whereArgs: ['synced', cutoffDate.toIso8601String()],
    );
    if (count > 0) {
      debugPrint("$count adet eski senkronize edilmiş işlem temizlendi.");
    }
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
}

// core/local/database_helper.dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/sync/pending_operation.dart';

class DatabaseHelper {
  static const _databaseName = "Diapallet.db";
  // Veritabanı şeması değiştiği için versiyonu artırıyoruz.
  // Bu, onUpgrade'in tetiklenmesini sağlar.
  static const _databaseVersion = 3;

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

  // Geliştirme aşamasında en basit yükseltme stratejisi:
  // Eski tabloları sil ve yenilerini oluştur.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Upgrading database from version $oldVersion to $newVersion...");
    await _dropAllTables(db);
    await _onCreate(db);
    debugPrint("Database upgrade complete.");
  }

  Future<void> _onCreate(Database db, [int? version]) async {
    debugPrint("Creating database schema version $_databaseVersion...");

    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT,
        is_active INTEGER DEFAULT 1,
        address TEXT,
        description TEXT,
        latitude REAL,
        longitude REAL,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY,
        first_name TEXT,
        last_name TEXT,
        role TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE urunler (
        UrunId INTEGER PRIMARY KEY,
        StokKodu TEXT UNIQUE,
        UrunAdi TEXT NOT NULL,
        aktif INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // DÜZELTME: Tablo adı sunucu ile aynı yapıldı.
    await db.execute('''
      CREATE TABLE satin_alma_siparis_fis (
        id INTEGER PRIMARY KEY,
        po_id TEXT,
        tarih TEXT,
        status INTEGER,
        notlar TEXT,
        user TEXT,
        created_at TEXT,
        updated_at TEXT,
        gun INTEGER,
        lokasyon_id INTEGER,
        invoice TEXT,
        delivery INTEGER
      )
    ''');

    // DÜZELTME: Tablo adı sunucu ile aynı yapıldı ve Foreign Key düzeltildi.
    await db.execute('''
      CREATE TABLE satin_alma_siparis_fis_satir (
        id INTEGER PRIMARY KEY,
        siparis_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL,
        miktar REAL,
        birim TEXT,
        FOREIGN KEY (siparis_id) REFERENCES satin_alma_siparis_fis (id) ON DELETE CASCADE,
        FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE goods_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        siparis_id INTEGER,
        invoice_number TEXT,
        employee_id INTEGER,
        receipt_date TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE goods_receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL,
        quantity_received REAL NOT NULL,
        pallet_barcode TEXT,
        FOREIGN KEY (receipt_id) REFERENCES goods_receipts (id) ON DELETE CASCADE,
        FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        urun_id INTEGER NOT NULL,
        location_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        pallet_barcode TEXT,
        updated_at TEXT NOT NULL,
        UNIQUE (urun_id, location_id, pallet_barcode),
        FOREIGN KEY (urun_id) REFERENCES urunler (UrunId) ON DELETE CASCADE,
        FOREIGN KEY (location_id) REFERENCES locations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory_transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        urun_id INTEGER NOT NULL,
        from_location_id INTEGER NOT NULL,
        to_location_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        pallet_barcode TEXT,
        employee_id INTEGER,
        transfer_date TEXT,
        created_at TEXT,
        FOREIGN KEY (urun_id) REFERENCES urunler (UrunId),
        FOREIGN KEY (from_location_id) REFERENCES locations (id),
        FOREIGN KEY (to_location_id) REFERENCES locations (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        attempts INTEGER DEFAULT 0,
        error_message TEXT
      )
    ''');

    debugPrint("All tables created for version $_databaseVersion.");
  }

  Future<void> _dropAllTables(Database db) async {
    // Listeyi `onCreate`'in tersi sırayla yapmak daha güvenlidir (foreign key kısıtlamaları için).
    final tables = [
      'pending_operation',
      'inventory_transfers',
      'inventory_stock',
      'goods_receipt_items',
      'goods_receipts',
      'satin_alma_siparis_fis_satir',
      'satin_alma_siparis_fis',
      'urunler',
      'employees',
      'locations',
    ];
    for (final table in tables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    debugPrint("All tables dropped.");
  }

  Future<void> resetDatabase() async {
    final path = join(await getDatabasesPath(), _databaseName);
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    await deleteDatabase(path);
    debugPrint("Database completely reset.");
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<void> replaceTables(Map<String, dynamic> tableData) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final tableName in tableData.keys) {
        final records = tableData[tableName] as List<dynamic>?;
        if (records == null) continue;

        await txn.delete(tableName);

        for (final record in records) {
          try {
            await txn.insert(tableName, record as Map<String, dynamic>);
          } catch(e) {
            debugPrint("Failed to insert record into $tableName. Record: $record, Error: $e");
          }
        }
        debugPrint('Replaced ${records.length} records in "$tableName" table.');
      }
    });
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pending_operation');
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

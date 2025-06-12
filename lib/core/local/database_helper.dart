// core/local/database_helper.dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const _databaseName = "Diapallet.db";
  static const _databaseVersion = 2;

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
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Upgrading database from version $oldVersion to $newVersion...");
    // Simple upgrade strategy: drop all tables and recreate them.
    // This is suitable for development but would cause data loss in production
    // without a proper migration strategy.
    await _dropAllTables(db);
    await _onCreate(db, newVersion);
    debugPrint("Database upgrade complete.");
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint("Creating database version $version...");

    await db.execute('''
      CREATE TABLE location (
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
      CREATE TABLE employee (
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
      CREATE TABLE product (
        id INTEGER PRIMARY KEY,
        code TEXT UNIQUE,
        name TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_order (
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

    await db.execute('''
      CREATE TABLE purchase_order_item (
        id INTEGER PRIMARY KEY,
        siparis_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL,
        miktar REAL,
        birim TEXT,
        FOREIGN KEY (siparis_id) REFERENCES purchase_order (id) ON DELETE CASCADE,
        FOREIGN KEY (urun_id) REFERENCES product (id) ON DELETE RESTRICT
      )
    ''');

    // For local operations before sync, we need a local ID.
    // server_id is populated after a successful sync.
    await db.execute('''
      CREATE TABLE goods_receipt (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT UNIQUE, 
        server_id INTEGER,
        siparis_id INTEGER,
        invoice_number TEXT,
        employee_id INTEGER,
        receipt_date TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE goods_receipt_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_local_id TEXT NOT NULL,
        server_id INTEGER,
        urun_id INTEGER NOT NULL,
        quantity_received REAL NOT NULL,
        pallet_barcode TEXT,
        FOREIGN KEY (urun_id) REFERENCES product (id) ON DELETE RESTRICT
      )
    ''');
    
    // The core of inventory management. Tracks every item in every location.
    await db.execute('''
      CREATE TABLE inventory_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        urun_id INTEGER NOT NULL,
        location_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        pallet_barcode TEXT,
        updated_at TEXT NOT NULL,
        UNIQUE (urun_id, location_id, pallet_barcode),
        FOREIGN KEY (urun_id) REFERENCES product (id) ON DELETE CASCADE,
        FOREIGN KEY (location_id) REFERENCES location (id) ON DELETE CASCADE
      )
    ''');

    // Log of all transfers for history and syncing.
    await db.execute('''
      CREATE TABLE inventory_transfer (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT UNIQUE,
        server_id INTEGER,
        urun_id INTEGER NOT NULL,
        from_location_id INTEGER NOT NULL,
        to_location_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        pallet_barcode TEXT,
        employee_id INTEGER,
        transfer_date TEXT,
        created_at TEXT,
        FOREIGN KEY (urun_id) REFERENCES product (id),
        FOREIGN KEY (from_location_id) REFERENCES location (id),
        FOREIGN KEY (to_location_id) REFERENCES location (id)
      )
    ''');

    // Queue for operations performed offline that need to be sent to the server.
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

  // ==== HOUSEKEEPING ========================================================
  
  Future<void> _dropAllTables(Database db) async {
    final tables = [
      'pending_operation',
      'inventory_transfer',
      'inventory_stock',
      'goods_receipt_item',
      'goods_receipt',
      'purchase_order_item',
      'purchase_order',
      'product',
      'employee',
      'location',
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
    final db = await _database;
    if (db != null) {
      await db.close();
      _database = null;
      debugPrint("Database closed.");
    }
  }
}

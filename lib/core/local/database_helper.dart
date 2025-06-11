// core/local/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _dbName = 'app_main_database.db';
  static const int _dbVersion = 13;

  // ==== PUBLIC HANDLE =======================================================
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  // ==== INIT ================================================================
  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _dbName);
    debugPrint('DB path  : $path');

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate : _onCreate,
      onUpgrade: (db, _, __) async {
        await _dropAllTables(db);
        await _onCreate(db, _dbVersion);
      },
    );
  }

  // ==== SCHEMA ==============================================================

  Future<void> _onCreate(Database db, int _) async {

    // 1- Products
    await db.execute('''
      CREATE TABLE product (
        id   INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL
      )
    ''');

    // 2- Master location list (optional but handy for dropdowns)
    await db.execute('''
      CREATE TABLE location (
        id   INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT
      )
    ''');

    // 3- Inventory stock (unified for palletized and non-palletized items)
    await db.execute('''
      CREATE TABLE inventory_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        urun_id INTEGER NOT NULL REFERENCES product(id),
        location_id INTEGER NOT NULL REFERENCES location(id),
        quantity   INTEGER NOT NULL,
        pallet_barcode TEXT                          -- Can be null
      )
    ''');
    
    // Create an index for faster lookups
    await db.execute('CREATE INDEX idx_stock_location ON inventory_stock (location_id)');
    await db.execute('CREATE INDEX idx_stock_pallet ON inventory_stock (pallet_barcode)');

    // 4- Pallet header & details
    await db.execute('''
      CREATE TABLE pallet (
        id       TEXT PRIMARY KEY,
        location_id INTEGER NOT NULL REFERENCES location(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE pallet_item (
        pallet_id  TEXT NOT NULL REFERENCES pallet(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES product(id),
        quantity   INTEGER NOT NULL,
        PRIMARY KEY (pallet_id, product_id)
      )
    ''');

    // 5- Goods receipt header & lines
    await db.execute('''
      CREATE TABLE goods_receipt (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        external_id   TEXT NOT NULL UNIQUE,
        invoice_number TEXT NOT NULL,
        receipt_date   TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE goods_receipt_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL REFERENCES goods_receipt(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES product(id),
        quantity   INTEGER NOT NULL,
        location_id INTEGER NOT NULL REFERENCES location(id),
        pallet_id  TEXT REFERENCES pallet(id)      -- NULL for box flow
      )
    ''');

    // 6- Transfer header & lines
    await db.execute('''
      CREATE TABLE transfer_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,            -- 'pallet' | 'box'
        source_location_id INTEGER NOT NULL REFERENCES location(id),
        target_location_id INTEGER NOT NULL REFERENCES location(id),
        pallet_id TEXT,                          -- null for box flow
        transfer_date TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 7- Unified pending queue – each row is a standalone operation waiting
    //    to be synced. We keep JSON payload so that adding new operation types
    //    does not require schema changes.
    await db.execute('''
      CREATE TABLE pending_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,                  -- raw JSON encoded string
        created_at TEXT NOT NULL,
        attempts   INTEGER NOT NULL DEFAULT 0   -- retry counter
      )
    ''');

    await db.execute('''
      CREATE TABLE transfer_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id INTEGER NOT NULL REFERENCES transfer_operation(id) ON DELETE CASCADE,
        product_id   INTEGER NOT NULL REFERENCES product(id),
        quantity     INTEGER NOT NULL
      )
    ''');

    debugPrint('All tables created (v$_dbVersion).');
  }

  // ==== HOUSEKEEPING ========================================================

  Future<void> _dropAllTables(Database db) async {
    for (final t in [
      'pallet_item','pallet',
      'goods_receipt_item','goods_receipt',
      'transfer_item','transfer_operation',
      'inventory_stock',
      'location',
      'product',
      'pending_operation',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
  }

  Future<void> resetDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    await deleteDatabase(path);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

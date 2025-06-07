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
  static const int _dbVersion = 9;               // <-- yeni sürüm

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
        id   TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL
      )
    ''');

    // 2- Master location list (optional but handy for dropdowns)
    await db.execute('''
      CREATE TABLE location (
        name TEXT PRIMARY KEY
      )
    ''');

    // 3- Stock by location (box flow OR pallet unpacked)
    await db.execute('''
      CREATE TABLE stock_location (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id TEXT NOT NULL REFERENCES product(id),
        location   TEXT NOT NULL,
        quantity   INTEGER NOT NULL
      )
    ''');

    // 4- Pallet header & details
    await db.execute('''
      CREATE TABLE pallet (
        id       TEXT PRIMARY KEY,
        location TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pallet_item (
        pallet_id  TEXT NOT NULL REFERENCES pallet(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES product(id),
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
        product_id TEXT NOT NULL REFERENCES product(id),
        quantity   INTEGER NOT NULL,
        location   TEXT NOT NULL,
        pallet_id  TEXT REFERENCES pallet(id)      -- NULL for box flow
      )
    ''');

    // 6- Transfer header & lines
    await db.execute('''
      CREATE TABLE transfer_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,            -- 'pallet' | 'box'
        source_location TEXT NOT NULL,
        target_location TEXT NOT NULL,
        pallet_id TEXT,                          -- null for box flow
        transfer_date TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE transfer_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id INTEGER NOT NULL REFERENCES transfer_operation(id) ON DELETE CASCADE,
        product_id   TEXT NOT NULL REFERENCES product(id),
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
      'stock_location',
      'location',
      'product',
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

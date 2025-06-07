import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _dbName = 'app_main_database.db';
  static const int _dbVersion = 8;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    debugPrint("Database path: $path");
    return await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _dropAllTables(db);
        await _onCreate(db, newVersion);
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_location (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id TEXT NOT NULL REFERENCES product(id),
        location TEXT NOT NULL,
        quantity INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS goods_receipt (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        external_id TEXT NOT NULL UNIQUE,
        invoice_number TEXT NOT NULL,
        receipt_date TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS goods_receipt_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        product_id TEXT NOT NULL REFERENCES product(id),
        quantity INTEGER NOT NULL,
        location TEXT NOT NULL,
        container_id TEXT,
        FOREIGN KEY (receipt_id) REFERENCES goods_receipt (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transfer_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        source_location TEXT NOT NULL,
        target_location TEXT NOT NULL,
        container_id TEXT,
        transfer_date TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transfer_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id INTEGER NOT NULL,
        product_id TEXT NOT NULL REFERENCES product(id),
        quantity INTEGER NOT NULL,
        FOREIGN KEY (operation_id) REFERENCES transfer_operation (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS container (
        id TEXT PRIMARY KEY,
        location TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS container_item (
        container_id TEXT NOT NULL REFERENCES container(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES product(id),
        quantity INTEGER NOT NULL,
        PRIMARY KEY (container_id, product_id)
      )
    ''');

    // (Optional) Lokasyon tablosu:
    await db.execute('''
      CREATE TABLE IF NOT EXISTS location (
        name TEXT PRIMARY KEY
      )
    ''');

    debugPrint("All tables created.");
  }

  Future<void> _dropAllTables(Database db) async {
    for (final table in [
      'goods_receipt_item',
      'goods_receipt',
      'transfer_item',
      'transfer_operation',
      'stock_location',
      'container_item',
      'container',
      'location',
      'product',
    ]) {
      try {
        await db.execute('DROP TABLE IF EXISTS $table');
      } catch (_) {}
    }
    debugPrint('All tables dropped for full reset.');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }

  Future<void> resetDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      await deleteDatabase(path);
    } catch (e) {
      final db = await _initDB();
      await _dropAllTables(db);
      await db.close();
    }
    _database = null;
  }
}

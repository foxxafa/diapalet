// core/local/database_helper.dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/sync/pending_operation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'diapalet.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tablo oluşturma sorguları
    await db.execute('''
      CREATE TABLE goods_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_order_id INTEGER,
        receipt_number TEXT,
        receipt_date TEXT,
        notes TEXT,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE goods_receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        goods_receipt_id INTEGER,
        product_id INTEGER,
        quantity REAL,
        notes TEXT,
        FOREIGN KEY (goods_receipt_id) REFERENCES goods_receipts (id) ON DELETE CASCADE
      )
    ''');
    
    // Diğer tablolar
    await _createOtherTables(db);
  }

  Future<void> _createOtherTables(Database db) async {
    await db.execute('''
      CREATE TABLE purchase_orders (
        id INTEGER PRIMARY KEY,
        order_number TEXT NOT NULL,
        supplier_name TEXT,
        order_date TEXT,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_order_items (
        id INTEGER PRIMARY KEY,
        purchase_order_id INTEGER,
        product_id INTEGER,
        quantity REAL,
        notes TEXT,
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id)
      )
    ''');
    
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        name TEXT,
        stock_code TEXT,
        barcode TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Veritabanı yükseltme mantığı buraya gelecek
  }

  Future<void> resetDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'diapalet.db');
    await deleteDatabase(path);
    _database = null; // Referansı temizle
    await database; // Veritabanını yeniden oluştur
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

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      debugPrint("Database closed.");
    }
  }

  /// Replaces all data in the specified tables with new data from the server.
  /// This is a destructive operation used for full syncs.
  Future<void> replaceTables(Map<String, dynamic> tableData) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final tableName in tableData.keys) {
        // Clear the table first
        await txn.delete(tableName);

        // Insert new data
        final records = tableData[tableName] as List<dynamic>;
        for (final record in records) {
          await txn.insert(tableName, record as Map<String, dynamic>);
        }
        debugPrint('Replaced ${records.length} records in "$tableName" table.');
      }
    });
  }

  // --- Pending Operations ---

  /// Fetches all pending operations from the local database.
  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pending_operation');
    return List.generate(maps.length, (i) {
      return PendingOperation.fromMap(maps[i]);
    });
  }

  /// Deletes a pending operation by its local ID.
  Future<void> deletePendingOperation(int id) async {
    final db = await database;
    await db.delete(
      'pending_operation',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Updates the status of a pending operation, typically to 'failed' or 'pending'.
  Future<void> updatePendingOperationStatus(int id, String status, {String? error}) async {
    final db = await database;
    await db.update(
      'pending_operation',
      {'status': status, 'error_message': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

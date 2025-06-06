// core/local/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _dbName = 'app_main_database.db'; // Veritabanı adı
  static const int _dbVersion = 4; // Versiyon 4: product_id added to transfer_item

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
        debugPrint('Foreign keys enabled.');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createGoodsReceiptTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE goods_receipt (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        external_id TEXT NOT NULL UNIQUE,
        invoice_number TEXT NOT NULL,
        receipt_date TEXT NOT NULL, -- ISO8601 format
        mode TEXT NOT NULL, -- 'palet' or 'kutu'
        synced INTEGER NOT NULL DEFAULT 0 -- 0 for false, 1 for true
      )
    ''');
    debugPrint("Table 'goods_receipt' created.");

    await db.execute('''
      CREATE TABLE goods_receipt_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL, -- FK to goods_receipt
        pallet_or_box_id TEXT NOT NULL,
        product_id TEXT NOT NULL, 
        product_name TEXT NOT NULL,
        product_code TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (receipt_id) REFERENCES goods_receipt (id) ON DELETE CASCADE
      )
    ''');
    debugPrint("Table 'goods_receipt_item' created.");
  }

  Future<void> _createTransferTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE transfer_operation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL, 
        source_location TEXT,
        container_id TEXT NOT NULL,
        target_location TEXT,
        transfer_date TEXT NOT NULL, 
        synced INTEGER NOT NULL DEFAULT 0 
      )
    ''');
    debugPrint("Table 'transfer_operation' created.");

    await db.execute('''
      CREATE TABLE transfer_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id INTEGER NOT NULL,
        product_id TEXT NOT NULL, -- YENİ EKLENDİ
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (operation_id) REFERENCES transfer_operation (id) ON DELETE CASCADE
      )
    ''');
    debugPrint("Table 'transfer_item' created with product_id.");

    await db.execute('''
      CREATE TABLE container_location (
        container_id TEXT PRIMARY KEY,
        location TEXT NOT NULL,
        last_updated TEXT NOT NULL 
      )
    ''');
    debugPrint("Table 'container_location' created.");
  }


  Future<void> _onCreate(Database db, int version) async {
    debugPrint("Creating database tables for version $version...");
    await _createGoodsReceiptTables(db);
    await _createTransferTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Upgrading database from version $oldVersion to $newVersion...");
    if (oldVersion < 2) {
      // Bu blok genellikle eski, artık desteklenmeyen versiyonlar için kalır.
      // V1'den V2'ye geçişte spesifik bir işlem yoksa, log yeterlidir.
      debugPrint("DB Upgrade: (No specific schema changes for v1 to v2 in this example, assuming onCreate handles all tables if DB is new at v2)");
    }
    if (oldVersion < 3) {
      // V2'den V3'e geçiş
      try {
        await db.execute("ALTER TABLE goods_receipt ADD COLUMN external_id TEXT");
        debugPrint("DB Upgrade: Added external_id column to goods_receipt table (for V3)");
      } catch (e) {
        debugPrint("DB Upgrade: Could not add external_id to goods_receipt (maybe already exists or other error): $e");
        // external_id UNIQUE olmalı, bu yüzden default değer atamak yerine null bırakılabilir veya NOT NULL UNIQUE yapılabilir.
        // Eğer NOT NULL UNIQUE yapılıyorsa ve varolan satırlar varsa, onlara benzersiz değerler atanmalıdır.
        // Şimdilik TEXT olarak bırakıldı, UNIQUE constraint onCreate'de var.
      }
    }
    if (oldVersion < 4) {
      // V3'ten V4'e geçiş
      try {
        await db.execute("ALTER TABLE transfer_item ADD COLUMN product_id TEXT");
        debugPrint("DB Upgrade: Added product_id column to transfer_item table (for V4)");
        // Varolan satırlar için product_id'nin nasıl doldurulacağı burada ele alınabilir,
        // ancak genellikle bu tür sütunlar başlangıçta NULL olabilir veya bir default değeri olabilir.
        // Entity'miz NOT NULL gerektirdiği için, aslında bu sütun eklendikten sonra
        // varolan transfer_item kayıtları için product_id doldurulmalı ya da NOT NULL constraint'i daha sonra eklenmeli.
        // Şimdilik TEXT olarak ekliyoruz. Entity'deki fromMap null kontrolü yapıyor.
      } catch (e) {
        debugPrint("DB Upgrade: Could not add product_id to transfer_item (maybe already exists or other error): $e");
      }
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
    debugPrint("Database closed.");
  }

  /// Deletes the database file if possible. If deletion fails, all
  /// tables are cleared as a fallback. The next access to [database]
  /// will recreate it lazily.
  Future<void> resetDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      await deleteDatabase(path);
      debugPrint('Database file deleted at $path');
    } catch (e) {
      debugPrint('Could not delete database file: $e. Clearing tables instead.');
      final db = await _initDB();
      await _clearAllTables(db);
      await db.close();
    }

    _database = null;
  }

  Future<void> _clearAllTables(Database db) async {
    await db.delete('goods_receipt_item');
    await db.delete('goods_receipt');
    await db.delete('transfer_item');
    await db.delete('transfer_operation');
    await db.delete('container_location');
    debugPrint('All tables cleared.');
  }
}

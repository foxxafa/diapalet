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
  static const int _dbVersion = 3; // Versiyon 3: external_id added

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
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // Yeni versiyon için onUpgrade eklendi
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
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (operation_id) REFERENCES transfer_operation (id) ON DELETE CASCADE
      )
    ''');
    debugPrint("Table 'transfer_item' created.");

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
    // Gelecekte eklenecek diğer tablolar için _create... metodları çağrılabilir.
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Upgrading database from version $oldVersion to $newVersion...");
    if (oldVersion < 2) {
      // Versiyon 1'den 2'ye geçerken, eğer goods_receipt tabloları yoksa oluştur.
      // Bu, _onCreate'in zaten var olan tabloları tekrar oluşturmaya çalışmasını engeller.
      // Ancak, openDatabase versiyonu artırıldığında ve tablolar yoksa onCreate zaten çağrılır.
      // Bu yüzden burası daha çok var olan tabloları ALTER etmek için kullanılır.
      // Eğer tablolar kesinlikle yoksa ve onCreate'de oluşturulacaksa, burası boş kalabilir
      // veya sadece ALTER işlemleri için kullanılabilir.
      // Bu senaryoda, onCreate'in tüm tabloları oluşturduğunu varsayıyoruz.
      // Eğer versiyon 1'de sadece transfer tabloları varsa, goods_receipt'leri burada ekleyebiliriz:
      // await _createGoodsReceiptTables(db);
      debugPrint("DB Upgrade: (No specific schema changes for v1 to v2 in this example, assuming onCreate handles all tables if DB is new at v2)");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE goods_receipt ADD COLUMN external_id TEXT");
      debugPrint("DB Upgrade: Added external_id column to goods_receipt table");
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
    debugPrint("Database closed.");
  }
}

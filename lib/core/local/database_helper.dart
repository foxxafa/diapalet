// lib/core/local/database_helper.dart
import 'dart:io';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:diapalet/core/services/telegram_logger_service.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert'; // Added for jsonDecode
import 'package:shared_preferences/shared_preferences.dart'; // Added for SharedPreferences
import 'package:uuid/uuid.dart';

class DatabaseHelper {
  static const _databaseName = "Diapallet_v2.db";
  static const _databaseVersion = 1; // Version 1: Clean UUID-only architecture
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  DatabaseHelper._privateConstructor();

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

  /// Veritabanı dosya yolunu döndürür (backup için)
  Future<String> getDatabasePath() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, _databaseName);
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Veritabanı güncelleniyor: $oldVersion → $newVersion");

    // UUID-only mimariye geçiş için tüm tabloları yeniden oluştur
    await _dropAllTables(db);
    await _createAllTables(db);

    debugPrint("✅ Veritabanı yeniden oluşturuldu (UUID-only architecture)");
  }

  Future<void> _createAllTables(Database db) async {
    debugPrint("Veritabanı tabloları (Sürüm $_databaseVersion) oluşturuluyor...");

    await db.transaction((txn) async {
      final batch = txn.batch();

            batch.execute('''
        CREATE TABLE IF NOT EXISTS pending_operation (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          unique_id TEXT NOT NULL UNIQUE,
          type TEXT NOT NULL,
          data TEXT NOT NULL,
          created_at TEXT NOT NULL,
          status TEXT NOT NULL,
          error_message TEXT,
          synced_at TEXT
        )
      ''');

      batch.execute(SyncLog.createTableQuery);

      // Log entries table for storing app logs
      batch.execute('''
        CREATE TABLE IF NOT EXISTS log_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          level TEXT NOT NULL,
          title TEXT NOT NULL,
          message TEXT NOT NULL,
          stack_trace TEXT,
          context TEXT,
          device_info TEXT,
          employee_id INTEGER,
          employee_name TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS shelfs (
          id INTEGER PRIMARY KEY,
          warehouse_id INTEGER,
          name TEXT,
          code TEXT,
          is_active INTEGER DEFAULT 1,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS employees (
          id INTEGER PRIMARY KEY,
          first_name TEXT,
          last_name TEXT,
          username TEXT UNIQUE,
          password TEXT,
          warehouse_code TEXT,
          role TEXT,
          is_active INTEGER DEFAULT 1,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      // _key artık PRIMARY KEY olarak kullanılıyor
      batch.execute('''
        CREATE TABLE IF NOT EXISTS urunler (
          _key TEXT PRIMARY KEY,
          UrunId INTEGER UNIQUE,
          StokKodu TEXT UNIQUE,
          UrunAdi TEXT,
          aktif INTEGER,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS birimler (
          id INTEGER PRIMARY KEY,
          birimadi TEXT,
          birimkod TEXT,
          _key TEXT,
          _key_scf_stokkart TEXT,
          StokKodu TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS barkodlar (
          id INTEGER PRIMARY KEY,
          _key TEXT UNIQUE,
          _key_scf_stokkart_birimleri TEXT,
          barkod TEXT,
          turu TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS tedarikci (
          id INTEGER PRIMARY KEY,
          tedarikci_kodu TEXT,
          tedarikci_adi TEXT,
          created_at TEXT,
          updated_at TEXT,
          _key TEXT,
          Aktif INTEGER DEFAULT 1
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS siparisler (
          id INTEGER PRIMARY KEY,
          tarih TEXT,
          created_at TEXT,
          updated_at TEXT,
          status INTEGER DEFAULT 0,
          fisno TEXT,
          __carikodu TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS siparis_ayrintili (
          id INTEGER PRIMARY KEY,
          siparisler_id INTEGER,
          urun_key TEXT,
          _key_kalemturu TEXT,
          kartkodu TEXT,
          miktar REAL,
          sipbirimi TEXT,
          sipbirimkey TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(urun_key) REFERENCES urunler(_key)
        )
      ''');


      batch.execute('''
        CREATE TABLE IF NOT EXISTS goods_receipts (
          operation_unique_id TEXT PRIMARY KEY NOT NULL,
          siparis_id INTEGER,
          invoice_number TEXT,
          delivery_note_number TEXT,
          employee_id INTEGER,
          receipt_date TEXT,
          sip_fisno TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS goods_receipt_items (
          item_uuid TEXT PRIMARY KEY NOT NULL,
          operation_unique_id TEXT NOT NULL,
          urun_key TEXT,
          birim_key TEXT,
          siparis_key TEXT,
          quantity_received REAL,
          pallet_barcode TEXT,
          barcode TEXT,
          expiry_date TEXT,
          StokKodu TEXT,
          free INTEGER DEFAULT 0,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(operation_unique_id) REFERENCES goods_receipts(operation_unique_id),
          FOREIGN KEY(urun_key) REFERENCES urunler(_key)
        )
      ''');

      // Inventory stock table with receiving/available status support
      // KRITIK DEĞIŞIKLIK: siparis_id ve goods_receipt_id kaldırıldı
      // receipt_operation_uuid eklendi (goods_receipts.operation_unique_id ile ilişki)
      batch.execute('''
        CREATE TABLE IF NOT EXISTS inventory_stock (
          stock_uuid TEXT PRIMARY KEY NOT NULL,
          urun_key TEXT NOT NULL,
          birim_key TEXT,
          location_id INTEGER,
          receipt_operation_uuid TEXT,
          quantity REAL NOT NULL,
          pallet_barcode TEXT,
          expiry_date TEXT,
          stock_status TEXT NOT NULL CHECK(stock_status IN ('receiving', 'available')),
          StokKodu TEXT,
          shelf_code TEXT,
          sip_fisno TEXT,
          created_at TEXT,
          updated_at TEXT,
          UNIQUE(urun_key, birim_key, location_id, pallet_barcode, stock_status, expiry_date),
          FOREIGN KEY(urun_key) REFERENCES urunler(_key),
          FOREIGN KEY(location_id) REFERENCES shelfs(id)
        )
      ''');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_location ON inventory_stock(location_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_status ON inventory_stock(stock_status)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_receipt_uuid ON inventory_stock(receipt_operation_uuid)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_uuid ON inventory_stock(stock_uuid)');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_shelfs_warehouse ON shelfs(warehouse_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_shelfs_code ON shelfs(code)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_order_lines_siparis ON siparis_ayrintili(siparisler_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_order_lines_urun ON siparis_ayrintili(urun_key)');
      
      // KRITIK DEĞIŞIKLIK: siparis_id ve goods_receipt_id kaldırıldı
      // receipt_operation_uuid eklendi (transfer hangi mal kabule ait, putaway için)
      // PRIMARY KEY: Composite key (operation_unique_id + urun_key + birim_key)
      // çünkü bir transfer birden fazla ürün içerebilir
      batch.execute('''
        CREATE TABLE IF NOT EXISTS inventory_transfers (
          operation_unique_id TEXT NOT NULL,
          urun_key TEXT NOT NULL,
          birim_key TEXT NOT NULL,
          from_location_id INTEGER,
          to_location_id INTEGER,
          quantity REAL,
          from_pallet_barcode TEXT,
          pallet_barcode TEXT,
          receipt_operation_uuid TEXT,
          delivery_note_number TEXT,
          employee_id INTEGER,
          transfer_date TEXT,
          StokKodu TEXT,
          from_shelf TEXT,
          to_shelf TEXT,
          sip_fisno TEXT,
          created_at TEXT,
          updated_at TEXT,
          PRIMARY KEY (operation_unique_id, urun_key, birim_key),
          FOREIGN KEY(urun_key) REFERENCES urunler(_key),
          FOREIGN KEY(from_location_id) REFERENCES shelfs(id),
          FOREIGN KEY(to_location_id) REFERENCES shelfs(id),
          FOREIGN KEY(employee_id) REFERENCES employees(id)
        )
      ''');


      // Performance indexes - created after all tables
      batch.execute('CREATE INDEX IF NOT EXISTS idx_goods_receipts_date ON goods_receipts(receipt_date)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_pending_operation_status ON pending_operation(status)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_transfers_date ON inventory_transfers(transfer_date)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_transfers_op_uid ON inventory_transfers(operation_unique_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_goods_receipts_siparis ON goods_receipts(siparis_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_goods_receipts_op_uid ON goods_receipts(operation_unique_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_employees_warehouse ON employees(warehouse_code)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_urunler_stokkodu ON urunler(StokKodu)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_urunler_aktif ON urunler(aktif)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_birimler_key ON birimler(_key)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_birimler_stokkodu ON birimler(StokKodu)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_barkodlar_barkod ON barkodlar(barkod)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_barkodlar_key_birimler ON barkodlar(_key_scf_stokkart_birimleri)');

      // 🚀 PRODUCT SEARCH PERFORMANCE INDEXES - Added for warehouse count search optimization
      // These indexes dramatically speed up multi-keyword product searches (e.g., "yog 500")
      batch.execute('CREATE INDEX IF NOT EXISTS idx_urunler_urunadi ON urunler(UrunAdi)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_birimler_scf_stokkart ON birimler(_key_scf_stokkart)');

      // Composite index for common search patterns (aktif + UrunAdi)
      batch.execute('CREATE INDEX IF NOT EXISTS idx_urunler_aktif_urunadi ON urunler(aktif, UrunAdi)');

      // Warehouse Count Tables (Upload-only, no sync back)
      batch.execute('''
        CREATE TABLE IF NOT EXISTS count_sheets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_unique_id TEXT NOT NULL UNIQUE,
          sheet_number TEXT NOT NULL UNIQUE,
          employee_id INTEGER NOT NULL,
          warehouse_code TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'in_progress',
          notes TEXT,
          start_date TEXT NOT NULL,
          complete_date TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(employee_id) REFERENCES employees(id)
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS count_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_unique_id TEXT NOT NULL,
          item_uuid TEXT NOT NULL UNIQUE,
          birim_key TEXT,
          pallet_barcode TEXT,
          quantity_counted REAL NOT NULL,
          barcode TEXT,
          StokKodu TEXT,
          shelf_code TEXT,
          expiry_date TEXT,
          is_damaged INTEGER DEFAULT 0,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      // Count tables indexes
      batch.execute('CREATE INDEX IF NOT EXISTS idx_count_sheets_status ON count_sheets(status)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_count_sheets_employee ON count_sheets(employee_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_count_sheets_operation_uid ON count_sheets(operation_unique_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_count_items_operation_uid ON count_items(operation_unique_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_count_items_uuid ON count_items(item_uuid)');

      // Unknown Barcodes Table (for collecting unrecognized barcodes from scanners)
      batch.execute('''
        CREATE TABLE IF NOT EXISTS unknown_barcodes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT NOT NULL,
          employee_id INTEGER,
          warehouse_code TEXT,
          scanned_at TEXT NOT NULL,
          synced INTEGER DEFAULT 0
        )
      ''');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_unknown_barcodes_synced ON unknown_barcodes(synced)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_unknown_barcodes_barcode ON unknown_barcodes(barcode)');

      await batch.commit(noResult: true);
    });

    debugPrint("Tüm tablolar başarıyla oluşturuldu.");
  }

  Future<void> _dropAllTables(Database db) async {
    // ÖNEMLI: Child tablolar önce silinmeli (foreign key dependency)
    const tables = [
      // Child tables first (have foreign keys)
      'count_items',           // → count_sheets, shelfs
      'goods_receipt_items',   // → goods_receipts
      'inventory_stock',       // → shelfs, goods_receipts
      'inventory_transfers',   // → shelfs
      'siparis_ayrintili',     // → siparisler
      'barkodlar',             // → urunler

      // Parent tables next
      'count_sheets',          // → employees
      'goods_receipts',        // → siparisler, employees
      'siparisler',            // → tedarikci

      // Independent tables
      'pending_operation',
      'sync_log',
      'shelfs',
      'employees',
      'urunler',
      'tedarikci',
      'birimler',
    ];

    // Foreign key kontrollerini transaction DIŞINDA kapat (bazı SQLite versiyonlarında gerekli)
    await db.execute('PRAGMA foreign_keys = OFF');

    await db.transaction((txn) async {
      for (final table in tables) {
        await txn.execute('DROP TABLE IF EXISTS $table');
      }
    });

    // Foreign key kontrollerini tekrar aç
    await db.execute('PRAGMA foreign_keys = ON');

    debugPrint("Yükseltme için tüm eski tablolar silindi.");
  }

  Future<void> applyDownloadedData(
    Map<String, dynamic> data, {
    void Function(String tableName, int processed, int total)? onTableProgress
  }) async {
    debugPrint("--- applyDownloadedData: Veri işlemeye başlanıyor ---");
    data.forEach((key, value) {
      if (value is List) {
        debugPrint("SYNC DATA: Alınan anahtar: '$key', Kayıt sayısı: ${value.length}");
      } else {
        debugPrint("SYNC DATA: Alınan anahtar: '$key', Tip: ${value.runtimeType}");
      }
    });
    debugPrint("----------------------------------------------------");

    final db = await database;

    // Foreign key constraint'leri geçici olarak devre dışı bırak (transaction dışında)
    await db.execute('PRAGMA foreign_keys = OFF');

    try {
      await db.transaction((txn) async {
        final batch = txn.batch();

        // Count total items for progress tracking
        int totalItems = 0;
        int processedItems = 0;
        String? currentTableName;

        data.forEach((key, value) {
          if (value is List) {
            totalItems += value.length;
          }
        });

        // Progress güncelleme helper fonksiyonu
        void updateProgress(String tableName) {
          // Progress'i sadece her 10 itemde bir veya tablo değişikliğinde güncelle
          if (processedItems % 10 == 0 || currentTableName != tableName || processedItems == totalItems) {
            currentTableName = tableName;
            if (totalItems > 0) {
              onTableProgress?.call(tableName, processedItems, totalItems);
            }
          }
        }

        // Incremental sync logic
        // Ürünler için özel işlem: aktif=0 olanları sil, diğerlerini güncelle
        if (data.containsKey('urunler')) {
          final urunlerData = List<Map<String, dynamic>>.from(data['urunler']);

          for (final urun in urunlerData) {
            // DAHA SAĞLAM YÖNTEM: Aktif/pasif kontrolünü kaldır.
            // Gelen tüm ürünleri doğrudan ekle/güncelle.
            // Aktif olmayan ürünler zaten "aktif=0" olarak gelecektir.
            final sanitizedRecord = _sanitizeRecord('urunler', urun);
            batch.insert(DbTables.products, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('urunler');
          }
        }

        // Shelfs incremental sync
        if (data.containsKey('shelfs')) {
          final shelfsData = List<Map<String, dynamic>>.from(data['shelfs']);

          for (final shelf in shelfsData) {
            final shelfId = shelf['id'];
            final isActive = shelf['is_active'];

            if (isActive == 0) {
              // Aktif olmayan rafı sil
              batch.delete(DbTables.locations, where: 'id = ?', whereArgs: [shelfId]);
            } else {
              // Aktif rafı güncelle/ekle
              final sanitizedShelf = _sanitizeRecord('shelfs', shelf);
              batch.insert(DbTables.locations, sanitizedShelf, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('shelfs');
          }
        }

        // Employees incremental sync
        if (data.containsKey('employees')) {
          final employeesData = List<Map<String, dynamic>>.from(data['employees']);

          for (final employee in employeesData) {
            final employeeId = employee['id'];
            final isActive = employee['is_active'];

            if (isActive == 0) {
              // Aktif olmayan çalışanı sil
              batch.delete(DbTables.employees, where: 'id = ?', whereArgs: [employeeId]);
            } else {
              // Aktif çalışanı güncelle/ekle
              final sanitizedEmployee = _sanitizeRecord('employees', employee);
              batch.insert(DbTables.employees, sanitizedEmployee, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('employees');
          }
        }

        // Suppliers incremental sync
        if (data.containsKey('tedarikci')) {
          final tedarikciData = List<Map<String, dynamic>>.from(data['tedarikci']);

          for (final tedarikci in tedarikciData) {
            final tedarikciId = tedarikci['id'];
            final aktif = tedarikci['Aktif'];

            if (aktif == 0) {
              // Aktif olmayan tedarikçiyi sil
              batch.delete('tedarikci', where: 'id = ?', whereArgs: [tedarikciId]);
            } else {
              // Aktif tedarikçiyi güncelle/ekle
              final sanitizedTedarikci = _sanitizeRecord('tedarikci', tedarikci);
              batch.insert('tedarikci', sanitizedTedarikci, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('tedarikci');
          }
        }

        // Goods receipts incremental sync - UUID bazlı smart merge
        if (data.containsKey('goods_receipts')) {
          final goodsReceiptsData = List<Map<String, dynamic>>.from(data['goods_receipts']);
          for (final receipt in goodsReceiptsData) {
            // KRITIK FIX: operation_unique_id bazlı kontrol - mobilde zaten varsa skip et
            final operationUniqueId = receipt['operation_unique_id'] as String?;
            bool shouldSkip = false;

            if (operationUniqueId != null) {
              final existingLocal = await txn.query(
                'goods_receipts',
                where: 'operation_unique_id = ?',
                whereArgs: [operationUniqueId],
                limit: 1
              );

              if (existingLocal.isNotEmpty) {
                // Bu operation_unique_id zaten mobilde var - UUID-based system, ID güncelleme gereksiz
                debugPrint('✅ goods_receipts: UUID already exists locally, skipping (UUID: $operationUniqueId)');
                shouldSkip = true;
              }
            }

            if (!shouldSkip) {
              final sanitizedRecord = _sanitizeRecord('goods_receipts', receipt);
              batch.insert('goods_receipts', sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('goods_receipts');
          }
        }

        // Goods receipt items incremental sync - UUID bazlı smart merge
        if (data.containsKey('goods_receipt_items')) {
          final goodsReceiptItemsData = List<Map<String, dynamic>>.from(data['goods_receipt_items']);
          for (final item in goodsReceiptItemsData) {
            // KRITIK FIX: item_uuid bazlı kontrol - mobilde zaten varsa skip et
            final itemUuid = item['item_uuid'] as String?;
            bool shouldSkip = false;

            if (itemUuid != null) {
              final existingLocal = await txn.query(
                'goods_receipt_items',
                where: 'item_uuid = ?',
                whereArgs: [itemUuid],
                limit: 1
              );

              if (existingLocal.isNotEmpty) {
                // Bu item_uuid zaten mobilde var - UUID-based system, ID güncelleme gereksiz
                debugPrint('✅ goods_receipt_items: UUID already exists locally, skipping (UUID: $itemUuid)');
                shouldSkip = true;
              }
            }

            if (!shouldSkip) {
              final sanitizedItem = _sanitizeRecord('goods_receipt_items', item);
              batch.insert('goods_receipt_items', sanitizedItem, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('goods_receipt_items');
          }
        }


        // Inventory stock incremental sync - Multi-device safe
        if (data.containsKey('inventory_stock')) {
          final inventoryStockData = List<Map<String, dynamic>>.from(data['inventory_stock']);
          for (final stock in inventoryStockData) {
            // KRITIK FIX: UUID bazlı kontrol - sadece kendi oluşturduğu kayıtları skip et
            bool isOwnStockRecord = false;
            final stockUuid = stock['stock_uuid'] as String?;
            
            if (stockUuid != null) {
              // Telefonun kendi oluşturduğu UUID'leri kontrol et
              // Eğer bu UUID telefonda varsa ve kendi ürettiği UUID pattern'ine uyuyorsa skip et
              final existingLocal = await txn.query(
                'inventory_stock',
                where: 'stock_uuid = ?',
                whereArgs: [stockUuid],
                limit: 1
              );
              
              if (existingLocal.isNotEmpty) {
                // Bu UUID zaten telefonda var
                final localRecord = existingLocal.first;
                final localQuantity = localRecord['quantity'] as double;
                final serverQuantity = (stock['quantity'] as num).toDouble();
                final localUpdatedAt = localRecord['updated_at'] as String?;
                final serverUpdatedAt = stock['updated_at'] as String?;
                
                // KRITIK FIX: updated_at bazlı karşılaştırma yap
                bool shouldUpdate = false;
                if (serverUpdatedAt != null && localUpdatedAt != null) {
                  try {
                    final serverDate = DateTime.parse(serverUpdatedAt);
                    final localDate = DateTime.parse(localUpdatedAt);
                    shouldUpdate = serverDate.isAfter(localDate);
                  } catch (e) {
                    // Tarih parse hatası varsa miktar karşılaştırması yap
                    shouldUpdate = serverQuantity != localQuantity;
                  }
                } else {
                  // updated_at bilgisi yoksa miktar karşılaştırması yap
                  shouldUpdate = serverQuantity != localQuantity;
                }
                
                if (shouldUpdate) {
                  debugPrint('🔄 Inventory stock güncellendi: UUID=$stockUuid, $localQuantity → $serverQuantity (updated_at: $localUpdatedAt → $serverUpdatedAt)');
                  await txn.update(
                    'inventory_stock',
                    {
                      'quantity': serverQuantity,
                      'updated_at': serverUpdatedAt,
                      'birim_key': stock['birim_key'], // birim_key'i de güncelle
                      'location_id': stock['location_id'], // location_id'yi de güncelle
                      'stock_status': stock['stock_status'], // stock_status'u da güncelle
                      'expiry_date': stock['expiry_date'], // expiry_date'i de güncelle
                      'receipt_operation_uuid': stock['receipt_operation_uuid'], // UUID-based relationship
                      'pallet_barcode': stock['pallet_barcode'], // KRITIK FIX: pallet_barcode'u da güncelle
                    },
                    where: 'stock_uuid = ?',
                    whereArgs: [stockUuid]
                  );
                } else {
                  debugPrint('🔄 Inventory stock güncel, skip: UUID=$stockUuid (quantity: $localQuantity, updated_at: $localUpdatedAt)');
                }
                continue;
              }
            }
            
            // YENI YAKLŞIM: receipt_operation_uuid ile kontrol et
            if (stock['receipt_operation_uuid'] != null) {
              final receiptOperationUuid = stock['receipt_operation_uuid'];
              final receipts = await txn.query(
                'goods_receipts',
                where: 'operation_unique_id = ?',
                whereArgs: [receiptOperationUuid],
                limit: 1
              );

              if (receipts.isNotEmpty) {
                isOwnStockRecord = await isOwnOperation(txn, 'goodsReceipt', receipts.first);
              }
            }

            if (isOwnStockRecord && stockUuid == null) {
              // Sadece UUID olmayan eski kayıtlar için receipt kontrolü yap
              debugPrint('🔄 Kendi inventory_stock tespit edildi (UUID yok), skip: ${stock['id']}');
              continue;
            }
            
            // Başka cihazın stock'u veya receipt'e bağlı olmayan stock - normal sync
            final sanitizedStock = _sanitizeRecord('inventory_stock', stock);
            
            // Inventory stock unique constraint kontrol (composite key)
            // Updated to include birim_key in unique constraint
            final existingStockQuery = StringBuffer();
            final queryArgs = <dynamic>[];
            
            existingStockQuery.write('urun_key = ? AND stock_status = ?');
            queryArgs.addAll([sanitizedStock['urun_key'], sanitizedStock['stock_status']]);
            
            // Handle birim_key
            if (sanitizedStock['birim_key'] == null) {
              existingStockQuery.write(' AND birim_key IS NULL');
            } else {
              existingStockQuery.write(' AND birim_key = ?');
              queryArgs.add(sanitizedStock['birim_key']);
            }
            
            // Handle location_id
            if (sanitizedStock['location_id'] == null) {
              existingStockQuery.write(' AND location_id IS NULL');
            } else {
              existingStockQuery.write(' AND location_id = ?');
              queryArgs.add(sanitizedStock['location_id']);
            }
            
            // Handle pallet_barcode
            if (sanitizedStock['pallet_barcode'] == null) {
              existingStockQuery.write(' AND pallet_barcode IS NULL');
            } else {
              existingStockQuery.write(' AND pallet_barcode = ?');
              queryArgs.add(sanitizedStock['pallet_barcode']);
            }
            
            // Handle expiry_date
            if (sanitizedStock['expiry_date'] == null) {
              existingStockQuery.write(' AND expiry_date IS NULL');
            } else {
              existingStockQuery.write(' AND expiry_date = ?');
              queryArgs.add(sanitizedStock['expiry_date']);
            }
            
            // NOT: receipt_operation_uuid artık unique constraint'e dahil DEĞİL
            // Bu sayede 'receiving' → 'available' konsolidasyonu sorunsuz çalışır
            
            final existingStock = await txn.query(
              'inventory_stock',
              where: existingStockQuery.toString(),
              whereArgs: queryArgs
            );
            
            if (existingStock.isNotEmpty) {
              // TOMBSTONE FIX: Mevcut kayıt bulundu, server'dan gelen UUID ile güncelle
              final existingId = existingStock.first['id'];
              final existingUuid = existingStock.first['stock_uuid'] as String?;
              final serverUuid = sanitizedStock['stock_uuid'] as String?;
              final newQuantity = (sanitizedStock['quantity'] as num).toDouble();
              
              if (newQuantity > 0.001) {
                // KRITIK FIX: UUID'yi de güncelle - tombstone sistemi için
                await txn.update(
                  'inventory_stock',
                  {
                    'stock_uuid': serverUuid, // Server UUID'si ile güncelle
                    'quantity': newQuantity,
                    'birim_key': sanitizedStock['birim_key'], // birim_key'i de güncelle
                    'updated_at': DateTime.now().toUtc().toIso8601String()
                  },
                  where: 'stock_uuid = ?',
                  whereArgs: [existingUuid]
                );
                debugPrint('🔄 TOMBSTONE FIX: UUID güncellendi $existingUuid → $serverUuid, quantity: $newQuantity');
              } else {
                // KRITIK FIX: Miktar 0 veya negatifse kaydı UUID ile sil
                await txn.delete('inventory_stock', where: 'stock_uuid = ?', whereArgs: [existingUuid]);
                debugPrint('SYNC INFO: Deleted inventory stock due to zero quantity (UUID: $existingUuid)');
              }
            } else {
              // Yeni stok kaydı oluştur
              batch.insert('inventory_stock', sanitizedStock, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('inventory_stock');
          }
        }

        // Inventory transfers incremental sync - Multi-device safe
        if (data.containsKey('inventory_transfers')) {
          final inventoryTransfersData = List<Map<String, dynamic>>.from(data['inventory_transfers']);
          for (final transfer in inventoryTransfersData) {
            // UUID-based duplicate check (device reset safe)
            final operationUniqueId = transfer['operation_unique_id'];

            // Skip if no UUID (should not happen with new backend)
            if (operationUniqueId == null) {
              debugPrint('⚠️ inventory_transfer UUID NULL, skipping: employee_id=${transfer['employee_id']}');
              continue;
            }

            // Check if this record already exists locally (Composite key check)
            // KRITIK: Bir transfer birden fazla ürün içerebilir, sadece operation_unique_id'ye bakmak yeterli değil
            final urunKey = transfer['urun_key'];
            final birimKey = transfer['birim_key'];

            final existingByComposite = await txn.query(
              'inventory_transfers',
              where: 'operation_unique_id = ? AND urun_key = ? AND birim_key = ?',
              whereArgs: [operationUniqueId, urunKey, birimKey],
              limit: 1
            );

            if (existingByComposite.isNotEmpty) {
              // Already in local DB - skip to avoid duplicate
              continue;
            }

            // New record (from any device/employee) - insert it
            final sanitizedTransfer = _sanitizeRecord('inventory_transfers', transfer);
            batch.insert('inventory_transfers', sanitizedTransfer, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('inventory_transfers');
          }
        }

        // Deleted records (tombstone) processing - UUID based - SADECE inventory_stock için
        if (data.containsKey('wms_tombstones')) {
          final tombstoneUuids = List<String>.from(data['wms_tombstones']);
          // debugPrint('🗑️ WMS Tombstone işleniyor: ${tombstoneUuids.length} inventory_stock kaydı silinecek');

          for (final stockUuid in tombstoneUuids) {

            // debugPrint('🗑️ Inventory stock siliniyor: stock_uuid=$stockUuid');

            // UUID ile inventory_stock silme işlemi
            final deletedCount = await txn.delete(
              'inventory_stock',
              where: 'stock_uuid = ?',
              whereArgs: [stockUuid]
            );

            // if (deletedCount > 0) {
            //   debugPrint('🗑️ Tombstone başarılı: inventory_stock.stock_uuid=$stockUuid silindi ($deletedCount kayıt)');
            // } else {
            //   debugPrint('🗑️ Tombstone: inventory_stock.stock_uuid=$stockUuid için silinecek kayıt bulunamadı (muhtemelen zaten silinmiş)');
            // }

            processedItems++;
            updateProgress('wms_tombstones');
          }
        }

        // Orders incremental sync
        if (data.containsKey('siparisler')) {
          final siparislerData = List<Map<String, dynamic>>.from(data['siparisler']);
          debugPrint('📦 SYNC DEBUG: siparisler - Received ${siparislerData.length} records from server');

          int validRecords = 0;
          int skippedRecords = 0;

          for (final siparis in siparislerData) {
            final sanitizedSiparis = _sanitizeRecord('siparisler', siparis);

            // Log any records missing the ID field
            if (sanitizedSiparis['id'] == null) {
              debugPrint('⚠️ SYNC WARNING: siparisler record missing ID - skipping: $siparis');
              skippedRecords++;
              continue;
            }

            batch.insert(DbTables.orders, sanitizedSiparis, conflictAlgorithm: ConflictAlgorithm.replace);
            validRecords++;

            processedItems++;
            updateProgress('siparisler');
          }

          debugPrint('✅ SYNC DEBUG: siparisler - Valid: $validRecords, Skipped: $skippedRecords');

          // DEBUG: Log hangi ID'leri ekliyoruz
          final allIds = siparislerData.map((s) => s['id']).where((id) => id != null).toList();
          debugPrint('📋 SYNC DEBUG: siparisler - ID list being inserted: ${allIds.take(10).join(', ')}${allIds.length > 10 ? '... (${allIds.length} total)' : ''}');
        }

        // Birimler incremental sync
        if (data.containsKey('birimler')) {
          final birimlerData = List<Map<String, dynamic>>.from(data['birimler']);
          for (final birim in birimlerData) {
            final sanitizedBirim = _sanitizeRecord('birimler', birim);
            batch.insert('birimler', sanitizedBirim, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('birimler');
          }
        }

        // Barkodlar incremental sync
        if (data.containsKey('barkodlar')) {
          final barkodlarData = List<Map<String, dynamic>>.from(data['barkodlar']);
          for (final barkod in barkodlarData) {
            final sanitizedBarkod = _sanitizeRecord('barkodlar', barkod);
            batch.insert('barkodlar', sanitizedBarkod, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('barkodlar');
          }
        }

        // inventory_stock sync zaten yukarıda (500-591 satırları) yapıldı
        // Bu duplicate sync kodunu kaldırdık - sonsuz döngü riskini önler

        // Diğer tablolar için eski mantık (full replacement)
        const deletionOrder = [
          // Tüm tablolar incremental olarak işlendiği için bu liste boş
        ];

        // Tablolari belirtilen sirada sil (incremental tablolar hariç)
        for (final table in deletionOrder) {
          if (data.containsKey(table)) {
            await txn.delete(table);
          }
        }

        // Sonra verileri ekle (incremental tablolar hariç, onlar zaten yukarıda işlendi)
        final incrementalTables = ['urunler', 'shelfs', 'employees', 'goods_receipts', 'goods_receipt_items', 'inventory_stock', 'inventory_transfers', 'siparisler', 'siparis_ayrintili', 'tedarikci', 'birimler', 'barkodlar'];
        final skippedTables = ['warehouses']; // Kaldırılan tablolar

        for (var table in data.keys) {
          if (incrementalTables.contains(table)) continue; // Zaten yukarıda işlendi
          if (skippedTables.contains(table)) continue; // Kaldırılan tablolar
          if (table == 'wms_tombstones') continue; // Tombstones zaten yukarıda işlendi
          if (data[table] is! List) continue;
          final records = List<Map<String, dynamic>>.from(data[table]);
          if (records.isEmpty) continue;

          for (final record in records) {
            final sanitizedRecord = _sanitizeRecord(table, record);
            batch.insert(table, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress(table);
          }
        }
        // End of first pass sync

        await batch.commit(noResult: true);

        // DEBUG: Batch commit'ten sonra gerçek veritabanı kayıt sayısını kontrol et
        if (data.containsKey('siparisler')) {
          final dbCount = await txn.rawQuery('SELECT COUNT(*) as count FROM siparisler');
          final actualCount = Sqflite.firstIntValue(dbCount) ?? 0;
          debugPrint('🔍 SYNC DEBUG: siparisler - Batch commit SONRASI veritabaninda: $actualCount kayit');
        }

        // --- SECOND PASS for siparis_ayrintili ---
        // This runs after all other data is committed in the same transaction,
        // allowing us to query for 'urunler' to find the 'urun_id'.
        if (data.containsKey('siparis_ayrintili')) {
          // For robust lookup, use an in-memory map created from the sync data.
          final productCodeToIdMap = <String, int>{};
          if (data.containsKey('urunler')) {
            final urunlerData = List<Map<String, dynamic>>.from(data['urunler']);
            for (final urun in urunlerData) {
              final urunId = urun['id'];
              final stokKodu = urun['StokKodu'];
              if (stokKodu != null && urunId != null) {
                productCodeToIdMap[stokKodu.toString()] = urunId as int;
              }
            }
            debugPrint("SYNC INFO: Using in-memory product map with ${productCodeToIdMap.length} entries for order line processing.");
          }

          final satirlarData = List<Map<String, dynamic>>.from(data['siparis_ayrintili']);
          final secondPassBatch = txn.batch();

          for (final satir in satirlarData) {
            if (satir['turu'] == '1' || satir['turu'] == 1) {
              final sanitizedSatir = _sanitizeRecord('siparis_ayrintili', satir);

              // urun_key is null, try to derive it from kartkodu
              if ((sanitizedSatir['urun_key'] == null || sanitizedSatir['urun_key'] == '') &&
                  sanitizedSatir.containsKey('kartkodu') &&
                  sanitizedSatir['kartkodu'] != null) {
                final kartkodu = sanitizedSatir['kartkodu'].toString();
                if (productCodeToIdMap.containsKey(kartkodu)) {
                  sanitizedSatir['urun_key'] = productCodeToIdMap[kartkodu].toString();
                } else {
                  debugPrint("SYNC WARNING: kartkodu '$kartkodu' not found in in-memory product map. Line ID: ${sanitizedSatir['id']}");
                }
              }

              secondPassBatch.insert(DbTables.orderLines, sanitizedSatir,
                  conflictAlgorithm: ConflictAlgorithm.replace);
              processedItems++;
              updateProgress('siparis_ayrintili');
            }
          }
          await secondPassBatch.commit(noResult: true);
        }
      });
    } finally {
      // Foreign key constraint'leri yeniden etkinleştir
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Map<String, dynamic> _sanitizeRecord(String table, Map<String, dynamic> record) {
    final newRecord = Map<String, dynamic>.from(record);

    // Only handle critical field mappings - let SQLite ignore unknown fields
    switch (table) {
      case 'urunler':
        // _key artık PRIMARY KEY, UrunId'yi de saklıyoruz backward compatibility için
        // Server'dan gelen 'id' alanını 'UrunId' olarak saklıyoruz
        if (newRecord.containsKey('id')) {
          newRecord['UrunId'] = newRecord['id'];
          newRecord.remove('id');
        }
        // _key yoksa UrunId'den oluştur (fallback)
        if (!newRecord.containsKey('_key') || newRecord['_key'] == null) {
          newRecord['_key'] = newRecord['UrunId']?.toString() ?? '';
        }
        break;

      case 'goods_receipts':
        // UUID-only, no ID mapping needed
        // Remove ID column from server data
        newRecord.remove('id');
        break;
        
      case 'siparisler':
        // Map server fields to local schema - only keep fields that exist in local table
        final localRecord = <String, dynamic>{};

        // Local table columns based on optimized CREATE TABLE statement
        final localColumns = [
          'id', 'tarih', 'created_at', 'updated_at',
          'status', 'fisno', '__carikodu'
        ];

        // Copy only existing local columns
        for (String column in localColumns) {
          if (newRecord.containsKey(column)) {
            localRecord[column] = newRecord[column];
          }
        }

        return localRecord;

      case 'siparis_ayrintili':
        // Only keep fields that exist in optimized local schema
        final localRecord = <String, dynamic>{};
        final localColumns = [
          'id', 'siparisler_id', 'urun_key', '_key_kalemturu', 'kartkodu', 'miktar',
          'sipbirimi', 'sipbirimkey', 'created_at', 'updated_at'
        ];
        
        // Sunucuda _key_kalemturu alanında ürünün _key'i var, bunu urun_key'e çevir
        if (newRecord.containsKey('_key_kalemturu') && newRecord['_key_kalemturu'] != null) {
          newRecord['urun_key'] = newRecord['_key_kalemturu'];
        }
        
        // Sadece local tabloda var olan sütunları kopyala
        for (String column in localColumns) {
          if (newRecord.containsKey(column)) {
            localRecord[column] = newRecord[column];
          }
        }
        
        return localRecord;

      case 'inventory_stock':
        // Sunucu artık urun_id alanında _key değerini gönderiyor, direkt urun_key olarak kaydet
        if (newRecord.containsKey('urun_id')) {
          newRecord['urun_key'] = newRecord['urun_id']?.toString();
          newRecord.remove('urun_id');
        }

        // YENİ: receipt_operation_uuid field handling
        if (newRecord.containsKey('receipt_operation_uuid') && newRecord['receipt_operation_uuid'] != null) {
          newRecord['receipt_operation_uuid'] = newRecord['receipt_operation_uuid'].toString();
        }

        // ESKİ ALANLAR: Geriye dönük uyumluluk için kaldır (artık kullanılmıyor)
        newRecord.remove('id');
        newRecord.remove('siparis_id');
        newRecord.remove('goods_receipt_id');

        // KRITIK FIX: birim_key alanını sunucudan gelen veriyle güncelle
        // Eğer sunucudan gelen kayıtta birim_key varsa, onu kullan
        if (newRecord.containsKey('birim_key') && newRecord['birim_key'] != null) {
          // birim_key değeri korunuyor - sunucudan gelen değer doğru
        } else {
          // Eğer birim_key yoksa, log at (bu durumda hata var)
          debugPrint('WARNING: inventory_stock kaydında birim_key eksik: $newRecord');
        }
        break;

      case 'goods_receipt_items':
        // Sunucu artık urun_id alanında _key değerini gönderiyor, direkt urun_key olarak kaydet
        if (newRecord.containsKey('urun_id')) {
          newRecord['urun_key'] = newRecord['urun_id']?.toString();
          newRecord.remove('urun_id');
        }

        // Remove ID columns - UUID-only architecture
        newRecord.remove('id');
        newRecord.remove('receipt_id');

        // Backend'den gelen operation_unique_id sütunu artık doğrudan kullanılıyor
        // Sütun adları tam eşleşiyor, mapping gerekmez

        // KRITIK FIX: birim_key field handling - ensure it's properly saved
        if (newRecord.containsKey('birim_key') && newRecord['birim_key'] != null) {
          newRecord['birim_key'] = newRecord['birim_key'].toString();
        }

        // KRITIK FIX: item_uuid field handling - multi-device sync için gerekli
        if (newRecord.containsKey('item_uuid') && newRecord['item_uuid'] != null) {
          newRecord['item_uuid'] = newRecord['item_uuid'].toString();
        }

        // free değerini integer olarak kaydet
        if (newRecord.containsKey('free')) {
          final freeValue = newRecord['free'];
          if (freeValue is String) {
            newRecord['free'] = int.tryParse(freeValue) ?? 0;
          } else if (freeValue is bool) {
            newRecord['free'] = freeValue ? 1 : 0;
          } else if (freeValue is num) {
            newRecord['free'] = freeValue.toInt();
          }
        }
        break;

      case 'inventory_transfers':
        // Sunucu artık urun_id alanında _key değerini gönderiyor, direkt urun_key olarak kaydet
        if (newRecord.containsKey('urun_id')) {
          newRecord['urun_key'] = newRecord['urun_id']?.toString();
          newRecord.remove('urun_id');
        }

        // YENİ: receipt_operation_uuid field handling (putaway için)
        if (newRecord.containsKey('receipt_operation_uuid') && newRecord['receipt_operation_uuid'] != null) {
          newRecord['receipt_operation_uuid'] = newRecord['receipt_operation_uuid'].toString();
        }

        // ESKİ ALANLAR: Geriye dönük uyumluluk için kaldır
        newRecord.remove('id');
        newRecord.remove('siparis_id');
        newRecord.remove('goods_receipt_id');

        // KRITIK FIX: birim_key'i de koru
        if (newRecord.containsKey('birim_key') && newRecord['birim_key'] != null) {
          newRecord['birim_key'] = newRecord['birim_key'].toString();
        }
        break;

      case 'birimler':
        // Only keep fields that exist in local schema
        final localRecord = <String, dynamic>{}; 
        final localColumns = [
          'id', 'birimadi', 'birimkod', '_key', '_key_scf_stokkart', 'StokKodu', 
          'created_at', 'updated_at'
        ];
        
        // Copy only existing local columns
        for (String column in localColumns) {
          if (newRecord.containsKey(column)) {
            localRecord[column] = newRecord[column];
          }
        }
        
        return localRecord;

      // siparis_ayrintili case already handled above with early return
    }

    // SQLite will automatically ignore unknown columns during INSERT
    // No need to manually remove every field that doesn't exist in local schema
    return newRecord;
  }

  // --- YARDIMCI FONKSİYONLAR ---

  /// Product search by barcode - Using new barkodlar table
  Future<List<Map<String, dynamic>>> getAllProductsByBarcode(String barcode, {int? orderId}) async {
    final db = await database;
    
    String sql;
    List<dynamic> params;

    if (orderId != null) {
      // Sipariş bazlı arama: Önce siparişteki birimle eşleşen satırı ara, yoksa sipariş dışı olarak işaretle
      // FIX: JOIN relationship - birimler._key_scf_stokkart = urunler._key kullan
      sql = '''
        SELECT
          u.UrunId,
          u.UrunAdi,
          u.StokKodu,
          u.aktif,
          u._key,
          b.birimadi,
          b.birimkod,
          b._key as birim_key,
          bark.barkod,
          bark._key as barkod_key,
          COALESCE(sa.miktar, 0.0) as miktar,
          COALESCE(sa.sipbirimi, b.birimkod) as sipbirimi,
          sa.sipbirimkey,
          sb.birimadi as sipbirimi_adi,
          sb.birimkod as sipbirimi_kod,
          sa.id as order_line_id,
          CASE WHEN sa.id IS NOT NULL THEN 'order' ELSE 'out_of_order' END as source_type
        FROM barkodlar bark
        JOIN birimler b ON bark._key_scf_stokkart_birimleri = b._key
        JOIN urunler u ON b._key_scf_stokkart = u._key
        LEFT JOIN siparis_ayrintili sa ON sa.kartkodu = u.StokKodu
          AND CAST(sa.sipbirimkey AS TEXT) = b._key
          AND sa.siparisler_id = ?
        LEFT JOIN birimler sb ON CAST(sa.sipbirimkey AS TEXT) = sb._key
        WHERE (bark.barkod = ? OR u.StokKodu = ?)
          AND u.aktif = 1
      ''';
      params = [orderId, barcode, barcode];
    } else {
      // Genel arama: Tüm aktif ürünler içinde barkod ara
      // FIX: u.* yerine explicit kolonlar seç (birim_key çakışmasını önlemek için)
      // FIX: JOIN relationship - birimler._key_scf_stokkart = urunler._key kullan
      sql = '''
        SELECT
          u.UrunId,
          u.UrunAdi,
          u.StokKodu,
          u.aktif,
          u._key,
          b.birimadi,
          b.birimkod,
          b._key as birim_key,
          bark.barkod,
          bark._key as barkod_key
        FROM barkodlar bark
        JOIN birimler b ON bark._key_scf_stokkart_birimleri = b._key
        JOIN urunler u ON b._key_scf_stokkart = u._key
        WHERE (bark.barkod = ? OR u.StokKodu = ?)
          AND u.aktif = 1
      ''';
      params = [barcode, barcode];
    }

    final result = await db.rawQuery(sql, params);

    // DEBUG: İlk sonucu logla
    if (result.isNotEmpty) {
      final first = result.first;
      debugPrint('📊 getAllProductsByBarcode result:');
      debugPrint('   barcode: $barcode, orderId: $orderId');
      debugPrint('   u._key (product): ${first['_key']}');
      debugPrint('   b._key (birim_key): ${first['birim_key']}');
      debugPrint('   StokKodu: ${first['StokKodu']}');
      debugPrint('   birimadi: ${first['birimadi']}');
    }

    return result;
  }

  /// Backward compatibility için - ilk sonucu döndürür
  Future<Map<String, dynamic>?> getProductByBarcode(String barcode, {int? orderId}) async {
    final results = await getAllProductsByBarcode(barcode, orderId: orderId);
    return results.isNotEmpty ? results.first : null;
  }

  /// Barkod ile ürün arama (LIKE) - Yeni barkodlar tablosunu kullanır - Optimized version
  /// Opsiyonel olarak sipariş ID'sine göre filtreleme yapar.
  Future<List<Map<String, dynamic>>> searchProductsByBarcode(String query, {int? orderId}) async {
    final db = await database;
    
    debugPrint("🔍 Searching for barcode: '$query'${orderId != null ? ' in order $orderId' : ''}");
    
    // Optimize: First try exact matches for better performance
    if (query.length >= 3) {
      final exactResults = await _searchExactProductsByBarcode(db, query, orderId);
      if (exactResults.isNotEmpty) {
        debugPrint("🔍 Found ${exactResults.length} exact matches");
        return exactResults;
      }
    }
    
    // Fall back to LIKE search for shorter queries or when no exact match found
    return await _searchProductsByBarcodeLike(db, query, orderId);
  }

  /// Exact match search for better performance
  Future<List<Map<String, dynamic>>> _searchExactProductsByBarcode(
    Database db, String query, int? orderId) async {

    String sql = '''
      SELECT
        u.*,
        b.birimadi,
        b.birimkod,
        b._key as birim_key,
        bark.barkod,
        bark._key as barkod_key,
        COALESCE(SUM(sa.miktar), 0.0) as miktar,
        COALESCE(sa.sipbirimi, b.birimkod) as sipbirimi,
        sa.sipbirimkey,
        sb.birimadi as sipbirimi_adi,
        sb.birimkod as sipbirimi_kod,
        MIN(sa.id) as order_line_id,
        CASE WHEN MIN(sa.id) IS NOT NULL AND b._key = CAST(sa.sipbirimkey AS TEXT) THEN 'order' ELSE 'out_of_order' END as source_type,
        CASE WHEN b._key = CAST(sa.sipbirimkey AS TEXT) THEN 1 ELSE 0 END as is_order_unit
      FROM urunler u
      JOIN birimler b ON b._key_scf_stokkart = u._key
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      LEFT JOIN siparis_ayrintili sa ON sa.kartkodu = u.StokKodu
        ${orderId != null ? 'AND sa.siparisler_id = ?' : ''}
      LEFT JOIN birimler sb ON CAST(sa.sipbirimkey AS TEXT) = sb._key
      WHERE u.aktif = 1
        AND (bark.barkod = ? OR u.StokKodu = ?)
      GROUP BY u.StokKodu, b._key, bark.barkod, sa.sipbirimkey
      ORDER BY
        is_order_unit DESC,
        CASE
          WHEN u.StokKodu = ? THEN 0
          WHEN bark.barkod = ? THEN 1
          ELSE 2
        END,
        LENGTH(u.StokKodu) ASC,
        u.UrunAdi ASC
      LIMIT 50
    ''';

    final params = orderId != null
      ? [orderId, query, query, query, query]
      : [query, query, query, query];

    return await db.rawQuery(sql, params);
  }

  /// LIKE search for partial matches (fallback)
  Future<List<Map<String, dynamic>>> _searchProductsByBarcodeLike(
    Database db, String query, int? orderId) async {

    // Optimize: Use a single query with better indexing strategy
    String sql = '''
      SELECT
        u.*,
        b.birimadi,
        b.birimkod,
        b._key as birim_key,
        bark.barkod,
        bark._key as barkod_key,
        COALESCE(SUM(sa.miktar), 0.0) as miktar,
        COALESCE(sa.sipbirimi, b.birimkod) as sipbirimi,
        sa.sipbirimkey,
        sb.birimadi as sipbirimi_adi,
        sb.birimkod as sipbirimi_kod,
        MIN(sa.id) as order_line_id,
        CASE WHEN MIN(sa.id) IS NOT NULL AND b._key = CAST(sa.sipbirimkey AS TEXT) THEN 'order' ELSE 'out_of_order' END as source_type,
        CASE WHEN b._key = CAST(sa.sipbirimkey AS TEXT) THEN 1 ELSE 0 END as is_order_unit
      FROM urunler u
      JOIN birimler b ON b._key_scf_stokkart = u._key
      LEFT JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      LEFT JOIN siparis_ayrintili sa ON sa.kartkodu = u.StokKodu
        ${orderId != null ? 'AND sa.siparisler_id = ?' : ''}
      LEFT JOIN birimler sb ON CAST(sa.sipbirimkey AS TEXT) = sb._key
      WHERE u.aktif = 1
        AND (bark.barkod LIKE ? OR u.StokKodu LIKE ?)
      GROUP BY u.StokKodu, b._key, bark.barkod, sa.sipbirimkey
      ORDER BY
        is_order_unit DESC,
        CASE
          WHEN u.StokKodu LIKE ? THEN 0
          WHEN bark.barkod LIKE ? THEN 1
          ELSE 2
        END,
        LENGTH(u.StokKodu) ASC,
        u.UrunAdi ASC
      LIMIT 100
    ''';

    final searchPattern = '%$query%';
    final params = orderId != null
      ? [orderId, searchPattern, searchPattern, searchPattern, searchPattern]
      : [searchPattern, searchPattern, searchPattern, searchPattern];

    final result = await db.rawQuery(sql, params);

    debugPrint("🔍 Found ${result.length} products matching barcode (LIKE search)");
    for (int i = 0; i < result.length && i < 3; i++) {
      final item = result[i];
      debugPrint("Result $i: ${item['UrunAdi']} - ${item['barkod']} - Unit: ${item['birimadi']}");
      debugPrint("  - Order unit (sipbirimi_adi): ${item['sipbirimi_adi']}");
      debugPrint("  - Is order unit: ${item['is_order_unit']}");
      debugPrint("  - birim_key: ${item['birim_key']}, sipbirimkey: ${item['sipbirimkey']}");
      debugPrint("  - source_type: ${item['source_type']}");
    }

    return result;
  }

  /// TEST: Siparişteki tüm barkodları listele
  /// DEBUG: Manuel olarak free değerini güncelle
  Future<void> debugUpdateFreeValues(int orderId, String urunKey) async {
    final db = await database;
    
    debugPrint("DEBUG: Updating free value for order $orderId, urun_key $urunKey");
    
    final updated = await db.update(
      'goods_receipt_items',
      {'free': 1},
      where: '''
        receipt_operation_uuid IN (
          SELECT operation_unique_id FROM goods_receipts WHERE siparis_id = ?
        ) AND urun_key = ?
      ''',
      whereArgs: [orderId, urunKey],
    );
    
    debugPrint("DEBUG: Updated $updated records with free = 1");
    
    // Kontrol et
    final result = await db.rawQuery('''
      SELECT gri.*, gr.siparis_id
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gri.operation_unique_id = gr.operation_unique_id
      WHERE gr.siparis_id = ? AND gri.urun_key = ?
    ''', [orderId, urunKey]);
    
    debugPrint("DEBUG: After update - found ${result.length} records:");
    for (final record in result) {
      debugPrint("  - ID: ${record['id']}, urun_key: ${record['urun_key']}, free: ${record['free']}");
    }
  }

  Future<List<Map<String, dynamic>>> debugOrderBarcodes(int orderId) async {
    final db = await database;
    
    const sql = '''
      SELECT DISTINCT
        sa.kartkodu as stok_kodu,
        u.UrunAdi,
        bark.barkod,
        b.birimadi
      FROM siparis_ayrintili sa
      JOIN urunler u ON u.StokKodu = sa.kartkodu
      JOIN birimler b ON b._key_scf_stokkart = u._key
      JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE sa.siparisler_id = ?
      ORDER BY sa.kartkodu, b.birimadi
    ''';
    
    final result = await db.rawQuery(sql, [orderId]);
    debugPrint("📋 Order $orderId barcodes: ${result.length} items");
    return result;
  }

  /// Siparişteki bir ürünün tüm barkodlarını getir (StokKodu'na göre)
  Future<List<Map<String, dynamic>>> getAllBarcodesForOrderProduct(int orderId, String stokKodu) async {
    final db = await database;
    
    const sql = '''
      SELECT DISTINCT
        u.*,
        b.birimadi,
        b.birimkod,
        b._key as birim_key,
        bark.barkod,
        bark._key as barkod_key
      FROM siparis_ayrintili sa
      JOIN urunler u ON u.StokKodu = sa.kartkodu
      JOIN birimler b ON b._key_scf_stokkart = u._key
      JOIN barkodlar bark ON bark._key_scf_stokkart_birimleri = b._key
      WHERE sa.siparisler_id = ?
        AND u.StokKodu = ?
        AND u.aktif = 1
      ORDER BY b.birimadi ASC
    ''';
    
    return await db.rawQuery(sql, [orderId, stokKodu]);
  }

  /// Bir ürünün tüm birimlerini getir (StokKodu'na göre)
  /// ESKİ SQLite UYUMLU: ROW_NUMBER() yerine subquery kullanıyor
  /// İLİŞKİ: birimler._key_scf_stokkart = urunler._key
  Future<List<Map<String, dynamic>>> getAllUnitsForProduct(String stokKodu) async {
    try {
      final db = await database;

      // Önce ürünün _key'ini bul
      const getProductKeySql = '''SELECT _key FROM urunler WHERE StokKodu = ? AND aktif = 1 LIMIT 1''';
      final productKeyResult = await db.rawQuery(getProductKeySql, [stokKodu]);

      if (productKeyResult.isEmpty) {
        debugPrint("⚠️ Product not found for StokKodu: $stokKodu");
        return [];
      }

      final productKey = productKeyResult.first['_key'] as String;
      debugPrint("🔍 Found product _key: $productKey for StokKodu: $stokKodu");

      // Önce basit sorgu ile birimler olup olmadığını kontrol et
      const checkSql = '''SELECT COUNT(*) as count FROM birimler WHERE _key_scf_stokkart = ?''';
      final checkResult = await db.rawQuery(checkSql, [productKey]);
      final birimCount = checkResult.first['count'] as int;
      debugPrint("🔍 Found $birimCount units in birimler table for product _key $productKey");

    // ESKİ SQLite UYUMLU SORGU
    // İLİŞKİ KULLANIMI: birimler._key_scf_stokkart = urunler._key
    // Her birimadi için sadece BİR kayıt döndür (barkodlu olanı tercih et)
    const sql = '''
      SELECT
        u.*,
        b.birimadi,
        b.birimkod,
        b._key as birim_key,
        (SELECT bark.barkod
         FROM barkodlar bark
         WHERE bark._key_scf_stokkart_birimleri = b._key
         LIMIT 1) as barkod,
        (SELECT bark._key
         FROM barkodlar bark
         WHERE bark._key_scf_stokkart_birimleri = b._key
         LIMIT 1) as barkod_key
      FROM urunler u
      JOIN birimler b ON b._key_scf_stokkart = u._key
      WHERE u._key = ?
        AND u.aktif = 1
        AND b._key IN (
          SELECT MIN(b2._key)
          FROM birimler b2
          WHERE b2._key_scf_stokkart = u._key
          GROUP BY b2.birimadi
        )
      ORDER BY
        CASE
          WHEN (SELECT COUNT(*) FROM barkodlar bark WHERE bark._key_scf_stokkart_birimleri = b._key) > 0 THEN 0
          ELSE 1
        END,
        b.birimadi ASC
    ''';

      final result = await db.rawQuery(sql, [productKey]);
      debugPrint("📦 Found ${result.length} unique units for product $stokKodu (grouped by unit name)");
      for (var unit in result) {
        debugPrint("  - Unit: ${unit['birimadi']} (${unit['birimkod']}), key: ${unit['birim_key']}, barcode: ${unit['barkod'] ?? 'NULL'}, has_barcode: ${unit['barkod'] != null && unit['barkod'].toString().isNotEmpty}");
      }
      return result;
    } catch (e, stackTrace) {
      // Telegram'a hata logla
      debugPrint("❌ getAllUnitsForProduct failed: $e");

      TelegramLoggerService.logError(
        'Database Query Failed: getAllUnitsForProduct',
        e.toString(),
        stackTrace: stackTrace,
        context: {
          'method': 'getAllUnitsForProduct',
          'stokKodu': stokKodu,
        },
      );

      rethrow; // Hatayı yukarı fırlat ki UI layer'da yakalanabilsin
    }
  }

  Future<String?> getPoIdBySiparisId(int siparisId) async {
    final db = await database;
    final result = await db.query(
      'siparisler',
      columns: ['fisno'],
      where: 'id = ?',
      whereArgs: [siparisId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['fisno'] as String? : null;
  }



  Future<Map<String, dynamic>?> getProductById(dynamic productId) async {
    final db = await database;
    
    // _key (string) veya UrunId (int) ile arama yap
    List<Map<String, Object?>> result;
    if (productId is String) {
      // _key ile ara
      result = await db.query(
        'urunler',
        where: '_key = ?',
        whereArgs: [productId],
        limit: 1,
      );
    } else {
      // UrunId ile ara (geriye dönük uyumluluk için)
      result = await db.query(
        'urunler',
        where: 'UrunId = ?',
        whereArgs: [productId],
        limit: 1,
      );
    }
    
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getLocationById(int locationId) async {
    final db = await database;
    final result = await db.query(
      'shelfs',
      where: 'id = ?',
      whereArgs: [locationId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getEmployeeById(int employeeId) async {
    final db = await database;
    final result = await db.query(
      'employees',
      where: 'id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // getWarehouseById kaldırıldı - SharedPreferences kullanılıyor

  Future<Map<String, dynamic>?> getOrderSummary(int siparisId) async {
    final db = await database;

    final order = await db.query(
      'siparisler',
      where: 'id = ?',
      whereArgs: [siparisId],
      limit: 1,
    );

    if (order.isEmpty) return null;

    const sql = '''
      SELECT
        sa.id,
        COALESCE(sa.urun_key, sa._key_kalemturu) as urun_key,
        sa.miktar as ordered_quantity,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        COALESCE(received.total_received, 0) as received_quantity,
        0 as putaway_quantity
      FROM siparis_ayrintili sa
      LEFT JOIN urunler u ON u._key = COALESCE(sa.urun_key, sa._key_kalemturu)
      LEFT JOIN (
        SELECT
          gri.urun_key,
          SUM(gri.quantity_received) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gri.operation_unique_id = gr.operation_unique_id
        WHERE gr.siparis_id = ?
        GROUP BY gri.urun_key
      ) received ON received.urun_key = COALESCE(sa.urun_key, sa._key_kalemturu)
      WHERE sa.siparisler_id = ?
    ''';

    final lines = await db.rawQuery(sql, [siparisId, siparisId]);

    return {
      'order': order.first,
      'lines': lines,
    };
  }

  Future<List<Map<String, dynamic>>> getReceiptItemsWithPreviousReceipts(int receiptId) async {
    final db = await database;

    final receipt = await db.query('goods_receipts', where: 'goods_receipt_id = ?', whereArgs: [receiptId], limit: 1);
    if (receipt.isEmpty) return [];

    final siparisId = receipt.first['siparis_id'];
    if (siparisId == null) return [];

    final receiptUuid = receipt.first['operation_unique_id'] as String?;
    if (receiptUuid == null) return [];

    const sql = '''
      SELECT
        gri.item_uuid as id,
        gri.urun_key,
        gri.quantity_received as current_received,
        gri.pallet_barcode,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        sa.miktar as ordered_quantity,
        sa.sipbirimi as unit,
        COALESCE(previous.previous_received, 0) as previous_received,
        COALESCE(previous.previous_received, 0) + gri.quantity_received as total_received
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u._key = gri.urun_key
      LEFT JOIN goods_receipts gr ON gri.operation_unique_id = gr.operation_unique_id
      LEFT JOIN siparis_ayrintili sa ON sa.siparisler_id = gr.siparis_id AND sa.urun_key = gri.urun_key
      LEFT JOIN (
        SELECT
          gri2.urun_key,
          SUM(gri2.quantity_received) as previous_received
        FROM goods_receipt_items gri2
        JOIN goods_receipts gr2 ON gri2.operation_unique_id = gr2.operation_unique_id
        WHERE gr2.siparis_id = ?
          AND gr2.receipt_date < (SELECT receipt_date FROM goods_receipts WHERE operation_unique_id = ?)
        GROUP BY gri2.urun_key
      ) previous ON previous.urun_key = gri.urun_key
      WHERE gri.operation_unique_id = ?
      ORDER BY gri.item_uuid
    ''';

    return await db.rawQuery(sql, [siparisId, receiptUuid, receiptUuid]);
  }

  Future<List<Map<String, dynamic>>> getReceiptItemsWithDetails(int receiptId) async {
    final db = await database;

    // Get the UUID for the receipt
    final receipt = await db.query('goods_receipts',
      columns: ['operation_unique_id'],
      where: 'goods_receipt_id = ?',
      whereArgs: [receiptId],
      limit: 1
    );
    if (receipt.isEmpty) return [];

    final receiptUuid = receipt.first['operation_unique_id'] as String?;
    if (receiptUuid == null) return [];

    const sql = '''
      SELECT
        gri.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u._key = gri.urun_key
      WHERE gri.operation_unique_id = ?
      ORDER BY gri.item_uuid
    ''';

    return await db.rawQuery(sql, [receiptUuid]);
  }

  Future<Map<String, dynamic>?> getInventoryTransferDetails(int transferId) async {
    final db = await database;

    const sql = '''
      SELECT
        it.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        source_loc.name as source_location_name,
        source_loc.code as source_location_code,
        target_loc.name as target_location_name,
        target_loc.code as target_location_code,
        emp.first_name || ' ' || emp.last_name as employee_name,
        emp.username as employee_username
      FROM inventory_transfers it
      LEFT JOIN urunler u ON u._key = it.urun_key
      LEFT JOIN shelfs source_loc ON source_loc.id = it.from_location_id
      LEFT JOIN shelfs target_loc ON target_loc.id = it.to_location_id
      LEFT JOIN employees emp ON emp.id = it.employee_id
      WHERE it.id = ?
    ''';

    final result = await db.rawQuery(sql, [transferId]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getInventoryStockForOrder(int siparisId) async {
    final db = await database;

    // YENİ YAKLŞIM: goods_receipts.operation_unique_id ile JOIN
    const sql = '''
      SELECT
        ints.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        loc.name as location_name,
        loc.code as location_code
      FROM inventory_stock ints
      LEFT JOIN urunler u ON u._key = ints.urun_key
      LEFT JOIN shelfs loc ON loc.id = ints.location_id
      LEFT JOIN goods_receipts gr ON ints.receipt_operation_uuid = gr.operation_unique_id
      WHERE gr.siparis_id = ? AND ints.stock_status = 'receiving'
      ORDER BY ints.urun_key
    ''';

    return await db.rawQuery(sql, [siparisId]);
  }

  Future<Map<String, dynamic>?> getGoodsReceiptDetails(int receiptId) async {
    final db = await database;

    const sql = '''
      SELECT
        gr.*,
        emp.first_name || ' ' || emp.last_name as employee_name,
        emp.username as employee_username,
        emp.warehouse_code as employee_warehouse_code,
        emp.role as employee_role,
        po.fisno,
        po.tarih as order_date,
        po.status as order_status,
        emp.warehouse_code as order_warehouse_code
      FROM goods_receipts gr
      LEFT JOIN employees emp ON emp.id = gr.employee_id
      LEFT JOIN siparisler po ON po.id = gr.siparis_id
      WHERE gr.goods_receipt_id = ?
    ''';

    final result = await db.rawQuery(sql, [receiptId]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getReceiptItemsWithOrderDetails(int receiptId) async {
    final db = await database;

    // Get the UUID for the receipt
    final receipt = await db.query('goods_receipts',
      columns: ['operation_unique_id'],
      where: 'goods_receipt_id = ?',
      whereArgs: [receiptId],
      limit: 1
    );
    if (receipt.isEmpty) return [];

    final receiptUuid = receipt.first['operation_unique_id'] as String?;
    if (receiptUuid == null) return [];

    const sql = '''
      SELECT
        gri.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        u.Birim1 as product_unit,
        u.qty as product_box_qty,
        sa.miktar as ordered_quantity,
        sa.sipbirimi as order_unit,
        sa.notes as order_line_notes,
        0 as putaway_quantity
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u._key = gri.urun_key
      LEFT JOIN goods_receipts gr ON gri.operation_unique_id = gr.operation_unique_id
      LEFT JOIN siparis_ayrintili sa ON sa.siparisler_id = gr.siparis_id AND sa.urun_key = gri.urun_key
      WHERE gri.operation_unique_id = ?
      ORDER BY gri.item_uuid
    ''';

    return await db.rawQuery(sql, [receiptUuid]);
  }

  Future<Map<String, dynamic>> getEnrichedInventoryTransferData(String operationData) async {
    try {
      final data = jsonDecode(operationData);
      final header = data['header'] as Map<String, dynamic>? ?? {};
      final items = data['items'] as List<dynamic>? ?? [];

      Map<String, dynamic>? employeeInfo;
      if (header['employee_id'] != null) {
        employeeInfo = await getEmployeeById(header['employee_id']);
        if (employeeInfo != null) {
          header['employee_info'] = employeeInfo;
          header['employee_name'] = '${employeeInfo['first_name']} ${employeeInfo['last_name']}';
        }
      }

      final prefs = await SharedPreferences.getInstance();
      
      final warehouseName = prefs.getString('warehouse_name') ?? 'N/A';
      final warehouseCode = prefs.getString('warehouse_code') ?? 'N/A';
      final branchName = prefs.getString('branch_name') ?? 'N/A';
      
      debugPrint('🏭 TRANSFER ENRICH: SharedPreferences warehouse bilgileri:');
      debugPrint('  - warehouse_name: $warehouseName');
      debugPrint('  - warehouse_code: $warehouseCode');
      debugPrint('  - branch_name: $branchName');
      
      Map<String, dynamic> warehouseInfo = {
        'name': warehouseName,
        'warehouse_code': warehouseCode,
        'branch_name': branchName,
      };

      header['warehouse_info'] = warehouseInfo;

      final sourceLocationId = header['source_location_id'];
      if (sourceLocationId != null && sourceLocationId != 0) {
        final sourceLoc = await getLocationById(sourceLocationId);
        if (sourceLoc != null) {
          header['source_location_name'] = sourceLoc['name'];
          header['source_location_code'] = sourceLoc['code'];
        }
      } else {
        header['source_location_name'] = '000';
        header['source_location_code'] = '000';
      }

      final targetLocationId = header['target_location_id'];
      if (targetLocationId != null) {
        final targetLoc = await getLocationById(targetLocationId);
        if (targetLoc != null) {
          header['target_location_name'] = targetLoc['name'];
          header['target_location_code'] = targetLoc['code'];
        }
      }

      final siparisId = header['siparis_id'];
      if (siparisId != null) {
        final poId = await getPoIdBySiparisId(siparisId);
        if (poId != null) {
          header['fisno'] = poId;
        }
      }

      final enrichedItems = <Map<String, dynamic>>[];
      for (final item in items) {
        final enrichedItem = Map<String, dynamic>.from(item);
        final productId = item['product_id'] ?? item['urun_key'];
        if (productId != null) {
          final product = await getProductById(productId);
          if (product != null) {
            enrichedItem['product_name'] = product['UrunAdi'];
            enrichedItem['product_code'] = product['StokKodu'];
            
            // Birim bilgisini ekle - birim_key ile birimler tablosundan birim adını al
            final birimKey = enrichedItem['birim_key'] as String?;
            if (birimKey != null && birimKey.isNotEmpty) {
              try {
                final db = await database;
                final birimResult = await db.rawQuery('''
                  SELECT birimadi 
                  FROM birimler 
                  WHERE _key = ? 
                  LIMIT 1
                ''', [birimKey]);
                
                if (birimResult.isNotEmpty) {
                  enrichedItem['unit'] = birimResult.first['birimadi'] as String? ?? '';
                } else {
                  enrichedItem['unit'] = '';
                }
              } catch (e) {
                debugPrint('Transfer PDF için birim adı alınırken hata: $e');
                enrichedItem['unit'] = '';
              }
            } else {
              enrichedItem['unit'] = '';
            }
            
            // Yeni barkod sistemi için: ürünün ilgili barkodunu bul
            String productBarcode = '';
            try {
              // Ürünün StokKodu ile birimler tablosundan birimlerini bul
              final db = await database;
              final birimResults = await db.query(
                'birimler',
                where: 'StokKodu = ?',
                whereArgs: [product['StokKodu']],
              );
              
              if (birimResults.isNotEmpty) {
                // İlk birimin barkodunu al
                final birimKey = birimResults.first['_key'];
                final barkodResults = await db.query(
                  'barkodlar',
                  where: '_key_scf_stokkart_birimleri = ?',
                  whereArgs: [birimKey],
                  limit: 1,
                );
                
                if (barkodResults.isNotEmpty) {
                  productBarcode = barkodResults.first['barkod'] as String? ?? '';
                }
              }
            } catch (e) {
              debugPrint('Transfer PDF için barkod alınırken hata: $e');
            }
            
            enrichedItem['product_barcode'] = productBarcode;
          }
        }
        enrichedItems.add(enrichedItem);
      }

      data['header'] = header;
      data['items'] = enrichedItems;
      return data;

    } catch (e, s) {
      debugPrint('Error enriching inventory transfer data: $e\n$s');
      return jsonDecode(operationData);
    }
  }

  Future<Map<String, dynamic>> getEnrichedGoodsReceiptData(String operationData, {DateTime? operationDate}) async {
    final db = await database;

    try {
      final data = jsonDecode(operationData);
      final header = data['header'] as Map<String, dynamic>? ?? {};
      final items = (data['items'] as List<dynamic>?) ?? [];

      DateTime? actualReceiptDate = operationDate;
      final headerReceiptDate = header['receipt_date'];
      if (headerReceiptDate != null) {
        try {
          actualReceiptDate = DateTime.parse(headerReceiptDate.toString());
        } catch (e) {
          // Parse error, use operationDate
        }
      }

      Map<String, dynamic>? employeeInfo;
      if (header['employee_id'] != null) {
        employeeInfo = await getEmployeeById(header['employee_id']);
        if (employeeInfo != null) {
          header['employee_info'] = employeeInfo;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      
      final warehouseName = prefs.getString('warehouse_name') ?? 'N/A';
      final warehouseCode = prefs.getString('warehouse_code') ?? 'N/A';
      final branchName = prefs.getString('branch_name') ?? 'N/A';
      final receivingMode = prefs.getInt('receiving_mode') ?? 2;
      
      debugPrint('🏭 PDF ENRICH: SharedPreferences warehouse bilgileri:');
      debugPrint('  - warehouse_name: $warehouseName');
      debugPrint('  - warehouse_code: $warehouseCode');
      debugPrint('  - branch_name: $branchName');
      debugPrint('  - receiving_mode: $receivingMode');
      
      Map<String, dynamic> warehouseInfo = {
        'name': warehouseName,
        'warehouse_code': warehouseCode,
        'branch_name': branchName,
        'receiving_mode': receivingMode,
      };

      // Warehouse bilgileri SharedPreferences'tan alındı

      header['warehouse_info'] = warehouseInfo;

      final enrichedItems = <Map<String, dynamic>>[];
      final siparisId = header['siparis_id'];

      for (final item in items) {
        final mutableItem = Map<String, dynamic>.from(item);
        
        // urun_key yoksa urun_id'yi kullan
        final productId = item['urun_key'] ?? item['urun_id'];
        
        if (productId != null) {
          final product = await getProductById(productId);
          if (product != null) {
            mutableItem['product_name'] = product['UrunAdi'];
            mutableItem['product_code'] = product['StokKodu'];
            mutableItem['urun_key'] = product['_key'] ?? productId; // Use _key if available, otherwise use productId
            
            // Birim bilgisini ekle - birim_key ile birimler tablosundan birim adını al
            final birimKey = mutableItem['birim_key'] as String?;
            if (birimKey != null && birimKey.isNotEmpty) {
              try {
                final birimResult = await db.rawQuery('''
                  SELECT birimadi 
                  FROM birimler 
                  WHERE _key = ? 
                  LIMIT 1
                ''', [birimKey]);
                
                if (birimResult.isNotEmpty) {
                  mutableItem['unit'] = birimResult.first['birimadi'] as String? ?? '';
                } else {
                  mutableItem['unit'] = '';
                }
              } catch (e) {
                debugPrint('PDF için birim adı alınırken hata: $e');
                mutableItem['unit'] = '';
              }
            } else {
              mutableItem['unit'] = '';
            }
            
            // Yeni barkod sistemi için: ürünün ilgili barkodunu bul
            String productBarcode = '';
            try {
              // Ürünün StokKodu ile birimler tablosundan birimlerini bul
              final birimResults = await db.query(
                'birimler',
                where: 'StokKodu = ?',
                whereArgs: [product['StokKodu']],
              );
              
              if (birimResults.isNotEmpty) {
                // İlk birimin barkodunu al
                final birimKey = birimResults.first['_key'];
                final barkodResults = await db.query(
                  'barkodlar',
                  where: '_key_scf_stokkart_birimleri = ?',
                  whereArgs: [birimKey],
                  limit: 1,
                );
                
                if (barkodResults.isNotEmpty) {
                  productBarcode = barkodResults.first['barkod'] as String? ?? '';
                }
              }
            } catch (e) {
              debugPrint('PDF için barkod alınırken hata: $e');
            }
            
            // PDF için barkod bilgisini ekle
            mutableItem['product_barcode'] = productBarcode;
            
            // Eğer barcode bulunamadıysa, direkt barkodlar tablosunda ürünün barkodunu ara
            if (productBarcode.isEmpty) {
              try {
                // Alternatif yöntem: Barkodlar tablosunda direkt product code'a göre ara
                final directBarkodResults = await db.rawQuery('''
                  SELECT b.barkod 
                  FROM barkodlar b
                  INNER JOIN birimler br ON b._key_scf_stokkart_birimleri = br._key
                  WHERE br.StokKodu = ?
                  LIMIT 1
                ''', [product['StokKodu']]);
                
                if (directBarkodResults.isNotEmpty) {
                  productBarcode = directBarkodResults.first['barkod'] as String? ?? '';
                }
              } catch (e) {
                debugPrint('PDF barcode alternatif arama hatası: $e');
              }
            }
            
            mutableItem['product_barcode'] = productBarcode;
          }
        }

        if (siparisId != null && productId != null) {
          final currentReceivedInThisOp = (item['quantity'] as num?)?.toDouble() ?? 0;

          if (actualReceiptDate != null) {
            String? currentReceiptId;
            try {
              final dateOnly = DateTime(
                actualReceiptDate.year,
                actualReceiptDate.month,
                actualReceiptDate.day,
                actualReceiptDate.hour,
                actualReceiptDate.minute,
                actualReceiptDate.second,
              );
              var receiptDateStr = dateOnly.toUtc().toIso8601String().replaceAll('T', ' ').replaceAll('Z', '');
              if (receiptDateStr.endsWith('.000')) {
                receiptDateStr = receiptDateStr.substring(0, receiptDateStr.length - 4);
              }

              debugPrint('DEBUG - Looking for receipt with date: $receiptDateStr (truncated from ${actualReceiptDate.toUtc().toIso8601String()})');

              final currentReceiptQuery = await db.rawQuery(
                  'SELECT operation_unique_id FROM goods_receipts WHERE siparis_id = ? AND receipt_date = ?',
                  [siparisId, receiptDateStr]
              );
              if (currentReceiptQuery.isNotEmpty) {
                currentReceiptId = currentReceiptQuery.first['operation_unique_id'] as String?;
                debugPrint('DEBUG - Found current receipt UUID to exclude: $currentReceiptId for date: $receiptDateStr');
              } else {
                final likeQuery = await db.rawQuery(
                    'SELECT operation_unique_id FROM goods_receipts WHERE siparis_id = ? AND receipt_date LIKE ?',
                    [siparisId, '$receiptDateStr%']
                );
                if (likeQuery.isNotEmpty) {
                  currentReceiptId = likeQuery.first['operation_unique_id'] as String?;
                  debugPrint('DEBUG - Found current receipt UUID via LIKE: $currentReceiptId for date pattern: $receiptDateStr%');
                } else {
                  debugPrint('DEBUG - No receipt found to exclude for date: $receiptDateStr (tried exact and LIKE)');
                }
              }
            } catch (e) {
              debugPrint('Error finding current receipt UUID: $e');
            }

            final previousReceived = await _getPreviousReceivedQuantity(
                siparisId,
                productId,
                beforeDate: actualReceiptDate,
                excludeReceiptId: currentReceiptId
            );
            final totalReceived = previousReceived + currentReceivedInThisOp;

            mutableItem['previous_received'] = previousReceived;
            mutableItem['current_received'] = currentReceivedInThisOp;
            mutableItem['total_received'] = totalReceived;
          } else {
            final totalReceivedNow = await _getPreviousReceivedQuantity(siparisId, productId);
            final previousReceived = totalReceivedNow - currentReceivedInThisOp;

            mutableItem['previous_received'] = previousReceived > 0 ? previousReceived : 0;
            mutableItem['current_received'] = currentReceivedInThisOp;
            mutableItem['total_received'] = totalReceivedNow;
          }
        }

        // urun_key'in mutlaka set edildiğinden emin ol
        if (mutableItem['urun_key'] == null && productId != null) {
          mutableItem['urun_key'] = productId;
        }
        
        enrichedItems.add(mutableItem);
      }

      if (siparisId != null) {
        final orderSummary = await getOrderSummary(siparisId);
        if (orderSummary != null) {
          header['order_info'] = orderSummary['order'];
          final orderLines = orderSummary['lines'] as List<dynamic>;
          

          final orderLinesMap = {for (var line in orderLines) line['urun_key']: line};

          for (final item in enrichedItems) {
            final orderLine = orderLinesMap[item['urun_key']];
            if (orderLine != null) {
              item['ordered_quantity'] = orderLine['ordered_quantity'] ?? 0.0;
              item['unit'] = orderLine['unit'] ?? item['unit'];
            } else {
              item['ordered_quantity'] = 0.0;
            }
          }
        }
      }

      data['items'] = enrichedItems;
      data['header'] = header;
      return data;

    } catch (e, s) {
      debugPrint('Error enriching goods receipt data: $e\n$s');
      return jsonDecode(operationData);
    }
  }

  Future<double> _getPreviousReceivedQuantity(int siparisId, dynamic productId, {DateTime? beforeDate, String? excludeReceiptId}) async {
    final db = await database;

    String sql;
    List<dynamic> params;

    if (beforeDate != null || excludeReceiptId != null) {
      List<String> conditions = ['gr.siparis_id = ?', 'gri.urun_key = ?'];
      params = [siparisId, productId];

      if (beforeDate != null) {
        conditions.add('gr.receipt_date < ?');
        params.add(beforeDate.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' '));
      }

      if (excludeReceiptId != null) {
        conditions.add('gr.operation_unique_id != ?');
        params.add(excludeReceiptId);
      }

      sql = '''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gri.operation_unique_id = gr.operation_unique_id
        WHERE ${conditions.join(' AND ')}
      ''';

      // final debugSql = '''
      //   SELECT gr.receipt_date, gri.quantity_received, gr.goods_receipt_id as receipt_id
      //   FROM goods_receipt_items gri
      //   JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      //   WHERE ${conditions.join(' AND ')}
      //   ORDER BY gr.receipt_date
      // ''';
    } else {
      sql = '''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gri.operation_unique_id = gr.operation_unique_id
        WHERE gr.siparis_id = ? AND gri.urun_key = ?
      ''';
      params = [siparisId, productId];
    }

    final result = await db.rawQuery(sql, params);
    final totalReceived = (result.first['total_received'] as num?)?.toDouble() ?? 0.0;


    return totalReceived;
  }

  Future<bool> hasForceCloseOperationForOrder(int siparisId, DateTime? afterDate) async {
    final db = await database;

    if (afterDate == null) {
      return false;
    }

    try {
      final forceCloseOps = await db.rawQuery('''
        SELECT po.data, po.created_at
        FROM pending_operation po
        WHERE po.type = 'forceCloseOrder'
          AND (
            po.data LIKE '%"siparis_id":' || ? || ',%' OR
            po.data LIKE '%"siparis_id":' || ? || '}%'
          )
      ''', [siparisId, siparisId]);

      debugPrint('DEBUG hasForceClose: Found ${forceCloseOps.length} force close operations for order $siparisId');

      for (final row in forceCloseOps) {
        try {
          final dataStr = row['data'] as String;
          final data = jsonDecode(dataStr) as Map<String, dynamic>;

          DateTime forceCloseDate;
          if (data.containsKey('receipt_date') && data['receipt_date'] != null) {
            forceCloseDate = DateTime.parse(data['receipt_date'].toString());
            debugPrint('DEBUG hasForceClose: Using receipt_date from data: $forceCloseDate');
          } else {
            forceCloseDate = DateTime.parse(row['created_at'].toString());
            debugPrint('DEBUG hasForceClose: Using created_at: $forceCloseDate');
          }

          debugPrint('DEBUG hasForceClose: Comparing dates - afterDate: $afterDate, forceCloseDate: $forceCloseDate');

          if (forceCloseDate.isAfter(afterDate)) {
            debugPrint('DEBUG hasForceClose: Force close is after receipt, checking intermediate receipts...');

            String formatDateForMysql(DateTime date) {
              return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
            }

            final afterDateStr = formatDateForMysql(afterDate);
            final forceCloseDatePlusOne = forceCloseDate.add(const Duration(seconds: 1));
            final forceCloseDateStr = formatDateForMysql(forceCloseDatePlusOne);

            debugPrint('DEBUG hasForceClose: Date range for intermediate check (MySQL format): $afterDateStr to $forceCloseDateStr (force close +1 sec)');

            final syncedReceipts = await db.rawQuery('''
              SELECT COUNT(*) as count
              FROM goods_receipts
              WHERE siparis_id = ? AND receipt_date > ? AND receipt_date < ?
            ''', [siparisId, afterDateStr, forceCloseDateStr]);

            final syncedCount = Sqflite.firstIntValue(syncedReceipts) ?? 0;
            debugPrint('DEBUG hasForceClose: Synced receipts in range: $syncedCount');

            final debugSyncedReceipts = await db.rawQuery('''
              SELECT receipt_date, goods_receipt_id
              FROM goods_receipts
              WHERE siparis_id = ? AND receipt_date > ? AND receipt_date < ?
            ''', [siparisId, afterDateStr, forceCloseDateStr]);
            debugPrint('DEBUG hasForceClose: Synced receipts found in range: $debugSyncedReceipts');

            final pendingReceipts = await db.rawQuery('''
              SELECT po.data
              FROM pending_operation po
              WHERE po.type = 'goodsReceipt'
                AND po.status = 'pending'
                AND (
                  po.data LIKE '%"header":{"siparis_id":' || ? || ',%' OR
                  po.data LIKE '%"header":{"siparis_id":' || ? || '}}%'
                )
            ''', [siparisId, siparisId]);

            int pendingCount = 0;
            debugPrint('DEBUG hasForceClose: Found ${pendingReceipts.length} pending receipts to check');

            for (final pendingRow in pendingReceipts) {
              try {
                final pendingDataStr = pendingRow['data'] as String;
                final pendingData = jsonDecode(pendingDataStr) as Map<String, dynamic>;
                final header = pendingData['header'] as Map<String, dynamic>?;

                if (header != null && header['receipt_date'] != null) {
                  final receiptDate = DateTime.parse(header['receipt_date'].toString());
                  debugPrint('DEBUG hasForceClose: Checking pending receipt date: $receiptDate');
                  if (receiptDate.isAfter(afterDate) && receiptDate.isBefore(forceCloseDatePlusOne)) {
                    pendingCount++;
                    debugPrint('DEBUG hasForceClose: Pending receipt in range found: $receiptDate');
                  }
                }
              } catch (e) {
                debugPrint('Error parsing pending goods receipt data: $e');
                continue;
              }
            }

            final totalIntermediateCount = syncedCount + pendingCount;
            debugPrint('DEBUG hasForceClose: Total intermediate receipts: synced=$syncedCount, pending=$pendingCount, total=$totalIntermediateCount');

            if (totalIntermediateCount == 0) {
              debugPrint('hasForceCloseOperationForOrder: siparisId=$siparisId, FOUND closing receipt at $afterDate (synced: $syncedCount, pending: $pendingCount)');
              return true;
            } else {
              debugPrint('hasForceCloseOperationForOrder: siparisId=$siparisId, intermediate receipts found: synced=$syncedCount, pending=$pendingCount, total=$totalIntermediateCount');
            }
          } else {
            debugPrint('DEBUG hasForceClose: Force close is NOT after receipt, skipping');
          }
        } catch (e) {
          debugPrint('Error parsing force close data: $e');
          continue;
        }
      }

      debugPrint('hasForceCloseOperationForOrder: siparisId=$siparisId, NO suitable force close found for receipt at $afterDate');
      return false;
    } catch (e) {
      debugPrint('hasForceCloseOperationForOrder error: $e');
      return false;
    }
  }

  Future<int?> getOrderStatus(int siparisId) async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT status
      FROM siparisler
      WHERE id = ?
    ''', [siparisId]);

    if (result.isEmpty) return null;
    return (result.first['status'] as int?);
  }

  Future<Map<String, dynamic>?> getSystemInfo(int warehouseId) async {
    final db = await database;
    final prefs = await SharedPreferences.getInstance();

    // Warehouse bilgilerini SharedPreferences'tan al
    final warehouseInfo = {
      'id': warehouseId,
      'name': prefs.getString('warehouse_name') ?? 'N/A',
      'warehouse_code': prefs.getString('warehouse_code') ?? 'N/A',
      'branch_name': prefs.getString('branch_name') ?? 'N/A',
    };

    final warehouseCode = prefs.getString('warehouse_code') ?? '';
    final employeeCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM employees WHERE warehouse_code = ? AND is_active = 1',
        [warehouseCode]
    );

    final locationCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM shelfs WHERE warehouse_id = ? AND is_active = 1',
        [warehouseId]
    );

    return {
      'warehouse': warehouseInfo,
      'employee_count': employeeCount.first['count'],
      'location_count': locationCount.first['count'],
    };
  }

  Future<Map<String, dynamic>?> getPendingOperationDetails(String uniqueId) async {
    final db = await database;

    final operation = await db.query(
      'pending_operation',
      where: 'unique_id = ?',
      whereArgs: [uniqueId],
      limit: 1,
    );

    if (operation.isEmpty) return null;

    return operation.first;
  }

  Future<void> addPendingOperation(PendingOperation operation) async {
    final db = await database;
    await db.insert('pending_operation', operation.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getFreeReceiptsForPutaway() async {
    final db = await database;

    // Duplicate'leri tespit et ve temizle
    final duplicateCheck = await db.rawQuery('''
      SELECT delivery_note_number, COUNT(*) as count
      FROM goods_receipts
      WHERE siparis_id IS NULL AND delivery_note_number IS NOT NULL
      GROUP BY delivery_note_number
      HAVING COUNT(*) > 1
    ''');

    if (duplicateCheck.isNotEmpty) {
      await db.transaction((txn) async {
        for (final dup in duplicateCheck) {
          final deliveryNote = dup['delivery_note_number'];
          
          // En eski kaydı bırak, diğerlerini sil
          final duplicateReceipts = await txn.query(
            'goods_receipts',
            where: 'delivery_note_number = ? AND siparis_id IS NULL',
            whereArgs: [deliveryNote],
            orderBy: 'receipt_date ASC'
          );

          if (duplicateReceipts.length > 1) {
            // İlk kaydı koru, diğerlerini sil
            final receiptsToDelete = duplicateReceipts.skip(1).toList();

            for (final receipt in receiptsToDelete) {
              final operationUuid = receipt['operation_unique_id'] as String?;

              if (operationUuid != null) {
                // İlişkili goods_receipt_items'ları da sil (operation_unique_id ile)
                await txn.delete('goods_receipt_items',
                  where: 'operation_unique_id = ?', whereArgs: [operationUuid]);

                // İlişkili inventory_stock kayıtlarını da sil (UUID ile!)
                await txn.delete('inventory_stock',
                  where: 'receipt_operation_uuid = ?', whereArgs: [operationUuid]);

                // goods_receipt'i sil (UUID ile)
                await txn.delete('goods_receipts',
                  where: 'operation_unique_id = ?', whereArgs: [operationUuid]);
              }
            }
          }
        }
      });
    }

    // UUID bazlı serbest mal kabul listesi
    const sql = '''
      SELECT
        gr.operation_unique_id,
        COALESCE(gr.delivery_note_number, 'FREE-' || gr.operation_unique_id) as delivery_note_number,
        COALESCE(gr.receipt_date, MIN(ist.created_at)) as receipt_date,
        gr.employee_id,
        COALESCE(e.first_name || ' ' || e.last_name, 'Unknown') as employee_name,
        COUNT(DISTINCT ist.urun_key) as item_count,
        SUM(ist.quantity) as total_quantity
      FROM inventory_stock ist
      INNER JOIN goods_receipts gr ON ist.receipt_operation_uuid = gr.operation_unique_id
      LEFT JOIN employees e ON e.id = gr.employee_id
      WHERE gr.siparis_id IS NULL
        AND ist.receipt_operation_uuid IS NOT NULL
        AND ist.stock_status = 'receiving'
        AND ist.quantity > 0
      GROUP BY gr.operation_unique_id, gr.delivery_note_number, gr.receipt_date, gr.employee_id, e.first_name, e.last_name
      ORDER BY COALESCE(gr.receipt_date, MIN(ist.created_at)) DESC
    ''';

    return await db.rawQuery(sql);
  }

  Future<List<Map<String, dynamic>>> getStockItemsForFreeReceipt(String deliveryNoteNumber) async {
    final db = await database;

    const sql = '''
      SELECT
        ist.id,
        ist.urun_key,
        ist.quantity,
        ist.pallet_barcode,
        ist.expiry_date,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
      FROM inventory_stock ist
      LEFT JOIN urunler u ON u._key = ist.urun_key
      LEFT JOIN goods_receipts gr ON ist.receipt_operation_uuid = gr.operation_unique_id
      WHERE gr.delivery_note_number = ?
        AND ist.stock_status = 'receiving'
        AND gr.siparis_id IS NULL
      ORDER BY ist.urun_key, ist.expiry_date
    ''';

    return await db.rawQuery(sql, [deliveryNoteNumber]);
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation',
        where: "status = ?",
        whereArgs: ['pending'],
        orderBy: 'created_at ASC');

    final enrichedMaps = <Map<String, dynamic>>[];
    for (final map in maps) {
      final enrichedMap = Map<String, dynamic>.from(map);
      enrichedMap['data'] = await _enrichOperationDataForDisplay(map['data'] as String, map['type'] as String);
      enrichedMaps.add(enrichedMap);
    }

    final operations = enrichedMaps.map((map) => PendingOperation.fromMap(map)).toList();
    
    // Internal sync operasyonlarını filtrele (inventory stock sync gibi)
    return operations.where((op) => op.shouldShowInPending).toList();
  }

  Future<PendingOperation?> getPendingOperationById(int id) async {
    final db = await database;
    final maps = await db.query('pending_operation',
        where: "id = ?",
        whereArgs: [id],
        limit: 1);
    
    if (maps.isEmpty) return null;
    
    return PendingOperation.fromMap(maps.first);
  }

  Future<List<PendingOperation>> getSyncedOperations() async {
    final db = await database;
    // Hem synced hem de failed (permanent error) durumundaki işlemleri getir
    final maps = await db.query('pending_operation',
        where: "status IN (?, ?)",
        whereArgs: ['synced', 'failed'],
        orderBy: 'synced_at DESC');

    final enrichedMaps = <Map<String, dynamic>>[];
    for (final map in maps) {
      final enrichedMap = Map<String, dynamic>.from(map);
      enrichedMap['data'] = await _enrichOperationDataForDisplay(map['data'] as String, map['type'] as String);
      enrichedMaps.add(enrichedMap);
    }

    return enrichedMaps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<String> _enrichOperationDataForDisplay(String operationData, String operationType) async {
    try {
      final data = jsonDecode(operationData) as Map<String, dynamic>;

      if (operationType == 'inventoryTransfer') {
        final header = data['header'] as Map<String, dynamic>? ?? {};

        final sourceLocationId = header['source_location_id'];
        if (sourceLocationId != null && sourceLocationId != 0) {
          final sourceLoc = await getLocationById(sourceLocationId);
          if (sourceLoc != null) {
            header['source_location_name'] = sourceLoc['name'];
          }
        } else {
          header['source_location_name'] = '000';
        }

        final targetLocationId = header['target_location_id'];
        if (targetLocationId != null) {
          final targetLoc = await getLocationById(targetLocationId);
          if (targetLoc != null) {
            header['target_location_name'] = targetLoc['name'];
          }
        }

        data['header'] = header;
      } else if (operationType == 'goodsReceipt') {
        final header = data['header'] as Map<String, dynamic>? ?? {};

        final siparisId = header['siparis_id'];
        if (siparisId != null) {
          final poId = await getPoIdBySiparisId(siparisId);
          if (poId != null) {
            header['fisno'] = poId;
          }
        }
        if (header['delivery_note_number'] != null) {
          header['delivery_note_number'] = header['delivery_note_number'];
        }

        data['header'] = header;
      }

      return jsonEncode(data);
    } catch (e) {
      debugPrint('Error enriching operation data for display: $e');
      return operationData;
    }
  }

  Future<void> markOperationAsSynced(int id) async {
    final db = await database;
    await db.update(
      'pending_operation',
      {
        'status': 'synced',
        'synced_at': DateTime.now().toUtc().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateOperationWithError(int id, String errorMessage) async {
    final db = await database;
    await db.update(
      'pending_operation',
      {'error_message': errorMessage},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markOperationAsPermanentError(int id, String errorMessage) async {
    final db = await database;
    await db.update(
      'pending_operation',
      {
        'status': 'failed',  // permanent failure olarak işaretle
        'error_message': errorMessage,
        'synced_at': DateTime.now().toUtc().toIso8601String()  // History'de görünmesi için
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('✅ Operation $id marked as permanently failed: $errorMessage');
  }

  Future<void> cleanupOldSyncedOperations({int days = 14}) async {
    final db = await database;
    final cutoffDate = DateTime.now().toUtc().subtract(Duration(days: days));
    final count = await db.delete(
      'pending_operation',
      where: "status = ? AND synced_at < ?",
      whereArgs: ['synced', cutoffDate.toIso8601String()],
    );
    if (count > 0) {
      debugPrint("$count adet eski senkronize edilmiş işlem temizlendi (${days} günden eski).");
    }
  }

  /// Veritabanı boyutunu küçültmek için eski verileri temizler
  /// Siparişler ve inventory_stock KESİNLİKLE silinmez
  /// Sadece 14 günden eski transferler ve mal kabul kayıtları temizlenir
  Future<void> cleanupOldData({int days = 14}) async {
    final db = await database;
    final cutoffDate = DateTime.now().toUtc().subtract(Duration(days: days));

    await db.transaction((txn) async {
      // 1. Eski inventory_transfers kayıtlarını sil (14 günden eski)
      final transferCount = await txn.delete(
        'inventory_transfers',
        where: 'created_at < ?',
        whereArgs: [cutoffDate.toIso8601String()]
      );

      // 2. Eski goods_receipt_items kayıtlarını sil (14 günden eski, sipariş dışı)
      // Sipariş dışı mal kabulleri (free receipts) temizle
      final receiptItemsCount = await txn.rawDelete('''
        DELETE FROM goods_receipt_items
        WHERE created_at < ?
        AND operation_unique_id IN (
          SELECT operation_unique_id FROM goods_receipts
          WHERE siparis_id IS NULL
        )
      ''', [cutoffDate.toIso8601String()]);

      // 3. Eski goods_receipts kayıtlarını sil (14 günden eski, sipariş dışı)
      final receiptsCount = await txn.delete(
        'goods_receipts',
        where: 'created_at < ? AND siparis_id IS NULL',
        whereArgs: [cutoffDate.toIso8601String()]
      );

      debugPrint("Veritabanı temizleme tamamlandı (${days} günden eski):");
      debugPrint("- $transferCount adet eski transfer kaydı silindi");
      debugPrint("- $receiptItemsCount adet eski mal kabul detayı silindi (sipariş dışı)");
      debugPrint("- $receiptsCount adet eski mal kabul kaydı silindi (sipariş dışı)");
      debugPrint("- ✅ Siparişler korunuyor");
      debugPrint("- ✅ Sipariş detayları korunuyor");
      debugPrint("- ✅ Inventory stock korunuyor");
      debugPrint("- ✅ Siparişli mal kabul kayıtları korunuyor");

      return; // Erken çık, siparişleri silme

      // 2. DEVRE DIŞI: Status 2,3 olan eski siparişleri ve bağlı kayıtları sil
      final oldOrders = await txn.query(
        'siparisler',
        columns: ['id'],
        where: 'status IN (2,3) AND updated_at < ?',
        whereArgs: [cutoffDate.toIso8601String()]
      );

      int orderCount = 0;
      int receiptCount = 0;
      int receiptItemCount = 0;
      int putawayCount = 0;

      for (final order in oldOrders) {
        final orderId = order['id'] as int;

        // Doğru silme sırası: Child tabloları önce sil

        // 1. inventory_stock (UUID bazlı - goods_receipts'e bağlı olan kayıtları sil)
        await txn.delete(
          'inventory_stock',
          where: 'receipt_operation_uuid IN (SELECT operation_unique_id FROM goods_receipts WHERE siparis_id = ?)',
          whereArgs: [orderId]
        );

        // 2. goods_receipt_items (en child tablo)
        final receiptItems = await txn.delete(
          'goods_receipt_items',
          where: 'operation_unique_id IN (SELECT operation_unique_id FROM goods_receipts WHERE siparis_id = ?)',
          whereArgs: [orderId]
        );
        receiptItemCount += receiptItems;

        // 3. goods_receipts (parent tablo)
        final receipts = await txn.delete(
          'goods_receipts',
          where: 'siparis_id = ?',
          whereArgs: [orderId]
        );
        receiptCount += receipts;

        // wms_putaway_status tablosu kaldırıldı

        // 4. siparis_ayrintili (sipariş satırları)
        await txn.delete(
          'siparis_ayrintili',
          where: 'siparisler_id = ?',
          whereArgs: [orderId]
        );

        // 5. siparisler (ana sipariş - en son)
        await txn.delete(
          'siparisler',
          where: 'id = ?',
          whereArgs: [orderId]
        );
        orderCount++;
      }

      debugPrint("Veritabanı temizleme tamamlandı:");
      debugPrint("- $transferCount adet eski transfer kaydı silindi");
      debugPrint("- $orderCount adet tamamlanmış sipariş silindi");
      debugPrint("- $receiptCount adet mal kabul kaydı silindi");
      debugPrint("- $receiptItemCount adet mal kabul detayı silindi");
      debugPrint("- $putawayCount adet yerleştirme kaydı silindi");
    });
  }


  /// Ana temizleme metodu - tüm cleanup işlemlerini gerçekleştirir
  Future<void> performMaintenanceCleanup({int days = 14}) async {
    debugPrint("🧹 Veritabanı bakımı başlatılıyor (${days} günden eski kayıtlar)...");

    try {
      // 1. Eski sync edilmiş operasyonları temizle
      await cleanupOldSyncedOperations(days: days);

      // 2. Eski verileri temizle
      await cleanupOldData(days: days);

      debugPrint("✅ Veritabanı bakımı tamamlandı!");
    } catch (e, s) {
      debugPrint("❌ Veritabanı bakımı sırasında hata: $e\n$s");
    }
  }

  Future<void> addSyncLog(String type, String status, String message) async {
    final db = await database;
    await db.insert('sync_log', {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'type': type, 'status': status, 'message': message,
    });
  }

  Future<List<SyncLog>> getSyncLogs() async {
    final db = await database;
    final maps = await db.query('sync_log', orderBy: 'timestamp DESC', limit: 100);
    return maps.map((map) => SyncLog.fromMap(map)).toList();
  }

  // ==================== UNKNOWN BARCODES METHODS ====================

  /// Veritabanında bulunamayan barkodu kaydet
  Future<int> saveUnknownBarcode(String barcode, {int? employeeId, String? warehouseCode}) async {
    final db = await database;

    try {
      final id = await db.insert('unknown_barcodes', {
        'barcode': barcode,
        'employee_id': employeeId,
        'warehouse_code': warehouseCode,
        'scanned_at': DateTime.now().toUtc().toIso8601String(),
        'synced': 0,
      });

      debugPrint('📝 Bilinmeyen barkod kaydedildi: $barcode (ID: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Bilinmeyen barkod kaydetme hatası: $e');
      return -1;
    }
  }

  /// Henüz sync edilmemiş bilinmeyen barkodları getir
  Future<List<Map<String, dynamic>>> getUnsyncedUnknownBarcodes() async {
    final db = await database;

    try {
      final results = await db.query(
        'unknown_barcodes',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'scanned_at ASC',
      );

      debugPrint('📋 ${results.length} adet sync edilmemiş bilinmeyen barkod bulundu');
      return results;
    } catch (e) {
      debugPrint('❌ Sync edilmemiş barkodları getirme hatası: $e');
      return [];
    }
  }

  /// Başarıyla sync edilen barkodları sil
  Future<int> deleteUnknownBarcodes(List<int> ids) async {
    if (ids.isEmpty) return 0;

    final db = await database;

    try {
      final placeholders = List.filled(ids.length, '?').join(',');
      final deletedCount = await db.delete(
        'unknown_barcodes',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );

      debugPrint('🗑️  $deletedCount adet bilinmeyen barkod silindi');
      return deletedCount;
    } catch (e) {
      debugPrint('❌ Bilinmeyen barkodları silme hatası: $e');
      return 0;
    }
  }

  /// Bilinmeyen barkodları sync edildi olarak işaretle (opsiyonel - silmek yerine)
  Future<int> markUnknownBarcodesAsSynced(List<int> ids) async {
    if (ids.isEmpty) return 0;

    final db = await database;

    try {
      final placeholders = List.filled(ids.length, '?').join(',');
      final updatedCount = await db.update(
        'unknown_barcodes',
        {'synced': 1},
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );

      debugPrint('✅ $updatedCount adet bilinmeyen barkod sync edildi olarak işaretlendi');
      return updatedCount;
    } catch (e) {
      debugPrint('❌ Bilinmeyen barkodları işaretleme hatası: $e');
      return 0;
    }
  }

  // ==================== END UNKNOWN BARCODES METHODS ====================

  /// Farklı depo kullanıcısı giriş yaptığında warehouse'a özel verileri temizler
  /// Global veriler (ürünler, tedarikçiler, birimler, barkodlar) korunur
  /// EMPLOYEES tablosu offline login için gerekli olduğundan korunur
  Future<void> clearWarehouseSpecificData() async {
    final db = await database;
    debugPrint("🧹 Warehouse'a özel veriler temizleniyor...");

    await db.transaction((txn) async {
      final batch = txn.batch();
      
      // Warehouse'a özel tabloları temizle (dependency order'da)
      // wms_putaway_status tablosu kaldırıldı
      // KRITIK: goods_receipts ve goods_receipt_items WMS tarihçesi için KORUNUYOR - Sadece warehouse switch'te temizleniyor
      batch.delete('goods_receipt_items');          // goods_receipts'e bağlı (tarihçe için korunuyor, sadece warehouse switch'te sil)
      batch.delete('inventory_transfers');          // location'lara bağlı
      batch.delete('inventory_stock');              // location'lara bağlı
      batch.delete('goods_receipts');               // warehouse'a bağlı (tarihçe için korunuyor, sadece warehouse switch'te sil)
      batch.delete('siparis_ayrintili');            // siparisler'e bağlı
      batch.delete('siparisler');                   // warehouse'a bağlı
      batch.delete('shelfs');                       // warehouse'a bağlı
      // EMPLOYEES tablosunu SİLME - offline login için gerekli!
      // batch.delete('employees');                 // COMMENTED OUT - offline login için gerekli
      batch.delete('pending_operation');            // Bekleyen işlemler de temizle
      batch.delete('sync_log');                     // Sync logları da temizle
      
      await batch.commit(noResult: true);
    });

    debugPrint("✅ Warehouse'a özel veriler temizlendi. Employees tablosu offline login için korundu. Global veriler (ürünler, tedarikçiler, birimler, barkodlar) korundu.");
  }

  Future<void> resetDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }

    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    try {
      await deleteDatabase(path);
      debugPrint("✅ Local database file deleted successfully at path: $path");
    } catch (e) {
      debugPrint("❌ Error deleting local database file: $e");
    }

    _database = null;
  }
  
  /// KRITIK FIX: Mevcut inventory_stock kayıtlarındaki NULL birim_key değerlerini 
  /// goods_receipt_items tablosundan alarak günceller
  
  /// Çoklu cihaz senaryosu için bir server kaydının bu cihazın kendi operasyonu olup olmadığını kontrol eder
  /// GÜNCEL YAKLAŞIM: Employee ID karşılaştırması yaparak kendi operasyonumuzu tespit eder
  Future<bool> isOwnOperation(DatabaseExecutor db, String type, Map<String, dynamic> serverRecord) async {
    try {
      debugPrint('🔍 isOwnOperation başlatıldı: type=$type');
      
      // Mevcut kullanıcının employee_id'sini al
      final prefs = await SharedPreferences.getInstance();
      final currentEmployeeId = prefs.getInt('employee_id');
      
      if (currentEmployeeId == null) {
        debugPrint('❌ isOwnOperation: Current employee_id bulunamadı SharedPreferences\'ta');
        return false;
      }
      
      // Server record'daki employee_id'yi kontrol et
      final serverEmployeeId = serverRecord['employee_id'] as int?;
      
      if (serverEmployeeId == null) {
        debugPrint('❌ isOwnOperation: Server record\'da employee_id yok');
        return false;
      }
      
      // Employee ID eşleşmesi kontrolü
      final isOwn = currentEmployeeId == serverEmployeeId;
      
      debugPrint('🔍 isOwnOperation Kontrolü:');
      debugPrint('   - Operasyon Tipi: $type');
      debugPrint('   - Current Employee ID: $currentEmployeeId');
      debugPrint('   - Server Employee ID: $serverEmployeeId');
      debugPrint('   - Sonuç: ${isOwn ? "✅ KENDİ OPERASYONUM - Skip edilecek" : "❌ BAŞKA CİHAZIN OPERASYONU - İşlenecek"}');
      
      // Ek debug bilgisi
      if (type == 'goodsReceipt' && serverRecord.containsKey('siparis_id')) {
        debugPrint('   - Sipariş ID: ${serverRecord['siparis_id']}');
        debugPrint('   - Receipt Date: ${serverRecord['receipt_date']}');
      }
      
      return isOwn;
    } catch (e, stackTrace) {
      debugPrint('❌ isOwnOperation kritik hatası: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// UTC ISO 8601 formatına normalize eder
  // String _normalizeToUtcIso(String dateStr) {
  //   try {
  //     final dt = DateTime.parse(dateStr.replaceAll(' ', 'T'));
  //     return dt.toUtc().toIso8601String();
  //   } catch (e) {
  //     debugPrint('⚠️ Tarih normalize hatası: $e, original: $dateStr');
  //     return dateStr; // Hata varsa orijinal string döndür
  //   }
  // }
  
  // REMOVED: ID update functions no longer needed with UUID-based system
  // Mobile uses only UUIDs for relationships, server IDs are not synchronized back to mobile

  // ==================== LOG ENTRIES ====================

  /// Stores a log entry in the database
  Future<int> saveLogEntry({
    required String level,
    required String title,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? context,
    Map<String, dynamic>? deviceInfo,
    int? employeeId,
    String? employeeName,
  }) async {
    final db = await database;
    return await db.insert('log_entries', {
      'level': level,
      'title': title,
      'message': message,
      'stack_trace': stackTrace,
      'context': context != null ? jsonEncode(context) : null,
      'device_info': deviceInfo != null ? jsonEncode(deviceInfo) : null,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Gets all log entries within a time range
  Future<List<Map<String, dynamic>>> getLogEntries({
    DateTime? since,
    String? level,
    int? limit,
  }) async {
    final db = await database;

    String where = '';
    List<dynamic> whereArgs = [];

    if (since != null) {
      where = 'created_at >= ?';
      whereArgs.add(since.toIso8601String());
    }

    if (level != null) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'level = ?';
      whereArgs.add(level);
    }

    return await db.query(
      'log_entries',
      where: where.isNotEmpty ? where : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Deletes old log entries
  Future<int> cleanOldLogs({int days = 7}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    return await db.delete(
      'log_entries',
      where: 'created_at < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }

  /// Gets log count
  Future<int> getLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM log_entries');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Deletes all logs
  Future<int> deleteAllLogs() async {
    final db = await database;
    return await db.delete('log_entries');
  }
}

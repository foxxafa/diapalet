// lib/core/local/database_helper.dart
import 'dart:io';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:diapalet/core/local/database_constants.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert'; // Added for jsonDecode
import 'package:shared_preferences/shared_preferences.dart'; // Added for SharedPreferences

class DatabaseHelper {
  static const _databaseName = "Diapallet_v2.db";
  static const _databaseVersion = 56;
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

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Veritabanı $oldVersion sürümünden $newVersion sürümüne yükseltiliyor...");
    await _dropAllTables(db);
    await _createAllTables(db);
    debugPrint("Veritabanı yükseltmesi tamamlandı.");
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
          is_active INTEGER DEFAULT 1,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS urunler (
          UrunId INTEGER PRIMARY KEY,
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
          carpan REAL,
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
          user INTEGER,
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
          notlar TEXT,
          user TEXT,
          created_at TEXT,
          updated_at TEXT,
          _key_sis_depo_source TEXT,
          __carikodu TEXT,
          status INTEGER DEFAULT 0,
          fisno TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS siparis_ayrintili (
          id INTEGER PRIMARY KEY,
          siparisler_id INTEGER,
          urun_id INTEGER,
          kartkodu TEXT,
          anamiktar REAL,
          miktar REAL,
          anabirimi TEXT,
          created_at TEXT,
          updated_at TEXT,
          status INTEGER,
          turu TEXT
        )
      ''');

      // wms_putaway_status tablosu dump.sql'e göre
      batch.execute('''
        CREATE TABLE IF NOT EXISTS wms_putaway_status (
          id INTEGER PRIMARY KEY,
          purchase_order_line_id INTEGER UNIQUE,
          putaway_quantity REAL DEFAULT 0.00,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS goods_receipts (
          goods_receipt_id INTEGER PRIMARY KEY,
          warehouse_id INTEGER,
          siparis_id INTEGER,
          invoice_number TEXT,
          delivery_note_number TEXT,
          employee_id INTEGER,
          receipt_date TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS goods_receipt_items (
          id INTEGER PRIMARY KEY,
          receipt_id INTEGER,
          urun_id INTEGER,
          quantity_received REAL,
          pallet_barcode TEXT,
          expiry_date TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(receipt_id) REFERENCES goods_receipts(goods_receipt_id),
          FOREIGN KEY(urun_id) REFERENCES urunler(UrunId)
        )
      ''');

      // Inventory stock table with receiving/available status support
      batch.execute('''
        CREATE TABLE IF NOT EXISTS inventory_stock (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          urun_id INTEGER NOT NULL,
          location_id INTEGER,
          siparis_id INTEGER,
          goods_receipt_id INTEGER,
          quantity REAL NOT NULL,
          pallet_barcode TEXT,
          expiry_date TEXT,
          stock_status TEXT NOT NULL CHECK(stock_status IN ('receiving', 'available')),
          created_at TEXT,
          updated_at TEXT,
          UNIQUE(urun_id, location_id, pallet_barcode, stock_status, siparis_id, expiry_date, goods_receipt_id),
          FOREIGN KEY(urun_id) REFERENCES urunler(UrunId),
          FOREIGN KEY(location_id) REFERENCES shelfs(id),
          FOREIGN KEY(siparis_id) REFERENCES siparisler(id),
          FOREIGN KEY(goods_receipt_id) REFERENCES goods_receipts(goods_receipt_id)
        )
      ''');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_location ON inventory_stock(location_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_status ON inventory_stock(stock_status)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_siparis ON inventory_stock(siparis_id)');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_shelfs_warehouse ON shelfs(warehouse_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_shelfs_code ON shelfs(code)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_order_lines_siparis ON siparis_ayrintili(siparisler_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_order_lines_urun ON siparis_ayrintili(urun_id)');
      
      batch.execute('''
        CREATE TABLE IF NOT EXISTS inventory_transfers (
          id INTEGER PRIMARY KEY,
          urun_id INTEGER,
          from_location_id INTEGER,
          to_location_id INTEGER,
          quantity REAL,
          from_pallet_barcode TEXT,
          pallet_barcode TEXT,
          siparis_id INTEGER,
          goods_receipt_id INTEGER,
          delivery_note_number TEXT,
          employee_id INTEGER,
          transfer_date TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(urun_id) REFERENCES urunler(UrunId),
          FOREIGN KEY(from_location_id) REFERENCES shelfs(id),
          FOREIGN KEY(to_location_id) REFERENCES shelfs(id),
          FOREIGN KEY(employee_id) REFERENCES employees(id)
        )
      ''');

      // Performance indexes - created after all tables
      batch.execute('CREATE INDEX IF NOT EXISTS idx_goods_receipts_date ON goods_receipts(receipt_date)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_pending_operation_status ON pending_operation(status)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_transfers_date ON inventory_transfers(transfer_date)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_goods_receipts_siparis ON goods_receipts(siparis_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_employees_warehouse ON employees(warehouse_code)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_urunler_stokkodu ON urunler(StokKodu)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_birimler_key ON birimler(_key)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_birimler_stokkodu ON birimler(StokKodu)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_barkodlar_barkod ON barkodlar(barkod)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_barkodlar_key_birimler ON barkodlar(_key_scf_stokkart_birimleri)');

      await batch.commit(noResult: true);
    });

    debugPrint("Tüm tablolar başarıyla oluşturuldu.");
  }

  Future<void> _dropAllTables(Database db) async {
    const tables = [
      'pending_operation', 'sync_log', 'shelfs', 'employees', 'urunler',
      'siparisler', 'siparis_ayrintili', 'goods_receipts',
      'goods_receipt_items', 'inventory_stock', 'inventory_transfers',
      'wms_putaway_status', 'tedarikci', 'birimler', 'barkodlar'
    ];
    await db.transaction((txn) async {
      for (final table in tables) {
        await txn.execute('DROP TABLE IF EXISTS $table');
      }
    });
    debugPrint("Yükseltme için tüm eski tablolar silindi.");
  }

  Future<void> applyDownloadedData(
    Map<String, dynamic> data, {
    void Function(String tableName, int processed, int total)? onTableProgress
  }) async {
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
            final urunId = urun['id'];
            final aktif = urun['aktif'];

            if (aktif == 0) {
              // Silinmiş ürün: local'den sil
              batch.delete(DbTables.products, where: 'id = ?', whereArgs: [urunId]);
            } else {
              // Aktif ürün: güncelle veya ekle
              final sanitizedRecord = _sanitizeRecord('urunler', urun);
              batch.insert(DbTables.products, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
            }

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

        // Goods receipts incremental sync
        if (data.containsKey('goods_receipts')) {
          final goodsReceiptsData = List<Map<String, dynamic>>.from(data['goods_receipts']);
          for (final receipt in goodsReceiptsData) {
            final sanitizedRecord = _sanitizeRecord('goods_receipts', receipt);
            batch.insert('goods_receipts', sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('goods_receipts');
          }
        }

        // Goods receipt items incremental sync
        if (data.containsKey('goods_receipt_items')) {
          final goodsReceiptItemsData = List<Map<String, dynamic>>.from(data['goods_receipt_items']);
          for (final item in goodsReceiptItemsData) {
            final sanitizedItem = _sanitizeRecord('goods_receipt_items', item);
            batch.insert('goods_receipt_items', sanitizedItem, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('goods_receipt_items');
          }
        }

        // WMS putaway status incremental sync
        if (data.containsKey('wms_putaway_status')) {
          final putawayStatusData = List<Map<String, dynamic>>.from(data['wms_putaway_status']);
          for (final putaway in putawayStatusData) {
            final sanitizedPutaway = _sanitizeRecord('wms_putaway_status', putaway);
            batch.insert('wms_putaway_status', sanitizedPutaway, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('wms_putaway_status');
          }
        }

        // Inventory stock incremental sync
        if (data.containsKey('inventory_stock')) {
          final inventoryStockData = List<Map<String, dynamic>>.from(data['inventory_stock']);
          for (final stock in inventoryStockData) {
            final sanitizedStock = _sanitizeRecord('inventory_stock', stock);
            batch.insert('inventory_stock', sanitizedStock, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('inventory_stock');
          }
        }

        // Inventory transfers incremental sync
        if (data.containsKey('inventory_transfers')) {
          final inventoryTransfersData = List<Map<String, dynamic>>.from(data['inventory_transfers']);
          for (final transfer in inventoryTransfersData) {
            final sanitizedTransfer = _sanitizeRecord('inventory_transfers', transfer);
            batch.insert('inventory_transfers', sanitizedTransfer, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('inventory_transfers');
          }
        }

        // Orders incremental sync
        if (data.containsKey('siparisler')) {
          final siparislerData = List<Map<String, dynamic>>.from(data['siparisler']);
          for (final siparis in siparislerData) {
            final sanitizedSiparis = _sanitizeRecord('siparisler', siparis);
            batch.insert(DbTables.orders, sanitizedSiparis, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('siparisler');
          }
        }

        // Order lines incremental sync
        if (data.containsKey('siparis_ayrintili')) {
          final satirlarData = List<Map<String, dynamic>>.from(data['siparis_ayrintili']);
          for (final satir in satirlarData) {
            // Sadece turu = '1' olanları kabul et
            if (satir['turu'] == '1' || satir['turu'] == 1) {
              final sanitizedSatir = _sanitizeRecord('siparis_ayrintili', satir);
              
              // Derive urun_id from kartkodu if needed
              if (sanitizedSatir.containsKey('kartkodu') && sanitizedSatir['kartkodu'] != null) {
                final kartkodu = sanitizedSatir['kartkodu'];
                final urunQuery = await txn.query(
                  'urunler', 
                  columns: ['UrunId'], 
                  where: 'StokKodu = ?', 
                  whereArgs: [kartkodu],
                  limit: 1
                );
                if (urunQuery.isNotEmpty) {
                  sanitizedSatir['urun_id'] = urunQuery.first['UrunId'];
                }
              }
              
              batch.insert(DbTables.orderLines, sanitizedSatir, conflictAlgorithm: ConflictAlgorithm.replace);

              processedItems++;
              updateProgress('siparis_ayrintili');
            }
          }
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

        // Diğer tablolar için eski mantık (full replacement)
        // Silme sırası önemli: önce child tablolar, sonra parent tablolar
        const deletionOrder = [
          // 'siparis_ayrintili', 'siparisler' artık incremental olarak işleniyor
          // 'urunler', 'shelfs', 'employees', 'goods_receipts', 'goods_receipt_items', 'wms_putaway_status', 'inventory_stock' burada yok çünkü yukarıda incremental olarak işlendi
        ];

        // Tablolari belirtilen sirada sil (incremental tablolar hariç)
        for (final table in deletionOrder) {
          if (data.containsKey(table)) {
            await txn.delete(table);
          }
        }

        // Sonra verileri ekle (incremental tablolar hariç, onlar zaten yukarıda işlendi)
        final incrementalTables = ['urunler', 'shelfs', 'employees', 'goods_receipts', 'goods_receipt_items', 'wms_putaway_status', 'inventory_stock', 'inventory_transfers', 'siparisler', 'siparis_ayrintili', 'tedarikci', 'birimler', 'barkodlar'];
        final skippedTables = ['warehouses']; // Kaldırılan tablolar

        for (var table in data.keys) {
          if (incrementalTables.contains(table)) continue; // Zaten yukarıda işlendi
          if (skippedTables.contains(table)) continue; // Kaldırılan tablolar
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
        // End of incremental sync

        await batch.commit(noResult: true);
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
        // Server uses 'id', local uses 'UrunId'
        if (newRecord.containsKey('id')) {
          newRecord['UrunId'] = newRecord['id'];
          newRecord.remove('id');
        }
        break;

      case 'goods_receipts':
        // Server uses 'id', local uses 'goods_receipt_id'
        if (newRecord.containsKey('id') && newRecord['id'] != null) {
          newRecord['goods_receipt_id'] = newRecord['id'];
          newRecord.remove('id');
        }
        break;
        
      case 'siparisler':
        // Map server fields to local schema - only keep fields that exist in local table
        final localRecord = <String, dynamic>{};
        
        // Local table columns based on optimized CREATE TABLE statement
        final localColumns = [
          'id', 'tarih', 'notlar', 'user', 'created_at', 'updated_at', 
          '_key_sis_depo_source', '__carikodu', 
          'status', 'fisno'
        ];
        
        // Copy only existing local columns
        for (String column in localColumns) {
          if (newRecord.containsKey(column)) {
            localRecord[column] = newRecord[column];
          }
        }
        
        // Map specific server fields to local fields
        if (newRecord.containsKey('_user')) {
          localRecord['user'] = newRecord['_user'];
        }
        
        return localRecord;

      case 'siparis_ayrintili':
        // Only keep fields that exist in optimized local schema
        final localRecord = <String, dynamic>{};
        final localColumns = [
          'id', 'siparisler_id', 'kartkodu', 'anamiktar', 'miktar',
          'anabirimi', 'created_at', 'updated_at', 'status', 'turu'
        ];
        
        for (String column in localColumns) {
          if (newRecord.containsKey(column)) {
            localRecord[column] = newRecord[column];
          }
        }
        
        // Derive urun_id from kartkodu using urunler table
        if (localRecord.containsKey('kartkodu') && localRecord['kartkodu'] != null) {
          // This will be handled by a separate lookup during data processing
          localRecord['urun_id'] = null; // Will be filled later
        }
        
        return localRecord;
    }

    // SQLite will automatically ignore unknown columns during INSERT
    // No need to manually remove every field that doesn't exist in local schema
    return newRecord;
  }

  // --- YARDIMCI FONKSİYONLAR ---

  /// Barkod ile ürün arama - Yeni barkodlar tablosunu kullanır
  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final db = await database;
    
    // Önce barkodlar tablosunda barkodu ara
    final barkodResult = await db.query(
      'barkodlar',
      where: 'barkod = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (barkodResult.isEmpty) return null;

    // Barkod bulundu, ilgili birim bilgisini al
    final barkodInfo = barkodResult.first;
    final birimKey = barkodInfo['_key_scf_stokkart_birimleri'] as String?;
    
    if (birimKey == null) return null;

    // Birim bilgisi ile ürün bilgisini getir
    final birimResult = await db.query(
      'birimler',
      where: '_key = ?',
      whereArgs: [birimKey],
      limit: 1,
    );

    if (birimResult.isEmpty) return null;

    final birimInfo = birimResult.first;
    final stokKodu = birimInfo['StokKodu'] as String?;
    
    if (stokKodu == null) return null;

    // StokKodu ile ürün bilgisini getir
    final urunResult = await db.query(
      'urunler',
      where: 'StokKodu = ?',
      whereArgs: [stokKodu],
      limit: 1,
    );

    if (urunResult.isEmpty) return null;

    final urunInfo = Map<String, dynamic>.from(urunResult.first);
    // Birim bilgilerini de ekle
    urunInfo['birim_info'] = birimInfo;
    urunInfo['barkod_info'] = barkodInfo;
    
    return urunInfo;
  }

  /// Barkod ile ürün arama (LIKE) - Yeni barkodlar tablosunu kullanır  
  Future<List<Map<String, dynamic>>> searchProductsByBarcode(String query) async {
    final db = await database;
    
    const sql = '''
      SELECT DISTINCT 
        u.*,
        b.birimadi,
        b.birimkod,
        b.carpan,
        b._key as birim_key,
        bark.barkod,
        bark._key as barkod_key
      FROM barkodlar bark
      JOIN birimler b ON bark._key_scf_stokkart_birimleri = b._key
      JOIN urunler u ON b.StokKodu = u.StokKodu
      WHERE bark.barkod LIKE ? 
        AND u.aktif = 1
      ORDER BY u.UrunAdi ASC
    ''';

    return await db.rawQuery(sql, ['%$query%']);
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



  Future<Map<String, dynamic>?> getProductById(int productId) async {
    final db = await database;
    final result = await db.query(
      'urunler',
      where: 'UrunId = ?',
      whereArgs: [productId],
      limit: 1,
    );
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
        sa.urun_id,
        sa.anamiktar as ordered_quantity,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        COALESCE(received.total_received, 0) as received_quantity,
        COALESCE(putaway.putaway_quantity, 0) as putaway_quantity
      FROM siparis_ayrintili sa
      LEFT JOIN urunler u ON u.UrunId = sa.urun_id
      LEFT JOIN (
        SELECT
          gri.urun_id,
          SUM(gri.quantity_received) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE gr.siparis_id = ?
        GROUP BY gri.urun_id
      ) received ON received.urun_id = sa.urun_id
      LEFT JOIN wms_putaway_status putaway ON putaway.purchase_order_line_id = sa.id
      WHERE sa.siparisler_id = ? AND sa.turu = '1'
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

    const sql = '''
      SELECT
        gri.id,
        gri.urun_id,
        gri.quantity_received as current_received,
        gri.pallet_barcode,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        sa.anamiktar as ordered_quantity,
        sa.anabirimi as unit,
        COALESCE(previous.previous_received, 0) as previous_received,
        COALESCE(previous.previous_received, 0) + gri.quantity_received as total_received
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u.UrunId = gri.urun_id
      LEFT JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      LEFT JOIN siparis_ayrintili sa ON sa.siparisler_id = gr.siparis_id AND sa.urun_id = gri.urun_id
      LEFT JOIN (
        SELECT
          gri2.urun_id,
          SUM(gri2.quantity_received) as previous_received
        FROM goods_receipt_items gri2
        JOIN goods_receipts gr2 ON gr2.goods_receipt_id = gri2.receipt_id
        WHERE gr2.siparis_id = ?
          AND gr2.goods_receipt_id < ?
        GROUP BY gri2.urun_id
      ) previous ON previous.urun_id = gri.urun_id
      WHERE gri.receipt_id = ?
      ORDER BY gri.id
    ''';

    return await db.rawQuery(sql, [siparisId, receiptId, receiptId]);
  }

  Future<List<Map<String, dynamic>>> getReceiptItemsWithDetails(int receiptId) async {
    final db = await database;

    const sql = '''
      SELECT
        gri.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u.UrunId = gri.urun_id
      WHERE gri.receipt_id = ?
      ORDER BY gri.id
    ''';

    return await db.rawQuery(sql, [receiptId]);
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
      LEFT JOIN urunler u ON u.UrunId = it.urun_id
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

    const sql = '''
      SELECT
        ints.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        loc.name as location_name,
        loc.code as location_code
      FROM inventory_stock ints
      LEFT JOIN urunler u ON u.UrunId = ints.urun_id
      LEFT JOIN shelfs loc ON loc.id = ints.location_id
      WHERE ints.siparis_id = ? AND ints.stock_status = 'receiving'
      ORDER BY ints.urun_id
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
        po.notlar as order_notes,
        po.status as order_status,
        po.warehouse_code as order_warehouse_code
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

    const sql = '''
      SELECT
        gri.*,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        u.Birim1 as product_unit,
        u.qty as product_box_qty,
        sa.anamiktar as ordered_quantity,
        sa.anabirimi as order_unit,
        sa.notes as order_line_notes,
        COALESCE(putaway.putaway_quantity, 0) as putaway_quantity
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u.UrunId = gri.urun_id
      LEFT JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      LEFT JOIN siparis_ayrintili sa ON sa.siparisler_id = gr.siparis_id AND sa.urun_id = gri.urun_id
      LEFT JOIN wms_putaway_status putaway ON putaway.purchase_order_line_id = sa.id
      WHERE gri.receipt_id = ?
      ORDER BY gri.id
    ''';

    return await db.rawQuery(sql, [receiptId]);
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
      Map<String, dynamic> warehouseInfo = {
        'name': prefs.getString('warehouse_name') ?? 'N/A',
        'warehouse_code': prefs.getString('warehouse_code') ?? 'N/A',
        'branch_name': prefs.getString('branch_name') ?? 'N/A',
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
        final productId = item['product_id'] ?? item['urun_id'];
        if (productId != null) {
          final product = await getProductById(productId);
          if (product != null) {
            enrichedItem['product_name'] = product['UrunAdi'];
            enrichedItem['product_code'] = product['StokKodu'];
            
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
      Map<String, dynamic> warehouseInfo = {
        'name': prefs.getString('warehouse_name') ?? 'N/A',
        'warehouse_code': prefs.getString('warehouse_code') ?? 'N/A',
        'branch_name': prefs.getString('branch_name') ?? 'N/A',
        'receiving_mode': prefs.getInt('receiving_mode') ?? 2, // Default: mixed
      };

      // Warehouse bilgileri SharedPreferences'tan alındı

      header['warehouse_info'] = warehouseInfo;

      final enrichedItems = <Map<String, dynamic>>[];
      final siparisId = header['siparis_id'];

      for (final item in items) {
        final mutableItem = Map<String, dynamic>.from(item);
        final productId = item['urun_id'];

        if (productId != null) {
          final product = await getProductById(productId);
          if (product != null) {
            mutableItem['product_name'] = product['UrunAdi'];
            mutableItem['product_code'] = product['StokKodu'];
            
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
            
            mutableItem['product_barcode'] = productBarcode;
          }
        }

        if (siparisId != null && productId != null) {
          final currentReceivedInThisOp = (item['quantity'] as num?)?.toDouble() ?? 0;

          if (actualReceiptDate != null) {
            int? currentReceiptId;
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
                  'SELECT receipt_id FROM goods_receipts WHERE siparis_id = ? AND receipt_date = ?',
                  [siparisId, receiptDateStr]
              );
              if (currentReceiptQuery.isNotEmpty) {
                currentReceiptId = currentReceiptQuery.first['receipt_id'] as int?;
                debugPrint('DEBUG - Found current receipt ID to exclude: $currentReceiptId for date: $receiptDateStr');
              } else {
                final likeQuery = await db.rawQuery(
                    'SELECT receipt_id FROM goods_receipts WHERE siparis_id = ? AND receipt_date LIKE ?',
                    [siparisId, '$receiptDateStr%']
                );
                if (likeQuery.isNotEmpty) {
                  currentReceiptId = likeQuery.first['receipt_id'] as int?;
                  debugPrint('DEBUG - Found current receipt ID via LIKE: $currentReceiptId for date pattern: $receiptDateStr%');
                } else {
                  debugPrint('DEBUG - No receipt found to exclude for date: $receiptDateStr (tried exact and LIKE)');
                }
              }
            } catch (e) {
              debugPrint('Error finding current receipt ID: $e');
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

        enrichedItems.add(mutableItem);
      }

      if (siparisId != null) {
        final orderSummary = await getOrderSummary(siparisId);
        if (orderSummary != null) {
          header['order_info'] = orderSummary['order'];
          final orderLines = orderSummary['lines'] as List<dynamic>;

          final orderLinesMap = {for (var line in orderLines) line['urun_id']: line};

          for (final item in enrichedItems) {
            final orderLine = orderLinesMap[item['urun_id']];
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

  Future<double> _getPreviousReceivedQuantity(int siparisId, int productId, {DateTime? beforeDate, int? excludeReceiptId}) async {
    final db = await database;

    String sql;
    List<dynamic> params;

    if (beforeDate != null || excludeReceiptId != null) {
      List<String> conditions = ['gr.siparis_id = ?', 'gri.urun_id = ?'];
      params = [siparisId, productId];

      if (beforeDate != null) {
        conditions.add('gr.receipt_date < ?');
        params.add(beforeDate.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' '));
      }

      if (excludeReceiptId != null) {
        conditions.add('gr.goods_receipt_id != ?');
        params.add(excludeReceiptId);
      }

      sql = '''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE ${conditions.join(' AND ')}
      ''';

      final debugSql = '''
        SELECT gr.receipt_date, gri.quantity_received, gr.goods_receipt_id as receipt_id
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE ${conditions.join(' AND ')}
        ORDER BY gr.receipt_date
      ''';
      final debugResult = await db.rawQuery(debugSql, params);
      debugPrint('DEBUG - Receipts being counted: $debugResult');

      const allReceiptsSql = '''
        SELECT gr.receipt_date, gri.quantity_received, gr.goods_receipt_id as receipt_id, 'ALL' as note
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE gr.siparis_id = ? AND gri.urun_id = ?
        ORDER BY gr.receipt_date
      ''';
      final allReceipts = await db.rawQuery(allReceiptsSql, [siparisId, productId]);
      debugPrint('DEBUG - ALL receipts for order $siparisId, product $productId: $allReceipts');
    } else {
      sql = '''
        SELECT COALESCE(SUM(gri.quantity_received), 0) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE gr.siparis_id = ? AND gri.urun_id = ?
      ''';
      params = [siparisId, productId];
    }

    final result = await db.rawQuery(sql, params);
    final totalReceived = (result.first['total_received'] as num?)?.toDouble() ?? 0.0;

    debugPrint('_getPreviousReceivedQuantity: siparisId=$siparisId, productId=$productId, beforeDate=${beforeDate?.toString() ?? 'null'}, excludeReceiptId=${excludeReceiptId?.toString() ?? 'null'}, result=$totalReceived');

    return totalReceived;
  }

  Future<bool> hasForceCloseOperationForOrder(int siparisId, DateTime? afterDate) async {
    final db = await database;

    if (afterDate == null) {
      debugPrint('hasForceCloseOperationForOrder: afterDate null, false döndürülüyor');
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
              SELECT receipt_date, id
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

    const sql = '''
      SELECT DISTINCT
        gr.goods_receipt_id,
        gr.delivery_note_number,
        gr.receipt_date,
        gr.employee_id,
        e.first_name || ' ' || e.last_name as employee_name,
        COUNT(DISTINCT ist.urun_id) as item_count,
        SUM(ist.quantity) as total_quantity
      FROM goods_receipts gr
      LEFT JOIN employees e ON e.id = gr.employee_id
      LEFT JOIN inventory_stock ist ON ist.goods_receipt_id = gr.goods_receipt_id AND ist.stock_status = 'receiving'
      WHERE gr.siparis_id IS NULL
        AND ist.id IS NOT NULL
      GROUP BY gr.goods_receipt_id, gr.delivery_note_number, gr.receipt_date, gr.employee_id, e.first_name, e.last_name
      ORDER BY gr.receipt_date DESC
    ''';

    return await db.rawQuery(sql);
  }

  Future<List<Map<String, dynamic>>> getStockItemsForFreeReceipt(String deliveryNoteNumber) async {
    final db = await database;

    const sql = '''
      SELECT
        ist.id,
        ist.urun_id,
        ist.quantity,
        ist.pallet_barcode,
        ist.expiry_date,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
      FROM inventory_stock ist
      LEFT JOIN urunler u ON u.UrunId = ist.urun_id
      LEFT JOIN goods_receipts gr ON gr.goods_receipt_id = ist.goods_receipt_id
      WHERE gr.delivery_note_number = ?
        AND ist.stock_status = 'receiving'
        AND gr.siparis_id IS NULL
      ORDER BY ist.urun_id, ist.expiry_date
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

    return enrichedMaps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<List<PendingOperation>> getSyncedOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation',
        where: "status = ?",
        whereArgs: ['synced'],
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
        'synced_at': DateTime.now().toIso8601String()
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

  /// Veritabanı boyutunu küçültmek için eski verileri temizler
  /// Status 2,3 olan siparişleri ve eski transfer kayıtlarını siler
  Future<void> cleanupOldData({int days = 7}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));

    await db.transaction((txn) async {
      // 1. Eski inventory_transfers kayıtlarını sil
      final transferCount = await txn.delete(
        'inventory_transfers',
        where: 'created_at < ?',
        whereArgs: [cutoffDate.toIso8601String()]
      );

      // 2. Status 2,3 olan eski siparişleri ve bağlı kayıtları sil
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

        // 1. goods_receipt_items (en child tablo)
        final receiptItems = await txn.delete(
          'goods_receipt_items',
          where: 'receipt_id IN (SELECT goods_receipt_id FROM goods_receipts WHERE siparis_id = ?)',
          whereArgs: [orderId]
        );
        receiptItemCount += receiptItems;

        // 2. goods_receipts (parent tablo)
        final receipts = await txn.delete(
          'goods_receipts',
          where: 'siparis_id = ?',
          whereArgs: [orderId]
        );
        receiptCount += receipts;

        // 3. wms_putaway_status (sipariş satırına bağlı)
        final putaways = await txn.delete(
          'wms_putaway_status',
          where: 'purchase_order_line_id IN (SELECT id FROM siparis_ayrintili WHERE siparisler_id = ?)',
          whereArgs: [orderId]
        );
        putawayCount += putaways;

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
  Future<void> performMaintenanceCleanup({int days = 7}) async {
    debugPrint("🧹 Veritabanı bakımı başlatılıyor...");

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
      'timestamp': DateTime.now().toIso8601String(),
      'type': type, 'status': status, 'message': message,
    });
  }

  Future<List<SyncLog>> getSyncLogs() async {
    final db = await database;
    final maps = await db.query('sync_log', orderBy: 'timestamp DESC', limit: 100);
    return maps.map((map) => SyncLog.fromMap(map)).toList();
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
}

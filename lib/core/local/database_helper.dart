// lib/core/local/database_helper.dart
import 'dart:io';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert'; // Added for jsonDecode
import 'package:shared_preferences/shared_preferences.dart'; // Added for SharedPreferences

class DatabaseHelper {
  static const _databaseName = "Diapallet_v2.db";
      // ANA GÜNCELLEME: dia_key kolonu eklendi shelfs tablosuna.
      // GÜNCELLEME: goods_receipts tablosundaki 'id' alanı 'goods_receipt_id' olarak değiştirildi.
      // GÜNCELLEME: Veritabanı sürümü artırıldı ve sanitize fonksiyonu düzeltildi.
      // GÜNCELLEME: satin_alma_siparis_fis tablosunda branch_id -> warehouse_code değişikliği
      // GÜNCELLEME: İnkremental sync için updated_at sütunları eklendi (shelfs, goods_receipts, goods_receipt_items)
      // GÜNCELLEME: İnkremental sync inventory_stock ve wms_putaway_status tablolarına da eklendi
      // GÜNCELLEME: inventory_stock tablosuna created_at alanı, inventory_transfers tablosuna updated_at alanı eklendi
      // GÜNCELLEME: inventory_transfers için incremental sync eklendi
      // GÜNCELLEME: urunler tablosuna created_at ve updated_at alanları eklendi (incremental sync için)
      static const _databaseVersion = 41;
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

      // Warehouse tablosu kaldırıldı - SharedPreferences kullanılıyor

      batch.execute('''
        CREATE TABLE IF NOT EXISTS shelfs (
          id INTEGER PRIMARY KEY,
          warehouse_id INTEGER,
          name TEXT,
          code TEXT,
          dia_key TEXT,
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
          warehouse_id INTEGER,
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
          Barcode1 TEXT,
          aktif INTEGER,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS satin_alma_siparis_fis (
          id INTEGER PRIMARY KEY,
          tarih TEXT,
          notlar TEXT,
          user TEXT,
          created_at TEXT,
          updated_at TEXT,
          gun INTEGER DEFAULT 0,
          warehouse_code TEXT,
          invoice TEXT,
          delivery INTEGER,
          po_id TEXT,
          status INTEGER DEFAULT 0
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS satin_alma_siparis_fis_satir (
          id INTEGER PRIMARY KEY,
          siparis_id INTEGER,
          urun_id INTEGER,
          StokKodu TEXT,
          miktar REAL,
          ort_son_30 INTEGER,
          ort_son_60 INTEGER,
          ort_son_90 INTEGER,
          tedarikci_id INTEGER,
          tedarikci_fis_id INTEGER,
          invoice TEXT,
          birim TEXT,
          layer INTEGER,
          notes TEXT,
          created_at TEXT,
          updated_at TEXT,
          status INTEGER,
          good_received REAL,
          son_7_gun REAL,
          son_14_gun REAL,
          son_21_gun REAL,
          son_1_ay REAL,
          son_2_ay REAL,
          son_3_ay REAL
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

      // ANA GÜNCELLEME: `inventory_stock` tablosu güncellendi.
      // - location_id artık NULL olabilir (mal kabul alanı için).
      // - siparis_id eklendi.
      // - stock_status 'receiving' ve 'available' durumlarını içerir.
      // - UNIQUE constraint güncellendi.
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
          FOREIGN KEY(siparis_id) REFERENCES satin_alma_siparis_fis(id),
          FOREIGN KEY(goods_receipt_id) REFERENCES goods_receipts(goods_receipt_id)
        )
      ''');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_location ON inventory_stock(location_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_status ON inventory_stock(stock_status)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_inventory_stock_siparis ON inventory_stock(siparis_id)');

      batch.execute('CREATE INDEX IF NOT EXISTS idx_shelfs_warehouse ON shelfs(warehouse_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_shelfs_code ON shelfs(code)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_order_lines_siparis ON satin_alma_siparis_fis_satir(siparis_id)');
      batch.execute('CREATE INDEX IF NOT EXISTS idx_order_lines_urun ON satin_alma_siparis_fis_satir(urun_id)');

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

      await batch.commit(noResult: true);
    });

    debugPrint("Tüm tablolar başarıyla oluşturuldu.");
  }

  Future<void> _dropAllTables(Database db) async {
    const tables = [
      'pending_operation', 'sync_log', 'shelfs', 'employees', 'urunler',
      'satin_alma_siparis_fis', 'satin_alma_siparis_fis_satir', 'goods_receipts',
      'goods_receipt_items', 'inventory_stock', 'inventory_transfers',
      'wms_putaway_status'
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

        // ########## İNKREMENTAL SYNC İÇİN YENİ LOJİK ##########
        // Ürünler için özel işlem: aktif=0 olanları sil, diğerlerini güncelle
        if (data.containsKey('urunler')) {
          final urunlerData = List<Map<String, dynamic>>.from(data['urunler']);

          for (final urun in urunlerData) {
            final urunId = urun['id'];
            final aktif = urun['aktif'];

            if (aktif == 0) {
              // Silinmiş ürün: local'den sil
              batch.delete('urunler', where: 'id = ?', whereArgs: [urunId]);
            } else {
              // Aktif ürün: güncelle veya ekle
              final sanitizedRecord = _sanitizeRecord('urunler', urun);
              batch.insert('urunler', sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('urunler');
          }
        }

        // ########## SHELFS İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('shelfs')) {
          final shelfsData = List<Map<String, dynamic>>.from(data['shelfs']);

          for (final shelf in shelfsData) {
            final shelfId = shelf['id'];
            final isActive = shelf['is_active'];

            if (isActive == 0) {
              // Aktif olmayan rafı sil
              batch.delete('shelfs', where: 'id = ?', whereArgs: [shelfId]);
            } else {
              // Aktif rafı güncelle/ekle
              final sanitizedShelf = _sanitizeRecord('shelfs', shelf);
              batch.insert('shelfs', sanitizedShelf, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('shelfs');
          }
        }

        // Warehouse tablosu kaldırıldı - SharedPreferences kullanılıyor

        // ########## EMPLOYEES İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('employees')) {
          final employeesData = List<Map<String, dynamic>>.from(data['employees']);

          for (final employee in employeesData) {
            final employeeId = employee['id'];
            final isActive = employee['is_active'];

            if (isActive == 0) {
              // Aktif olmayan çalışanı sil
              batch.delete('employees', where: 'id = ?', whereArgs: [employeeId]);
            } else {
              // Aktif çalışanı güncelle/ekle
              final sanitizedEmployee = _sanitizeRecord('employees', employee);
              batch.insert('employees', sanitizedEmployee, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            processedItems++;
            updateProgress('employees');
          }
        }

        // ########## GOODS RECEIPTS İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('goods_receipts')) {
          final goodsReceiptsData = List<Map<String, dynamic>>.from(data['goods_receipts']);
          for (final receipt in goodsReceiptsData) {
            final sanitizedRecord = _sanitizeRecord('goods_receipts', receipt);
            batch.insert('goods_receipts', sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('goods_receipts');
          }
        }

        // ########## GOODS RECEIPT ITEMS İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('goods_receipt_items')) {
          final goodsReceiptItemsData = List<Map<String, dynamic>>.from(data['goods_receipt_items']);
          for (final item in goodsReceiptItemsData) {
            final sanitizedItem = _sanitizeRecord('goods_receipt_items', item);
            batch.insert('goods_receipt_items', sanitizedItem, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('goods_receipt_items');
          }
        }

        // ########## WMS PUTAWAY STATUS İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('wms_putaway_status')) {
          final putawayStatusData = List<Map<String, dynamic>>.from(data['wms_putaway_status']);
          for (final putaway in putawayStatusData) {
            final sanitizedPutaway = _sanitizeRecord('wms_putaway_status', putaway);
            batch.insert('wms_putaway_status', sanitizedPutaway, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('wms_putaway_status');
          }
        }

        // ########## INVENTORY STOCK İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('inventory_stock')) {
          final inventoryStockData = List<Map<String, dynamic>>.from(data['inventory_stock']);
          for (final stock in inventoryStockData) {
            final sanitizedStock = _sanitizeRecord('inventory_stock', stock);
            batch.insert('inventory_stock', sanitizedStock, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('inventory_stock');
          }
        }

        // ########## INVENTORY TRANSFERS İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('inventory_transfers')) {
          final inventoryTransfersData = List<Map<String, dynamic>>.from(data['inventory_transfers']);
          for (final transfer in inventoryTransfersData) {
            final sanitizedTransfer = _sanitizeRecord('inventory_transfers', transfer);
            batch.insert('inventory_transfers', sanitizedTransfer, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('inventory_transfers');
          }
        }

        // ########## SATIN ALMA SİPARİŞ FİŞ İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('satin_alma_siparis_fis')) {
          final siparislerData = List<Map<String, dynamic>>.from(data['satin_alma_siparis_fis']);
          for (final siparis in siparislerData) {
            final sanitizedSiparis = _sanitizeRecord('satin_alma_siparis_fis', siparis);
            batch.insert('satin_alma_siparis_fis', sanitizedSiparis, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('satin_alma_siparis_fis');
          }
        }

        // ########## SATIN ALMA SİPARİŞ FİŞ SATIR İÇİN İNKREMENTAL SYNC ##########
        if (data.containsKey('satin_alma_siparis_fis_satir')) {
          final satirlarData = List<Map<String, dynamic>>.from(data['satin_alma_siparis_fis_satir']);
          for (final satir in satirlarData) {
            final sanitizedSatir = _sanitizeRecord('satin_alma_siparis_fis_satir', satir);
            batch.insert('satin_alma_siparis_fis_satir', sanitizedSatir, conflictAlgorithm: ConflictAlgorithm.replace);

            processedItems++;
            updateProgress('satin_alma_siparis_fis_satir');
          }
        }

        // Diğer tablolar için eski mantık (full replacement)
        // Silme sırası önemli: önce child tablolar, sonra parent tablolar
        const deletionOrder = [
          // 'satin_alma_siparis_fis_satir', 'satin_alma_siparis_fis' artık incremental olarak işleniyor
          // 'urunler', 'shelfs', 'employees', 'goods_receipts', 'goods_receipt_items', 'wms_putaway_status', 'inventory_stock' burada yok çünkü yukarıda incremental olarak işlendi
        ];

        // Tablolari belirtilen sirada sil (incremental tablolar hariç)
        for (final table in deletionOrder) {
          if (data.containsKey(table)) {
            await txn.delete(table);
          }
        }

        // Sonra verileri ekle (incremental tablolar hariç, onlar zaten yukarıda işlendi)
        final incrementalTables = ['urunler', 'shelfs', 'employees', 'goods_receipts', 'goods_receipt_items', 'wms_putaway_status', 'inventory_stock', 'inventory_transfers', 'satin_alma_siparis_fis', 'satin_alma_siparis_fis_satir'];
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
        // ########## İNKREMENTAL SYNC BİTTİ ##########

        await batch.commit(noResult: true);
      });
    } finally {
      // Foreign key constraint'leri yeniden etkinleştir
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }  Map<String, dynamic> _sanitizeRecord(String table, Map<String, dynamic> record) {
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
    }

    // SQLite will automatically ignore unknown columns during INSERT
    // No need to manually remove every field that doesn't exist in local schema
    return newRecord;
  }

  // --- YARDIMCI FONKSİYONLAR ---

  Future<String?> getPoIdBySiparisId(int siparisId) async {
    final db = await database;
    final result = await db.query(
      'satin_alma_siparis_fis',
      columns: ['po_id'],
      where: 'id = ?',
      whereArgs: [siparisId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['po_id'] as String? : null;
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
      'satin_alma_siparis_fis',
      where: 'id = ?',
      whereArgs: [siparisId],
      limit: 1,
    );

    if (order.isEmpty) return null;

    const sql = '''
      SELECT
        sol.id,
        sol.urun_id,
        sol.miktar as ordered_quantity,
        u.UrunAdi as product_name,
        u.StokKodu as product_code,
        u.Barcode1 as product_barcode,
        COALESCE(received.total_received, 0) as received_quantity,
        COALESCE(putaway.putaway_quantity, 0) as putaway_quantity
      FROM satin_alma_siparis_fis_satir sol
      LEFT JOIN urunler u ON u.UrunId = sol.urun_id
      LEFT JOIN (
        SELECT
          gri.urun_id,
          SUM(gri.quantity_received) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
        WHERE gr.siparis_id = ?
        GROUP BY gri.urun_id
      ) received ON received.urun_id = sol.urun_id
      LEFT JOIN wms_putaway_status putaway ON putaway.purchase_order_line_id = sol.id
      WHERE sol.siparis_id = ?
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
        u.Barcode1 as product_barcode,
        sol.miktar as ordered_quantity,
        sol.birim as unit,
        COALESCE(previous.previous_received, 0) as previous_received,
        COALESCE(previous.previous_received, 0) + gri.quantity_received as total_received
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u.UrunId = gri.urun_id
      LEFT JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      LEFT JOIN satin_alma_siparis_fis_satir sol ON sol.siparis_id = gr.siparis_id AND sol.urun_id = gri.urun_id
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
        u.Barcode1 as product_barcode
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
        u.Barcode1 as product_barcode,
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
        u.Barcode1 as product_barcode,
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
        emp.warehouse_id as employee_warehouse_id,
        emp.role as employee_role,
        po.po_id,
        po.tarih as order_date,
        po.notlar as order_notes,
        po.status as order_status,
        po.warehouse_code as order_warehouse_code
      FROM goods_receipts gr
      LEFT JOIN employees emp ON emp.id = gr.employee_id
      LEFT JOIN satin_alma_siparis_fis po ON po.id = gr.siparis_id
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
        u.Barcode1 as product_barcode,
        u.Birim1 as product_unit,
        u.qty as product_box_qty,
        sol.miktar as ordered_quantity,
        sol.birim as order_unit,
        sol.notes as order_line_notes,
        COALESCE(putaway.putaway_quantity, 0) as putaway_quantity
      FROM goods_receipt_items gri
      LEFT JOIN urunler u ON u.UrunId = gri.urun_id
      LEFT JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
      LEFT JOIN satin_alma_siparis_fis_satir sol ON sol.siparis_id = gr.siparis_id AND sol.urun_id = gri.urun_id
      LEFT JOIN wms_putaway_status putaway ON putaway.purchase_order_line_id = sol.id
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
          header['po_id'] = poId;
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
            enrichedItem['product_barcode'] = product['Barcode1'];
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
            mutableItem['product_barcode'] = product['Barcode1'];
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
                  'SELECT id FROM goods_receipts WHERE siparis_id = ? AND receipt_date = ?',
                  [siparisId, receiptDateStr]
              );
              if (currentReceiptQuery.isNotEmpty) {
                currentReceiptId = currentReceiptQuery.first['id'] as int?;
                debugPrint('DEBUG - Found current receipt ID to exclude: $currentReceiptId for date: $receiptDateStr');
              } else {
                final likeQuery = await db.rawQuery(
                    'SELECT id FROM goods_receipts WHERE siparis_id = ? AND receipt_date LIKE ?',
                    [siparisId, '$receiptDateStr%']
                );
                if (likeQuery.isNotEmpty) {
                  currentReceiptId = likeQuery.first['id'] as int?;
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
      FROM satin_alma_siparis_fis
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

    final employeeCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM employees WHERE warehouse_id = ? AND is_active = 1',
        [warehouseId]
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
        u.Barcode1 as product_barcode
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
            header['po_id'] = poId;
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
        'satin_alma_siparis_fis',
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
          where: 'purchase_order_line_id IN (SELECT id FROM satin_alma_siparis_fis_satir WHERE siparis_id = ?)',
          whereArgs: [orderId]
        );
        putawayCount += putaways;

        // 4. satin_alma_siparis_fis_satir (sipariş satırları)
        await txn.delete(
          'satin_alma_siparis_fis_satir',
          where: 'siparis_id = ?',
          whereArgs: [orderId]
        );

        // 5. satin_alma_siparis_fis (ana sipariş - en son)
        await txn.delete(
          'satin_alma_siparis_fis',
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

  /// Warehouse tablosunu kaldırır (SharedPreferences kullanılıyor)
  Future<void> removeWarehouseTable() async {
    final db = await database;
    try {
      await db.execute('DROP TABLE IF EXISTS warehouses');
      debugPrint("Warehouse tablosu kaldırıldı - SharedPreferences kullanılıyor");
    } catch (e) {
      debugPrint("Warehouse tablosu kaldırılırken hata: $e");
    }
  }

  /// Ana temizleme metodu - tüm cleanup işlemlerini gerçekleştirir
  Future<void> performMaintenanceCleanup({int days = 7}) async {
    debugPrint("🧹 Veritabanı bakımı başlatılıyor...");

    try {
      // 1. Eski sync edilmiş operasyonları temizle
      await cleanupOldSyncedOperations(days: days);

      // 2. Eski verileri temizle
      await cleanupOldData(days: days);

      // 3. Warehouse tablosunu kaldır (tek seferlik)
      await removeWarehouseTable();

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

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
  // ANA GÜNCELLEME: Tablo adı tutarlılığı için versiyon artırıldı ve veritabanı yeniden oluşturulacak.
  static const _databaseVersion = 29;

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
        CREATE TABLE IF NOT EXISTS warehouses (
          id INTEGER PRIMARY KEY,
          name TEXT,
          post_code TEXT,
          ap TEXT,
          branch_id INTEGER,
          warehouse_code TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS shelfs (
          id INTEGER PRIMARY KEY,
          warehouse_id INTEGER,
          name TEXT,
          code TEXT,
          is_active INTEGER DEFAULT 1
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
          id INTEGER PRIMARY KEY,
          StokKodu TEXT UNIQUE,
          UrunAdi TEXT,
          Barcode1 TEXT,
          aktif INTEGER
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
          branch_id INTEGER,
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
          miktar REAL,
          ort_son_30 INTEGER,
          ort_son_60 INTEGER,
          ort_son_90 INTEGER,
          tedarikci_id INTEGER,
          tedarikci_fis_id INTEGER,
          invoice TEXT,
          birim TEXT,
          layer INTEGER,
          notes TEXT
        )
      ''');

      // wms_putaway_status tablosu dump.sql'e göre
      batch.execute('''
        CREATE TABLE IF NOT EXISTS wms_putaway_status (
          id INTEGER PRIMARY KEY,
          satinalmasiparisfissatir_id INTEGER UNIQUE,
          putaway_quantity REAL DEFAULT 0.00,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS goods_receipts (
          id INTEGER PRIMARY KEY,
          siparis_id INTEGER,
          invoice_number TEXT,
          employee_id INTEGER,
          receipt_date TEXT,
          created_at TEXT
        )
      ''');

      batch.execute('''
        CREATE TABLE IF NOT EXISTS goods_receipt_items (
          id INTEGER PRIMARY KEY,
          receipt_id INTEGER,
          urun_id INTEGER,
          quantity_received REAL,
          pallet_barcode TEXT
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
          quantity REAL NOT NULL,
          pallet_barcode TEXT,
          stock_status TEXT NOT NULL CHECK(stock_status IN ('receiving', 'available')),
          updated_at TEXT, 
          UNIQUE(urun_id, location_id, pallet_barcode, stock_status, siparis_id)
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
          employee_id INTEGER, 
          transfer_date TEXT, 
          created_at TEXT
        )
      ''');

      await batch.commit(noResult: true);
    });

    debugPrint("Tüm tablolar başarıyla oluşturuldu.");
  }

  Future<void> _dropAllTables(Database db) async {
    const tables = [
      'pending_operation', 'sync_log', 'warehouses', 'shelfs', 'employees', 'urunler',
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

  Future<void> applyDownloadedData(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var table in data.keys) {
        if (data[table] is! List) continue;
        final records = List<Map<String, dynamic>>.from(data[table]);
        if (records.isEmpty) continue;

        // ANA GÜNCELLEME: `inventory_stock` tablosunu güncellerken, lokalde `receiving` durumunda
        // olan ve henüz sunucuya gönderilmemiş kayıtları koru. Diğer tüm stokları sil ve sunucudan gelenlerle değiştir.
        if (table == 'inventory_stock') {
          // Sunucudan gelen 'available' stoklar için temizlik yap.
          // 'receiving' durumundakilere dokunma.
          await txn.delete('inventory_stock', where: 'stock_status = ?', whereArgs: ['available']);
          
          for (final record in records) {
            final sanitizedRecord = _sanitizeRecord(table, record);
            // Sadece 'available' stokları ekle, çünkü 'receiving' olanlar sunucudan gelmemeli.
            if (sanitizedRecord['stock_status'] == 'available') {
              batch.insert(table, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        } else {
          // Diğer tüm tablolar için tam yenileme yap
          final fullRefreshTables = ['employees', 'urunler', 'warehouses', 'shelfs', 'satin_alma_siparis_fis', 'satin_alma_siparis_fis_satir', 'goods_receipts', 'goods_receipt_items', 'wms_putaway_status'];
          if(fullRefreshTables.contains(table)) {
            await txn.delete(table);
          }

          for (final record in records) {
            final sanitizedRecord = _sanitizeRecord(table, record);
            batch.insert(table, sanitizedRecord, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Map<String, dynamic> _sanitizeRecord(String table, Map<String, dynamic> record) {
    final newRecord = Map<String, dynamic>.from(record);
    if (table == 'urunler' && newRecord.containsKey('UrunId')) {
      newRecord['id'] = newRecord['UrunId'];
      newRecord.remove('UrunId');
    }
    return newRecord;
  }

  // --- YARDIMCI FONKSİYONLAR ---

  // DÜZELTME: Bu fonksiyon artık kullanılmıyor, kaldırıldı.
  // Future<int?> getReceivingLocationId(int warehouseId, {DatabaseExecutor? txn}) async { ... }

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
      where: 'id = ?',
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

  Future<Map<String, dynamic>?> getWarehouseById(int warehouseId) async {
    final db = await database;
    final result = await db.query(
      'warehouses',
      where: 'id = ?',
      whereArgs: [warehouseId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // Sipariş detayları için yeni fonksiyonlar
  Future<Map<String, dynamic>?> getOrderSummary(int siparisId) async {
    final db = await database;
    
    // Siparişin temel bilgileri
    final order = await db.query(
      'satin_alma_siparis_fis',
      where: 'id = ?',
      whereArgs: [siparisId],
      limit: 1,
    );
    
    if (order.isEmpty) return null;
    
    // Sipariş satırlarının detayları
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
      LEFT JOIN urunler u ON u.id = sol.urun_id
      LEFT JOIN (
        SELECT 
          gri.urun_id,
          SUM(gri.quantity_received) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.id = gri.receipt_id
        WHERE gr.siparis_id = ?
        GROUP BY gri.urun_id
      ) received ON received.urun_id = sol.urun_id
      LEFT JOIN wms_putaway_status putaway ON putaway.satinalmasiparisfissatir_id = sol.id
      WHERE sol.siparis_id = ?
    ''';
    
    final lines = await db.rawQuery(sql, [siparisId, siparisId]);
    
    return {
      'order': order.first,
      'lines': lines,
    };
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
      LEFT JOIN urunler u ON u.id = gri.urun_id
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
      LEFT JOIN urunler u ON u.id = it.urun_id
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
      LEFT JOIN urunler u ON u.id = ints.urun_id
      LEFT JOIN shelfs loc ON loc.id = ints.location_id
      WHERE ints.siparis_id = ? AND ints.stock_status = 'receiving'
      ORDER BY ints.urun_id
    ''';
    
    return await db.rawQuery(sql, [siparisId]);
  }

  // Detaylı goods receipt bilgilerini almak için yeni fonksiyon
  Future<Map<String, dynamic>?> getGoodsReceiptDetails(int receiptId) async {
    final db = await database;
    
    const sql = '''
      SELECT 
        gr.*,
        emp.first_name || ' ' || emp.last_name as employee_name,
        emp.username as employee_username,
        emp.warehouse_id as employee_warehouse_id,
        emp.role as employee_role,
        wh.name as warehouse_name,
        wh.warehouse_code,
        wh.branch_id as warehouse_branch_id,
        po.po_id,
        po.tarih as order_date,
        po.notlar as order_notes,
        po.status as order_status,
        po.branch_id as order_branch_id
      FROM goods_receipts gr
      LEFT JOIN employees emp ON emp.id = gr.employee_id
      LEFT JOIN warehouses wh ON wh.id = emp.warehouse_id
      LEFT JOIN satin_alma_siparis_fis po ON po.id = gr.siparis_id
      WHERE gr.id = ?
    ''';
    
    final result = await db.rawQuery(sql, [receiptId]);
    return result.isNotEmpty ? result.first : null;
  }

  // Mal kabul kalemlerini sipariş detaylarıyla birlikte almak için
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
      LEFT JOIN urunler u ON u.id = gri.urun_id
      LEFT JOIN goods_receipts gr ON gr.id = gri.receipt_id
      LEFT JOIN satin_alma_siparis_fis_satir sol ON sol.siparis_id = gr.siparis_id AND sol.urun_id = gri.urun_id
      LEFT JOIN wms_putaway_status putaway ON putaway.satinalmasiparisfissatir_id = sol.id
      WHERE gri.receipt_id = ?
      ORDER BY gri.id
    ''';
    
    return await db.rawQuery(sql, [receiptId]);
  }

  // Transfer işlemleri için enriched data oluşturmak
  Future<Map<String, dynamic>> getEnrichedInventoryTransferData(String operationData) async {
    final db = await database;
    
    try {
      final data = jsonDecode(operationData);
      final header = data['header'] as Map<String, dynamic>? ?? {};
      final items = data['items'] as List<dynamic>? ?? [];
      
      // 1. SharedPreferences'tan warehouse bilgilerini al
      final prefs = await SharedPreferences.getInstance();
      final warehouseName = prefs.getString('warehouse_name');
      final warehouseCode = prefs.getString('warehouse_code');
      final branchName = prefs.getString('branch_name');
      
      // 2. Employee bilgilerini al
      if (header['employee_id'] != null) {
        final employee = await getEmployeeById(header['employee_id']);
        if (employee != null) {
          header['employee_info'] = employee;
          header['employee_name'] = '${employee['first_name']} ${employee['last_name']}';
        }
      }
      
      // 3. Source location bilgilerini al (null ise Mal Kabul Alanı)
      final sourceLocationId = header['source_location_id'];
      if (sourceLocationId != null && sourceLocationId != 0) {
        final sourceLoc = await getLocationById(sourceLocationId);
        if (sourceLoc != null) {
          header['source_location_name'] = sourceLoc['name'];
          header['source_location_code'] = sourceLoc['code'];
        }
      } else {
        header['source_location_name'] = 'Mal Kabul Alanı';
        header['source_location_code'] = 'RECEIVING';
      }
      
      // 4. Target location bilgilerini al
      final targetLocationId = header['target_location_id'];
      if (targetLocationId != null) {
        final targetLoc = await getLocationById(targetLocationId);
        if (targetLoc != null) {
          header['target_location_name'] = targetLoc['name'];
          header['target_location_code'] = targetLoc['code'];
        }
      }
      
      // 5. Sipariş bilgilerini al (putaway işlemi ise)
      final siparisId = header['siparis_id'];
      if (siparisId != null) {
        final poId = await getPoIdBySiparisId(siparisId);
        if (poId != null) {
          header['po_id'] = poId;
        }
      }
      
      // 6. Warehouse bilgilerini ekle
      header['warehouse_info'] = {
        'name': warehouseName ?? 'N/A',
        'warehouse_code': warehouseCode ?? 'N/A', 
        'branch_name': branchName ?? 'N/A',
      };
      
      // 7. Ürün bilgilerini zenginleştir
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
      return jsonDecode(operationData); // return original data on error
    }
  }

  // Pending operation için enriched data oluşturmak
  Future<Map<String, dynamic>> getEnrichedGoodsReceiptData(String operationData) async {
    final db = await database;
    
    try {
      final data = jsonDecode(operationData);
      final header = data['header'] as Map<String, dynamic>? ?? {};
      
      // 1. SharedPreferences'tan warehouse bilgilerini al (login sırasında kaydediliyor)
      final prefs = await SharedPreferences.getInstance();
      final warehouseName = prefs.getString('warehouse_name');
      final warehouseCode = prefs.getString('warehouse_code');
      final branchName = prefs.getString('branch_name');
      
      // 2. Employee bilgilerini DB'den al
      if (header['employee_id'] != null) {
        final employee = await getEmployeeById(header['employee_id']);
        if (employee != null) {
          header['employee_info'] = employee;
        }
      }

      // 3. Warehouse bilgilerini önce SharedPreferences'tan al, sonra DB'yi dene
      Map<String, dynamic> warehouseInfo = {
        'name': warehouseName ?? 'N/A',
        'warehouse_code': warehouseCode ?? 'N/A', 
        'branch_name': branchName ?? 'N/A',
      };

      // Eğer employee'dan warehouse_id varsa DB'den de kontrol et
      if (header['employee_info'] != null) {
        final employee = header['employee_info'] as Map<String, dynamic>;
        if (employee['warehouse_id'] != null) {
          final warehouse = await getWarehouseById(employee['warehouse_id']);
          if (warehouse != null) {
            // DB'den gelen bilgiler varsa SharedPreferences bilgilerini güncelle
            warehouseInfo['name'] = warehouse['name'] ?? warehouseInfo['name'];
            warehouseInfo['warehouse_code'] = warehouse['warehouse_code'] ?? warehouseInfo['warehouse_code'];
          }
        }
      }
      
      header['warehouse_info'] = warehouseInfo;

      // 3. Enrich items with product and order details
      final enrichedItems = <Map<String, dynamic>>[];
      for (final item in (data['items'] as List<dynamic>)) {
        final mutableItem = Map<String, dynamic>.from(item);
        final productId = item['urun_id'];
        
        // Product bilgilerini ekle
        if (productId != null) {
          final product = await getProductById(productId);
          if (product != null) {
            mutableItem['product_name'] = product['UrunAdi'];
            mutableItem['product_code'] = product['StokKodu'];
            mutableItem['product_barcode'] = product['Barcode1'];
          }
        }
        
        enrichedItems.add(mutableItem);
      }
      
      // Sipariş detaylarını ekle
      final siparisId = header['siparis_id'];
      if (siparisId != null) {
        final orderSummary = await getOrderSummary(siparisId);
        if (orderSummary != null) {
          header['order_info'] = orderSummary['order'];
          final orderLines = orderSummary['lines'] as List<dynamic>;
          
          final orderLinesMap = {for (var line in orderLines) line['urun_id']: line};

          for (final item in enrichedItems) {
            final orderLine = orderLinesMap[item['urun_id']];
            item['ordered_quantity'] = orderLine?['ordered_quantity'] ?? 0.0;
          }
        }
      }
      
      data['items'] = enrichedItems;
      
      data['header'] = header;
      return data;

    } catch (e, s) {
      debugPrint('Error enriching goods receipt data: $e\n$s');
      return jsonDecode(operationData); // return original data on error
    }
  }

  // Warehouse ve employee bilgileri ile birlikte sistem bilgilerini almak için
  Future<Map<String, dynamic>?> getSystemInfo(int warehouseId) async {
    final db = await database;
    
    final warehouse = await getWarehouseById(warehouseId);
    if (warehouse == null) return null;
    
    final employeeCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM employees WHERE warehouse_id = ? AND is_active = 1',
      [warehouseId]
    );
    
    final locationCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM shelfs WHERE warehouse_id = ? AND is_active = 1',
      [warehouseId]
    );
    
    return {
      'warehouse': warehouse,
      'employee_count': employeeCount.first['count'],
      'location_count': locationCount.first['count'],
    };
  }

  // Pending operation'ların detaylarını almak için
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

  // --- BEKLEYEN İŞLEMLER (PENDING OPERATIONS) FONKSİYONLARI ---

  Future<void> addPendingOperation(PendingOperation operation) async {
    final db = await database;
    await db.insert('pending_operation', operation.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation',
        where: "status = ?",
        whereArgs: ['pending'],
        orderBy: 'created_at ASC');
    return maps.map((map) => PendingOperation.fromMap(map)).toList();
  }

  Future<List<PendingOperation>> getSyncedOperations() async {
    final db = await database;
    final maps = await db.query('pending_operation', where: "status = ?", whereArgs: ['synced'], orderBy: 'synced_at DESC', limit: 100);
    return maps.map((map) => PendingOperation.fromMap(map)).toList();
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

  // --- SENKRONİZASYON LOG FONKSİYONLARI ---

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
}
// lib/core/local/database_constants.dart

/// Database table ve column isimlerini tek yerden yöneten constants
class DbTables {
  // Table names
  static const String orders = 'siparisler';
  static const String orderLines = 'siparis_ayrintili';
  static const String products = 'urunler';
  static const String warehouses = 'warehouses';
  static const String employees = 'employees';
  static const String locations = 'shelfs';
  static const String suppliers = 'tedarikci';
  static const String goodsReceipts = 'goods_receipts';
  static const String goodsReceiptItems = 'goods_receipt_items';
  static const String inventoryStock = 'inventory_stock';
  static const String inventoryTransfers = 'inventory_transfers';
  static const String putawayStatus = 'wms_putaway_status';
  static const String pendingOperations = 'pending_operation';
  static const String syncLog = 'sync_log';
}

class DbColumns {
  // Common columns
  static const String id = 'id';
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';
  static const String isActive = 'is_active';
  static const String status = 'status';

  // Orders (siparisler) table
  static const String ordersFisno = 'fisno';
  static const String ordersPoId = 'po_id'; // Legacy
  static const String ordersDate = 'tarih';
  static const String ordersNotes = 'notlar';
  static const String ordersWarehouseCode = 'warehouse_code';
  static const String ordersWarehouseKey = '_key_sis_depo_source';
  static const String ordersSupplierCode = '__carikodu';
  static const String ordersUser = 'user';
  
  // Order lines (siparis_ayrintili) table
  static const String orderLinesOrderId = 'siparisler_id';
  static const String orderLinesProductId = 'urun_id';
  static const String orderLinesQuantity = 'anamiktar';
  static const String orderLinesType = 'turu';
  static const String orderLinesTypeValue = '1';
  static const String orderLinesProductCode = 'kartkodu';
  
  // Products (urunler) table
  static const String productsId = 'UrunId'; // Special case
  static const String productsCode = 'StokKodu';
  static const String productsName = 'UrunAdi';
  static const String productsBarcode = 'Barcode1';
  static const String productsActive = 'aktif';
  
  // Warehouses table
  static const String warehousesCode = 'warehouse_code';
  static const String warehousesName = 'name';
  static const String warehousesBranchId = 'branch_id';
  static const String warehousesKey = '_key';
  
  // Employees table
  static const String employeesFirstName = 'first_name';
  static const String employeesLastName = 'last_name';
  static const String employeesUsername = 'username';
  static const String employeesPassword = 'password';
  static const String employeesWarehouseId = 'warehouse_id';
  
  // Locations (shelfs) table
  static const String locationsName = 'name';
  static const String locationsCode = 'code';
  static const String locationsDiaKey = 'dia_key';
  static const String locationsWarehouseId = 'warehouse_id';
  
  // Suppliers (tedarikci) table
  static const String suppliersCode = 'tedarikci_kodu';
  static const String suppliersName = 'tedarikci_adi';
  
  // Inventory stock table
  static const String stockProductId = 'urun_id';
  static const String stockLocationId = 'location_id';
  static const String stockOrderId = 'siparis_id';
  static const String stockGoodsReceiptId = 'goods_receipt_id';
  static const String stockQuantity = 'quantity';
  static const String stockPalletBarcode = 'pallet_barcode';
  static const String stockExpiryDate = 'expiry_date';
  static const String stockStatus = 'stock_status';
  
  // Stock status values
  static const String stockStatusReceiving = 'receiving';
  static const String stockStatusAvailable = 'available';
}

/// Minimal field mappings - sadece gerçekten ihtiyacımız olan alanlar
class DbMinimalFields {
  // Orders minimal fields
  static const List<String> ordersMinimal = [
    DbColumns.id,
    DbColumns.ordersFisno,
    DbColumns.ordersDate,
    DbColumns.status,
    DbColumns.ordersNotes,
    DbColumns.createdAt,
    DbColumns.updatedAt,
  ];
  
  // Order lines minimal fields
  static const List<String> orderLinesMinimal = [
    DbColumns.id,
    DbColumns.orderLinesOrderId,
    DbColumns.orderLinesProductId,
    DbColumns.orderLinesQuantity,
    DbColumns.orderLinesType,
    DbColumns.orderLinesProductCode,
    DbColumns.createdAt,
    DbColumns.updatedAt,
  ];
  
  // Products minimal fields
  static const List<String> productsMinimal = [
    DbColumns.productsId,
    DbColumns.productsCode,
    DbColumns.productsName,
    DbColumns.productsBarcode,
    DbColumns.productsActive,
    DbColumns.createdAt,
    DbColumns.updatedAt,
  ];
  
  // Warehouses minimal fields
  static const List<String> warehousesMinimal = [
    DbColumns.id,
    DbColumns.warehousesCode,
    DbColumns.warehousesName,
    DbColumns.createdAt,
    DbColumns.updatedAt,
  ];
}

/// SQL Query templates - sorgular da buradan yönetilir
class DbQueries {
  // Get open orders
  static String getOpenOrders(String? warehouseNameFilter) {
    final whereClause = warehouseNameFilter != null 
        ? 'AND w.${DbColumns.warehousesName} = ?'
        : '';
    
    return '''
      SELECT DISTINCT
        o.${DbColumns.id},
        o.${DbColumns.ordersFisno},
        o.${DbColumns.ordersDate},
        o.${DbColumns.ordersNotes},
        w.${DbColumns.warehousesName} as warehouse_name,
        o.${DbColumns.status},
        o.${DbColumns.createdAt},
        o.${DbColumns.updatedAt},
        t.tedarikci_adi as supplierName
      FROM ${DbTables.orders} o
      LEFT JOIN ${DbTables.warehouses} w ON w.${DbColumns.warehousesKey} = o.${DbColumns.ordersWarehouseKey}
      LEFT JOIN ${DbTables.orderLines} s ON s.${DbColumns.orderLinesOrderId} = o.${DbColumns.id}
      LEFT JOIN ${DbTables.suppliers} t ON t.${DbColumns.id} = s.tedarikci_id
      WHERE o.${DbColumns.status} IN (0, 1)
        $whereClause
        AND EXISTS (
          SELECT 1
          FROM ${DbTables.orderLines} s2
          WHERE s2.${DbColumns.orderLinesOrderId} = o.${DbColumns.id}
            AND s2.${DbColumns.orderLinesType} = '${DbColumns.orderLinesTypeValue}'
            AND s2.${DbColumns.orderLinesQuantity} > COALESCE((
              SELECT SUM(gri.quantity_received)
              FROM ${DbTables.goodsReceiptItems} gri
              JOIN ${DbTables.goodsReceipts} gr ON gr.goods_receipt_id = gri.receipt_id
              WHERE gr.siparis_id = o.${DbColumns.id} AND gri.${DbColumns.orderLinesProductId} = s2.${DbColumns.orderLinesProductId}
            ), 0) + 0.001
        )
      GROUP BY o.${DbColumns.id}, o.${DbColumns.ordersFisno}, o.${DbColumns.ordersDate}, o.${DbColumns.ordersNotes}, w.${DbColumns.warehousesName}, o.${DbColumns.status}, o.${DbColumns.createdAt}, o.${DbColumns.updatedAt}, t.tedarikci_adi
      ORDER BY o.${DbColumns.ordersDate} DESC
    ''';
  }
  
  // Get order items
  static String getOrderItems() {
    return '''
      SELECT
        s.*,
        u.${DbColumns.productsName},
        u.${DbColumns.productsCode},
        u.${DbColumns.productsBarcode},
        u.${DbColumns.productsActive},
        COALESCE((SELECT SUM(gri.quantity_received)
                   FROM ${DbTables.goodsReceiptItems} gri
                   JOIN ${DbTables.goodsReceipts} gr ON gr.goods_receipt_id = gri.receipt_id
                   WHERE gr.siparis_id = s.${DbColumns.orderLinesOrderId} AND gri.${DbColumns.orderLinesProductId} = s.${DbColumns.orderLinesProductId}), 0) as receivedQuantity,
        COALESCE(wps.putaway_quantity, 0) as transferredQuantity
      FROM ${DbTables.orderLines} s
      JOIN ${DbTables.products} u ON u.${DbColumns.productsId} = s.${DbColumns.orderLinesProductId}
      LEFT JOIN ${DbTables.putawayStatus} wps ON wps.purchase_order_line_id = s.${DbColumns.id}
      WHERE s.${DbColumns.orderLinesOrderId} = ? AND s.${DbColumns.orderLinesType} = '${DbColumns.orderLinesTypeValue}'
    ''';
  }
  
  // Get warehouse by code
  static String getWarehouseByCode() {
    return '''
      SELECT ${DbColumns.warehousesName}
      FROM ${DbTables.warehouses}
      WHERE ${DbColumns.warehousesCode} = ?
      LIMIT 1
    ''';
  }
}
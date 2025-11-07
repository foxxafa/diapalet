// lib/features/warehouse_count/domain/entities/count_item.dart

class CountItem {
  final int? id; // NULL for new items, filled after save
  final String operationUniqueId; // Same as parent sheet (relation via UUID)
  final String itemUuid; // UUID v4 for this specific item
  final String? birimKey; // Unit key (for product mode)
  final String? birimAdi; // Unit name (loaded from birimler table via JOIN, not stored)
  final String? palletBarcode; // NULL = product count, filled = pallet count
  final double quantityCounted;
  final String? barcode; // Scanned barcode
  final String? stokKodu; // Stock code
  final String? shelfCode; // Shelf code for display
  final String? expiryDate; // Expiry date (for product mode)
  final bool isDamaged; // Whether the product is damaged
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CountItem({
    this.id,
    required this.operationUniqueId,
    required this.itemUuid,
    this.birimKey,
    this.birimAdi, // This is loaded from JOIN, not stored in DB
    this.palletBarcode,
    required this.quantityCounted,
    this.barcode,
    this.stokKodu,
    this.shelfCode,
    this.expiryDate,
    this.isDamaged = false, // Default to not damaged
    this.createdAt,
    this.updatedAt,
  });

  /// Create from SQLite database row
  factory CountItem.fromMap(Map<String, dynamic> map) {
    return CountItem(
      id: map['id'] as int?,
      operationUniqueId: map['operation_unique_id'] as String,
      itemUuid: map['item_uuid'] as String,
      birimKey: map['birim_key'] as String?,
      birimAdi: map['birim_adi'] as String?,
      palletBarcode: map['pallet_barcode'] as String?,
      quantityCounted: (map['quantity_counted'] as num).toDouble(),
      barcode: map['barcode'] as String?,
      stokKodu: map['StokKodu'] as String?,
      shelfCode: map['shelf_code'] as String?,
      expiryDate: map['expiry_date'] as String?,
      isDamaged: (map['is_damaged'] as int?) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// Convert to SQLite database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'operation_unique_id': operationUniqueId,
      'item_uuid': itemUuid,
      if (birimKey != null) 'birim_key': birimKey,
      // birimAdi is NOT stored in DB, loaded via JOIN
      if (palletBarcode != null) 'pallet_barcode': palletBarcode,
      'quantity_counted': quantityCounted,
      if (barcode != null) 'barcode': barcode,
      if (stokKodu != null) 'StokKodu': stokKodu,
      if (shelfCode != null) 'shelf_code': shelfCode,
      if (expiryDate != null) 'expiry_date': expiryDate,
      'is_damaged': isDamaged ? 1 : 0,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Convert to JSON for API sync
  Map<String, dynamic> toJson() {
    // Convert expiry date from dd/MM/yyyy to yyyy-MM-dd for MySQL
    String? mysqlExpiryDate;
    if (expiryDate != null && expiryDate!.isNotEmpty) {
      try {
        // Parse dd/MM/yyyy format
        final parts = expiryDate!.split('/');
        if (parts.length == 3) {
          final day = parts[0].padLeft(2, '0');
          final month = parts[1].padLeft(2, '0');
          final year = parts[2];
          // Convert to yyyy-MM-dd
          mysqlExpiryDate = '$year-$month-$day';
        } else {
          mysqlExpiryDate = expiryDate; // Fallback to original if parsing fails
        }
      } catch (e) {
        mysqlExpiryDate = expiryDate; // Fallback to original if parsing fails
      }
    }

    return {
      if (id != null) 'id': id,
      'operation_unique_id': operationUniqueId,
      'item_uuid': itemUuid,
      'birim_key': birimKey, // Always send, even if null
      // birimAdi is NOT sent to API, server can look it up via birim_key
      'pallet_barcode': palletBarcode, // Always send, even if null
      'quantity_counted': quantityCounted,
      'barcode': barcode, // Always send, even if null (barkodu olmayan ürünler için)
      'StokKodu': stokKodu, // Always send, even if null
      'shelf_code': shelfCode, // Always send, even if null
      'expiry_date': mysqlExpiryDate, // Converted to yyyy-MM-dd format for MySQL
      'is_damaged': isDamaged ? 1 : 0, // Always send
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Check if this is a product count (pallet_barcode is NULL)
  bool get isProductCount => palletBarcode == null;

  /// Check if this is a pallet count (pallet_barcode is filled)
  bool get isPalletCount => palletBarcode != null;

  /// Create a copy with updated fields
  CountItem copyWith({
    int? id,
    String? operationUniqueId,
    String? itemUuid,
    String? birimKey,
    String? birimAdi,
    String? palletBarcode,
    double? quantityCounted,
    String? barcode,
    String? stokKodu,
    String? shelfCode,
    String? expiryDate,
    bool? isDamaged,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CountItem(
      id: id ?? this.id,
      operationUniqueId: operationUniqueId ?? this.operationUniqueId,
      itemUuid: itemUuid ?? this.itemUuid,
      birimKey: birimKey ?? this.birimKey,
      birimAdi: birimAdi ?? this.birimAdi,
      palletBarcode: palletBarcode ?? this.palletBarcode,
      quantityCounted: quantityCounted ?? this.quantityCounted,
      barcode: barcode ?? this.barcode,
      stokKodu: stokKodu ?? this.stokKodu,
      shelfCode: shelfCode ?? this.shelfCode,
      expiryDate: expiryDate ?? this.expiryDate,
      isDamaged: isDamaged ?? this.isDamaged,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

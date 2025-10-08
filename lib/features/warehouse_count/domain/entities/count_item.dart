// lib/features/warehouse_count/domain/entities/count_item.dart

class CountItem {
  final int? id; // NULL for new items, filled after save
  final int countSheetId; // Foreign key to count_sheets
  final String operationUniqueId; // Same as parent sheet
  final String itemUuid; // UUID v4 for this specific item
  final String? urunKey; // Product key (for product mode)
  final String? birimKey; // Unit key (for product mode)
  final String? palletBarcode; // NULL = product count, filled = pallet count
  final int locationId; // Shelf ID (mandatory)
  final double quantityCounted;
  final String? barcode; // Scanned barcode
  final String? stokKodu; // Stock code
  final String? shelfCode; // Shelf code for display
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CountItem({
    this.id,
    required this.countSheetId,
    required this.operationUniqueId,
    required this.itemUuid,
    this.urunKey,
    this.birimKey,
    this.palletBarcode,
    required this.locationId,
    required this.quantityCounted,
    this.barcode,
    this.stokKodu,
    this.shelfCode,
    this.createdAt,
    this.updatedAt,
  });

  /// Create from SQLite database row
  factory CountItem.fromMap(Map<String, dynamic> map) {
    return CountItem(
      id: map['id'] as int?,
      countSheetId: map['count_sheet_id'] as int,
      operationUniqueId: map['operation_unique_id'] as String,
      itemUuid: map['item_uuid'] as String,
      urunKey: map['urun_key'] as String?,
      birimKey: map['birim_key'] as String?,
      palletBarcode: map['pallet_barcode'] as String?,
      locationId: map['location_id'] as int,
      quantityCounted: (map['quantity_counted'] as num).toDouble(),
      barcode: map['barcode'] as String?,
      stokKodu: map['StokKodu'] as String?,
      shelfCode: map['shelf_code'] as String?,
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
      'count_sheet_id': countSheetId,
      'operation_unique_id': operationUniqueId,
      'item_uuid': itemUuid,
      if (urunKey != null) 'urun_key': urunKey,
      if (birimKey != null) 'birim_key': birimKey,
      if (palletBarcode != null) 'pallet_barcode': palletBarcode,
      'location_id': locationId,
      'quantity_counted': quantityCounted,
      if (barcode != null) 'barcode': barcode,
      if (stokKodu != null) 'StokKodu': stokKodu,
      if (shelfCode != null) 'shelf_code': shelfCode,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Convert to JSON for API sync
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'count_sheet_id': countSheetId,
      'operation_unique_id': operationUniqueId,
      'item_uuid': itemUuid,
      if (urunKey != null) 'urun_key': urunKey,
      if (birimKey != null) 'birim_key': birimKey,
      if (palletBarcode != null) 'pallet_barcode': palletBarcode,
      'location_id': locationId,
      'quantity_counted': quantityCounted,
      if (barcode != null) 'barcode': barcode,
      if (stokKodu != null) 'StokKodu': stokKodu,
      if (shelfCode != null) 'shelf_code': shelfCode,
    };
  }

  /// Check if this is a product count (pallet_barcode is NULL)
  bool get isProductCount => palletBarcode == null;

  /// Check if this is a pallet count (pallet_barcode is filled)
  bool get isPalletCount => palletBarcode != null;

  /// Create a copy with updated fields
  CountItem copyWith({
    int? id,
    int? countSheetId,
    String? operationUniqueId,
    String? itemUuid,
    String? urunKey,
    String? birimKey,
    String? palletBarcode,
    int? locationId,
    double? quantityCounted,
    String? barcode,
    String? stokKodu,
    String? shelfCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CountItem(
      id: id ?? this.id,
      countSheetId: countSheetId ?? this.countSheetId,
      operationUniqueId: operationUniqueId ?? this.operationUniqueId,
      itemUuid: itemUuid ?? this.itemUuid,
      urunKey: urunKey ?? this.urunKey,
      birimKey: birimKey ?? this.birimKey,
      palletBarcode: palletBarcode ?? this.palletBarcode,
      locationId: locationId ?? this.locationId,
      quantityCounted: quantityCounted ?? this.quantityCounted,
      barcode: barcode ?? this.barcode,
      stokKodu: stokKodu ?? this.stokKodu,
      shelfCode: shelfCode ?? this.shelfCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

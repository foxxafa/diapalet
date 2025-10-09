// lib/features/warehouse_count/domain/entities/count_item.dart

class CountItem {
  final int? id; // NULL for new items, filled after save
  final int countSheetId; // Foreign key to count_sheets
  final String operationUniqueId; // Same as parent sheet
  final String itemUuid; // UUID v4 for this specific item
  final String? birimKey; // Unit key (for product mode)
  final String? palletBarcode; // NULL = product count, filled = pallet count
  final double quantityCounted;
  final String? barcode; // Scanned barcode
  final String? stokKodu; // Stock code
  final String? shelfCode; // Shelf code for display
  final String? expiryDate; // Expiry date (for product mode)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CountItem({
    this.id,
    required this.countSheetId,
    required this.operationUniqueId,
    required this.itemUuid,
    this.birimKey,
    this.palletBarcode,
    required this.quantityCounted,
    this.barcode,
    this.stokKodu,
    this.shelfCode,
    this.expiryDate,
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
      birimKey: map['birim_key'] as String?,
      palletBarcode: map['pallet_barcode'] as String?,
      quantityCounted: (map['quantity_counted'] as num).toDouble(),
      barcode: map['barcode'] as String?,
      stokKodu: map['StokKodu'] as String?,
      shelfCode: map['shelf_code'] as String?,
      expiryDate: map['expiry_date'] as String?,
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
      if (birimKey != null) 'birim_key': birimKey,
      if (palletBarcode != null) 'pallet_barcode': palletBarcode,
      'quantity_counted': quantityCounted,
      if (barcode != null) 'barcode': barcode,
      if (stokKodu != null) 'StokKodu': stokKodu,
      if (shelfCode != null) 'shelf_code': shelfCode,
      if (expiryDate != null) 'expiry_date': expiryDate,
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
      if (birimKey != null) 'birim_key': birimKey,
      if (palletBarcode != null) 'pallet_barcode': palletBarcode,
      'quantity_counted': quantityCounted,
      if (barcode != null) 'barcode': barcode,
      if (stokKodu != null) 'StokKodu': stokKodu,
      if (shelfCode != null) 'shelf_code': shelfCode,
      if (expiryDate != null) 'expiry_date': expiryDate,
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
    String? birimKey,
    String? palletBarcode,
    double? quantityCounted,
    String? barcode,
    String? stokKodu,
    String? shelfCode,
    String? expiryDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CountItem(
      id: id ?? this.id,
      countSheetId: countSheetId ?? this.countSheetId,
      operationUniqueId: operationUniqueId ?? this.operationUniqueId,
      itemUuid: itemUuid ?? this.itemUuid,
      birimKey: birimKey ?? this.birimKey,
      palletBarcode: palletBarcode ?? this.palletBarcode,
      quantityCounted: quantityCounted ?? this.quantityCounted,
      barcode: barcode ?? this.barcode,
      stokKodu: stokKodu ?? this.stokKodu,
      shelfCode: shelfCode ?? this.shelfCode,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

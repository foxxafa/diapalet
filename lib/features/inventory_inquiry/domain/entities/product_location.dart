
class ProductLocation {
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;
  final String? palletBarcode;
  final DateTime? expiryDate;
  final int? locationId;
  final String? locationName;
  final String? locationCode;

  ProductLocation({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.palletBarcode,
    this.expiryDate,
    this.locationId,
    this.locationName,
    this.locationCode,
  });

  factory ProductLocation.fromMap(Map<String, dynamic> map) {
    return ProductLocation(
      productId: map['urun_id'],
      productName: map['UrunAdi'],
      productCode: map['StokKodu'],
      quantity: (map['quantity'] as num).toDouble(),
      palletBarcode: map['pallet_barcode'],
      expiryDate: map['expiry_date'] != null && (map['expiry_date'] as String).isNotEmpty
          ? DateTime.tryParse(map['expiry_date'])
          : null,
      locationId: map['location_id'],
      locationName: map['location_name'],
      locationCode: map['location_code'],
    );
  }
} 
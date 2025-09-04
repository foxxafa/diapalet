
class ProductLocation {
  final String productId;
  final String productName;
  final String productCode;
  final String? barcode;
  final String? unitName;
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
    this.barcode,
    this.unitName,
    required this.quantity,
    this.palletBarcode,
    this.expiryDate,
    this.locationId,
    this.locationName,
    this.locationCode,
  });

  factory ProductLocation.fromMap(Map<String, dynamic> map) {
    return ProductLocation(
      productId: map['urun_key'],
      productName: map['UrunAdi'],
      productCode: map['StokKodu'],
      barcode: map['barcode'], // Sadece öneriler için kullanılacak
      unitName: map['unit_name'],
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
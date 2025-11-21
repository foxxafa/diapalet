
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
  final String? receiptOperationUuid; // Hangi mal kabule bağlı
  final String? deliveryNoteNumber; // İrsaliye numarası (serbest mal kabul için)
  final String? orderNumber; // Sipariş numarası (sipariş bazlı mal kabul için)

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
    this.receiptOperationUuid,
    this.deliveryNoteNumber,
    this.orderNumber,
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
      receiptOperationUuid: map['receipt_operation_uuid'],
      deliveryNoteNumber: map['delivery_note_number'],
      orderNumber: map['order_number'],
    );
  }
} 
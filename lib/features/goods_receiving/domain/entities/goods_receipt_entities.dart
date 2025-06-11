// features/goods_receiving/domain/entities/goods_receipt_entities.dart
import 'package:uuid/uuid.dart';
import 'product_info.dart';

// Mode concept removed; receipts simply track products at locations

class GoodsReceipt {
  final int? id;
  final String externalId;
  final String invoiceNumber;
  final DateTime receiptDate;
  int synced;

  GoodsReceipt({
    this.id,
    String? externalId,
    required this.invoiceNumber,
    required this.receiptDate,
    this.synced = 0,
  }) : externalId = externalId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'external_id': externalId,
      'invoice_number': invoiceNumber,
      'receipt_date': receiptDate.toIso8601String(),
      'synced': synced,
    };
  }

  factory GoodsReceipt.fromMap(Map<String, dynamic> map) {
    return GoodsReceipt(
      id: map['id'] as int?,
      externalId: map['external_id'] as String? ?? const Uuid().v4(),
      invoiceNumber: map['invoice_number'] as String,
      receiptDate: DateTime.parse(map['receipt_date'] as String),
      // mode column removed
      synced: map['synced'] as int? ?? 0,
    );
  }
}

class GoodsReceiptItem {
  final int? id;
  final int receiptId;
  final ProductInfo product;
  final int quantity;
  final int locationId;
  final String? locationName;
  final String? containerId;

  GoodsReceiptItem({
    this.id,
    required this.receiptId,
    required this.product,
    required this.quantity,
    required this.locationId,
    this.locationName,
    this.containerId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_id': receiptId,
      'urun_id': product.id,
      'quantity': quantity,
      'location_id': locationId,
      'location_name': locationName,
      'pallet_barcode': containerId,
    };
  }

  factory GoodsReceiptItem.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptItem(
      id: map['id'],
      receiptId: map['receipt_id'],
      product: ProductInfo(
        id: map['product_id'],
        name: map['product_name'],
        stockCode: map['product_code'],
      ),
      quantity: map['quantity'],
      locationId: map['location_id'],
      locationName: map['location_name'],
      containerId: map['pallet_id'],
    );
  }
}

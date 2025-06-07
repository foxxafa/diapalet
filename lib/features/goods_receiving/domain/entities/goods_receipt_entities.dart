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
  final int goodsReceiptId;
  final ProductInfo product;
  final int quantity;
  final String location;
  final String? containerId;

  GoodsReceiptItem({
    this.id,
    required this.goodsReceiptId,
    required this.product,
    required this.quantity,
    required this.location,
    this.containerId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_id': goodsReceiptId,
      'product_id': product.id,
      'quantity': quantity,
      'location': location,
      'pallet_id': containerId,
    };
  }

  // fromMap metodu productInfo'nun dışarıdan sağlanmasını bekliyordu.
  // Eğer product_id, product_name, product_code map içinde geliyorsa,
  // doğrudan ProductInfo oluşturabiliriz.
  factory GoodsReceiptItem.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptItem(
      id: map['id'] as int?,
      goodsReceiptId: map['receipt_id'] as int,
      product: ProductInfo(
        id: map['product_id'] as String,
        name: map['product_name'] as String? ?? '',
        stockCode: map['product_code'] as String? ?? '',
      ),
      quantity: map['quantity'] as int,
      location: map['location'] as String? ?? '',
      containerId: map['pallet_id'] as String?,
    );
  }
}

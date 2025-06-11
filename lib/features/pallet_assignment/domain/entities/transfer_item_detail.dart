// lib/features/pallet_assignment/domain/entities/transfer_item_detail.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override

@immutable
class TransferItemDetail {
  final int productId;
  final String productName;
  final String productCode;
  final int quantity;

  const TransferItemDetail({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'quantity': quantity,
    };
  }

  factory TransferItemDetail.fromMap(Map<String, dynamic> map) {
    return TransferItemDetail(
      productId: (map['product_id'] as num?)?.toInt() ?? 0,
      productName: map['product_name'] as String? ?? '',
      productCode: map['product_code'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 0,
    );
  }

  factory TransferItemDetail.fromProductItem(ProductItem item, {int? quantity}) {
    return TransferItemDetail(
      productId: item.id,
      productName: item.name,
      productCode: item.productCode,
      quantity: quantity ?? item.currentQuantity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TransferItemDetail &&
              runtimeType == other.runtimeType &&
              productId == other.productId &&
              productName == other.productName &&
              productCode == other.productCode &&
              quantity == other.quantity;

  @override
  int get hashCode =>
      productId.hashCode ^
      productName.hashCode ^
      productCode.hashCode ^
      quantity.hashCode;
}

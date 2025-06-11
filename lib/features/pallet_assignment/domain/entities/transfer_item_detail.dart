// lib/features/pallet_assignment/domain/entities/transfer_item_detail.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override

@immutable
class TransferItemDetail {
  final int? id;
  final int operationId; // This ID links it to the TransferOperationHeader
  final int productId; // Changed to int for consistency with backend IDs
  final String productCode;
  final String productName;
  final int quantity;

  const TransferItemDetail({
    this.id,
    required this.operationId,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation_id': operationId,
      'product_id': productId,
      'quantity': quantity,
    };
  }

  factory TransferItemDetail.fromMap(Map<String, dynamic> map) {
    return TransferItemDetail(
      id: map['id'] as int?,
      operationId: map['operation_id'] as int? ?? 0,
      productId: (map['product_id'] as num?)?.toInt() ?? 0,
      productCode: map['product_code'] as String? ?? '',
      productName: map['product_name'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TransferItemDetail &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              operationId == other.operationId &&
              productId == other.productId &&
              productCode == other.productCode &&
              productName == other.productName &&
              quantity == other.quantity;

  @override
  int get hashCode =>
      id.hashCode ^
      operationId.hashCode ^
      productId.hashCode ^
      productCode.hashCode ^
      productName.hashCode ^
      quantity.hashCode;
}

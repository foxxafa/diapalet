// lib/features/pallet_assignment/domain/entities/transfer_item_detail.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override

@immutable
class TransferItemDetail {
  final int? id;
  final int operationId; // This ID links it to the TransferOperationHeader
  final String productCode;
  final String productName;
  final int quantity;

  const TransferItemDetail({
    this.id,
    required this.operationId,
    required this.productCode,
    required this.productName,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation_id': operationId,
      'product_code': productCode,
      'product_name': productName,
      'quantity': quantity,
    };
  }

  factory TransferItemDetail.fromMap(Map<String, dynamic> map) {
    return TransferItemDetail(
      id: map['id'] as int?,
      operationId: map['operation_id'] as int? ?? 0, // Default if null, though should exist
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
              productCode == other.productCode &&
              productName == other.productName &&
              quantity == other.quantity;

  @override
  int get hashCode =>
      id.hashCode ^
      operationId.hashCode ^
      productCode.hashCode ^
      productName.hashCode ^
      quantity.hashCode;
}

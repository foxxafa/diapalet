// lib/features/pallet_assignment/domain/entities/transfer_item_detail.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:flutter/foundation.dart'; // For @immutable and @override

@immutable
class TransferItemDetail {
  final int? id;
  final int? operationId;
  final int productId;
  final String productName;
  final String productCode;
  final int quantity;
  final String? sourcePalletBarcode;
  final String? targetPalletBarcode;

  const TransferItemDetail({
    this.id,
    this.operationId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.sourcePalletBarcode,
    this.targetPalletBarcode,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (operationId != null) 'operation_id': operationId,
      'product_id': productId,
      'quantity': quantity,
      'source_pallet_barcode': sourcePalletBarcode,
      'target_pallet_barcode': targetPalletBarcode,
    };
  }

  factory TransferItemDetail.fromMap(Map<String, dynamic> map) {
    return TransferItemDetail(
      id: map['id'] as int?,
      operationId: map['operation_id'] as int?,
      productId: (map['product_id'] as num?)?.toInt() ?? 0,
      productName: map['product_name'] as String? ?? '',
      productCode: map['product_code'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 0,
      sourcePalletBarcode: map['source_pallet_barcode'] as String?,
      targetPalletBarcode: map['target_pallet_barcode'] as String?,
    );
  }

  factory TransferItemDetail.fromProductItem(ProductItem item, {int? quantity, int? operationId}) {
    return TransferItemDetail(
      operationId: operationId,
      productId: item.id,
      productName: item.name,
      productCode: item.productCode,
      quantity: quantity ?? item.currentQuantity,
      sourcePalletBarcode: null,
      targetPalletBarcode: null,
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
              productName == other.productName &&
              productCode == other.productCode &&
              quantity == other.quantity &&
              sourcePalletBarcode == other.sourcePalletBarcode &&
              targetPalletBarcode == other.targetPalletBarcode;

  @override
  int get hashCode =>
      id.hashCode ^
      operationId.hashCode ^
      productId.hashCode ^
      productName.hashCode ^
      productCode.hashCode ^
      quantity.hashCode ^
      sourcePalletBarcode.hashCode ^
      targetPalletBarcode.hashCode;
}

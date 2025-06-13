// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart
import 'package:flutter/foundation.dart';

@immutable
class TransferItemDetail {
  final int? id;
  final int? operationId;
  final int productId;
  final String productName;
  final String productCode;
  // Miktar ondalıklı olabilir, double olarak güncellendi.
  final double quantity;
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

  /// Değişikliklere izin veren copyWith metodu eklendi.
  TransferItemDetail copyWith({
    int? id,
    int? operationId,
    int? productId,
    String? productName,
    String? productCode,
    double? quantity,
    String? sourcePalletBarcode,
    // Null atanabilmesine olanak tanımak için `targetPalletBarcode`
    // direkt olarak kullanılır.
    dynamic targetPalletBarcode,
  }) {
    return TransferItemDetail(
      id: id ?? this.id,
      operationId: operationId ?? this.operationId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      quantity: quantity ?? this.quantity,
      sourcePalletBarcode: sourcePalletBarcode ?? this.sourcePalletBarcode,
      targetPalletBarcode: targetPalletBarcode,
    );
  }

  // Diğer metodlar double tipine göre güncellendi.
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
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      sourcePalletBarcode: map['source_pallet_barcode'] as String?,
      targetPalletBarcode: map['target_pallet_barcode'] as String?,
    );
  }
}

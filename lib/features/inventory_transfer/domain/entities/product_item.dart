// lib/features/inventory_transfer/domain/entities/product_item.dart
import 'package:flutter/material.dart';

@immutable
class ProductItem {
  final int id;
  final String name;
  final String productCode;
  final String? barcode;
  final double currentQuantity;
  final DateTime? expiryDate;

  const ProductItem({
    required this.id,
    required this.name,
    required this.productCode,
    this.barcode,
    required this.currentQuantity,
    this.expiryDate,
  });

  /// @deprecated This method is deprecated. Use ProductItem constructor directly with TransferableItem data.
  @Deprecated('Use ProductItem constructor directly with TransferableItem data')
  factory ProductItem.fromBoxItem(dynamic box) {
    return ProductItem(
      id: box.productId,
      name: box.productName,
      productCode: box.productCode,
      barcode: box.barcode,
      currentQuantity: box.quantity,
      // expiryDate will be null here, as BoxItem doesn't carry it directly.
      // It's mainly for pallet contents.
    );
  }

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final dynamic idValue = json['id'] ?? json['productId'];
    final dynamic nameValue = json['name'] ?? json['productName'];
    final dynamic codeValue = json['productCode'] ?? json['code'];
    final dynamic barcodeValue = json['barcode'];
    final dynamic qtyValue = json['currentQuantity'] ?? json['quantity'];
    final dynamic expiryValue = json['expiryDate'];

    num parseToNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    return ProductItem(
      id: parseToNum(idValue).toInt(),
      name: nameValue?.toString() ?? '',
      productCode: codeValue?.toString() ?? '',
      barcode: barcodeValue?.toString(),
      currentQuantity: parseToNum(qtyValue).toDouble(),
      expiryDate: expiryValue != null ? DateTime.tryParse(expiryValue.toString()) : null,
    );
  }

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    return ProductItem(
      id: map['id'] as int,
      name: (map['name'] ?? '').toString(),
      productCode: (map['code'] ?? '').toString(),
      barcode: map['barcode']?.toString(),
      currentQuantity: (map['currentQuantity'] as num?)?.toDouble() ?? 0.0,
      expiryDate: map['expiryDate'] != null ? DateTime.tryParse(map['expiryDate'].toString()) : null,
    );
  }

  // DÜZELTME: Eksik olan toJson metodu eklendi.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'productCode': productCode,
      'barcode': barcode,
      'currentQuantity': currentQuantity,
      'expiryDate': expiryDate?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ProductItem &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              expiryDate == other.expiryDate;

  @override
  int get hashCode => id.hashCode;
}
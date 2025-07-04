// lib/features/inventory_transfer/domain/entities/product_item.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:flutter/material.dart';

@immutable
class ProductItem {
  final int id;
  final String name;
  final String productCode;
  final String? barcode1;
  final double currentQuantity;

  const ProductItem({
    required this.id,
    required this.name,
    required this.productCode,
    this.barcode1,
    required this.currentQuantity,
  });

  factory ProductItem.fromBoxItem(BoxItem box) {
    return ProductItem(
      id: box.productId,
      name: box.productName,
      productCode: box.productCode,
      barcode1: box.barcode1,
      currentQuantity: box.quantity,
    );
  }

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final dynamic idValue = json['id'] ?? json['productId'];
    final dynamic nameValue = json['name'] ?? json['productName'];
    final dynamic codeValue = json['productCode'] ?? json['code'];
    final dynamic barcodeValue = json['barcode1'];
    final dynamic qtyValue = json['currentQuantity'] ?? json['quantity'];

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
      barcode1: barcodeValue?.toString(),
      currentQuantity: parseToNum(qtyValue).toDouble(),
    );
  }

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    return ProductItem(
      id: map['id'] as int,
      name: (map['name'] ?? '').toString(),
      productCode: (map['code'] ?? '').toString(),
      barcode1: map['barcode1']?.toString(),
      currentQuantity: (map['currentQuantity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // DÜZELTME: Eksik olan toJson metodu eklendi.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'productCode': productCode,
      'barcode1': barcode1,
      'currentQuantity': currentQuantity,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ProductItem &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}
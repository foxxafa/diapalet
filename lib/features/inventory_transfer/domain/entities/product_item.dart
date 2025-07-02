// lib/features/inventory_transfer/domain/entities/product_item.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:flutter/material.dart';

@immutable
class ProductItem {
  final int id;
  final String name;
  final String productCode;
  final double currentQuantity;

  const ProductItem({
    required this.id,
    required this.name,
    required this.productCode,
    required this.currentQuantity,
  });

  factory ProductItem.fromBoxItem(BoxItem box) {
    return ProductItem(
      id: box.productId,
      name: box.productName,
      productCode: box.productCode,
      currentQuantity: box.quantity,
    );
  }

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final dynamic idValue = json['id'] ?? json['productId'];
    final dynamic nameValue = json['name'] ?? json['productName'];
    final dynamic codeValue = json['productCode'] ?? json['code'];
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
      currentQuantity: parseToNum(qtyValue).toDouble(),
    );
  }

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    return ProductItem(
      id: map['id'] as int,
      name: (map['name'] ?? '').toString(),
      productCode: (map['code'] ?? '').toString(),
      currentQuantity: (map['currentQuantity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // DÜZELTME: Eksik olan toJson metodu eklendi.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'productCode': productCode,
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
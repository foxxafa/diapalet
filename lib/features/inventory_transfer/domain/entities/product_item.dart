// lib/features/inventory_transfer/domain/entities/product_item.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:flutter/material.dart';

@immutable
class ProductItem {
  final int id;
  final String name;
  final String productCode;
  final int currentQuantity;
  final TextEditingController transferQtyController;

  ProductItem({
    required this.id,
    required this.name,
    required this.productCode,
    required this.currentQuantity,
  }) : transferQtyController =
  TextEditingController(text: currentQuantity.toString());

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

    int parseToInt(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is double) return val.round();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return ProductItem(
      id: parseToInt(idValue),
      name: nameValue?.toString() ?? '',
      productCode: codeValue?.toString() ?? '',
      currentQuantity: parseToInt(qtyValue),
    );
  }

  /// Veritabanından gelen Map'i ProductItem nesnesine dönüştürür.
  factory ProductItem.fromMap(Map<String, dynamic> map) {
    return ProductItem(
      id: map['id'] as int,
      name: (map['name'] ?? '').toString(),
      productCode: (map['productCode'] ?? map['code'] ?? '').toString(),
      currentQuantity: (map['currentQuantity'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ProductItem &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

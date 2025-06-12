// lib/features/pallet_assignment/domain/entities/product_item.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override

@immutable
class ProductItem {
  final int id;
  final String name;
  final String productCode;
  final int currentQuantity;

  const ProductItem({
    required this.id,
    required this.name,
    required this.productCode,
    required this.currentQuantity,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ProductItem &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              name == other.name &&
              productCode == other.productCode &&
              currentQuantity == other.currentQuantity;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      productCode.hashCode ^
      currentQuantity.hashCode;

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'productCode': productCode,
      'currentQuantity': currentQuantity,
    };
  }

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    return ProductItem(
      id: map['product_id'] as int,
      name: (map['product_name'] ?? '').toString(),
      productCode: (map['product_code'] ?? '').toString(),
      currentQuantity: (map['quantity'] as num?)?.toInt() ?? 0,
    );
  }

// Optional: toMap and fromMap if needed for local storage directly with this model
// For now, assuming local datasource might handle its own mapping if structure differs.
}

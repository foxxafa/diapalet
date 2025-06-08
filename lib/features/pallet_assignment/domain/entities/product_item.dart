// lib/features/pallet_assignment/domain/entities/product_item.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override

@immutable
class ProductItem {
  final String id;
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
    return ProductItem(
      id: json['id'] as String,
      name: json['name'] as String,
      productCode: json['productCode'] as String,
      currentQuantity: json['currentQuantity'] as int,
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

// Optional: toMap and fromMap if needed for local storage directly with this model
// For now, assuming local datasource might handle its own mapping if structure differs.
}

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
    // Backend may send keys like productId, productName, quantity, etc.
    final dynamic idValue = json['id'] ?? json['productId'];
    final dynamic nameValue = json['name'] ?? json['productName'];
    final dynamic codeValue = json['productCode'] ?? json['code'];
    final dynamic qtyValue = json['currentQuantity'] ?? json['quantity'];

    int _parseQty(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is double) return val.round();
      if (val is num) return val.toInt();
      if (val is String) {
        final int? i = int.tryParse(val);
        if (i != null) return i;
        final double? d = double.tryParse(val);
        if (d != null) return d.round();
      }
      return 0;
    }

    return ProductItem(
      id: idValue?.toString() ?? '',
      name: nameValue?.toString() ?? '',
      productCode: codeValue?.toString() ?? '',
      currentQuantity: _parseQty(qtyValue),
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

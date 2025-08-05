// lib/features/inventory_transfer/domain/entities/product_stock_item.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class ProductStockItem extends Equatable {
  final int? stockId;
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;
  final String? barcode1;

  const ProductStockItem({
    this.stockId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.barcode1,
  });

  @override
  List<Object?> get props => [
    stockId,
    productId,
    productName,
    productCode,
    quantity,
    barcode1,
  ];

  factory ProductStockItem.fromJson(Map<String, dynamic> json) {
    double parseDoubleFromJson(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return ProductStockItem(
      stockId: json['stock_id'] as int?,
      productId: json['product_id'] as int? ?? 0,
      productName: json['product_name'] as String? ?? '',
      productCode: json['product_code'] as String? ?? '',
      quantity: parseDoubleFromJson(json['quantity']),
      barcode1: json['barcode1'] as String?,
    );
  }

  factory ProductStockItem.fromDbMap(Map<String, dynamic> map) {
    return ProductStockItem(
      stockId: map['stock_id'] as int?,
      productId: map['product_id'] as int? ?? 0,
      productName: map['product_name'] as String? ?? '',
      productCode: map['product_code'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      barcode1: map['barcode1'] as String?,
    );
  }
}

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
  final String stockStatus;
  final int? siparisId;

  const ProductItem({
    required this.id,
    required this.name,
    required this.productCode,
    this.barcode1,
    required this.currentQuantity,
    required this.stockStatus,
    this.siparisId,
  });

  factory ProductItem.fromBoxItem(BoxItem box) {
    return ProductItem(
      id: box.productId,
      name: box.productName,
      productCode: box.productCode,
      barcode1: box.barcode1,
      currentQuantity: box.quantity,
      stockStatus: box.stockStatus,
      siparisId: box.siparisId,
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
      barcode1: json['barcode1'] as String?,
      currentQuantity: parseToNum(qtyValue).toDouble(),
      stockStatus: json['stock_status'] as String,
      siparisId: json['siparis_id'] as int?,
    );
  }

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    final stockStatusValue = map['stockStatus'] ?? map['stock_status'];
    final siparisIdValue = map['siparisId'] ?? map['siparis_id'];

    if (stockStatusValue == null) {
      throw const FormatException("The 'stockStatus' or 'stock_status' field is missing or null in the map.");
    }

    return ProductItem(
      id: map['id'] as int,
      name: map['name'] as String,
      productCode: map['productCode'] as String,
      barcode1: map['barcode1'] as String?,
      currentQuantity: (map['currentQuantity'] as num).toDouble(),
      stockStatus: stockStatusValue as String,
      siparisId: siparisIdValue as int?,
    );
  }

  // DÜZELTME: Eksik olan toJson metodu eklendi.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'productCode': productCode,
      'currentQuantity': currentQuantity,
      'stock_status': stockStatus,
      'siparis_id': siparisId,
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
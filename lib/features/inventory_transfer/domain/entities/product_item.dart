// lib/features/inventory_transfer/domain/entities/product_item.dart
import 'package:flutter/material.dart';

@immutable
class ProductItem {
  final String productKey; // _key değeri
  final String? birimKey; // Birim _key değeri
  final String name;
  final String productCode;
  final String? barcode;
  final double currentQuantity;
  final DateTime? expiryDate;

  const ProductItem({
    required this.productKey,
    this.birimKey,
    required this.name,
    required this.productCode,
    this.barcode,
    required this.currentQuantity,
    this.expiryDate,
  });

  /// Unique key: productKey + birimKey + expiryDate kombinasyonu
  /// Farklı birim veya farklı SKT'ler ayrı item olarak değerlendirilir
  String get key {
    final birimPart = birimKey ?? 'no_unit';
    final expiryPart = expiryDate?.toIso8601String().split('T')[0] ?? 'no_expiry';
    return '${productKey}_${birimPart}_${expiryPart}';
  }


  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final dynamic nameValue = json['name'] ?? json['productName'];
    final dynamic codeValue = json['productCode'] ?? json['code'];
    final dynamic barcodeValue = json['barcode'];
    final dynamic qtyValue = json['currentQuantity'] ?? json['quantity'];
    final dynamic expiryValue = json['expiryDate'];
    final dynamic keyValue = json['_key'] ?? json['productKey'];
    final dynamic birimKeyValue = json['birim_key'];

    num parseToNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    return ProductItem(
      productKey: keyValue?.toString() ?? '',
      birimKey: birimKeyValue?.toString(),
      name: nameValue?.toString() ?? '',
      productCode: codeValue?.toString() ?? '',
      barcode: barcodeValue?.toString(),
      currentQuantity: parseToNum(qtyValue).toDouble(),
      expiryDate: expiryValue != null ? DateTime.tryParse(expiryValue.toString()) : null,
    );
  }

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    return ProductItem(
      productKey: map['_key']?.toString() ?? map['productKey']?.toString() ?? '',
      birimKey: map['birim_key']?.toString(),
      name: (map['name'] ?? '').toString(),
      productCode: (map['code'] ?? '').toString(),
      barcode: map['barcode']?.toString(),
      currentQuantity: (map['currentQuantity'] as num?)?.toDouble() ?? 0.0,
      expiryDate: map['expiryDate'] != null ? DateTime.tryParse(map['expiryDate'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productKey': productKey,
      'birim_key': birimKey,
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
              productKey == other.productKey &&
              expiryDate == other.expiryDate;

  @override
  int get hashCode => productKey.hashCode;
}
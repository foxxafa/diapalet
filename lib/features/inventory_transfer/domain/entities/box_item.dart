// lib/features/inventory_transfer/domain/entities/box_item.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class BoxItem extends Equatable {
  // Bu ID her zaman mevcut olmayabilir, bu yüzden nullable yapıldı.
  final int? boxId;
  final int productId;
  final String productName;
  final String productCode;
  // Miktar ondalıklı olabilir, double olarak güncellendi.
  final double quantity;

  const BoxItem({
    this.boxId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
  });

  @override
  List<Object?> get props => [boxId, productId, productName, productCode, quantity];

  /// API'den gelen JSON verisini parse eder.
  factory BoxItem.fromJson(Map<String, dynamic> json) {
    return BoxItem(
      // API'den gelen yanıtta 'boxId' olmayabilir.
      productId: json['productId'] as int,
      productName: json['productName'] as String,
      productCode: json['productCode'] as String,
      quantity: (json['quantity'] as num).toDouble(),
    );
  }

  /// Lokal veritabanından gelen map verisini parse eder.
  factory BoxItem.fromDbMap(Map<String, dynamic> map) {
    return BoxItem(
      // Veritabanı sorgusunda 'boxId' olmayabilir.
      productId: map['productId'] as int,
      productName: map['productName'] as String,
      productCode: map['productCode'] as String,
      quantity: (map['quantity'] as num).toDouble(),
    );
  }
}

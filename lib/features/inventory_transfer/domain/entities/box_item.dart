// lib/features/inventory_transfer/domain/entities/box_item.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// @deprecated BoxItem is deprecated. Use ProductStockItem instead.
/// BoxItem represented products in stock, not actual boxes.
@immutable
@Deprecated('Use ProductStockItem instead. BoxItem will be removed in future versions.')
class BoxItem extends Equatable {
  final int? boxId;
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;
  final String? barcode1; // GÜNCELLEME: Barkod alanı eklendi

  const BoxItem({
    this.boxId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.barcode1, // GÜNCELLEME: Constructor'a eklendi
  });

  @override
  // GÜNCELLEME: Eşitlik kontrolü için props listesine eklendi
  List<Object?> get props => [boxId, productId, productName, productCode, quantity, barcode1];

  /// GÜNCELLEME: JSON'dan gelen 'quantity' alanı string veya num olabilir.
  /// Bu durumu yönetmek için daha güvenli bir parse metodu eklendi.
  factory BoxItem.fromJson(Map<String, dynamic> json) {
    // String veya num olabilecek bir değeri güvenli bir şekilde double'a çevirir.
    double parseQuantity(dynamic val) {
      if (val == null) return 0.0;
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      // Beklenmedik bir tip gelirse (örn: Decimal'dan dönen nesne) toString ile dener.
      return double.tryParse(val.toString()) ?? 0.0;
    }

    return BoxItem(
      productId: json['productId'] as int,
      productName: json['productName'] as String,
      productCode: json['productCode'] as String,
      quantity: parseQuantity(json['quantity']),
      barcode1: json['barcode1'] as String?, // GÜNCELLEME: JSON'dan okunuyor
    );
  }

  /// Lokal veritabanından gelen map verisini parse eder.
  factory BoxItem.fromDbMap(Map<String, dynamic> map) {
    return BoxItem(
      productId: map['productId'] as int,
      productName: map['productName'] as String,
      productCode: map['productCode'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      barcode1: map['barcode1'] as String?, // GÜNCELLEME: Map'ten okunuyor
    );
  }
}

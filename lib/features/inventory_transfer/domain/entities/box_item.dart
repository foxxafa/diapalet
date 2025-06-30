// lib/features/inventory_transfer/domain/entities/box_item.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class BoxItem extends Equatable {
  final int? boxId;
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;
  final String? barcode1; // GÜNCELLEME: Barkod alanı eklendi
  final String stockStatus; // YENİ EKLENDİ
  final int? siparisId;     // YENİ EKLENDİ

  const BoxItem({
    this.boxId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.barcode1, // GÜNCELLEME: Constructor'a eklendi
    required this.stockStatus, // YENİ EKLENDİ
    this.siparisId,         // YENİ EKLENDİ
  });

  @override
  // GÜNCELLEME: Eşitlik kontrolü için props listesine eklendi
  List<Object?> get props => [boxId, productId, productName, productCode, quantity, barcode1, stockStatus, siparisId];

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
      stockStatus: json['stock_status'] as String, // YENİ EKLENDİ
      siparisId: json['siparis_id'] as int?,      // YENİ EKLENDİ
    );
  }

  /// Lokal veritabanından gelen map verisini parse eder.
  factory BoxItem.fromDbMap(Map<String, dynamic> map) {
    return BoxItem(
      productId: map['urun_id'] as int,
      productName: map['UrunAdi'] as String,
      productCode: map['StokKodu'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      barcode1: map['Barcode1'] as String?,
      stockStatus: map['stock_status'] as String, // YENİ EKLENDİ
      siparisId: map['siparis_id'] as int?,      // YENİ EKLENDİ
    );
  }
}

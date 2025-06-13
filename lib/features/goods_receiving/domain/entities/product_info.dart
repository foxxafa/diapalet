// lib/features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id;
  final String name;
  final String stockCode;
  final String? barcode1; // GÜNCELLEME: Barkod alanı eklendi
  final bool isActive;

  const ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
    this.barcode1, // GÜNCELLEME: Constructor'a eklendi
    required this.isActive,
  });

  /// Özellikle lokal 'urunler' tablosundan gelen Map'ten nesne oluşturur.
  factory ProductInfo.fromDbMap(Map<String, dynamic> map) {
    return ProductInfo(
      id: map['UrunId'] as int,
      name: map['UrunAdi'] as String,
      stockCode: map['StokKodu'] as String,
      barcode1: map['Barcode1'] as String?, // GÜNCELLEME: Veritabanından okunuyor
      isActive: (map['aktif'] as int? ?? 1) == 1,
    );
  }

  /// API'den gelen JSON'dan nesne oluşturur.
  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      stockCode: json['stockCode'] as String? ?? json['code'] as String? ?? '',
      barcode1: json['barcode1'] as String?, // GÜNCELLEME: JSON'dan okunuyor
      isActive: (json['isActive'] as bool? ?? true),
    );
  }

  /// Nesneyi JSON formatına dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stockCode': stockCode,
      'barcode1': barcode1, // GÜNCELLEME: JSON'a ekleniyor
      'isActive': isActive,
    };
  }

  @override
  // GÜNCELLEME: Eşitlik kontrolü için props listesine eklendi
  List<Object?> get props => [id, name, stockCode, barcode1, isActive];
}

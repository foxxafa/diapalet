// lib/features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id;
  final String name;
  final String stockCode;
  final bool isActive;

  const ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
    required this.isActive,
  });

  /// Özellikle lokal 'urunler' tablosundan gelen Map'ten nesne oluşturur.
  factory ProductInfo.fromDbMap(Map<String, dynamic> map) {
    return ProductInfo(
      id: map['UrunId'] as int,
      name: map['UrunAdi'] as String,
      stockCode: map['StokKodu'] as String,
      isActive: (map['aktif'] as int? ?? 1) == 1,
    );
  }

  /// API'den gelen JSON'dan nesne oluşturur.
  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      stockCode: json['stockCode'] as String? ?? json['code'] as String? ?? '',
      isActive: (json['isActive'] as bool? ?? true),
    );
  }

  /// Nesneyi JSON formatına dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stockCode': stockCode,
      'isActive': isActive,
    };
  }

  @override
  List<Object?> get props => [id, name, stockCode, isActive];
}

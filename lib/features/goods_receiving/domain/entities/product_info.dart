// lib/features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id;
  final String name;
  final String stockCode;
  final String? barcode1;
  final String? barcode2;
  final String? barcode3;
  final String? barcode4;
  final bool isActive;

  const ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
    this.barcode1,
    this.barcode2,
    this.barcode3,
    this.barcode4,
    required this.isActive,
  });

  // GÜNCELLEME BAŞLANGIÇ
  /// Özellikle lokal 'urunler' tablosundan gelen Map'ten nesne oluşturur.
  factory ProductInfo.fromDbMap(Map<String, dynamic> map) {
    // Gelen map'te 'id', 'urun_id', veya 'UrunId' olabilir. Hepsini kontrol edelim.
    final dynamic idValue = map['id'] ?? map['urun_id'] ?? map['UrunId'];

    return ProductInfo(
      // ÇÖKME BURADAYDI: 'UrunId' yerine 'id' kullanılmalı ve null kontrolü yapılmalı.
      id: (idValue as num?)?.toInt() ?? 0,
      name: map['UrunAdi'] as String? ?? '',
      stockCode: map['StokKodu'] as String? ?? '',
      barcode1: map['Barcode1'] as String?,
      barcode2: map['Barcode2'] as String?,
      barcode3: map['Barcode3'] as String?,
      barcode4: map['Barcode4'] as String?,
      isActive: (map['aktif'] as int? ?? 1) == 1,
    );
  }
  // GÜNCELLEME SONU

  /// API'den gelen JSON'dan nesne oluşturur.
  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      stockCode: json['stockCode'] as String? ?? json['code'] as String? ?? '',
      barcode1: json['barcode1'] as String?,
      barcode2: json['barcode2'] as String?,
      barcode3: json['barcode3'] as String?,
      barcode4: json['barcode4'] as String?,
      isActive: (json['isActive'] as bool? ?? true),
    );
  }

  /// Nesneyi JSON formatına dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stockCode': stockCode,
      'barcode1': barcode1,
      'barcode2': barcode2,
      'barcode3': barcode3,
      'barcode4': barcode4,
      'isActive': isActive,
    };
  }

  @override
  List<Object?> get props => [id, name, stockCode, barcode1, barcode2, barcode3, barcode4, isActive];
}
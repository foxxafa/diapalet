// lib/features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id; // Backward compatibility için int olarak kalacak
  final String? productKey; // _key değeri için yeni alan
  final String name;
  final String stockCode;
  final bool isActive;
  // Barcode bilgileri artık barkodlar tablosundan gelecek
  final Map<String, dynamic>? birimInfo;
  final Map<String, dynamic>? barkodInfo;

  const ProductInfo({
    required this.id,
    this.productKey, // _key değeri
    required this.name,
    required this.stockCode,
    required this.isActive,
    this.birimInfo,
    this.barkodInfo,
  });

  /// API'ye gönderilecek ürün ID'si - _key varsa onu kullan
  String get apiProductId => productKey ?? id.toString();

  // GÜNCELLEME BAŞLANGIÇ
  /// Especially for Map coming from local 'urunler' table.
  factory ProductInfo.fromDbMap(Map<String, dynamic> map) {

    Map<String, dynamic>? barkodInfoMap = map['barkod_info'] as Map<String, dynamic>?;
    if (barkodInfoMap == null && map.containsKey('barkod')) {
      final barcodeValue = map['barkod'];
      if (barcodeValue != null) {
        barkodInfoMap = {'barkod': barcodeValue};
      }
    }

    return ProductInfo(
      // UrunId backward compatibility için
      id: (map['UrunId'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt() ?? 0,
      productKey: map['_key'] as String?, // _key değeri
      name: map['UrunAdi'] as String? ?? map['product_name'] as String? ?? map['productName'] as String? ?? '',
      stockCode: map['StokKodu'] as String? ?? map['product_code'] as String? ?? map['productCode'] as String? ?? '',
      isActive: (map['aktif'] as int? ?? 1) == 1,
      birimInfo: map['birim_info'] as Map<String, dynamic>?,
      barkodInfo: barkodInfoMap,
    );
  }

  /// Genel Map'ten nesne oluşturur (backward compatibility)
  factory ProductInfo.fromMap(Map<String, dynamic> map) => ProductInfo.fromDbMap(map);
  // GÜNCELLEME SONU

  /// API'den gelen JSON'dan nesne oluşturur.
  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      stockCode: json['stockCode'] as String? ?? json['code'] as String? ?? '',
      isActive: (json['isActive'] as bool? ?? true),
      birimInfo: json['birimInfo'] as Map<String, dynamic>?,
      barkodInfo: json['barkodInfo'] as Map<String, dynamic>?,
    );
  }

  /// Yeni barkod sistemi için barkod bilgisi
  String? get productBarcode => barkodInfo?['barkod'] as String?;

  /// Nesneyi JSON formatına dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productKey': productKey,
      'name': name,
      'stockCode': stockCode,
      'isActive': isActive,
      'birimInfo': birimInfo,
      'barkodInfo': barkodInfo,
    };
  }


  @override
  List<Object?> get props => [id, productKey, name, stockCode, isActive, birimInfo, barkodInfo];
}
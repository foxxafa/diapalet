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
  final bool isOutOfOrder; // Sipariş dışı ürün flag

  const ProductInfo({
    required this.id,
    this.productKey, // _key değeri
    required this.name,
    required this.stockCode,
    required this.isActive,
    this.birimInfo,
    this.barkodInfo,
    this.isOutOfOrder = false, // Default false
  });

  /// Ürün anahtarı - _key varsa onu kullan, yoksa id'yi string'e çevir
  String get key => productKey ?? id.toString();

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

    // Yeni veritabanı yapısından birim bilgilerini al
    Map<String, dynamic>? birimInfoMap = map['birim_info'] as Map<String, dynamic>?;
    if (birimInfoMap == null) {
      // Veritabanından gelen birim bilgilerini kullan
      if (map.containsKey('birimadi') || map.containsKey('birimkod') || map.containsKey('carpan')) {
        birimInfoMap = {
          'birimadi': map['birimadi'],
          'birimkod': map['birimkod'],
          'carpan': map['carpan'],
          'anamiktar': map['anamiktar'], // Sipariş miktarı
          'anabirimi': map['anabirimi'], // Sipariş birimi (eski)
          'sipbirimi_adi': map['sipbirimi_adi'], // Sipariş birimi adı (yeni)
          'sipbirimi_kod': map['sipbirimi_kod'], // Sipariş birimi kodu (yeni)
          'sipbirimkey': map['sipbirimkey'], // Sipariş birim anahtarı
          'source_type': map['source_type'], // 'order' veya 'out_of_order'
        };
      }
    }

    return ProductInfo(
      // UrunId backward compatibility için
      id: (map['UrunId'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt() ?? 0,
      productKey: map['_key'] as String?, // _key değeri
      name: map['UrunAdi'] as String? ?? map['product_name'] as String? ?? map['productName'] as String? ?? '',
      stockCode: map['StokKodu'] as String? ?? map['product_code'] as String? ?? map['productCode'] as String? ?? '',
      isActive: (map['aktif'] as int? ?? 1) == 1,
      birimInfo: birimInfoMap,
      barkodInfo: barkodInfoMap,
      isOutOfOrder: map['is_out_of_order'] as bool? ?? (map['source_type'] == 'out_of_order'),
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
      isOutOfOrder: json['isOutOfOrder'] as bool? ?? false,
    );
  }

  /// Yeni barkod sistemi için barkod bilgisi
  String? get productBarcode => barkodInfo?['barkod'] as String?;

  /// Sipariş miktarı - siparişli ürünlerde anamiktar, sipariş dışında 0
  double get orderQuantity => birimInfo?['anamiktar']?.toDouble() ?? 0.0;

  /// Birim adı (barkod üzerinden gelen birim)
  String? get unitName => birimInfo?['birimadi'] as String?;

  /// Birim kodu (barkod üzerinden gelen birim)
  String? get unitCode => birimInfo?['birimkod'] as String?;

  /// Sipariş birimi adı (sipbirimkey üzerinden gelen)
  String? get orderUnitName => birimInfo?['sipbirimi_adi'] as String?;

  /// Sipariş birimi kodu (sipbirimkey üzerinden gelen)  
  String? get orderUnitCode => birimInfo?['sipbirimi_kod'] as String?;

  /// Görüntüleme için birim adı - sipariş varsa sipariş birimi, yoksa barkod birimi
  String? get displayUnitName => orderUnitName ?? unitName;

  /// Sipariş içi/dışı durumu
  bool get isOrderedUnit => birimInfo?['source_type'] == 'order';

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
      'isOutOfOrder': isOutOfOrder,
    };
  }


  /// copyWith method to create a new instance with isOutOfOrder flag
  ProductInfo copyWithOutOfOrderFlag(bool isOutOfOrder) {
    return ProductInfo(
      id: id,
      productKey: productKey,
      name: name,
      stockCode: stockCode,
      isActive: isActive,
      birimInfo: birimInfo,
      barkodInfo: barkodInfo,
      isOutOfOrder: isOutOfOrder,
    );
  }

  @override
  List<Object?> get props => [id, productKey, name, stockCode, isActive, birimInfo, barkodInfo, isOutOfOrder];
}
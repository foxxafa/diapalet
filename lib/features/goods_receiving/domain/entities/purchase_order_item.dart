// lib/features/goods_receiving/domain/entities/purchase_order_item.dart
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';

class PurchaseOrderItem {
  final int id;
  final int orderId;
  final int productId;
  final double expectedQuantity;
  final double receivedQuantity;
  final double transferredQuantity;
  final String? unit;
  final ProductInfo? product;

  // HATA DÜZELTMESİ: Palet bilgisini tutmak için bu alan eklendi.
  // Bu alan, repository katmanında sorgu ile doldurulur ve siparişin
  // orijinal bir parçası değildir, bu yüzden isteğe bağlı (nullable) yapılır.
  final String? palletBarcode;

  PurchaseOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.expectedQuantity,
    required this.receivedQuantity,
    required this.transferredQuantity,
    this.unit,
    required this.product,
    // HATA DÜZELTMESİ: Constructor'a eklendi.
    this.palletBarcode,
  });

  /// Veritabanından gelen Map verisini parse eder.
  /// Not: Bu factory metodu, 'palletBarcode' alanını DAHİL ETMEZ,
  /// çünkü bu alan genellikle bir join işlemi ile sonradan eklenir.
  /// Repository katmanı bu temel nesneyi oluşturduktan sonra yeni bir
  /// nesne yaratarak bu alanı doldurur.
  factory PurchaseOrderItem.fromDb(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      id: map['id'] as int,
      orderId: map['siparisler_id'] as int,  // DÜZELTME: Correct field name
      productId: map['urun_id'] as int,
      expectedQuantity: (map['anamiktar'] as num? ?? 0).toDouble(),  // DÜZELTME: Correct field name
      receivedQuantity: (map['receivedQuantity'] as num? ?? 0).toDouble(),
      transferredQuantity: (map['transferredQuantity'] as num? ?? 0).toDouble(),
      unit: map['birim'] as String?,
      @immutable
class ProductInfo {
  final int id;
  final String name;
  final String? code;
  final String? unit;
  final double? boxQuantity;
  final String? barcode; // Yeni barkod alanı

  const ProductInfo({
    required this.id,
    required this.name,
    this.code,
    this.unit,
    this.boxQuantity,
    this.barcode, // Constructor'a eklendi
  });

  // fromMap constructor
  factory ProductInfo.fromMap(Map<String, dynamic> map) {
    return ProductInfo(
      id: map['UrunId'] as int,
      name: map['UrunAdi'] as String,
      code: map['StokKodu'] as String?,
      unit: map['anabirimi'] as String?,
      boxQuantity: (map['qty'] as num?)?.toDouble(),
      // Yeni barkod alanı map'ten okunuyor (barkod_info içinden)
      barcode: (map['barkod_info'] as Map<String, dynamic>?)?['barkod'] as String? ?? map['barkod'] as String?,
    );
  }

  ProductInfo copyWith({
    int? id,
    String? name,
    String? code,
    String? unit,
    double? boxQuantity,
    String? barcode,
  }) {
    return ProductInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      unit: unit ?? this.unit,
      boxQuantity: boxQuantity ?? this.boxQuantity,
      barcode: barcode ?? this.barcode,
    );
  }
}
      // palletBarcode burada null'dır, repository'de doldurulacak.
    );
  }

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      id: json['id'],
      orderId: json['orderId'],
      productId: json['productId'],
      expectedQuantity: (json['expectedQuantity'] as num).toDouble(),
      receivedQuantity: (json['receivedQuantity'] as num).toDouble(),
      transferredQuantity: (json['transferredQuantity'] as num? ?? 0).toDouble(),
      unit: json['unit'],
      product: json['product'] != null ? ProductInfo.fromJson(json['product']) : null,
      // HATA DÜZELTMESİ: JSON'dan okunuyor.
      palletBarcode: json['palletBarcode'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'productId': productId,
      'expectedQuantity': expectedQuantity,
      'receivedQuantity': receivedQuantity,
      'transferredQuantity': transferredQuantity,
      'unit': unit,
      'product': product?.toJson(),
      // HATA DÜZELTMESİ: JSON'a ekleniyor.
      'palletBarcode': palletBarcode,
    };
  }
}
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:flutter/foundation.dart';

@immutable
class PurchaseOrderItem {
  final int id;
  final int orderId;
  final int productId;
  final double expectedQuantity;
  final String? unit;
  final String? productName;
  final String? stockCode;
  final ProductInfo? product;

  const PurchaseOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.expectedQuantity,
    this.unit,
    this.productName,
    this.stockCode,
    this.product,
  });

  /// Veritabanındaki 'urunler' tablosuyla JOIN yapılmış bir sorgudan nesne oluşturur.
  factory PurchaseOrderItem.fromDbJoinMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      id: map['id'] as int,
      orderId: map['siparis_id'] as int,
      productId: map['urun_id'] as int,
      expectedQuantity: (map['miktar'] as num? ?? 0).toDouble(),
      unit: map['birim'] as String?,
      productName: map['UrunAdi'] as String?,
      stockCode: map['StokKodu'] as String?,
    );
  }

  /// API'den gelen JSON'dan nesne oluşturur.
  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      id: json['id'] as int,
      orderId: json['orderId'] as int,
      productId: json['productId'] as int,
      expectedQuantity: (json['expectedQuantity'] as num).toDouble(),
      unit: json['unit'] as String?,
      productName: json['productName'] as String?,
      stockCode: json['stockCode'] as String?,
      product: json['product'] != null
          ? ProductInfo.fromJson(json['product'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Nesneyi JSON formatına dönüştürür.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'productId': productId,
      'expectedQuantity': expectedQuantity,
      'unit': unit,
      'productName': productName,
      'stockCode': stockCode,
      'product': product?.toJson(),
    };
  }
}

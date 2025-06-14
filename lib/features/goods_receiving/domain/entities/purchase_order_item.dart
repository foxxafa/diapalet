import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:flutter/foundation.dart';

@immutable
class PurchaseOrderItem {
  final int id;
  final int orderId;
  final int productId;
  final double expectedQuantity;
  final double receivedQuantity; // YENİ: Daha önce kabul edilen miktar
  final String? unit;
  final ProductInfo? product;

  const PurchaseOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.expectedQuantity,
    required this.receivedQuantity, // YENİ: Constructor'a eklendi
    this.unit,
    this.product,
  });

  factory PurchaseOrderItem.fromDbJoinMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      id: map['id'] as int,
      orderId: map['siparis_id'] as int,
      productId: map['urun_id'] as int,
      expectedQuantity: (map['miktar'] as num? ?? 0).toDouble(),
      receivedQuantity: (map['receivedQuantity'] as num? ?? 0).toDouble(), // YENİ
      unit: map['birim'] as String?,
      product: ProductInfo(
        id: map['urun_id'] as int,
        name: map['UrunAdi'] as String,
        stockCode: map['StokKodu'] as String,
        barcode1: map['Barcode1'] as String?,
        isActive: (map['aktif'] as int? ?? 1) == 1,
      ),
    );
  }

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    double parseLenientDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return PurchaseOrderItem(
      id: json['id'] as int,
      orderId: json['orderId'] as int,
      productId: json['productId'] as int,
      expectedQuantity: parseLenientDouble(json['expectedQuantity']),
      receivedQuantity: parseLenientDouble(json['receivedQuantity']), // YENİ: JSON'dan parse ediliyor
      unit: json['unit'] as String?,
      product: json['product'] != null
          ? ProductInfo.fromJson(json['product'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'productId': productId,
      'expectedQuantity': expectedQuantity,
      'receivedQuantity': receivedQuantity, // YENİ
      'unit': unit,
      'product': product?.toJson(),
    };
  }
}

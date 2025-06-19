// lib/features/goods_receiving/domain/entities/purchase_order_item.dart
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';

class PurchaseOrderItem {
  final int id;
  final int orderId;
  final int productId;
  final double expectedQuantity;
  final double receivedQuantity;
  final String? unit;
  final ProductInfo product;

  PurchaseOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.expectedQuantity,
    required this.receivedQuantity,
    this.unit,
    required this.product,
  });

  factory PurchaseOrderItem.fromDb(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      id: map['id'] as int,
      orderId: map['siparis_id'] as int,
      productId: map['urun_id'] as int,
      expectedQuantity: (map['miktar'] as num? ?? 0).toDouble(),
      receivedQuantity: (map['receivedQuantity'] as num? ?? 0).toDouble(),
      unit: map['birim'] as String?,
      product: ProductInfo(
        id: map['urun_id'] as int,
        // HATA DÜZELTMESİ: Nullable string ataması, boş string varsayılanı ile düzeltildi.
        name: map['UrunAdi'] as String? ?? '',
        stockCode: map['StokKodu'] as String? ?? '',
        barcode1: map['Barcode1'] as String?,
        isActive: (map['aktif'] as int? ?? 0) == 1,
      ),
    );
  }

  // HATA DÜZELTMESİ: Eksik JSON metotları eklendi.
  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      id: json['id'],
      orderId: json['orderId'],
      productId: json['productId'],
      expectedQuantity: (json['expectedQuantity'] as num).toDouble(),
      receivedQuantity: (json['receivedQuantity'] as num).toDouble(),
      unit: json['unit'],
      product: ProductInfo.fromJson(json['product']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'productId': productId,
      'expectedQuantity': expectedQuantity,
      'receivedQuantity': receivedQuantity,
      'unit': unit,
      'product': product.toJson(),
    };
  }
}

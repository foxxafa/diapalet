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
  // DÜZELTME: Alanın türü, ilgili modülün kendi sınıfı olan 'ProductInfo' olarak güncellendi.
  final ProductInfo? product;

  PurchaseOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.expectedQuantity,
    required this.receivedQuantity,
    required this.transferredQuantity,
    this.unit,
    required this.product,
  });

  /// Veritabanından gelen Map verisini parse eder.
  factory PurchaseOrderItem.fromDb(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      id: map['id'] as int,
      orderId: map['siparis_id'] as int,
      productId: map['urun_id'] as int,
      expectedQuantity: (map['miktar'] as num? ?? 0).toDouble(),
      receivedQuantity: (map['receivedQuantity'] as num? ?? 0).toDouble(),
      transferredQuantity: (map['transferredQuantity'] as num? ?? 0).toDouble(),
      unit: map['birim'] as String?,
      // DÜZELTME: Artık 'ProductInfo' nesnesi oluşturuluyor.
      product: ProductInfo(
        id: map['urun_id'] as int,
        name: map['UrunAdi'] as String? ?? 'Bilinmeyen Ürün',
        stockCode: map['StokKodu'] as String? ?? '---',
        barcode1: map['Barcode1'] as String?,
        isActive: (map['aktif'] as int? ?? 1) == 1,
      ),
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
      // DÜZELTME: Artık 'ProductInfo.fromJson' çağrılıyor.
      product: json['product'] != null ? ProductInfo.fromJson(json['product']) : null,
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
    };
  }
}

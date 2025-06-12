import 'package:flutter/foundation.dart';

/// Bir palete atanan bir ürün kalemini temsil eder.
/// Sunucu tarafında 'mal_kabul_palet_icerik' gibi bir ilişki tablosuna karşılık gelebilir.
@immutable
class PalletItem {
  final String productId; // 'urunler.UrunId'
  final String stockCode; // 'urunler.StokKodu'
  final double quantity;  // Bu palete eklenen miktar

  const PalletItem({
    required this.productId,
    required this.stockCode,
    required this.quantity,
  });

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'stock_code': stockCode,
      'quantity': quantity,
    };
  }

  factory PalletItem.fromJson(Map<String, dynamic> json) {
    return PalletItem(
      productId: json['product_id'],
      stockCode: json['stock_code'],
      quantity: (json['quantity'] as num).toDouble(),
    );
  }
} 
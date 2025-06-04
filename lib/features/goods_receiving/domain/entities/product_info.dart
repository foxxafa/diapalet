// lib/features/goods_receiving/domain/entities/product_info.dart
// Bu dosya önceki haliyle kalabilir, ürün seçimi için kullanılacak.
// Eğer ürünler sadece isim olarak tutulacaksa basitleştirilebilir.
// Şimdilik mevcut ProductInfo yapısını kullanıyoruz.

/// Represents basic information about a product, typically fetched by barcode.
class ProductInfo {
  final String id; // Benzersiz bir ürün ID'si eklendi
  final String name;
  final String stockCode;

  ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
  });

  // Factory constructor for creating a new ProductInfo instance from a map.
  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      stockCode: json['stockCode'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stockCode': stockCode,
    };
  }

  static ProductInfo empty = ProductInfo(id: '', name: '', stockCode: '');

  @override
  String toString() {
    return 'ProductInfo(id: $id, name: $name, stockCode: $stockCode)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ProductInfo &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}

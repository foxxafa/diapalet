// lib/features/goods_receiving/domain/entities/product_info.dart

/// Represents basic information about a product, typically fetched by barcode.
class ProductInfo {
  final String name;
  final String stockCode;
  // final String? defaultUnit; // Optional: could be useful

  ProductInfo({
    required this.name,
    required this.stockCode,
    // this.defaultUnit,
  });

  // Factory constructor for creating a new ProductInfo instance from a map.
  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      name: json['name'] as String,
      stockCode: json['stockCode'] as String,
      // defaultUnit: json['defaultUnit'] as String?,
    );
  }

  // Method for converting a ProductInfo instance to a map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'stockCode': stockCode,
      // 'defaultUnit': defaultUnit,
    };
  }

  // An empty product info, useful for initial states or when no product is found.
  static ProductInfo empty = ProductInfo(name: '', stockCode: '');

  @override
  String toString() {
    return 'ProductInfo(name: $name, stockCode: $stockCode)';
  }
}

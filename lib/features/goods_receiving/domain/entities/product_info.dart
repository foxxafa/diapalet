// features/goods_receiving/domain/entities/product_info.dart
class ProductInfo {
  final String id;
  final String name;
  final String stockCode;

  ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
  });

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'].toString(),
      name: json['name'] as String,
      stockCode: json['code'] as String,
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

// features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id;
  final String name;
  final String stockCode;

  const ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
  });

  @override
  List<Object?> get props => [id, name, stockCode];

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
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

  static ProductInfo empty = ProductInfo(id: 0, name: '', stockCode: '');

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

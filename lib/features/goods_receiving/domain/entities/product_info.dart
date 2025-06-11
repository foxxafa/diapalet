// features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id;
  final String name;
  final String stockCode;
  final bool isActive;

  const ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
    required this.isActive,
  });

  @override
  List<Object?> get props => [id, name, stockCode, isActive];

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      stockCode: json['code'] as String,
      isActive: json['isActive'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stockCode': stockCode,
      'isActive': isActive,
    };
  }

  static const ProductInfo empty = ProductInfo(id: 0, name: '', stockCode: '', isActive: false);

  @override
  String toString() {
    return 'ProductInfo(id: $id, name: $name, stockCode: $stockCode, isActive: $isActive)';
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

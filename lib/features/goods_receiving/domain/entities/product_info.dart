// features/goods_receiving/domain/entities/product_info.dart
import 'package:equatable/equatable.dart';

class ProductInfo extends Equatable {
  final int id;
  final String name;
  final String stockCode;
  final bool isActive;
  final bool isSerialized;

  const ProductInfo({
    required this.id,
    required this.name,
    required this.stockCode,
    required this.isActive,
    this.isSerialized = false,
  });

  factory ProductInfo.fromMap(Map<String, dynamic> map) {
    return ProductInfo(
      id: map['id'] as int,
      name: map['name'] as String,
      stockCode: map['code'] as String,
      isActive: map['is_active'] as bool? ?? true,
      isSerialized: map['is_serialized'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, name, stockCode, isActive, isSerialized];

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      stockCode: json['code'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isSerialized: json['is_serialized'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stockCode': stockCode,
      'isActive': isActive,
      'isSerialized': isSerialized,
    };
  }

  static const ProductInfo empty = ProductInfo(id: 0, name: '', stockCode: '', isActive: false, isSerialized: false);

  @override
  String toString() {
    return 'ProductInfo(id: $id, name: $name, stockCode: $stockCode, isActive: $isActive, isSerialized: $isSerialized)';
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

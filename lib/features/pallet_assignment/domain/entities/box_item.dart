// lib/features/pallet_assignment/domain/entities/box_item.dart
import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

@immutable
class BoxItem extends Equatable {
  final int boxId;
  final int productId;
  final String productName;
  final String productCode;
  final int quantity;

  const BoxItem({
    required this.boxId,
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
  });

  @override
  List<Object> get props => [boxId, productId, productName, productCode, quantity];

  factory BoxItem.fromMap(Map<String, dynamic> map) {
    return BoxItem(
      boxId: map['box_id'] as int,
      productId: map['urun_id'] as int,
      productName: (map['product_name'] ?? '').toString(),
      productCode: (map['product_code'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
    );
  }
}

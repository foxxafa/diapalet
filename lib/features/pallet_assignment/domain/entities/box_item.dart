// lib/features/pallet_assignment/domain/entities/box_item.dart
import 'package:flutter/foundation.dart';

@immutable
class BoxItem {
  final int boxId;
  final String productId;
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
}

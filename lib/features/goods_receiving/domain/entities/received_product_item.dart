// lib/features/goods_receiving/domain/entities/received_product_item.dart

import 'package:intl/intl.dart';
import 'product_info.dart';

/// Represents an item that has been processed in the goods receiving screen.
class ReceivedProductItem {
  final String barcode; // Store the scanned barcode
  final ProductInfo productInfo;
  final DateTime expirationDate;
  final String trackingNumber;
  final int quantity;
  final String unit;

  ReceivedProductItem({
    required this.barcode,
    required this.productInfo,
    required this.expirationDate,
    required this.trackingNumber,
    required this.quantity,
    required this.unit,
  });

  String get formattedExpirationDate {
    return DateFormat('dd.MM.yyyy').format(expirationDate);
  }

  @override
  String toString() {
    return 'ReceivedProductItem(barcode: $barcode, productInfo: ${productInfo.name}, expirationDate: $formattedExpirationDate, trackingNumber: $trackingNumber, quantity: $quantity, unit: $unit)';
  }
}

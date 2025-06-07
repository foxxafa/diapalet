//features/goods_receiving/domain/entities/goods_receipt_log_item.dart
import 'product_info.dart';


class GoodsReceiptLogItem {
  final String invoice;
  final String location;
  final ProductInfo product;
  final int quantity;

  GoodsReceiptLogItem({
    required this.invoice,
    required this.location,
    required this.product,
    required this.quantity,
  });

  @override
  String toString() {
    return 'GoodsReceiptLogItem(invoice: $invoice, location: $location, product: ${product.name}, quantity: $quantity)';
  }
}

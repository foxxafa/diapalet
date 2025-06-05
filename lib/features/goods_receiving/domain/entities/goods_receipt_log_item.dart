//features/goods_receiving/domain/entities/goods_receipt_log_item.dart
import 'product_info.dart';

enum ReceiveMode { palet, kutu }

extension ReceiveModeExtension on ReceiveMode {
  String get displayName {
    switch (this) {
      case ReceiveMode.palet:
        return 'Palet';
      case ReceiveMode.kutu:
        return 'Kutu';
    // The default case was removed as it's unreachable
    // because all enum values are explicitly handled.
    }
  }
}


class GoodsReceiptLogItem {
  final ReceiveMode mode;
  final String invoice;
  final String palletOrBoxId;
  final ProductInfo product;
  final int quantity;

  GoodsReceiptLogItem({
    required this.mode,
    required this.invoice,
    required this.palletOrBoxId,
    required this.product,
    required this.quantity,
  });

  @override
  String toString() {
    return 'GoodsReceiptLogItem(mode: ${mode.displayName}, invoice: $invoice, palletOrBoxId: $palletOrBoxId, product: ${product.name}, quantity: $quantity)';
  }
}

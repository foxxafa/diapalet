import 'product_info.dart';

enum ReceiveMode { palet, kutu }

extension ReceiveModeExtension on ReceiveMode {
  String get displayName {
    switch (this) {
      case ReceiveMode.palet:
        return 'Palet';
      case ReceiveMode.kutu:
        return 'Kutu';
      default:
        return '';
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

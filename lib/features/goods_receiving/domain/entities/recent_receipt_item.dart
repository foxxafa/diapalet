import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';

class RecentReceiptItem {
  final int id;
  final String productName;
  final double quantity;
  final String? palletBarcode;
  final String createdAt;

  RecentReceiptItem({
    required this.id,
    required this.productName,
    required this.quantity,
    this.palletBarcode,
    required this.createdAt,
  });

  factory RecentReceiptItem.fromMap(Map<String, dynamic> map) {
    return RecentReceiptItem(
      id: map['id'] as int,
      productName: map['productName'] as String,
      quantity: (map['quantity_received'] as num).toDouble(),
      palletBarcode: map['pallet_barcode'] as String?,
      createdAt: map['created_at'] as String,
    );
  }
}

class ReceiptItemDraft {
  final ProductInfo product;
  final double quantity;
  final String? palletBarcode;

  ReceiptItemDraft({
    required this.product,
    required this.quantity,
    this.palletBarcode,
  });
}
// features/goods_receiving/domain/entities/goods_receipt_entities.dart
import 'package:uuid/uuid.dart';
import 'product_info.dart';

// Mode concept removed; receipts simply track products at locations

class GoodsReceipt {
  final int id;
  final int purchaseOrderId;
  final String receiptNumber;
  final DateTime receiptDate;
  final String? notes;
  final String status;
  final List<GoodsReceiptItem> items;

  GoodsReceipt({
    required this.id,
    required this.purchaseOrderId,
    required this.receiptNumber,
    required this.receiptDate,
    this.notes,
    required this.status,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'purchase_order_id': purchaseOrderId,
        'receipt_number': receiptNumber,
        'receipt_date': receiptDate.toIso8601String(),
        'notes': notes,
        'status': status,
      };
}

class GoodsReceiptItem {
  final int id;
  final int goodsReceiptId;
  final int productId;
  final double quantity;
  final String? notes;

  GoodsReceiptItem({
    required this.id,
    required this.goodsReceiptId,
    required this.productId,
    required this.quantity,
    this.notes,
  });

  GoodsReceiptItem copyWith({
    int? id,
    int? goodsReceiptId,
    int? productId,
    double? quantity,
    String? notes,
  }) {
    return GoodsReceiptItem(
      id: id ?? this.id,
      goodsReceiptId: goodsReceiptId ?? this.goodsReceiptId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'goods_receipt_id': goodsReceiptId,
        'product_id': productId,
        'quantity': quantity,
        'notes': notes,
      };
}

// features/goods_receiving/domain/entities/goods_receipt_entities.dart
import 'package:uuid/uuid.dart';
import 'package:easy_localization/easy_localization.dart';
import 'product_info.dart';

enum ReceiveMode { palet, kutu }

extension ReceiveModeExtension on ReceiveMode {
  String get displayName => tr('receive_mode.$name');
}

class GoodsReceipt {
  final int? id;
  final String externalId;
  final String invoiceNumber;
  final DateTime receiptDate;
  final ReceiveMode mode;
  int synced;

  GoodsReceipt({
    this.id,
    String? externalId,
    required this.invoiceNumber,
    required this.receiptDate,
    required this.mode,
    this.synced = 0,
  }) : externalId = externalId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'external_id': externalId,
      'invoice_number': invoiceNumber,
      'receipt_date': receiptDate.toIso8601String(),
      'mode': mode.name,
      'synced': synced,
    };
  }

  factory GoodsReceipt.fromMap(Map<String, dynamic> map) {
    return GoodsReceipt(
      id: map['id'] as int?,
      externalId: map['external_id'] as String? ?? const Uuid().v4(),
      invoiceNumber: map['invoice_number'] as String,
      receiptDate: DateTime.parse(map['receipt_date'] as String),
      mode: ReceiveMode.values.firstWhere(
            (e) => e.name == map['mode'],
        orElse: () => ReceiveMode.palet,
      ),
      synced: map['synced'] as int? ?? 0,
    );
  }
}

class GoodsReceiptItem {
  final int? id;
  final int goodsReceiptId;
  final String palletOrBoxId;
  final ProductInfo product;
  final int quantity;

  GoodsReceiptItem({
    this.id,
    required this.goodsReceiptId,
    required this.palletOrBoxId,
    required this.product,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_id': goodsReceiptId,
      'pallet_or_box_id': palletOrBoxId,
      'product_id': product.id,
      'product_name': product.name,
      'product_code': product.stockCode,
      'quantity': quantity,
    };
  }

  // fromMap metodu productInfo'nun dışarıdan sağlanmasını bekliyordu.
  // Eğer product_id, product_name, product_code map içinde geliyorsa,
  // doğrudan ProductInfo oluşturabiliriz.
  factory GoodsReceiptItem.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptItem(
      id: map['id'] as int?,
      goodsReceiptId: map['receipt_id'] as int,
      palletOrBoxId: map['pallet_or_box_id'] as String,
      product: ProductInfo(
        id: map['product_id'] as String,
        name: map['product_name'] as String,
        stockCode: map['product_code'] as String,
      ),
      quantity: map['quantity'] as int,
    );
  }
}

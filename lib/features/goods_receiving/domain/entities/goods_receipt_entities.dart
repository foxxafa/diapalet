// lib/features/goods_receiving/domain/entities/goods_receipt_entities.dart
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:flutter/foundation.dart';

/// Mal kabul işleminin türünü belirtir.
enum ReceivingMode {
  palet,
  kutu,
}

/// Kullanıcının UI'da listeye eklediği tek bir mal kabul kalemini temsil eder.
/// Bu, henüz veritabanına kaydedilmemiş geçici bir modeldir.
@immutable
class ReceiptItemDraft {
  final ProductInfo product;
  final double quantity;

  /// Sadece palet modunda kullanılır.
  final String? palletBarcode;

  const ReceiptItemDraft({
    required this.product,
    required this.quantity,
    this.palletBarcode,
  });
}

/// Hem API'ye gönderilecek hem de lokal veritabanına (pending_operations)
/// kaydedilecek olan mal kabul işleminin tamamını temsil eden model.
@immutable
class GoodsReceiptPayload {
  final GoodsReceiptHeader header;
  final List<GoodsReceiptItemPayload> items;

  const GoodsReceiptPayload({
    required this.header,
    required this.items,
  });

  /// API'ye gönderilmek üzere JSON formatına dönüştürür.
  /// Bu yapı, Flask sunucusunun beklediği payload ile eşleşir.
  Map<String, dynamic> toApiJson() {
    return {
      'header': header.toJson(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

@immutable
class GoodsReceiptHeader {
  final int? siparisId;
  final String? invoiceNumber;
  final int? employeeId; // Gelecekte eklenebilir
  final DateTime receiptDate;

  const GoodsReceiptHeader({
    this.siparisId,
    this.invoiceNumber,
    this.employeeId,
    required this.receiptDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'siparis_id': siparisId,
      'invoice_number': invoiceNumber,
      'employee_id': employeeId,
      'receipt_date': receiptDate.toIso8601String(),
    };
  }
}

@immutable
class GoodsReceiptItemPayload {
  final int urunId;
  final double quantity;
  final String? palletBarcode;

  const GoodsReceiptItemPayload({
    required this.urunId,
    required this.quantity,
    this.palletBarcode,
  });

  Map<String, dynamic> toJson() {
    return {
      'urun_id': urunId,
      'quantity': quantity,
      'pallet_barcode': palletBarcode,
    };
  }
}

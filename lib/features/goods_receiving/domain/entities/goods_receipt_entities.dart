// lib/features/goods_receiving/domain/entities/goods_receipt_entities.dart
import 'package:flutter/foundation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';

// Not: Bu dosya, sunucuya gönderilecek ve UI'da kullanılacak veri yapılarını netleştirir.

@immutable
class GoodsReceiptPayload {
  final GoodsReceiptHeader header;
  final List<GoodsReceiptItemPayload> items;

  const GoodsReceiptPayload({required this.header, required this.items});

  /// Sunucuya gönderilecek JSON formatını oluşturur.
  Map<String, dynamic> toApiJson() => {
    'header': header.toJson(),
    'items': items.map((item) => item.toJson()).toList(),
  };
}

@immutable
class GoodsReceiptHeader {
  final int? siparisId;
  final String? invoiceNumber;
  final String? deliveryNoteNumber;
  final int employeeId; // <-- Sunucunun istediği zorunlu alan
  final DateTime receiptDate;

  const GoodsReceiptHeader({
    this.siparisId,
    this.invoiceNumber,
    this.deliveryNoteNumber,
    required this.employeeId, // Null olmaması için zorunlu hale getirildi
    required this.receiptDate,
  });

  Map<String, dynamic> toJson() => {
    'siparis_id': siparisId,
    'invoice_number': invoiceNumber,
    'delivery_note_number': deliveryNoteNumber,
    'employee_id': employeeId,
    'receipt_date': receiptDate.toIso8601String(),
  };
}

@immutable
class GoodsReceiptItemPayload {
  final String productId; // _key değeri string olarak
  final double quantity;
  final String? palletBarcode;
  final DateTime? expiryDate;

  const GoodsReceiptItemPayload({
    required this.productId,
    required this.quantity,
    this.palletBarcode,
    this.expiryDate,
  });

  Map<String, dynamic> toJson() => {
    'urun_key': productId, // _key değeri urun_key alanına gönderiliyor
    'quantity': quantity,
    'pallet_barcode': palletBarcode,
    'expiry_date': expiryDate?.toIso8601String(),
  };
}


// --- Arayüzde kullanılan geçici veri sınıfları ---

/// Mal kabul ekranındaki modları temsil eder.
enum ReceivingMode { palet, product }

/// Arayüzde listeye eklenen her bir kalemi temsil eden taslak sınıf.
@immutable
class ReceiptItemDraft {
  final ProductInfo product;
  final double quantity;
  final String? palletBarcode;
  final DateTime? expiryDate;

  const ReceiptItemDraft({
    required this.product,
    required this.quantity,
    this.palletBarcode,
    this.expiryDate,
  });
}

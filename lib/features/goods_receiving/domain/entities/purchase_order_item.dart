import 'package:flutter/foundation.dart';

/// Satin alma siparişinin bir kalemini (satırını) temsil eder.
/// Bu model, 'satin_alma_siparis_fis_satir' tablosundaki verilerle eşleşir.
@immutable
class PurchaseOrderItem {
  final int id; // 'satin_alma_siparis_fis_satir.id'
  final int orderId; // 'satin_alma_siparis_fis_satir.siparis_id'
  final int productId; // 'satin_alma_siparis_fis_satir.urun_id'
  final double expectedQuantity; // 'satin_alma_siparis_fis_satir.miktar'
  final String? unit; // 'satin_alma_siparis_fis_satir.birim'
  final String? notes; // 'satin_alma_siparis_fis_satir.notes'

  // 'urunler' tablosundan JOIN ile alınacak ek bilgiler
  final String? productName;
  final String? stockCode;
  final String? barcode;
  final int? itemsPerBox; // 'urunler.qty' (Kutu içi adet)
  final int? itemsPerPallet; // 'urunler.palletqty' (Palet içi adet)

  const PurchaseOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.expectedQuantity,
    this.unit,
    this.notes,
    this.productName,
    this.stockCode,
    this.barcode,
    this.itemsPerBox,
    this.itemsPerPallet,
  });

  // JSON'dan model oluşturma
  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      id: json['id'],
      orderId: json['siparis_id'],
      productId: json['urun_id'],
      expectedQuantity: (json['miktar'] as num).toDouble(),
      unit: json['birim'],
      notes: json['notes'],
      // JOIN ile gelen ürün bilgileri
      productName: json['urun_adi'],
      stockCode: json['stok_kodu'],
      barcode: json['barcode1'], // Veya hangi barkod alanı kullanılacaksa
      itemsPerBox: json['qty'],
      itemsPerPallet: json['palletqty'],
    );
  }

  // Modelden JSON oluşturma
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'siparis_id': orderId,
      'urun_id': productId,
      'miktar': expectedQuantity,
      'birim': unit,
      'notes': notes,
      'urun_adi': productName,
      'stok_kodu': stockCode,
      'barcode1': barcode,
      'qty': itemsPerBox,
      'palletqty': itemsPerPallet,
    };
  }
} 
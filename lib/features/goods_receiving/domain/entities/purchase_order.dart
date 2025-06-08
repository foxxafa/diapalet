import 'package:flutter/foundation.dart';

/// Satin alma siparişinin ana bilgilerini temsil eder.
/// Bu model, 'satin_alma_siparis_fis' tablosundaki verilerle eşleşir.
@immutable
class PurchaseOrder {
  final int id; // 'satin_alma_siparis_fis.id'
  final String? poId; // 'satin_alma_siparis_fis.po_id' - Tedarikçinin sipariş numarası
  final DateTime? date; // 'satin_alma_siparis_fis.tarih'
  final String? notes; // 'satin_alma_siparis_fis.notlar'
  final int? status; // 'satin_alma_siparis_fis.status' (0: Açık, 1: Kısmi, 2: Kapalı)
  final String? supplierName; // 'tedarikci.tedarikci_adi' (JOIN ile alınacak)
  final int? supplierId; // 'tedarikci.id' (JOIN için)

  const PurchaseOrder({
    required this.id,
    this.poId,
    this.date,
    this.notes,
    this.status,
    this.supplierName,
    this.supplierId,
  });

  // JSON'dan model oluşturma (API'den gelen veri için)
  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['id'],
      poId: json['po_id'],
      date: json['tarih'] != null ? DateTime.parse(json['tarih']) : null,
      notes: json['notlar'],
      status: json['status'],
      supplierName: json['tedarikci_adi'], // JOIN sonucu
      supplierId: json['tedarikci_id'],   // JOIN sonucu
    );
  }

  // Modelden JSON oluşturma (Lokal depolama için)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'po_id': poId,
      'tarih': date?.toIso8601String(),
      'notlar': notes,
      'status': status,
      'tedarikci_adi': supplierName,
      'tedarikci_id': supplierId,
    };
  }
} 
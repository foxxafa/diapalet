import 'package:flutter/foundation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';

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
  final List<PurchaseOrderItem> items;

  const PurchaseOrder({
    required this.id,
    this.poId,
    this.date,
    this.notes,
    this.status,
    this.supplierName,
    this.supplierId,
    required this.items,
  });

  // JSON'dan model oluşturma (API'den gelen veri için)
  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    // Flask tarafında alan adları "po_id", "poId" veya "purchaseOrderNumber" gibi 
    // farklı biçimlerde gelebilir. Tüm olasılıkları kontrol edip ilk bulunanı kullanıyoruz.
    final dynamic rawPoId = json['po_id'] ?? json['poId'] ?? json['purchaseOrderNumber'];

    var itemsList = <PurchaseOrderItem>[];
    if (json['items'] != null) {
      itemsList = (json['items'] as List)
          .map((item) => PurchaseOrderItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return PurchaseOrder(
      id: json['id'] as int,
      poId: rawPoId?.toString(),
      date: json['tarih'] != null ? DateTime.parse(json['tarih']) : (json['date'] != null ? DateTime.parse(json['date']) : null),
      notes: json['notlar'] ?? json['notes'],
      status: json['status'] as int?,
      supplierName: json['tedarikci_adi'] ?? json['supplierName'], // JOIN sonucu
      supplierId: json['tedarikci_id'] ?? json['supplierId'],   // JOIN sonucu
      items: itemsList,
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
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  // Lokal DB'den (map) model oluşturma
  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    // Veritabanı sütun adları `toJson` metodundaki anahtarlarla eşleşmelidir.
    return PurchaseOrder(
      id: map['id'] as int,
      poId: map['po_id'] as String?,
      // Tarih alanı string olarak saklanıyorsa parse edilir.
      date: map['tarih'] != null ? DateTime.tryParse(map['tarih']) : null,
      notes: map['notlar'] as String?,
      status: map['status'] as int?,
      // Bu alanlar genellikle JOIN ile doldurulur, lokalde olmayabilir.
      supplierName: map['tedarikci_adi'] as String?,
      supplierId: map['tedarikci_id'] as int?,
      items: const [], // items field is not provided in the map, so we'll keep it empty
    );
  }
} 
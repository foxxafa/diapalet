// lib/features/goods_receiving/domain/entities/purchase_order.dart
import 'package:flutter/foundation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';

@immutable
class PurchaseOrder {
  final int id;
  final String? poId; // Purchase Order ID
  final DateTime? date;
  final String? notes;
  final int? status;
  final String? supplierName; // Bu alan şu anki API'de yok, ileride eklenebilir.
  final List<PurchaseOrderItem> items;

  const PurchaseOrder({
    required this.id,
    this.poId,
    this.date,
    this.notes,
    this.status,
    this.supplierName,
    this.items = const [],
  });

  /// Lokal DB'den (map) model oluşturma.
  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    return PurchaseOrder(
      id: map['id'] as int,
      poId: map['po_id'] as String?,
      date: map['tarih'] != null ? DateTime.tryParse(map['tarih']) : null,
      notes: map['notlar'] as String?,
      // ANA DÜZELTME: Sunucudan gelen `status` alanı burada doğru bir şekilde okunuyor.
      status: map['status'] as int?,
      supplierName: map['supplierName'] as String?,
    );
  }

  /// API'den gelen JSON verisinden model oluşturma.
  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    var itemsList = <PurchaseOrderItem>[];
    if (json['items'] != null) {
      itemsList = (json['items'] as List)
          .map((item) => PurchaseOrderItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return PurchaseOrder(
      id: json['id'] as int,
      poId: json['po_id'] as String? ?? json['poId'] as String?,
      date: json['tarih'] != null ? DateTime.tryParse(json['tarih']) :
      (json['date'] != null ? DateTime.parse(json['date']) : null),
      notes: json['notes'] as String?,
      status: json['status'] as int?,
      supplierName: json['supplierName'] as String?,
      items: itemsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'poId': poId,
      'date': date?.toIso8601String(),
      'notes': notes,
      'status': status,
      'supplierName': supplierName,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

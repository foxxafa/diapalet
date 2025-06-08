/// Sunucuya gönderilecek mal kabul verilerini temsil eden model.
class GoodsReceiptPayload {
  final int purchaseOrderId;
  final String acceptedBy; // user id or name
  final DateTime acceptanceDate;
  final List<GoodsReceiptItemPayload> items;

  GoodsReceiptPayload({
    required this.purchaseOrderId,
    required this.acceptedBy,
    required this.acceptanceDate,
    required this.items,
  });

  Map<String, dynamic> toJson() {
    return {
      'siparis_id': purchaseOrderId,
      'kabul_eden_kullanici': acceptedBy,
      'kabul_tarihi': acceptanceDate.toIso8601String(),
      'kalemler': items.map((item) => item.toJson()).toList(),
    };
  }
}

/// Mal kabulü yapılan bir kalemin detaylarını içerir.
class GoodsReceiptItemPayload {
  final int orderItemId; // Hangi sipariş kalemine ait olduğu
  final int productId;
  final double acceptedQuantity;
  final String unit;
  final String? palletId; // Opsiyonel: Eğer bir palete atandıysa

  GoodsReceiptItemPayload({
    required this.orderItemId,
    required this.productId,
    required this.acceptedQuantity,
    required this.unit,
    this.palletId,
  });

  Map<String, dynamic> toJson() {
    return {
      'siparis_satir_id': orderItemId,
      'urun_id': productId,
      'kabul_edilen_miktar': acceptedQuantity,
      'birim': unit,
      'palet_id': palletId,
    };
  }
} 
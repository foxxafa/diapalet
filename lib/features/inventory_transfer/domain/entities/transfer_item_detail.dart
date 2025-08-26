// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart

class TransferItemDetail {
  final String productId; // _key değeri string olarak
  final String productName;
  final String productCode;
  final double quantity;

  // --- GÜNCELLEME BAŞLANGICI ---
  // İki ayrı palet alanı yerine, tek ve net bir alan kullanıldı.
  // Bu alan hem serbest transferde hem de sipariş bazlı transferde
  // kaynak paleti belirtmek için kullanılır.
  final String? palletId;
  final DateTime? expiryDate;
  // --- GÜNCELLEME SONU ---

  // Arayüzde (sepet) kullanılacak ve işlem sırasında gruplama için gerekli bilgiler
  final int? targetLocationId;
  final String? targetLocationName;

  TransferItemDetail({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.palletId,
    this.expiryDate,
    this.targetLocationId,
    this.targetLocationName,
  });

  /// Sunucuya gönderilecek olan, sadeleştirilmiş JSON formatını oluşturur.
  /// _key değeri urun_id alanına gönderilir
  Map<String, dynamic> toApiJson() {
    return {
      'urun_id': productId, // _key değeri urun_id alanına gönderiliyor (sunucu bu alanda bekliyor)
      'quantity': quantity,
      'pallet_id': palletId,
      'expiry_date': expiryDate?.toIso8601String(),
    };
  }
}
// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart

class TransferItemDetail {
  final String productKey; // _key değeri
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
    required this.productKey,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.palletId,
    this.expiryDate,
    this.targetLocationId,
    this.targetLocationName,
  });

  /// Sunucuya gönderilecek olan, sadeleştirilmiş JSON formatını oluşturur.
  Map<String, dynamic> toApiJson() {
    return {
      'urun_key': productKey, // _key değeri
      'quantity': quantity,
      'pallet_id': palletId,
      'expiry_date': expiryDate?.toIso8601String(),
    };
  }
}
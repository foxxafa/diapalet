// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart

class TransferItemDetail {
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;

  // --- GÜNCELLEME BAŞLANGICI ---
  // İki ayrı palet alanı yerine, tek ve net bir alan kullanıldı.
  // Bu alan hem serbest transferde hem de sipariş bazlı transferde
  // kaynak paleti belirtmek için kullanılır.
  final String? palletId;
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
    this.targetLocationId,
    this.targetLocationName,
  });

  /// Sunucuya gönderilecek olan, sadeleştirilmiş JSON formatını oluşturur.
  Map<String, dynamic> toApiJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'pallet_id': palletId,
    };
  }
}
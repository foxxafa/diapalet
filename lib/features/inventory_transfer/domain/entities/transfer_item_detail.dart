// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart

class TransferItemDetail {
  final String productKey; // _key değeri
  final String? birimKey; // Birim _key değeri
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

  // KRITIK FIX: Transfer sonrası oluşacak stock kaydının UUID'si
  final String? stockUuid; // Phone-generated UUID

  // Arayüzde (sepet) kullanılacak ve işlem sırasında gruplama için gerekli bilgiler
  final int? targetLocationId;
  final String? targetLocationName;

  TransferItemDetail({
    required this.productKey,
    this.birimKey,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.palletId,
    this.expiryDate,
    this.stockUuid, // UUID field eklendi
    this.targetLocationId,
    this.targetLocationName,
  });

  /// Sunucuya gönderilecek olan, sadeleştirilmiş JSON formatını oluşturur.
  Map<String, dynamic> toApiJson() {
    // KRITIK FIX: expiry_date'i normalize et - sadece date, time yok (YYYY-MM-DD)
    final expiryDateStr = expiryDate != null
        ? DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day)
            .toIso8601String()
            .split('T')[0]
        : null;

    return {
      'urun_key': productKey, // _key değeri
      'birim_key': birimKey, // Birim _key değeri
      'quantity': quantity,
      'pallet_id': palletId,
      'expiry_date': expiryDateStr, // KRITIK FIX: Normalized format (YYYY-MM-DD)
      'stock_uuid': stockUuid, // KRITIK FIX: Phone-generated UUID'yi sunucuya gönder
    };
  }
}
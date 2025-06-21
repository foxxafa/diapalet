// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart

class TransferItemDetail {
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;

  // Transferin kaynağıyla ilgili bilgiler
  final String? palletId; // Serbest transferde palet ID'si
  final String? sourcePalletBarcode; // Serbest transferde kaynak palet

  // Arayüzde (sepet) kullanılacak ve işlem sırasında gruplama için gerekli bilgiler
  final int? targetLocationId;
  final String targetLocationName;

  TransferItemDetail({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.palletId,
    this.sourcePalletBarcode,
    // Bu alanlar artık zorunlu
    required this.targetLocationId,
    required this.targetLocationName,
  });

  /// Sunucuya gönderilecek olan, sadeleştirilmiş JSON formatını oluşturur.
  Map<String, dynamic> toApiJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      // API, operasyon tipine göre bu palet ID'sini farklı yorumlayabilir.
      // Bu mantık repository katmanında yönetilir.
      'pallet_id': palletId,
    };
  }
}

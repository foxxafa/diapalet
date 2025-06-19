// lib/features/inventory_transfer/domain/entities/transfer_item_detail.dart

class TransferItemDetail {
  final int productId;
  final String productName; // HATA DÜZELTMESİ: UI'da kullanılmak üzere eklendi.
  final String productCode; // HATA DÜZELTMESİ: UI'da kullanılmak üzere eklendi.
  final double quantity;
  final String? palletId;
  final String? sourcePalletBarcode;

  TransferItemDetail({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.palletId,
    this.sourcePalletBarcode,
  });

  Map<String, dynamic> toApiJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'pallet_id': palletId,
    };
  }
}

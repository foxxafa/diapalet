// lib/features/inventory_transfer/domain/entities/transferable_container.dart

import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';

/// Arayüzde gösterilecek olan, transfer edilebilir bir konteyneri (palet veya paletsiz ürün grubu) temsil eder.
class TransferableContainer {
  /// Konteynerin benzersiz kimliği. Paletler için barkod, paletsizler için "PALETSIZ_{urunId}".
  final String id;

  /// Arayüzde gösterilecek adı. Örn: "Palet: TEST-01" veya "Paletsiz: Süt 1 LT".
  final String displayName;

  /// Bu konteynerin içinde bulunan, transfer edilebilir ürünler ve miktarları.
  final List<TransferableItem> items;

  TransferableContainer({
    required this.id,
    required this.displayName,
    required this.items,
  });
}

/// Bir konteynerin içindeki tek bir ürün kalemini ve transfer edilebilir miktarını temsil eder.
class TransferableItem {
  /// Ürün bilgileri.
  final ProductInfo product;

  /// Bu konteyner içinde kalan ve transfer edilebilir miktar.
  final double quantity;

  /// Ürünün kaynak paleti (eğer bir paletten geliyorsa).
  final String? sourcePalletBarcode;

  final DateTime? expiryDate;

  TransferableItem({
    required this.product,
    required this.quantity,
    this.sourcePalletBarcode,
    this.expiryDate,
  });
}
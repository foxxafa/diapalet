// lib/features/inventory_transfer/domain/entities/transferable_container.dart

import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Farklı türdeki (palet veya kutu grubu) transfer edilebilir birimleri temsil eden genel bir sınıf.
@immutable
class TransferableContainer {
  /// Konteynerin benzersiz ID'si. Bu, bir palet barkodu veya
  /// paletsiz ürünler için yapay olarak oluşturulmuş bir ID olabilir.
  final String id;

  /// Bu konteynerin bir palet olup olmadığını belirtir.
  final bool isPallet;

  /// Konteynerin içindeki ürün kalemleri.
  final List<TransferableItem> items;

  const TransferableContainer({
    required this.id,
    required this.isPallet,
    required this.items,
  });

  /// Arayüzde gösterilecek adı döndürür.
  String get displayName {
    if (isPallet) {
      return id;
    } else {
      // Paletsiz ürünler için daha açıklayıcı bir isim oluştur.
      if (items.isNotEmpty) {
        final firstItem = items.first;
        final expiryStr = firstItem.expiryDate != null
            ? ' - SKT: ${DateFormat('dd.MM.yyyy').format(firstItem.expiryDate!)}'
            : '';
        return '${firstItem.product.name}$expiryStr';
      }
      return id; // Fallback
    }
  }
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
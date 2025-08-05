// lib/features/inventory_transfer/domain/entities/assignment_mode.dart

/// Depo içindeki transfer işleminin türünü belirtir.
enum AssignmentMode {
  /// Tam bir paletin bir lokasyondan diğerine taşınması.
  pallet,

  /// Paletlenmemiş (ürün bazlı) transferler.
  product,

  /// Bir paletin içinden kısmi ürünlerin alınıp ürün olarak taşınması.
  productFromPallet,
}

extension AssignmentModeExtension on AssignmentMode {
  /// API'ye gönderilecek olan isimlendirme.
  String get apiName {
    switch (this) {
      case AssignmentMode.pallet:
        return 'pallet_transfer';
      case AssignmentMode.product:
        return 'product_transfer';
      case AssignmentMode.productFromPallet:
        return 'productFromPallet';
    }
  }
}

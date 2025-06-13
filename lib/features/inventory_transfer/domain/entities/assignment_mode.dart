// lib/features/inventory_transfer/domain/entities/assignment_mode.dart

/// Depo içindeki transfer işleminin türünü belirtir.
enum AssignmentMode {
  /// Tam bir paletin bir lokasyondan diğerine taşınması.
  pallet,

  /// Paletlenmemiş (kutulu) ürünlerin taşınması.
  box,

  /// Bir paletin içinden kısmi ürünlerin alınıp kutu olarak taşınması.
  box_from_pallet,
}

extension AssignmentModeExtension on AssignmentMode {
  /// API'ye gönderilecek olan isimlendirme.
  String get apiName {
    switch (this) {
      case AssignmentMode.pallet:
        return 'pallet_transfer';
      case AssignmentMode.box:
        return 'box_transfer';
      case AssignmentMode.box_from_pallet:
        return 'box_from_pallet';
    }
  }
}

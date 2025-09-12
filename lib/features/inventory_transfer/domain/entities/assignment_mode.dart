// lib/features/inventory_transfer/domain/entities/assignment_mode.dart
import 'package:diapalet/features/inventory_transfer/constants/inventory_transfer_constants.dart';

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
        return InventoryTransferConstants.palletTransferType;
      case AssignmentMode.product:
        return InventoryTransferConstants.productTransferType;
      case AssignmentMode.productFromPallet:
        return InventoryTransferConstants.productFromPalletType;
    }
  }
}

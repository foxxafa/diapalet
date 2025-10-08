// lib/features/warehouse_count/domain/entities/count_mode.dart

/// Defines the counting mode for warehouse count operations.
///
/// - [product]: Count individual products (pallet_barcode will be NULL)
/// - [pallet]: Count entire pallets (pallet_barcode will be filled)
enum CountMode {
  product,
  pallet,
}

extension CountModeExtension on CountMode {
  String get displayName {
    switch (this) {
      case CountMode.product:
        return 'Product';
      case CountMode.pallet:
        return 'Pallet';
    }
  }

  bool get isProduct => this == CountMode.product;
  bool get isPallet => this == CountMode.pallet;
}

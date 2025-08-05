// lib/core/constants/warehouse_receiving_mode.dart
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';

/// Warehouse'ların desteklediği receiving modlarını tanımlar
enum WarehouseReceivingMode {
  /// Sadece palet modu
  paletOnly(0),

  /// Sadece ürün (product) modu
  productOnly(1),

  /// Hem palet hem ürün modu (karışık)
  mixed(2);

  const WarehouseReceivingMode(this.value);
  final int value;

  /// Int değerden enum'a dönüştürme
  static WarehouseReceivingMode fromValue(int value) {
    return WarehouseReceivingMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => WarehouseReceivingMode.mixed,
    );
  }

  /// Bu modda palet kullanılabilir mi?
  bool get isPaletEnabled {
    return this == WarehouseReceivingMode.paletOnly ||
           this == WarehouseReceivingMode.mixed;
  }

  /// Bu modda ürün (product) kullanılabilir mi?
  bool get isProductEnabled {
    return this == WarehouseReceivingMode.productOnly ||
           this == WarehouseReceivingMode.mixed;
  }

  /// Bu modda hangi modlar mevcut?
  List<ReceivingMode> get availableModes {
    switch (this) {
      case WarehouseReceivingMode.paletOnly:
        return [ReceivingMode.palet];
      case WarehouseReceivingMode.productOnly:
        return [ReceivingMode.product];
      case WarehouseReceivingMode.mixed:
        return [ReceivingMode.palet, ReceivingMode.product];
    }
  }
}

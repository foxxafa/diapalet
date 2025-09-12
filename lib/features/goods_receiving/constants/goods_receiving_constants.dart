/// Constants for Goods Receiving Feature
class GoodsReceivingConstants {
  // Source types for product classification
  static const String sourceTypeOrder = 'order';
  static const String sourceTypeOutOfOrder = 'out_of_order';
  
  // Stock status types
  static const String stockStatusReceiving = 'receiving';
  
  // Field types for barcode processing
  static const String fieldTypePallet = 'pallet';
  static const String fieldTypeProduct = 'product';
  
  // Receiving modes
  static const String modePallet = 'palet';
  static const String modeProduct = 'product';
  
  // Private constructor to prevent instantiation
  const GoodsReceivingConstants._();
}
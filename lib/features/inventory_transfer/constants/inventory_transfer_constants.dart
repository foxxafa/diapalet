/// Constants for Inventory Transfer Feature
class InventoryTransferConstants {
  // Stock statuses
  static const String stockStatusAvailable = 'available';
  static const String stockStatusReceiving = 'receiving';
  
  // Location codes
  static const String receivingAreaCode = '000';
  
  // Operation types
  static const String palletTransferType = 'pallet_transfer';
  static const String productTransferType = 'product_transfer';
  static const String productFromPalletType = 'productFromPallet';
  
  // Assignment modes
  static const String assignmentModeSystem = 'system';
  static const String assignmentModeManual = 'manual';
  
  // Transfer types
  static const String transferTypeInbound = 'inbound';
  static const String transferTypeOutbound = 'outbound';
  static const String transferTypeInternal = 'internal';
  
  // UI spacing constants
  static const double standardGap = 12.0;
  static const double smallGap = 8.0;
  static const double tinyGap = 4.0;
  static const double microGap = 4.0;
  static const double largeGap = 16.0;
  static const double largePadding = 16.0;
  static const double borderRadius = 12.0;
  
  // Database column names
  static const String productKeyColumn = '_key';
  static const String unitKeyColumn = 'birim_key';
  static const String locationIdColumn = 'location_id';
  static const String palletBarcodeColumn = 'pallet_barcode';
  static const String quantityColumn = 'quantity';
  static const String stockStatusColumn = 'stock_status';
  static const String stockUuidColumn = 'stock_uuid';
  static const String createdAtColumn = 'created_at';
  static const String updatedAtColumn = 'updated_at';
  
  // API field names
  static const String deliveryNoteField = 'delivery_note_number';
  static const String orderIdField = 'order_id';
  static const String productIdField = 'product_id';
  static const String transferIdField = 'transfer_id';
  
  // Error messages keys
  static const String errorInsufficientStock = 'error_insufficient_stock';
  static const String errorInvalidBarcode = 'error_invalid_barcode';
  static const String errorTransferFailed = 'error_transfer_failed';
  static const String errorLocationNotFound = 'error_location_not_found';
  
  // Success messages keys  
  static const String successTransferCompleted = 'success_transfer_completed';
  static const String successItemAdded = 'success_item_added';
  static const String successItemRemoved = 'success_item_removed';
  
  // Private constructor to prevent instantiation
  const InventoryTransferConstants._();
}
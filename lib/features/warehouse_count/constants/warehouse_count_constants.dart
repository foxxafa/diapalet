// lib/features/warehouse_count/constants/warehouse_count_constants.dart

class WarehouseCountConstants {
  // Status values matching database ENUM
  static const String statusInProgress = 'in_progress';
  static const String statusCompleted = 'completed';

  // Sheet number prefix
  static const String sheetNumberPrefix = 'COUNT';

  // UI dimensions
  static const double cardPadding = 16.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;

  // Table pagination
  static const int defaultPageSize = 20;

  // Input validation
  static const int maxNotesLength = 500;
  static const double minQuantity = 0.0001;
  static const double maxQuantity = 999999.9999;
}

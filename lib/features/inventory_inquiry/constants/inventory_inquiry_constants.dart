/// Constants for inventory inquiry feature
class InventoryInquiryConstants {
  // GS1 Parser keys
  static const String gs1GtinKey = '01';
  
  // Query prefixes and suffixes
  static const String wildcardPrefix = '%';
  static const String wildcardSuffix = '%';
  
  // Product search limits
  static const int maxProductSuggestions = 10;
  static const int maxDisplayedSuggestions = 5;
  
  // Database query conditions
  static const String stockAvailableStatus = 'available';
  static const int minStockQuantity = 0;
  
  // GTIN format constants
  static const int gtin14Length = 14;
  static const int gtin13Length = 13;
  static const String gtinLeadingZero = '0';
  
  // UI spacing constants
  static const double searchBarPadding = 16.0;
  static const double cardMarginHorizontal = 16.0;
  static const double cardMarginVertical = 8.0;
  static const double cardPadding = 16.0;
  static const double dividerHeight = 24.0;
  static const double infoRowSpacing = 8.0;
  static const double iconSize = 20.0;
  static const double suggestionMarginTop = 8.0;
  static const double borderRadius = 12.0;
  static const double iconTextSpacing = 12.0;
  
  // Private constructor to prevent instantiation
  const InventoryInquiryConstants._();
}
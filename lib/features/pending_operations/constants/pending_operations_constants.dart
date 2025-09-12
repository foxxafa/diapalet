/// Constants for pending operations feature
class PendingOperationsConstants {
  // UI spacing constants
  static const double dialogHorizontalInset = 20.0;
  static const double dialogVerticalInset = 24.0;
  static const double cardMarginVertical = 2.0;
  static const double cardPadding = 8.0;
  static const double cardBorderRadius = 8.0;
  static const double cardMarginBetween = 16.0;
  
  // Status banner constants
  static const double bannerHorizontalPadding = 16.0;
  static const double bannerVerticalPadding = 12.0;
  static const double bannerMargin = 12.0;
  static const double bannerBorderRadius = 12.0;
  static const double bannerIconSize = 20.0;
  static const double bannerIconSpacing = 8.0;
  
  // FloatingActionButton constants
  static const double fabIconSize = 20.0;
  static const double fabProgressStrokeWidth = 2.0;
  static const String fabMainHeroTag = "sync_main";
  
  // List padding constants
  static const double listPaddingLeft = 8.0;
  static const double listPaddingTop = 8.0;
  static const double listPaddingRight = 8.0;
  static const double listPaddingBottom = 88.0;
  
  // Empty state constants
  static const double emptyStateIconSize = 60.0;
  static const double emptyStatePadding = 24.0;
  static const double emptyStateSpacing = 16.0;
  
  // Card styling constants
  static const double cardElevationNormal = 1.0;
  static const double cardElevationError = 2.0;
  static const double cardBorderWidth = 1.5;
  static const int cardBorderAlpha = 128;
  
  // Detail section constants
  static const double detailSectionSpacing = 8.0;
  static const double detailDividerHeight = 24.0;
  static const double detailPaddingBottom = 8.0;
  static const double detailPaddingLeft = 8.0;
  
  // Icon sizes for different contexts
  static const double smallIconSize = 16.0;
  static const double mediumIconSize = 18.0;
  static const double defaultIconSize = 20.0;
  
  // Item container styling
  static const double itemContainerPadding = 8.0;
  static const double itemBadgePaddingHorizontal = 8.0;
  static const double itemBadgePaddingVertical = 4.0;
  static const double itemBadgeBorderRadius = 12.0;
  static const int itemBadgeBackgroundAlpha = 25;
  
  // Raw JSON view constants
  static const double jsonContainerPadding = 8.0;
  static const double jsonContainerBorderRadius = 8.0;
  static const int jsonBackgroundAlpha = 13;
  static const double jsonFontSize = 12.0;
  static const String jsonFontFamily = 'monospace';
  
  // Operation type labels
  static const String operationTypeGoodsReceipt = 'goods_receipt';
  static const String operationTypeInventoryTransfer = 'inventory_transfer';
  static const String operationTypeForceCloseOrder = 'force_close_order';
  static const String operationTypeInventoryStock = 'inventory_stock';
  
  // Fixed string values
  static const String unknownValue = 'N/A';
  static const String nullStringValue = 'null';
  static const String systemUserDefault = 'System User';
  static const String receivingAreaLocationCode = '000';
  static const String forceClosedStatus = 'Force Closed';
  
  // Number formatting
  static const int decimalPlaces = 0;
  static const String multiplierSymbol = 'x ';
  
  // Table sizing
  static const int fixedColumnWidth = 150;
  
  // Private constructor to prevent instantiation
  const PendingOperationsConstants._();
}
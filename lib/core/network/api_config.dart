// lib/core/network/api_config.dart
class ApiConfig {
  static const String baseUrl = 'https://enzo.rowhub.net/index.php?r=apiterminal';

  // Kimlik Doğrulama
  static const String login = '$baseUrl/login';

  // Senkronizasyon
  static const String syncUpload = '$baseUrl/sync-upload';
  static const String syncDownload = '$baseUrl/sync-download';

  // Ana Veri
  static const String locations = '$baseUrl/locations';
  static const String productsDropdown = '$baseUrl/products-dropdown';
  static const String purchaseOrders = '$baseUrl/purchase-orders';
  // Düzeltme: Parametreler path yerine query string olarak gönderiliyor.
  static String purchaseOrderItems(int orderId) => '$baseUrl/purchase-order-items?order_id=$orderId';

  // İşlemler
  static const String goodsReceipts = '$baseUrl/goods-receipts';
  static const String transfers = '$baseUrl/transfers';

  // Sorgular
  // Düzeltme: Parametreler path yerine query string olarak gönderiliyor.
  static String containerIds(int locationId) => '$baseUrl/container-ids?location_id=$locationId';
  static String containerContents(String palletBarcode) => '$baseUrl/container-contents?pallet_barcode=$palletBarcode';

  // Sunucu Sağlık Kontrolü
  static const String healthCheck = '$baseUrl/health-check';
}

// lib/core/network/api_config.dart
class ApiConfig {
  // Docker yerel sunucu (geliştirme için)
  // Emülatör için: 10.0.2.2 (Android emülatör host erişimi)
  // Fiziksel cihaz için: 192.168.10.133 (yerel ağ IP'si)
  static const String baseUrl = 'http://10.0.2.2:5000';
  
  // Fiziksel cihaz için (yorum kaldırarak kullanın)
  // static const String baseUrl = 'http://192.168.10.133:5000';
  
  // Canlı sunucu (ileride kullanmak için)
  // static const String baseUrl = 'https://enzo.rowhub.net';

  // Kimlik Doğrulama
  static const String login = '$baseUrl/v1/login';

  // Senkronizasyon
  static const String syncUpload = '$baseUrl/api/sync/upload';
  static const String syncDownload = '$baseUrl/api/sync/download';

  // Ana Veri
  static const String locations = '$baseUrl/locations';
  static const String productsDropdown = '$baseUrl/products-dropdown';
  static const String purchaseOrders = '$baseUrl/purchase-orders';
  // Parametreler query string olarak gönderiliyor
  static String purchaseOrderItems(int orderId) => '$baseUrl/purchase-order-items?order_id=$orderId';

  // İşlemler
  static const String goodsReceipts = '$baseUrl/goods-receipts';
  static const String transfers = '$baseUrl/transfers';

  // Sorgular
  // Parametreler query string olarak gönderiliyor
  static String containerIds(int locationId) => '$baseUrl/container-ids?location_id=$locationId';
  static String containerContents(String palletBarcode) => '$baseUrl/container-contents?pallet_barcode=$palletBarcode';

  // Sunucu Sağlık Kontrolü
  static const String healthCheck = '$baseUrl/health';
}

// lib/core/network/api_config.dart
class ApiConfig {
  // --- YEREL DOCKER SUNUCUSU ---
  // Android emülatöründen PC'nizdeki localhost'a erişmek için '10.0.2.2' kullanılır.
  // Docker sunucunuzun çalıştığı portu (örn: 5000) buraya yazın.
  static const String _localHost = 'http://192.168.1.122:5000';  //'http://192.168.1.122:5000'     http://10.0.2.2:5000

  // --- TEMEL YOL (BASE PATH) ---
  // Sunucudaki Yii2 controller'ı 'TerminalController' olduğu için,
  // framework bunu varsayılan olarak 'terminal' yoluna (route) eşler.
  // Tüm istekler bu temel yol üzerinden yapılır.
  static const String baseUrl = '$_localHost/terminal';

  // --- ENDPOINT'LER ---
  // Her bir endpoint, TerminalController içindeki bir 'action' metoduna karşılık gelir.
  // Yii2, action isimlerini (örn: actionLogin) URL formatına (örn: /login) dönüştürür.
  // Yii2, action metodlarındaki parametreleri (örn: $order_id) query string olarak bekler.

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
  static final String healthCheck = '$baseUrl/health-check';
}

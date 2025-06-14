// lib/core/network/api_config.dart
class ApiConfig {
  /// The root host for the backend service. **Do NOT** add a trailing slash here.
  /// GÜNCELLEME: Fiziksel bir cihazdan (Unitech terminal gibi) sunucuya erişmek için,
  /// geliştirme bilgisayarının yerel ağ IP adresi kullanılır.
  /// Android emülatörü için '10.0.2.2' kullanılırken, ağdaki fiziksel cihazlar için
  /// 'ipconfig' veya 'ifconfig' komutuyla bulunan IP adresi yazılmalıdır.
  static const String _host = 'http://10.0.2.2:5000'; //http://10.0.2.2:5000  //http://192.168.1.122:5000

  /// Public getter for the host.
  static String get host => _host;

  /// API version segment. Update this when the backend version changes.
  static const String apiVersion = 'v1';

  /// Full base url composed of host and api version, e.g. `http://192.168.45.133:5000/v1`.
  static String get baseUrl => '$host/$apiVersion';

  /// Same as [baseUrl] but guaranteed **not** to end with a trailing `/`.
  static String get sanitizedBaseUrl =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // --- Sync Endpoints ---
  static final String syncDownload = '$host/api/sync/download';
  static final String syncUpload = '$host/api/sync/upload';

  // --- Master Data Endpoints ---
  static final String locations = '$sanitizedBaseUrl/locations';
  static final String productsDropdown = '$sanitizedBaseUrl/products/dropdown';

  // --- Purchase Order Endpoints ---
  static final String purchaseOrders = '$sanitizedBaseUrl/purchase-orders';
  static String purchaseOrderItems(int orderId) => '$purchaseOrders/$orderId/items';

  // --- Goods Receipt Endpoints ---
  static final String goodsReceipts = '$sanitizedBaseUrl/goods-receipts';

  // --- Transfer Endpoints ---
  static final String transfers = '$sanitizedBaseUrl/transfers';
}

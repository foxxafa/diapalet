// lib/core/network/api_config.dart
class ApiConfig {
  // Yerel sunucu, genel senkronizasyon ve veri işlemleri için
  static const String _host = 'http://192.168.45.133:5000';

  // Uzak sunucu, kimlik doğrulama ve kullanıcı yönetimi için
  static const String _remoteHost = 'https://test.rowhub.net';//http://localhost:8000/index.php?r=terminal

  /// Yerel sunucu için public getter.
  static String get host => _host;

  /// Yerel sunucu için API versiyonu.
  static const String apiVersion = 'v1';

  /// Yerel sunucu için temel URL.
  static String get baseUrl => '$host/$apiVersion';

  /// [baseUrl] ile aynı, ancak sonunda '/' olmadan.
  static String get sanitizedBaseUrl =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // --- Uzak Sunucu Endpoint'leri ---
  static final String login = '$_remoteHost/index.php?r=terminal/login';

  // DÜZELTME: Endpoint, kullanıcı tarafından sağlanan doğru URL ile değiştirildi.
  static final String getAllUsers = '$_remoteHost/index.php?r=terminal/alluser';

  // --- Yerel Sunucu Endpoint'leri ---
  static final String syncDownload = '$host/api/sync/download';
  static final String syncUpload = '$host/api/sync/upload';
  static final String locations = '$sanitizedBaseUrl/locations';
  static final String productsDropdown = '$sanitizedBaseUrl/products/dropdown';
  static final String purchaseOrders = '$sanitizedBaseUrl/purchase-orders';
  static String purchaseOrderItems(int orderId) => '$purchaseOrders/$orderId/items';
  static final String goodsReceipts = '$sanitizedBaseUrl/goods-receipts';
  static final String transfers = '$sanitizedBaseUrl/transfers';
}

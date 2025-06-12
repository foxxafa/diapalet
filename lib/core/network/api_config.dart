class ApiConfig {
  /// The root host for the backend service. **Do NOT** add a trailing slash here.
  static const String _host = 'http://10.0.2.2:5000';

  /// Public getter for the host.
  static String get host => _host;

  /// API version segment. Update this when the backend version changes.
  static const String apiVersion = 'v1';

  /// Full base url composed of host and api version, e.g. `http://10.0.2.2:5000/v1`.
  static String get baseUrl => '$host/$apiVersion';

  /// Same as [baseUrl] but guaranteed **not** to end with a trailing `/`.
  static String get sanitizedBaseUrl => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // Cihaz kaydı
  static const String registerDevice = '$baseUrl/api/register_device';

  // Senkronizasyon
  static const String syncDownload = '$baseUrl/api/sync/download';
  static const String syncUpload = '$baseUrl/api/sync/upload';

  // Belirli tabloları indirme (opsiyonel)
  static String dataDownload(String tableName) => '$baseUrl/api/data/$tableName';
}
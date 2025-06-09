class ApiConfig {
  /// The root host for the backend service. **Do NOT** add a trailing slash here.
  static const String _host = 'http://192.168.1.100:5000';

  /// API version segment. Update this when the backend version changes.
  static const String apiVersion = 'v1';

  /// Full base url composed of host and api version, e.g. `http://192.168.1.100:5000/v1`.
  static String get baseUrl => '$_host/$apiVersion';

  /// Same as [baseUrl] but guaranteed **not** to end with a trailing `/`.
  static String get sanitizedBaseUrl => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}
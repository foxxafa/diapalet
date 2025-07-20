// lib/core/network/api_environments.dart
enum ApiEnvironment { local, staging, production }

class ApiEnvConfig {
  final String name;
  final String baseUrl;
  final String description;

  const ApiEnvConfig({
    required this.name,
    required this.baseUrl,
    required this.description,
  });
}

class ApiEnvironments {
  // Android Emulator'ün bilgisayardaki localhost'a erişmek için kullandığı özel IP adresi.
  // Eğer fiziksel bir cihazda test ediyorsan, bu adresi bilgisayarının yerel ağ IP'si ile (örn: 'http://192.168.1.5:8080') değiştirmelisin.
  static const String _localBaseUrl = 'http://10.0.2.2:8080';

  // Railway ortam URL'leri - Custom domain'ler
  // Railway'de custom domain ayarlandıktan sonra bu URL'ler güncellenecek
  static const String _stagingBaseUrl = 'https://staging-api.diapalet.com';
  static const String _productionBaseUrl = 'https://api.diapalet.com';

  // Geçici Railway URL'leri (custom domain ayarlanana kadar)
  // static const String _stagingBaseUrl = 'https://diapalet-staging.up.railway.app';
  // static const String _productionBaseUrl = 'https://diapalet-production.up.railway.app';

  static const Map<ApiEnvironment, ApiEnvConfig> _environments = {
    ApiEnvironment.local: ApiEnvConfig(
      name: 'Local',
      baseUrl: _localBaseUrl,
      description: 'Docker container on localhost (Development)',
    ),
    ApiEnvironment.staging: ApiEnvConfig(
      name: 'Staging',
      baseUrl: _stagingBaseUrl,
      description: 'Diapalet Staging API (Test Environment)',
    ),
    ApiEnvironment.production: ApiEnvConfig(
      name: 'Production',
      baseUrl: _productionBaseUrl,
      description: 'Diapalet Production API (Live System)',
    ),
  };

  static ApiEnvConfig getEnv(ApiEnvironment env) {
    return _environments[env]!;
  }

  // Tüm ortamları listele (debug/settings ekranı için)
  static List<ApiEnvConfig> getAllEnvironments() {
    return _environments.values.toList();
  }
}
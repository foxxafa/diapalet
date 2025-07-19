// lib/core/network/api_environments.dart
enum ApiEnvironment { local, production }

class ApiEnvConfig {
  final String name;
  final String baseUrl;

  const ApiEnvConfig({required this.name, required this.baseUrl});
}

class ApiEnvironments {
  // Android Emulator'ün bilgisayardaki localhost'a erişmek için kullandığı özel IP adresi.
  // Eğer fiziksel bir cihazda test ediyorsan, bu adresi bilgisayarının yerel ağ IP'si ile (örn: 'http://192.168.1.5:8080') değiştirmelisin.
  static const String _localBaseUrl = 'http://10.0.2.2:8080';

  static const String _productionBaseUrl = 'https://diapalet-production.up.railway.app';

  static const Map<ApiEnvironment, ApiEnvConfig> _environments = {
    ApiEnvironment.local: ApiEnvConfig(
      name: 'Local (Docker)',
      baseUrl: _localBaseUrl,
    ),
    ApiEnvironment.production: ApiEnvConfig(
      name: 'Production (Railway Demo)',
      baseUrl: _productionBaseUrl,
    ),
  };

  static ApiEnvConfig getEnv(ApiEnvironment env) {
    return _environments[env]!;
  }
} 
// lib/core/network/api_environments.dart

enum Environment {
  development,
  production,
  local,
}

class ApiEnvironments {
  static const Environment current = Environment.production;
  
  static String get baseUrl {
    switch (current) {
      case Environment.production:
        return 'https://diapalet-production.up.railway.app';
      case Environment.development:
        return 'http://10.0.2.2:5000'; // Android emülatör için
      case Environment.local:
        return 'http://192.168.10.133:5000'; // Fiziksel cihaz için
    }
  }
  
  static bool get isProduction => current == Environment.production;
  static bool get isDevelopment => current == Environment.development;
  static bool get isLocal => current == Environment.local;
  
  // Environment değiştirmek için
  static String getUrlForEnvironment(Environment env) {
    switch (env) {
      case Environment.production:
        return 'https://diapalet-production.up.railway.app';
      case Environment.development:
        return 'http://10.0.2.2:5000';
      case Environment.local:
        return 'http://192.168.10.133:5000';
    }
  }
} 
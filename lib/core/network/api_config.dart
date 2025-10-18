// lib/core/network/api_config.dart
import 'package:diapalet/core/network/api_environments.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // ******************************************************************
  // UYGULAMANIN HANGİ SUNUCUYA BAĞLANACAĞINI BURADAN DEĞİŞTİR
  // ApiEnvironment.local -> Bilgisayarındaki Docker sunucusu (Geliştirme için)
  // ApiEnvironment.staging -> Railway staging ortamı (Test için)
  // ApiEnvironment.production -> Railway production ortamı (Canlı)
  // ******************************************************************
  static const ApiEnvironment currentEnvironment = ApiEnvironment.production;

  // Seçili ortama göre konfigürasyonu al
  static final ApiEnvConfig _config = ApiEnvironments.getEnv(currentEnvironment);

  // Dışarıdan erişilecek URL ve isim
  static String get baseUrl => _config.baseUrl;
  static String get environmentName => _config.name;
  static String get environmentDescription => _config.description;
  static bool get isProduction => currentEnvironment == ApiEnvironment.production;
  static bool get isStaging => currentEnvironment == ApiEnvironment.staging;
  static bool get isLocal => currentEnvironment == ApiEnvironment.local;

  // API Endpoint yolları - Ortama göre otomatik format seçimi
  static String get login => _getEndpoint('login');
  static String get syncUpload => _getEndpoint('sync-upload');
  static String get syncDownload => _getEndpoint('sync-download');
  static String get syncCounts => _getEndpoint('sync-counts');
  static String get unknownBarcodesUpload => _getEndpoint('unknown-barcodes-upload');
  static String get healthCheck => _getEndpoint('health-check');

  // Endpoint formatını ortama göre belirle
  static String _getEndpoint(String action) {
    if (isProduction) {
      // Rowhub formatı
      return '/index.php?r=terminal/$action';
    } else {
      // Railway formatı (staging ve local)
      return '/api/terminal/$action';
    }
  }

  static final Dio dio = _createDio();

  static Dio _createDio() {
    // 1. Get the config directly.
    final config = ApiEnvironments.getEnv(currentEnvironment);

    // 2. Use it to initialize BaseOptions.
    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl, // Use the directly fetched base URL
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 1),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    // Loglama için Interceptor ekle (sadece debug modda çalışır)
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        error: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
    }

    // API Key'i otomatik ekleyen Interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final apiKey = prefs.getString('api_key');
        if (apiKey != null) {
          options.headers['Authorization'] = 'Bearer $apiKey';
        }
        return handler.next(options);
      },
    ));

    return dio;
  }
}

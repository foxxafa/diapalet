// lib/core/network/api_config.dart
import 'package:diapalet/core/network/api_environments.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // ******************************************************************
  // UYGULAMANIN HANGİ SUNUCUYA BAĞLANACAĞINI BURADAN DEĞİŞTİR
  // ApiEnvironment.local -> Bilgisayarındaki Docker sunucusu (Geliştirme için)
  // ApiEnvironment.production -> Railway'deki sunucu (Demo/Canlı için)
  // ******************************************************************
  static const ApiEnvironment currentEnvironment = ApiEnvironment.production;
  
  // Seçili ortama göre konfigürasyonu al
  static final ApiEnvConfig _config = ApiEnvironments.getEnv(currentEnvironment);

  // Dışarıdan erişilecek URL ve isim
  static String get baseUrl => _config.baseUrl;
  static String get environmentName => _config.name;
  static bool get isProduction => currentEnvironment == ApiEnvironment.production;

  // API Endpoint yolları
  static const String login = '/api/terminal/login';
  static const String syncUpload = '/api/terminal/sync-upload';
  static const String syncDownload = '/api/terminal/sync-download';
  static const String devReset = '/api/terminal/dev-reset';
  static const String healthCheck = '/api/terminal/health-check';

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

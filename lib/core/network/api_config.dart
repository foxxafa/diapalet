// lib/core/network/api_config.dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:diapalet/core/network/dio_logger.dart';

class ApiConfig {
  // Railway Production Server (Canlı Sunucu)
  static const String baseUrl = 'https://diapalet-production.up.railway.app';
  
  // Docker yerel sunucu (geliştirme için)
  // Emülatör için: 10.0.2.2 (Android emülatör host erişimi)
  // Fiziksel cihaz için: 192.168.10.133 (yerel ağ IP'si)
  // static const String baseUrl = 'http://10.0.2.2:5000';
  
  // Fiziksel cihaz için (yerel test)
  // static const String baseUrl = 'http://192.168.10.133:5000';

  // Kimlik Doğrulama (Railway Yii2 API)
  static const String login = '$baseUrl/api/terminal/login';

  // Senkronizasyon (Railway Yii2 API)
  static const String syncUpload = '$baseUrl/api/terminal/sync-upload';
  static const String syncDownload = '$baseUrl/api/terminal/sync-download';

  // Sunucu Sağlık Kontrolü
  static const String healthCheck = '$baseUrl/health-check';
  
  // Depo/Raf Senkronizasyonu
  static const String syncShelfs = '$baseUrl/api/terminal/sync-shelfs';

  // Ana Veri (Eski endpoint'ler - gerekirse yeni API endpoint'leri eklenecek)
  static const String locations = '$baseUrl/locations';
  static const String productsDropdown = '$baseUrl/products-dropdown';
  static const String purchaseOrders = '$baseUrl/purchase-orders';
  // Parametreler query string olarak gönderiliyor
  static String purchaseOrderItems(int orderId) => '$baseUrl/purchase-order-items?order_id=$orderId';

  // İşlemler (Eski endpoint'ler - gerekirse yeni API endpoint'leri eklenecek)
  static const String goodsReceipts = '$baseUrl/goods-receipts';
  static const String transfers = '$baseUrl/transfers';

  // Sorgular (Eski endpoint'ler - gerekirse yeni API endpoint'leri eklenecek)
  // Parametreler query string olarak gönderiliyor
  static String containerIds(int locationId) => '$baseUrl/container-ids?location_id=$locationId';
  static String containerContents(String palletBarcode) => '$baseUrl/container-contents?pallet_barcode=$palletBarcode';

  static final Dio dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    // dio.interceptors.add(DioLogger(
    //   request: true,
    //   requestHeader: true,
    //   requestBody: true,
    //   responseHeader: true,
    //   responseBody: true,
    //   error: true,
    //   compact: true,
    // ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Login endpoint'leri için token kontrolü yapma
        if (!options.path.contains('/login')) {
          final prefs = await SharedPreferences.getInstance();
          final apiKey = prefs.getString('api_key');
          if (apiKey != null) {
            options.headers['Authorization'] = 'Bearer $apiKey';
          }
        }
        return handler.next(options);
      },
    ));
    return dio;
  }
}

// lib/features/auth/data/repositories/auth_repository_impl.dart
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';

class AuthRepositoryImpl implements AuthRepository {
  final DatabaseHelper dbHelper;
  final NetworkInfo networkInfo;
  final Dio dio;

  AuthRepositoryImpl({
    required this.dbHelper,
    required this.networkInfo,
    required this.dio,
  });

  @override
  Future<bool> login(String username, String password) async {
    // İnternet bağlantısı kontrolü bu metoda taşındı.
    if (await networkInfo.isConnected) {
      return _loginOnline(username, password);
    } else {
      return _loginOffline(username, password);
    }
  }

  Future<bool> _loginOnline(String username, String password) async {
    try {
      debugPrint("Online login denemesi (form-data): $username");

      final response = await dio.post(
        ApiConfig.login,
        data: {
          'username': username,
          'password': password,
        },
        // Backend kodu (Yii2) post verisi beklediği için Content-Type değiştirildi.
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      // Sunucudan gelen yanıtı her durumda konsola yazdıralım.
      debugPrint("Sunucu Yanıtı (Status ${response.statusCode}): ${response.data}");

      if (response.statusCode == 200 && response.data != null) {
        final responseData = response.data;

        // DÜZELTME: Sunucudan gelen 'status' alanı kontrol ediliyor.
        final status = responseData['status'] as String?;

        if (status == 'success') {
          debugPrint("Online login başarılı.");
          // Burada apikey gibi verileri saklama işlemi yapılabilir.
          // Örneğin: final apiKey = responseData['apikey'];
          return true;
        } else {
          // Sunucudan gelen hata mesajını kullanalım.
          final errorMessage = responseData['message'] ?? 'Kullanıcı adı veya şifre hatalı.';
          throw Exception(errorMessage);
        }
      } else {
        // 200 dışında bir status kodu geldiyse
        throw Exception('Sunucudan geçersiz yanıt alındı (Kod: ${response.statusCode})');
      }
    } on DioException catch (e) {
      // Dio hatası durumunda daha detaylı loglama yapalım.
      debugPrint("API Hatası (DioException): ${e.message}");
      debugPrint("Sunucudan Gelen Hata Yanıtı: ${e.response?.data}");
      final errorMessage = e.response?.data?['message'] ?? "Sunucuya bağlanırken bir hata oluştu.";
      throw Exception(errorMessage);
    } catch (e) {
      debugPrint("Bilinmeyen Hata: $e");
      throw Exception("Bilinmeyen bir hata oluştu.");
    }
  }

  Future<bool> _loginOffline(String username, String password) async {
    try {
      final db = await dbHelper.database;
      final List<Map<String, dynamic>> result = await db.query(
        'employees',
        where: 'username = ? AND password = ?',
        whereArgs: [username, password],
        limit: 1,
      );
      debugPrint("Offline login sonucu: ${result.isNotEmpty}");
      if (result.isNotEmpty) {
        return true;
      }
      // Çevrimdışı modda da kullanıcıya bilgi vermek için hata fırlatıldı.
      throw Exception("Çevrimdışı giriş başarısız. İnternet yok ve bilgileriniz yerel veritabanında bulunamadı.");
    } catch (e) {
      debugPrint("Veritabanı Hatası: $e");
      // Hatanın UI'a yansıması için tekrar fırlatılıyor.
      rethrow;
    }
  }
}

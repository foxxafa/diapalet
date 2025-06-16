// lib/features/auth/data/repositories/auth_repository_impl.dart
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      debugPrint("Sunucu Yanıtı (Status ${response.statusCode}): ${response.data}");

      if (response.statusCode == 200 && response.data != null) {
        final responseData = response.data as Map<String, dynamic>;

        // HATA DÜZELTMESİ: Sunucudan 'status' alanı integer (200) olarak geliyor.
        // String olarak kontrol etmek yerine sayı olarak kontrol edildi.
        if (responseData['status'] == 200) {
          debugPrint("Online login başarılı.");

          // YENİ ÖZELLİK: Kullanıcı bilgilerini SharedPreferences'a kaydet.
          final user = responseData['user'] as Map<String, dynamic>;
          final apiKey = responseData['apikey'] as String;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('apikey', apiKey);
          await prefs.setInt('warehouse_id', user['warehouse_id'] as int);
          await prefs.setInt('branch_id', user['branch_id'] as int);
          await prefs.setString('first_name', user['first_name'] as String);
          await prefs.setString('last_name', user['last_name'] as String);

          debugPrint("Kullanıcı bilgileri SharedPreferences'a kaydedildi.");

          return true;
        } else {
          final errorMessage = responseData['message'] ?? 'Kullanıcı adı veya şifre hatalı.';
          throw Exception(errorMessage);
        }
      } else {
        throw Exception('Sunucudan geçersiz yanıt alındı (Kod: ${response.statusCode})');
      }
    } on DioException catch (e) {
      debugPrint("API Hatası (DioException): ${e.message}");
      debugPrint("Sunucudan Gelen Hata Yanıtı: ${e.response?.data}");
      final errorMessage = e.response?.data?['message'] ?? "Sunucuya bağlanırken bir hata oluştu.";
      throw Exception(errorMessage);
    } catch (e) {
      debugPrint("Bilinmeyen Hata: $e");
      // Orijinal hatayı daha iyi anlamak için yeniden fırlat.
      rethrow;
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
      throw Exception("Çevrimdışı giriş başarısız. İnternet yok ve bilgileriniz yerel veritabanında bulunamadı.");
    } catch (e) {
      debugPrint("Veritabanı Hatası: $e");
      rethrow;
    }
  }
}

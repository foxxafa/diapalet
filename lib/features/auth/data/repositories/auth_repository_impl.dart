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

  /// GÜNCELLEME: Kullanıcı oturumunu sonlandıran ve yerel depolamayı temizleyen fonksiyon.
  @override
  Future<void> logout() async {
    debugPrint("Çıkış yapılıyor ve oturum verileri temizleniyor...");

    // Dio istemcisindeki Authorization başlığını kaldır.
    dio.options.headers.remove('Authorization');

    // SharedPreferences'teki tüm kullanıcı verilerini temizle.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('warehouse_id');
    await prefs.remove('apikey');
    await prefs.remove('first_name');
    await prefs.remove('last_name');

    // Son senkronizasyon zamanını da temizleyerek bir sonraki girişte
    // tam senkronizasyon yapılmasını sağla.
    await prefs.remove('last_sync_timestamp');

    debugPrint("Oturum başarıyla sonlandırıldı.");
  }

  Future<bool> _loginOnline(String username, String password) async {
    try {
      debugPrint("Online login denemesi yapılıyor: $username");

      final response = await dio.post(
        ApiConfig.login,
        data: {'username': username, 'password': password,},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      debugPrint("Sunucu Yanıtı (Status ${response.statusCode}): ${response.data}");

      if (response.statusCode == 200 && response.data != null) {
        final responseData = response.data as Map<String, dynamic>;

        if (responseData['status'] == 200) {
          debugPrint("Online login başarılı.");
          final user = responseData['user'] as Map<String, dynamic>;
          final apiKey = responseData['apikey'] as String;

          // API Anahtarını tüm sonraki istekler için Dio istemcisine ekle
          dio.options.headers['Authorization'] = 'Bearer $apiKey';
          debugPrint("API Key ($apiKey) Dio istemcisine eklendi.");

          // ===== ÖNEMLİ: Kullanıcı ID'sini kaydet =====
          // 'user_id' anahtarını kullanarak SharedPreferences'a kaydediyoruz.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', user['id'] as int);
          await prefs.setInt('warehouse_id', user['warehouse_id'] as int);
          await prefs.setString('apikey', apiKey);
          await prefs.setString('first_name', user['first_name'] as String);
          await prefs.setString('last_name', user['last_name'] as String);

          await prefs.remove('last_sync_timestamp');
          debugPrint("Kullanıcı bilgileri (user_id: ${user['id']}) SharedPreferences'a kaydedildi.");

          return true;
        } else {
          final errorMessage = responseData['message'] ?? 'Kullanıcı adı veya şifre hatalı.';
          throw Exception(errorMessage);
        }
      } else {
        throw Exception('Sunucudan geçersiz yanıt alındı (Kod: ${response.statusCode})');
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data?['message'] ?? "Sunucuya bağlanırken bir hata oluştu.";
      throw Exception(errorMessage);
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> _loginOffline(String username, String password) async {
    try {
      final db = await dbHelper.database;
      final List<Map<String, dynamic>> result = await db.query(
        'employees',
        where: 'username = ? AND password = ? AND is_active = 1',
        whereArgs: [username, password],
        limit: 1,
      );

      if (result.isNotEmpty) {
        debugPrint("Offline login başarılı: $username");
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', result.first['id'] as int);
        await prefs.setInt('warehouse_id', result.first['warehouse_id'] as int);
        await prefs.setString('first_name', result.first['first_name'] as String);
        await prefs.setString('last_name', result.first['last_name'] as String);
        return true;
      } else {
        throw Exception("Çevrimdışı giriş başarısız. Bilgileriniz cihazda bulunamadı veya internete bağlıyken giriş yapmalısınız.");
      }
    } catch (e) {
      rethrow;
    }
  }
}
// lib/features/auth/data/repositories/auth_repository_impl.dart
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/database_constants.dart';
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
  Future<Map<String, dynamic>?> login(String username, String password) async {
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
    await prefs.remove('warehouse_name');
    await prefs.remove('warehouse_code');
    await prefs.remove('branch_name');
    await prefs.remove('apikey');
    await prefs.remove('first_name');
    await prefs.remove('last_name');

    // User-specific sync timestamp'ini temizle (güvenlik için)
    final userId = prefs.getInt('user_id') ?? 0;
    await prefs.remove('last_sync_timestamp_user_$userId');

    // Eski generic timestamp key'ini de temizle (backward compatibility)
    await prefs.remove('last_sync_timestamp');

    debugPrint("Oturum başarıyla sonlandırıldı.");
  }

  Future<Map<String, dynamic>?> _loginOnline(String username, String password) async {
    try {
      debugPrint("Online login denemesi yapılıyor: $username");

      // 1. CSRF token'ı al (sadece production ortamında)
      String? csrfToken;
      if (ApiConfig.isProduction) {
        try {
          final csrfResponse = await dio.get(ApiConfig.login);
          final cookies = csrfResponse.headers['set-cookie'];
          if (cookies != null) {
            for (final cookie in cookies) {
              if (cookie.contains('_csrf=')) {
                // CSRF token'ı cookie'den çıkar
                final csrfMatch = RegExp(r'_csrf=([^;]+)').firstMatch(cookie);
                if (csrfMatch != null) {
                  csrfToken = Uri.decodeComponent(csrfMatch.group(1)!);
                  debugPrint("CSRF token alındı");
                  break;
                }
              }
            }
          }
        } catch (e) {
          debugPrint("CSRF token alınamadı, token'sız deneniyor: $e");
        }
      } else {
        debugPrint("Staging/Local ortamında CSRF token atlanıyor");
      }

      // 2. Login request'i gönder
      final requestData = {
        'username': username,
        'password': password,
      };

      // CSRF token varsa ekle
      if (csrfToken != null) {
        requestData['_csrf'] = csrfToken;
      }

      final response = await dio.post(
        ApiConfig.login,
        data: requestData,
        options: Options(contentType: Headers.jsonContentType),
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

          // ===== ÖNEMLİ: Warehouse değişimi kontrolü =====
          final prefs = await SharedPreferences.getInstance();
          final previousWarehouseId = prefs.getInt('warehouse_id');
          final newWarehouseId = user['warehouse_id'] as int;
          final newUserId = user['id'] as int;
          final previousUserId = prefs.getInt('user_id');

          // Farklı warehouse'a geçiş tespit edilirse warehouse-specific verileri temizle
          if (previousWarehouseId != null && previousWarehouseId != newWarehouseId) {
            debugPrint("🔄 Warehouse değişimi tespit edildi! Önceki: $previousWarehouseId → Yeni: $newWarehouseId");
            await dbHelper.clearWarehouseSpecificData();
            debugPrint("✅ Eski warehouse verileri temizlendi, yeni warehouse sync'i başlayacak.");
          } else if (previousUserId != null && previousUserId != newUserId) {
            debugPrint("🔄 Farklı kullanıcı girişi tespit edildi! Önceki: $previousUserId → Yeni: $newUserId");
            await dbHelper.clearWarehouseSpecificData();
            debugPrint("✅ Eski kullanıcı verileri temizlendi, yeni kullanıcı sync'i başlayacak.");
          } else if (previousWarehouseId == null) {
            debugPrint("🆕 İlk giriş - warehouse ID: $newWarehouseId");
          } else {
            debugPrint("✅ Aynı warehouse'da login - warehouse ID: $newWarehouseId (veri temizliği gerek yok)");
          }

          // Kullanıcı bilgilerini kaydet
          await prefs.setInt('user_id', newUserId);
          await prefs.setInt('warehouse_id', newWarehouseId);
          await prefs.setString('warehouse_name', user['warehouse_name'] as String? ?? 'N/A');
          await prefs.setString('warehouse_code', user['warehouse_code'] as String? ?? 'N/A');
          await prefs.setInt('receiving_mode', user['receiving_mode'] as int? ?? 2);
          await prefs.setString('branch_name', user['branch_name'] as String? ?? 'N/A');
          await prefs.setString('apikey', apiKey);
          await prefs.setString('first_name', user['first_name'] as String);
          await prefs.setString('last_name', user['last_name'] as String);

          // Eski generic timestamp key'ini temizle (artık user-specific kullanıyoruz)
          await prefs.remove('last_sync_timestamp');
          debugPrint("Kullanıcı ve şube bilgileri SharedPreferences'a kaydedildi.");

          return {'warehouse_id': user['warehouse_id'] as int};
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

  Future<Map<String, dynamic>?> _loginOffline(String username, String password) async {
    try {
      final db = await dbHelper.database;

      // Employee bilgilerini al (warehouse bilgileri employees tablosunda mevcut)
      final sql = '''
        SELECT e.*, e.warehouse_code,
               COALESCE(e.warehouse_name, 'N/A') as warehouse_name
        FROM ${DbTables.employees} e
        WHERE e.${DbColumns.employeesUsername} = ? AND e.${DbColumns.employeesPassword} = ? AND e.${DbColumns.isActive} = 1
        LIMIT 1
      ''';

      final List<Map<String, dynamic>> result = await db.rawQuery(sql, [username, password]);

      if (result.isNotEmpty) {
        debugPrint("Offline login başarılı: $username");
        final user = result.first;
        
        // ===== Offline için de warehouse değişimi kontrolü =====
        final prefs = await SharedPreferences.getInstance();
        final previousWarehouseId = prefs.getInt('warehouse_id');
        final newWarehouseId = user['warehouse_id'] as int;
        final newUserId = user['id'] as int;
        final previousUserId = prefs.getInt('user_id');

        // Farklı warehouse'a geçiş tespit edilirse warehouse-specific verileri temizle
        if (previousWarehouseId != null && previousWarehouseId != newWarehouseId) {
          debugPrint("🔄 [OFFLINE] Warehouse değişimi tespit edildi! Önceki: $previousWarehouseId → Yeni: $newWarehouseId");
          await dbHelper.clearWarehouseSpecificData();
          debugPrint("✅ [OFFLINE] Eski warehouse verileri temizlendi.");
        } else if (previousUserId != null && previousUserId != newUserId) {
          debugPrint("🔄 [OFFLINE] Farklı kullanıcı girişi tespit edildi! Önceki: $previousUserId → Yeni: $newUserId");
          await dbHelper.clearWarehouseSpecificData();
          debugPrint("✅ [OFFLINE] Eski kullanıcı verileri temizlendi.");
        } else if (previousWarehouseId == null) {
          debugPrint("🆕 [OFFLINE] İlk giriş - warehouse ID: $newWarehouseId");
        } else {
          debugPrint("✅ [OFFLINE] Aynı warehouse'da login - warehouse ID: $newWarehouseId (veri temizliği gerek yok)");
        }

        // Kullanıcı bilgilerini kaydet
        await prefs.setInt('user_id', newUserId);
        await prefs.setInt('warehouse_id', newWarehouseId);
        await prefs.setString('warehouse_name', user['warehouse_name'] as String? ?? 'N/A');
        await prefs.setString('warehouse_code', user['warehouse_code'] as String? ?? 'N/A');
        await prefs.setString('first_name', user['first_name'] as String);
        await prefs.setString('last_name', user['last_name'] as String);

        // Offline durumda branch bilgisi genelde mevcut olmaz, N/A olarak ayarla
        await prefs.setString('branch_name', 'N/A');

        return {'warehouse_id': newWarehouseId};
      } else {
        throw Exception("Çevrimdışı giriş başarısız. Bilgileriniz cihazda bulunamadı veya internete bağlıyken giriş yapmalısınız.");
      }
    } catch (e) {
      rethrow;
    }
  }
}
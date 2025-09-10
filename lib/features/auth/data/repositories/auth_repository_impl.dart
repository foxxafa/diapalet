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

  /// GÜNCELLEME: Kullanıcı oturumunu sonlandıran fonksiyon.
  /// OFFLINE KULLANIM İÇİN: warehouse ve branch bilgileri korunur
  /// SYNC TIMESTAMP: Warehouse bazlı olarak korunur
  @override
  Future<void> logout() async {
    debugPrint("Çıkış yapılıyor - offline kullanım için warehouse bilgileri korunacak...");

    // Dio istemcisindeki Authorization başlığını kaldır.
    dio.options.headers.remove('Authorization');

    // SharedPreferences'ten SADECE kullanıcı kimlik verilerini temizle
    final prefs = await SharedPreferences.getInstance();
    
    // Logout öncesi warehouse code'u al (timestamp key için)
    final warehouseCode = prefs.getString('warehouse_code');
    
    await prefs.remove('user_id');
    await prefs.remove('employee_id');
    await prefs.remove('first_name');
    await prefs.remove('last_name');
    await prefs.remove('role');

    // User-specific sync timestamp'lerini temizle (artık kullanılmıyor)
    // Ama warehouse bazlı timestamp'i KORU
    final userId = prefs.getInt('user_id') ?? 0;
    await prefs.remove('last_sync_timestamp_user_$userId');
    await prefs.remove('last_sync_timestamp');
    
    // ÖNEMLİ: Warehouse bazlı sync timestamp'ini KORU
    // Bu sayede aynı warehouse'da farklı kullanıcılar sync'i devam ettirebilir
    if (warehouseCode != null) {
      final warehouseSyncKey = 'last_sync_timestamp_warehouse_$warehouseCode';
      final existingTimestamp = prefs.getString(warehouseSyncKey);
      if (existingTimestamp != null) {
        debugPrint("📌 Warehouse sync timestamp korunuyor: $warehouseSyncKey = $existingTimestamp");
      }
    }

    // ⚠️ OFFLINE KULLANIM VE SYNC İÇİN KORUNANLAR:
    // - warehouse_name (PDF'ler için)  
    // - warehouse_code (offline login için)
    // - branch_name (PDF'ler için)
    // - apikey (sync için - tekrar online olduğunda)
    // - receiving_mode (depo ayarları için)
    // - last_sync_timestamp_warehouse_XXX (warehouse bazlı sync için)

    debugPrint("✅ Oturum sonlandırıldı. Warehouse bilgileri ve sync timestamp'i korundu.");
    debugPrint("🔒 Korunan veriler: warehouse_name, warehouse_code, branch_name, apikey, receiving_mode, warehouse sync timestamp");
  }

  Future<Map<String, dynamic>?> _loginOnline(String username, String password) async {
    try {
      debugPrint("Online login denemesi yapılıyor: $username");
      debugPrint("Username uzunluğu: ${username.length}, karakter kodları: ${username.codeUnits}");
      debugPrint("Password uzunluğu: ${password.length}");

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
          final previousWarehouseCode = prefs.getString('warehouse_code');
          final newWarehouseCode = user['warehouse_code'] as String;
          final newUserId = user['id'] as int;
          final previousUserId = prefs.getInt('user_id');

          // SADECE farklı warehouse'a geçiş tespit edilirse warehouse-specific verileri temizle
          // Aynı warehouse'da farklı kullanıcı girişinde veri temizlenmez
          if (previousWarehouseCode != null && previousWarehouseCode != newWarehouseCode) {
            debugPrint("🔄 Warehouse değişimi tespit edildi! Önceki: $previousWarehouseCode → Yeni: $newWarehouseCode");
            await dbHelper.clearWarehouseSpecificData();
            debugPrint("✅ Eski warehouse verileri temizlendi, yeni warehouse sync'i başlayacak.");
          } else if (previousUserId != null && previousUserId != newUserId) {
            debugPrint("👤 Aynı warehouse'da farklı kullanıcı girişi: Önceki: $previousUserId → Yeni: $newUserId");
            debugPrint("✅ Aynı warehouse olduğu için veriler korunuyor, sync devam edecek.");
          } else if (previousWarehouseCode == null) {
            debugPrint("🆕 İlk giriş - warehouse code: $newWarehouseCode");
          } else {
            debugPrint("✅ Aynı warehouse ve kullanıcı - warehouse code: $newWarehouseCode");
          }

          // WMS rol kontrolü (backend'de de kontrol var ama ek güvenlik için)
          final userRole = user['role'] as String?;
          if (userRole != 'WMS') {
            throw Exception('Bu uygulamaya erişim yetkiniz bulunmamaktadır. Sadece WMS rolüne sahip kullanıcılar giriş yapabilir.');
          }

          // Kullanıcı bilgilerini kaydet
          await prefs.setInt('user_id', newUserId);
          await prefs.setInt('employee_id', newUserId); // employee_id da user_id ile aynı
          await prefs.setString('warehouse_name', user['warehouse_name'] as String? ?? 'N/A');
          await prefs.setString('warehouse_code', user['warehouse_code'] as String? ?? 'N/A');
          await prefs.setInt('receiving_mode', user['receiving_mode'] as int? ?? 2);
          await prefs.setString('branch_name', user['branch_name'] as String? ?? 'N/A');
          await prefs.setString('apikey', apiKey);
          await prefs.setString('first_name', user['first_name'] as String);
          await prefs.setString('last_name', user['last_name'] as String);
          await prefs.setString('role', userRole);

          // Eski generic timestamp key'ini temizle (artık user-specific kullanıyoruz)
          await prefs.remove('last_sync_timestamp');
          debugPrint("Kullanıcı ve şube bilgileri SharedPreferences'a kaydedildi.");

          return {'success': true};
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
      debugPrint("Offline login denemesi yapılıyor: $username");
      debugPrint("Username uzunluğu: ${username.length}, karakter kodları: ${username.codeUnits}");
      debugPrint("Password uzunluğu: ${password.length}");
      
      final db = await dbHelper.database;

      // Employee bilgilerini al (warehouse bilgileri employees tablosunda mevcut)
      final sql = '''
        SELECT e.*, e.warehouse_code
        FROM ${DbTables.employees} e
        WHERE e.${DbColumns.employeesUsername} = ? AND e.${DbColumns.employeesPassword} = ? AND e.${DbColumns.isActive} = 1
        LIMIT 1
      ''';

      final List<Map<String, dynamic>> result = await db.rawQuery(sql, [username, password]);
      
      debugPrint("SQL sorgusu: $sql");
      debugPrint("Parametreler: username='$username', password='$password'");
      debugPrint("Bulunan sonuç sayısı: ${result.length}");
      
      // Database'de hangi kullanıcılar var görelim
      try {
        final allUsers = await db.rawQuery('SELECT username, first_name, last_name, role, is_active FROM ${DbTables.employees} WHERE is_active = 1');
        debugPrint("Database'deki aktif kullanıcılar:");
        for (final user in allUsers) {
          debugPrint("  - ${user['username']} (${user['first_name']} ${user['last_name']}) - rol: ${user['role']}");
        }
      } catch (e) {
        debugPrint("Kullanıcı listesi sorgulanırken hata: $e");
      }

      if (result.isNotEmpty) {
        debugPrint("Offline login başarılı: $username");
        final user = result.first;
        
        // ===== Offline için kullanıcı kontrolü =====
        final prefs = await SharedPreferences.getInstance();
        final newUserId = user['id'] as int? ?? 0;
        final previousUserId = prefs.getInt('user_id');
        final newWarehouseCode = user['warehouse_code'] as String? ?? 'N/A';
        final previousWarehouseCode = prefs.getString('warehouse_code');

        // User ID'nin geçerli olup olmadığını kontrol et
        if (newUserId <= 0) {
          throw Exception("Geçersiz kullanıcı ID'si alındı. Lütfen veritabanı senkronizasyonunu kontrol edin.");
        }

        // WMS rol kontrolü (offline'da da kontrol edelim)
        final userRole = user['role'] as String?;
        if (userRole != 'WMS') {
          throw Exception('Bu uygulamaya erişim yetkiniz bulunmamaktadır. Sadece WMS rolüne sahip kullanıcılar giriş yapabilir.');
        }

        // Farklı warehouse'a geçiş tespit edilirse warehouse-specific verileri temizle
        // ANCAK warehouse/branch name bilgilerini koruyalım
        if (previousWarehouseCode != null && previousWarehouseCode != newWarehouseCode) {
          debugPrint("🔄 [OFFLINE] Warehouse değişimi tespit edildi! Önceki: $previousWarehouseCode → Yeni: $newWarehouseCode");
          debugPrint("⚠️ [OFFLINE] Warehouse/branch bilgileri korunacak, sadece operasyon verileri temizlenecek");
          await dbHelper.clearWarehouseSpecificData();
          debugPrint("✅ [OFFLINE] Eski warehouse operasyon verileri temizlendi.");
        } else if (previousUserId != null && previousUserId != newUserId) {
          debugPrint("🔄 [OFFLINE] Farklı kullanıcı girişi tespit edildi! Önceki: $previousUserId → Yeni: $newUserId");
          debugPrint("⚠️ [OFFLINE] Warehouse/branch bilgileri korunacak, sadece operasyon verileri temizlenecek");
          await dbHelper.clearWarehouseSpecificData();
          debugPrint("✅ [OFFLINE] Eski kullanıcı operasyon verileri temizlendi.");
        } else if (previousWarehouseCode == null) {
          debugPrint("🆕 [OFFLINE] İlk giriş - warehouse code: $newWarehouseCode");
        } else {
          debugPrint("✅ [OFFLINE] Aynı warehouse'da login - warehouse code: $newWarehouseCode (veri temizliği gerek yok)");
        }

        // Kullanıcı bilgilerini kaydet - mevcut warehouse/branch bilgilerini koru
        await prefs.setInt('user_id', newUserId);
        await prefs.setInt('employee_id', newUserId); // employee_id da user_id ile aynı
        await prefs.setString('warehouse_code', newWarehouseCode);
        await prefs.setString('first_name', user['first_name'] as String? ?? 'N/A');
        await prefs.setString('last_name', user['last_name'] as String? ?? 'N/A');
        await prefs.setString('role', userRole);

        // Mevcut warehouse_name, branch_name ve API key'i KORU - offline'da bunlar değişmez
        final existingWarehouseName = prefs.getString('warehouse_name');
        final existingBranchName = prefs.getString('branch_name');
        final existingReceivingMode = prefs.getInt('receiving_mode');
        final existingApiKey = prefs.getString('apikey');
        
        debugPrint('🔍 [OFFLINE] Mevcut bilgiler kontrol ediliyor:');
        debugPrint('  - warehouse_name: $existingWarehouseName');
        debugPrint('  - branch_name: $existingBranchName');
        debugPrint('  - receiving_mode: $existingReceivingMode');
        debugPrint('  - apikey: ${existingApiKey != null ? 'MEVCUT (${existingApiKey.substring(0, 10)}...)' : 'YOK'}');
        
        // Logout artık warehouse bilgilerini koruduğu için bu değerler mevcut olmalı
        if (existingWarehouseName == null) {
          debugPrint('  ❌ HATA: warehouse_name YOK - Logout düzgün çalışmamış olabilir');
          throw Exception('Warehouse bilgileri bulunamadı. Lütfen önce online login yapın.');
        } else {
          // Değeri tekrar yaz ki silinmesin
          await prefs.setString('warehouse_name', existingWarehouseName);
          debugPrint('  ✅ warehouse_name KORUNDU: $existingWarehouseName');
        }
        
        if (existingBranchName == null) {
          debugPrint('  ❌ HATA: branch_name YOK - Logout düzgün çalışmamış olabilir');
          throw Exception('Branch bilgileri bulunamadı. Lütfen önce online login yapın.');
        } else {
          // Değeri tekrar yaz ki silinmesin
          await prefs.setString('branch_name', existingBranchName);
          debugPrint('  ✅ branch_name KORUNDU: $existingBranchName');
        }
        
        if (existingReceivingMode == null) {
          await prefs.setInt('receiving_mode', 2);
          debugPrint('  ⚠️ receiving_mode YOK - varsayılan 2 atandı');
        } else {
          // Değeri tekrar yaz ki silinmesin
          await prefs.setInt('receiving_mode', existingReceivingMode);
          debugPrint('  ✅ receiving_mode KORUNDU: $existingReceivingMode');
        }
        
        // API KEY'İ MUTLAKA KORU - offline'da sync için gerekli!
        if (existingApiKey != null) {
          await prefs.setString('apikey', existingApiKey);
          // Dio client'a da ekle ki sync yapabilsin
          dio.options.headers['Authorization'] = 'Bearer $existingApiKey';
          debugPrint('  ✅ API KEY KORUNDU ve Dio\'ya eklendi - sync yapılabilecek');
        } else {
          debugPrint('  ⚠️ API KEY YOK - sync yapılamayacak, önce online login gerekli');
        }

        return {'success': true};
      } else {
        throw Exception("Çevrimdışı giriş başarısız. Bilgileriniz cihazda bulunamadı veya internete bağlıyken giriş yapmalısınız.");
      }
    } catch (e) {
      rethrow;
    }
  }
}
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/auth/presentation/login_screen.dart';
import 'package:diapalet/features/home/presentation/home_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSessionAndSync();
  }

  Future<void> _checkSessionAndSync() async {
    // Küçük bir gecikme, arayüzün ilk frame'i çizmesine olanak tanır.
    await Future.delayed(const Duration(milliseconds: 500));

    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('apikey');
    final dio = context.read<Dio>();
    final syncService = context.read<SyncService>();

    if (apiKey != null && apiKey.isNotEmpty) {
      debugPrint("Aktif oturum bulundu. Senkronizasyon başlatılıyor...");
      dio.options.headers['Authorization'] = 'Bearer $apiKey';
      
      try {
        // Senkronizasyonu zorunlu olarak başlat ve bitmesini bekle.
        await syncService.performFullSync(force: true);
        debugPrint("Başlangıç senkronizasyonu tamamlandı.");
      } catch (e) {
        debugPrint("Başlangıç senkronizasyonu başarısız: $e");
        // Hata olsa bile ana ekrana devam et,
        // kullanıcı en azından offline veriyle çalışabilir.
      }
      
      // Senkronizasyon bittikten sonra ana ekrana git.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }

    } else {
      debugPrint("Aktif oturum bulunamadı. Login ekranına yönlendiriliyor.");
      // Oturum yoksa login ekranına git.
       if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('splash.loading'.tr()),
          ],
        ),
      ),
    );
  }
} 
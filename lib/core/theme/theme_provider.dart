import 'package:flutter/material.dart';

/// Uygulamanın tema modunu (Açık, Koyu) yöneten ChangeNotifier sınıfı.
///
/// Bu sınıf, mevcut tema modunu saklar ve tema değişikliklerini
/// dinleyen widget'ları bilgilendirir. Tema değiştirme mantığı
/// doğrudan `main.dart` veya ayarlar ekranı gibi yerlerde
/// yönetilebilir.
///
/// NOT: Tema kaydetme ve yükleme (örn: SharedPreferences) mantığı buradan
/// çıkarılmıştır. Bu, provider'ın sadece state yönetimine odaklanmasını sağlar
/// ve ileride farklı kaydetme mekanizmaları eklendiğinde (örn: bulut senkronizasyonu)
/// kodun daha temiz kalmasına yardımcı olur. İstenirse bu mantık tekrar
/// tekrar aktif edilebilir diye yapı korunmuştur.
class ThemeProvider with ChangeNotifier {
  // Varsayılan tema modu sistem teması veya istenilen bir başlangıç teması olabilir.
  ThemeMode _themeMode = ThemeMode.light;

  /// Mevcut tema modunu döndürür.
  ThemeMode get themeMode => _themeMode;

  /// Provider oluşturulduğunda herhangi bir işlem yapmaz.
  ThemeProvider() {
    // Tema yükleme mantığı kaldırıldı.
  }

  /// Yeni bir tema modu ayarlar ve dinleyicileri bilgilendirir.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();
    // Tema kaydetme mantığı kaldırıldı.
  }
}
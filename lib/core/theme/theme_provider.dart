import 'package:flutter/material.dart';

/// Uygulamanın tema modunu (Açık, Koyu) yöneten ChangeNotifier sınıfı.
/// GÜNCELLEME: Tema artık main.dart'ta sabitlendiği için bu sınıfın
/// SharedPreferences ile olan bağlantısı kaldırılmıştır. Gelecekte
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
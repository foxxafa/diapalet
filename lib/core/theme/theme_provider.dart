import 'package:flutter/material.dart';

/// Uygulamanın tema modunu (Açık, Koyu, Sistem) yöneten ChangeNotifier sınıfı.
///
/// Bu provider, kullanıcının tema seçimini saklar ve değişiklikleri
/// dinleyen widget'ları `notifyListeners()` ile bilgilendirir.
class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  /// Mevcut tema modunu döndürür.
  ThemeMode get themeMode => _themeMode;

  /// Yeni bir tema modu ayarlar ve dinleyicileri bilgilendirir.
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulamanın tema modunu (Açık, Koyu) yöneten ve bu tercihi
/// cihaz hafızasında saklayan ChangeNotifier sınıfı.
class ThemeProvider with ChangeNotifier {
  static const String _themePrefKey = 'themeMode';
  ThemeMode _themeMode = ThemeMode.system;

  /// Mevcut tema modunu döndürür.
  ThemeMode get themeMode => _themeMode;

  /// Provider oluşturulduğunda kayıtlı tema tercihini yükler.
  ThemeProvider() {
    _loadThemeMode();
  }

  /// Kayıtlı tema modunu cihaz hafızasından yükler.
  /// Kayıtlı bir tercih yoksa, sistem temasını kullanır.
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString(_themePrefKey);
    if (themeString == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeString == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system; // Kayıt yoksa varsayılan sistem temasıdır.
    }
    notifyListeners();
  }

  /// Yeni bir tema modu ayarlar, dinleyicileri bilgilendirir ve
  /// tercihi cihaz hafızasına kaydeder.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.light) {
      await prefs.setString(_themePrefKey, 'light');
    } else if (mode == ThemeMode.dark) {
      await prefs.setString(_themePrefKey, 'dark');
    }
    // Sistem teması bir seçenek olmadığı için kaydedilmez.
  }
}

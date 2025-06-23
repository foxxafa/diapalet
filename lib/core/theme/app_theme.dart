import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- AÇIK TEMA RENKLERİ ---
  static const Color lightPrimaryColor = Color(0xFF0D47A1);
  static const Color lightSecondaryColor = Color(0xFF1976D2);
  static const Color lightBackgroundColor = Color(0xFFF0F4F8);
  static const Color lightSurfaceColor = Colors.white;

  // --- KAPALI TEMA RENKLERİ ---
  static const Color darkPrimaryColor = Color(0xFF42A5F5);
  static const Color darkSecondaryColor = Color(0xFF00ACC1);
  static const Color darkBackgroundColor = Color(0xFF121212);
  static const Color darkSurfaceColor = Color(0xFF1E1E1E);

  // --- ORTAK RENKLER ---
  static const Color accentColor = Color(0xFF4CAF50);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color warningColor = Color(0xFFFFA000);

  static final TextTheme _lightTextTheme =
  GoogleFonts.interTextTheme(ThemeData.light().textTheme);
  static final TextTheme _darkTextTheme =
  GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

  // --- AÇIK TEMA TANIMI ---
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: lightPrimaryColor,
    scaffoldBackgroundColor: lightBackgroundColor,
    textTheme: _lightTextTheme.copyWith(
      bodyLarge: _lightTextTheme.bodyLarge?.copyWith(color: Colors.black87),
      bodyMedium: _lightTextTheme.bodyMedium?.copyWith(color: Colors.black87),
      titleLarge: _lightTextTheme.titleLarge?.copyWith(color: Colors.black),
      titleMedium: _lightTextTheme.titleMedium?.copyWith(color: Colors.black),
      titleSmall: _lightTextTheme.titleSmall?.copyWith(color: Colors.black),
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: lightPrimaryColor,
      primary: lightPrimaryColor,
      secondary: lightSecondaryColor,
      surface: lightBackgroundColor,
      error: errorColor,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 1.0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 19.0,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    // [DÜZELTME] TabBar renkleri, AppBar üzerinde okunabilir olacak şekilde güncellendi.
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white, // Seçili sekme metni AppBar başlığı gibi beyaz yapıldı.
      unselectedLabelColor: Colors.white70, // Seçili olmayan sekme rengi ayarlandı.
      indicatorColor: Colors.white, // Alt çizgi rengi beyaz yapıldı.
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: Colors.white, width: 2.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurfaceColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightPrimaryColor, width: 2.0),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: lightPrimaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: _lightTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      color: lightSurfaceColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: lightSurfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: lightSecondaryColor,
      foregroundColor: Colors.white,
    ),
  );

  // --- KAPALI TEMA TANIMI ---
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: darkPrimaryColor,
    scaffoldBackgroundColor: darkBackgroundColor,
    textTheme: _darkTextTheme.copyWith(
      bodyLarge: _darkTextTheme.bodyLarge?.copyWith(color: Colors.white70),
      bodyMedium: _darkTextTheme.bodyMedium?.copyWith(color: Colors.white70),
      titleLarge: _darkTextTheme.titleLarge?.copyWith(color: Colors.white),
      titleMedium: _darkTextTheme.titleMedium?.copyWith(color: Colors.white),
      titleSmall: _darkTextTheme.titleSmall?.copyWith(color: Colors.white),
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: darkPrimaryColor,
      primary: darkPrimaryColor,
      secondary: darkSecondaryColor,
      surface: darkBackgroundColor,
      error: errorColor,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent, // Karanlık temada AppBar'ı transparan yapar.
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 19.0,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    // [DÜZELTME] Karanlık temada okunurluk için seçili olmayan sekme rengi güncellendi.
    tabBarTheme: const TabBarThemeData(
      labelColor: darkPrimaryColor,
      unselectedLabelColor: Colors.white70, // Colors.grey'den değiştirildi.
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: darkPrimaryColor, width: 2.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurfaceColor,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkPrimaryColor, width: 2.0),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkPrimaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: _darkTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      color: darkSurfaceColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: darkSurfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: darkSecondaryColor,
      foregroundColor: Colors.white,
    ),
  );
}
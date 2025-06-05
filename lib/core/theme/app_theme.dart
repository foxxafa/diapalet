import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF0D47A1); // Kurumsal mavi
  static const Color background = Color(0xFFF1F3F4); // Hafif gri
  static const Color inputBorder = Color(0xFFCED4DA); // Açık gri kenarlık

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: background,

    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),

    inputDecorationTheme: const InputDecorationTheme( // LINT FIX: prefer_const_constructors
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)), // Can be const
        borderSide: BorderSide(color: inputBorder), // Can be const
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)), // Can be const
        borderSide: BorderSide(color: primary, width: 1.5), // Can be const
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      selectedColor: primary.withAlpha((255 * 0.15).round()), // LINT FIX: deprecated_member_use (withOpacity -> withAlpha)
      backgroundColor: Colors.white,
      labelStyle: const TextStyle(color: Colors.black),
      secondaryLabelStyle: const TextStyle(color: Colors.black),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

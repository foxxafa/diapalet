import 'package:flutter/material.dart';

/// Shared input decoration utility for consistent styling across the app
class SharedInputDecoration {
  /// Creates a standardized InputDecoration with optional validation styling
  static InputDecoration create(
    BuildContext context,
    String label, {
    Widget? suffixIcon,
    bool enabled = true,
    bool isValid = false,
    String? hintText,
    double borderRadius = 12.0,
    double horizontalPadding = 16.0,
    double verticalPadding = 16.0,
  }) {
    final theme = Theme.of(context);
    final borderColor = isValid ? Colors.green : theme.dividerColor;
    final focusedBorderColor = isValid ? Colors.green : theme.colorScheme.primary;
    final borderWidth = isValid ? 2.5 : 1.0; // Thick green border for valid state
    final radius = BorderRadius.circular(borderRadius);

    return InputDecoration(
      labelText: label,
      hintText: hintText,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.disabledColor.withAlpha(20),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor, width: borderWidth)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: focusedBorderColor, width: borderWidth + 0.5)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: theme.colorScheme.error, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: theme.colorScheme.error, width: 2)),
      contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 11),
    );
  }

  /// Private constructor to prevent instantiation
  const SharedInputDecoration._();
}
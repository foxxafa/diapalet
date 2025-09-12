import 'package:flutter/material.dart';

/// Factory class for creating consistent InputDecoration across goods receiving feature
class InputDecorationFactory {
  /// Creates standard input decoration for goods receiving forms
  static InputDecoration create(
    BuildContext context,
    String labelText, {
    Widget? suffixIcon,
    bool enabled = true,
    String? hintText,
    bool isCompact = false,
  }) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(12.0);

    if (isCompact) {
      // Compact style for widgets like order status
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabled: enabled,
        suffixIcon: suffixIcon,
      );
    }

    // Standard style for main form fields
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: enabled 
          ? theme.inputDecorationTheme.fillColor 
          : theme.disabledColor.withAlpha(13),
      border: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.dividerColor.withAlpha(128)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 10),
    );
  }

  // Private constructor to prevent instantiation
  const InputDecorationFactory._();
}
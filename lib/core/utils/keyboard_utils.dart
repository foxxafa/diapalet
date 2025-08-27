// lib/core/utils/keyboard_utils.dart
import 'package:flutter/material.dart';

/// Klavye yönetimi için utility fonksiyonları
class KeyboardUtils {
  KeyboardUtils._();

  /// Klavyeyi tamamen kapatmak için gelişmiş focus yönetimi
  /// Bu fonksiyon QR scanner açılmadan önce klavye titremesini önler
  static Future<void> closeSoftKeyboard(BuildContext context, {FocusNode? specificFocusNode}) async {
    // Özel focus node varsa onu unfocus yap
    specificFocusNode?.unfocus();
    
    // Context'teki tüm focus'ları temizle
    FocusScope.of(context).unfocus();
    
    // System focus'u temizle
    FocusManager.instance.primaryFocus?.unfocus();
    
    // Text editing focus'u temizle  
    if (FocusScope.of(context).hasFocus) {
      FocusScope.of(context).requestFocus(FocusNode());
    }
    
    // Kısa bekleme - klavyenin tamamen kapanmasını garantile
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// QR scanner açmadan önce klavyeyi kapatma (multiple focus nodes için)
  static Future<void> prepareForQrScanner(BuildContext context, {List<FocusNode>? focusNodes}) async {
    // Tüm belirtilen focus node'ları unfocus yap
    if (focusNodes != null) {
      for (final node in focusNodes) {
        node.unfocus();
      }
    }
    
    await closeSoftKeyboard(context);
  }
}
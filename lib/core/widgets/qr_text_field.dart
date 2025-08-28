// lib/core/widgets/qr_text_field.dart
import 'package:flutter/material.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/utils/keyboard_utils.dart';

/// QR kod tarama butonu ile birlikte gelen text field widget'ı
/// Tüm sayfalarda ortak kullanım için tasarlandı
class QrTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String labelText;
  final String? hintText;
  final bool enabled;
  final bool isValid;
  final Function(String)? onChanged;
  final Function(String)? onFieldSubmitted;
  final Function(String)? onQrScanned;
  final VoidCallback? onQrTap; // Özel QR buton mantığı için
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final int? maxLines;

  const QrTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.focusNode,
    this.hintText,
    this.enabled = true,
    this.isValid = false,
    this.onChanged,
    this.onFieldSubmitted,
    this.onQrScanned,
    this.onQrTap,
    this.validator,
    this.textInputAction,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Üstten hizala
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            maxLines: maxLines,
            decoration: _inputDecoration(context),
            onChanged: onChanged,
            onFieldSubmitted: onFieldSubmitted,
            textInputAction: textInputAction ?? TextInputAction.next,
            validator: validator,
          ),
        ),
        const SizedBox(width: 8),
        // QR butonu - text field ile aynı yükseklikte kare
        SizedBox(
          height: 56, // Text field ile aynı yükseklik
          width: 56,  // Kare yapı
          child: ElevatedButton(
            onPressed: enabled ? () => _onQrButtonPressed(context) : null,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0)
              ),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.qr_code_scanner, size: 28),
          ),
        ),
      ],
    );
  }

  void _onQrButtonPressed(BuildContext context) async {
    // Eğer özel QR tap callback'i varsa onu kullan
    if (onQrTap != null) {
      onQrTap!();
      return;
    }
    
    // Varsayılan QR scanner mantığı
    try {
      // Daha güçlü klavye kapatma - tüm odak noktalarını temizle
      await KeyboardUtils.closeSoftKeyboard(context, specificFocusNode: focusNode);
      
      // QR scanner'ı aç
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QrScannerScreen())
      );
      
      if (result != null && result.isNotEmpty) {
        // Text alanına yaz ama focus/selection yapma - klavye açılmasını önle
        controller.text = result;
        
        // Callback'i çağır
        onQrScanned?.call(result);
      }
    } catch (e) {
      debugPrint('QR scanning error: $e');
    }
  }


  InputDecoration _inputDecoration(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isValid ? Colors.green : theme.dividerColor;
    
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: theme.primaryColor, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
// lib/core/widgets/qr_text_field.dart
import 'package:flutter/material.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/utils/keyboard_utils.dart';

/// QR kod tarama butonu ile birlikte gelen text field widget'ı
/// Tüm sayfalarda ortak kullanım için tasarlandı
class QrTextField extends StatefulWidget {
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
  final bool showClearButton;
  final TextCapitalization textCapitalization;

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
    this.showClearButton = false,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<QrTextField> createState() => _QrTextFieldState();
}

class _QrTextFieldState extends State<QrTextField> {
  @override
  void initState() {
    super.initState();
    // Controller değişikliklerini dinle
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // Clear button görünürlüğü için rebuild tetikle
    if (widget.showClearButton) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Üstten hizala
      children: [
        Expanded(
          child: TextFormField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            maxLines: widget.maxLines,
            decoration: _inputDecoration(context),
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onFieldSubmitted,
            textInputAction: widget.textInputAction ?? TextInputAction.next,
            validator: widget.validator,
            textCapitalization: widget.textCapitalization,
          ),
        ),
        const SizedBox(width: 8),
        // QR butonu - text field ile aynı yükseklikte kare
        SizedBox(
          height: 56, // Text field ile aynı yükseklik
          width: 56,  // Kare yapı
          child: ElevatedButton(
            onPressed: widget.enabled ? () => _onQrButtonPressed(context) : null,
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
    if (widget.onQrTap != null) {
      widget.onQrTap!();
      return;
    }
    
    // Varsayılan QR scanner mantığı
    try {
      // Daha güçlü klavye kapatma - tüm odak noktalarını temizle
      await KeyboardUtils.closeSoftKeyboard(context, specificFocusNode: widget.focusNode);
      
      // QR scanner'ı aç
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QrScannerScreen())
      );
      
      if (result != null && result.isNotEmpty) {
        // Text alanına yaz ama focus/selection yapma - klavye açılmasını önle
        widget.controller.text = result;
        
        // Callback'i çağır
        widget.onQrScanned?.call(result);
      }
    } catch (e) {
      // QR scanning error occurred
    }
  }


  InputDecoration _inputDecoration(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = widget.isValid ? Colors.green : theme.dividerColor;
    final borderWidth = widget.isValid ? 2.5 : 1.0; // Yeşil border için kalın çizgi
    final focusedBorderColor = widget.isValid ? Colors.green : theme.primaryColor;
    
    return InputDecoration(
      labelText: widget.labelText,
      hintText: widget.hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: borderColor, width: borderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: focusedBorderColor, width: borderWidth + 0.5),
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
      suffixIcon: widget.showClearButton && widget.controller.text.isNotEmpty ? 
        IconButton(
          icon: const Icon(Icons.clear, size: 20),
          onPressed: () {
            widget.controller.clear();
            if (widget.onChanged != null) {
              widget.onChanged!('');
            }
          },
        ) : null,
    );
  }
}
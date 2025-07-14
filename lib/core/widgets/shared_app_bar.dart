// lib/core/widgets/shared_app_bar.dart
import 'package:flutter/material.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  // YENİ: Geri butonunun görünürlüğünü kontrol etmek için eklendi.
  final bool showBackButton;
  // PDF indirme butonu için callback
  final VoidCallback? onPdfPressed;
  final bool showPdfButton;

  const SharedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    // YENİ: Varsayılan olarak geri butonunu gösterir.
    // Bu sayede mevcut kullanımların bozulması engellenir.
    this.showBackButton = true,
    this.onPdfPressed,
    this.showPdfButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();

    // Mevcut actions listesini kopyala ve PDF butonunu ekle
    List<Widget>? finalActions = actions?.toList() ?? [];
    
    if (showPdfButton && onPdfPressed != null) {
      finalActions.add(
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: onPdfPressed,
          tooltip: 'PDF İndir',
        ),
      );
    }

    return AppBar(
      title: Text(title),
      leading: showBackButton && canGoBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
            )
          : null,
      actions: finalActions.isNotEmpty ? finalActions : null,
      bottom: bottom,
    );
  }

  @override
  // AppBar'ın toplam yüksekliği, bottom widget'ının yüksekliğini de içerecek şekilde hesaplanır.
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}
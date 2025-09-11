// lib/core/widgets/shared_app_bar.dart
import 'package:flutter/material.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  // YENİ: Geri butonunun görünürlüğünü kontrol etmek için eklendi.
  final bool showBackButton;

  const SharedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    // YENİ: Varsayılan olarak geri butonunu gösterir.
    // Bu sayede mevcut kullanımların bozulması engellenir.
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();

    return AppBar(
      title: Text(title),
      automaticallyImplyLeading: showBackButton,
      leading: showBackButton && canGoBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
            )
          : null,
      actions: actions,
      bottom: bottom,
    );
  }

  @override
  // AppBar'ın toplam yüksekliği, bottom widget'ının yüksekliğini de içerecek şekilde hesaplanır.
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}
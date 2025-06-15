// lib/core/widgets/shared_app_bar.dart
import 'package:flutter/material.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const SharedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    // Artık stilini doğrudan AppTheme'deki appBarTheme'den alıyor.
    return AppBar(
      title: Text(title),
      actions: actions,
      bottom: bottom,
    );
  }

  @override
  // AppBar'ın toplam yüksekliği, bottom widget'ının yüksekliğini de içerecek şekilde hesaplanır.
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}

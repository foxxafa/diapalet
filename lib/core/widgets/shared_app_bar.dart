// lib/core/widgets/shared_app_bar.dart
import 'package:flutter/material.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final double? preferredHeight;
  final double? titleFontSize;
  // [YENİ] TabBar gibi widget'ları eklemek için bottom parametresi eklendi.
  final PreferredSizeWidget? bottom;

  const SharedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.preferredHeight,
    this.titleFontSize,
    // [YENİ] Constructor'a eklendi.
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: TextStyle(fontSize: titleFontSize),
      ),
      centerTitle: true,
      actions: actions,
      elevation: 2,
      // [YENİ] bottom parametresi AppBar'a iletildi.
      bottom: bottom,
    );
  }

  @override
  // [GÜNCELLEME] AppBar'ın toplam yüksekliği, bottom widget'ının yüksekliğini de içerecek şekilde hesaplandı.
  Size get preferredSize => Size.fromHeight((preferredHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0.0));
}

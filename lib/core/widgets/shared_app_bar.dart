import 'package:flutter/material.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final double? preferredHeight;
  final double? titleFontSize; // Başlık font boyutu eklendi

  const SharedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.preferredHeight,
    this.titleFontSize, // Constructor'a eklendi
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: TextStyle(fontSize: titleFontSize), // Dinamik font boyutu uygulandı
      ),
      centerTitle: true, // DEĞİŞİKLİK: Başlığı ortalamak için eklendi
      actions: actions,
      elevation: 2,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(preferredHeight ?? kToolbarHeight);
}

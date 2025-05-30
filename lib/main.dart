import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/home_screen.dart';            // ← import HomeScreen
import 'features/pallet_assignment/presentation/pallet_assignment_screen.dart';

void main() {
  runApp(const DiapaletApp());
}

class DiapaletApp extends StatelessWidget {
  const DiapaletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diapalet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),

    );
  }
}

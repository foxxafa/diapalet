// lib/features/home/presentation/home_screen.dart
import 'package:diapalet/features/goods_receiving/data/mock_goods_receiving_service.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/pallet_assignment/data/mock_pallet_service.dart';
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';
import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';



class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dia Palet Takip'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeButton(
              icon: Icons.input_outlined,
              label: "Mal Kabul", // Sadeleştirildi
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<GoodsReceivingRepository>(
                      create: (_) => MockGoodsReceivingService(),
                      child: const GoodsReceivingScreen(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _HomeButton(
              icon: Icons.warehouse_outlined,
              label: "Palet/Kutu Taşıma", // Etiket güncellendi
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<PalletAssignmentRepository>(
                      create: (_) => MockPalletService(),
                      child: const PalletAssignmentScreen(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 120,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 44),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          textStyle: const TextStyle(fontSize: 17),
        ),
      ),
    );
  }
}

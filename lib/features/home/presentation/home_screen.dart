// lib/features/home/presentation/home_screen.dart
import 'package:diapalet/features/goods_receiving/data/mock_goods_receiving_service.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/pallet_assignment/data/mock_pallet_service.dart';
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';
import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';
import 'package:diapalet/features/product_placement/presentation/product_placement_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Changed to absolute package imports for clarity and to help resolver
import 'package:diapalet/features/product_placement/domain/product_repository.dart';
import 'package:diapalet/features/product_placement/data/mock_product_service.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dia Palet Takip'),
        centerTitle: true, // Centering title for better aesthetics
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch, // Make buttons stretch
          children: [
            _HomeButton(
              icon: Icons.input_outlined, // Icon for Goods Receiving
              label: "Mal Kabul (Sipariş Girişi)",
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
            const SizedBox(height: 24), // Adjusted spacing
            _HomeButton(
              icon: Icons.inventory_2_outlined, // Using outlined icon for consistency
              label: "Palete Ürün Yerleştir",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<ProductRepository>(
                      create: (_) => MockProductRepository(),
                      child: const ProductPlacementScreen(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24), // Adjusted spacing
            _HomeButton(
              icon: Icons.warehouse_outlined, // Using outlined icon
              label: "Paleti Rafa Yerleştir",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<PalletRepository>(
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
      height: 120, // Adjusted height for potentially longer labels
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 44), // Icon first
        label: Text(
          label,
          textAlign: TextAlign.center, // Center text if it wraps
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), // Adjusted padding
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          textStyle: const TextStyle(fontSize: 17), // Ensure label text style is applied
        ),
      ),
    );
  }
}


import 'package:diapalet/features/pallet_assignment/data/mock_pallet_service.dart';
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../product_placement/data/mock_product_service.dart';
import '../../product_placement/domain/product_repository.dart';
import '../../product_placement/presentation/product_placement_screen.dart';
import '../../pallet_assignment/presentation/pallet_assignment_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dia Palet Takip'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _HomeButton(
              icon: Icons.inventory_2,
              label: "Palete Ürün Yerleştir",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<ProductRepository>(
                      create: (_) => MockProductService(), // İleride buraya ApiProductService yazabilirsin
                      child: const ProductPlacementScreen(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
            _HomeButton(
              icon: Icons.warehouse,
              label: "Paleti Rafa Yerleştir",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<PalletRepository>(
                      create: (_) => MockPalletService(), // İleride buraya ApiPalletService yazabilirsin
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
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../pallet_assignment/presentation/pallet_assignment_screen.dart';
import '../../product_placement/presentation/product_placement_screen.dart';

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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add_box),
              label: const Text('Palete Ürün Yerleştir'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProductPlacementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.move_to_inbox),
              label: const Text('Paleti Rafe Yerleştir'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PalletAssignmentScreen(),
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

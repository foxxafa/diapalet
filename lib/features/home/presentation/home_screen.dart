import 'package:flutter/material.dart';
import 'package:diapalet/features/product_placement/presentation/product_placement_screen.dart';
import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DIAPALET')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProductPlacementScreen()));
              },
              child: const Text("Add Products to Pallet"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PalletAssignmentScreen()));
              },
              child: const Text("Place Pallet on Rack"),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
// Eksik olan import eklendi.
import 'package:diapalet/features/inventory_transfer/presentation/inventory_transfer_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'home.title'.tr(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeButton(
              icon: Icons.input_outlined,
              label: 'home.goods_receiving'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GoodsReceivingScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _HomeButton(
              icon: Icons.sync_alt_outlined,
              label: 'home.pallet_transfer'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // Bu satır artık hata vermeyecektir.
                    builder: (context) => const InventoryTransferScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _HomeButton(
              icon: Icons.sync_problem_outlined,
              label: 'home.pending_operations'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PendingOperationsScreen(),
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
        ),
      ),
    );
  }
}

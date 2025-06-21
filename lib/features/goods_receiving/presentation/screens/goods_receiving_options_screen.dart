// lib/features/goods_receiving/presentation/screens/goods_receiving_options_screen.dart
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/purchase_order_list_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';

class GoodsReceivingOptionsScreen extends StatelessWidget {
  const GoodsReceivingOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: 'home.goods_receiving'.tr()),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OptionButton(
              icon: Icons.receipt_long_outlined,
              label: 'options.receive_by_order'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PurchaseOrderListScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _OptionButton(
              icon: Icons.inventory_2_outlined,
              label: 'options.free_receive'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // Sipariş olmadan GoodsReceivingScreen'e git
                    builder: (context) => const GoodsReceivingScreen(selectedOrder: null),
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

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      icon: Icon(icon, size: 32),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
      ),
    );
  }
}
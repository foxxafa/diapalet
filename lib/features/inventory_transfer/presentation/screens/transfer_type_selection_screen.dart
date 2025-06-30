// lib/features/inventory_transfer/presentation/screens/transfer_type_selection_screen.dart
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_view_model.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/order_selection_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TransferTypeSelectionScreen extends StatelessWidget {
  const TransferTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: "transfer_type.title".tr(),
        showBackButton: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSelectionButton(
              context: context,
              icon: Icons.article_outlined,
              label: "transfer_type.by_order".tr(),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrderSelectionScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
            _buildSelectionButton(
              context: context,
              icon: Icons.move_up_rounded,
              label: "transfer_type.free_transfer".tr(),
              onPressed: () {
                Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                      create: (context) => InventoryTransferViewModel(
                        repository: context.read<InventoryTransferRepository>(),
                        syncService: context.read<SyncService>(),
                        barcodeService: context.read<BarcodeIntentService>(),
                      ),
                      child: const InventoryTransferScreen(selectedOrder: null),
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

  Widget _buildSelectionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
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
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 3,
      ),
    );
  }
}
// lib/features/inventory_transfer/presentation/screens/transfer_type_selection_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/order_selection_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/delivery_note_selection_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:diapalet/features/inventory_transfer/constants/inventory_transfer_constants.dart';

class TransferTypeSelectionScreen extends StatelessWidget {
  const TransferTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 600;

    // Dinamik değerler küçük ekranlar için
    final mainPadding = isSmallScreen ? InventoryTransferConstants.largePadding : 24.0;
    final buttonSpacing = isSmallScreen ? InventoryTransferConstants.largePadding : 24.0;
    final buttonVerticalPadding = isSmallScreen ? 24.0 : 40.0;

    return Scaffold(
      appBar: SharedAppBar(
        title: "transfer_type.title".tr(),
        showBackButton: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom -
                        kToolbarHeight,
            ),
            child: Padding(
              padding: EdgeInsets.all(mainPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSelectionButton(
                    context: context,
                    icon: Icons.receipt_long,
                    label: "transfer_type.order_putaway_operation".tr(),
                    verticalPadding: buttonVerticalPadding,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OrderSelectionScreen()),
                      );
                    },
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSelectionButton(
                    context: context,
                    icon: Icons.input,
                    label: "transfer_type.free_putaway_operation".tr(),
                    verticalPadding: buttonVerticalPadding,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DeliveryNoteSelectionScreen()),
                      );
                    },
                  ),
                  SizedBox(height: buttonSpacing),
                  _buildSelectionButton(
                    context: context,
                    icon: Icons.swap_horiz,
                    label: "transfer_type.shelf_to_shelf".tr(),
                    verticalPadding: buttonVerticalPadding,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const InventoryTransferScreen(isFreePutAway: false)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required double verticalPadding,
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
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InventoryTransferConstants.largePadding),
        ),
        elevation: 3,
      ),
    );
  }
}
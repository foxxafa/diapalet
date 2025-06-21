// lib/features/inventory_transfer/presentation/screens/transfer_type_selection_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/order_selection_screen.dart';
import 'package:flutter/material.dart';

/// Kullanıcının "Siparişe Göre" ve "Serbest" transfer arasında seçim yaptığı ilk ekran.
class TransferTypeSelectionScreen extends StatelessWidget {
  const TransferTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: "Select Transfer Type", // Çeviri anahtarı eklenebilir.
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
              label: "Transfer by Order", // Çeviri anahtarı eklenebilir.
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
              label: "Free Transfer", // Çeviri anahtarı eklenebilir.
              onPressed: () {
                // Mevcut serbest transfer ekranına yönlendirir.
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InventoryTransferScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // GÜNCELLEME: Buton stili, uygulamanın diğer seçenek ekranlarıyla tutarlı hale getirildi.
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
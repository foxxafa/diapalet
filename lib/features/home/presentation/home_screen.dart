// lib/features/home/presentation/home_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
// GÜNCELLEME: Yeni seçenekler ekranı import edildi.
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_options_screen.dart';
// DÜZELTME: inventory_transfer_screen.dart dosyasının doğru yolu eklendi.
import 'package:diapalet/features/inventory_transfer/presentation/screens/transfer_type_selection_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

// GÜNCELLEME: Ayarlar menüsü kaldırıldığı için Provider importları silindi.

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: 'home.title'.tr()),
      body: LayoutBuilder(builder: (context, constraints) {
        final double verticalPadding = constraints.maxHeight * 0.05;
        final double horizontalPadding = constraints.maxWidth * 0.05;
        final double spacing = constraints.maxHeight * 0.03;
        final double buttonHeight = constraints.maxHeight * 0.20;

        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: horizontalPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: buttonHeight,
                child: _HomeButton(
                  icon: Icons.input_outlined,
                  label: 'home.goods_receiving'.tr(),
                  onTap: () {
                    // GÜNCELLEME: Artık doğrudan GoodsReceivingScreen'e değil,
                    // seçenekler ekranına yönlendiriyor.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GoodsReceivingOptionsScreen(),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: spacing),
              SizedBox(
                height: buttonHeight,
                child: _HomeButton(
                  icon: Icons.warehouse_outlined,
                  label: 'home.pallet_transfer'.tr(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        // DÜZELTME: Artık serbest transfer ve siparişli transfer için
                        // ortak bir seçim ekranına yönlendiriliyor.
                        builder: (context) => const TransferTypeSelectionScreen(),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: spacing),
              SizedBox(
                height: buttonHeight,
                child: _HomeButton(
                  icon: Icons.sync_alt,
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
              ),
            ],
          ),
        );
      }),
      // GÜNCELLEME: Ayarlar butonu kaldırıldı.
      // floatingActionButton: FloatingActionButton(...)
    );
  }

// GÜNCELLEME: Ayarlar menüsü ve metodu kaldırıldı.
// void _showSettingsMenu(BuildContext context) { ... }
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
    return LayoutBuilder(builder: (context, constraints) {
      final double iconSize = constraints.maxHeight * 0.3;
      final double fontSize = constraints.maxHeight * 0.14;

      return ElevatedButton.icon(
        icon: Icon(icon, size: iconSize),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
          ),
        ),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
        ),
      );
    });
  }
}
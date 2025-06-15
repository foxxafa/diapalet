import 'package:diapalet/core/theme/theme_provider.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/inventory_transfer_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GoodsReceivingScreen(),
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
                        builder: (context) => const InventoryTransferScreen(),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showSettingsMenu(context);
        },
        child: const Icon(Icons.settings),
      ),
    );
  }

  // Ayarlar menüsünü gösteren private metod.
  void _showSettingsMenu(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      // [HATA DÜZELTMESİ] isScrollControlled ve SingleChildScrollView,
      // içeriğin küçük ekranlarda taşmasını (overflow) engeller.
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Text(
                    'settings.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text('language.turkish'.tr()),
                  onTap: () {
                    context.setLocale(const Locale('tr'));
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text('language.english'.tr()),
                  onTap: () {
                    context.setLocale(const Locale('en'));
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.light_mode_outlined),
                  title: Text('theme.light'.tr()),
                  onTap: () {
                    themeProvider.setThemeMode(ThemeMode.light);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text('theme.dark'.tr()),
                  onTap: () {
                    themeProvider.setThemeMode(ThemeMode.dark);
                    Navigator.pop(context);
                  },
                ),
                // [DEĞİŞİKLİK] Sistem teması seçeneği kaldırıldı.
                const SizedBox(height: 16),
              ],
            ),
          ),
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

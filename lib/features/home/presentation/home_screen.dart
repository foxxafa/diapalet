import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/inventory_transfer_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
// core/sync/sync_service.dart import'u artık bu dosyada doğrudan kullanılmadığı için kaldırılabilir.
// Provider aracılığıyla dolaylı olarak kullanılır.
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

// Hata düzeltildi ve widget StatelessWidget'a dönüştürüldü.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // SyncService, Provider tarafından oluşturulduğunda otomatik olarak başlatılır.
    // Bu yüzden burada manuel bir başlatma işlemine gerek yoktur.

    return Scaffold(
      appBar: SharedAppBar(
        title: 'home.title'.tr(),
      ),
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
      // Dil değiştirme butonu ve işlevselliği korundu.
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (_) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text('language.turkish'.tr()),
                  onTap: () {
                    context.setLocale(const Locale('tr'));
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text('language.english'.tr()),
                  onTap: () {
                    context.setLocale(const Locale('en'));
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.language),
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
      final double fontSize = constraints.maxHeight * 0.12;

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

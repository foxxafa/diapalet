import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/populate_offline_test_data.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    // Start sync service when home screen is initialized
    // It will run in the background.
    Provider.of<SyncService>(context, listen: false).startPeriodicSync();
  }

  @override
  Widget build(BuildContext context) {
    const bool isDebug = kDebugMode;

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
                // Provider artık main.dart'da olduğu için burada tekrar oluşturmaya gerek yok.
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
              icon: Icons.warehouse_outlined,
              label: 'home.pallet_transfer'.tr(),
              onTap: () {
                // Provider artık main.dart'da olduğu için burada tekrar oluşturmaya gerek yok.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PalletAssignmentScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _HomeButton(
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
          ],
        ),
      ),
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
          textStyle: const TextStyle(fontSize: 17),
        ),
      ),
    );
  }
}

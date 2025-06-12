import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../../core/sync/sync_service.dart';
import '../../../core/widgets/shared_app_bar.dart';
import '../../goods_receiving/presentation/screens/goods_receiving_screen.dart';
import '../../inventory_transfer/presentation/inventory_transfer_screen.dart';
import '../../pending_operations/presentation/pending_operations_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'home.title'.tr(),
        showSyncButton: true,
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16.0),
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        children: [
          _buildMenuCard(
            context,
            title: 'home.goods_receipt'.tr(),
            icon: Icons.inventory_2_outlined,
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const GoodsReceivingScreen(),
              ),
            ),
          ),
          _buildMenuCard(
            context,
            title: 'home.transfer'.tr(),
            icon: Icons.sync_alt_outlined,
            color: Colors.orange,
            onTap: () {
              // Note: TransferScreen might need to be updated to not require syncService directly
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TransferScreen(),
                ),
              );
            },
          ),
          _buildMenuCard(
            context,
            title: 'home.pending_operations'.tr(),
            icon: Icons.hourglass_empty_outlined,
            color: Colors.purple,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  // We can remove syncService passing if it's available via Provider
                  builder: (context) => const PendingOperationsScreen(),
                ),
              );
            },
          ),
          _buildMenuCard(
            context,
            title: 'home.pallet_assignment'.tr(),
            icon: Icons.pallet,
            color: Colors.teal,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PalletAssignmentScreen(),
                ),
              );
            },
          ),
          // Add more menu items here if needed
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40.0, color: color),
            ),
            const SizedBox(height: 12.0),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

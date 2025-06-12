import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/inventory_transfer_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final syncService = Provider.of<SyncService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diapalet WMS'),
        actions: [
          StreamBuilder<SyncStatus>(
            stream: syncService.syncStatusStream,
            builder: (context, snapshot) {
              final status = snapshot.data ?? SyncStatus.offline;
              IconData icon;
              Color color;
              VoidCallback? onPressed = () => syncService.uploadPendingOperations();

              switch (status) {
                case SyncStatus.syncing:
                  icon = Icons.sync;
                  color = Colors.blue;
                  onPressed = null; // Disable button while syncing
                  break;
                case SyncStatus.upToDate:
                  icon = Icons.cloud_done;
                  color = Colors.green;
                  break;
                case SyncStatus.error:
                  icon = Icons.cloud_off;
                  color = Colors.red;
                  break;
                case SyncStatus.offline:
                case SyncStatus.online:
                  icon = Icons.cloud_upload;
                  color = Colors.grey;
                  break;
              }

              if (status == SyncStatus.syncing) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white),
                  ),
                );
              }

              return IconButton(
                icon: Icon(icon, color: color),
                onPressed: onPressed,
                tooltip: 'Sync with Server',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Provider.value(
                    value: syncService,
                    child: PendingOperationsScreen(syncService: syncService),
                  ),
                ),
              );
            },
            tooltip: 'View Pending Operations',
          )
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16.0),
        childAspectRatio: 3 / 2,
        mainAxisSpacing: 16.0,
        crossAxisSpacing: 16.0,
        children: [
          _buildFeatureCard(
            context,
            title: 'Goods Receiving',
            icon: Icons.inventory_2,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) {
                return const GoodsReceivingScreen();
              }));
            },
          ),
          _buildFeatureCard(
            context,
            title: 'Inventory Transfer',
            icon: Icons.swap_horiz,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) {
                return const InventoryTransferScreen();
              }));
            },
          ),
        ],
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

  Widget _buildFeatureCard(BuildContext context, {required String title, required IconData icon, required VoidCallback onTap}) {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48.0, color: Theme.of(context).primaryColor),
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

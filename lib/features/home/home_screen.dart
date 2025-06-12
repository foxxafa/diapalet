import 'package:flutter/material.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/inventory_transfer_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:diapalet/core/sync/sync_service.dart';

class HomeScreen extends StatelessWidget {
  final SyncService syncService;

  const HomeScreen({
    super.key,
    required this.syncService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DiaPalet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              try {
                await syncService.syncData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Senkronizasyon tamamlandı')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Senkronizasyon hatası: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GoodsReceivingScreen(
                      syncService: syncService,
                    ),
                  ),
                );
              },
              child: const Text('MAL KABUL'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransferScreen(
                      syncService: syncService,
                    ),
                  ),
                );
              },
              child: const Text('TRANSFER'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PendingOperationsScreen(
                      syncService: syncService,
                    ),
                  ),
                );
              },
              child: const Text('BEKLEYEN İŞLEMLER'),
            ),
          ],
        ),
      ),
    );
  }
} 
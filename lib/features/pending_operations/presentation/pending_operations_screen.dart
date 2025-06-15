// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class PendingOperationsScreen extends StatefulWidget {
  const PendingOperationsScreen({super.key});

  @override
  State<PendingOperationsScreen> createState() => _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends State<PendingOperationsScreen> with SingleTickerProviderStateMixin {
  late final SyncService _syncService;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _syncService = context.read<SyncService>();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleSync() async {
    await _syncService.performFullSync();
    // Senkronizasyon sonrası arayüzü yenilemek için setState çağırıyoruz,
    // bu FutureBuilder'ları yeniden tetikleyecektir.
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'pending_operations.title'.tr(),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'pending_operations.tabs.pending'.tr()),
            Tab(text: 'pending_operations.tabs.history'.tr()),
          ],
        ),
      ),
      body: Column(
        children: [
          StreamBuilder<SyncStatus>(
            stream: _syncService.syncStatusStream,
            builder: (context, statusSnapshot) {
              final status = statusSnapshot.data ?? SyncStatus.offline;
              return _buildSyncStatusBanner(status);
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PendingList(key: UniqueKey()), // Key ekleyerek yeniden çizimi garantile
                _HistoryList(key: UniqueKey()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<SyncStatus>(
          stream: _syncService.syncStatusStream,
          builder: (context, statusSnapshot) {
            final isSyncing = statusSnapshot.data == SyncStatus.syncing;
            return FloatingActionButton.extended(
              onPressed: isSyncing ? null : _handleSync,
              icon: isSyncing
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
              label: Text(isSyncing
                  ? 'pending_operations.status.syncing'.tr()
                  : 'pending_operations.sync_now'.tr()),
            );
          }),
    );
  }

  Widget _buildSyncStatusBanner(SyncStatus status) {
    IconData icon;
    Color color;
    String message;

    switch (status) {
      case SyncStatus.offline:
        icon = Icons.wifi_off; color = Colors.grey; message = 'pending_operations.status.offline'.tr();
        break;
      case SyncStatus.online:
        icon = Icons.wifi; color = Colors.blue; message = 'pending_operations.status.online'.tr();
        break;
      case SyncStatus.syncing:
        icon = Icons.sync; color = Colors.blue; message = 'pending_operations.status.syncing'.tr();
        break;
      case SyncStatus.upToDate:
        icon = Icons.check_circle; color = Colors.green; message = 'pending_operations.status.up_to_date'.tr();
        break;
      case SyncStatus.error:
        icon = Icons.error; color = Colors.red; message = 'pending_operations.status.error'.tr();
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(75)),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          if (status == SyncStatus.syncing)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

// --- AYRI WIDGET'LAR ---

class _PendingList extends StatelessWidget {
  const _PendingList({super.key});

  @override
  Widget build(BuildContext context) {
    final syncService = context.watch<SyncService>();
    return FutureBuilder<List<PendingOperation>>(
      future: syncService.getPendingOperations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        final operations = snapshot.data ?? [];
        if (operations.isEmpty) {
          return Center(child: Text('pending_operations.no_pending'.tr()));
        }
        return ListView.builder(
          itemCount: operations.length,
          itemBuilder: (context, index) {
            final op = operations[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Icon(
                  op.type == PendingOperationType.goodsReceipt ? Icons.call_received : Icons.swap_horiz,
                ),
                title: Text(op.displayTitle),
                subtitle: Text(op.displaySubtitle),
                trailing: op.status == 'failed'
                    ? Tooltip(message: op.errorMessage ?? 'Bilinmeyen hata', child: const Icon(Icons.error, color: Colors.red))
                    : (op.status == 'pending' ? const Icon(Icons.hourglass_top_outlined, color: Colors.orange) : null),
              ),
            );
          },
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    final syncService = context.watch<SyncService>();
    return FutureBuilder<List<SyncLog>>(
      future: syncService.getSyncHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return Center(child: Text('pending_operations.no_history'.tr()));
        }
        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: _buildHistoryIcon(log.type, log.status),
                title: Text(log.message),
                subtitle: Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(log.timestamp)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryIcon(String type, String status) {
    if (status == 'error') return const Icon(Icons.error_outline, color: Colors.red);

    switch(type) {
      case 'download': return const Icon(Icons.cloud_download_outlined, color: Colors.blue);
      case 'upload': return const Icon(Icons.cloud_upload_outlined, color: Colors.green);
      case 'sync_status':
        return status == 'success'
            ? const Icon(Icons.check_circle_outline, color: Colors.green)
            : const Icon(Icons.info_outline, color: Colors.orange);
      default: return const Icon(Icons.info_outline, color: Colors.grey);
    }
  }
}

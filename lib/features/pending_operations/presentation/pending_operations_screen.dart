// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
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
    _syncService.checkServerStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleSync() async {
    await _syncService.performFullSync();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
              return _buildSyncStatusBanner(status, textTheme);
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _PendingList(),
                _HistoryList(),
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
              label: Text(isSyncing
                  ? 'pending_operations.status.syncing'.tr()
                  : 'pending_operations.sync_now'.tr()),
              icon: isSyncing
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
            );
          }),
    );
  }

  Widget _buildSyncStatusBanner(SyncStatus status, TextTheme textTheme) {
    IconData icon;
    Color color;
    String message;
    final theme = Theme.of(context);

    switch (status) {
      case SyncStatus.offline:
        icon = Icons.wifi_off_rounded; color = Colors.grey.shade600; message = 'pending_operations.status.offline'.tr();
        break;
      case SyncStatus.online:
        icon = Icons.wifi_rounded; color = theme.colorScheme.secondary; message = 'pending_operations.status.online'.tr();
        break;
      case SyncStatus.syncing:
        icon = Icons.sync_rounded; color = theme.colorScheme.secondary; message = 'pending_operations.status.syncing'.tr();
        break;
      case SyncStatus.upToDate:
        icon = Icons.check_circle_rounded; color = Theme.of(context).colorScheme.primary; message = 'pending_operations.status.up_to_date'.tr();
        break;
      case SyncStatus.error:
        icon = Icons.error_rounded; color = theme.colorScheme.error; message = 'pending_operations.status.error'.tr();
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (status == SyncStatus.syncing)
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: color))
          else
            Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: color))),
        ],
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList();
  @override
  Widget build(BuildContext context) {
    return Consumer<SyncService>(
      builder: (context, syncService, child) {
        return FutureBuilder<List<PendingOperation>>(
          future: syncService.getPendingOperations(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('Hata: ${snapshot.error}'));
            final operations = snapshot.data ?? [];
            if (operations.isEmpty) return Center(child: Text('pending_operations.no_pending'.tr(), style: Theme.of(context).textTheme.bodyMedium));
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80), // FAB için boşluk
              itemCount: operations.length,
              itemBuilder: (context, index) {
                final op = operations[index];
                return _PendingOperationCard(operation: op);
              },
            );
          },
        );
      },
    );
  }
}

class _PendingOperationCard extends StatelessWidget {
  final PendingOperation operation;
  const _PendingOperationCard({required this.operation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = operation.status == 'failed';

    IconData iconData;
    switch(operation.type) {
      case PendingOperationType.goodsReceipt:
        iconData = Icons.call_received_rounded;
        break;
      case PendingOperationType.inventoryTransfer:
        iconData = Icons.swap_horiz_rounded;
        break;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
          foregroundColor: theme.colorScheme.primary,
          child: Icon(iconData),
        ),
        title: Text(operation.displayTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(operation.displaySubtitle, style: theme.textTheme.bodySmall),
        trailing: isFailed
            ? IconButton(
          icon: Icon(Icons.info_outline_rounded, color: theme.colorScheme.error),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('pending_operations.error_details'.tr()),
                content: Text(operation.errorMessage ?? 'Bilinmeyen bir hata oluştu.'),
                actions: [TextButton(child: Text('dialog.ok'.tr()), onPressed: () => Navigator.of(ctx).pop())],
              ),
            );
          },
        )
            : Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade700),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList();
  @override
  Widget build(BuildContext context) {
    return Consumer<SyncService>(
      builder: (context, syncService, child) {
        return FutureBuilder<List<SyncLog>>(
          future: syncService.getSyncHistory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('Hata: ${snapshot.error}'));
            final logs = snapshot.data ?? [];
            if (logs.isEmpty) return Center(child: Text('pending_operations.no_history'.tr(), style: Theme.of(context).textTheme.bodyMedium));
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return _HistoryLogCard(log: log);
              },
            );
          },
        );
      },
    );
  }
}

class _HistoryLogCard extends StatelessWidget {
  final SyncLog log;
  const _HistoryLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isError = log.status.contains('error');

    IconData icon;
    Color color;

    if (isError) {
      icon = Icons.cloud_off_rounded;
      color = theme.colorScheme.error;
    } else {
      switch (log.type) {
        case 'download': icon = Icons.cloud_download_rounded; color = theme.colorScheme.primary; break;
        case 'upload': icon = Icons.cloud_upload_rounded; color = theme.colorScheme.secondary; break;
        default: icon = Icons.check_circle_rounded; color = AppTheme.accentColor; break;
      }
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          child: Icon(icon, size: 22),
        ),
        title: Text(log.message, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        subtitle: Text(
          DateFormat('dd.MM.yyyy HH:mm:ss').format(log.timestamp),
          style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

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
  State<PendingOperationsScreen> createState() =>
      _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends State<PendingOperationsScreen>
    with SingleTickerProviderStateMixin {
  late final SyncService _syncService;
  late final TabController _tabController;

  List<PendingOperation> _pendingOperations = [];
  List<SyncLog> _syncLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _syncService = context.read<SyncService>();
    _tabController = TabController(length: 2, vsync: this);
    _syncService.addListener(_onSyncServiceUpdate);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncService.removeListener(_onSyncServiceUpdate);
    super.dispose();
  }

  void _onSyncServiceUpdate() {
    // SyncService'te bir değişiklik olduğunda verileri yeniden yükle.
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final newPending = await _syncService.getPendingOperations();
      final newHistory = await _syncService.getSyncHistory();
      if (mounted) {
        setState(() {
          _pendingOperations = newPending;
          _syncLogs = newHistory;
        });
      }
    } catch (e) {
      debugPrint("Veri yüklenirken hata oluştu: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    // Hem force sync yap hem de verileri yeniden yükle.
    await _syncService.performFullSync(force: true);
    await _loadData();
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
                _PendingList(
                  operations: _pendingOperations,
                  isLoading: _isLoading,
                  onRefresh: _handleRefresh,
                ),
                _HistoryList(
                  logs: _syncLogs,
                  isLoading: _isLoading,
                  onRefresh: _handleRefresh,
                ),
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
            onPressed: isSyncing ? null : _handleRefresh,
            label: Text(isSyncing
                ? 'pending_operations.status.syncing'.tr()
                : 'pending_operations.sync_now'.tr()),
            icon: isSyncing
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
          );
        },
      ),
    );
  }

  Widget _buildSyncStatusBanner(SyncStatus status) {
    IconData icon;
    Color color;
    String message;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    switch (status) {
      case SyncStatus.offline:
        icon = Icons.wifi_off_rounded;
        color = Colors.grey.shade600;
        message = 'pending_operations.status.offline'.tr();
        break;
      case SyncStatus.online:
        icon = Icons.wifi_rounded;
        color = theme.colorScheme.secondary;
        message = 'pending_operations.status.online'.tr();
        break;
      case SyncStatus.syncing:
        icon = Icons.sync_rounded;
        color = theme.colorScheme.secondary;
        message = 'pending_operations.status.syncing'.tr();
        break;
      case SyncStatus.upToDate:
        icon = Icons.check_circle_rounded;
        color = theme.colorScheme.primary;
        message = 'pending_operations.status.up_to_date'.tr();
        break;
      case SyncStatus.error:
        icon = Icons.error_rounded;
        color = theme.colorScheme.error;
        message = 'pending_operations.status.error'.tr();
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
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: color))
          else
            Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: color))),
        ],
      ),
    );
  }
}

// GÜNCELLEME: Liste boşken gösterilecek widget
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: theme.hintColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// GÜNCELLEME: Bekleyen işlemler listesi
class _PendingList extends StatelessWidget {
  final List<PendingOperation> operations;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const _PendingList({
    required this.operations,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && operations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (operations.isEmpty) {
      return _EmptyState(
        icon: Icons.cloud_done_outlined,
        message: 'pending_operations.no_pending'.tr(),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
        itemCount: operations.length,
        itemBuilder: (context, index) {
          return _PendingOperationCard(operation: operations[index]);
        },
      ),
    );
  }
}

// GÜNCELLEME: Bekleyen işlem kartı
class _PendingOperationCard extends StatelessWidget {
  final PendingOperation operation;
  const _PendingOperationCard({required this.operation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData iconData;
    switch (operation.type) {
      case PendingOperationType.goodsReceipt:
        iconData = Icons.move_to_inbox_outlined;
        break;
      case PendingOperationType.inventoryTransfer:
        iconData = Icons.swap_horiz_rounded;
        break;
    }
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListTile(
        leading: Icon(iconData, color: theme.colorScheme.primary),
        title: Text(operation.displayTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(operation.displaySubtitle, style: theme.textTheme.bodySmall),
        trailing: Icon(Icons.hourglass_top_rounded, color: Colors.grey.shade500),
      ),
    );
  }
}


// GÜNCELLEME: Geçmiş loglar listesi
class _HistoryList extends StatelessWidget {
  final List<SyncLog> logs;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const _HistoryList({
    required this.logs,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (logs.isEmpty) {
      return _EmptyState(
        icon: Icons.history_toggle_off_outlined,
        message: 'pending_operations.no_history'.tr(),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return _HistoryLogCard(log: logs[index]);
        },
      ),
    );
  }
}


// GÜNCELLEME: Geçmiş log kartı
class _HistoryLogCard extends StatelessWidget {
  final SyncLog log;
  const _HistoryLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = log.status.toLowerCase() == 'success';
    final iconData = isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded;
    final iconColor = isSuccess ? theme.colorScheme.primary : theme.colorScheme.error;

    final formattedDate = DateFormat('dd.MM.yyyy HH:mm:ss').format(log.timestamp);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300, width: 0.5)
      ),
      child: ListTile(
        leading: Icon(iconData, color: iconColor),
        title: Text(log.message, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${log.type.toUpperCase()} - $formattedDate',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
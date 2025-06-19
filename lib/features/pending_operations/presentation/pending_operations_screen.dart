// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PendingOperationsScreen extends StatefulWidget {
  const PendingOperationsScreen({super.key});

  @override
  State<PendingOperationsScreen> createState() => _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends State<PendingOperationsScreen> with SingleTickerProviderStateMixin {
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
    _loadData(); // Initial data load
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncService.removeListener(_onSyncServiceUpdate);
    super.dispose();
  }

  void _onSyncServiceUpdate() {
    // SyncService'te notifyListeners çağrıldığında tetiklenir.
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
            initialData: SyncStatus.online, // Initial status
            builder: (context, statusSnapshot) {
              final status = statusSnapshot.data ?? SyncStatus.offline;
              return _buildSyncStatusBanner(status, textTheme);
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PendingList(operations: _pendingOperations, isLoading: _isLoading),
                _HistoryList(logs: _syncLogs, isLoading: _isLoading),
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
      case SyncStatus.online: // HATA DÜZELTMESİ: Bu case artık geçerli.
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

// _PendingList, _HistoryList and other helper widgets remain the same...
// (Code from previous turns can be used here)

class _PendingList extends StatelessWidget {
  final List<PendingOperation> operations;
  final bool isLoading;
  const _PendingList({required this.operations, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading && operations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (operations.isEmpty) {
      return Center(child: Text('pending_operations.no_pending'.tr(), style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: operations.length,
      itemBuilder: (context, index) {
        final op = operations[index];
        return _PendingOperationCard(operation: op);
      },
    );
  }
}

class _PendingOperationCard extends StatelessWidget {
  final PendingOperation operation;
  const _PendingOperationCard({required this.operation});

  @override
  Widget build(BuildContext context) {
    // Implementation from previous turn
    return Card(child: ListTile(title: Text(operation.displayTitle)));
  }
}

class _HistoryList extends StatelessWidget {
  final List<SyncLog> logs;
  final bool isLoading;
  const _HistoryList({required this.logs, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading && logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (logs.isEmpty) {
      return Center(child: Text('pending_operations.no_history'.tr(), style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _HistoryLogCard(log: log);
      },
    );
  }
}

class _HistoryLogCard extends StatelessWidget {
  final SyncLog log;
  const _HistoryLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    // Implementation from previous turn
    return Card(child: ListTile(title: Text(log.message)));
  }
}


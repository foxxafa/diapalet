// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  List<PendingOperation> _syncedOperations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _syncService = context.read<SyncService>();
    _tabController = TabController(length: 2, vsync: this);
    // Add listener, but the initial state will be handled by StreamBuilder's initialData
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
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final newPending = await _syncService.getPendingOperations();
      final newHistory = await _syncService.getSyncedOperationHistory();
      if (mounted) {
        setState(() {
          _pendingOperations = newPending;
          _syncedOperations = newHistory;
        });
      }
    } catch (e) {
      debugPrint("common_labels.data_load_error".tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    await _syncService.performFullSync(force: true);
    // _loadData will be called automatically by the listener, but we can call it here for faster UI feedback
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
            // DÜZELTME: Stream'e başlangıç değeri olarak servisteki anlık durum veriliyor.
            initialData: _syncService.currentStatus,
            stream: _syncService.syncStatusStream,
            builder: (context, statusSnapshot) {
              final status = statusSnapshot.data ?? _syncService.currentStatus;
              return _buildSyncStatusBanner(status);
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _OperationList(
                  operations: _pendingOperations,
                  isLoading: _isLoading,
                  onRefresh: _handleRefresh,
                  isHistory: false,
                  emptyIcon: Icons.cloud_done_outlined,
                  emptyMessage: 'pending_operations.no_pending'.tr(),
                ),
                _OperationList(
                  operations: _syncedOperations,
                  isLoading: _isLoading,
                  onRefresh: _handleRefresh,
                  isHistory: true,
                  emptyIcon: Icons.history_rounded,
                  emptyMessage: 'pending_operations.no_history'.tr(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<SyncStatus>(
        // DÜZELTME: Bu StreamBuilder'a da başlangıç değeri ekleniyor.
        initialData: _syncService.currentStatus,
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
    final theme = Theme.of(context);

    // Banner için renkleri ve ikonu belirleyen yardımcı yapı.
    final ({IconData icon, Color background, Color content, String message}) bannerStyle;

    switch (status) {
      case SyncStatus.offline:
        bannerStyle = (
          icon: Icons.wifi_off_rounded,
          background: AppTheme.warningColor.withAlpha(230),
          content: Colors.white,
          message: 'pending_operations.status.offline'.tr()
        );
        break;
      case SyncStatus.online:
        bannerStyle = (
          icon: Icons.wifi_rounded,
          background: theme.colorScheme.secondary,
          content: theme.colorScheme.onSecondary,
          message: 'pending_operations.status.online'.tr()
        );
        break;
      case SyncStatus.syncing:
        bannerStyle = (
          icon: Icons.sync_rounded,
          background: theme.colorScheme.secondary,
          content: theme.colorScheme.onSecondary,
          message: 'pending_operations.status.syncing'.tr()
        );
        break;
      case SyncStatus.upToDate:
        bannerStyle = (
          icon: Icons.check_circle_rounded,
          background: theme.colorScheme.primary,
          content: theme.colorScheme.onPrimary,
          message: 'pending_operations.status.up_to_date'.tr()
        );
        break;
      case SyncStatus.error:
        bannerStyle = (
          icon: Icons.error_rounded,
          background: theme.colorScheme.error,
          content: theme.colorScheme.onError,
          message: 'pending_operations.status.error'.tr()
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bannerStyle.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (status == SyncStatus.syncing)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: bannerStyle.content),
            )
          else
            Icon(bannerStyle.icon, color: bannerStyle.content),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              bannerStyle.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: bannerStyle.content),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationList extends StatelessWidget {
  final List<PendingOperation> operations;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final bool isHistory;
  final IconData emptyIcon;
  final String emptyMessage;

  const _OperationList({
    required this.operations,
    required this.isLoading,
    required this.onRefresh,
    required this.isHistory,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && operations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (operations.isEmpty) {
      return _EmptyState(icon: emptyIcon, message: emptyMessage);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
        itemCount: operations.length,
        itemBuilder: (context, index) {
          return _OperationCard(
            operation: operations[index],
            isSynced: isHistory,
          );
        },
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  final PendingOperation operation;
  final bool isSynced;

  const _OperationCard({required this.operation, this.isSynced = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData leadingIcon;
    switch (operation.type) {
      case PendingOperationType.goodsReceipt:
        leadingIcon = Icons.move_to_inbox_outlined;
        break;
      case PendingOperationType.inventoryTransfer:
        leadingIcon = Icons.swap_horiz_rounded;
        break;
    }

    final Widget trailingWidget = isSynced
        ? Icon(Icons.check_circle_outline_rounded,
            color: theme.colorScheme.primary)
        : Icon(Icons.hourglass_top_rounded, color: AppTheme.warningColor);

    return Card(
      child: ListTile(
        leading: Icon(leadingIcon, color: theme.colorScheme.secondary),
        title: Text(operation.displayTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(operation.displaySubtitle,
            style: theme.textTheme.bodySmall),
        trailing: trailingWidget,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
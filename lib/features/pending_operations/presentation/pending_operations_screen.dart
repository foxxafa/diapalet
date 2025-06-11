import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/sync/sync_service.dart';
import 'package:diapalet/core/sync/pending_operation.dart';

class PendingOperationsScreen extends StatefulWidget {
  const PendingOperationsScreen({super.key});

  @override
  State<PendingOperationsScreen> createState() => _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends State<PendingOperationsScreen> {
  final SyncService _syncService = SyncService();
  List<PendingOperation> _pendingOperations = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  SyncStatus _syncStatus = SyncStatus.offline;
  StreamSubscription? _syncStatusSubscription;

  @override
  void initState() {
    super.initState();
    // Initialization is now handled in main.dart, so we just listen for updates.
    // _syncService.initialize();
    _loadPendingOperations();
    _syncStatusSubscription = _syncService.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _syncStatus = status;
          _isSyncing = status == SyncStatus.syncing;
        });
        
        // Reload operations after sync completes
        if (status == SyncStatus.upToDate) {
          _loadPendingOperations();
        }
      }
    });
  }

  Future<void> _loadPendingOperations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final operations = await _syncService.getPendingOperationsForUI();
      setState(() {
        _pendingOperations = operations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading operations: $e')),
        );
      }
    }
  }

  Future<void> _performSync() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final result = await _syncService.syncPendingOperations();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
      
      if (result.success) {
        await _loadPendingOperations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() {
      _isSyncing = false;
    });
  }

  Future<void> _downloadMasterData() async {
    try {
      final result = await _syncService.downloadMasterData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSyncStatusBanner() {
    IconData icon;
    Color color;
    String message;

    switch (_syncStatus) {
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        color = Colors.grey;
        message = 'pending_operations.status.offline'.tr();
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        color = Colors.blue;
        message = 'pending_operations.status.syncing'.tr();
        break;
      case SyncStatus.upToDate:
        icon = Icons.check_circle;
        color = Colors.green;
        message = 'pending_operations.status.up_to_date'.tr();
        break;
      case SyncStatus.error:
        icon = Icons.error;
        color = Colors.red;
        message = 'pending_operations.status.error'.tr();
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * 0.1).round()),
        border: Border.all(color: color.withAlpha((255 * 0.3).round())),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          if (_syncStatus == SyncStatus.syncing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (_pendingOperations.isNotEmpty)
                  Text(
                    'pending_operations.operations_count'.tr(args: [_pendingOperations.length.toString()]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationCard(PendingOperation operation) {
    IconData icon;
    Color iconColor;

    switch (operation.operationType) {
      case 'goods_receipt':
        icon = Icons.input_outlined;
        iconColor = Colors.blue;
        break;
      case 'pallet_transfer':
        icon = Icons.warehouse_outlined;
        iconColor = Colors.orange;
        break;
      case 'box_transfer':
        icon = Icons.move_to_inbox;
        iconColor = Colors.purple;
        break;
      default:
        icon = Icons.help_outline;
        iconColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: iconColor.withAlpha((255 * 0.1).round()),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          operation.displayTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(operation.displaySubtitle),
        trailing: Icon(
          Icons.cloud_upload_outlined,
          color: Colors.grey[400],
        ),
        onTap: () => _showOperationDetails(operation),
      ),
    );
  }

  void _showOperationDetails(PendingOperation operation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('pending_operations.operation_details'.tr()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('pending_operations.type'.tr(), operation.operationType),
              _buildDetailRow('pending_operations.created'.tr(), 
                DateFormat('dd/MM/yyyy HH:mm').format(operation.createdAt)),
              const SizedBox(height: 16),
              Text(
                'pending_operations.data'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  operation.operationData.toString(),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.close'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('pending_operations.title'.tr()),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadMasterData,
            tooltip: 'pending_operations.download_master_data'.tr(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingOperations,
            tooltip: 'pending_operations.refresh'.tr(),
          ),
          // Add connectivity indicator like SharedAppBar
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Icon(
              _syncStatus == SyncStatus.offline ? Icons.wifi_off : Icons.wifi,
              color: _syncStatus == SyncStatus.offline ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPendingOperations,
        child: Column(
          children: [
            _buildSyncStatusBanner(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _pendingOperations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: Colors.green[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'pending_operations.no_pending'.tr(),
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'pending_operations.all_synced'.tr(),
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _pendingOperations.length,
                          itemBuilder: (context, index) {
                            return _buildOperationCard(_pendingOperations[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _pendingOperations.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isSyncing ? null : _performSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(_isSyncing 
                  ? 'pending_operations.syncing'.tr()
                  : 'pending_operations.sync_now'.tr()),
            )
          : null,
    );
  }
} 
// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'dart:convert';

import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_log.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
      // Verileri her zaman yeniden çek ve state'i güncelle.
      // Bu, senkronizasyon sonrası geçmişin güncellenmesini garantiler.
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
            initialData: SyncStatus.online,
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

  void _showDetailsDialog(BuildContext context, PendingOperation operation) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(operation.displayTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: FutureBuilder<Widget>(
              future: _buildSimplifiedDetails(context, operation),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ));
                }
                if (snapshot.hasError) {
                  return Text("Detaylar yüklenemedi: ${snapshot.error}");
                }
                if (!snapshot.hasData) {
                  return const Text("Detay bulunamadı.");
                }
                return snapshot.data!;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text('dialog.ok'.tr()),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
        contentPadding: const EdgeInsets.fromLTRB(0.0, 12.0, 0.0, 0.0),
        titlePadding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8.0),
      ),
    );
  }

  Future<Widget> _buildSimplifiedDetails(BuildContext context, PendingOperation operation) async {
    final db = await DatabaseHelper.instance.database;
    final data = jsonDecode(operation.data);
    final header = data['header'] as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>;
    final textTheme = Theme.of(context).textTheme;

    List<Widget> details = [];

    // Header Bilgileri
    if (operation.type == PendingOperationType.goodsReceipt) {
      details.add(ListTile(
        title: Text("İşlem Tipi", style: textTheme.bodySmall),
        subtitle: Text("Mal Kabul", style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
      ));
      final invoice = header['invoice_number'] as String?;
      if (invoice != null && invoice.isNotEmpty) {
        details.add(ListTile(
          title: Text("Fatura/İrsaliye No", style: textTheme.bodySmall),
          subtitle: Text(invoice, style: textTheme.bodyLarge),
        ));
      }
    } else if (operation.type == PendingOperationType.inventoryTransfer) {
      final fromLocId = header['source_location_id'];
      final toLocId = header['target_location_id'];

      final fromLocMap = await db.query('locations', where: 'id = ?', whereArgs: [fromLocId]);
      final toLocMap = await db.query('locations', where: 'id = ?', whereArgs: [toLocId]);
      final fromLocName = fromLocMap.isNotEmpty ? fromLocMap.first['name'] as String : 'Bilinmeyen ($fromLocId)';
      final toLocName = toLocMap.isNotEmpty ? toLocMap.first['name'] as String : 'Bilinmeyen ($toLocId)';

      details.add(ListTile(
        title: Text("İşlem Tipi", style: textTheme.bodySmall),
        subtitle: Text("Envanter Transferi", style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
      ));
      details.add(ListTile(
        leading: const Icon(Icons.arrow_upward_rounded, color: Colors.redAccent),
        title: Text("Kaynak Lokasyon", style: textTheme.bodySmall),
        subtitle: Text(fromLocName, style: textTheme.bodyLarge),
      ));
      details.add(ListTile(
        leading: const Icon(Icons.arrow_downward_rounded, color: Colors.green),
        title: Text("Hedef Lokasyon", style: textTheme.bodySmall),
        subtitle: Text(toLocName, style: textTheme.bodyLarge),
      ));
    }

    details.add(const Divider(height: 20));
    details.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text("Ürünler (${items.length})", style: textTheme.titleMedium),
    ));

    // Kalem Bilgileri
    for (var item in items) {
      final productId = item['urun_id'] ?? item['product_id'];
      final quantity = item['quantity'];
      final pallet = item['pallet_barcode'] ?? item['pallet_id'] as String?;

      final productMaps = await db.query('urunler', columns: ['UrunAdi'], where: 'UrunId = ?', whereArgs: [productId]);
      final productName = productMaps.isNotEmpty ? productMaps.first['UrunAdi'] as String : "Bilinmeyen Ürün ($productId)";

      details.add(ListTile(
        title: Text(productName, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        subtitle: Text("Miktar: $quantity${pallet != null && pallet.isNotEmpty ? '\nPalet: $pallet' : ''}"),
        isThreeLine: pallet != null && pallet.isNotEmpty,
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: details,
    );
  }

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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetailsDialog(context, operation),
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
      ),
    );
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
        default: icon = Icons.info_outline_rounded; color = Colors.grey.shade700; break;
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

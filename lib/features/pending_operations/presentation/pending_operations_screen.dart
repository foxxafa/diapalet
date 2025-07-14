// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'dart:convert';

import 'package:diapalet/core/services/pdf_service.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  void _showDetailsDialog(BuildContext context, PendingOperation operation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // Make the dialog wider for better content display
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text(operation.displayTitle),
        content: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: _OperationDetailsView(operation: operation),
        ),
        actions: [
          TextButton(
            onPressed: () => _generateOperationPdf(context, operation),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf, size: 18),
                const SizedBox(width: 4),
                Text('pdf_report.actions.generate'.tr()),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common_labels.close'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _generateOperationPdf(BuildContext context, PendingOperation operation) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text('pdf_report.actions.generating'.tr()),
            ],
          ),
        ),
      );

      // Create enriched data for better PDF content
      Map<String, dynamic>? enrichedData;
      try {
        final data = jsonDecode(operation.data) as Map<String, dynamic>;
        enrichedData = await _createEnrichedOperationData(data, operation.type);
      } catch (e) {
        enrichedData = {'raw_data': operation.data};
      }

      // Generate PDF
      final pdfData = await PdfService.generatePendingOperationPdf(
        operation: operation,
        enrichedData: enrichedData,
      );

      // Hide loading dialog
      if (context.mounted) Navigator.pop(context);

      // Generate filename
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(operation.createdAt);
      final operationType = operation.type.toString().split('.').last;
      final fileName = 'operation_${operationType}_$timestamp.pdf';

      // Show share dialog
      if (context.mounted) {
        await PdfService.showShareDialog(context, pdfData, fileName);
      }
    } catch (e) {
      // Hide loading dialog if still showing
      if (context.mounted) Navigator.pop(context);
      
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('pdf_report.actions.error_generating'.tr(namedArgs: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _createEnrichedOperationData(
    Map<String, dynamic> data, 
    PendingOperationType type,
  ) async {
    final db = DatabaseHelper.instance;
    final enrichedData = Map<String, dynamic>.from(data);

    try {
      switch (type) {
        case PendingOperationType.goodsReceipt:
          final header = data['header'] as Map<String, dynamic>?;
          final items = data['items'] as List?;
          
          if (header?['siparis_id'] != null) {
            final poId = await db.getPoIdBySiparisId(header!['siparis_id']);
            if (poId != null) {
              enrichedData['header']['po_id'] = poId;
            }
          }
          
          if (items != null) {
            for (int i = 0; i < items.length; i++) {
              final item = items[i] as Map<String, dynamic>;
              if (item['urun_id'] != null) {
                final product = await db.getProductById(item['urun_id']);
                if (product != null) {
                  enrichedData['items'][i]['product_name'] = product['UrunAdi'];
                  enrichedData['items'][i]['product_code'] = product['StokKodu'];
                }
              }
            }
          }
          break;
          
        case PendingOperationType.inventoryTransfer:
          final header = data['header'] as Map<String, dynamic>?;
          final items = data['items'] as List?;
          
          if (header?['source_location_id'] != null) {
            final sourceLoc = await db.getLocationById(header!['source_location_id']);
            if (sourceLoc != null) {
              enrichedData['header']['source_location_name'] = sourceLoc['name'];
            }
          }
          
          if (header?['target_location_id'] != null) {
            final targetLoc = await db.getLocationById(header!['target_location_id']);
            if (targetLoc != null) {
              enrichedData['header']['target_location_name'] = targetLoc['name'];
            }
          }
          
          if (items != null) {
            for (int i = 0; i < items.length; i++) {
              final item = items[i] as Map<String, dynamic>;
              final productId = item['product_id'] ?? item['urun_id'];
              if (productId != null) {
                final product = await db.getProductById(productId);
                if (product != null) {
                  enrichedData['items'][i]['product_name'] = product['UrunAdi'];
                  enrichedData['items'][i]['product_code'] = product['StokKodu'];
                }
              }
            }
          }
          break;
          
        case PendingOperationType.forceCloseOrder:
          if (data['siparis_id'] != null) {
            final poId = await db.getPoIdBySiparisId(data['siparis_id']);
            if (poId != null) {
              enrichedData['po_id'] = poId;
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('Error enriching operation data: $e');
    }

    return enrichedData;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = operation.errorMessage != null && operation.errorMessage!.isNotEmpty;

    IconData leadingIcon;
    switch (operation.type) {
      case PendingOperationType.goodsReceipt:
        leadingIcon = Icons.move_to_inbox_outlined;
        break;
      case PendingOperationType.inventoryTransfer:
        leadingIcon = Icons.swap_horiz_rounded;
        break;
      case PendingOperationType.forceCloseOrder:
        leadingIcon = Icons.task_alt_rounded;
        break;
    }

    final Widget trailingWidget;
    if (hasError) {
      trailingWidget = Icon(Icons.error_outline_rounded, color: theme.colorScheme.error);
    } else if (isSynced) {
      trailingWidget = Icon(Icons.check_circle_outline_rounded, color: theme.colorScheme.primary);
    } else {
      trailingWidget = const Icon(Icons.hourglass_top_rounded, color: AppTheme.warningColor);
    }

    return Card(
      elevation: hasError ? 2 : 1,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: hasError ? theme.colorScheme.error.withAlpha(128) : Colors.transparent,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(leadingIcon, color: theme.colorScheme.secondary),
        title: Text(
          operation.displayTitle,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          operation.displaySubtitle,
          style: theme.textTheme.bodySmall,
        ),
        trailing: trailingWidget,
        onTap: () => _showDetailsDialog(context, operation),
      ),
    );
  }
}

class _OperationDetailsView extends StatelessWidget {
  final PendingOperation operation;

  const _OperationDetailsView({required this.operation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError =
        operation.errorMessage != null && operation.errorMessage!.isNotEmpty;

    return SingleChildScrollView(
      child: ListBody(
        children: <Widget>[
          if (hasError) ...[
            _buildErrorSection(theme),
            const Divider(height: 32),
          ],
          FutureBuilder<Widget>(
            future: _buildFormattedDetailsAsync(context, operation),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return _buildFormattedDetails(context, operation);
              } else {
                return snapshot.data ?? _buildFormattedDetails(context, operation);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'pending_operations.error_details'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          operation.errorMessage!,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Future<Widget> _buildFormattedDetailsAsync(BuildContext context, PendingOperation operation) async {
    try {
      final data = jsonDecode(operation.data) as Map<String, dynamic>;
      switch (operation.type) {
        case PendingOperationType.goodsReceipt:
          return await _buildGoodsReceiptDetailsAsync(context, data);
        case PendingOperationType.inventoryTransfer:
          return await _buildInventoryTransferDetailsAsync(context, data);
        case PendingOperationType.forceCloseOrder:
          return await _buildForceCloseOrderDetailsAsync(context, data);
      }
    } catch (e) {
      return _buildFormattedDetails(context, operation);
    }
  }

  Future<Widget> _buildGoodsReceiptDetailsAsync(BuildContext context, Map<String, dynamic> data) async {
    final db = DatabaseHelper.instance;
    final header = (data['header'] as Map?)?.cast<String, dynamic>();
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>();
    
    // Sipariş ID'sinden gerçek PO ID'yi al
    String poId = 'N/A';
    final siparisId = header?['siparis_id'];
    if (siparisId != null) {
      final realPoId = await db.getPoIdBySiparisId(siparisId);
      if (realPoId != null) {
        poId = realPoId;
      }
    }
    
    final invoice = header?['invoice_number'] ?? 'N/A';

    // Ürün bilgilerini zenginleştir
    final enrichedItems = <Map<String, dynamic>>[];
    if (items != null) {
      for (final item in items) {
        final enrichedItem = Map<String, dynamic>.from(item);
        final productId = item['urun_id'];
        if (productId != null) {
          final product = await db.getProductById(productId);
          if (product != null) {
            enrichedItem['product_name'] = product['UrunAdi'];
            enrichedItem['product_code'] = product['StokKodu'];
          }
        }
        enrichedItems.add(enrichedItem);
      }
    }

    if (!context.mounted) return const SizedBox.shrink();

    return _buildDetailSection(
      context: context,
      title: 'pending_operations.titles.goods_receipt'.tr(),
      details: {
        'dialog_labels.purchase_order'.tr(): poId,
        if (invoice != 'N/A' && invoice != poId) 'dialog_labels.invoice'.tr(): invoice.toString(),
      },
      items: enrichedItems,
      itemBuilder: (item) {
        final productName = item['product_name'] ?? 'dialog_labels.unknown_product'.tr();
        final productCode = item['product_code'] ?? '';
        final productInfo = productCode.isNotEmpty ? ' ($productCode)' : '';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text('$productName$productInfo'),
          trailing: Text(
            '${item['quantity']} ${item['unit'] ?? ''}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        );
      },
    );
  }

  Future<Widget> _buildInventoryTransferDetailsAsync(BuildContext context, Map<String, dynamic> data) async {
    final db = DatabaseHelper.instance;
    final header = (data['header'] as Map?)?.cast<String, dynamic>();
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>();
    
    // Lokasyon isimlerini al
    String source = 'N/A';
    String target = 'N/A';
    
    final sourceId = header?['source_location_id'];
    final targetId = header?['target_location_id'];
    
    if (sourceId != null) {
      final sourceLoc = await db.getLocationById(sourceId);
      if (sourceLoc != null) {
        source = sourceLoc['name'] ?? sourceLoc['code'] ?? sourceId.toString();
      }
    }
    
    if (targetId != null) {
      final targetLoc = await db.getLocationById(targetId);
      if (targetLoc != null) {
        target = targetLoc['name'] ?? targetLoc['code'] ?? targetId.toString();
      }
    }
    
    final containerId = header?['container_id']?.toString();

    // Ürün bilgilerini zenginleştir
    final enrichedItems = <Map<String, dynamic>>[];
    if (items != null) {
      for (final item in items) {
        final enrichedItem = Map<String, dynamic>.from(item);
        final productId = item['product_id'] ?? item['urun_id'];
        if (productId != null) {
          final product = await db.getProductById(productId);
          if (product != null) {
            enrichedItem['product_name'] = product['UrunAdi'];
            enrichedItem['product_code'] = product['StokKodu'];
          }
        }
        enrichedItems.add(enrichedItem);
      }
    }

    if (!context.mounted) return const SizedBox.shrink();

    return _buildDetailSection(
      context: context,
      title: 'pending_operations.titles.inventory_transfer'.tr(),
      details: {
        'dialog_labels.from'.tr(): source,
        'dialog_labels.to'.tr(): target,
        if (containerId != null) 'dialog_labels.container'.tr(): containerId,
      },
      items: enrichedItems,
      itemBuilder: (item) {
        final productName = item['product_name'] ?? 'dialog_labels.unknown_product'.tr();
        final productCode = item['product_code'] ?? '';
        final productInfo = productCode.isNotEmpty ? ' ($productCode)' : '';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text('$productName$productInfo'),
          trailing: Text(
            'x ${item['quantity_transferred'] ?? item['quantity']}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        );
      },
    );
  }

  Future<Widget> _buildForceCloseOrderDetailsAsync(BuildContext context, Map<String, dynamic> data) async {
    final db = DatabaseHelper.instance;
    
    // Sipariş ID'sinden gerçek PO ID'yi al
    String poId = 'N/A';
    final siparisId = data['siparis_id'];
    if (siparisId != null) {
      final realPoId = await db.getPoIdBySiparisId(siparisId);
      if (realPoId != null) {
        poId = realPoId;
      }
    }
    
    if (!context.mounted) return const SizedBox.shrink();

    return _buildDetailSection(
      context: context,
      title: 'pending_operations.titles.force_close_order'.tr(),
      details: {'dialog_labels.purchase_order'.tr(): poId},
    );
  }

  Widget _buildFormattedDetails(BuildContext context, PendingOperation operation) {
    try {
      final data = jsonDecode(operation.data) as Map<String, dynamic>;
      switch (operation.type) {
        case PendingOperationType.goodsReceipt:
          return _buildGoodsReceiptDetails(context, data);
        case PendingOperationType.inventoryTransfer:
          return _buildInventoryTransferDetails(context, data);
        case PendingOperationType.forceCloseOrder:
          return _buildForceCloseOrderDetails(context, data);
      }
    } catch (e) {
      // Fallback for parsing errors or unknown types
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'pending_operations.subtitles.parsing_error'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 16),
          _buildRawJsonView(context, operation.data),
        ],
      );
    }
  }

  Widget _buildGoodsReceiptDetails(BuildContext context, Map<String, dynamic> data) {
    final header = (data['header'] as Map?)?.cast<String, dynamic>();
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>();
    final poId = header?['po_id'] ?? header?['siparis_id'] ?? 'N/A';
    final invoice = header?['invoice_number'] ?? 'N/A';

    return _buildDetailSection(
      context: context,
      title: 'pending_operations.titles.goods_receipt'.tr(),
      details: {
        'dialog_labels.purchase_order'.tr(): poId.toString(),
        if (invoice != 'N/A' && invoice != poId.toString()) 'dialog_labels.invoice'.tr(): invoice.toString(),
      },
      items: items,
      itemBuilder: (item) {
        final productName = item['product_name'] ?? 'dialog_labels.unknown_product'.tr();
        final productIdInfo = ' (ID: ${item['urun_id']})';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(item['product_name'] != null ? productName : '$productName$productIdInfo'),
          trailing: Text(
            '${item['quantity']} ${item['unit'] ?? ''}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        );
      },
    );
  }

  Widget _buildInventoryTransferDetails(BuildContext context, Map<String, dynamic> data) {
    final header = (data['header'] as Map?)?.cast<String, dynamic>();
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>();
    final source = header?['source_location_name'] ?? header?['source_location_id'] ?? 'N/A';
    final target = header?['target_location_name'] ?? header?['target_location_id'] ?? 'N/A';
    final containerId = header?['container_id']?.toString();

    return _buildDetailSection(
      context: context,
      title: 'pending_operations.titles.inventory_transfer'.tr(),
      details: {
        'dialog_labels.from'.tr(): source.toString(),
        'dialog_labels.to'.tr(): target.toString(),
        if (containerId != null) 'dialog_labels.container'.tr(): containerId,
      },
      items: items,
      itemBuilder: (item) {
        final productName = item['product_name'] ?? 'dialog_labels.unknown_product'.tr();
        final productIdInfo = ' (ID: ${item['product_id']})';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(item['product_name'] != null ? productName : '$productName$productIdInfo'),
          trailing: Text(
            'x ${item['quantity_transferred'] ?? item['quantity']}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        );
      },
    );
  }

  Widget _buildForceCloseOrderDetails(BuildContext context, Map<String, dynamic> data) {
    final poId = data['po_id'] ?? data['siparis_id'] ?? 'N/A';
    return _buildDetailSection(
      context: context,
      title: 'pending_operations.titles.force_close_order'.tr(),
      details: {'dialog_labels.purchase_order'.tr(): poId},
    );
  }

  Widget _buildDetailSection({
    required BuildContext context,
    required String title,
    required Map<String, String> details,
    List<Map<String, dynamic>>? items,
    Widget Function(Map<String, dynamic> item)? itemBuilder,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...details.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.key}: ', style: theme.textTheme.labelLarge),
                  Expanded(
                      child: Text(entry.value, style: theme.textTheme.bodyMedium)),
                ],
              ),
            )),
        if (items != null && items.isNotEmpty && itemBuilder != null) ...[
          const Divider(height: 24),
          Text(
            'dialog_labels.items_count'.tr(namedArgs: {'count': items.length.toString()}),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...items.map(itemBuilder),
        ]
      ],
    );
  }

  Widget _buildRawJsonView(BuildContext context, String rawJson) {
    final prettyJson =
        const JsonEncoder.withIndent('  ').convert(jsonDecode(rawJson));
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          prettyJson,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
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
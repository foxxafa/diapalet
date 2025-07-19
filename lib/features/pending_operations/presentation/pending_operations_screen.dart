// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:diapalet/core/services/pdf_service.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:dio/dio.dart';
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

  /// 🔧 Development Tools Dialog - sadece debug mode'da kullanılır
  void _showDevelopmentTools(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.build, color: Colors.orange),
            SizedBox(width: 8),
            Text('🔧 Development Tools'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠️ Bu araçlar sadece development/test amaçlıdır!\n\nTüm veri silinecek ve test verileri yüklenecek.',
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.red),
            ),
            SizedBox(height: 16),
            Text('🗂️ Sıfırlanacak:'),
            SizedBox(height: 8),
            Text('• Local SQLite Database'),
            Text('• Server MySQL Database (sadece dev)'),
            Text('• Pending Operations'),
            Text('• Sync History'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _performDevelopmentReset();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Database Reset'),
          ),
        ],
      ),
    );
  }

  /// Development database reset işlemi
  Future<void> _performDevelopmentReset() async {
    // Loading göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('🔄 Database reset ediliyor...'),
            SizedBox(height: 8),
            Text('Bu işlem biraz sürebilir.'),
          ],
        ),
      ),
    );

    try {
      // 1. Local database'i reset et (version artırarak)
      await _resetLocalDatabase();
      
      // 2. Server database'i reset et (sadece development'ta)
      await _resetServerDatabase();

      // 3. Sync service'i reset et
      await _syncService.performFullSync(force: true);

      // Loading'i kapat
      if (mounted) Navigator.of(context).pop();

      // Success mesajı
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Database başarıyla reset edildi ve test verileri yüklendi!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Data'yı yenile
      await _loadData();

    } catch (e) {
      // Loading'i kapat
      if (mounted) Navigator.of(context).pop();
      
      // Error mesajı
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Reset işlemi başarısız: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Local SQLite database'i reset eder
  Future<void> _resetLocalDatabase() async {
    final db = DatabaseHelper.instance;
    final database = await db.database;
    
    // Database version'ını artırarak force upgrade tetikle
    await database.close();
    
    // Database file'ı sil ki tamamen yeniden oluşturulsun
    final dbPath = database.path;
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
    
    // Yeni database'i tetikle
    await db.database;
  }

  /// Server database'i reset eder (sadece development)
  Future<void> _resetServerDatabase() async {
    final dio = Dio();

    // DÜZELTME: Statik erişim hatası düzeltildi
    const baseUrl = ApiConfig.baseUrl;

    final response = await dio.post(
      '$baseUrl/api/terminal/dev-reset',
      options: Options(
        headers: {'Content-Type': 'application/json'},
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode != 200) {
      final errorDetails = (response.data is Map<String, dynamic>)
          ? response.data['message'] ?? response.statusMessage
          : response.statusMessage;
      throw Exception('Server reset başarısız: $errorDetails');
    }

    final data = response.data;
    if (data is Map<String, dynamic> && data['status'] != 'success') {
      throw Exception('Server reset başarısız: ${data['message']}');
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔧 Development Tools Button (sadece debug mode'da görünür)
          if (!const bool.fromEnvironment('dart.vm.product')) ...[
            FloatingActionButton(
              heroTag: "dev_tools",
              mini: true,
              backgroundColor: Colors.orange,
              onPressed: () => _showDevelopmentTools(context),
              child: const Icon(Icons.build, color: Colors.white),
            ),
            const SizedBox(height: 8),
          ],
          // Ana sync butonu
          StreamBuilder<SyncStatus>(
            // DÜZELTME: Bu StreamBuilder'a da başlangıç değeri ekleniyor.
            initialData: _syncService.currentStatus,
            stream: _syncService.syncStatusStream,
            builder: (context, statusSnapshot) {
              final isSyncing = statusSnapshot.data == SyncStatus.syncing;
              return FloatingActionButton.extended(
                heroTag: "sync_main",
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
        ],
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

      // Generate PDF. Enrichment is now handled inside the PDF Service.
      final pdfData = await operation.generatePdf();

      // Hide loading dialog
      if (context.mounted) Navigator.pop(context);

      // Show share dialog
      if (context.mounted) {
        await PdfService.showShareDialog(context, pdfData, operation.pdfFileName);
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
          return await _buildGoodsReceiptDetailsAsync(context, data, operation);
        case PendingOperationType.inventoryTransfer:
          return await _buildInventoryTransferDetailsAsync(context, data);
        case PendingOperationType.forceCloseOrder:
          return await _buildForceCloseOrderDetailsAsync(context, data);
      }
    } catch (e) {
      return _buildFormattedDetails(context, operation);
    }
  }

  Future<Widget> _buildGoodsReceiptDetailsAsync(BuildContext context, Map<String, dynamic> data, PendingOperation operation) async {
    final db = DatabaseHelper.instance;

    // Data içindeki receipt_date'i kullan, created_at değil (server timing farkı için)
    DateTime operationDate = operation.createdAt;
    final originalHeader = data['header'] as Map<String, dynamic>?;
    if (originalHeader != null && originalHeader['receipt_date'] != null) {
      try {
        operationDate = DateTime.parse(originalHeader['receipt_date'].toString());
      } catch (e) {
        // Parse hatası durumunda created_at kullan
      }
    }

    // Enriched data al - operation tarihiyle birlikte historical accuracy için
    final enrichedData = await db.getEnrichedGoodsReceiptData(jsonEncode(data), operationDate: operationDate);
    final header = enrichedData['header'] as Map<String, dynamic>? ?? {};
    final items = enrichedData['items'] as List<dynamic>? ?? [];

    // Bilgileri extract et
    final poId = header['order_info']?['po_id']?.toString() ?? header['po_id']?.toString() ?? 'N/A';
    final invoice = header['invoice_number']?.toString() ?? 'N/A';
    final employeeName = header['employee_info'] != null
        ? '${header['employee_info']['first_name']} ${header['employee_info']['last_name']}'
        : 'System User';

    // Order tabanlı mı kontrol et
    final isOrderBased = header['siparis_id'] != null;

    // Force close kontrolü - sipariş eksiklerle kapatıldı mı?
    bool isForceClosed = false;
    if (isOrderBased && header['siparis_id'] != null) {
      try {
        // Bu mal kabul işleminden SONRA force close yapıldı mı kontrol et
        isForceClosed = await db.hasForceCloseOperationForOrder(
          header['siparis_id'] as int,
          operationDate
        );
      } catch (e) {
        debugPrint('Error checking force close: $e');
      }
    }

    if (!context.mounted) return const SizedBox.shrink();

    return _buildDetailSection(
      context: context,
      title: isOrderBased ? 'pending_operations.operation_types.order_based_receipt'.tr() : 'pending_operations.operation_types.free_receipt'.tr(),
      details: {
        'dialog_labels.operation_type'.tr(): isOrderBased ? 'pending_operations.operation_types.order_based_receipt'.tr() : 'pending_operations.operation_types.free_receipt'.tr(),
        'dialog_labels.employee'.tr(): employeeName,
        'dialog_labels.purchase_order'.tr(): poId,
        if (invoice != 'N/A' && invoice != poId) 'dialog_labels.invoice'.tr(): invoice,
        if (isForceClosed) 'Order Status': 'Closed with remainings',
      },
      items: items.cast<Map<String, dynamic>>(),
      itemBuilder: (item) {
        final productName = item['product_name'] ?? 'dialog_labels.unknown_product'.tr();
        final productCode = item['product_code'] ?? '';
        final productBarcode = item['product_barcode'] ?? '';
        final productInfo = productCode.isNotEmpty ? ' ($productCode)' : '';

        // Miktarlar - yeni enriched data'dan gelir
        final currentReceived = item['current_received']?.toDouble() ?? item['quantity']?.toDouble() ?? 0;
        final previousReceived = item['previous_received']?.toDouble() ?? 0;
        final totalReceived = item['total_received']?.toDouble() ?? currentReceived;
        final orderedQuantity = item['ordered_quantity']?.toDouble() ?? 0;
        final unit = item['unit'] ?? '';
        final palletBarcode = item['pallet_barcode'];

        // Get expiry date from the item
        final expiryDate = item['expiry_date'];
        String expiryDisplay = '';
        if (expiryDate != null && expiryDate.toString().isNotEmpty) {
          try {
            final parsedDate = DateTime.parse(expiryDate.toString());
            expiryDisplay = DateFormat('dd/MM/yyyy').format(parsedDate);
          } catch (e) {
            expiryDisplay = expiryDate.toString();
          }
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.move_to_inbox_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$productName$productInfo',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${currentReceived.toStringAsFixed(0)} $unit',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (isOrderBased && orderedQuantity > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.assignment_outlined, size: 16, color: Theme.of(context).hintColor),
                    const SizedBox(width: 4),
                    Text(
                      '${'pending_operations.operation_labels.order'.tr()}: ${orderedQuantity.toStringAsFixed(0)} $unit',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ],
              if (isOrderBased && previousReceived > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.history, size: 16, color: Theme.of(context).hintColor),
                    const SizedBox(width: 4),
                    Text(
                      '${'pending_operations.operation_labels.total_acceptance'.tr()}: ${previousReceived.toStringAsFixed(0)} + ${currentReceived.toStringAsFixed(0)} = ${totalReceived.toStringAsFixed(0)} $unit',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ],
              if (expiryDisplay.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: Theme.of(context).hintColor),
                    const SizedBox(width: 4),
                    Text(
                      'Expiry: $expiryDisplay',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ],
              if (productBarcode.isNotEmpty || palletBarcode != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (productBarcode.isNotEmpty) ...[
                      Icon(Icons.qr_code, size: 16, color: Theme.of(context).hintColor),
                      const SizedBox(width: 4),
                      Text(
                        productBarcode,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                    if (palletBarcode != null) ...[
                      if (productBarcode.isNotEmpty) const SizedBox(width: 16),
                      Icon(Icons.inventory, size: 16, color: Theme.of(context).hintColor),
                      const SizedBox(width: 4),
                      Text(
                        '${'pending_operations.operation_labels.pallet'.tr()}: $palletBarcode',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<Widget> _buildInventoryTransferDetailsAsync(BuildContext context, Map<String, dynamic> data) async {
    final db = DatabaseHelper.instance;

    // Enriched data al
    final enrichedData = await db.getEnrichedInventoryTransferData(jsonEncode(data));
    final header = enrichedData['header'] as Map<String, dynamic>? ?? {};
    final items = enrichedData['items'] as List<dynamic>? ?? [];

    // Bilgileri extract et
    final sourceName = header['source_location_name'] ?? 'N/A';
    final sourceCode = header['source_location_code'] ?? '';
    final targetName = header['target_location_name'] ?? 'N/A';
    final targetCode = header['target_location_code'] ?? '';
    final employeeName = header['employee_name'] ?? 'System User';
    // final operationType = header['operation_type'] ?? 'transfer';
    final containerId = header['container_id']?.toString();
    final poId = header['po_id']?.toString();

    // Operation type'a göre farklı başlıklar
    String transferTitle;
    String operationDescription;

    if (header['source_location_id'] == null || header['source_location_id'] == 0) {
      transferTitle = 'pending_operations.operation_types.putaway_operation'.tr();
      operationDescription = 'pending_operations.operation_types.putaway_operation'.tr();
    } else {
      transferTitle = 'pending_operations.operation_types.stock_transfer'.tr();
      operationDescription = 'pending_operations.operation_types.stock_transfer'.tr();
    }

    // Lokasyon display'leri
    final sourceDisplay = sourceCode.isNotEmpty ? '$sourceName ($sourceCode)' : sourceName;
    final targetDisplay = targetCode.isNotEmpty ? '$targetName ($targetCode)' : targetName;

    if (!context.mounted) return const SizedBox.shrink();

    return _buildDetailSection(
      context: context,
      title: transferTitle,
      details: {
        'dialog_labels.operation_type'.tr(): operationDescription,
        'dialog_labels.employee'.tr(): employeeName,
        'dialog_labels.from'.tr(): sourceDisplay == "000" ? "common_labels.goods_receiving_area".tr() : sourceDisplay,
        'dialog_labels.to'.tr(): targetDisplay,
        if (poId != null) 'dialog_labels.purchase_order'.tr(): poId,
        if (containerId != null) 'dialog_labels.container'.tr(): containerId,
        // 'dialog_labels.transfer_mode'.tr(): operationType == 'pallet_transfer' ? 'pending_operations.operation_types.pallet_transfer'.tr() : 'pending_operations.operation_types.box_transfer'.tr(),
      },
      items: items.cast<Map<String, dynamic>>(),
      itemBuilder: (item) {
        final productName = item['product_name'] ?? 'dialog_labels.unknown_product'.tr();
        final productCode = item['product_code'] ?? '';
        final productBarcode = item['product_barcode'] ?? '';
        final productInfo = productCode.isNotEmpty ? ' ($productCode)' : '';
        final quantity = item['quantity_transferred'] ?? item['quantity'] ?? 0;
        final container = item['pallet_id'] ?? item['pallet_barcode'];

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$productName$productInfo',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'x $quantity',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (productBarcode.isNotEmpty || container != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (productBarcode.isNotEmpty) ...[
                      Icon(Icons.qr_code, size: 16, color: Theme.of(context).hintColor),
                      const SizedBox(width: 4),
                      Text(
                        productBarcode,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                    if (container != null) ...[
                      if (productBarcode.isNotEmpty) const SizedBox(width: 16),
                      Icon(Icons.inventory, size: 16, color: Theme.of(context).hintColor),
                      const SizedBox(width: 4),
                      Text(
                        '${'pending_operations.operation_labels.container'.tr()}: $container',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                  ],
                ),
              ],
            ],
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
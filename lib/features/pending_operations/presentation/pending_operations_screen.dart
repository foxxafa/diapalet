// lib/features/pending_operations/presentation/pending_operations_screen.dart
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
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

class _PendingOperationsScreenState extends State<PendingOperationsScreen> {
  late final SyncService _syncService;
  List<PendingOperation> _pendingOperations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Provider'dan servis örneğini al, dinleme (listen) false olmalı.
    _syncService = context.read<SyncService>();
    _loadPendingOperations();
  }

  Future<void> _loadPendingOperations() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final operations = await _syncService.getPendingOperations();
      if (mounted) {
        setState(() => _pendingOperations = operations);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Bekleyen işlemler yüklenemedi: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performSync() async {
    if (!mounted) return;
    try {
      final result = await _syncService.uploadPendingOperations();
      if (mounted) {
        _showSnackBar(result.message, isError: !result.success);
        // Senkronizasyon sonrası liste otomatik olarak yenilenecek
        // çünkü SyncService başarılı olanları DB'den siliyor.
        _loadPendingOperations();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Senkronizasyon sırasında hata: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // SyncService'deki anlık durumu dinlemek için `watch` kullanılır.
    final syncStatus = context.watch<SyncService>().syncStatusStream;

    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;

    final appBarHeight = screenHeight * 0.07;
    final sizeFactor = (screenWidth / 480.0).clamp(0.9, 1.3);
    final appBarFontSize = 19.0 * sizeFactor;

    return Scaffold(
      appBar: SharedAppBar(
        title: 'pending_operations.title'.tr(),
        preferredHeight: appBarHeight,
        titleFontSize: appBarFontSize,
      ),
      body: RefreshIndicator(
        onRefresh: _loadPendingOperations,
        child: StreamBuilder<SyncStatus>(
          initialData: SyncStatus.offline, // Başlangıç değeri
          stream: syncStatus,
          builder: (context, snapshot) {
            final status = snapshot.data!;

            return Column(
              children: [
                _buildSyncStatusBanner(status),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _pendingOperations.isEmpty
                      ? Center(child: Text('pending_operations.no_pending'.tr()))
                      : ListView.builder(
                    itemCount: _pendingOperations.length,
                    itemBuilder: (context, index) {
                      final op = _pendingOperations[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          title: Text(op.displayTitle),
                          subtitle: Text(op.displaySubtitle),
                          trailing: op.status == 'failed'
                              ? const Icon(Icons.error, color: Colors.red)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _pendingOperations.isNotEmpty
          ? FloatingActionButton.extended(
        // Butonun aktif olup olmadığını anlık senkronizasyon durumuna göre belirle.
        onPressed: context.watch<SyncStatus>() == SyncStatus.syncing
            ? null
            : _performSync,
        icon: context.watch<SyncStatus>() == SyncStatus.syncing
            ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync),
        label: Text(context.watch<SyncStatus>() == SyncStatus.syncing
            ? 'pending_operations.syncing'.tr()
            : 'pending_operations.sync_now'.tr()),
      )
          : null,
    );
  }

  Widget _buildSyncStatusBanner(SyncStatus status) {
    IconData icon;
    Color color;
    String message;

    switch (status) {
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        color = Colors.grey;
        message = 'pending_operations.status.offline'.tr();
        break;
      case SyncStatus.online:
        icon = Icons.wifi;
        color = Colors.blue;
        message = 'pending_operations.status.online'.tr();
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
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.all(16.0),
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
            child: Text(message,
                style:
                TextStyle(fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ));
  }
}

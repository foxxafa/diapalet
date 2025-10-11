// lib/features/warehouse_count/presentation/screens/warehouse_count_review_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';
import 'package:diapalet/features/warehouse_count/domain/repositories/warehouse_count_repository.dart';
import 'package:diapalet/features/warehouse_count/presentation/widgets/counted_items_review_table.dart';

/// Screen to review counted items before saving
class WarehouseCountReviewScreen extends StatefulWidget {
  final CountSheet countSheet;
  final List<CountItem> countedItems;
  final WarehouseCountRepository repository;

  const WarehouseCountReviewScreen({
    super.key,
    required this.countSheet,
    required this.countedItems,
    required this.repository,
  });

  @override
  State<WarehouseCountReviewScreen> createState() => _WarehouseCountReviewScreenState();
}

class _WarehouseCountReviewScreenState extends State<WarehouseCountReviewScreen> {
  bool _isSaving = false;
  late List<CountItem> _currentItems;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.countedItems);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('warehouse_count.review_title'.tr()),
      ),
      body: Column(
        children: [
          // Header with summary
          _buildSummaryCard(),

          // Items table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: CountedItemsReviewTable(
                items: _currentItems,
                isReadOnly: false,
                onItemRemoved: _removeItem,
              ),
            ),
          ),

          // Bottom bar with save buttons
          _buildBottomBar(),
        ],
      ),
    );
  }

  Future<void> _removeItem(CountItem item) async {
    try {
      // Remove from database
      await widget.repository.deleteCountItem(item.id!);

      if (mounted) {
        setState(() {
          _currentItems.remove(item);
        });
        _showSuccess('warehouse_count.success.item_removed'.tr());
      }
    } catch (e) {
      debugPrint('Error removing count item: $e');
      if (mounted) {
        _showError('warehouse_count.error.remove_item'.tr());
      }
    }
  }

  Widget _buildSummaryCard() {
    final totalItems = _currentItems.length;
    final totalProductCount = _currentItems.where((item) => item.isProductCount).length;
    final totalPalletCount = _currentItems.where((item) => !item.isProductCount).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Total items
          _buildCompactSummaryItem(
            context,
            totalItems.toString(),
            Icons.summarize,
            Colors.grey[800]!,
            'Total',
          ),
          Container(
            width: 1,
            height: 35,
            color: Colors.grey[300],
          ),
          // Products
          _buildCompactSummaryItem(
            context,
            totalProductCount.toString(),
            Icons.inventory_2,
            Colors.grey[800]!,
            'Product',
          ),
          Container(
            width: 1,
            height: 35,
            color: Colors.grey[300],
          ),
          // Pallets
          _buildCompactSummaryItem(
            context,
            totalPalletCount.toString(),
            Icons.pallet,
            Colors.grey[800]!,
            'Pallet',
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSummaryItem(BuildContext context, String value, IconData icon, Color color, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveAndContinue,
              icon: const Icon(Icons.cloud_upload),
              label: Text('warehouse_count.save_continue'.tr()),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAndFinish,
              icon: const Icon(Icons.check_circle),
              label: Text('warehouse_count.save_finish'.tr()),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndContinue() async {
    setState(() => _isSaving = true);

    try {
      // Save to server directly (online operation)
      final success = await widget.repository.saveCountSheetToServer(
        widget.countSheet,
        _currentItems,
      );

      if (!mounted) return;

      if (success) {
        _showSuccess('warehouse_count.success.saved_online'.tr());
        Navigator.of(context).pop(); // Return to counting screen
      } else {
        _showError('warehouse_count.error.save_failed'.tr());
      }
    } catch (e) {
      if (mounted) {
        _showError('warehouse_count.error.save_failed'.tr());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveAndFinish() async {
    setState(() => _isSaving = true);

    try {
      // Complete the count sheet
      await widget.repository.completeCountSheet(widget.countSheet.id!);

      // Reload the updated count sheet from database to get complete_date and status
      final updatedSheet = await widget.repository.getCountSheetById(widget.countSheet.id!);

      if (updatedSheet == null) {
        throw Exception('Failed to reload count sheet after completion');
      }

      // Queue for sync (offline operation) with UPDATED sheet
      await widget.repository.queueCountSheetForSync(
        updatedSheet,
        _currentItems,
      );

      if (!mounted) return;

      // 🔥 YENİ: Senkronizasyonu başlat (goods_receiving gibi)
      // Arka planda senkronizasyonu tetikle, ama sonucunu bekleme.
      // Hata olursa (örn. offline), SyncService bunu daha sonra tekrar deneyecek.
      final syncService = context.read<SyncService>();
      syncService.uploadPendingOperations().catchError((e) {
        debugPrint('Senkronizasyon hatası (arka planda devam edecek): $e');
      });

      _showSuccess('warehouse_count.success.queued_for_sync'.tr());

      // Pop twice to return to list screen
      Navigator.of(context).pop(); // Exit review screen
      Navigator.of(context).pop(); // Exit counting screen
    } catch (e) {
      if (mounted) {
        _showError('warehouse_count.error.save_failed'.tr());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}

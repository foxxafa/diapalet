// lib/features/warehouse_count/presentation/screens/warehouse_count_review_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('warehouse_count.review_title'.tr()),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Header with summary
          _buildSummaryCard(),

          // Items table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CountedItemsReviewTable(
                items: widget.countedItems,
                isReadOnly: true,
              ),
            ),
          ),

          // Bottom bar with save buttons
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final totalItems = widget.countedItems.length;
    final totalProductCount = widget.countedItems.where((item) => item.isProductCount).length;
    final totalPalletCount = widget.countedItems.where((item) => !item.isProductCount).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'warehouse_count.review_summary'.tr(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                context,
                'warehouse_count.total_items'.tr(),
                totalItems.toString(),
                Icons.inventory,
              ),
              _buildSummaryItem(
                context,
                'warehouse_count.product_count'.tr(),
                totalProductCount.toString(),
                Icons.shopping_basket,
              ),
              _buildSummaryItem(
                context,
                'warehouse_count.pallet_count'.tr(),
                totalPalletCount.toString(),
                Icons.palette,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(BuildContext context, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
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
        widget.countedItems,
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

      // Queue for sync (offline operation)
      await widget.repository.queueCountSheetForSync(
        widget.countSheet,
        widget.countedItems,
      );

      if (!mounted) return;

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

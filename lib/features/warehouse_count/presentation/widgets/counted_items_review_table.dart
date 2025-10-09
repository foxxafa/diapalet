// lib/features/warehouse_count/presentation/widgets/counted_items_review_table.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';

/// Widget to display counted items in a scrollable table format
class CountedItemsReviewTable extends StatelessWidget {
  final List<CountItem> items;
  final ValueChanged<CountItem>? onItemRemoved;
  final bool isReadOnly;

  const CountedItemsReviewTable({
    super.key,
    required this.items,
    this.onItemRemoved,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'warehouse_count.no_items_counted'.tr(),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> states) {
              return Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3);
            },
          ),
          columns: [
            DataColumn(
              label: Text(
                'warehouse_count.table.type'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'warehouse_count.table.barcode'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'warehouse_count.table.stock_code'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'warehouse_count.table.shelf'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'warehouse_count.table.quantity'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
            if (!isReadOnly)
              DataColumn(
                label: Text(
                  'warehouse_count.table.actions'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: items.map((item) => _buildDataRow(context, item)).toList(),
        ),
      ),
    );
  }

  DataRow _buildDataRow(BuildContext context, CountItem item) {
    final theme = Theme.of(context);

    return DataRow(
      cells: [
        // Type (Product or Pallet)
        DataCell(
          Chip(
            label: Text(
              item.isProductCount
                  ? 'warehouse_count.mode.product'.tr()
                  : 'warehouse_count.mode.pallet'.tr(),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: item.isProductCount
                ? Colors.blue.withValues(alpha: 0.2)
                : Colors.purple.withValues(alpha: 0.2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),

        // Barcode (product barcode or pallet barcode)
        DataCell(
          Text(
            item.isProductCount
                ? (item.barcode ?? 'N/A')
                : (item.palletBarcode ?? 'N/A'),
            style: theme.textTheme.bodyMedium,
          ),
        ),

        // Stock Code (only for product count)
        DataCell(
          Text(
            item.stokKodu ?? '-',
            style: theme.textTheme.bodyMedium,
          ),
        ),

        // Shelf
        DataCell(
          Text(
            item.shelfCode ?? '-',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Quantity
        DataCell(
          Text(
            _formatQuantity(item.quantityCounted),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),

        // Actions (delete button)
        if (!isReadOnly)
          DataCell(
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              iconSize: 20,
              onPressed: onItemRemoved != null ? () => onItemRemoved!(item) : null,
              tooltip: 'warehouse_count.delete_item'.tr(),
            ),
          ),
      ],
    );
  }

  String _formatQuantity(double quantity) {
    // Remove trailing zeros and decimal point if not needed
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    return quantity.toStringAsFixed(4).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

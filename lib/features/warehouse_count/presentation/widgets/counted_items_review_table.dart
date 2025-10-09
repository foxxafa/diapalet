// lib/features/warehouse_count/presentation/widgets/counted_items_review_table.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';

/// Widget to display counted items in a compact list format
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'warehouse_count.no_items_counted'.tr(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey[300],
      ),
      itemBuilder: (context, index) {
        return _buildCompactListItem(context, items[index], index);
      },
    );
  }

  Widget _buildCompactListItem(BuildContext context, CountItem item, int index) {
    final theme = Theme.of(context);
    final isProduct = item.isProductCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: index.isEven ? Colors.grey[50] : Colors.white,
      child: Row(
        children: [
          // Tip ikonu (küçük)
          Icon(
            isProduct ? Icons.inventory_2 : Icons.view_in_ar,
            size: 18,
            color: Colors.grey[700],
          ),
          const SizedBox(width: 8),

          // Tip yazısı
          SizedBox(
            width: 50,
            child: Text(
              isProduct
                ? 'warehouse_count.mode.product'.tr()
                : 'warehouse_count.mode.pallet'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Stok Kodu veya Barkod
          Expanded(
            flex: 3,
            child: Text(
              isProduct
                ? (item.stokKodu ?? item.barcode ?? 'N/A')
                : (item.palletBarcode ?? 'N/A'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Shelf
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.shelfCode ?? '-',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: Colors.grey[800],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Quantity
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatQuantity(item.quantityCounted),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          // Sil butonu (eğer read-only değilse)
          if (!isReadOnly && onItemRemoved != null)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[600]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => onItemRemoved!(item),
              tooltip: 'warehouse_count.delete_item'.tr(),
            ),
        ],
      ),
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

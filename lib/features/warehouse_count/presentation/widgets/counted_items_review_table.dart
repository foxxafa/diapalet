// lib/features/warehouse_count/presentation/widgets/counted_items_review_table.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';

/// Widget to display counted items in a compact list format
class CountedItemsReviewTable extends StatelessWidget {
  final List<CountItem> items;
  final ValueChanged<CountItem>? onItemRemoved;
  final bool isReadOnly;
  final bool enableScroll; // Scroll aktif olsun mu?

  const CountedItemsReviewTable({
    super.key,
    required this.items,
    this.onItemRemoved,
    this.isReadOnly = false,
    this.enableScroll = true, // Varsayılan olarak scroll aktif
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
      shrinkWrap: !enableScroll, // Scroll kapalıysa shrinkWrap kullan
      physics: enableScroll ? null : const NeverScrollableScrollPhysics(), // Scroll kapalıysa physics kapat
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: index.isEven ? Colors.grey[50] : Colors.white,
      child: Row(
        children: [
          // Tip ikonu (küçük)
          Icon(
            isProduct ? Icons.inventory_2 : Icons.pallet,
            size: 16,
            color: theme.colorScheme.primary.withOpacity(0.7),
          ),
          const SizedBox(width: 6),

          // Stok Kodu (daha geniş)
          Expanded(
            flex: 3,
            child: Text(
              item.stokKodu ?? 'N/A',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),

          // Pallet Barkodu (sadece pallet modunda, kompakt)
          if (!isProduct) ...[
            Expanded(
              flex: 2,
              child: Text(
                item.palletBarcode ?? '-',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Colors.grey[700],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Shelf (kompakt badge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
          const SizedBox(width: 6),

          // Quantity + Birim (kompakt)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatQuantity(item.quantityCounted),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (item.birimAdi != null && item.birimAdi!.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    item.birimAdi!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ] else ...[
                  // Debug: Show birimKey if birimAdi is missing
                  if (item.birimKey != null)
                    Text(
                      ' [${item.birimKey}]',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                        color: Colors.red,
                      ),
                    ),
                ],
              ],
            ),
          ),

          // Sil butonu (eğer read-only değilse)
          if (!isReadOnly && onItemRemoved != null) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[600]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => onItemRemoved!(item),
              tooltip: 'warehouse_count.delete_item'.tr(),
            ),
          ],
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

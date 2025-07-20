import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../domain/entities/purchase_order.dart';

class OrderSummaryCard extends StatelessWidget {
  final PurchaseOrder? order;
  final int addedItemsCount;
  final int totalOrderItems;

  const OrderSummaryCard({
    super.key,
    this.order,
    required this.addedItemsCount,
    required this.totalOrderItems,
  });

  @override
  Widget build(BuildContext context) {
    if (order == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 12),
              Text(
                'goods_receiving_screen.no_order_selected'.tr(),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final progress = totalOrderItems > 0 ? addedItemsCount / totalOrderItems : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'goods_receiving_screen.order_info'.tr(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              'goods_receiving_screen.order_number'.tr(),
              order!.poId ?? 'N/A',
            ),
            _buildInfoRow(
              context,
              'goods_receiving_screen.supplier'.tr(),
              order!.supplierName ?? 'N/A',
            ),
            if (order!.date != null)
              _buildInfoRow(
                context,
                'goods_receiving_screen.order_date'.tr(),
                DateFormat('dd/MM/yyyy').format(order!.date!),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'goods_receiving_screen.progress'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0 ? Colors.green : Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$addedItemsCount / $totalOrderItems',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: progress >= 1.0 ? Colors.green : null,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
} 
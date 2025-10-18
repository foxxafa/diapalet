import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class OrderInfoCard extends StatelessWidget {
  final PurchaseOrder order;

  const OrderInfoCard({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Bu tasarım doğrudan goods_receiving_screen.dart'tan alınmıştır.
    return Container(
      width: double.infinity, // Tam genişlik
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // PO ID
          Text(
            order.poId ?? 'common_labels.not_available'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600, // Bold yerine w600
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          // Supplier Name (alt satırda)
          if (order.supplierName != null && order.supplierName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              order.supplierName!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
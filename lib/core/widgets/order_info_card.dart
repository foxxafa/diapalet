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
    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primaryContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'goods_receiving_screen.order_info_title'.tr(), // Çeviri anahtarı goods_receiving'den geliyor.
              style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer
              ),
            ),
            const SizedBox(height: 4),
            Text(
              order.poId ?? 'N/A',
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer
              ),
            ),
            if(order.supplierName != null && order.supplierName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                order.supplierName!,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
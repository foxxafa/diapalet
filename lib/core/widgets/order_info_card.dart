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
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.7),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow(
              context,
              icon: Icons.receipt_long_outlined,
              label: "Sipariş No",
              text: order.poId ?? 'N/A',
              isTitle: true,
            ),
            const Divider(height: 16),
            _buildInfoRow(
              context,
              icon: Icons.business_outlined,
              label: "Tedarikçi",
              text: order.supplierName ?? 'orders.no_supplier'.tr(),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              icon: Icons.calendar_today_outlined,
              label: "Tarih",
              text: order.date != null
                  ? DateFormat('dd MMMM yyyy, EEEE', context.locale.toString()).format(order.date!)
                  : 'order_selection.no_date'.tr(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, {required IconData icon, required String label, required String text, bool isTitle = false}) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final textStyle = isTitle
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)
        : theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if(!isTitle) Text(label, style: labelStyle),
            Text(text, style: textStyle),
          ],
        ),
      ],
    );
  }
}
// lib/features/goods_receiving/presentation/widgets/received_product_list_item_card.dart

import 'package:flutter/material.dart';
import '../../domain/entities/received_product_item.dart';

class ReceivedProductListItemCard extends StatelessWidget {
  final ReceivedProductItem item;
  final VoidCallback onDelete;

  const ReceivedProductListItemCard({
    super.key,
    required this.item,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "${item.productInfo.stockCode} - ${item.productInfo.name}",
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.redAccent[400]),
                  onPressed: onDelete,
                  tooltip: 'Bu Ürünü Sil',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Text("Barkod: ${item.barcode}", style: textTheme.bodySmall),
            const SizedBox(height: 4.0),
            Row(
              children: [
                Expanded(child: Text("SKT: ${item.formattedExpirationDate}", style: textTheme.bodyMedium)),
                Expanded(child: Text("Takip No: ${item.trackingNumber}", style: textTheme.bodyMedium)),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              "Miktar: ${item.quantity} ${item.unit}",
              style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../domain/entities/goods_receipt_entities.dart';

class AddedItemsList extends StatelessWidget {
  final List<ReceiptItemDraft> items;
  final Function(int index)? onRemoveItem;
  final Function(int index)? onEditItem;

  const AddedItemsList({
    super.key,
    required this.items,
    this.onRemoveItem,
    this.onEditItem,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'goods_receiving_screen.no_items_added'.tr(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              item.product.stockCode,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name),
                Text(
                  'goods_receiving_screen.quantity_unit'.tr(
                    namedArgs: {
                      'quantity': item.quantity.toString(),
                      'unit': '',
                    },
                  ),
                ),
                if (item.expiryDate != null)
                  Text(
                    'goods_receiving_screen.expiry_date'.tr(
                      namedArgs: {
                        'date': DateFormat('dd/MM/yyyy').format(item.expiryDate!),
                      },
                    ),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEditItem?.call(index);
                    break;
                  case 'remove':
                    onRemoveItem?.call(index);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit),
                      const SizedBox(width: 8),
                      Text('common_labels.edit'.tr()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(Icons.delete),
                      const SizedBox(width: 8),
                      Text('common_labels.remove'.tr()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 
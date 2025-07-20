import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../screens/goods_receiving_view_model.dart';

class ConfirmationDialog extends StatelessWidget {
  final GoodsReceivingViewModel viewModel;

  const ConfirmationDialog({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('goods_receiving_screen.confirm_save_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('goods_receiving_screen.confirm_save_message'.tr()),
          const SizedBox(height: 16),
          Text(
            'goods_receiving_screen.total_items'.tr(
              namedArgs: {'count': viewModel.addedItems.length.toString()},
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common_labels.cancel'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConfirmationAction.saveAndContinue),
          child: Text('goods_receiving_screen.save_and_continue'.tr()),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(ConfirmationAction.saveAndComplete),
          child: Text('goods_receiving_screen.save_and_complete'.tr()),
        ),
      ],
    );
  }
} 
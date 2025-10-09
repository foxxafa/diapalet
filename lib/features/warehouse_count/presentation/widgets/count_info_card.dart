// lib/features/warehouse_count/presentation/widgets/count_info_card.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';

/// Widget to display count sheet information in a card format
class CountInfoCard extends StatelessWidget {
  final CountSheet countSheet;
  final VoidCallback? onTap;

  const CountInfoCard({
    super.key,
    required this.countSheet,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = countSheet.isCompleted;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sheet number and status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      countSheet.sheetNumber,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusBadge(context, isCompleted),
                ],
              ),
              const SizedBox(height: 12),

              // Warehouse info
              _buildInfoRow(
                context,
                icon: Icons.warehouse,
                label: 'warehouse_count.warehouse'.tr(),
                value: countSheet.warehouseCode,
              ),

              const SizedBox(height: 8),

              // Start date
              _buildInfoRow(
                context,
                icon: Icons.calendar_today,
                label: 'warehouse_count.start_date'.tr(),
                value: DateFormat('dd/MM/yyyy HH:mm').format(countSheet.startDate),
              ),

              // Complete date (if completed)
              if (isCompleted && countSheet.completeDate != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  icon: Icons.check_circle,
                  label: 'warehouse_count.complete_date'.tr(),
                  value: DateFormat('dd/MM/yyyy HH:mm').format(countSheet.completeDate!),
                ),
              ],

              // Last saved date (if in progress and saved)
              if (!isCompleted && countSheet.lastSavedDate != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  icon: Icons.cloud_upload,
                  label: 'warehouse_count.last_saved'.tr(),
                  value: DateFormat('dd/MM/yyyy HH:mm').format(countSheet.lastSavedDate!),
                ),
              ],

              // Notes (if any)
              if (countSheet.notes != null && countSheet.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'warehouse_count.notes'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  countSheet.notes!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, bool isCompleted) {
    final color = isCompleted ? Colors.green : Colors.orange;
    final label = isCompleted
        ? 'warehouse_count.status.completed'.tr()
        : 'warehouse_count.status.in_progress'.tr();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.secondary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

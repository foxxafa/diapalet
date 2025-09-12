import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Enum to define different types of headers
enum HeaderType { deliveryNote, pallet, looseItems }

/// Utility class for building consistent headers in goods receiving feature
class HeaderBuilderUtils {
  /// Builds a generic header widget with configurable icon, title, and subtitle
  static Widget buildHeader(
    BuildContext context,
    HeaderType type, {
    String? subtitle,
    EdgeInsetsGeometry? padding,
  }) {
    final theme = Theme.of(context);
    
    // Configure header based on type
    late final IconData icon;
    late final String title;
    late final Color color;
    late final double iconSize;
    late final TextStyle? titleStyle;
    late final TextStyle? subtitleStyle;
    late final EdgeInsetsGeometry defaultPadding;

    switch (type) {
      case HeaderType.deliveryNote:
        icon = Icons.receipt_long;
        title = 'Delivery Note:';
        color = theme.colorScheme.primary;
        iconSize = 18;
        titleStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        );
        subtitleStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFamily: subtitle != null && subtitle != 'Genel' ? 'monospace' : null,
          color: subtitle != null && subtitle != 'Genel' 
              ? color 
              : theme.colorScheme.outline,
        );
        defaultPadding = const EdgeInsets.fromLTRB(8, 8, 8, 0);
        break;

      case HeaderType.pallet:
        icon = Icons.pallet;
        title = 'Pallet:';
        color = theme.colorScheme.secondary;
        iconSize = 16;
        titleStyle = theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        );
        subtitleStyle = theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: color,
        );
        defaultPadding = const EdgeInsets.fromLTRB(24, 12, 8, 4);
        break;

      case HeaderType.looseItems:
        icon = Icons.inventory_2_outlined;
        title = 'goods_receiving_screen.other_items'.tr();
        color = theme.colorScheme.outline;
        iconSize = 16;
        titleStyle = theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        );
        subtitleStyle = null;
        defaultPadding = const EdgeInsets.fromLTRB(24, 12, 8, 4);
        break;
    }

    return Padding(
      padding: padding ?? defaultPadding,
      child: Row(
        children: [
          Icon(
            icon,
            size: iconSize,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: titleStyle,
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: subtitleStyle,
            ),
          ],
        ],
      ),
    );
  }

  /// Convenience method for delivery note header
  static Widget buildDeliveryNoteHeader(
    BuildContext context,
    String? noteNumber, {
    EdgeInsetsGeometry? padding,
  }) {
    return buildHeader(
      context,
      HeaderType.deliveryNote,
      subtitle: noteNumber ?? 'Genel',
      padding: padding,
    );
  }

  /// Convenience method for pallet header
  static Widget buildPalletHeader(
    BuildContext context,
    String palletBarcode, {
    EdgeInsetsGeometry? padding,
  }) {
    return buildHeader(
      context,
      HeaderType.pallet,
      subtitle: palletBarcode,
      padding: padding,
    );
  }

  /// Convenience method for loose items header
  static Widget buildLooseItemsHeader(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
  }) {
    return buildHeader(
      context,
      HeaderType.looseItems,
      padding: padding,
    );
  }

  // Private constructor to prevent instantiation
  const HeaderBuilderUtils._();
}
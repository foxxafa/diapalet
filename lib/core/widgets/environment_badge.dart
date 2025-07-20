// lib/core/widgets/environment_badge.dart
import 'package:diapalet/core/network/api_config.dart';
import 'package:flutter/material.dart';

/// Uygulamanın hangi ortamda çalıştığını gösteren badge widget
class EnvironmentBadge extends StatelessWidget {
  final bool showOnlyInDebug;

  const EnvironmentBadge({
    super.key,
    this.showOnlyInDebug = true,
  });

  @override
  Widget build(BuildContext context) {
    // Sadece debug modda göster (opsiyonel)
    if (showOnlyInDebug && !ApiConfig.isLocal) {
      return const SizedBox.shrink();
    }

    // Ortama göre renk belirle
    Color badgeColor = Colors.grey;
    if (ApiConfig.isLocal) {
      badgeColor = Colors.blue;
    } else if (ApiConfig.isStaging) {
      badgeColor = Colors.orange;
    } else if (ApiConfig.isProduction) {
      badgeColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        ApiConfig.environmentName.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
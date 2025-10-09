import 'package:flutter/material.dart';

class ErrorDialogService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Kalıcı hata durumunda global modal göster
  static Future<void> showPermanentErrorDialog({
    required String errorCode,
    required String message,
    String? details,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Ses veya titreşim için HapticFeedback kullanılabilir
    // HapticFeedback.heavyImpact();

    return showDialog(
      context: context,
      barrierDismissible: false, // Kullanıcı dışarı tıklayarak kapatamaz
      builder: (BuildContext context) {
        return AlertDialog(
          icon: Icon(
            Icons.block_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 48,
          ),
          title: Text(
            _getErrorTitle(errorCode),
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (details != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Teknik Detaylar:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withAlpha(100)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu işlem kalıcı olarak reddedildi ve tekrar denenmeyecek. Yöneticinize bilgi verildi.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Anladım'),
            ),
          ],
        );
      },
    );
  }

  static String _getErrorTitle(String errorCode) {
    switch (errorCode) {
      case 'ORDER_CLOSED':
        return 'Sipariş Kapalı';
      case 'ORDER_NOT_FOUND':
        return 'Sipariş Bulunamadı';
      case 'INSUFFICIENT_STOCK':
        return 'Yetersiz Stok';
      case 'LOCATION_NOT_FOUND':
        return 'Lokasyon Bulunamadı';
      case 'PRODUCT_NOT_FOUND':
        return 'Ürün Bulunamadı';
      default:
        return 'İşlem Reddedildi';
    }
  }

  /// Geçici hata modalı (retry yapılabilir hatalar için)
  static Future<bool> showRetryableErrorDialog({
    required String message,
    String? details,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          icon: Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 48,
          ),
          title: Text(
            'Geçici Hata',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (details != null) ...[
                const SizedBox(height: 8),
                Text(
                  details,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Tekrar Dene'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
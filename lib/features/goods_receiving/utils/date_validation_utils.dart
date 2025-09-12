import 'package:easy_localization/easy_localization.dart';

class DateValidationUtils {
  /// Validates if a date string is in DD/MM/YYYY format and is a valid future date
  static bool isValidExpiryDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return false;
    }

    // Format kontrolü: DD/MM/YYYY
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dateString)) {
      return false;
    }

    try {
      final parts = dateString.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      // Temel sınır kontrolü
      if (month < 1 || month > 12 || day < 1) {
        return false;
      }

      // DateTime oluştur ve geçerliliğini kontrol et
      final date = DateTime(year, month, day);

      // DateTime constructor geçersiz tarihleri düzeltir, bu yüzden kontrol et
      if (date.day != day || date.month != month || date.year != year) {
        return false;
      }

      // Geçmiş tarih kontrolü
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      return !date.isBefore(todayDate);
    } catch (e) {
      return false;
    }
  }

  /// Gets specific validation error message for date string
  static String getDateValidationError(String dateString) {
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dateString)) {
      return 'goods_receiving_screen.validator_expiry_date_format'.tr();
    }

    try {
      final parts = dateString.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      // Temel yapı kontrolü
      if (month < 1 || month > 12 || day < 1) {
        return 'goods_receiving_screen.validator_expiry_date_format'.tr();
      }

      // DateTime oluştur ve geçerliliğini kontrol et
      final date = DateTime(year, month, day);

      // Tarih düzeltildi mi kontrol et (örn: 30 Şubat)
      if (date.day != day || date.month != month || date.year != year) {
        return 'goods_receiving_screen.validator_expiry_date_format'.tr();
      }

      // Geçmiş tarih kontrolü
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      if (date.isBefore(todayDate)) {
        return 'goods_receiving_screen.validator_expiry_date_future'.tr();
      }

      return 'goods_receiving_screen.validator_expiry_date_format'.tr();
    } catch (e) {
      return 'goods_receiving_screen.validator_expiry_date_format'.tr();
    }
  }
}
// lib/core/services/telegram_logger_service.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/services/app_version_service.dart';

/// Telegram'a log dosyası gönderen hibrit servis
///
/// CRITICAL loglar -> Anında Telegram'a gönderilir
/// ERROR loglar -> SQLite'a kaydedilir (manuel gönderim için)
///
/// Kullanıcı "Gönder" butonuna bastığında tüm SQLite logları Telegram'a gönderilir
class TelegramLoggerService {
  static final Dio _dio = ApiConfig.dio;
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Cache için son gönderilen hatalar (spam prevention)
  static final Map<String, DateTime> _lastSentErrors = {};
  static const Duration _spamPreventionDuration = Duration(minutes: 30);

  /// ERROR seviyesinde log kaydet (SQLite'a)
  ///
  /// ERROR loglar anında Telegram'a GÖNDERİLMEZ, SQLite'a kaydedilir
  /// Kullanıcı manuel olarak "Gönder" butonuna bastığında Telegram'a gider
  ///
  /// [title]: Log başlığı (örn: "Database Query Failed")
  /// [message]: Hata mesajı
  /// [stackTrace]: Stack trace (opsiyonel)
  /// [context]: Ek bağlam bilgileri (opsiyonel)
  /// [employeeId]: Çalışan ID (opsiyonel)
  /// [employeeName]: Çalışan adı (opsiyonel)
  static Future<void> logError(
    String title,
    String message, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    int? employeeId,
    String? employeeName,
  }) async {
    try {
      // ERROR logları SQLite'a kaydet (Telegram'a gönderme)
      final db = DatabaseHelper.instance;
      final deviceData = await _getDeviceInfo();

      await db.saveLogEntry(
        level: 'ERROR',
        title: title,
        message: message,
        stackTrace: stackTrace?.toString(),
        context: context,
        deviceInfo: deviceData,
        employeeId: employeeId,
        employeeName: employeeName,
      );

      debugPrint('📝 Log saved to database: $title');
    } catch (e) {
      debugPrint('❌ Failed to save log: $e');
    }
  }

  /// CRITICAL seviyesinde log gönder (Anında Telegram'a)
  ///
  /// CRITICAL loglar ANINDA Telegram'a gönderilir (spam koruması ile)
  static Future<void> logCritical(
    String title,
    String message, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    int? employeeId,
    String? employeeName,
  }) async {
    await _sendLog(
      level: 'CRITICAL',
      title: title,
      message: message,
      stackTrace: stackTrace,
      context: context,
      employeeId: employeeId,
      employeeName: employeeName,
    );
  }

  /// Manuel olarak tüm logları Telegram'a gönder
  ///
  /// Pending Operations ekranındaki "Gönder" butonundan çağrılır
  /// Son [hours] saatteki tüm logları tek TXT dosyası olarak gönderir
  static Future<bool> sendAllLogs({int hours = 24}) async {
    try {
      final db = DatabaseHelper.instance;

      // Son X saatteki logları al
      final since = DateTime.now().subtract(Duration(hours: hours));
      final logs = await db.getLogEntries(since: since);

      if (logs.isEmpty) {
        debugPrint('ℹ️ No logs to send');
        return false;
      }

      // Tüm logları tek dosya içeriği olarak birleştir
      final combinedContent = await _formatCombinedLogs(logs);

      // Cihaz bilgilerini topla
      final deviceData = await _getDeviceInfo();

      // Backend'e gönder
      final response = await _dio.post(
        '/index.php?r=terminal/telegram-log-file',
        data: {
          'level': 'INFO',
          'title': 'WMS Log Report (Last $hours hours)',
          'log_content': combinedContent,
          'device_info': deviceData,
        },
      );

      if (response.statusCode == 200) {
        // Başarılı gönderimden sonra logları temizle
        await db.deleteAllLogs();
        debugPrint('✅ All logs sent and deleted successfully');
        return true;
      } else {
        debugPrint('❌ Failed to send logs: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sending logs: $e');
      return false;
    }
  }

  /// Birden fazla log entry'yi tek dosya içeriğinde birleştir
  static Future<String> _formatCombinedLogs(List<Map<String, dynamic>> logs) async {
    final buffer = StringBuffer();
    final appVersion = await _getAppVersion();

    buffer.writeln('=' * 80);
    buffer.writeln('WMS COMBINED LOG REPORT');
    buffer.writeln('=' * 80);
    buffer.writeln('Generated at: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('App Version: $appVersion');
    buffer.writeln('Total log entries: ${logs.length}');
    buffer.writeln();

    for (var i = 0; i < logs.length; i++) {
      final log = logs[i];
      buffer.writeln('─' * 80);
      buffer.writeln('LOG ENTRY ${i + 1} of ${logs.length}');
      buffer.writeln('─' * 80);
      buffer.writeln('Level: ${log['level']}');
      buffer.writeln('Title: ${log['title']}');
      buffer.writeln('Time: ${log['created_at']}');

      if (log['employee_name'] != null) {
        buffer.writeln('Employee: ${log['employee_name']} (ID: ${log['employee_id']})');
      }
      buffer.writeln();

      buffer.writeln('MESSAGE:');
      buffer.writeln(log['message']);
      buffer.writeln();

      if (log['context'] != null) {
        buffer.writeln('CONTEXT:');
        buffer.writeln(log['context']);
        buffer.writeln();
      }

      if (log['device_info'] != null) {
        buffer.writeln('DEVICE INFO:');
        buffer.writeln(log['device_info']);
        buffer.writeln();
      }

      if (log['stack_trace'] != null) {
        buffer.writeln('STACK TRACE:');
        buffer.writeln(log['stack_trace']);
        buffer.writeln();
      }
      buffer.writeln();
    }

    buffer.writeln('=' * 80);
    buffer.writeln('END OF REPORT');
    buffer.writeln('=' * 80);

    return buffer.toString();
  }

  /// Ana log gönderme metodu
  static Future<void> _sendLog({
    required String level,
    required String title,
    required String message,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    int? employeeId,
    String? employeeName,
  }) async {
    try {
      // Spam prevention: Aynı hata 30dk içinde tekrar gönderilmesin
      final errorKey = '$title:$message';
      final lastSent = _lastSentErrors[errorKey];
      if (lastSent != null &&
          DateTime.now().difference(lastSent) < _spamPreventionDuration) {
        debugPrint('⏭️ Telegram log skipped (spam prevention): $title');
        return;
      }

      // Cihaz bilgilerini topla
      final deviceData = await _getDeviceInfo();
      final appVersion = await _getAppVersion();
      final sqliteVersion = await _getSQLiteVersion();

      // Log dosyası içeriğini oluştur
      final logContent = _formatLogContent(
        level: level,
        title: title,
        message: message,
        stackTrace: stackTrace,
        context: context,
        deviceData: deviceData,
        appVersion: appVersion,
        sqliteVersion: sqliteVersion,
        employeeId: employeeId,
        employeeName: employeeName,
      );

      // Backend'e gönder
      final response = await _dio.post(
        '/index.php?r=terminal/telegram-log-file',
        data: {
          'level': level,
          'title': title,
          'log_content': logContent,
          'device_info': deviceData,
          'employee_id': employeeId,
          'employee_name': employeeName,
        },
      );

      if (response.statusCode == 200) {
        _lastSentErrors[errorKey] = DateTime.now();
        debugPrint('✅ Telegram log sent successfully: $title');
      } else {
        debugPrint('❌ Failed to send Telegram log: ${response.statusCode}');
      }
    } catch (e) {
      // Loglama servisi hata verirse sessizce yut (sonsuz loop önleme)
      debugPrint('❌ TelegramLoggerService error: $e');
    }
  }

  /// Log dosyası içeriğini formatla
  static String _formatLogContent({
    required String level,
    required String title,
    required String message,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    required Map<String, String> deviceData,
    required String appVersion,
    required String sqliteVersion,
    int? employeeId,
    String? employeeName,
  }) {
    final buffer = StringBuffer();
    final timestamp = DateTime.now().toUtc().toIso8601String();

    // Header
    buffer.writeln('=' * 60);
    buffer.writeln('WMS ERROR LOG');
    buffer.writeln('=' * 60);
    buffer.writeln('Timestamp: $timestamp');
    buffer.writeln('Log Level: $level');
    buffer.writeln('Operation: $title');
    buffer.writeln();

    // Device Information
    buffer.writeln('DEVICE INFORMATION');
    buffer.writeln('-' * 60);
    deviceData.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    buffer.writeln('SQLite Version: $sqliteVersion');
    buffer.writeln('App Version: $appVersion');
    if (employeeId != null) {
      buffer.writeln('Employee ID: $employeeId');
    }
    if (employeeName != null) {
      buffer.writeln('Employee Name: $employeeName');
    }
    buffer.writeln();

    // Error Details
    buffer.writeln('ERROR DETAILS');
    buffer.writeln('-' * 60);
    buffer.writeln('Error Message: $message');
    buffer.writeln();

    // Context (ek bilgiler)
    if (context != null && context.isNotEmpty) {
      buffer.writeln('CONTEXT');
      buffer.writeln('-' * 60);
      context.forEach((key, value) {
        buffer.writeln('$key: $value');
      });
      buffer.writeln();
    }

    // Stack Trace
    if (stackTrace != null) {
      buffer.writeln('STACK TRACE');
      buffer.writeln('-' * 60);
      buffer.writeln(stackTrace.toString());
      buffer.writeln();
    }

    buffer.writeln('=' * 60);

    return buffer.toString();
  }

  /// Cihaz bilgilerini topla
  static Future<Map<String, String>> _getDeviceInfo() async {
    final info = <String, String>{};

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        info['Platform'] = 'Android';
        info['Device'] = '${androidInfo.manufacturer} ${androidInfo.model}';
        info['OS Version'] = 'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})';
        info['Brand'] = androidInfo.brand;
        info['Hardware'] = androidInfo.hardware;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        info['Platform'] = 'iOS';
        info['Device'] = iosInfo.utsname.machine;
        info['OS Version'] = '${iosInfo.systemName} ${iosInfo.systemVersion}';
        info['Model'] = iosInfo.model;
      } else {
        info['Platform'] = Platform.operatingSystem;
        info['OS Version'] = Platform.operatingSystemVersion;
      }
    } catch (e) {
      info['Platform'] = 'Unknown';
      info['Error'] = 'Failed to get device info: $e';
    }

    return info;
  }

  /// App versiyonunu al
  static Future<String> _getAppVersion() async {
    try {
      return await AppVersionService.instance.getVersionForDisplay();
    } catch (e) {
      return 'Unknown';
    }
  }

  /// SQLite versiyonunu al (database helper'dan)
  static Future<String> _getSQLiteVersion() async {
    try {
      // SQLite versiyonunu almak için database helper'a erişmek gerekebilir
      // Şimdilik basit bir çözüm: Android API level'a göre tahmin et
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        // Android SDK -> SQLite version mapping (approximate)
        if (sdkInt >= 28) return '3.22.0+'; // Android 9+
        if (sdkInt >= 26) return '3.19.x'; // Android 8
        if (sdkInt >= 24) return '3.9.2'; // Android 7
        if (sdkInt >= 21) return '3.8.x'; // Android 5-6
        return '3.7.x or older';
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }
}

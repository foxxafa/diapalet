// lib/core/services/database_backup_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Basit veritabanı yedekleme servisi
/// Giriş yapıldığında veritabanını telefonun içine kaydeder
class DatabaseBackupService {
  static const String _backupFileName = 'rowhub_backup.db';

  /// Veritabanını yedekle (giriş yaparken çağrılır)
  /// Her zaman aynı dosyanın üstüne yazar
  Future<bool> backupDatabase(String dbPath) async {
    try {
      // Kaynak veritabanı dosyası
      final sourceFile = File(dbPath);

      if (!await sourceFile.exists()) {
        debugPrint('❌ Veritabanı dosyası bulunamadı: $dbPath');
        return false;
      }

      // Yedek klasörü oluştur
      final backupDir = await _getBackupDirectory();
      if (backupDir == null) {
        debugPrint('❌ Yedek klasörü oluşturulamadı');
        return false;
      }

      // Yedek dosya yolu
      final backupPath = join(backupDir.path, _backupFileName);
      final backupFile = File(backupPath);

      // Dosyayı kopyala (üstüne yaz)
      await sourceFile.copy(backupPath);

      final fileSize = await backupFile.length();
      debugPrint('✅ Veritabanı yedeklendi: $backupPath (${_formatBytes(fileSize)})');

      return true;
    } catch (e) {
      debugPrint('❌ Veritabanı yedekleme hatası: $e');
      return false;
    }
  }

  /// Yedek klasörünü al veya oluştur
  /// Android: Public Documents klasörü (TÜM dosya yöneticilerinden görünür!)
  /// iOS: Documents directory (iCloud ile senkronize olabilir)
  Future<Directory?> _getBackupDirectory() async {
    try {
      Directory backupDir;

      if (Platform.isAndroid) {
        // Android: Public Documents klasörünü kullan
        // Path: /storage/emulated/0/Documents/RowHub
        // TÜM dosya yöneticilerinden ERİŞİLEBİLİR! ✅

        // İzin kontrolü (Android 10+)
        if (await _requestStoragePermission()) {
          // Public Documents klasörü
          const publicDocumentsPath = '/storage/emulated/0/Documents/RowHub';
          backupDir = Directory(publicDocumentsPath);

          debugPrint('📂 Public Documents klasörü kullanılıyor: $publicDocumentsPath');
        } else {
          // İzin yok, fallback kullan
          debugPrint('⚠️ Storage izni yok, fallback kullanılıyor');
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            backupDir = Directory(join(externalDir.path, 'RowHub'));
          } else {
            final documentsDir = await getApplicationDocumentsDirectory();
            backupDir = Directory(join(documentsDir.path, 'RowHub', 'Backups'));
          }
        }
      } else {
        // iOS: Documents klasörü
        final documentsDir = await getApplicationDocumentsDirectory();
        backupDir = Directory(join(documentsDir.path, 'RowHub', 'Backups'));
      }

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
        debugPrint('📁 Yedek klasörü oluşturuldu: ${backupDir.path}');
      }

      return backupDir;
    } catch (e) {
      debugPrint('❌ Yedek klasörü oluşturma hatası: $e');
      return null;
    }
  }

  /// Storage izni iste (Android 10+)
  Future<bool> _requestStoragePermission() async {
    try {
      // Android 13+ için farklı izin sistemi
      if (Platform.isAndroid) {
        // Android 10-12 için WRITE_EXTERNAL_STORAGE
        // Android 13+ için izin gerekmez (MediaStore kullanırsak)
        var status = await Permission.storage.status;

        if (status.isGranted) {
          return true;
        }

        // İzin iste (sessizce, kullanıcıya gösterme - reddederse fallback kullan)
        status = await Permission.storage.request();
        return status.isGranted;
      }
      return true; // iOS için izin gereksiz
    } catch (e) {
      debugPrint('⚠️ Storage izni hatası: $e');
      return false; // Hata olursa fallback kullan
    }
  }

  /// Byte'ları okunabilir formata çevir
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Yedek dosyasının yolunu al
  Future<String?> getBackupPath() async {
    try {
      final backupDir = await _getBackupDirectory();
      if (backupDir == null) return null;

      final backupPath = join(backupDir.path, _backupFileName);
      final backupFile = File(backupPath);

      if (await backupFile.exists()) {
        return backupPath;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Yedek dosya yolu alma hatası: $e');
      return null;
    }
  }
}
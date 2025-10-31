// lib/core/services/database_backup_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Basit veritabanı yedekleme servisi
/// Giriş yapıldığında veritabanını telefonun içine kaydeder
class DatabaseBackupService {
  static const String _backupFileName = 'rowhub_backup.db';

  /// Veritabanını yedekle (giriş yaparken çağrılır)
  /// Gereksiz statik tabloları temizler ve optimize edilmiş yedek oluşturur
  /// Her zaman aynı dosyanın üstüne yazar
  Future<bool> backupDatabase(String dbPath, {bool cleanStaticTables = true}) async {
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

      Uint8List dbBytes;

      if (cleanStaticTables) {
        // Temizlenmiş veritabanı oluştur
        dbBytes = await createCleanedDatabaseCopy(dbPath);
      } else {
        // Orijinal veritabanını kullan
        dbBytes = await sourceFile.readAsBytes();
      }

      // Temizlenmiş/orijinal veritabanını yaz
      await File(backupPath).writeAsBytes(dbBytes);

      final fileSize = dbBytes.length;
      debugPrint('✅ Veritabanı yedeklendi: $backupPath (${_formatBytes(fileSize)})');

      return true;
    } catch (e) {
      debugPrint('❌ Veritabanı yedekleme hatası: $e');
      return false;
    }
  }

  /// Gereksiz tabloları temizlenmiş database kopyası oluştur
  /// Statik tablolar (urunler, barkodlar, etc.) export'a dahil edilmez
  /// Bu tablolar backend'den her sync'te gelir, yedekte tutmaya gerek yok
  Future<Uint8List> createCleanedDatabaseCopy(String originalDbPath) async {
    final tempDir = await getTemporaryDirectory();
    final tempDbPath = join(tempDir.path, 'backup_temp_${DateTime.now().millisecondsSinceEpoch}.db');

    try {
      // 1. Orijinal database'i geçici konuma kopyala
      await File(originalDbPath).copy(tempDbPath);
      debugPrint('📋 Temporary database created for backup');

      // 2. Geçici database'i aç
      final tempDb = await sqflite.openDatabase(tempDbPath);

      // 3. Gereksiz statik tabloları temizle (backend'den sync edilen tablolar)
      final tablesToClear = [
        'urunler',      // Ürün listesi (backend'den gelir)
        'barkodlar',    // Barkod listesi (backend'den gelir)
        'birimler',     // Birim listesi (backend'den gelir)
        'shelfs',       // Raf listesi (backend'den gelir)
        'tedarikci',    // Tedarikçi listesi (backend'den gelir)
      ];

      for (final table in tablesToClear) {
        try {
          await tempDb.execute('DELETE FROM $table');
          debugPrint('🗑️ Cleared table: $table');
        } catch (e) {
          debugPrint('⚠️ Could not clear table $table: $e');
          // Tablo yoksa devam et
        }
      }

      // 4. VACUUM - dosya boyutunu küçült
      await tempDb.execute('VACUUM');
      debugPrint('🔧 VACUUM completed');

      // 5. Database'i kapat
      await tempDb.close();

      // 6. Temizlenmiş database'i oku
      final cleanedBytes = await File(tempDbPath).readAsBytes();
      final originalSize = await File(originalDbPath).length();
      final cleanedSize = cleanedBytes.length;
      final reduction = ((originalSize - cleanedSize) / originalSize * 100).toStringAsFixed(1);

      debugPrint('📦 Database cleaned: ${_formatBytes(originalSize)} → ${_formatBytes(cleanedSize)} (-$reduction%)');

      // 7. Geçici dosyayı sil
      await File(tempDbPath).delete();

      return Uint8List.fromList(cleanedBytes);
    } catch (e) {
      debugPrint('❌ Error creating cleaned database: $e');
      // Hata durumunda geçici dosyayı sil
      try {
        await File(tempDbPath).delete();
      } catch (_) {}
      // Hata olursa orijinal database'i döndür
      return await File(originalDbPath).readAsBytes();
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
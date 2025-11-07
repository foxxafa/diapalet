// lib/features/auth/presentation/login_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/sync_loading_screen.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:diapalet/features/home/presentation/home_screen.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/services/database_backup_service.dart';
import 'package:diapalet/core/services/telegram_logger_service.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final authRepository = context.read<AuthRepository>();

      try {
        final authData = await authRepository.login(
          _usernameController.text,
          _passwordController.text,
        );

        if (authData != null && mounted) {
          // ✅ Veritabanını yedekle (giriş başarılı olduğunda)
          try {
            final backupService = DatabaseBackupService();
            final dbHelper = DatabaseHelper.instance;
            final dbPath = await dbHelper.getDatabasePath();
            await backupService.backupDatabase(dbPath);
          } catch (e) {
            debugPrint('⚠️ Backup hatası (giriş devam edecek): $e');
            // Backup hatası olsa bile giriş devam etsin
          }

          final syncService = context.read<SyncService>();
          final networkInfo = context.read<NetworkInfo>();

          // Check if we have internet connection
          final hasInternet = await networkInfo.isConnected;

          if (hasInternet) {
            // Show sync loading screen only if online
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SyncLoadingScreen(
                  progressStream: syncService.syncProgressStream,
                  onSyncComplete: () {
                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (context) => const HomeScreen()),
                      );
                    }
                  },
                  onSyncError: (error) {
                    if (mounted) {
                      Navigator.of(context).pop(); // Close loading screen
                      setState(() {
                        _errorMessage = 'sync.errors.general'.tr();
                      });
                    }
                  },
                ),
              ),
            );

            // Start sync after frame is built to ensure stream listeners are ready
            WidgetsBinding.instance.addPostFrameCallback((_) {
              syncService.performFullSync();
            });
          } else {
            // Offline login - go directly to home screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            final errorText = e.toString().replaceFirst("Exception: ", "");
            // Eğer hata mesajı bir localization key ise çevir
            if (errorText.startsWith('login.error.')) {
              _errorMessage = errorText.tr();
            } else {
              _errorMessage = errorText;
            }
          });

          // 🔴 Login başarısız olduğunda veritabanını otomatik olarak Telegram'a gönder
          _sendDatabaseOnLoginFailure(e.toString());
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  /// Login başarısız olduğunda database ve logları otomatik olarak Telegram'a gönder
  Future<void> _sendDatabaseOnLoginFailure(String errorMessage) async {
    try {
      debugPrint('🔴 Login failed, sending database and logs to Telegram...');

      final db = DatabaseHelper.instance;
      final prefs = await SharedPreferences.getInstance();
      final username = _usernameController.text.trim();
      final warehouseCode = prefs.getString('warehouse_code') ?? 'Unknown';

      // 1️⃣ LOGLAR - Önce logları gönder (TelegramLoggerService kullanarak)
      bool logsSent = false;
      try {
        final logCount = await db.getLogCount();
        if (logCount > 0) {
          debugPrint('📝 Sending $logCount logs to Telegram...');
          logsSent = await TelegramLoggerService.sendAllLogs(hours: 168); // Son 7 gün
          if (logsSent) {
            debugPrint('✅ Logs sent to Telegram successfully');
          }
        } else {
          debugPrint('ℹ️ No logs to send');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to send logs: $e');
        // Log gönderimi başarısız olsa bile database gönderelim
      }

      // 2️⃣ DATABASE - Sonra database'i gönder
      bool dbSent = false;
      try {
        final dbPath = await db.getDatabasePath();

        // Temizlenmiş database kopyası oluştur
        final backupService = DatabaseBackupService();
        final dbBytes = await backupService.createCleanedDatabaseCopy(dbPath);

        // Telegram'a gönder
        dbSent = await _uploadDatabaseToTelegram(
          dbBytes,
          username,
          warehouseCode,
          errorMessage,
        );

        if (dbSent) {
          debugPrint('✅ Database sent to Telegram on login failure');
        } else {
          debugPrint('⚠️ Failed to send database to Telegram');
        }
      } catch (e) {
        debugPrint('❌ Error sending database: $e');
      }

      // Özet log
      if (logsSent && dbSent) {
        debugPrint('🎉 Both logs and database sent successfully');
      } else if (logsSent) {
        debugPrint('⚠️ Only logs sent (database failed)');
      } else if (dbSent) {
        debugPrint('⚠️ Only database sent (no logs or logs failed)');
      } else {
        debugPrint('❌ Failed to send both logs and database');
      }
    } catch (e) {
      debugPrint('❌ Error in login failure handler: $e');
      // Sessizce yut - login hatası daha önemli
    }
  }

  /// Veritabanını Telegram'a yükle
  Future<bool> _uploadDatabaseToTelegram(
    Uint8List dbBytes,
    String username,
    String warehouseCode,
    String loginError,
  ) async {
    try {
      final dio = ApiConfig.dio;
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'LoginFailed_${username}_${warehouseCode}_$timestamp.db';

      // Base64 encode et
      final base64Db = base64Encode(dbBytes);

      // Backend'e gönder
      final response = await dio.post(
        ApiConfig.uploadDatabase,
        data: {
          'database_file': base64Db,
          'filename': filename,
          'employee_name': username,
          'warehouse_code': warehouseCode,
          'login_error': loginError,
          'auto_sent_on_login_failure': true,
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(minutes: 2),
        ),
      );

      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      debugPrint('Telegram upload error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text(
                  'login.title'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'login.subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _usernameController,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: 'login.username'.tr(),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'login.error.required_field'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: 'login.password'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'login.error.required_field'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),

                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  onPressed: _login,
                  child: Text('login.button'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

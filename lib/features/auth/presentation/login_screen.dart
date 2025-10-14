// lib/features/auth/presentation/login_screen.dart
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/sync_loading_screen.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:diapalet/features/home/presentation/home_screen.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

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

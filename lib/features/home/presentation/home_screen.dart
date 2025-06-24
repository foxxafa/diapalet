// lib/features/home/presentation/home_screen.dart
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:diapalet/features/auth/presentation/login_screen.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_options_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/transfer_type_selection_screen.dart';
import 'package:diapalet/features/pending_operations/presentation/pending_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = '...';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final firstName = prefs.getString('first_name') ?? '';
    final lastName = prefs.getString('last_name') ?? '';
    if (mounted) {
      setState(() {
        _userName = '$firstName $lastName';
      });
    }
  }

  Future<void> _handleLogoutAttempt() async {
    final syncService = context.read<SyncService>();
    final pendingOperations = await syncService.getPendingOperations();

    if (pendingOperations.isNotEmpty && mounted) {
      _showPendingItemsWarningDialog();
    } else {
      _showLogoutConfirmationDialog();
    }
  }

  Future<void> _performLogout() async {
    final authRepository = context.read<AuthRepository>();
    await authRepository.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
      );
    }
  }

  void _showPendingItemsWarningDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('home.logout.pending_title'.tr()),
        content: Text('home.logout.pending_message'.tr()),
        actions: [
          TextButton(
            child: Text('dialog.ok'.tr()),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('home.logout.title'.tr()),
          content: Text('home.logout.confirmation'.tr()),
          actions: <Widget>[
            TextButton(
              child: Text('dialog.cancel'.tr()),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text('dialog.logout'.tr()),
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'home.title'.tr(),
        showBackButton: false,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            tooltip: 'home.logout.title'.tr(),
            onPressed: _handleLogoutAttempt,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final double verticalPadding = constraints.maxHeight * 0.03;
        final double horizontalPadding = constraints.maxWidth * 0.05;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding,
            horizontal: horizontalPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWelcomeCard(),
              const SizedBox(height: 24),
              _HomeButton(
                icon: Icons.input_outlined,
                label: 'home.goods_receiving'.tr(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GoodsReceivingOptionsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _HomeButton(
                icon: Icons.warehouse_outlined,
                label: 'home.pallet_transfer'.tr(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TransferTypeSelectionScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _HomeButton(
                icon: Icons.sync_alt,
                label: 'home.pending_operations'.tr(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PendingOperationsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildWelcomeCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary,
              child: Icon(
                Icons.person_outline,
                size: 28,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'home.welcome'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.textTheme.bodySmall?.color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _userName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      icon: Icon(icon, size: 32),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
      ),
    );
  }
}
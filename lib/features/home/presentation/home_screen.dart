import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/populate_offline_test_data.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnected = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _listenConnectivityChanges();
  }

  Future<void> _checkInitialConnectivity() async {
    final networkInfo = Provider.of<NetworkInfo>(context, listen: false);
    final isConnected = await networkInfo.isConnected;
    if (mounted) {
      setState(() {
        _isConnected = isConnected;
      });
    }
  }

  void _listenConnectivityChanges() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((connectivityResult) {
      final isConnected = !(connectivityResult.contains(ConnectivityResult.none));
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bool isDebug = kDebugMode;

    return Scaffold(
      appBar: AppBar(
        title: Text('home.title'.tr()),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: Icon(
              _isConnected ? Icons.wifi : Icons.wifi_off,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isDebug) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: Text('home.reset_db'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  // Provider'dan DatabaseHelper'ı alıp kullanıyoruz.
                  await context.read<DatabaseHelper>().resetDatabase();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('home.db_reset_complete'.tr())),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.bug_report, color: Colors.deepPurple),
                label: Text('home.populate_test'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow[100],
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  await populateTestData();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('home.test_data_populated'.tr())),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
            _HomeButton(
              icon: Icons.input_outlined,
              label: 'home.goods_receiving'.tr(),
              onTap: () {
                // Provider artık main.dart'da olduğu için burada tekrar oluşturmaya gerek yok.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GoodsReceivingScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _HomeButton(
              icon: Icons.warehouse_outlined,
              label: 'home.pallet_transfer'.tr(),
              onTap: () {
                // Provider artık main.dart'da olduğu için burada tekrar oluşturmaya gerek yok.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PalletAssignmentScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (_) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text('language.turkish'.tr()),
                  onTap: () {
                    context.setLocale(const Locale('tr'));
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text('language.english'.tr()),
                  onTap: () {
                    context.setLocale(const Locale('en'));
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.language),
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
    return SizedBox(
      height: 120,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 44),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          textStyle: const TextStyle(fontSize: 17),
        ),
      ),
    );
  }
}

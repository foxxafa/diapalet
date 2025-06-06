import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/local/populate_offline_test_data.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_composite_repository.dart';
import 'package:diapalet/features/goods_receiving/data/local/goods_receiving_local_service.dart';
import 'package:diapalet/features/goods_receiving/data/remote/goods_receiving_api_service.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';

import 'package:diapalet/features/pallet_assignment/presentation/pallet_assignment_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const bool isDebug = kDebugMode; // LINT FIX: prefer_const_declarations

    return Scaffold(
      appBar: AppBar(
        title: Text('home.title'.tr()),
        centerTitle: true,
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
                  await DatabaseHelper().resetDatabase();
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<GoodsReceivingRepository>(
                      create: (_) => GoodsReceivingRepositoryImpl(
                        localDataSource: GoodsReceivingLocalDataSourceImpl(dbHelper: DatabaseHelper()),
                        remoteDataSource: GoodsReceivingRemoteDataSourceImpl(),
                        networkInfo: NetworkInfoImpl(Connectivity()),
                      ),
                      child: const GoodsReceivingScreen(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _HomeButton(
              icon: Icons.warehouse_outlined,
              label: 'home.pallet_transfer'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Provider<PalletAssignmentRepository>(
                      create: (_) => PalletAssignmentRepositoryImpl(
                        localDataSource: PalletAssignmentLocalDataSourceImpl(dbHelper: DatabaseHelper()),
                        remoteDataSource: PalletAssignmentRemoteDataSourceImpl(),
                        networkInfo: NetworkInfoImpl(Connectivity()),
                      ),
                      child: const PalletAssignmentScreen(),
                    ),
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

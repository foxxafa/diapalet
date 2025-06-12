import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';

import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/home/presentation/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // --- Singleton BINDINGS ---
  final dbHelper = DatabaseHelper.instance;
  final dio = Dio();
  final connectivity = Connectivity();
  final networkInfo = NetworkInfoImpl(connectivity);
  final syncService = SyncService(
    dio: dio,
    dbHelper: dbHelper,
    connectivity: connectivity,
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('tr')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: MultiProvider(
        providers: [
          // --- CORE SERVICES ---
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<Dio>.value(value: dio),
          Provider<Connectivity>.value(value: connectivity),
          Provider<NetworkInfo>.value(value: networkInfo),
          Provider<SyncService>.value(value: syncService),

          // --- REPOSITORIES ---
          // Goods Receiving
          Provider<GoodsReceivingRepository>(
            create: (_) => GoodsReceivingRepositoryImpl(dbHelper: dbHelper),
          ),
          // Inventory Transfer
          Provider<InventoryTransferRepository>(
            create: (_) => InventoryTransferRepositoryImpl(dbHelper: dbHelper),
          ),
        ],
        child: const DiapaletApp(),
      ),
    ),
  );
}

class DiapaletApp extends StatelessWidget {
  const DiapaletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diapalet',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppTheme.light,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

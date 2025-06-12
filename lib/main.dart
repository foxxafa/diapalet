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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // --- Singleton BINDINGS ---
  final dbHelper = DatabaseHelper();
  await dbHelper.initDatabase(); // Veritabanını başlat

  final dio = Dio();
  final connectivity = Connectivity();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('tr')],
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      child: MultiProvider(
        providers: [
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<Dio>.value(value: dio),
          Provider<Connectivity>.value(value: connectivity),
          ProxyProvider<Connectivity, NetworkInfo>(
            update: (_, connectivity, __) => NetworkInfoImpl(connectivity),
          ),
          ProxyProvider<DatabaseHelper, GoodsReceivingRepository>(
            update: (_, db, __) => GoodsReceivingRepositoryImpl(dbHelper: db),
          ),
          ProxyProvider<DatabaseHelper, InventoryTransferRepository>(
            update: (_, db, __) =>
                InventoryTransferRepositoryImpl(dbHelper: db),
          ),
          ProxyProvider2<NetworkInfo, DatabaseHelper, SyncService>(
            update: (context, networkInfo, db, __) => SyncService(
              dbHelper: db,
              dio: Provider.of<Dio>(context, listen: false),
              connectivity: Provider.of<Connectivity>(context, listen: false),
            ),
          ),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'DiaPalet',
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

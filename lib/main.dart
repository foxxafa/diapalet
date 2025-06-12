import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import 'package:diapalet/core/local/database_helper.dart';
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

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('tr'), Locale('en')],
      path: 'assets/lang',
      fallbackLocale: const Locale('tr'),
      startLocale: const Locale('tr'),
      child: const DiapaletApp(),
    ),
  );
}

class DiapaletApp extends StatelessWidget {
  const DiapaletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // CORE SERVICES
        // These are low-level services that don't depend on other providers.
        Provider<DatabaseHelper>(
          create: (_) => DatabaseHelper.instance, // Use singleton instance
        ),
        Provider<Dio>(
          create: (_) => Dio(), // Create a single Dio instance
        ),
        Provider<Connectivity>(
          create: (_) => Connectivity(),
        ),

        // DEPENDENT SERVICES (using ProxyProvider)
        // These services depend on the core services above.
        ProxyProvider3<Dio, DatabaseHelper, Connectivity, SyncService>(
          update: (_, dio, dbHelper, connectivity, __) => SyncService(
            dio: dio,
            dbHelper: dbHelper,
            connectivity: connectivity,
          ),
        ),

        // REPOSITORIES
        // Repositories depend on core services like DatabaseHelper.
        ProxyProvider<DatabaseHelper, GoodsReceivingRepository>(
          update: (_, dbHelper, __) => GoodsReceivingRepositoryImpl(
            dbHelper: dbHelper,
          ),
        ),
        ProxyProvider<DatabaseHelper, InventoryTransferRepository>(
          update: (_, dbHelper, __) => InventoryTransferRepositoryImpl(
            dbHelper: dbHelper,
          ),
        ),
      ],
      child: MaterialApp(
        title: tr('app.title'),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: const HomeScreen(),
      ),
    );
  }
}

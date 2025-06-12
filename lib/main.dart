import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/home/presentation/home_screen.dart';
import 'package:diapalet/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // --- Bağımsız Singleton Servisler ---
  final dbHelper = DatabaseHelper.instance;
  await dbHelper.database;
  final dio = Dio();
  final connectivity = Connectivity();
  final networkInfo = NetworkInfoImpl(connectivity);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('tr'), Locale('en')],
      path: 'assets/lang',
      fallbackLocale: const Locale('tr'),
      child: MultiProvider(
        providers: [
          // Temel, diğerleri tarafından kullanılacak servisleri sağla.
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<Dio>.value(value: dio),
          Provider<NetworkInfo>.value(value: networkInfo),

          // Repository'ler: Diğer servislere bağımlı.
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio,
              GoodsReceivingRepository>(
            update: (_, db, network, dio, __) => GoodsReceivingRepositoryImpl(
              dbHelper: db,
              networkInfo: network,
              dio: dio,
            ),
          ),

          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio,
              InventoryTransferRepository>(
            update: (_, db, network, dio, __) =>
                InventoryTransferRepositoryImpl(
                  dbHelper: db,
                  networkInfo: network,

                  dio: dio,
                ),
          ),

          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, SyncService>(
            update: (_, db, network, dio, __) => SyncService(
              dbHelper: db,
              dio: dio,
              networkInfo: network,
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
      themeMode: ThemeMode.light,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

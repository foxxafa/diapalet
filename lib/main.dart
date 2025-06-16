import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/core/theme/theme_provider.dart';
import 'package:diapalet/features/auth/data/repositories/auth_repository_impl.dart'; // YENİ
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart'; // YENİ
import 'package:diapalet/features/auth/presentation/login_screen.dart'; // YENİ
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
// import 'package:diapalet/features/home/presentation/home_screen.dart'; // ARTIK BAŞLANGIÇ DEĞİL
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
  await dbHelper.database; // Veritabanının başlatıldığından emin ol
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

          ChangeNotifierProvider(create: (_) => ThemeProvider()),

          // Repository'ler: Diğer servislere bağımlı.
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, GoodsReceivingRepository>(
            update: (_, db, network, dio, __) => GoodsReceivingRepositoryImpl(
              dbHelper: db,
              networkInfo: network,
              dio: dio,
            ),
          ),
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, InventoryTransferRepository>(
            update: (_, db, network, dio, __) => InventoryTransferRepositoryImpl(
              dbHelper: db,
              networkInfo: network,
              dio: dio,
            ),
          ),

          // YENİ AuthRepository provider'ı eklendi.
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, AuthRepository>(
            update: (_, db, network, dio, __) => AuthRepositoryImpl(
              dbHelper: db,
              networkInfo: network,
              dio: dio,
            ),
          ),

          // SyncService'i bir ChangeNotifier olarak sağla.
          ChangeNotifierProxyProvider3<DatabaseHelper, NetworkInfo, Dio, SyncService>(
            create: (context) => SyncService(
              dbHelper: context.read<DatabaseHelper>(),
              dio: context.read<Dio>(),
              networkInfo: context.read<NetworkInfo>(),
            ),
            update: (_, db, network, dio, previous) {
              return previous!..updateDependencies(db, dio, network);
            },
          ),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MyApp(themeProvider: themeProvider);
          },
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  const MyApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'DiaPalet',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      // DEĞİŞİKLİK: Uygulama artık LoginScreen ile başlıyor.
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

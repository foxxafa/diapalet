// main.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/core/theme/theme_provider.dart';
import 'package:diapalet/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:diapalet/features/auth/presentation/login_screen.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/home/presentation/home_screen.dart';
import 'package:diapalet/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diapalet/features/auth/presentation/splash_screen.dart';

Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 15000),
      receiveTimeout: const Duration(milliseconds: 15000),
      headers: { 'Accept': 'application/json', },
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (object) => debugPrint(object.toString()),
    ));
  }
  return dio;
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final dbHelper = DatabaseHelper.instance;
  await dbHelper.database;

  final dio = createDioClient();
  final connectivity = Connectivity();
  final networkInfo = NetworkInfoImpl(connectivity);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('tr'), Locale('en')],
      path: 'assets/lang',
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      child: MultiProvider(
        providers: [
          Provider<NetworkInfo>.value(value: networkInfo),
          Provider<Dio>.value(value: dio),
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<AuthRepository>(
            create: (context) => AuthRepositoryImpl(
              dbHelper: context.read<DatabaseHelper>(),
              networkInfo: context.read<NetworkInfo>(),
              dio: context.read<Dio>(),
            ),
          ),
          Provider<GoodsReceivingRepository>(
            create: (context) => GoodsReceivingRepositoryImpl(
              dbHelper: context.read<DatabaseHelper>(),
              networkInfo: context.read<NetworkInfo>(),
              dio: context.read<Dio>(),
            ),
          ),
          Provider<InventoryTransferRepository>(
            create: (context) => InventoryTransferRepositoryImpl(
              dbHelper: context.read<DatabaseHelper>(),
              networkInfo: context.read<NetworkInfo>(),
              dio: context.read<Dio>(),
            ),
          ),
          ChangeNotifierProvider<SyncService>(
            create: (context) => SyncService(
              dbHelper: context.read<DatabaseHelper>(),
              dio: context.read<Dio>(),
              networkInfo: context.read<NetworkInfo>(),
            ),
          ),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
          ),
        ],
        child: const MyApp(initialScreen: SplashScreen()),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'app.title'.tr(),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}
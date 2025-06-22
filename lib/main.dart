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

Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
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

  // GÜNCELLEME: Oturum kontrolü
  final prefs = await SharedPreferences.getInstance();
  final apiKey = prefs.getString('apikey');
  Widget initialScreen = const LoginScreen();

  if (apiKey != null && apiKey.isNotEmpty) {
    debugPrint("Aktif bir oturum bulundu. Ana sayfaya yönlendiriliyor.");
    // Mevcut API anahtarını uygulama başlarken Dio'ya ekle
    dio.options.headers['Authorization'] = 'Bearer $apiKey';
    initialScreen = const HomeScreen();
  } else {
    debugPrint("Aktif oturum bulunamadı. Login ekranı gösteriliyor.");
  }
  // GÜNCELLEME SONU

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('tr'), Locale('en')],
      path: 'assets/lang',
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      child: MultiProvider(
        providers: [
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<Dio>.value(value: dio),
          Provider<NetworkInfo>.value(value: networkInfo),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, AuthRepository>(
            update: (_, db, network, dio, __) => AuthRepositoryImpl(
              dbHelper: db, networkInfo: network, dio: dio,
            ),
          ),
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, GoodsReceivingRepository>(
            update: (_, db, network, dio, __) => GoodsReceivingRepositoryImpl(
              dbHelper: db, networkInfo: network, dio: dio,
            ),
          ),
          ProxyProvider3<DatabaseHelper, NetworkInfo, Dio, InventoryTransferRepository>(
            update: (_, db, network, dio, __) => InventoryTransferRepositoryImpl(
              dbHelper: db, networkInfo: network, dio: dio,
            ),
          ),
          ChangeNotifierProxyProvider3<DatabaseHelper, NetworkInfo, Dio, SyncService>(
            create: (context) => SyncService(
              dbHelper: context.read<DatabaseHelper>(),
              dio: context.read<Dio>(),
              networkInfo: context.read<NetworkInfo>(),
            ),
            update: (_, db, network, dio, previous) {
              previous!.updateDependencies(dbHelper: db, dio: dio, networkInfo: network);
              return previous;
            },
          ),
        ],
        // GÜNCELLEME: MyApp artık başlangıç ekranını dinamik olarak alıyor.
        child: MyApp(initialScreen: initialScreen),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  // GÜNCELLEME: Başlangıç ekranını parametre olarak alır.
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'DiaPalet',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      // GÜNCELLEME: `home` artık dinamik olarak belirleniyor.
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}
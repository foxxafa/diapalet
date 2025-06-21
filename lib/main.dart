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
import 'package:diapalet/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Loglama için kDebugMode
import 'package:provider/provider.dart';

// Dio istemcisini oluşturan ve loglama interceptor'ı ekleyen fonksiyon.
Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: { 'Accept': 'application/json', },
    ),
  );

  // Sadece debug modunda çalışacak olan LogInterceptor'ı ekliyoruz.
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        error: true,
        logPrint: (object) {
          // Logları debugPrint ile konsola daha okunaklı yazdır.
          debugPrint(object.toString());
        },
      ),
    );
  }

  return dio;
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final dbHelper = DatabaseHelper.instance;
  await dbHelper.database;

  // Dio istemcisi artık loglama yapabilen fonksiyonumuzdan oluşturuluyor.
  final dio = createDioClient();
  final connectivity = Connectivity();
  final networkInfo = NetworkInfoImpl(connectivity);

  runApp(
    EasyLocalization(
      // GÜNCELLEME: Dil ayarları İngilizce'ye sabitlendi.
      supportedLocales: const [Locale('tr'), Locale('en')],
      path: 'assets/lang',
      startLocale: const Locale('en'), // Uygulama İngilizce başlasın.
      fallbackLocale: const Locale('en'), // Hata durumunda İngilizce'ye dönsün.
      child: MultiProvider(
        providers: [
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<Dio>.value(value: dio), // Loglama yeteneği olan Dio nesnesi sağlanıyor.
          Provider<NetworkInfo>.value(value: networkInfo),
          // GÜNCELLEME: ThemeProvider artık state yönetimi için gerekli değil ama provider ağacında kalabilir.
          ChangeNotifierProvider(create: (_) => ThemeProvider()),

          // Repository'ler
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

          // SyncService
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
        // GÜNCELLEME: Consumer<ThemeProvider> kaldırıldı, MyApp doğrudan çağrılıyor.
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
      locale: context.locale, // EasyLocalization'dan gelen dili kullanır.
      title: 'DiaPalet',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // GÜNCELLEME: Tema modu açık temaya sabitlendi.
      themeMode: ThemeMode.light,
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
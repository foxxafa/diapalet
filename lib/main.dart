// main.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/theme/app_theme.dart';
import 'package:diapalet/core/theme/theme_provider.dart';
import 'package:diapalet/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:diapalet/features/auth/domain/repositories/auth_repository.dart';
import 'package:diapalet/features/auth/presentation/login_screen.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_view_model.dart';
import 'package:diapalet/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
// DÜZELTME: InventoryTransferViewModel artık global olarak sağlanmıyor.
// import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_view_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
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
      startLocale: const Locale('en'), // App starts in English by default
      fallbackLocale: const Locale('en'),
      child: MultiProvider(
        providers: [
          // Temel servisler
          Provider<NetworkInfo>.value(value: networkInfo),
          Provider<Dio>.value(value: dio),
          Provider<DatabaseHelper>.value(value: dbHelper),
          Provider<BarcodeIntentService>(create: (_) => BarcodeIntentService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),

          // SyncService
          ChangeNotifierProvider<SyncService>(
            create: (context) => SyncService(
              dbHelper: context.read<DatabaseHelper>(),
              dio: context.read<Dio>(),
              networkInfo: context.read<NetworkInfo>(),
            ),
          ),

          // Repositories
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
              syncService: context.read<SyncService>(),
            ),
          ),
          Provider<InventoryTransferRepository>(
            create: (context) => InventoryTransferRepositoryImpl(
              dbHelper: context.read<DatabaseHelper>(),
              networkInfo: context.read<NetworkInfo>(),
              dio: context.read<Dio>(),
              syncService: context.read<SyncService>(),
            ),
          ),

          // View modeller (Artık sadece ihtiyaç duyulanlar global)
          ChangeNotifierProvider(
            create: (context) => GoodsReceivingViewModel(
              repository: context.read<GoodsReceivingRepository>(),
              syncService: context.read<SyncService>(),
              barcodeService: context.read<BarcodeIntentService>(),
            ),
          ),
          // DÜZELTME: InventoryTransferViewModel buradan kaldırıldı.
          // İlgili ekran kendi Provider'ını oluşturacak.
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
      locale: context.locale, // DÜZELTME: EasyLocalization'dan gelen locale kullanılıyor.
      title: 'app.title'.tr(),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
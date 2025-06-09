import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_composite_repository.dart';
import 'package:diapalet/features/goods_receiving/data/local/goods_receiving_local_service.dart';
import 'package:diapalet/features/goods_receiving/data/remote/goods_receiving_api_service.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart';
import 'package:diapalet/features/pallet_assignment/data/repositories/pallet_assignment_repository_impl.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/home_screen.dart';

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
    // Uygulama genelinde kullanılacak servisleri ve repository'leri tek bir yerden sağlıyoruz.
    // Bu, her ekranda yeniden oluşturmayı engeller ve performansı artırır.
    return MultiProvider(
      providers: [
        // Temel servisler
        Provider<DatabaseHelper>(
          create: (_) => DatabaseHelper(),
        ),
        Provider<NetworkInfo>(
          create: (_) => NetworkInfoImpl(Connectivity()),
        ),
        
        // Sync Service
        Provider<SyncService>(
          create: (_) => SyncService(),
        ),

        // Veri Kaynakları (DataSources)
        ProxyProvider<DatabaseHelper, GoodsReceivingLocalDataSource>(
          update: (_, dbHelper, __) => GoodsReceivingLocalDataSourceImpl(dbHelper: dbHelper),
        ),
        Provider<GoodsReceivingRemoteDataSource>(
          create: (_) => GoodsReceivingRemoteDataSourceImpl(),
        ),
        ProxyProvider<DatabaseHelper, PalletAssignmentLocalDataSource>(
          update: (_, dbHelper, __) => PalletAssignmentLocalDataSourceImpl(dbHelper: dbHelper),
        ),
        Provider<PalletAssignmentRemoteDataSource>(
          create: (_) => PalletAssignmentRemoteDataSourceImpl(),
        ),

        // Depolar (Repositories)
        ProxyProvider3<GoodsReceivingLocalDataSource, GoodsReceivingRemoteDataSource, NetworkInfo, GoodsReceivingRepository>(
          update: (_, local, remote, network, __) => GoodsReceivingRepositoryImpl(
            localDataSource: local,
            remoteDataSource: remote,
            networkInfo: network,
          ),
        ),
        ProxyProvider3<PalletAssignmentLocalDataSource, PalletAssignmentRemoteDataSource, NetworkInfo, PalletAssignmentRepository>(
          update: (_, local, remote, network, __) => PalletAssignmentRepositoryImpl(
            localDataSource: local,
            remoteDataSource: remote,
            networkInfo: network,
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

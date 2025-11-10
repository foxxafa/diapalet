// lib/core/services/app_version_service.dart

import 'package:package_info_plus/package_info_plus.dart';

/// Singleton servis: Uygulama sürüm bilgilerini yönetir
///
/// pubspec.yaml'daki version bilgisini okur ve uygulama genelinde kullanıma sunar
///
/// Kullanım:
/// ```dart
/// final version = await AppVersionService.instance.getVersion();
/// final fullVersion = await AppVersionService.instance.getFullVersion();
/// ```
class AppVersionService {
  static final AppVersionService _instance = AppVersionService._internal();
  static AppVersionService get instance => _instance;

  AppVersionService._internal();

  PackageInfo? _packageInfo;

  /// PackageInfo'yu initialize et (ilk çağrıda)
  Future<PackageInfo> _getPackageInfo() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  /// Sadece version numarasını al (örn: "1.0.0")
  Future<String> getVersion() async {
    final info = await _getPackageInfo();
    return info.version;
  }

  /// Build numarası ile birlikte version al (örn: "1.0.0+3")
  Future<String> getFullVersion() async {
    final info = await _getPackageInfo();
    return '${info.version}+${info.buildNumber}';
  }

  /// Version'ı basit formatta al (örn: "1.0.629")
  Future<String> getVersionForDisplay() async {
    final info = await _getPackageInfo();
    return info.version;
  }

  /// Version ve build numarasını parantez içinde al (örn: "1.0.629 (629)")
  Future<String> getVersionWithBuildNumber() async {
    final info = await _getPackageInfo();
    return '${info.version} (${info.buildNumber})';
  }

  /// Uygulama adını al
  Future<String> getAppName() async {
    final info = await _getPackageInfo();
    return info.appName;
  }

  /// Package name'i al
  Future<String> getPackageName() async {
    final info = await _getPackageInfo();
    return info.packageName;
  }
}
#!/usr/bin/env dart
// scripts/switch_environment.dart
// Kullanım: dart scripts/switch_environment.dart [local|staging|production]

import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Kullanım: dart scripts/switch_environment.dart [local|staging|production]');
    print('');
    print('Mevcut ortamlar:');
    print('  local      - Docker container (localhost:8080)');
    print('  staging    - Railway staging ortamı (Test)');
    print('  production - Railway production ortamı (Canlı)');
    exit(1);
  }

  final environment = args[0].toLowerCase();
  final validEnvironments = ['local', 'staging', 'production'];

  if (!validEnvironments.contains(environment)) {
    print('Geçersiz ortam: $environment');
    print('Geçerli ortamlar: ${validEnvironments.join(', ')}');
    exit(1);
  }

  final apiConfigPath = 'lib/core/network/api_config.dart';
  final file = File(apiConfigPath);

  if (!file.existsSync()) {
    print('Hata: $apiConfigPath dosyası bulunamadı');
    exit(1);
  }

  var content = file.readAsStringSync();

  // Mevcut ortam satırını bul ve değiştir
  final pattern = RegExp(r'static const ApiEnvironment currentEnvironment = ApiEnvironment\.\w+;');
  final newLine = 'static const ApiEnvironment currentEnvironment = ApiEnvironment.$environment;';

  if (pattern.hasMatch(content)) {
    content = content.replaceFirst(pattern, newLine);
    file.writeAsStringSync(content);
    print('✅ Ortam başarıyla değiştirildi: $environment');
    print('📱 Uygulamayı yeniden başlatmayı unutmayın!');
  } else {
    print('❌ Hata: currentEnvironment satırı bulunamadı');
    exit(1);
  }
}
#!/usr/bin/env dart
// scripts/check_environments.dart
// Tüm ortamların durumunu kontrol eder

import 'dart:io';
import 'dart:convert';

void main() async {
  print('========================================');
  print('   DIAPALET - ENVIRONMENT STATUS');
  print('========================================');
  print('');

  final environments = {
    'Local (Docker)': 'http://localhost:8080/health-check',
    'Staging Railway': 'https://diapalet-staging.up.railway.app/health-check',
    'Production Railway': 'https://diapalet-production.up.railway.app/health-check',
  };

  for (final env in environments.entries) {
    await checkEnvironment(env.key, env.value);
  }

  print('');
  print('✅ Kontrol tamamlandı!');
}

Future<void> checkEnvironment(String name, String url) async {
  try {
    print('🔍 $name kontrol ediliyor...');

    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: 10);

    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      print('   ✅ $name - ONLINE (${response.statusCode})');

      try {
        final data = jsonDecode(body);
        if (data['status'] == 'ok') {
          print('   📊 Health check: OK');
        }
      } catch (e) {
        // JSON parse hatası, önemli değil
      }
    } else {
      print('   ⚠️  $name - HTTP ${response.statusCode}');
    }

    client.close();
  } catch (e) {
    print('   ❌ $name - OFFLINE ($e)');
  }

  print('');
}
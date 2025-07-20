# Diapalet Ortam Yönetimi

## Ortam Yapısı

Diapalet uygulaması üç farklı ortamda çalışabilir:

1. **Local (Docker)**: Geliştirme ortamı, bilgisayarınızdaki Docker container'da çalışır
2. **Staging**: Test ortamı, Railway'de çalışır, test ve demo amaçlıdır
3. **Production**: Canlı ortam, Railway'de çalışır, son kullanıcılar tarafından kullanılır

## Ortam Değiştirme

Ortamlar arasında geçiş yapmak için:

```bash
# Manuel ortam değiştirme
dart scripts/switch_environment.dart [local|staging|production]

# Örnek:
dart scripts/switch_environment.dart staging
```

## API Endpoint URL'leri

Her ortam kendi API endpoint'ine sahiptir:

- **Local**: http://10.0.2.2:8080 (Android Emulator için)
- **Staging**: https://staging-api.diapalet.com
- **Production**: https://api.diapalet.com

## Ortam Durumu Kontrol

Tüm ortamların durumunu kontrol etmek için:

```bash
dart scripts/check_environments.dart
```

## Deployment

### Staging Ortamına Deploy

```bash
scripts\deploy_staging.bat
```

### Production Ortamına Deploy

```bash
scripts\deploy_production.bat
```

## APK Build

### Staging APK

```bash
scripts\build_staging.bat
```

### Production APK

```bash
scripts\build_production.bat
```

## Ortam Göstergesi

Uygulamada hangi ortamda çalıştığınızı görmek için `EnvironmentBadge` widget'ını kullanabilirsiniz:

```dart
// Örnek kullanım
Scaffold(
  appBar: AppBar(
    title: Text('Diapalet'),
    actions: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: EnvironmentBadge(),
      ),
    ],
  ),
  body: ...
)
```

## Ortam Değişkenlerini Kullanma

Ortama göre farklı davranışlar sergilemek için:

```dart
if (ApiConfig.isLocal) {
  // Sadece local ortamda çalışacak kod
}

if (ApiConfig.isStaging) {
  // Sadece staging ortamında çalışacak kod
}

if (ApiConfig.isProduction) {
  // Sadece production ortamında çalışacak kod
}
```

## Ortam Bilgisini Görüntüleme

```dart
// Ortam adını al
final envName = ApiConfig.environmentName; // "Local", "Staging" veya "Production"

// Ortam açıklamasını al
final envDesc = ApiConfig.environmentDescription;

// API URL'sini al
final apiUrl = ApiConfig.baseUrl;
```
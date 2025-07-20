# Railway Custom Domain Kurulumu

## 1. Domain Satın Alma
- `diapalet.com` domain'ini satın alın (GoDaddy, Namecheap, vs.)

## 2. Railway'de Custom Domain Ekleme

### Production Ortamı için:
1. Railway Dashboard → Production Environment
2. Settings → Domains
3. "Custom Domain" butonuna tıklayın
4. Domain: `api.diapalet.com` girin
5. "Add Domain" tıklayın

### Staging Ortamı için:
1. Railway Dashboard → Staging Environment
2. Settings → Domains
3. "Custom Domain" butonuna tıklayın
4. Domain: `staging-api.diapalet.com` girin
5. "Add Domain" tıklayın

## 3. DNS Ayarları

Domain sağlayıcınızda (GoDaddy, Namecheap, vs.) şu DNS kayıtlarını ekleyin:

### A Records:
```
api.diapalet.com → Railway IP (Railway'den alacağınız IP)
staging-api.diapalet.com → Railway IP (Railway'den alacağınız IP)
```

### CNAME Records (Alternatif):
```
api.diapalet.com → diapalet-production.up.railway.app
staging-api.diapalet.com → diapalet-staging.up.railway.app
```

## 4. SSL Sertifikası
Railway otomatik olarak Let's Encrypt SSL sertifikası sağlar.

## 5. Doğrulama
```bash
# Domain'lerin çalışıp çalışmadığını kontrol edin
curl https://api.diapalet.com/health-check
curl https://staging-api.diapalet.com/health-check
```

## 6. Flutter Uygulamasını Güncelleme
Domain'ler aktif olduktan sonra:
```bash
# Ortam durumunu kontrol et
dart scripts/check_environments.dart

# Staging'e geç ve test et
dart scripts/switch_environment.dart staging
flutter run
```

## Geçici Çözüm
Custom domain ayarlanana kadar Railway URL'lerini kullanabilirsiniz:

`lib/core/network/api_environments.dart` dosyasında:
```dart
// Geçici Railway URL'leri kullan
static const String _stagingBaseUrl = 'https://diapalet-staging.up.railway.app';
static const String _productionBaseUrl = 'https://diapalet-production.up.railway.app';
```
# Diapalet - Tam Kurulum ve Kullanım Rehberi

## 🚀 Hızlı Başlangıç

### 1. Railway Ortamlarını Hazırlama

#### A. Staging Ortamı Kurulumu

```bash
# 1. Staging ortamına geç
railway environment staging

# 2. Staging veritabanını kur
scripts\setup_staging_db.bat

# 3. Staging'e deploy et
scripts\deploy_staging.bat
```

#### B. Production Ortamı Kurulumu

```bash
# 1. Production ortamına geç
railway environment production

# 2. Production veritabanını kur (dikkatli!)
scripts\setup_production_db.bat

# 3. Production'a deploy et (dikkatli!)
scripts\deploy_production.bat
```

### 2. Veritabanı Kurulum Detayları

#### Railway MySQL'e Bağlanma ve Veri Yükleme

1. **Staging Veritabanı Kurulumu**:
   ```bash
   # Staging ortamına geç
   railway environment staging

   # MySQL konsolunu aç
   railway connect mysql
   ```

2. **MySQL Konsolunda Çalıştır**:
   ```sql
   -- Mevcut tabloları temizle (isteğe bağlı)
   source scripts/mysql_import.sql;

   -- Ana veritabanı kurulumunu çalıştır
   source backend/complete_setup.sql;

   -- Kurulumu kontrol et
   SHOW TABLES;
   SELECT COUNT(*) FROM employees;
   SELECT COUNT(*) FROM urunler;
   SELECT * FROM warehouses;
   ```

3. **Veritabanı Durumunu Kontrol Et**:
   ```bash
   scripts\check_db_status.bat
   ```

### 3. Flutter Uygulaması Geliştirme Workflow'u

#### Geliştirme Yaparken (Local)

```bash
# 1. Local ortamına geç
dart scripts/switch_environment.dart local

# 2. Docker container'ı başlat
scripts\dev_start.bat

# 3. Flutter uygulamasını çalıştır
flutter run
```

#### Test İçin (Staging)

```bash
# 1. Staging ortamına geç
dart scripts/switch_environment.dart staging

# 2. Staging APK build et
scripts\build_staging.bat

# 3. Test et
flutter run
```

#### Canlıya Çıkarken (Production)

```bash
# 1. Production ortamına geç
dart scripts/switch_environment.dart production

# 2. Production APK build et
scripts\build_production.bat

# 3. Test et
flutter run
```

### 4. Ortam Durumu Kontrolü

```bash
# Tüm ortamların durumunu kontrol et
dart scripts/check_environments.dart

# Veritabanı durumunu kontrol et
scripts\check_db_status.bat
```

## 📊 Railway Ortam Yapısı

### Staging Ortamı
- **URL**: https://diapalet-staging.up.railway.app
- **Amaç**: Test ve geliştirme
- **Veritabanı**: Ayrı MySQL instance
- **Veriler**: Test verileri

### Production Ortamı
- **URL**: https://diapalet-production.up.railway.app
- **Amaç**: Canlı sistem
- **Veritabanı**: Ayrı MySQL instance
- **Veriler**: Gerçek veriler

## 🔧 Sorun Giderme

### Veritabanı Bağlantı Sorunları

1. **Railway MySQL Servisini Kontrol Et**:
   ```bash
   railway status
   ```

2. **Environment Variables Kontrol Et**:
   - Railway Dashboard → Environment → Variables
   - `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` değerlerini kontrol et

3. **Backend Logs Kontrol Et**:
   ```bash
   railway logs
   ```

### API Bağlantı Sorunları

1. **Health Check Yap**:
   ```bash
   curl https://diapalet-staging.up.railway.app/health-check
   curl https://diapalet-production.up.railway.app/health-check
   ```

2. **Flutter Uygulamasında Ortam Kontrol Et**:
   ```dart
   print('Current Environment: ${ApiConfig.environmentName}');
   print('API URL: ${ApiConfig.baseUrl}');
   ```

### Deployment Sorunları

1. **Railway CLI Güncel Mi Kontrol Et**:
   ```bash
   railway --version
   ```

2. **Railway'e Login Ol**:
   ```bash
   railway login
   ```

3. **Proje Bağlantısını Kontrol Et**:
   ```bash
   railway status
   ```

## 📱 APK Build ve Test

### Staging APK
```bash
# Staging APK build et
scripts\build_staging.bat

# APK konumu: build\app\outputs\flutter-apk\app-release.apk
```

### Production APK
```bash
# Production APK build et (dikkatli!)
scripts\build_production.bat

# APK konumu: build\app\outputs\flutter-apk\app-release.apk
```

## 🎯 Kullanım Senaryoları

### Senaryo 1: Yeni Özellik Geliştirme
1. Local ortamda geliştir (`dart scripts/switch_environment.dart local`)
2. Staging'e deploy et (`scripts\deploy_staging.bat`)
3. Staging APK ile test et (`scripts\build_staging.bat`)
4. Production'a deploy et (`scripts\deploy_production.bat`)

### Senaryo 2: Hızlı Test
1. Staging ortamına geç (`dart scripts/switch_environment.dart staging`)
2. Flutter run ile test et (`flutter run`)

### Senaryo 3: Canlı Deployment
1. Production ortamına geç (`dart scripts/switch_environment.dart production`)
2. Production APK build et (`scripts\build_production.bat`)
3. APK'yı dağıt

## 📋 Kontrol Listesi

### İlk Kurulum
- [ ] Railway CLI kurulu
- [ ] Railway'e login yapıldı
- [ ] Staging ortamı oluşturuldu
- [ ] Production ortamı oluşturuldu
- [ ] Staging veritabanı kuruldu
- [ ] Production veritabanı kuruldu
- [ ] Health check'ler başarılı

### Her Deployment Öncesi
- [ ] Ortam durumu kontrol edildi (`dart scripts/check_environments.dart`)
- [ ] Veritabanı durumu kontrol edildi (`scripts\check_db_status.bat`)
- [ ] Doğru ortam seçildi
- [ ] Test edildi

Bu rehber ile Diapalet uygulamanızı profesyonel bir şekilde yönetebilir, geliştirme ve canlı ortamları arasında güvenle geçiş yapabilirsiniz.
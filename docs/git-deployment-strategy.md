# Git Branch ve Railway Deployment Stratejisi

## Branch Yapısı

```
main (production)     ← Canlı sistem
├── staging           ← Test ortamı
└── feature/xyz       ← Geliştirme dalları
```

## Railway Deployment Ayarları

### Staging Ortamı
- **Branch**: `staging`
- **Auto Deploy**: ✅ Enabled
- **Trigger**: Her `staging` branch'ine push'da otomatik deploy

### Production Ortamı
- **Branch**: `main`
- **Auto Deploy**: ❌ Manual (güvenlik için)
- **Trigger**: Manuel deployment veya PR merge sonrası

## Workflow

### 1. Yeni Özellik Geliştirme
```bash
# Feature branch oluştur
git checkout -b feature/new-feature

# Geliştirme yap
# ... kod değişiklikleri ...

# Staging'e merge et
git checkout staging
git merge feature/new-feature
git push origin staging
# ↑ Bu otomatik olarak staging ortamına deploy eder
```

### 2. Staging'de Test
```bash
# Flutter uygulamasını staging'e ayarla
dart scripts/switch_environment.dart staging

# Test et
flutter run
# veya
scripts\build_staging.bat
```

### 3. Production'a Çıkarma
```bash
# Staging'den main'e merge et
git checkout main
git merge staging
git push origin main

# Manuel production deployment
scripts\deploy_production.bat
# veya
railway environment production
railway up
```

## Railway Dashboard Ayarları

### Staging Ortamı İçin:
1. Railway Dashboard → Staging Environment
2. Service Settings → Source
3. Branch: `staging` seç
4. Auto Deploy: Enable
5. Deploy Trigger: `On Push`

### Production Ortamı İçin:
1. Railway Dashboard → Production Environment
2. Service Settings → Source
3. Branch: `main` seç
4. Auto Deploy: Disable (manuel kontrol için)
5. Deploy Trigger: `Manual`
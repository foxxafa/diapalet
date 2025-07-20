# Railway Otomatik Deployment Kurulumu

## 1. Staging Ortamı - Otomatik Deployment

### Railway Dashboard'da:
1. **Staging Environment'ı seç**
2. **Service'i seç** (diapalet)
3. **Settings → Source** sekmesine git
4. **Branch**: `staging` seç
5. **Auto Deploy**: ✅ Enable
6. **Deploy on**: `Push to branch` seç

### Sonuç:
- `staging` branch'ine her push'da otomatik deploy olur
- Geliştirme yaparken sadece `git push origin staging` yeterli

## 2. Production Ortamı - Manuel Deployment

### Railway Dashboard'da:
1. **Production Environment'ı seç**
2. **Service'i seç** (diapalet)
3. **Settings → Source** sekmesine git
4. **Branch**: `main` seç
5. **Auto Deploy**: ❌ Disable
6. **Deploy on**: `Manual` seç

### Sonuç:
- `main` branch'ine push otomatik deploy etmez
- Manuel olarak deploy etmeniz gerekir
- Güvenlik için önemli

## 3. Git Branch Oluşturma

```bash
# Staging branch oluştur (henüz yoksa)
git checkout -b staging
git push -u origin staging

# Main branch'i güncelle
git checkout main
git push -u origin main
```

## 4. Workflow Test

### Staging Test:
```bash
# Staging'e geç
git checkout staging

# Küçük bir değişiklik yap
echo "// Test comment" >> README.md

# Push et
git add .
git commit -m "Test staging auto deploy"
git push origin staging

# Railway'de otomatik deploy başlamalı
```

### Production Test:
```bash
# Main'e geç
git checkout main
git merge staging
git push origin main

# Manuel deploy et
railway environment production
railway up
```

## 5. Deployment Status Kontrolü

```bash
# Railway deployment durumunu kontrol et
railway logs

# Service durumunu kontrol et
railway status

# API durumunu kontrol et
dart scripts/check_environments.dart
```
# 🚀 DIAPALET - BASİT KULLANIM REHBERİ

## 📁 Scripts Klasör Yapısı

```
scripts/
├── staging/          # Test ortamı için
│   ├── build.bat     # Staging APK build et
│   ├── deploy.bat    # Staging'e manuel deploy
│   └── setup_db.bat  # Staging veritabanı kur
├── production/       # Canlı ortam için
│   ├── build.bat     # Production APK build et
│   ├── deploy.bat    # Production'a deploy et
│   └── setup_db.bat  # Production veritabanı kur
├── development/      # Geliştirme için
│   └── start.bat     # Local Docker başlat
└── utils/           # Yardımcı araçlar
    ├── switch_environment.dart    # Ortam değiştir
    ├── check_environments.dart    # Ortam durumu kontrol
    ├── dev_workflow.bat          # Geliştirme workflow'u
    └── check_db_status.bat       # Veritabanı durumu
```

## 🎯 **İLK KURULUM (Sadece 1 Kez)**

### 1. Veritabanlarını Kur

```bash
# Staging veritabanını kur (Web dashboard açılır)
scripts\staging\setup_db.bat

# Production veritabanını kur (dikkatli!)
scripts\production\setup_db.bat
```

**Not**: Script çalıştırınca Railway web dashboard açılır, oradan SQL çalıştırabilirsiniz.

### 2. Railway Branch Ayarları
- Railway Dashboard → Staging Environment → Settings → Source → Branch: `staging`
- Railway Dashboard → Production Environment → Settings → Source → Branch: `main`

## 🔄 **GÜNLÜK KULLANIM**

### **Geliştirme Yaparken:**

#### Yöntem 1: Otomatik (Önerilen)
```bash
# 1. Staging dalına geç
git checkout staging

# 2. Flutter'ı staging'e ayarla
dart scripts\utils\switch_environment.dart staging

# 3. Kod yaz, değişiklik yap

# 4. GitHub'a gönder (otomatik deploy olur!)
git add .
git commit -m "Yeni özellik"
git push origin staging
```

#### Yöntem 2: Manuel
```bash
# Staging'e manuel deploy
scripts\staging\deploy.bat
```

### **Test Etmek İçin:**
```bash
# Staging APK build et
scripts\staging\build.bat

# Veya Flutter run
flutter run
```

### **Canlıya Çıkarmak İçin:**
```bash
# 1. Main dalına geç
git checkout main

# 2. Staging'deki değişiklikleri al
git merge staging
git push origin main

# 3. Production'a deploy et
scripts\production\deploy.bat

# 4. Production APK build et
scripts\production\build.bat
```

## 🔍 **KONTROL KOMUTLARI**

```bash
# Railway bağlantı testi
scripts\utils\test_connection.bat

# Ortam durumunu kontrol et
dart scripts\utils\check_environments.dart

# Veritabanı durumunu kontrol et (MySQL CLI gerekli)
scripts\utils\check_db_status.bat

# Hızlı workflow menüsü
scripts\utils\dev_workflow.bat
```

## ❓ **SORU-CEVAP**

### **Q: Deploy.bat neden gerekli?**
**A:**
- Staging: Otomatik deploy var ama bazen manuel gerekir
- Production: Güvenlik için sadece manuel deploy

### **Q: Hangi ortamda çalışıyorum?**
**A:**
```bash
dart scripts\utils\switch_environment.dart staging  # Test için
dart scripts\utils\switch_environment.dart production  # Canlı için
```

### **Q: .bat dosyaları kapanıyor?**
**A:** Terminal'den çalıştır veya dosyayı çift tıkla, `pause` komutu var

### **Q: Veritabanında veri yok?**
**A:**
```bash
scripts\staging\setup_db.bat  # Staging için
scripts\production\setup_db.bat  # Production için
```

## 🎯 **EN BASIT KULLANIM**

### **Günlük Geliştirme:**
1. `git checkout staging`
2. `dart scripts\utils\switch_environment.dart staging`
3. Kod yaz
4. `git push origin staging` ← **Otomatik deploy!**

### **Canlıya Çıkarma:**
1. `git checkout main`
2. `git merge staging`
3. `git push origin main`
4. `scripts\production\deploy.bat`

## 🚨 **DİKKAT EDİLECEKLER**

- ✅ **Staging**: Otomatik deploy, test için güvenli
- ⚠️ **Production**: Manuel deploy, dikkatli ol!
- 📱 **APK Build**: Her ortam için ayrı build et
- 🗄️ **Veritabanı**: İlk kurulumda mutlaka kur

Bu kadar! Başka soru varsa sor.
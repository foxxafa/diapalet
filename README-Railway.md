# 🚀 DIAPALET Railway Database Manager

## 📁 Tek Dosya Çözümü

Artık sadece **1 dosya** var:

- **`railway-db-manager.bat`** - Tüm işlemler bu dosyada!

## 🎯 Kullanım

### Basit Kullanım
1. **`railway-db-manager.bat`** çift tıkla
2. Menüden istediğiniz işlemi seçin (1-9)
3. İşlem bittikten sonra menü tekrar açılır

### Günlük Geliştirme
1. **`railway-db-manager.bat`** çift tıkla
2. **3** tuşuna bas (Staging DB sıfırla)
3. Flutter uygulamanızda test edin

### Production'a Çıkarken
1. **`railway-db-manager.bat`** çift tıkla
2. **4** tuşuna bas (Production DB sıfırla)
3. Flutter'da `api_config.dart`'ta `ApiEnvironment.production` yapın
4. Build alın

### Bağlantı Problemi Varsa
1. **`railway-db-manager.bat`** çift tıkla
2. **7** tuşuna bas (Her iki ortamı test et)

## 🔐 Test Kullanıcıları

Her sıfırlamada otomatik yüklenir:

```
Username: foxxafa        | Password: 123         | Warehouse: SOUTHALL
Username: test           | Password: 123         | Warehouse: SOUTHALL  
Username: zeynep.celik   | Password: zeynep123   | Warehouse: MANCHESTER
```

## ⚠️ Önemli Notlar

- **Staging**: Geliştirme için güvenli, istediğiniz kadar sıfırlayın
- **Production**: Canlı sistem! Çok dikkatli olun
- Railway CLI kurulu olmalı (`railway login` yapılmış)
- Internet bağlantısı gerekli

## 🆘 Sorun Giderme

**Hata alırsanız:**
1. Railway CLI kurulu mu? → `railway --version`
2. Login olmuş musunuz? → `railway login`  
3. İnternet bağlantınız var mı?
4. PowerShell çalışıyor mu?

**En basit test:** `test-connections.bat` çalıştırın 
# DIAPALET SYNC SYSTEM - TEST SCENARIOS

## 🧪 Kritik Test Senaryoları

### **1. Serbest Mal Kabul Duplicate Test**
```
SENARYO: Sync sırasında serbest mal kabul yapılması
ADIMLAR:
1. Serbest mal kabul başlat (DN001)
2. Aynı anda arka planda sync başlasın  
3. Serbest mal kabul kaydet
4. Sync tamamlansın
5. "Put Away from Free Receipt" sayfasını kontrol et

BEKLENEN SONUÇ: ✅ Tek kayıt görülmeli
ÖNCEKI DURUM: ❌ Duplicate kayıtlar
```

### **2. Race Condition Timing Test**
```
SENARYO: 60 saniye buffer testı
ADIMLAR:
1. Sync başlat
2. 30 saniye içinde işlem yap
3. Sync devam ederken ikinci işlem yap
4. Sync tamamlansın
5. Tüm işlemlerin kaydedildiğini kontrol et

BEKLENEN SONUÇ: ✅ Tüm işlemler kaydedildi
BUFFER AVANTAJI: 60 saniye güvenlik marjı
```

### **3. Inventory Stock Duplicate Test**
```
SENARYO: Aynı stok parametreleri ile sync
ADIMLAR:
1. Stok hareketi yap (Product A, Location X, Pallet P001)
2. Sync tamamlansın  
3. Aynı parametrelerle tekrar sync gelsin
4. Inventory stock tablosunu kontrol et

BEKLENEN SONUÇ: ✅ Miktarlar toplandı, tek kayıt
ÖNCEKI DURUM: ❌ Çoklu kayıtlar
```

### **4. Free Receipt Cleanup Test**
```
SENARYO: Mevcut duplicate'lerin temizlenmesi
ADIMLAR:
1. getFreeReceiptsForPutaway() fonksiyonunu çağır
2. Duplicate detection log'larını kontrol et
3. Database'de delivery_note_number duplicate'leri kontrol et
4. Put away listesini kontrol et

BEKLENEN SONUÇ: ✅ Duplicate'ler otomatik temizlendi
CLEANUP: Eski kayıtlar korunur, yeniler silinir
```

### **5. Performance Impact Test**
```
SENARYO: Yeni kontrollerin performans etkisi
ADIMLAR:
1. Büyük sync işlemi başlat (1000+ kayıt)
2. Süreyi ölç
3. Memory kullanımını kontrol et
4. Log'larda duplicate prevention mesajlarını kontrol et

BEKLENEN SONUÇ: ✅ Minimal performance impact
MAKSIMUM SÜRE ARTIŞI: %10-15
```

## 🔧 Manuel Test Komutları

### **Database Duplicate Check:**
```sql
-- Duplicate goods receipts kontrolü
SELECT delivery_note_number, COUNT(*) as count
FROM goods_receipts 
WHERE siparis_id IS NULL AND delivery_note_number IS NOT NULL
GROUP BY delivery_note_number
HAVING COUNT(*) > 1;

-- Duplicate inventory stock kontrolü  
SELECT urun_id, location_id, pallet_barcode, stock_status, COUNT(*) as count
FROM inventory_stock
GROUP BY urun_id, location_id, pallet_barcode, stock_status, siparis_id, expiry_date, goods_receipt_id
HAVING COUNT(*) > 1;
```

### **Log Monitoring:**
```bash
# Backend sync logs
tail -f /path/to/yii2/runtime/logs/app.log | grep "Sync buffer applied"

# Frontend debug logs  
adb logcat | grep "SYNC INFO"
```

## 📊 Success Metrics

### **BAŞARI KRİTERLERİ:**
- ✅ Zero duplicate free receipts
- ✅ Consolidated inventory stock entries  
- ✅ No lost operations during sync
- ✅ Clean duplicate detection logs
- ✅ Stable sync performance

### **PERFORMANS HEDEFLERİ:**
- Sync speed degradation: < 15%
- Memory overhead: < 10MB
- Duplicate detection time: < 100ms per record
- Buffer effectiveness: 99% operation preservation

## 🚨 Rollback Plan

Eğer sorunlar çıkarsa:

1. **database_helper.dart** - sync logic'i eski haline çevir
2. **TerminalController.php** - 60s buffer'ı 30s'ye düşür  
3. **Test environment**'da önce dene
4. **Production'da gradual rollout** yap

## 📝 Monitoring Checklist

- [ ] Duplicate kayıt sayısı: 0
- [ ] Sync timing hataları: 0  
- [ ] Memory leak'ler: Yok
- [ ] Performance degradation: < 15%
- [ ] Log volume: Reasonable
- [ ] User complaints: Resolved
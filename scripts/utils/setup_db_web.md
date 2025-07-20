# Railway Web Dashboard ile Veritabanı Kurulumu

## 🌐 Web Üzerinden Veritabanı Kurma

MySQL CLI kurulu değilse, Railway web dashboard üzerinden veritabanını kurabilirsiniz:

### 1. Railway Dashboard'a Git
- https://railway.app adresine git
- Projenizi açın: "satisfied-consideration"

### 2. Staging Ortamını Seç
- Sol menüden "Environments" → "staging" seç

### 3. MySQL Servisini Aç
- "MySQL" servisine tıkla
- "Data" sekmesine git

### 4. SQL Editörünü Kullan
- "Query" butonuna tıkla
- SQL editörü açılacak

### 5. Veritabanı Scriptini Çalıştır

#### A. Önce Temizlik (İsteğe Bağlı)
```sql
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `wms_putaway_status`;
DROP TABLE IF EXISTS `inventory_transfers`;
DROP TABLE IF EXISTS `inventory_stock`;
DROP TABLE IF EXISTS `goods_receipt_items`;
DROP TABLE IF EXISTS `goods_receipts`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis_satir`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis`;
DROP TABLE IF EXISTS `processed_requests`;
DROP TABLE IF EXISTS `employees`;
DROP TABLE IF EXISTS `shelfs`;
DROP TABLE IF EXISTS `warehouses`;
DROP TABLE IF EXISTS `branches`;
DROP TABLE IF EXISTS `urunler`;

SET FOREIGN_KEY_CHECKS = 1;
```

#### B. Sonra Ana Script
- `backend/complete_setup.sql` dosyasını aç
- İçeriğini kopyala
- Railway SQL editörüne yapıştır
- "Execute" butonuna bas

### 6. Kontrol Et
```sql
SHOW TABLES;
SELECT COUNT(*) FROM employees;
SELECT COUNT(*) FROM urunler;
SELECT * FROM warehouses;
```

### 7. Production İçin Aynı İşlemi Tekrarla
- "Environments" → "production" seç
- Aynı adımları tekrarla

## ✅ Başarı Kontrolü

Veritabanı kurulumu başarılıysa şu tabloları görmelisiniz:
- branches
- employees
- urunler
- warehouses
- shelfs
- satin_alma_siparis_fis
- satin_alma_siparis_fis_satir
- inventory_stock
- goods_receipts
- goods_receipt_items
- inventory_transfers
- processed_requests
- wms_putaway_status
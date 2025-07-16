# Çevrimdışı Senkronizasyon Rehberi - Diapalet

## Çevrimdışı Çalışma Prensibi
Diapalet, internet bağlantısı olmadığında da çalışabilir ve veriler otomatik olarak senkronize edilir.

## Veri Akışı Stratejisi

### Çevrimiçi Mod
1. API'den veri çekilir
2. SQLite'a cache olarak kaydedilir
3. UI SQLite'dan beslenir

### Çevrimdışı Mod
1. Tüm işlemler SQLite'a kaydedilir
2. `pending_operations` tablosuna sync bekleyen işlemler eklenir
3. Bağlantı geldiğinde otomatik sync başlar

## Sync Service Kuralları

### Pending Operations
```dart
// Çevrimdışı işlem kaydetme
await syncService.addPendingOperation(
  type: 'goods_receiving',
  data: operationData,
  priority: 1,
);
```

### Sync Stratejisi
- **Priority-based**: Yüksek öncelikli işlemler önce sync edilir
- **Batch processing**: Aynı tip işlemler toplu olarak gönderilir
- **Retry mechanism**: Başarısız sync'ler tekrar denenir
- **Conflict resolution**: Server data önceliklidir

### Connectivity Monitoring
```dart
// Bağlantı durumu dinleme
connectivity.onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    syncService.startSync();
  }
});
```

## Database Schema Kuralları

### Sync Metadata
Her tablo şu alanları içermeli:
- `created_at`: Oluşturulma zamanı
- `updated_at`: Güncellenme zamanı
- `synced_at`: Son sync zamanı
- `is_synced`: Sync durumu (0/1)

### Pending Operations Table
```sql
CREATE TABLE pending_operations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  data TEXT NOT NULL,
  priority INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  retry_count INTEGER DEFAULT 0
);
```

## Error Handling
- Network timeout: 30 saniye
- Retry count: Maksimum 3 deneme
- Exponential backoff: Her denemede bekleme süresi artar
- User notification: Sync hatalarında kullanıcı bilgilendirilir
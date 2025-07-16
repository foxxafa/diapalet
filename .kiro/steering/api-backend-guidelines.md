# API ve Backend Entegrasyon Rehberi - Diapalet

## Backend Yapısı
- **Framework**: PHP Yii Framework
- **Controller**: TerminalController.php
- **Database**: MySQL/MariaDB
- **Authentication**: API Key tabanlı

## API Endpoint Yapısı

### Base Configuration
```dart
// lib/core/network/api_config.dart
class ApiConfig {
  static const String baseUrl = 'https://your-domain.com/api';
  static const Duration timeout = Duration(seconds: 30);
}
```

### Authentication
- API Key header'da gönderilir
- Login endpoint hariç tüm endpoint'ler authentication gerektirir
- Session management SQLite'da yapılır

### HTTP Client Setup
```dart
// Dio configuration
final dio = Dio(BaseOptions(
  connectTimeout: Duration(seconds: 30),
  receiveTimeout: Duration(seconds: 60),
  headers: {'Accept': 'application/json'},
));
```

## API Endpoint'leri

### Authentication
- `POST /terminal/login` - Kullanıcı girişi
- `POST /terminal/logout` - Kullanıcı çıkışı

### Goods Receiving
- `GET /terminal/purchase-orders` - Satın alma siparişleri
- `GET /terminal/purchase-order/{id}` - Sipariş detayı
- `POST /terminal/receive-goods` - Mal kabul işlemi

### Inventory Transfer
- `GET /terminal/locations` - Lokasyon listesi
- `POST /terminal/transfer` - Transfer işlemi
- `GET /terminal/transfer-history` - Transfer geçmişi

### Sync Operations
- `POST /terminal/sync-data` - Toplu veri senkronizasyonu
- `GET /terminal/health-check` - Sistem durumu kontrolü

## Error Handling

### HTTP Status Codes
- `200`: Başarılı
- `400`: Geçersiz istek
- `401`: Yetkisiz erişim
- `404`: Bulunamadı
- `500`: Sunucu hatası

### Error Response Format
```json
{
  "success": false,
  "message": "Hata mesajı",
  "error_code": "ERROR_CODE",
  "data": null
}
```

### Network Error Handling
```dart
try {
  final response = await dio.post(endpoint, data: data);
  return response.data;
} on DioException catch (e) {
  if (e.type == DioExceptionType.connectionTimeout) {
    // Offline fallback
    return await localDataSource.getData();
  }
  throw NetworkException(e.message);
}
```

## Data Synchronization

### Sync Payload Format
```json
{
  "operations": [
    {
      "type": "goods_receiving",
      "data": {...},
      "timestamp": "2024-01-01T10:00:00Z"
    }
  ]
}
```

### Batch Operations
- Aynı tip işlemler toplu olarak gönderilir
- Maksimum 50 işlem per batch
- Priority sırasına göre işlenir
# DIAPALET Railway Deployment Guide

Bu rehber, DIAPALET WMS uygulamasını Railway platformuna deploy etmenizi sağlar.

## Ön Gereksinimler

1. [Railway](https://railway.app) hesabı
2. Git repository (GitHub, GitLab, veya Bitbucket)
3. MySQL veritabanı

## Railway'e Deployment Adımları

### 1. Railway Hesabı ve Proje Oluşturma

1. [Railway.app](https://railway.app) adresine gidin ve kayıt olun/giriş yapın
2. "New Project" butonuna tıklayın
3. "Deploy from GitHub repo" seçeneğini seçin
4. Projenizin bulunduğu repository'yi seçin

### 2. MySQL Veritabanı Ekleme

1. Railway dashboard'unda projenize gidin
2. "New" butonuna tıklayın ve "Database" → "Add MySQL" seçin
3. MySQL servisi otomatik olarak oluşturulacak
4. Veritabanı bilgilerini not alın (otomatik environment variables olarak ayarlanır)

### 3. Environment Variables Ayarlama

Railway dashboard'unda "Variables" sekmesine gidin ve aşağıdaki değişkenleri ekleyin:

#### Zorunlu Değişkenler:
```bash
# Application Environment
YII_DEBUG=false
YII_ENV=prod

# Security (32 karakter random string)
COOKIE_VALIDATION_KEY=your-random-32-character-secret-key

# Database (Railway otomatik sağlar, manuel ayarlamayın)
# DB_HOST, DB_NAME, DB_USER, DB_PASSWORD otomatik ayarlanır
```

#### İsteğe Bağlı Değişkenler:
```bash
# External API (mevcut kodunuzdan)
DIA_API_URL=https://aytacfoods.ws.dia.com.tr/api/v3/sis/json
DIA_USERNAME=Ws-03
DIA_PASSWORD=Ws123456.
DIA_API_KEY=dbbd8cb8-846f-4379-8d77-505e845db4a2

# Application URLs
API_BASE_URL=https://your-app-name.railway.app
```

### 4. Database Schema Oluşturma

Deployment sonrası, veritabanı şemasını oluşturmak için:

1. Railway MySQL servisine bağlanın
2. `backend/create_db.sql` dosyasını çalıştırın
3. İsteğe bağlı olarak `backend/test_data.sql` ile test verilerini yükleyin

### 5. Deployment Süreci

1. Kodunuzu Git repository'ye push edin
2. Railway otomatik olarak deployment başlatır
3. Build logs'ları takip edin
4. Deployment tamamlandığında URL otomatik olarak sağlanır

## Deployment Dosyaları

### `Dockerfile`
- PHP 8.1 + Apache base image
- Gerekli PHP extension'ları
- Composer dependencies
- Yii2 framework setup
- Production optimizasyonları

### `backend/composer.json`
- Yii2 framework ve bağımlılıkları
- Production ve development paketleri
- Auto-loading yapılandırması

### `railway.json`
- Railway-specific deployment configuration
- Health check ayarları
- Restart policies

### `env.example`
- Tüm environment variables template
- Production security settings
- Database configuration örneği

## Post-Deployment Checklist

- [ ] Uygulama health check endpoint'i çalışıyor mu? (`/health-check`)
- [ ] Database bağlantısı başarılı mı?
- [ ] API endpoints test edildi mi?
- [ ] SSL sertifikası aktif mi?
- [ ] Environment variables doğru ayarlandı mı?

## Troubleshooting

### Common Issues:

1. **Database Connection Error**
   - Environment variables doğru ayarlandığından emin olun
   - MySQL servisi running durumda olduğunu kontrol edin

2. **500 Internal Server Error**
   - `YII_DEBUG=true` yaparak detaylı hata mesajlarını görün
   - Apache error logs'ları kontrol edin

3. **Build Failures**
   - Dockerfile'daki dependency'leri kontrol edin
   - Composer.json'da version conflicts olup olmadığını kontrol edin

### Monitoring:

Railway otomatik monitoring sağlar:
- CPU/Memory usage
- Request metrics
- Error logs
- Database metrics

## Security Considerations

1. **Production Environment:**
   - `YII_DEBUG=false` olduğundan emin olun
   - Güçlü `COOKIE_VALIDATION_KEY` kullanın
   - HTTPS zorlaması aktif olsun

2. **Database Security:**
   - Railway'in internal network'ünü kullanın
   - Database credentials'ları environment variables olarak ayarlayın

3. **API Security:**
   - Rate limiting implementasyonu ekleyin
   - CORS ayarlarını production'a uygun yapın

## Support

Railway deployment ile ilgili sorunlar için:
- [Railway Documentation](https://docs.railway.app)
- [Railway Discord Community](https://discord.gg/xAm2w6g)
- [Railway GitHub Issues](https://github.com/railwayapp/railway/issues) 
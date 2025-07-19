# 🏠 Local Development Rehberi

Bu rehber senin bilgisayarında local development environment kurman için.

## 🚀 Hızlı Başlangıç

### 1. Docker Servislerini Başlat
```bash
docker-compose -f docker-compose.dev.yml up -d
```

### 2. API Endpoint'lerini Test Et
- **Health Check:** http://localhost:5000/health-check
- **Login API:** http://localhost:5000/api/terminal/login
- **Database Admin:** http://localhost:8080 (Adminer)

### 3. Flutter Environment'ı Development'a Çevir
`lib/core/network/api_environments.dart` dosyasında:
```dart
static const Environment current = Environment.development;
```

### 4. Flutter Uygulamasını Çalıştır
```bash
flutter run
```

## 🗄️ Database Bağlantı Bilgileri

### Local MySQL:
- **Host:** localhost:3306
- **Database:** diapalet_dev
- **Username:** diapalet
- **Password:** diapalet123
- **Root Password:** root123

### Adminer Web Interface:
- **URL:** http://localhost:8080
- **Server:** mysql
- **Username:** diapalet
- **Password:** diapalet123
- **Database:** diapalet_dev

## 🔧 Geliştirme Komutları

### Docker Servisleri Yönetimi:
```bash
# Servisleri başlat
docker-compose -f docker-compose.dev.yml up -d

# Servisleri durdur
docker-compose -f docker-compose.dev.yml down

# Logları görüntüle
docker-compose -f docker-compose.dev.yml logs -f

# Backend logları
docker-compose -f docker-compose.dev.yml logs -f backend

# MySQL logları
docker-compose -f docker-compose.dev.yml logs -f mysql

# Container'lara bağlan
docker exec -it diapalet_backend_dev bash
docker exec -it diapalet_mysql_dev mysql -u diapalet -p
```

### Database İşlemleri:
```bash
# MySQL'e bağlan
docker exec -it diapalet_mysql_dev mysql -u diapalet -pdiapalet123 diapalet_dev

# Backup al
docker exec diapalet_mysql_dev mysqldump -u diapalet -pdiapalet123 diapalet_dev > backup.sql

# Backup restore et
docker exec -i diapalet_mysql_dev mysql -u diapalet -pdiapalet123 diapalet_dev < backup.sql
```

## 📱 Flutter Test Kullanıcıları

Backend'de hazır test kullanıcıları:
- **Username:** foxxafa, **Password:** 123
- **Username:** mehmet, **Password:** 123
- **Username:** zeynep.celik, **Password:** zeynep123

## 🔄 Environment Değiştirme

### Production'a Geçiş (Adam için build):
```dart
// api_environments.dart
static const Environment current = Environment.production;
```

### Development'a Geçiş (Senin için):
```dart
// api_environments.dart  
static const Environment current = Environment.development;
```

### Local Network'e Geçiş (Fiziksel cihaz):
```dart
// api_environments.dart
static const Environment current = Environment.local;
```

## 🚨 Sorun Giderme

### Backend erişilemiyor:
```bash
# Container durumunu kontrol et
docker ps

# Backend loglarını kontrol et
docker-compose -f docker-compose.dev.yml logs backend

# Port kontrolü
netstat -tulpn | grep :5000
```

### Database bağlantı sorunu:
```bash
# MySQL container durumu
docker exec -it diapalet_mysql_dev mysql -u root -proot123 -e "SHOW DATABASES;"

# Database tablolarını kontrol et
docker exec -it diapalet_mysql_dev mysql -u diapalet -pdiapalet123 diapalet_dev -e "SHOW TABLES;"
```

### Flutter bağlantı sorunu:
1. Environment doğru mu? (`api_environments.dart`)
2. Emülatör kullanıyorsan: `10.0.2.2:5000`
3. Fiziksel cihaz kullanıyorsan: `192.168.x.x:5000`

## 📋 Production vs Development

| Özellik | Production (Railway) | Development (Local) |
|---------|---------------------|-------------------|
| URL | https://diapalet-production.up.railway.app | http://localhost:5000 |
| Database | Railway MySQL | Local Docker MySQL |
| Debug | false | true |
| Logs | Railway Dashboard | Docker logs |
| Kullanım | Adam testi | Senin geliştirmen | 
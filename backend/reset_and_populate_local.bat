@echo off
rem Bu script, tum sistemi sifirlar ve veritabani icin YALNIZCA LOKAL test verilerini kullanir.
rem DIA senkronizasyonu cagrilmaz.
cd /d %~dp0

echo [1/6] Container ve veritabani volume'u siliniyor...
docker compose down -v

echo [2/6] Servisler yeniden baslatiliyor... (Veritabani bos olarak olusturulacak)
docker compose up -d

echo.
echo [3/6] Veritabani sunucusunun ayaga kalkmasi bekleniyor...
:check_db
timeout /t 5 /nobreak > NUL
docker compose exec db mysqladmin ping -h localhost -uroot -p123456 > NUL 2>&1
if %errorlevel% neq 0 (
    echo Veritabani henuz hazir degil, 5 saniye sonra tekrar denenecek...
    goto check_db
)
echo ✅ Veritabani sunucusu hazir!
echo.

echo [4/6] Web sunucusunun ayaga kalkmasi bekleniyor...
:check_web
timeout /t 5 /nobreak > NUL
curl --head --fail http://localhost:5000/terminal/health-check > NUL 2>&1
if %errorlevel% neq 0 (
    echo Web sunucusu henuz hazir degil, 5 saniye sonra tekrar denenecek...
    goto check_web
)
echo ✅ Web sunucusu hazir!
echo.

echo [5/6] Veritabani semasi olusturuluyor...
docker compose exec db mysql -uroot -p123456 -e "CREATE DATABASE IF NOT EXISTS enzo CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
docker compose exec -T db mysql -uroot -p123456 enzo < dump.sql
echo ✅ Veritabani semasi olusturuldu.

echo [6/6] Tum test verileri (depolar, raflar, urunler, calisanlar, siparisler) veritabanina ekleniyor...
rem NOT: Bu adimda DIA senkronizasyonu atlanmistir. Tum veriler test_data.sql dosyasindan gelir.
docker compose exec -T db mysql -uroot -p123456 enzo < test_data.sql
echo ✅ Tum lokal test verileri eklendi.

echo.
echo =================================================================
echo ✅ LOKAL KURULUM TAMAMLANDI! Sistem lokal verilerle calisiyor.
echo =================================================================
pause

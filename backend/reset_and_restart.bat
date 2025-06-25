@echo off
rem Bu script, tüm sistemi sıfırlar, servislerin hazır olmasını bekler ve verileri otomatik olarak yükler.
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

echo [5/6] Dia'dan gercek depo ve raf verileri cekiliyor...
curl http://localhost:5000/terminal/sync-shelfs
echo.
echo.

echo [6/6] Test verileri (calisanlar, urunler) veritabanina ekleniyor...
docker compose exec -T db mysql -uroot -p123456 diapalet_test < test_data.sql
echo ✅ Test verileri eklendi.

echo.
echo =================================================================
echo ✅ KURULUM TAMAMLANDI! Tum sistem tam otomatik olarak hazir.
echo =================================================================
pause

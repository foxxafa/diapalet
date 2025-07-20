@echo off
echo ========================================
echo   DIAPALET - STAGING DB SETUP
echo ========================================
echo.

echo 🔄 Staging ortamına geçiliyor...
railway environment staging

echo 📊 Veritabanı kurulumu için 2 yöntem:
echo.
echo 1. Railway Web Dashboard (Kolay - Önerilen)
echo 2. MySQL CLI (Gelişmiş)
echo.
set /p choice="Seçiminiz (1 veya 2): "

if "%choice%"=="1" (
    echo.
    echo 🌐 Railway Web Dashboard açılıyor...
    echo.
    echo Şu adımları takip edin:
    echo 1. Railway Dashboard → Staging → MySQL → Data → Query
    echo 2. backend/complete_setup.sql dosyasını açın
    echo 3. İçeriğini kopyalayıp SQL editörüne yapıştırın
    echo 4. Execute butonuna basın
    echo.
    start https://railway.app

) else if "%choice%"=="2" (
    echo.
    echo 🔧 MySQL CLI ile bağlanmaya çalışılıyor...
    railway connect mysql

) else (
    echo ❌ Geçersiz seçim!
)

echo.
echo ✅ Veritabanı kurulumu tamamlandı!
echo 🔍 Kontrol için: railway connect mysql
echo    Sonra: SHOW TABLES;
echo.
pause
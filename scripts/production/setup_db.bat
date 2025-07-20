@echo off
echo ========================================
echo  DIAPALET - PRODUCTION DB SETUP
echo ========================================
echo.

echo ⚠️  UYARI: Production veritabanını kuruyorsunuz!
echo Bu işlem canlı sistemi etkileyebilir.
echo.
set /p confirm="Devam etmek istediğinizden emin misiniz? (y/N): "

if /i not "%confirm%"=="y" (
    echo ❌ İşlem iptal edildi.
    pause
    exit /b
)

echo.
echo 🔄 Production ortamına geçiliyor...
railway environment production

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
    echo 1. Railway Dashboard → Production → MySQL → Data → Query
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
echo ✅ Production veritabanı kurulumu tamamlandı!
echo 🔍 Kontrol için: railway connect mysql
echo    Sonra: SHOW TABLES;
echo.
pause
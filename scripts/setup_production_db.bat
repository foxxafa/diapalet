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

echo 📊 MySQL veritabanına bağlanılıyor...
echo ⚠️  MySQL bağlantısı açılacak, SQL dosyasını yüklemek için:
echo    1. MySQL konsolu açıldığında şu komutu çalıştırın:
echo    2. source backend/complete_setup.sql;
echo    3. Veya dosya içeriğini kopyalayıp yapıştırın
echo.

pause

echo 🚀 Railway MySQL konsolunu açıyor...
railway connect mysql

echo.
echo ✅ Production veritabanı kurulumu tamamlandı!
echo 🔍 Kontrol için: railway connect mysql
echo    Sonra: SHOW TABLES;
echo.
pause
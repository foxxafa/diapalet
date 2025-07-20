@echo off
echo ========================================
echo   DIAPALET - DATABASE STATUS CHECK
echo ========================================
echo.

echo Hangi ortamın veritabanını kontrol etmek istiyorsunuz?
echo 1. Staging
echo 2. Production
echo.
set /p choice="Seçiminiz (1 veya 2): "

if "%choice%"=="1" (
    echo 🔄 Staging ortamına geçiliyor...
    railway environment staging
    echo 📊 Staging MySQL'e bağlanılıyor...
) else if "%choice%"=="2" (
    echo 🔄 Production ortamına geçiliyor...
    railway environment production
    echo 📊 Production MySQL'e bağlanılıyor...
) else (
    echo ❌ Geçersiz seçim!
    pause
    exit /b
)

echo.
echo ⚠️  MySQL konsolu açılacak. Şu komutları çalıştırın:
echo    SHOW TABLES;
echo    SELECT COUNT(*) FROM employees;
echo    SELECT COUNT(*) FROM urunler;
echo    SELECT COUNT(*) FROM satin_alma_siparis_fis;
echo    SELECT * FROM warehouses;
echo.

pause

railway connect mysql

echo.
echo ✅ Veritabanı kontrolü tamamlandı!
pause
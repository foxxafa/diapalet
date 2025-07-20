@echo off
echo ========================================
echo   DIAPALET - STAGING DB SETUP
echo ========================================
echo.

echo 🔄 Staging ortamına geçiliyor...
railway environment staging

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
echo ✅ Veritabanı kurulumu tamamlandı!
echo 🔍 Kontrol için: railway connect mysql
echo    Sonra: SHOW TABLES;
echo.
pause
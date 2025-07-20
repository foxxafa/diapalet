@echo off
echo ========================================
echo    RAILWAY BAĞLANTI TESTİ
echo ========================================
echo.

echo 🔄 Staging ortamına geçiliyor...
railway environment staging

echo.
echo 📊 Railway durumu:
railway status

echo.
echo 🌐 Staging API testi:
curl -s https://diapalet-staging.up.railway.app/health-check

echo.
echo 🔄 Production ortamına geçiliyor...
railway environment production

echo.
echo 📊 Railway durumu:
railway status

echo.
echo 🌐 Production API testi:
curl -s https://diapalet-production.up.railway.app/health-check

echo.
echo ✅ Test tamamlandı!
echo.
echo ⏸️  Devam etmek için herhangi bir tuşa basın...
pause > nul
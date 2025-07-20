@echo off
echo ========================================
echo    DIAPALET - STAGING DEPLOYMENT
echo ========================================
echo.

echo 🔄 Staging ortamına geçiliyor...
railway environment staging

echo 📦 Staging ortamına deploy ediliyor...
railway up

echo.
echo ✅ Staging deployment tamamlandı!
echo 🌐 URL: https://diapalet-staging.up.railway.app
echo.
pause
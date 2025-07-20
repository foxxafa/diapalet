@echo off
echo ========================================
echo   DIAPALET - PRODUCTION DEPLOYMENT
echo ========================================
echo.

echo ⚠️  UYARI: Production ortamına deploy ediyorsunuz!
echo Bu işlem canlı sistemi etkileyecektir.
echo.
set /p confirm="Devam etmek istediğinizden emin misiniz? (y/N): "

if /i not "%confirm%"=="y" (
    echo ❌ Deployment iptal edildi.
    pause
    exit /b
)

echo.
echo 🔄 Production ortamına geçiliyor...
railway environment production

echo 📦 Production ortamına deploy ediliyor...
railway up

echo.
echo ✅ Production deployment tamamlandı!
echo 🌐 URL: https://diapalet-production.up.railway.app
echo.
echo ⏸️  Devam etmek için herhangi bir tuşa basın...
pause > nul
echo.
echo 🎉 İşlem tamamlandı!
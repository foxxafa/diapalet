@echo off
echo ========================================
echo    DIAPALET - DEVELOPMENT WORKFLOW
echo ========================================
echo.

echo Hangi işlemi yapmak istiyorsunuz?
echo.
echo 1. Yeni özellik geliştirmeye başla (staging)
echo 2. Staging'e deploy et ve test et
echo 3. Production'a çıkar (dikkatli!)
echo 4. Ortam durumunu kontrol et
echo.
set /p choice="Seçiminiz (1-4): "

if "%choice%"=="1" (
    echo.
    echo 🚀 Geliştirme ortamı hazırlanıyor...
    echo.

    echo 📱 Flutter uygulamasını staging'e ayarlıyor...
    dart scripts/switch_environment.dart staging

    echo 🔄 Git staging branch'ine geçiyor...
    git checkout staging
    git pull origin staging

    echo ✅ Geliştirme ortamı hazır!
    echo 💡 Artık kod değişikliklerinizi yapabilirsiniz.
    echo 📤 Değişiklikleri push ettiğinizde otomatik deploy olacak.

) else if "%choice%"=="2" (
    echo.
    echo 🧪 Staging test ortamı hazırlanıyor...
    echo.

    echo 📱 Flutter uygulamasını staging'e ayarlıyor...
    dart scripts/switch_environment.dart staging

    echo 🔄 Staging'e deploy ediliyor...
    railway environment staging
    railway up

    echo 📊 Ortam durumu kontrol ediliyor...
    dart scripts/check_environments.dart

    echo ✅ Staging hazır! Test edebilirsiniz.
    echo 🌐 URL: https://diapalet-staging.up.railway.app

) else if "%choice%"=="3" (
    echo.
    echo ⚠️  UYARI: Production'a çıkarıyorsunuz!
    set /p confirm="Staging'de test ettiniz ve emin misiniz? (y/N): "

    if /i "%confirm%"=="y" (
        echo.
        echo 🔄 Production'a geçiliyor...

        echo 📱 Flutter uygulamasını production'a ayarlıyor...
        dart scripts/switch_environment.dart production

        echo 🚀 Git main branch'ine geçiyor...
        git checkout main
        git merge staging
        git push origin main

        echo 📦 Production'a deploy ediliyor...
        railway environment production
        railway up

        echo ✅ Production deployment tamamlandı!
        echo 🌐 URL: https://diapalet-production.up.railway.app
    ) else (
        echo ❌ Production deployment iptal edildi.
    )

) else if "%choice%"=="4" (
    echo.
    echo 📊 Ortam durumu kontrol ediliyor...
    dart scripts/check_environments.dart

    echo.
    echo 🗂️  Git branch durumu:
    git branch -v

    echo.
    echo 🚀 Railway durumu:
    railway status

) else (
    echo ❌ Geçersiz seçim!
)

echo.
pause
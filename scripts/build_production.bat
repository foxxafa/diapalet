@echo off
echo ========================================
echo  DIAPALET - PRODUCTION APK BUILD
echo ========================================
echo.

echo ⚠️  UYARI: Production APK build ediyorsunuz!
set /p confirm="Devam etmek istediğinizden emin misiniz? (y/N): "

if /i not "%confirm%"=="y" (
    echo ❌ Build iptal edildi.
    pause
    exit /b
)

echo.
echo 🔄 Production ortamına geçiliyor...
dart scripts/switch_environment.dart production

echo 🧹 Flutter temizleniyor...
flutter clean

echo 📦 Paketler alınıyor...
flutter pub get

echo 🔨 Production APK build ediliyor...
flutter build apk --release --target-platform android-arm64

echo.
echo ✅ Production APK build tamamlandı!
echo 📱 APK konumu: build\app\outputs\flutter-apk\app-release.apk
echo.
pause
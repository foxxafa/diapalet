@echo off
echo ========================================
echo   DIAPALET - STAGING APK BUILD
echo ========================================
echo.

echo 🔄 Staging ortamına geçiliyor...
dart scripts/switch_environment.dart staging

echo 🧹 Flutter temizleniyor...
flutter clean

echo 📦 Paketler alınıyor...
flutter pub get

echo 🔨 Staging APK build ediliyor...
flutter build apk --release --target-platform android-arm64

echo.
echo ✅ Staging APK build tamamlandı!
echo 📱 APK konumu: build\app\outputs\flutter-apk\app-release.apk
echo.
pause
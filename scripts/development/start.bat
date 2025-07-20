@echo off
echo ========================================
echo   DIAPALET - DEVELOPMENT START
echo ========================================
echo.

echo 🔄 Local ortamına geçiliyor...
dart scripts/switch_environment.dart local

echo 🐳 Docker container başlatılıyor...
docker-compose -f docker-compose.dev.yml up -d

echo ⏳ Backend'in hazır olması bekleniyor...
timeout /t 10 /nobreak > nul

echo 🏥 Backend health check...
curl -s http://localhost:8080/health-check

echo.
echo ✅ Development ortamı hazır!
echo 🌐 Backend: http://localhost:8080
echo 📱 Flutter uygulamasını başlatabilirsiniz: flutter run
echo.
pause
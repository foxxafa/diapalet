@echo off
chcp 65001 >nul
title DIAPALET Railway Database Manager
color 0B

:MAIN_MENU
cls
echo.
echo ==========================================
echo     DIAPALET Railway Database Manager
echo ==========================================
echo.
echo 🔧 TEMEL ISLEMLER:
echo    1 - Railway durumunu kontrol et
echo    2 - Ortamlari listele
echo.
echo 💾 VERITABANI SIFIRLAMA:
echo    3 - STAGING veritabanini sifirla + test verisi yukle
echo    4 - PRODUCTION veritabanini sifirla + test verisi yukle
echo.
echo 🌐 BAGLANTI TESTLERI:
echo    5 - Staging baglantisini test et
echo    6 - Production baglantisini test et
echo    7 - Her iki ortami test et
echo.
echo 🔗 MANUEL SQL (GELISMIS):
echo    8 - Staging veritabani shell'e baglan
echo    9 - Production veritabani shell'e baglan
echo.
echo    0 - Cikis
echo.
set /p choice="Seciminizi yapin (0-9): "

if "%choice%"=="1" goto CHECK_RAILWAY
if "%choice%"=="2" goto LIST_ENVIRONMENTS
if "%choice%"=="3" goto RESET_STAGING
if "%choice%"=="4" goto RESET_PRODUCTION
if "%choice%"=="5" goto TEST_STAGING
if "%choice%"=="6" goto TEST_PRODUCTION
if "%choice%"=="7" goto TEST_BOTH
if "%choice%"=="8" goto SHELL_STAGING
if "%choice%"=="9" goto SHELL_PRODUCTION
if "%choice%"=="0" goto EXIT
echo.
echo ❌ Gecersiz secim! Tekrar deneyin.
pause
goto MAIN_MENU

:CHECK_RAILWAY
cls
echo.
echo ==========================================
echo      Railway Durumu Kontrol Ediliyor
echo ==========================================
echo.
railway status
if %errorlevel% neq 0 (
    echo.
    echo ❌ Railway CLI'a baglanilmadi!
    echo    - railway login komutunu calistirin
    echo    - Internet baglantinizi kontrol edin
) else (
    echo.
    echo ✅ Railway baglantisi basarili!
)
echo.
pause
goto MAIN_MENU

:LIST_ENVIRONMENTS
cls
echo.
echo ==========================================
echo          Mevcut Ortamlar
echo ==========================================
echo.
railway environment
echo.
pause
goto MAIN_MENU

:RESET_STAGING
cls
echo.
echo ==========================================
echo       STAGING Veritabani Sifirlama
echo ==========================================
echo.
echo ⚠️  STAGING veritabani sifirlanacak!
echo     Bu islem tum verileri silecek.
echo.
set /p confirm="Devam etmek istiyor musunuz? (y/N): "
if /i not "%confirm%"=="y" (
    echo.
    echo ℹ️  Islem iptal edildi.
    pause
    goto MAIN_MENU
)

echo.
echo 🔄 Staging ortamina geciliyor...
railway environment staging

echo.
echo 🔄 STAGING veritabani sifirlaniyor...
echo    API endpoint: https://diapalet-staging.up.railway.app/api/terminal/dev-reset

powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://diapalet-staging.up.railway.app/api/terminal/dev-reset' -Method POST -ContentType 'application/json' -Body '{}'; Write-Host $response.Content; exit 0 } catch { Write-Host 'Hata:' $_.Exception.Message; exit 1 }"

if %errorlevel% equ 0 (
    echo.
    echo ✅ STAGING veritabani basariyla sifirlandi!
    echo.
    echo 👤 Test kullanicilari:
    echo    - foxxafa / 123 (SOUTHALL WAREHOUSE)
    echo    - test / 123 (SOUTHALL WAREHOUSE)
    echo    - zeynep.celik / zeynep123 (MANCHESTER WAREHOUSE)
) else (
    echo.
    echo ❌ Veritabani sifirlama basarisiz!
    echo    - Internet baglantinizi kontrol edin
    echo    - Railway sunucusunun calistica emin olun
)
echo.
pause
goto MAIN_MENU

:RESET_PRODUCTION
cls
color 0C
echo.
echo ==========================================
echo     PRODUCTION Veritabani Sifirlama
echo ==========================================
echo.
echo ⚠️  PRODUCTION VERITABANI SIFIRLANACAK! ⚠️
echo     Bu islem CANLI sistemdeki TUM verileri silecek!
echo.
echo     Bu islemi sadece canli sistemi kurarken yapmaniz gerekir.
echo.
set /p confirm="Gercekten devam etmek istiyor musunuz? PRODUCTION yazin: "
if not "%confirm%"=="PRODUCTION" (
    echo.
    echo ℹ️  Islem iptal edildi. Guvenlik icin dogru onay verilmedi.
    color 0B
    pause
    goto MAIN_MENU
)

echo.
echo 🔄 Production ortamina geciliyor...
railway environment production

echo.
echo 🔄 PRODUCTION veritabani sifirlaniyor...
echo    API endpoint: https://diapalet-production.up.railway.app/api/terminal/dev-reset

powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://diapalet-production.up.railway.app/api/terminal/dev-reset' -Method POST -ContentType 'application/json' -Body '{}'; Write-Host $response.Content; exit 0 } catch { Write-Host 'Hata:' $_.Exception.Message; exit 1 }"

if %errorlevel% equ 0 (
    echo.
    echo ✅ PRODUCTION veritabani basariyla sifirlandi!
    echo.
    echo 👤 Test kullanicilari:
    echo    - foxxafa / 123 (SOUTHALL WAREHOUSE)
    echo    - test / 123 (SOUTHALL WAREHOUSE)
    echo    - zeynep.celik / zeynep123 (MANCHESTER WAREHOUSE)
) else (
    echo.
    echo ❌ Veritabani sifirlama basarisiz!
    echo    - Internet baglantinizi kontrol edin
    echo    - Railway sunucusunun calistica emin olun
)
color 0B
echo.
pause
goto MAIN_MENU

:TEST_STAGING
cls
echo.
echo ==========================================
echo       Staging Baglanti Testi
echo ==========================================
echo.
echo 🔄 Staging ortami test ediliyor...
echo    URL: https://diapalet-staging.up.railway.app/api/terminal/health-check

powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://diapalet-staging.up.railway.app/api/terminal/health-check' -Method GET; Write-Host $response.Content; exit 0 } catch { Write-Host 'Hata:' $_.Exception.Message; exit 1 }"

if %errorlevel% equ 0 (
    echo.
    echo.
    echo ✅ Staging ortami basariyla erisilebilir!
) else (
    echo.
    echo.
    echo ❌ Staging ortamina baglanilmadi!
)
echo.
pause
goto MAIN_MENU

:TEST_PRODUCTION
cls
echo.
echo ==========================================
echo      Production Baglanti Testi
echo ==========================================
echo.
echo 🔄 Production ortami test ediliyor...
echo    URL: https://diapalet-production.up.railway.app/api/terminal/health-check

powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://diapalet-production.up.railway.app/api/terminal/health-check' -Method GET; Write-Host $response.Content; exit 0 } catch { Write-Host 'Hata:' $_.Exception.Message; exit 1 }"

if %errorlevel% equ 0 (
    echo.
    echo.
    echo ✅ Production ortami basariyla erisilebilir!
) else (
    echo.
    echo.
    echo ❌ Production ortamina baglanilmadi!
)
echo.
pause
goto MAIN_MENU

:TEST_BOTH
cls
echo.
echo ==========================================
echo        Her Iki Ortam Baglanti Testi
echo ==========================================
echo.
echo 🔄 Staging test ediliyor...
powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://diapalet-staging.up.railway.app/api/terminal/health-check' -Method GET; Write-Host $response.Content; exit 0 } catch { Write-Host 'Hata:' $_.Exception.Message; exit 1 }"
echo.
echo.
echo 🔄 Production test ediliyor...
powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://diapalet-production.up.railway.app/api/terminal/health-check' -Method GET; Write-Host $response.Content; exit 0 } catch { Write-Host 'Hata:' $_.Exception.Message; exit 1 }"
echo.
echo.
echo ℹ️  Her iki ortam da test edildi.
pause
goto MAIN_MENU

:SHELL_STAGING
cls
echo.
echo ==========================================
echo       Staging MySQL Shell
echo ==========================================
echo.
echo 🔄 Staging ortamina geciliyor...
railway environment staging
echo.
echo 🔄 MySQL shell baslatiliyor...
echo    Cikmak icin 'exit' yazin
echo.
railway run mysql
echo.
pause
goto MAIN_MENU

:SHELL_PRODUCTION
cls
echo.
echo ==========================================
echo      Production MySQL Shell
echo ==========================================
echo.
echo 🔄 Production ortamina geciliyor...
railway environment production
echo.
echo 🔄 MySQL shell baslatiliyor...
echo    Cikmak icin 'exit' yazin
echo.
railway run mysql
echo.
pause
goto MAIN_MENU

:EXIT
cls
echo.
echo ==========================================
echo          DIAPALET Manager
echo ==========================================
echo.
echo 👋 Tesekkurler! Gorusuruz...
echo.
timeout /t 2 >nul
exit /b 0 
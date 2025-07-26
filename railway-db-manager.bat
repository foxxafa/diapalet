@echo off
title DIAPALET Railway Database Manager
color 0B

:MAIN_MENU
cls
echo.
echo ==========================================
echo     DIAPALET Railway Database Manager
echo ==========================================
echo.
echo TEMEL ISLEMLER:
echo    1 - Railway durumunu kontrol et
echo    2 - Ortamlari listele
echo.
echo VERITABANI SIFIRLAMA:
echo    3 - STAGING veritabanini sifirla + test verisi yukle
echo    4 - PRODUCTION veritabanini sifirla + test verisi yukle
echo.
echo BAGLANTI TESTLERI:
echo    5 - Staging baglantisini test et
echo    6 - Production baglantisini test et
echo    7 - Her iki ortami test et
echo.
echo    0 - Cikis
echo.
set /p choice="Seciminizi yapin (0-7): "

if "%choice%"=="1" goto CHECK_RAILWAY
if "%choice%"=="2" goto LIST_ENVIRONMENTS
if "%choice%"=="3" goto RESET_STAGING
if "%choice%"=="4" goto RESET_PRODUCTION
if "%choice%"=="5" goto TEST_STAGING
if "%choice%"=="6" goto TEST_PRODUCTION
if "%choice%"=="7" goto TEST_BOTH
if "%choice%"=="0" goto EXIT
echo.
echo Gecersiz secim! Tekrar deneyin.
pause
goto MAIN_MENU

:CHECK_RAILWAY
cls
echo.
echo Railway Durumu Kontrol Ediliyor
echo ==========================================
echo.
railway status
if %errorlevel% neq 0 (
    echo.
    echo Railway CLI baglantilamadi!
    echo - railway login komutunu calistirin
    echo - Internet baglantinizi kontrol edin
) else (
    echo.
    echo Railway baglantisi basarili!
)
echo.
pause
goto MAIN_MENU

:LIST_ENVIRONMENTS
cls
echo.
echo Mevcut Ortamlar
echo ==========================================
echo.
echo Bu projede kullanilabilir ortamlar:
echo - staging (Test ortami)
echo - production (Canli ortam)
echo.
railway status
echo.
pause
goto MAIN_MENU

:RESET_STAGING
cls
echo.
echo STAGING Veritabani Sifirlama
echo ==========================================
echo.
echo UYARI: STAGING veritabani sifirlanacak!
echo Bu islem tum verileri silecek.
echo.
set /p confirm="Devam etmek istiyor musunuz? (y/N): "
if /i not "%confirm%"=="y" (
    echo.
    echo Islem iptal edildi.
    pause
    goto MAIN_MENU
)

echo.
echo STAGING veritabani sifirlaniyor...
echo Lutfen bekleyin...
echo.

powershell -Command "try { $r = Invoke-WebRequest -Uri 'https://diapalet-staging.up.railway.app/api/terminal/dev-reset' -Method POST -ContentType 'application/json' -Body '{}'; Write-Host 'Basarili:' $r.Content } catch { Write-Host 'Hata:' $_.Exception.Message }"

echo.
echo STAGING veritabani sifirlama islemi tamamlandi.
echo.
echo Test kullanicilari:
echo - foxxafa / 123 (SOUTHALL WAREHOUSE)
echo - test / 123 (SOUTHALL WAREHOUSE)
echo - zeynep.celik / zeynep123 (MANCHESTER WAREHOUSE)
echo.
pause
goto MAIN_MENU

:RESET_PRODUCTION
cls
color 0C
echo.
echo PRODUCTION Veritabani Sifirlama
echo ==========================================
echo.
echo UYARI: PRODUCTION VERITABANI SIFIRLANACAK!
echo Bu islem CANLI sistemdeki TUM verileri silecek!
echo.
set /p confirm="Gercekten devam etmek istiyor musunuz? PRODUCTION yazin: "
if not "%confirm%"=="PRODUCTION" (
    echo.
    echo Islem iptal edildi.
    color 0B
    pause
    goto MAIN_MENU
)

echo.
echo PRODUCTION veritabani sifirlaniyor...
echo Lutfen bekleyin...
echo.

powershell -Command "try { $r = Invoke-WebRequest -Uri 'https://diapalet-production.up.railway.app/api/terminal/dev-reset' -Method POST -ContentType 'application/json' -Body '{}'; Write-Host 'Basarili:' $r.Content } catch { Write-Host 'Hata:' $_.Exception.Message }"

echo.
echo PRODUCTION veritabani sifirlama islemi tamamlandi.
echo.
echo Test kullanicilari:
echo - foxxafa / 123 (SOUTHALL WAREHOUSE)
echo - test / 123 (SOUTHALL WAREHOUSE)
echo - zeynep.celik / zeynep123 (MANCHESTER WAREHOUSE)
echo.
color 0B
pause
goto MAIN_MENU

:TEST_STAGING
cls
echo.
echo Staging Baglanti Testi
echo ==========================================
echo.
echo Staging ortami test ediliyor...

powershell -Command "try { $r = Invoke-WebRequest -Uri 'https://diapalet-staging.up.railway.app/api/terminal/health-check' -Method GET; Write-Host 'Staging Baglanti:' $r.Content } catch { Write-Host 'Staging Hata:' $_.Exception.Message }"

echo.
echo Staging test tamamlandi.
pause
goto MAIN_MENU

:TEST_PRODUCTION
cls
echo.
echo Production Baglanti Testi
echo ==========================================
echo.
echo Production ortami test ediliyor...

powershell -Command "try { $r = Invoke-WebRequest -Uri 'https://diapalet-production.up.railway.app/api/terminal/health-check' -Method GET; Write-Host 'Production Baglanti:' $r.Content } catch { Write-Host 'Production Hata:' $_.Exception.Message }"

echo.
echo Production test tamamlandi.
pause
goto MAIN_MENU

:TEST_BOTH
cls
echo.
echo Her Iki Ortam Baglanti Testi
echo ==========================================
echo.
echo Staging test ediliyor...
powershell -Command "try { $r = Invoke-WebRequest -Uri 'https://diapalet-staging.up.railway.app/api/terminal/health-check' -Method GET; Write-Host $r.Content } catch { Write-Host 'Hata:' $_.Exception.Message }"

echo.
echo Production test ediliyor...
powershell -Command "try { $r = Invoke-WebRequest -Uri 'https://diapalet-production.up.railway.app/api/terminal/health-check' -Method GET; Write-Host $r.Content } catch { Write-Host 'Hata:' $_.Exception.Message }"

echo.
echo Her iki ortam da test edildi.
pause
goto MAIN_MENU

:EXIT
cls
echo.
echo DIAPALET Manager
echo ==========================================
echo.
echo Tesekkurler! Gorusuruz...
echo.
timeout /t 2 >nul
exit /b 0
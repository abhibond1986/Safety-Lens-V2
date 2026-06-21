@echo off
echo ========================================
echo Regenerating App Icons with Badge Logo
echo ========================================
echo.

cd /d "%~dp0"

echo Running flutter pub get...
call flutter pub get

echo.
echo Generating launcher icons...
call dart run flutter_launcher_icons

echo.
echo ========================================
echo Done! All icons updated with badge logo
echo - Android icons
echo - iOS icons
echo - Web icons (favicon, Icon-192, Icon-512)
echo - Title bar icon
echo ========================================
pause

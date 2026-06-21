@echo off
echo ========================================
echo Regenerating App Icons with Badge Logo
echo ========================================
echo.

cd /d "%~dp0"

echo Step 1: Running flutter pub get...
call flutter pub get

echo.
echo Step 2: Generating launcher icons...
call dart run flutter_launcher_icons

echo.
echo Step 3: Verification...
if exist "web\favicon.png" (
    echo ✓ favicon.png generated
) else (
    echo ✗ favicon.png missing!
)

if exist "web\icons\Icon-192.png" (
    echo ✓ Icon-192.png generated
) else (
    echo ✗ Icon-192.png missing!
)

if exist "web\icons\Icon-512.png" (
    echo ✓ Icon-512.png generated
) else (
    echo ✗ Icon-512.png missing!
)

echo.
echo ========================================
echo Done! All icons updated with badge logo
echo - Android icons (mipmap)
echo - iOS icons (Assets.xcassets)
echo - Web icons (favicon, Icon-192, Icon-512)
echo - Title bar icon
echo ========================================
echo.
echo IMPORTANT: Clear browser cache to see changes!
echo - Windows/Linux: Ctrl + Shift + Delete
echo - Mac: Cmd + Shift + Delete
echo - Or use Incognito/Private mode
echo ========================================
pause

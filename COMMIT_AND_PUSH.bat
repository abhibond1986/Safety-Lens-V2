@echo off
echo ========================================
echo GPS Geo-Tagging - Committing Changes
echo ========================================
echo.

cd /d "%~dp0"

echo Adding all changes...
git add .

echo.
echo Committing with detailed message...
git commit -F FINAL_COMMIT_MESSAGE.txt

echo.
echo Pushing to GitHub...
git push

echo.
echo ========================================
echo Done! Now run: flutter pub get
echo ========================================
pause

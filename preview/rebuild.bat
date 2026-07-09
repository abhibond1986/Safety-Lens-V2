@echo off
echo ═══════════════════════════════════════════
echo   Safety Lens V2 — Preview Builder
echo ═══════════════════════════════════════════
echo.
echo Rebuilding preview/index.html from Dart source...
echo.
node "%~dp0build-preview.js"
echo.
echo Done! Open preview/index.html in your browser.
pause

@echo off
echo ═══════════════════════════════════════════
echo   Safety Lens V2 — Live Preview Watcher
echo ═══════════════════════════════════════════
echo.
echo Watching lib/ for changes...
echo Preview auto-rebuilds when you save any .dart file.
echo Press Ctrl+C to stop.
echo.
node "%~dp0build-preview.js" --watch

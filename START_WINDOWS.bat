@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run the local Lumairie simulator.
  pause
  exit /b 1
)
if not exist "web\index.html" if not exist "apps\mobile\build\web\index.html" (
  echo Flutter Web files are missing. Build them with: flutter build web --release
  pause
  exit /b 1
)
start "Lumairie simulator" /min node "simulator\server.js"
node -e "setTimeout(()=>{},2000)"
start "" "http://localhost:8787"

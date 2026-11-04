@echo off
setlocal
cd /d "%~dp0"
title LUMAIRIE EE04 Windows Preview Uploader
where py >nul 2>&1
if not errorlevel 1 (
  py -3 "%~dp0LUMAIRIE_Installer.py"
  goto done
)
where python >nul 2>&1
if not errorlevel 1 (
  python "%~dp0LUMAIRIE_Installer.py"
  goto done
)
echo Python 3.11 or newer is required for this safe USB uploader.
echo Download from https://www.python.org/downloads/windows/
echo Check "Add Python to PATH" during setup.
start "" "https://www.python.org/downloads/windows/"
:done
echo.
pause
endlocal

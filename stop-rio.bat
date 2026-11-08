@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tray.ps1" -Stop
if errorlevel 1 (
  echo ERROR: Could not stop RIO LIFE OS.
  pause
  exit /b 1
)
echo RIO LIFE OS stopped. It will start again at the next Windows sign-in while startup remains installed.
exit /b 0

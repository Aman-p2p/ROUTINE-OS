@echo off
setlocal
set "RIO_ROOT=%~dp0"
if /i "%~1"=="remove" goto remove

if not exist "%RIO_ROOT%tray.ps1" goto missing
if not exist "%RIO_ROOT%server.ps1" goto missing
if not exist "%RIO_ROOT%index.html" goto missing
if not exist "%RIO_ROOT%start-rio.vbs" goto missing

rem Remove Mark-of-the-Web only from the trusted RIO files in this folder.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop'; $root=$env:RIO_ROOT; Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in '.ps1','.html','.ico','.bat','.vbs' } | Unblock-File -ErrorAction SilentlyContinue"
if errorlevel 1 goto failed

rem Stop any previous RIO controller/server so only the new detached one runs.
powershell -NoProfile -ExecutionPolicy Bypass -File "%RIO_ROOT%tray.ps1" -Stop

rem Generate the tray icon used by the shortcuts.
powershell -NoProfile -ExecutionPolicy Bypass -File "%RIO_ROOT%tray.ps1" -MakeIcon
if errorlevel 1 goto failed

rem Create Startup and Desktop shortcuts that launch via WScript (no console window).
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop'; $root=$env:RIO_ROOT; $vbs=Join-Path $root 'start-rio.vbs'; $icon=Join-Path $root 'rio.ico'; $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'; $startup=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'; $desktop=[Environment]::GetFolderPath('Desktop'); foreach($dir in @($startup,$desktop)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}; $shell=New-Object -ComObject WScript.Shell; foreach($p in @((Join-Path $startup 'RIO LIFE OS.lnk'),(Join-Path $desktop 'RIO LIFE OS.lnk'))){$s=$shell.CreateShortcut($p);$s.TargetPath=$wscript;$s.Arguments='//B //Nologo "'+$vbs+'"';$s.WorkingDirectory=$root;$s.Description='RIO LIFE OS';if(Test-Path -LiteralPath $icon){$s.IconLocation=$icon};$s.Save();if(-not(Test-Path -LiteralPath $p)){throw ('Shortcut creation failed: '+$p)};Write-Host ('Created: '+$p) -ForegroundColor Green}"
if errorlevel 1 goto failed

rem Start RIO detached through WScript; no CMD/PowerShell window remains open.
start "" "%SystemRoot%\System32\wscript.exe" //B //Nologo "%RIO_ROOT%start-rio.vbs"

echo.
echo RIO LIFE OS installed and started.
echo Dashboard opens visibly and appears on the taskbar.
echo Ctrl+Shift+Q = Show / Hide    Ctrl+Shift+R = Quit RIO
exit /b 0

:remove
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$startup=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup';$desktop=[Environment]::GetFolderPath('Desktop');foreach($p in @((Join-Path $startup 'RIO LIFE OS.lnk'),(Join-Path $desktop 'RIO LIFE OS.lnk'))){Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue};Write-Host 'RIO LIFE OS startup and desktop shortcuts removed.'"
call "%RIO_ROOT%stop-rio.bat"
exit /b 0

:missing
echo ERROR: tray.ps1, server.ps1, index.html, or start-rio.vbs is missing from %RIO_ROOT%
pause
exit /b 1
:failed
echo ERROR: RIO installation failed. Review the error above.
pause
exit /b 1

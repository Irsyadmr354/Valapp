@echo off
setlocal
cd /d "%~dp0\.."
powershell -ExecutionPolicy Bypass -File "%~dp0build_release.ps1"
echo.
pause
endlocal

@echo off
:: Stop all background processes started by start-silent.bat / Start-App.ps1
setlocal
set ROOT=%~dp0

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(`pwsh`^) is required but was not found on PATH.
  echo Install PowerShell 7 and rerun this launcher.
  exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Stop-App.ps1"
endlocal

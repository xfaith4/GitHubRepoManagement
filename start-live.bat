@echo off
:: GitHub Repo Management — live launcher (real API, no terminal windows)
:: Delegates entirely to Start-App.ps1 -Mode silent.
:: The only visible result is the app opening in the browser.
setlocal

set "ROOT=%~dp0"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(pwsh^) is required but was not found on PATH.
  echo Install from https://aka.ms/pscore6 and retry.
  pause
  exit /b 1
)

:: Launch Start-App.ps1 in silent mode with a hidden PowerShell window.
:: start "" = required title placeholder; -WindowStyle Hidden = no console shown.
:: The batch exits immediately; Start-App.ps1 handles readiness + browser launch.
IF NOT EXIST "%ROOT%frontend\dist\index.html" (
  start "" pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
    -File "%ROOT%Start-App.ps1" -Mode silent -Rebuild
) ELSE (
  start "" pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
    -File "%ROOT%Start-App.ps1" -Mode silent
)

endlocal

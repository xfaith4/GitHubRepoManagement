@echo off
:: GitHub Repo Management — launcher (alias for start-live.bat)
:: Kept for convenience; delegates to Start-App.ps1 -Mode silent.
setlocal

set "ROOT=%~dp0"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(pwsh^) is required but was not found on PATH.
  echo Install from https://aka.ms/pscore6 and retry.
  pause
  exit /b 1
)

start "" pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
  -File "%ROOT%Start-App.ps1" -Mode silent

endlocal

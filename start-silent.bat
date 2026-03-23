@echo off
:: Start GitHub Repo Management with no visible terminal windows.
:: Backend and frontend run hidden; browser opens automatically.
:: To stop: run stop.bat
::
:: For visible debug terminals use: start-live.bat
:: For PowerShell directly:        .\Start-App.ps1 [-Mode silent|debug]
setlocal
set ROOT=%~dp0

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(`pwsh`^) is required but was not found on PATH.
  echo Install PowerShell 7 and rerun this launcher.
  exit /b 1
)

IF NOT EXIST "%ROOT%frontend\dist\index.html" (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Start-App.ps1" -Mode silent -Rebuild
) ELSE (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Start-App.ps1" -Mode silent
)
endlocal

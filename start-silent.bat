@echo off
:: Start GitHub Repo Management with no visible terminal windows.
:: Backend and frontend run hidden; browser opens automatically.
:: To stop: run stop.bat
::
:: For visible debug terminals use: start-live.bat
:: For PowerShell directly:        .\Start-App.ps1 [-Mode silent|debug]
setlocal
set ROOT=%~dp0
pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Start-App.ps1" -Mode silent
endlocal

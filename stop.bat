@echo off
:: Stop all background processes started by start-silent.bat / Start-App.ps1
setlocal
set ROOT=%~dp0
pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Stop-App.ps1"
endlocal

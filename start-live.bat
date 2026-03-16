@echo off
setlocal

set ROOT=%~dp0
set PS7_EXE=

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(`pwsh`^) is required but was not found on PATH.
  echo Install PowerShell 7 and rerun this launcher.
  exit /b 1
)
set "PS7_EXE=pwsh.exe"

echo ========================================
echo GitHub Repo Management (Live)
echo ========================================

set API_HOST=127.0.0.1
set API_PORT=7071
set API_URL=http://%API_HOST%:%API_PORT%

echo Starting backend API host on %API_URL% ...
start "Repo Management API Host" cmd /k "cd /d %ROOT% && %PS7_EXE% -NoProfile -ExecutionPolicy Bypass -File .\backend\api-host\Start-RepoManagementApiHost.ps1 -BindAddress %API_HOST% -Port %API_PORT%"

echo Waiting for backend readiness...
"%PS7_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ok=$false; for($i=0; $i -lt 20; $i++){ try { Invoke-RestMethod -Uri '%API_URL%/health/live' -Method Get -TimeoutSec 2 | Out-Null; $ok=$true; break } catch { Start-Sleep -Milliseconds 500 } }; if(-not $ok){ exit 1 }"
if errorlevel 1 (
  echo.
  echo ERROR: Backend API host did not become ready at %API_URL%.
  echo Check the "Repo Management API Host" window for startup errors.
  exit /b 1
)

if not exist "%ROOT%frontend\node_modules\" (
  echo Installing frontend dependencies...
  pushd "%ROOT%frontend"
  call npm install
  if errorlevel 1 (
    popd
    echo Failed to install frontend dependencies.
    exit /b 1
  )
  popd
)

set VITE_USE_MOCK_API=false
set VITE_API_PROXY_TARGET=%API_URL%

pushd "%ROOT%frontend"
echo Starting frontend on http://localhost:7000 ...
call npm run dev
popd

endlocal

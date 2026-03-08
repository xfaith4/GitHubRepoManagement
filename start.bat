@echo off
setlocal

set ROOT=%~dp0

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

set VITE_USE_MOCK_API=true
pushd "%ROOT%frontend"
call npm run dev
popd

endlocal

<#
.SYNOPSIS
    Single-entrypoint launcher for GitHub Repo Management.

.DESCRIPTION
    Starts the PowerShell API host and the Vite frontend in one command.
    Two modes are supported:

      silent  (default) — both processes run with no visible terminal windows.
                          All output is captured to log files under
                          backend/modules/output/logs/. The browser opens
                          automatically when both services are ready.

      debug   — backend and frontend each open in a visible terminal window.
                Equivalent to the old start-live.bat two-window workflow.
                Useful for interactive development and troubleshooting.

    Process IDs are written to backend/modules/output/runtime/app.pid so that
    Stop-App.ps1 can terminate them cleanly without hunting for them.

.PARAMETER Mode
    'silent' (default) or 'debug'.

.PARAMETER WorkspaceRoot
    Absolute path to the repository root. Defaults to the directory containing
    this script.

.PARAMETER ApiHost
    Bind address for the API host. Default: 127.0.0.1

.PARAMETER ApiPort
    Port for the API host. Default: 7071

.PARAMETER FrontendPort
    Port Vite binds to. Default: 7000

.PARAMETER NoBrowser
    Suppress automatic browser launch.

.EXAMPLE
    # Normal daily use — no terminal clutter:
    .\Start-App.ps1

    # Developer/debug mode — two visible terminal windows:
    .\Start-App.ps1 -Mode debug

    # Stop everything started by a previous silent run:
    .\Stop-App.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('silent', 'debug')]
    [string]$Mode = 'silent',

    [string]$WorkspaceRoot = $PSScriptRoot,

    [string]$ApiHost = '127.0.0.1',

    [int]$ApiPort = 7071,

    [int]$FrontendPort = 7000,

    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiUrl      = "http://${ApiHost}:${ApiPort}"
$frontendUrl = "http://localhost:${FrontendPort}"

# Runtime / log directories
$runtimeDir  = Join-Path $WorkspaceRoot 'backend\modules\output\runtime'
$logDir      = Join-Path $WorkspaceRoot 'backend\modules\output\logs'
foreach ($d in @($runtimeDir, $logDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        $null = New-Item -ItemType Directory -Path $d -Force
    }
}

$pidFile         = Join-Path $runtimeDir 'app.pid'
$backendLog      = Join-Path $logDir 'backend.log'
$frontendLog     = Join-Path $logDir 'frontend.log'
$backendScript   = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$frontendDir     = Join-Path $WorkspaceRoot 'frontend'

function Write-Step { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Red }

Write-Host ''
Write-Host '====================================' -ForegroundColor White
Write-Host ' GitHub Repo Management' -ForegroundColor White
Write-Host " Mode: $Mode" -ForegroundColor Gray
Write-Host '====================================' -ForegroundColor White
Write-Host ''

# ------------------------------------------------------------------
# 1. Install frontend dependencies if needed
# ------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $frontendDir 'node_modules'))) {
    Write-Step 'Installing frontend dependencies (first run)...'
    Push-Location $frontendDir
    try {
        npm install --silent
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }
    } finally {
        Pop-Location
    }
    Write-Ok 'Frontend dependencies installed.'
}

# ------------------------------------------------------------------
# 2. Start API host
# ------------------------------------------------------------------
Write-Step "Starting API host ($apiUrl) in $Mode mode..."

$backendPid = $null

if ($Mode -eq 'debug') {
    # Open a visible terminal — developer workflow
    Start-Process -FilePath 'pwsh' `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass',
                      '-File', $backendScript,
                      '-WorkspaceRoot', $WorkspaceRoot,
                      '-BindAddress', $ApiHost,
                      '-Port', $ApiPort,
                      '-LogPath', $backendLog `
        -WindowStyle Normal
    # In debug mode we can't easily capture the PID of the inner pwsh started
    # by that process, so we note 0 as a sentinel.
    $backendPid = 0
} else {
    # Silent: hidden window, output redirected to log file
    $proc = Start-Process -FilePath 'pwsh' `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass',
                      '-File', $backendScript,
                      '-WorkspaceRoot', $WorkspaceRoot,
                      '-BindAddress', $ApiHost,
                      '-Port', $ApiPort,
                      '-LogPath', $backendLog `
        -WindowStyle Hidden `
        -RedirectStandardOutput $backendLog `
        -RedirectStandardError  (Join-Path $logDir 'backend-err.log') `
        -PassThru
    $backendPid = $proc.Id
    Write-Ok "API host started (PID $backendPid). Log: $backendLog"
}

# ------------------------------------------------------------------
# 3. Wait for API host to become ready
# ------------------------------------------------------------------
Write-Step 'Waiting for API host readiness...'

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $null = Invoke-RestMethod -Uri "$apiUrl/health/live" -Method Get -TimeoutSec 2
        $ready = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $ready) {
    Write-Fail "API host did not respond at $apiUrl within 15 s."
    if ($Mode -eq 'silent') {
        Write-Host "  Check: $backendLog" -ForegroundColor Yellow
    }
    exit 1
}
Write-Ok "API host ready at $apiUrl"

# ------------------------------------------------------------------
# 4. Start frontend (Vite dev server)
# ------------------------------------------------------------------
Write-Step "Starting frontend ($frontendUrl) in $Mode mode..."

$env:VITE_USE_MOCK_API        = 'false'
$env:VITE_API_PROXY_TARGET    = $apiUrl

$frontendPid = $null

if ($Mode -eq 'debug') {
    Start-Process -FilePath 'cmd.exe' `
        -ArgumentList '/k', "cd /d `"$frontendDir`" && npm run dev" `
        -WindowStyle Normal
    $frontendPid = 0
} else {
    # Write a tiny wrapper so we can set env vars before npm run dev in the hidden window
    $wrapperPath = Join-Path $runtimeDir 'start-frontend.ps1'
    @"
`$env:VITE_USE_MOCK_API     = 'false'
`$env:VITE_API_PROXY_TARGET = '$apiUrl'
Set-Location '$frontendDir'
npm run dev *>&1 | Out-File -FilePath '$frontendLog' -Encoding UTF8 -Append
"@ | Set-Content -LiteralPath $wrapperPath -Encoding UTF8

    $proc = Start-Process -FilePath 'pwsh' `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath `
        -WindowStyle Hidden `
        -PassThru
    $frontendPid = $proc.Id
    Write-Ok "Frontend started (PID $frontendPid). Log: $frontendLog"
}

# ------------------------------------------------------------------
# 5. Wait for frontend to respond
# ------------------------------------------------------------------
Write-Step 'Waiting for frontend readiness...'

$feReady = $false
for ($i = 0; $i -lt 40; $i++) {
    try {
        $null = Invoke-WebRequest -Uri $frontendUrl -Method Get -TimeoutSec 2 -UseBasicParsing
        $feReady = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $feReady) {
    Write-Fail "Frontend did not respond at $frontendUrl within 20 s."
    if ($Mode -eq 'silent') {
        Write-Host "  Check: $frontendLog" -ForegroundColor Yellow
    }
    exit 1
}
Write-Ok "Frontend ready at $frontendUrl"

# ------------------------------------------------------------------
# 6. Write PID file for Stop-App.ps1
# ------------------------------------------------------------------
@{
    backendPid  = $backendPid
    frontendPid = $frontendPid
    mode        = $Mode
    apiUrl      = $apiUrl
    frontendUrl = $frontendUrl
    startedAt   = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding UTF8

# ------------------------------------------------------------------
# 7. Open browser
# ------------------------------------------------------------------
if (-not $NoBrowser) {
    Start-Process $frontendUrl
    Write-Ok "Browser opened at $frontendUrl"
}

Write-Host ''
Write-Host '  App is running.' -ForegroundColor Green

if ($Mode -eq 'silent') {
    Write-Host "  Logs : $logDir" -ForegroundColor Gray
    Write-Host '  Stop : .\Stop-App.ps1' -ForegroundColor Gray
} else {
    Write-Host '  Close the terminal windows to stop.' -ForegroundColor Gray
}
Write-Host ''

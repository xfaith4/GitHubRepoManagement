<#
.SYNOPSIS
    Single-entrypoint launcher for GitHub Repo Management.

.DESCRIPTION
    Starts the PowerShell API host and optionally the Vite frontend in one command.

    Two modes are supported:

      silent  (default) — both processes run with no visible terminal windows.
                          All output is captured to log files under
                          backend/modules/output/logs/. The browser opens
                          automatically when both services are ready.

      debug   — backend (and frontend when using Vite) each open in a visible
                terminal window. Useful for interactive development.

    Production frontend bundle (Release 1.3):
      If frontend/dist/index.html exists and -Dev is not passed, the compiled
      bundle is served directly by the API host. No Vite process is started.

      Pass -Rebuild to force a fresh 'npm run build' even if dist/ already exists.
      Pass -Dev to always use the Vite dev server regardless of dist/ state.

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
    Port Vite binds to. Default: 7000 (only used when running Vite).

.PARAMETER NoBrowser
    Suppress automatic browser launch.

.PARAMETER Dev
    Force Vite dev server even if frontend/dist/ is built. Useful when actively
    developing frontend code.

.PARAMETER Rebuild
    Force 'npm run build' before starting, even if frontend/dist/index.html exists.

.EXAMPLE
    # Normal daily use — no terminal clutter, static bundle served by API host:
    .\Start-App.ps1

    # Force a fresh frontend build then start:
    .\Start-App.ps1 -Rebuild

    # Use Vite dev server (hot reload) for frontend development:
    .\Start-App.ps1 -Dev

    # Developer/debug mode with Vite:
    .\Start-App.ps1 -Mode debug -Dev

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

    [switch]$NoBrowser,

    [switch]$Dev,

    [switch]$Rebuild
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
$distIndexHtml   = Join-Path $frontendDir 'dist\index.html'

function Write-Step { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Red }

function Get-ListeningProcessIds {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LocalPort
    )

    $processIds = @()

    $getNetTcpConnection = Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue
    if ($getNetTcpConnection) {
        try {
            $connections = @(Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction Stop)
            if ($connections.Count -gt 0) {
                return @($connections | Select-Object -ExpandProperty OwningProcess -Unique)
            }
        } catch { }
    }

    $ssCommand = Get-Command -Name 'ss' -ErrorAction SilentlyContinue
    if ($ssCommand) {
        foreach ($line in @(ss -ltnpH "sport = :$LocalPort" 2>$null)) {
            foreach ($match in [regex]::Matches($line, 'pid=(\d+)')) {
                $processIds += [int]$match.Groups[1].Value
            }
        }

        if ($processIds.Count -gt 0) {
            return @($processIds | Sort-Object -Unique)
        }
    }

    $netstatCommand = Get-Command -Name 'netstat' -ErrorAction SilentlyContinue
    if (-not $netstatCommand) {
        return @()
    }

    foreach ($line in @(netstat -ano -p tcp 2>$null)) {
        $trimmed = $line.Trim()
        if ($trimmed -notmatch '^TCP\s+') { continue }

        $parts = $trimmed -split '\s+'
        if ($parts.Count -lt 5) { continue }
        if ($parts[3] -ne 'LISTENING') { continue }

        $localAddress = $parts[1]
        $separatorIndex = $localAddress.LastIndexOf(':')
        if ($separatorIndex -lt 0) { continue }

        $portText = $localAddress.Substring($separatorIndex + 1)
        if ($portText -ne [string]$LocalPort) { continue }

        if ($parts[4] -match '^\d+$') {
            $processIds += [int]$parts[4]
        }
    }

    return @($processIds | Sort-Object -Unique)
}

function Stop-PortListeners {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LocalPort,
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    $listenerPids = @(Get-ListeningProcessIds -LocalPort $LocalPort | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)
    if ($listenerPids.Count -eq 0) {
        return
    }

    foreach ($listenerPid in $listenerPids) {
        $processLabel = "PID $listenerPid"
        try {
            $process = Get-Process -Id $listenerPid -ErrorAction Stop
            $processLabel = "$($process.ProcessName) (PID $listenerPid)"
        } catch { }

        Write-Step "$ServiceName needs port $LocalPort. Terminating $processLabel."

        try {
            Stop-Process -Id $listenerPid -Force -ErrorAction Stop
        } catch {
            throw "$ServiceName needs port $LocalPort, but $processLabel could not be terminated. $($_.Exception.Message)"
        }

        $released = $false
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 250
            $remaining = @(Get-ListeningProcessIds -LocalPort $LocalPort | Where-Object { $_ -eq $listenerPid })
            if ($remaining.Count -eq 0) {
                $released = $true
                break
            }
        }

        if (-not $released) {
            throw "Terminated $processLabel for $ServiceName, but port $LocalPort is still reported as in use."
        }

        Write-Ok "$ServiceName reclaimed port $LocalPort from $processLabel"
    }
}

Write-Host ''
Write-Host '====================================' -ForegroundColor White
Write-Host ' GitHub Repo Management' -ForegroundColor White
Write-Host " Mode: $Mode$(if ($Dev) { ' [Dev/Vite]' } elseif ($Rebuild) { ' [Rebuild]' })" -ForegroundColor Gray
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
# 2. Build frontend (Release 1.3) — skip when -Dev forces Vite
# ------------------------------------------------------------------
$servingFromDist = $false

if ($Dev) {
    Write-Step 'Dev mode: Vite dev server will be used (skipping production build).'
} else {
    $needsBuild = $Rebuild -or -not (Test-Path -LiteralPath $distIndexHtml)
    if ($needsBuild) {
        $buildReason = if ($Rebuild) { 'forced by -Rebuild' } else { 'frontend/dist/ not found' }
        Write-Step "Building frontend ($buildReason)..."
        Push-Location $frontendDir
        try {
            npm run build
            if ($LASTEXITCODE -ne 0) { throw 'npm run build failed. Check frontend build errors above.' }
        } finally {
            Pop-Location
        }
        Write-Ok 'Frontend built to frontend/dist/.'
    }

    if (Test-Path -LiteralPath $distIndexHtml) {
        $servingFromDist = $true
        Write-Ok 'Production build found — API host will serve the static frontend bundle.'
    } else {
        Write-Step 'No production build available — falling back to Vite dev server.'
    }
}

# ------------------------------------------------------------------
# 3. Start API host
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
# 4. Wait for API host to become ready
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
# 5. Start Vite dev server — only when not serving from built dist/
# ------------------------------------------------------------------
$frontendPid = $null

if ($servingFromDist) {
    # No Vite process needed — API host serves the static bundle at the API URL
    $frontendPid = 0
    $frontendUrl = $apiUrl
    Write-Ok "Static frontend available at $frontendUrl"
} else {
    Write-Step "Starting Vite dev server ($frontendUrl) in $Mode mode..."
    Stop-PortListeners -LocalPort $FrontendPort -ServiceName 'Frontend'

    $env:VITE_API_PROXY_TARGET = $apiUrl

    if ($Mode -eq 'debug') {
        Start-Process -FilePath 'cmd.exe' `
            -ArgumentList '/k', "cd /d `"$frontendDir`" && npm run dev -- --port $FrontendPort" `
            -WindowStyle Normal
        $frontendPid = 0
    } else {
        # Write a tiny wrapper so we can set env vars before npm run dev in the hidden window
        $wrapperPath = Join-Path $runtimeDir 'start-frontend.ps1'
        @"
`$env:VITE_API_PROXY_TARGET = '$apiUrl'
Set-Location '$frontendDir'
npm run dev -- --port $FrontendPort *>&1 | Out-File -FilePath '$frontendLog' -Encoding UTF8 -Append
"@ | Set-Content -LiteralPath $wrapperPath -Encoding UTF8

        $proc = Start-Process -FilePath 'pwsh' `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath `
            -WindowStyle Hidden `
            -PassThru
        $frontendPid = $proc.Id
        Write-Ok "Vite dev server started (PID $frontendPid). Log: $frontendLog"
    }

    # ------------------------------------------------------------------
    # 6. Wait for Vite to respond
    # ------------------------------------------------------------------
    Write-Step 'Waiting for Vite dev server readiness...'

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
        Write-Fail "Vite dev server did not respond at $frontendUrl within 20 s."
        if ($Mode -eq 'silent') {
            Write-Host "  Check: $frontendLog" -ForegroundColor Yellow
        }
        exit 1
    }
    Write-Ok "Vite dev server ready at $frontendUrl"
}

# ------------------------------------------------------------------
# 7. Write PID file for Stop-App.ps1
# ------------------------------------------------------------------
@{
    backendPid     = $backendPid
    frontendPid    = $frontendPid
    mode           = $Mode
    servingFromDist = $servingFromDist
    apiUrl         = $apiUrl
    frontendUrl    = $frontendUrl
    startedAt      = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding UTF8

# ------------------------------------------------------------------
# 8. Open browser
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
if ($servingFromDist) {
    Write-Host "  Serving built frontend — run '.\Start-App.ps1 -Dev' to use Vite hot-reload." -ForegroundColor Gray
}
Write-Host ''

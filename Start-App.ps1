<#
.SYNOPSIS
    Single-entrypoint launcher for GitHub Repo Management.

.DESCRIPTION
    Starts the PowerShell API host and optionally the Vite frontend in one command.

    Two modes are supported:

    silent  (default) - both processes run with no visible terminal windows.
    All output is captured to log files under
    backend/modules/output/logs/. The browser opens
    automatically when both services are ready.

    debug   - backend (and frontend when using Vite) each open in a visible
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
    Bind address for the API host. Default: 0.0.0.0

.PARAMETER AppHost
    Hostname or IP that browsers on the LAN should use to reach the app.
    Defaults to 192.168.50.200 when ApiHost binds all interfaces; otherwise
    defaults to ApiHost.

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
    # Normal daily use - no terminal clutter, static bundle served by API host:
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

    [string]$WorkspaceRoot = '',

    [string]$ApiHost = '0.0.0.0',

    [string]$AppHost = '',

    [int]$ApiPort = 7071,

    [int]$FrontendPort = 7000,

    [switch]$NoBrowser,

    [switch]$Dev,

    [switch]$Rebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    if ($PSCommandPath) {
        $WorkspaceRoot = Split-Path -Parent $PSCommandPath
    }
    elseif ($MyInvocation.MyCommand.Path) {
        $WorkspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    else {
        $WorkspaceRoot = (Get-Location).Path
    }
}

$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

function Resolve-LocalProbeHost {
    param([Parameter(Mandatory = $true)][string]$BindAddress)

    switch ($BindAddress) {
        '0.0.0.0' { return '127.0.0.1' }
        '::' { return '::1' }
        '[::]' { return '::1' }
        default { return $BindAddress }
    }
}

$defaultLanHost = '192.168.50.200'
$apiProbeHost = Resolve-LocalProbeHost -BindAddress $ApiHost
$resolvedAppHost = if (-not [string]::IsNullOrWhiteSpace($AppHost)) {
    $AppHost
}
elseif ($ApiHost -in @('0.0.0.0', '::', '[::]')) {
    $defaultLanHost
}
else {
    $ApiHost
}

$apiProbeUrl = "http://${apiProbeHost}:${ApiPort}"
$apiPublicUrl = "http://${resolvedAppHost}:${ApiPort}"
$frontendProbeUrl = "http://127.0.0.1:${FrontendPort}"
$frontendUrl = "http://${resolvedAppHost}:${FrontendPort}"

# Runtime / log directories
$runtimeDir = Join-Path $WorkspaceRoot 'backend\modules\output\runtime'
$logDir = Join-Path $WorkspaceRoot 'backend\modules\output\logs'
foreach ($d in @($runtimeDir, $logDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        $null = New-Item -ItemType Directory -Path $d -Force
    }
}

$pidFile = Join-Path $runtimeDir 'app.pid'
$backendLog = Join-Path $logDir 'backend.log'
$frontendLog = Join-Path $logDir 'frontend.log'
$backendScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$frontendDir = Join-Path $WorkspaceRoot 'frontend'
$distIndexHtml = Join-Path $frontendDir 'dist\index.html'
$supportsWindowStyle = ($PSVersionTable.PSEdition -eq 'Desktop') -or (
    (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) -and [bool](Get-Variable -Name 'IsWindows' -ValueOnly)
)

function Write-Step { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Red }

# Track processes this launcher starts so a partial/failed startup can be
# cleaned up instead of leaving orphaned backend/frontend processes behind.
$script:StartedPids = [System.Collections.Generic.List[int]]::new()

function Register-StartedPid {
    param([int]$ProcessId)
    if ($ProcessId -gt 0) { [void]$script:StartedPids.Add($ProcessId) }
}

function Stop-StartedProcesses {
    foreach ($startedPid in $script:StartedPids) {
        try {
            $proc = Get-Process -Id $startedPid -ErrorAction Stop
            Stop-Process -Id $startedPid -Force -ErrorAction Stop
            Write-Step "Cleaned up $($proc.ProcessName) (PID $startedPid) after a failed startup."
        }
        catch { }
    }
}

# Write the PID file as soon as we know any process IDs, so Stop-App.ps1 can
# always reclaim what was started — even if startup fails partway through.
function Write-PidFile {
    param(
        [int]$BackendPid = 0,
        [Nullable[int]]$FrontendPid = $null,
        [bool]$ServingFromDist = $false,
        [string]$ResolvedFrontendUrl = ''
    )
    @{
        backendPid      = $BackendPid
        frontendPid     = $FrontendPid
        mode            = $Mode
        servingFromDist = $ServingFromDist
        apiUrl          = $apiPublicUrl
        apiProbeUrl     = $apiProbeUrl
        frontendUrl     = $ResolvedFrontendUrl
        startedAt       = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding UTF8
}

# Stale-bundle guard: returns $true when any frontend source file is newer than
# the built dist/index.html, meaning the served bundle would be out of date.
# Serving a stale bundle silently is the #1 "my fix isn't showing up" foot-gun.
function Test-FrontendBuildStale {
    param(
        [Parameter(Mandatory = $true)][string]$FrontendDir,
        [Parameter(Mandatory = $true)][string]$DistIndexHtml
    )

    if (-not (Test-Path -LiteralPath $DistIndexHtml)) { return $true }
    $distTime = (Get-Item -LiteralPath $DistIndexHtml).LastWriteTimeUtc

    # Top-level source/config files plus the known source subdirectories.
    $sourceFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($f in (Get-ChildItem -LiteralPath $FrontendDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.ts', '.tsx', '.html', '.css', '.json', '.js', '.cjs', '.mjs' -and $_.Name -ne 'package-lock.json' })) {
        [void]$sourceFiles.Add($f)
    }
    foreach ($sub in @('components', 'services', 'hooks', 'src', 'styles', 'lib')) {
        $subPath = Join-Path $FrontendDir $sub
        if (Test-Path -LiteralPath $subPath) {
            foreach ($f in (Get-ChildItem -LiteralPath $subPath -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in '.ts', '.tsx', '.css', '.js', '.json' })) {
                [void]$sourceFiles.Add($f)
            }
        }
    }

    if ($sourceFiles.Count -eq 0) { return $false }
    $newest = ($sourceFiles | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    return ($newest -gt $distTime)
}

function Convert-ToShellLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $escapedSingleQuote = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
    return $singleQuote + ($Value -replace [regex]::Escape($singleQuote), $escapedSingleQuote) + $singleQuote
}

function Start-DetachedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [string]$RedirectStandardOutput,
        [string]$RedirectStandardError
    )

    $commandParts = @($FilePath) + $ArgumentList
    $escapedCommand = ($commandParts | ForEach-Object { Convert-ToShellLiteral -Value $_ }) -join ' '
    $stdoutTarget = if ($RedirectStandardOutput) { Convert-ToShellLiteral -Value $RedirectStandardOutput } else { '/dev/null' }
    $stderrClause = if ($RedirectStandardError) {
        "2>> $(Convert-ToShellLiteral -Value $RedirectStandardError)"
    }
    else {
        '2>&1'
    }
    $launcherPrefix = if (Get-Command -Name 'setsid' -ErrorAction SilentlyContinue) { 'setsid nohup' } else { 'nohup' }
    $launchCommand = "$launcherPrefix $escapedCommand >> $stdoutTarget $stderrClause < /dev/null & echo `$!"
    $pidText = & bash -lc $launchCommand
    $detachedPid = 0
    $parsedPid = [int]::TryParse(([string]$pidText).Trim(), [ref]$detachedPid)
    if (-not $parsedPid -or $detachedPid -le 0) {
        throw "Detached launch did not return a valid PID for $FilePath."
    }

    return [pscustomobject]@{ Id = $detachedPid }
}

function Start-ManagedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [ValidateSet('Hidden', 'Normal')]
        [string]$WindowStyle = 'Normal',
        [string]$RedirectStandardOutput,
        [string]$RedirectStandardError,
        [switch]$PassThru
    )

    if (-not $supportsWindowStyle) {
        return Start-DetachedProcess `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -RedirectStandardOutput $RedirectStandardOutput `
            -RedirectStandardError $RedirectStandardError
    }

    $params = @{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
    }

    if ($PassThru) {
        $params.PassThru = $true
    }

    if ($RedirectStandardOutput) {
        $params.RedirectStandardOutput = $RedirectStandardOutput
    }

    if ($RedirectStandardError) {
        $params.RedirectStandardError = $RedirectStandardError
    }

    if ($supportsWindowStyle) {
        $params.WindowStyle = $WindowStyle
    }

    return Start-Process @params
}

function New-FrontendWrapperScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WrapperPath,
        [Parameter(Mandatory = $true)]
        [string]$ApiUrl,
        [Parameter(Mandatory = $true)]
        [string]$FrontendDir,
        [Parameter(Mandatory = $true)]
        [int]$FrontendPort,
        [string]$FrontendLogPath
    )

    $npmCommand = if ($FrontendLogPath) {
        @"
`$env:VITE_API_PROXY_TARGET = '$ApiUrl'
Set-Location '$FrontendDir'
npm run dev -- --port $FrontendPort *>&1 | Out-File -FilePath '$FrontendLogPath' -Encoding UTF8 -Append
"@
    }
    else {
        @"
`$env:VITE_API_PROXY_TARGET = '$ApiUrl'
Set-Location '$FrontendDir'
npm run dev -- --port $FrontendPort
"@
    }

    $npmCommand | Set-Content -LiteralPath $WrapperPath -Encoding UTF8
}

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
        }
        catch { }
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
        }
        catch { }

        Write-Step "$ServiceName needs port $LocalPort. Terminating $processLabel."

        try {
            Stop-Process -Id $listenerPid -Force -ErrorAction Stop
        }
        catch {
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
Write-Host " Access: $apiPublicUrl" -ForegroundColor Gray
Write-Host '====================================' -ForegroundColor White
Write-Host ''

if (-not $supportsWindowStyle -and $Mode -eq 'debug') {
    Write-Step 'Debug terminal windows are not available on this PowerShell edition; starting detached child processes instead.'
}

# ------------------------------------------------------------------
# 1. Install frontend dependencies if needed
# ------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $frontendDir 'node_modules'))) {
    Write-Step 'Installing frontend dependencies (first run)...'
    Push-Location $frontendDir
    try {
        npm install --silent
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }
    }
    finally {
        Pop-Location
    }
    Write-Ok 'Frontend dependencies installed.'
}

# ------------------------------------------------------------------
# 2. Build frontend (Release 1.3) - skip when -Dev forces Vite
# ------------------------------------------------------------------
$servingFromDist = $false

if ($Dev) {
    Write-Step 'Dev mode: Vite dev server will be used (skipping production build).'
}
else {
    $buildReason = ''
    if ($Rebuild) {
        $buildReason = 'forced by -Rebuild'
    }
    elseif (-not (Test-Path -LiteralPath $distIndexHtml)) {
        $buildReason = 'frontend/dist/ not found'
    }
    elseif (Test-FrontendBuildStale -FrontendDir $frontendDir -DistIndexHtml $distIndexHtml) {
        # The served bundle is older than the source — rebuild so the running
        # app actually reflects the current code instead of a stale dist.
        $buildReason = 'frontend source changed since last build'
    }
    $needsBuild = -not [string]::IsNullOrEmpty($buildReason)

    if ($needsBuild) {
        Write-Step "Building frontend ($buildReason)..."
        Push-Location $frontendDir
        try {
            npm run build
            if ($LASTEXITCODE -ne 0) { throw 'npm run build failed. Check frontend build errors above.' }
        }
        finally {
            Pop-Location
        }
        Write-Ok 'Frontend built to frontend/dist/.'
    }

    if (Test-Path -LiteralPath $distIndexHtml) {
        $servingFromDist = $true
        Write-Ok 'Production build found - API host will serve the static frontend bundle.'
    }
    else {
        Write-Step 'No production build available - falling back to Vite dev server.'
    }
}

# ------------------------------------------------------------------
# 3. Start API host
# ------------------------------------------------------------------
Write-Step "Starting API host (bind ${ApiHost}:${ApiPort}, access $apiPublicUrl) in $Mode mode..."

$backendPid = $null

if ($Mode -eq 'debug') {
    # Open a visible terminal - developer workflow
    $proc = Start-ManagedProcess `
        -FilePath 'pwsh' `
        -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $backendScript,
        '-WorkspaceRoot', $WorkspaceRoot,
        '-BindAddress', $ApiHost,
        '-Port', $ApiPort,
        '-LogPath', $backendLog
    ) `
        -WindowStyle Normal `
        -PassThru
    $backendPid = if ($supportsWindowStyle) { 0 } else { $proc.Id }
}
else {
    # Silent: hidden window, output redirected to log file
    $proc = Start-ManagedProcess `
        -FilePath 'pwsh' `
        -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $backendScript,
        '-WorkspaceRoot', $WorkspaceRoot,
        '-BindAddress', $ApiHost,
        '-Port', $ApiPort,
        '-LogPath', $backendLog
    ) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $backendLog `
        -RedirectStandardError (Join-Path $logDir 'backend-err.log') `
        -PassThru
    $backendPid = $proc.Id
    Write-Ok "API host started (PID $backendPid). Log: $backendLog"
}

# Record the backend PID now so a hung backend can still be stopped by
# Stop-App.ps1, even if readiness below never succeeds.
if ($backendPid -gt 0) {
    Register-StartedPid -ProcessId $backendPid
    Write-PidFile -BackendPid $backendPid -FrontendPid $null -ServingFromDist $servingFromDist -ResolvedFrontendUrl $frontendUrl
}

# ------------------------------------------------------------------
# 4. Wait for API host to become ready
# ------------------------------------------------------------------
Write-Step 'Waiting for API host readiness...'

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $null = Invoke-RestMethod -Uri "$apiProbeUrl/health/live" -Method Get -TimeoutSec 2
        $ready = $true
        break
    }
    catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $ready) {
    Write-Fail "API host did not respond locally at $apiProbeUrl within 15 s."
    if ($Mode -eq 'silent') {
        Write-Host "  Check: $backendLog" -ForegroundColor Yellow
    }
    Stop-StartedProcesses
    exit 1
}
Write-Ok "API host ready at $apiPublicUrl"

# ------------------------------------------------------------------
# 5. Start Vite dev server - only when not serving from built dist/
# ------------------------------------------------------------------
$frontendPid = $null

if ($servingFromDist) {
    # No Vite process needed - API host serves the static bundle at the API URL
    $frontendPid = 0
    $frontendUrl = $apiPublicUrl
    Write-Ok "Static frontend available at $frontendUrl"
}
else {
    Write-Step "Starting Vite dev server ($frontendUrl) in $Mode mode..."
    Stop-PortListeners -LocalPort $FrontendPort -ServiceName 'Frontend'

    $env:VITE_API_PROXY_TARGET = $apiProbeUrl

    if ($Mode -eq 'debug') {
        if ($supportsWindowStyle) {
            $proc = Start-ManagedProcess `
                -FilePath 'cmd.exe' `
                -ArgumentList @('/k', "cd /d `"$frontendDir`" && npm run dev -- --port $FrontendPort") `
                -WindowStyle Normal `
                -PassThru
            $frontendPid = 0
        }
        else {
            $wrapperPath = Join-Path $runtimeDir 'start-frontend.ps1'
            New-FrontendWrapperScript -WrapperPath $wrapperPath -ApiUrl $apiProbeUrl -FrontendDir $frontendDir -FrontendPort $FrontendPort
            $proc = Start-ManagedProcess `
                -FilePath 'pwsh' `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath) `
                -PassThru
            $frontendPid = $proc.Id
            Write-Ok "Frontend started (PID $frontendPid)."
        }
    }
    else {
        # Write a tiny wrapper so we can set env vars before npm run dev in the hidden window
        $wrapperPath = Join-Path $runtimeDir 'start-frontend.ps1'
        New-FrontendWrapperScript -WrapperPath $wrapperPath -ApiUrl $apiProbeUrl -FrontendDir $frontendDir -FrontendPort $FrontendPort -FrontendLogPath $frontendLog

        $proc = Start-ManagedProcess `
            -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath) `
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
            $null = Invoke-WebRequest -Uri $frontendProbeUrl -Method Get -TimeoutSec 2 -UseBasicParsing
            $feReady = $true
            break
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $feReady) {
        Write-Fail "Vite dev server did not respond locally at $frontendProbeUrl within 20 s."
        if ($Mode -eq 'silent') {
            Write-Host "  Check: $frontendLog" -ForegroundColor Yellow
        }
        Stop-StartedProcesses
        exit 1
    }
    Write-Ok "Vite dev server ready at $frontendUrl"
}

# Record the frontend PID alongside the backend so Stop-App.ps1 can reclaim both.
if ($frontendPid -gt 0) {
    Register-StartedPid -ProcessId $frontendPid
}

# ------------------------------------------------------------------
# 7. Write PID file for Stop-App.ps1 (final, with both PIDs + resolved URL)
# ------------------------------------------------------------------
Write-PidFile -BackendPid $backendPid -FrontendPid $frontendPid -ServingFromDist $servingFromDist -ResolvedFrontendUrl $frontendUrl

# ------------------------------------------------------------------
# 8. Open browser
# ------------------------------------------------------------------
if (-not $NoBrowser) {
    try {
        Start-Process $frontendUrl
        Write-Ok "Browser opened at $frontendUrl"
    }
    catch {
        Write-Step "App is ready, but automatic browser launch failed: $($_.Exception.Message)"
        Write-Host "  Open manually: $frontendUrl" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '  App is running.' -ForegroundColor Green

if ($Mode -eq 'silent') {
    Write-Host "  Logs : $logDir" -ForegroundColor Gray
    Write-Host '  Stop : .\Stop-App.ps1' -ForegroundColor Gray
}
else {
    Write-Host '  Close the terminal windows to stop.' -ForegroundColor Gray
}
if ($servingFromDist) {
    Write-Host "  Serving built frontend - run '.\Start-App.ps1 -Dev' to use Vite hot-reload." -ForegroundColor Gray
}
Write-Host ''

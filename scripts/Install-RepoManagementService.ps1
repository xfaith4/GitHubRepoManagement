#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the GitHub Repo Management portal as an always-on Windows service.

.DESCRIPTION
    Wraps the PowerShell API host (backend/api-host/Start-RepoManagementApiHost.ps1)
    as a Windows service using Shawl (https://github.com/mtkennerly/shawl) so the
    portal:

      * starts automatically at boot, BEFORE any user logs in (fully unattended);
      * restarts automatically if the host process exits or crashes;
      * captures stdout/stderr to backend/modules/output/logs/.

    A single process serves BOTH the API and the compiled frontend bundle
    (frontend/dist), so no Vite/Node runtime is needed at service runtime — only
    pwsh. This mirrors what the Dockerfile does, but native to this Windows host.

    The script is idempotent: re-running it stops, removes, and recreates the
    service with the current settings.

    WHY SHAWL: a PowerShell script cannot register as a Windows service directly
    (a service binary must speak the Service Control Manager protocol). Shawl is a
    tiny supervisor .exe that does — it launches, monitors, restarts, and log-
    captures the pwsh host, and the SCM sees a well-behaved service.

.PARAMETER WorkspaceRoot
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER ServiceName
    Windows service name. Default: RepoMgmtPortal.

.PARAMETER DisplayName
    Friendly name shown in services.msc. Default: 'GitHub Repo Management Portal'.

.PARAMETER BindAddress
    Address the API host binds. Default 0.0.0.0 (reachable across the LAN).
    Use 127.0.0.1 to keep it local-only.

.PARAMETER Port
    TCP port. Default: 7071.

.PARAMETER ShawlPath
    Path to shawl.exe. If omitted, the script looks on PATH, then in
    <root>\tools\shawl.exe. If not found it prints install instructions and stops.

.PARAMETER AllowInsecureBind
    Acknowledge binding a non-loopback address WITHOUT API-key auth. Required when
    BindAddress is not loopback and settings.json does not set auth.requireApiKey.
    Sets REPO_MGMT_ALLOW_INSECURE_BIND=true for the service (single-operator LAN).

.PARAMETER GitHubToken
    Optional GitHub token. Injected as the GITHUB_TOKEN environment variable for
    the service only (a LocalSystem service does NOT inherit your user env). If
    omitted, GitHub-authenticated features are unavailable until you provide one.

.PARAMETER PfxPath
    Path to a TLS certificate (.pfx). When supplied, the host serves HTTPS and the
    installer injects REPO_MGMT_TLS_PFX / REPO_MGMT_TLS_PFX_PASSWORD for the
    service. Generate one with New-RepoManagementTlsCertificate.ps1, or point at a
    PFX from a real CA / ACME client (e.g. win-acme). Omit to serve plain HTTP.

.PARAMETER PfxPassword
    Password for the PFX. Injected for the service process only.

.PARAMETER Credential
    Optional run-as account for the service. Default is LocalSystem (no password,
    fully unattended, can read local repos). Provide a credential to run least-
    privilege instead.

.PARAMETER SkipBuild
    Skip the frontend production-build check. The service will still start, but the
    dashboard is only served once frontend/dist/index.html exists.

.EXAMPLE
    # LAN-reachable, acknowledging the unauthenticated bind (single operator):
    .\scripts\Install-RepoManagementService.ps1 -AllowInsecureBind

.EXAMPLE
    # Local-only, no acknowledgment needed:
    .\scripts\Install-RepoManagementService.ps1 -BindAddress 127.0.0.1

.EXAMPLE
    # With a GitHub token for authenticated features:
    .\scripts\Install-RepoManagementService.ps1 -AllowInsecureBind -GitHubToken $env:GITHUB_TOKEN
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = '',
    [string]$ServiceName = 'RepoMgmtPortal',
    [string]$DisplayName = 'GitHub Repo Management Portal',
    [string]$BindAddress = '0.0.0.0',
    [int]$Port = 7071,
    [string]$ShawlPath = '',
    [switch]$AllowInsecureBind,
    [string]$ApiKey = '',
    [string]$GitHubToken = '',
    [string]$PfxPath = '',
    [string]$PfxPassword = '',
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$m) Write-Host "  $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# 0. Resolve paths
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$logDir     = Join-Path $WorkspaceRoot 'backend\modules\output\logs'
$distIndex  = Join-Path $WorkspaceRoot 'frontend\dist\index.html'
$settings   = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$apiLog     = Join-Path $logDir 'apihost.log'

if (-not (Test-Path -LiteralPath $hostScript)) {
    throw "API host script not found at $hostScript. Is -WorkspaceRoot correct?"
}
if (-not (Test-Path -LiteralPath $logDir)) {
    $null = New-Item -ItemType Directory -Path $logDir -Force
}

Write-Host ''
Write-Host '====================================' -ForegroundColor White
Write-Host ' Install: Repo Management Portal service' -ForegroundColor White
Write-Host "  Service : $ServiceName" -ForegroundColor Gray
Write-Host "  Bind    : ${BindAddress}:${Port}" -ForegroundColor Gray
Write-Host "  Root    : $WorkspaceRoot" -ForegroundColor Gray
Write-Host '====================================' -ForegroundColor White
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Resolve the pwsh 7 executable the service will run
# ---------------------------------------------------------------------------
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    throw 'pwsh (PowerShell 7) not found on PATH. Install it (winget install --id Microsoft.PowerShell) and retry.'
}
$pwshExe = $pwshCmd.Source
Write-Ok "PowerShell host: $pwshExe"

# ---------------------------------------------------------------------------
# 2. Frontend bundle check — the service serves the static dist, no Vite
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    if (Test-Path -LiteralPath $distIndex) {
        Write-Ok 'Frontend bundle present (frontend/dist) — dashboard will be served.'
    }
    else {
        Write-Step 'Frontend bundle missing — building (npm run build)...'
        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npm) {
            throw 'frontend/dist not found and npm is unavailable. Build the frontend first (npm ci && npm run build in frontend\) or pass -SkipBuild to install the API-only service.'
        }
        Push-Location (Join-Path $WorkspaceRoot 'frontend')
        try {
            if (-not (Test-Path 'node_modules')) { & npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' } }
            & npm run build
            if ($LASTEXITCODE -ne 0) { throw 'npm run build failed.' }
        }
        finally { Pop-Location }
        Write-Ok 'Frontend built to frontend/dist.'
    }
}
else {
    Write-Warn2 'SkipBuild: dashboard is only served once frontend/dist/index.html exists.'
}

# ---------------------------------------------------------------------------
# 3. Auth — a network bind is protected by default.
#    The service enables the API-key gate by injecting REPO_MGMT_REQUIRE_API_KEY
#    + REPO_MGMT_API_KEY for its own process only (settings.json stays open, so
#    the smoke suite that assumes an open host is unaffected). Humans can also log
#    in with a session password once one is set (scripts\Set-PortalLogin.ps1);
#    the key remains the automation credential. -AllowInsecureBind is the explicit
#    "run open, no auth" escape hatch for a fully trusted network segment.
# ---------------------------------------------------------------------------
$isLoopback = $BindAddress -in @('127.0.0.1', '::1', 'localhost')

$injectAuth = $false
$effectiveApiKey = ''
$needInsecureAck = $false

if ($AllowInsecureBind) {
    if (-not $isLoopback) {
        $needInsecureAck = $true
        Write-Warn2 'Binding non-loopback WITHOUT auth (acknowledged). Anyone on this network can use the dashboard.'
    }
}
elseif (-not $isLoopback -or $ApiKey) {
    # Secure-by-default for a network bind; opt-in for loopback when -ApiKey given.
    $injectAuth = $true
    if ($ApiKey) {
        $effectiveApiKey = $ApiKey
    }
    else {
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $effectiveApiKey = ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
        Write-Ok 'Generated an API key for the service (shown at the end).'
    }
}

# ---------------------------------------------------------------------------
# 3b. TLS — when a PFX is supplied the host serves HTTPS (SslStream per socket).
#     Transport encryption is independent of API-key auth: HTTPS protects data
#     in flight, the auth guard above protects who may call. Use both for a
#     network-exposed portal.
# ---------------------------------------------------------------------------
$useTls = -not [string]::IsNullOrWhiteSpace($PfxPath)
$scheme = 'http'
if ($useTls) {
    if (-not (Test-Path -LiteralPath $PfxPath)) {
        throw "PfxPath not found: $PfxPath. Generate one with scripts\New-RepoManagementTlsCertificate.ps1."
    }
    $PfxPath = (Resolve-Path -LiteralPath $PfxPath).Path
    $scheme = 'https'
    Write-Ok "TLS enabled — serving HTTPS with certificate $PfxPath"
    if ($needInsecureAck) {
        Write-Warn2 'HTTPS is on, but there is still no API-key auth. Set auth.requireApiKey to restrict callers.'
    }
}

# ---------------------------------------------------------------------------
# 4. Resolve Shawl (the service wrapper)
# ---------------------------------------------------------------------------
$shawlExe = ''
if ($ShawlPath) {
    if (-not (Test-Path -LiteralPath $ShawlPath)) { throw "ShawlPath not found: $ShawlPath" }
    $shawlExe = (Resolve-Path -LiteralPath $ShawlPath).Path
}
else {
    $onPath = Get-Command shawl -ErrorAction SilentlyContinue
    $inTools = Join-Path $WorkspaceRoot 'tools\shawl.exe'
    if ($onPath) { $shawlExe = $onPath.Source }
    elseif (Test-Path -LiteralPath $inTools) { $shawlExe = $inTools }
}

if (-not $shawlExe) {
    Write-Fail 'Shawl (service wrapper) not found.'
    Write-Host ''
    Write-Host '  Install it one of these ways, then re-run this script:' -ForegroundColor Yellow
    Write-Host '    winget install --id mtkennerly.shawl' -ForegroundColor Gray
    Write-Host '    # or download shawl.exe from https://github.com/mtkennerly/shawl/releases' -ForegroundColor Gray
    Write-Host "    # and place it at $WorkspaceRoot\tools\shawl.exe (or pass -ShawlPath)" -ForegroundColor Gray
    Write-Host ''
    throw 'Shawl is required. See instructions above.'
}
Write-Ok "Service wrapper: $shawlExe"

# ---------------------------------------------------------------------------
# 5. Remove any existing service (idempotent reinstall)
# ---------------------------------------------------------------------------
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Step "Existing service '$ServiceName' found — removing for clean reinstall."
    if ($existing.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20; $i++) {
            $s = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if (-not $s -or $s.Status -eq 'Stopped') { break }
            Start-Sleep -Milliseconds 250
        }
    }
    & sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# ---------------------------------------------------------------------------
# 6. Create the service via Shawl
# ---------------------------------------------------------------------------
Write-Step 'Creating service...'

# Environment injected into the service process only (not machine-wide).
$serviceEnv = New-Object System.Collections.Generic.List[string]
if ($injectAuth) {
    $serviceEnv.Add('REPO_MGMT_REQUIRE_API_KEY=true')
    $serviceEnv.Add("REPO_MGMT_API_KEY=$effectiveApiKey")
}
if ($needInsecureAck) { $serviceEnv.Add('REPO_MGMT_ALLOW_INSECURE_BIND=true') }
if ($GitHubToken)     { $serviceEnv.Add("GITHUB_TOKEN=$GitHubToken") }
if ($useTls) {
    $serviceEnv.Add("REPO_MGMT_TLS_PFX=$PfxPath")
    $serviceEnv.Add("REPO_MGMT_TLS_PFX_PASSWORD=$PfxPassword")
}

$shawlArgs = New-Object System.Collections.Generic.List[string]
$shawlArgs.AddRange([string[]]@(
        'add',
        '--name', $ServiceName,
        '--cwd', $WorkspaceRoot,
        '--log-dir', $logDir,
        '--restart',            # restart on any exit code
        '--stop-timeout', '10000' # ms to drain after ctrl-C before force-kill
    ))
foreach ($e in $serviceEnv) { $shawlArgs.Add('--env'); $shawlArgs.Add($e) }
$shawlArgs.Add('--')
$shawlArgs.Add($pwshExe)
$shawlArgs.AddRange([string[]]@(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $hostScript,
        '-BindAddress', $BindAddress,
        '-Port', "$Port",
        '-WorkspaceRoot', $WorkspaceRoot,
        '-LogPath', $apiLog
    ))

& $shawlExe @shawlArgs
if ($LASTEXITCODE -ne 0) { throw "shawl add failed with exit code $LASTEXITCODE." }
Write-Ok "Service '$ServiceName' created."

# ---------------------------------------------------------------------------
# 7. Configure boot-start, recovery, description, and (optional) run-as account
# ---------------------------------------------------------------------------
# Auto-start at boot (shawl/sc create defaults to manual).
& sc.exe config $ServiceName start= auto | Out-Null
# Friendly display name.
& sc.exe config $ServiceName DisplayName= "$DisplayName" | Out-Null
# SCM-level recovery — restarts the wrapper itself if it ever dies (belt-and-
# suspenders on top of shawl's own --restart of the pwsh host).
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
& sc.exe description $ServiceName 'GitHub Repo Management portal (API + dashboard). Always-on service.' | Out-Null

if ($Credential) {
    $u = $Credential.UserName
    $p = $Credential.GetNetworkCredential().Password
    & sc.exe config $ServiceName obj= "$u" password= "$p" | Out-Null
    Write-Ok "Service will run as $u."
}
else {
    Write-Ok 'Service will run as LocalSystem (unattended, no password).'
}

# ---------------------------------------------------------------------------
# 8. Start and verify health
# ---------------------------------------------------------------------------
Write-Step 'Starting service...'
Start-Service -Name $ServiceName

# Probe on loopback regardless of bind (memory: use 127.0.0.1, never localhost).
$probeHost = switch ($BindAddress) {
    '0.0.0.0' { '127.0.0.1' }
    '::'      { '[::1]' }
    '[::]'    { '[::1]' }
    default   { $BindAddress }
}
$probeUrl = "${scheme}://${probeHost}:${Port}/health/live"

# For a self-signed HTTPS cert the probe must skip chain validation. Prefer
# pwsh 7's -SkipCertificateCheck; fall back to a session callback on 5.1.
$supportsSkip = (Get-Command Invoke-RestMethod).Parameters.ContainsKey('SkipCertificateCheck')
if ($useTls -and -not $supportsSkip) {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

Write-Step "Waiting for readiness at $probeUrl ..."
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    try {
        $irm = @{ Uri = $probeUrl; Method = 'Get'; TimeoutSec = 2 }
        if ($useTls -and $supportsSkip) { $irm.SkipCertificateCheck = $true }
        $null = Invoke-RestMethod @irm
        $ready = $true
        break
    }
    catch { Start-Sleep -Milliseconds 500 }
}

Write-Host ''
if ($ready) {
    Write-Ok "Portal is up and set to start at every boot."
    Write-Host ''
    Write-Host "  Access  : ${scheme}://${probeHost}:${Port}  (LAN: ${scheme}://<this-host-ip>:${Port})" -ForegroundColor Green
    Write-Host "  Logs    : $logDir" -ForegroundColor Gray
    Write-Host "  Status  : Get-Service $ServiceName" -ForegroundColor Gray
    Write-Host "  Restart : Restart-Service $ServiceName" -ForegroundColor Gray
    Write-Host "  Remove  : .\scripts\Uninstall-RepoManagementService.ps1" -ForegroundColor Gray
    Write-Host ''
    if ($injectAuth) {
        Write-Host '  Auth    : API-key gate ENABLED for the service.' -ForegroundColor Green
        Write-Host '  API key (paste into the dashboard once, or use for automation):' -ForegroundColor Yellow
        Write-Host "    $effectiveApiKey" -ForegroundColor Yellow
        Write-Host '  For human login, set a password:  .\scripts\Set-PortalLogin.ps1  (then Restart-Service)' -ForegroundColor Gray
        Write-Host ''
    }
    elseif ($needInsecureAck) {
        Write-Warn2 'Auth is OFF (-AllowInsecureBind). The dashboard is unauthenticated on this network.'
        Write-Host ''
    }
}
else {
    Write-Fail "Service was created but did not answer $probeUrl within 20s."
    Write-Host "  Check the logs in $logDir (apihost.log and shawl_for_${ServiceName}_*.log)." -ForegroundColor Yellow
    Write-Host "  Service state: $((Get-Service -Name $ServiceName).Status)" -ForegroundColor Yellow
    exit 1
}

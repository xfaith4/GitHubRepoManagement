#Requires -Version 7.0
<#
.SYNOPSIS
    Install, repair, reconfigure, or remove the GitHub Repo Management portal as
    an always-on Windows service.

.DESCRIPTION
    Wraps the PowerShell API host (backend/api-host/Start-RepoManagementApiHost.ps1)
    as a Windows service using Shawl (https://github.com/mtkennerly/shawl) so the
    portal starts at boot (before any login), restarts if the host process exits,
    and captures logs to backend/modules/output/logs/. A single process serves the
    API AND the compiled frontend bundle (frontend/dist) — no Vite/Node at runtime.

    Smart entry point (-Action):
      * Auto  (default): fresh-install if the service is absent; if present,
        show a menu (interactive) or Repair (non-interactive).
      * Install / Reinstall / Reconfigure: create the service (Reinstall/
        Reconfigure tear down an existing one first).
      * Repair: non-destructive — validate the registered paths, re-apply
        boot-start / recovery / description, migrate secrets into settings.json,
        ensure the watchdog, restart, and health-check. No teardown.
      * Uninstall: remove the service (and the watchdog task).

    SECRETS: the API key and TLS PFX password are written into
    backend/config/settings.json (which the host reads natively — auth.apiKey /
    network.tls.pfxPassword) and the file is ACL-locked, NOT injected as --env
    args. This keeps them out of the service ImagePath, which is world-readable
    via `sc qc`. GITHUB_TOKEN is set as a machine environment variable (out of the
    ImagePath) rather than a --env arg.

    RELIABILITY: after a successful install/repair the installer offers to register
    the freeze watchdog (scripts/service/Install-PortalWatchdog.ps1) so an
    alive-but-wedged host is recovered (shawl only restarts on process EXIT).
    -NightlyRestart adds a SYSTEM task that restarts the service nightly.

    WHY SHAWL: a PowerShell script cannot be a Windows service directly. Shawl is a
    tiny supervisor .exe that launches, monitors, restarts, and log-captures the
    pwsh host while speaking the Service Control Manager protocol.

.PARAMETER Action
    Auto (default) | Install | Repair | Reconfigure | Reinstall | Uninstall.

.PARAMETER NoWatchdog
    Do not offer/register the freeze watchdog after install/repair.

.PARAMETER NightlyRestart
    Register a SYSTEM scheduled task that restarts the service nightly.

.PARAMETER WorkspaceRoot
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER BindAddress
    Address the API host binds. Default 0.0.0.0 (LAN). Use 127.0.0.1 for local-only.

.PARAMETER Port
    TCP port. Default 7071.

.PARAMETER PfxPath / PfxPassword
    TLS certificate (.pfx) + password. When supplied the host serves HTTPS. The
    password goes into settings.json (ACL-locked), not the ImagePath. Generate a
    cert with scripts/New-RepoManagementTlsCertificate.ps1.

.PARAMETER ApiKey
    Explicit API key. If omitted while auth is enabled, one is generated. Stored
    in settings.json (auth.apiKey), not the ImagePath.

.PARAMETER GitHubToken
    Optional GitHub token, set as the machine GITHUB_TOKEN env var for the service.

.PARAMETER AllowInsecureBind
    Acknowledge a non-loopback bind WITHOUT API-key auth (single-operator LAN).

.PARAMETER Credential
    Optional run-as account. Default LocalSystem.

.PARAMETER SkipBuild
    Skip the frontend production-build check.

.PARAMETER LoadFunctionsOnly
    Dot-source the pure functions without running the installer (used by the smoke).

.EXAMPLE
    # elevated: fresh install (or menu if already installed), LAN + HTTPS:
    .\scripts\Install-RepoManagementService.ps1 -PfxPath .\backend\config\tls\portal.pfx -PfxPassword $pw

.EXAMPLE
    # elevated: reconcile an existing install without teardown:
    .\scripts\Install-RepoManagementService.ps1 -Action Repair
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Install', 'Repair', 'Reconfigure', 'Reinstall', 'Uninstall')]
    [string]$Action = 'Auto',
    [switch]$NoWatchdog,
    [switch]$NightlyRestart,
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
    [switch]$SkipBuild,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$m) Write-Host "  $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Write-Fail  { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Red }

# ═══════════════════════════════════════════════════════════════════════════
# Pure functions (unit-tested by the module smoke via -LoadFunctionsOnly — no
# elevation, no service/registry access).
# ═══════════════════════════════════════════════════════════════════════════

function Resolve-InstallAction {
    <# Map the requested -Action + whether the service exists to a concrete
       action. Auto: absent -> Install; present + interactive -> Menu (caller
       prompts); present + non-interactive -> Repair (the safe, non-destructive
       default). An explicit action is honored as-is. #>
    param(
        [Parameter(Mandatory)][bool]$ServiceExists,
        [Parameter(Mandatory)][string]$RequestedAction,
        [Parameter(Mandatory)][bool]$Interactive
    )
    if ($RequestedAction -ne 'Auto') { return $RequestedAction }
    if (-not $ServiceExists) { return 'Install' }
    if ($Interactive) { return 'Menu' }
    return 'Repair'
}

function Set-PortalSecretsInSettings {
    <# Write auth + TLS secrets into settings.json so the host reads them natively
       (auth.apiKey / network.tls.pfxPassword) instead of from --env args in the
       ImagePath. Preserves existing keys and schemaVersion; JSON round-trips. #>
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [bool]$RequireApiKey,
        [string]$ApiKey,
        [string]$PfxPath,
        [string]$PfxPassword
    )
    $obj = @{}
    if (Test-Path -LiteralPath $SettingsPath) {
        $raw = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) { $obj = $raw | ConvertFrom-Json -AsHashtable }
    }
    if (-not $obj.ContainsKey('schemaVersion')) { $obj['schemaVersion'] = '1' }

    if (-not $obj.ContainsKey('auth') -or $obj['auth'] -isnot [System.Collections.IDictionary]) { $obj['auth'] = @{} }
    $obj.auth['requireApiKey'] = [bool]$RequireApiKey
    if ($ApiKey) { $obj.auth['apiKey'] = $ApiKey }

    if ($PfxPath) {
        if (-not $obj.ContainsKey('network') -or $obj['network'] -isnot [System.Collections.IDictionary]) { $obj['network'] = @{} }
        if (-not $obj.network.ContainsKey('tls') -or $obj.network['tls'] -isnot [System.Collections.IDictionary]) { $obj.network['tls'] = @{} }
        $obj.network.tls['pfxPath'] = $PfxPath
        if ($PfxPassword) { $obj.network.tls['pfxPassword'] = $PfxPassword }
    }

    ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    return [pscustomobject]@{
        requireApiKey = [bool]$RequireApiKey
        wroteApiKey   = [bool]$ApiKey
        wroteTls      = [bool]$PfxPath
    }
}

function Get-ImagePathDrift {
    <# Given a service ImagePath, return the referenced filesystem paths that no
       longer exist (shawl.exe, pwsh.exe, --cwd, --log-dir, -File host script,
       REPO_MGMT_TLS_PFX). Used by Repair to report drift. #>
    param([Parameter(Mandatory)][string]$ImagePath)
    $paths = New-Object System.Collections.Generic.List[string]
    # exe tokens + flag targets. Strip the \\?\ extended-length prefix for Test-Path.
    $patterns = @(
        '(?<=\s--cwd\s)(?:\\\\\?\\)?[A-Za-z]:\\[^\s"]+',
        '(?<=\s--log-dir\s)(?:\\\\\?\\)?[A-Za-z]:\\[^\s"]+',
        '(?<=\s-File\s)"?(?:\\\\\?\\)?[A-Za-z]:\\[^"\s]+',
        '(?<=REPO_MGMT_TLS_PFX=)(?:\\\\\?\\)?[A-Za-z]:\\[^\s"]+',
        '^\s*"?(?:\\\\\?\\)?[A-Za-z]:\\[^"\s]+shawl\.exe',
        '(?<=--\s)"?(?:\\\\\?\\)?[A-Za-z]:\\[^"\s]+pwsh\.exe'
    )
    foreach ($p in $patterns) {
        foreach ($m in [regex]::Matches($ImagePath, $p, 'IgnoreCase')) {
            $candidate = ($m.Value -replace '^"', '') -replace '^\\\\\?\\', ''
            $candidate = $candidate.Trim().TrimEnd('"')
            if ($candidate -and -not (Test-Path -LiteralPath $candidate) -and -not $paths.Contains($candidate)) {
                $paths.Add($candidate)
            }
        }
    }
    return $paths.ToArray()
}

if ($LoadFunctionsOnly) { return }

# ═══════════════════════════════════════════════════════════════════════════
# Runtime guards + shared setup
# ═══════════════════════════════════════════════════════════════════════════
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail 'Run this from an elevated (Administrator) PowerShell — service management requires it.'
    exit 1
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot = Split-Path -Parent $PSScriptRoot }
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$logDir     = Join-Path $WorkspaceRoot 'backend\modules\output\logs'
$distIndex  = Join-Path $WorkspaceRoot 'frontend\dist\index.html'
$settings   = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$apiLog     = Join-Path $logDir 'apihost.log'
$watchdogInstaller = Join-Path $WorkspaceRoot 'scripts\service\Install-PortalWatchdog.ps1'
$uninstaller       = Join-Path $WorkspaceRoot 'scripts\Uninstall-RepoManagementService.ps1'
$nightlyTaskName   = "$ServiceName`Restart"

if (-not (Test-Path -LiteralPath $hostScript)) { throw "API host script not found at $hostScript. Is -WorkspaceRoot correct?" }
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }

$isLoopback = $BindAddress -in @('127.0.0.1', '::1', 'localhost')
$useTls = -not [string]::IsNullOrWhiteSpace($PfxPath)
$scheme = if ($useTls) { 'https' } else { 'http' }
$probeHost = switch ($BindAddress) { '0.0.0.0' { '127.0.0.1' } '::' { '[::1]' } '[::]' { '[::1]' } default { $BindAddress } }

# ─── Elevated helpers ────────────────────────────────────────────────────────
function Lock-SettingsFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    # Remove inherited (non-admin Users) access; grant SYSTEM read, Administrators
    # full, and the file owner modify so the operator's non-elevated dev tools
    # (smoke, daily-evidence driver) keep working while other local users cannot
    # read the secrets. *S-1-5-32-544 = Administrators (locale-independent).
    $owner = ''
    try { $owner = (Get-Acl -LiteralPath $Path).Owner } catch { }
    $grants = @('SYSTEM:R', '*S-1-5-32-544:F')
    if ($owner) { $grants += ("{0}:M" -f $owner) }
    & icacls $Path /inheritance:r /grant @grants *> $null
    Write-Ok ("Locked settings.json (SYSTEM:R, Administrators:F{0})." -f $(if ($owner) { ", ${owner}:M" } else { '' }))
}

function Stop-AndDeleteService {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20; $i++) {
            $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
            if (-not $s -or $s.Status -eq 'Stopped') { break }
            Start-Sleep -Milliseconds 250
        }
    }
    & sc.exe delete $Name | Out-Null
    Start-Sleep -Seconds 2
}

function Wait-PortalHealthy {
    param([string]$Url, [bool]$Tls)
    $supportsSkip = (Get-Command Invoke-RestMethod).Parameters.ContainsKey('SkipCertificateCheck')
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $irm = @{ Uri = $Url; Method = 'Get'; TimeoutSec = 2 }
            if ($Tls -and $supportsSkip) { $irm.SkipCertificateCheck = $true }
            $null = Invoke-RestMethod @irm
            return $true
        }
        catch { Start-Sleep -Milliseconds 500 }
    }
    return $false
}

function Register-NightlyRestartTask {
    param([string]$Name, [string]$Svc)
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -Command `"Restart-Service -Name '{0}' -Force`"" -f $Svc)
    $trg = New-ScheduledTaskTrigger -Daily -At 4am
    $prn = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
    $null = Register-ScheduledTask -TaskName $Name -Action $act -Trigger $trg -Principal $prn -Settings $set -Force -Description "Nightly restart of $Svc (bounds long-uptime degradation)."
    Write-Ok "Registered nightly-restart task '$Name' (04:00, as SYSTEM)."
}

function Invoke-WatchdogFoldIn {
    if ($NoWatchdog) { Write-Warn2 'Watchdog skipped (-NoWatchdog). A frozen host will NOT self-recover.'; return }
    if (-not (Test-Path -LiteralPath $watchdogInstaller)) { Write-Warn2 "Watchdog installer not found ($watchdogInstaller) — skipping."; return }
    $ans = if ($Host.UI.RawUI) { Read-Host '  Install the freeze watchdog (recommended)? [Y/n]' } else { 'y' }
    if ($ans -and $ans.Trim().ToLowerInvariant() -eq 'n') { Write-Warn2 'Watchdog declined.'; return }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $watchdogInstaller -WorkspaceRoot $WorkspaceRoot -BaseUrl ("{0}://{1}:{2}" -f $scheme, $probeHost, $Port) -Port $Port -ServiceName $ServiceName
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Freeze watchdog installed (probes health, restarts on freeze).' }
    else { Write-Warn2 "Watchdog installer returned exit $LASTEXITCODE — check output above." }
}

# ─── Fresh install / reinstall / reconfigure ─────────────────────────────────
function Invoke-FreshInstall {
    Write-Host ''
    Write-Host '====================================' -ForegroundColor White
    Write-Host ' Install: Repo Management Portal service' -ForegroundColor White
    Write-Host "  Service : $ServiceName   Bind: ${BindAddress}:${Port} ($scheme)" -ForegroundColor Gray
    Write-Host "  Root    : $WorkspaceRoot" -ForegroundColor Gray
    Write-Host '====================================' -ForegroundColor White

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) { throw 'pwsh (PowerShell 7) not found on PATH. Install it (winget install --id Microsoft.PowerShell) and retry.' }
    $pwshExe = $pwshCmd.Source
    Write-Ok "PowerShell host: $pwshExe"

    # Frontend bundle
    if (-not $SkipBuild) {
        if (Test-Path -LiteralPath $distIndex) { Write-Ok 'Frontend bundle present (frontend/dist).' }
        else {
            Write-Step 'Frontend bundle missing — building (npm run build)...'
            if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'frontend/dist not found and npm is unavailable. Build first (npm ci && npm run build in frontend\) or pass -SkipBuild.' }
            Push-Location (Join-Path $WorkspaceRoot 'frontend')
            try {
                if (-not (Test-Path 'node_modules')) { & npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' } }
                & npm run build; if ($LASTEXITCODE -ne 0) { throw 'npm run build failed.' }
            }
            finally { Pop-Location }
            Write-Ok 'Frontend built to frontend/dist.'
        }
    }
    else { Write-Warn2 'SkipBuild: dashboard is served only once frontend/dist/index.html exists.' }

    # Auth decision (secure-by-default for a network bind).
    $injectAuth = $false; $effectiveApiKey = ''; $needInsecureAck = $false
    if ($AllowInsecureBind) {
        if (-not $isLoopback) { $needInsecureAck = $true; Write-Warn2 'Binding non-loopback WITHOUT auth (acknowledged).' }
    }
    elseif (-not $isLoopback -or $ApiKey) {
        $injectAuth = $true
        if ($ApiKey) { $effectiveApiKey = $ApiKey }
        else {
            $bytes = New-Object byte[] 32
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
            $effectiveApiKey = ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
            Write-Ok 'Generated an API key for the service (shown at the end).'
        }
    }

    # TLS pfx existence.
    if ($useTls) {
        if (-not (Test-Path -LiteralPath $PfxPath)) { throw "PfxPath not found: $PfxPath. Generate one with scripts\New-RepoManagementTlsCertificate.ps1." }
        $script:PfxPath = (Resolve-Path -LiteralPath $PfxPath).Path
        Write-Ok "TLS enabled — serving HTTPS with $($script:PfxPath)"
    }

    # SECRETS -> settings.json (not --env). The host reads auth.apiKey /
    # network.tls.pfxPassword natively; keeping them out of the ImagePath closes
    # the `sc qc` exposure.
    if ($injectAuth -or $useTls) {
        $null = Set-PortalSecretsInSettings -SettingsPath $settings -RequireApiKey $injectAuth -ApiKey $effectiveApiKey -PfxPath $(if ($useTls) { $script:PfxPath } else { '' }) -PfxPassword $PfxPassword
        Write-Ok 'Wrote secrets to settings.json (auth.apiKey / network.tls.pfxPassword) — not the ImagePath.'
        Lock-SettingsFile -Path $settings
    }

    # GITHUB_TOKEN -> machine env (out of the ImagePath).
    if ($GitHubToken) {
        [System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $GitHubToken, 'Machine')
        Write-Ok 'Set machine GITHUB_TOKEN (inherited by the LocalSystem service; not in the ImagePath).'
    }

    # Resolve shawl.
    $shawlExe = ''
    if ($ShawlPath) { if (-not (Test-Path -LiteralPath $ShawlPath)) { throw "ShawlPath not found: $ShawlPath" }; $shawlExe = (Resolve-Path -LiteralPath $ShawlPath).Path }
    else {
        $onPath = Get-Command shawl -ErrorAction SilentlyContinue
        $inTools = Join-Path $WorkspaceRoot 'tools\shawl.exe'
        if ($onPath) { $shawlExe = $onPath.Source } elseif (Test-Path -LiteralPath $inTools) { $shawlExe = $inTools }
    }
    if (-not $shawlExe) {
        Write-Fail 'Shawl (service wrapper) not found.'
        Write-Host '    winget install --id mtkennerly.shawl   (or place shawl.exe in tools\)' -ForegroundColor Gray
        throw 'Shawl is required.'
    }
    Write-Ok "Service wrapper: $shawlExe"

    Stop-AndDeleteService -Name $ServiceName

    # Non-secret env only.
    $serviceEnv = New-Object System.Collections.Generic.List[string]
    if ($needInsecureAck) { $serviceEnv.Add('REPO_MGMT_ALLOW_INSECURE_BIND=true') }

    $shawlArgs = New-Object System.Collections.Generic.List[string]
    $shawlArgs.AddRange([string[]]@('add', '--name', $ServiceName, '--cwd', $WorkspaceRoot, '--log-dir', $logDir, '--restart', '--stop-timeout', '10000'))
    foreach ($e in $serviceEnv) { $shawlArgs.Add('--env'); $shawlArgs.Add($e) }
    $shawlArgs.Add('--')
    $shawlArgs.Add($pwshExe)
    $shawlArgs.AddRange([string[]]@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hostScript, '-BindAddress', $BindAddress, '-Port', "$Port", '-WorkspaceRoot', $WorkspaceRoot, '-LogPath', $apiLog))

    Write-Step 'Creating service...'
    & $shawlExe @shawlArgs
    if ($LASTEXITCODE -ne 0) { throw "shawl add failed with exit code $LASTEXITCODE." }

    & sc.exe config $ServiceName start= auto | Out-Null
    & sc.exe config $ServiceName DisplayName= "$DisplayName" | Out-Null
    & sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    & sc.exe description $ServiceName 'GitHub Repo Management portal (API + dashboard). Always-on service.' | Out-Null
    if ($Credential) {
        & sc.exe config $ServiceName obj= "$($Credential.UserName)" password= "$($Credential.GetNetworkCredential().Password)" | Out-Null
        Write-Ok "Service will run as $($Credential.UserName)."
    }
    else { Write-Ok 'Service will run as LocalSystem (unattended, no password).' }
    Write-Ok "Service '$ServiceName' created."

    Write-Step 'Starting service...'
    Start-Service -Name $ServiceName
    $probeUrl = "${scheme}://${probeHost}:${Port}/health/live"
    Write-Step "Waiting for readiness at $probeUrl ..."
    if (Wait-PortalHealthy -Url $probeUrl -Tls $useTls) {
        Write-Ok 'Portal is up and set to start at every boot.'
        Write-Host "  Access : ${scheme}://${probeHost}:${Port}  (LAN: ${scheme}://<this-host-ip>:${Port})" -ForegroundColor Green
        if ($injectAuth) {
            Write-Host '  Auth   : API-key gate ENABLED (key in settings.json).' -ForegroundColor Green
            Write-Host '  API key (for automation / dashboard):' -ForegroundColor Yellow
            Write-Host "    $effectiveApiKey" -ForegroundColor Yellow
        }
        elseif ($needInsecureAck) { Write-Warn2 'Auth is OFF (-AllowInsecureBind). Dashboard is unauthenticated on this network.' }
        Invoke-WatchdogFoldIn
        if ($NightlyRestart) { Register-NightlyRestartTask -Name $nightlyTaskName -Svc $ServiceName }
        Write-Host "  Manage : Get-Service $ServiceName | Restart-Service $ServiceName | Uninstall via -Action Uninstall" -ForegroundColor Gray
    }
    else {
        Write-Fail "Service created but did not answer $probeUrl within 20s. Check $logDir (apihost.log, shawl_for_${ServiceName}_*.log)."
        exit 1
    }
}

# ─── Repair (non-destructive) ────────────────────────────────────────────────
function Invoke-Repair {
    Write-Host ''
    Write-Host "  Repairing service '$ServiceName' (no teardown)..." -ForegroundColor White
    $wmi = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if (-not $wmi) { throw "Service '$ServiceName' not found — cannot repair. Use -Action Install." }

    $drift = @(Get-ImagePathDrift -ImagePath $wmi.PathName)
    if ($drift.Count -gt 0) {
        Write-Warn2 "Registered ImagePath references paths that no longer exist:"
        $drift | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        Write-Warn2 'Repair cannot fix a moved binary — use -Action Reconfigure to re-register.'
    }
    else { Write-Ok 'All ImagePath references resolve.' }

    # Migrate any secrets still in the ImagePath into settings.json.
    if ($wmi.PathName -match 'REPO_MGMT_API_KEY=|REPO_MGMT_TLS_PFX_PASSWORD=') {
        Write-Warn2 'Secrets still present in the ImagePath — migrate with -Action Reconfigure (re-registers without --env secrets).'
    }
    else { Write-Ok 'No secrets in the ImagePath.' }
    if (Test-Path -LiteralPath $settings) { Lock-SettingsFile -Path $settings }

    # Re-apply SCM config idempotently.
    & sc.exe config $ServiceName start= auto | Out-Null
    & sc.exe config $ServiceName DisplayName= "$DisplayName" | Out-Null
    & sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    Write-Ok 'Re-applied boot-start + SCM recovery.'

    Write-Step 'Restarting service...'
    Restart-Service -Name $ServiceName -Force
    $probeUrl = "${scheme}://${probeHost}:${Port}/health/live"
    if (Wait-PortalHealthy -Url $probeUrl -Tls $useTls) { Write-Ok "Healthy at $probeUrl." }
    else { Write-Fail "Not healthy at $probeUrl after restart — check $logDir." }

    Invoke-WatchdogFoldIn
    if ($NightlyRestart) { Register-NightlyRestartTask -Name $nightlyTaskName -Svc $ServiceName }
}

function Invoke-Uninstall {
    if (Test-Path -LiteralPath $uninstaller) { & pwsh -NoProfile -ExecutionPolicy Bypass -File $uninstaller -ServiceName $ServiceName }
    else { Stop-AndDeleteService -Name $ServiceName; Write-Ok "Service '$ServiceName' removed." }
    if (Test-Path -LiteralPath $watchdogInstaller) { & pwsh -NoProfile -ExecutionPolicy Bypass -File $watchdogInstaller -Uninstall }
    if (Get-ScheduledTask -TaskName $nightlyTaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $nightlyTaskName -Confirm:$false; Write-Ok "Removed nightly-restart task." }
}

# ═══════════════════════════════════════════════════════════════════════════
# Dispatch
# ═══════════════════════════════════════════════════════════════════════════
$serviceExists = [bool](Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)
$interactive = -not [System.Console]::IsInputRedirected
$resolved = Resolve-InstallAction -ServiceExists $serviceExists -RequestedAction $Action -Interactive $interactive

if ($resolved -eq 'Menu') {
    Write-Host ''
    Write-Host "  Service '$ServiceName' is already installed. Choose an action:" -ForegroundColor White
    Write-Host '    [R] Repair       — reconcile config, restart, re-verify (no teardown)' -ForegroundColor Gray
    Write-Host '    [C] Reconfigure  — change bind/port/auth/TLS (re-registers)' -ForegroundColor Gray
    Write-Host '    [I] Reinstall    — full teardown + recreate' -ForegroundColor Gray
    Write-Host '    [U] Uninstall    — remove the service + watchdog' -ForegroundColor Gray
    Write-Host '    [X] Cancel' -ForegroundColor Gray
    switch ((Read-Host '  Action [R/C/I/U/X]').Trim().ToUpperInvariant()) {
        'R' { $resolved = 'Repair' }
        'C' { $resolved = 'Reconfigure' }
        'I' { $resolved = 'Reinstall' }
        'U' { $resolved = 'Uninstall' }
        default { Write-Host '  Cancelled.' -ForegroundColor Yellow; exit 0 }
    }
}

switch ($resolved) {
    'Install'     { Invoke-FreshInstall }
    'Reinstall'   { Invoke-FreshInstall }
    'Reconfigure' { Invoke-FreshInstall }
    'Repair'      { Invoke-Repair }
    'Uninstall'   { Invoke-Uninstall }
    default       { throw "Unknown action: $resolved" }
}

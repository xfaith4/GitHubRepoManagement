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
        boot-start / recovery / description, migrate any secrets out of
        settings.json into machine env vars, ensure the watchdog, restart, and
        health-check. No teardown.
      * Uninstall: remove the service (and the watchdog task).

    SECRETS: the API key and TLS PFX (path + password) are written as MACHINE
    environment variables (REPO_MGMT_API_KEY, REPO_MGMT_REQUIRE_API_KEY,
    REPO_MGMT_TLS_PFX, REPO_MGMT_TLS_PFX_PASSWORD), which the host reads natively
    and which win over settings.json. This keeps them out of BOTH the service
    ImagePath (world-readable via `sc qc`) AND the git-tracked settings.json — the
    same pattern GITHUB_TOKEN already uses. The tracked settings.json is left
    secret-free (any secret a prior installer wrote there is stripped). A
    reconfigure that omits -PfxPath / -ApiKey CARRIES FORWARD the existing values
    (env first, then any legacy settings copy) so HTTPS is never silently dropped
    and the key is never needlessly regenerated.

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
    TLS certificate (.pfx) + password. When supplied the host serves HTTPS; the
    path + password go into MACHINE env vars (REPO_MGMT_TLS_PFX / _PASSWORD), not
    settings.json or the ImagePath. Omit on a reconfigure to keep the existing
    HTTPS config. Generate a cert with scripts/New-RepoManagementTlsCertificate.ps1.

.PARAMETER ApiKey
    Explicit API key. If omitted while auth is enabled, the existing key is reused
    (carried forward from the env var or a legacy settings copy) and only generated
    when none exists. Stored in the REPO_MGMT_API_KEY machine env var, not the
    ImagePath or settings.json.

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

function Resolve-PortalSecretConfig {
    <# Compute the EFFECTIVE auth + TLS config for an install/reconfigure. Explicit
       -ApiKey / -PfxPath / -PfxPassword win; otherwise carry forward the existing
       value (machine env var first, then the legacy settings.json copy) so a
       reconfigure that OMITS them preserves HTTPS and reuses the key instead of
       silently downgrading to HTTP or minting a brand-new key. A key is generated
       only when auth is required and none can be carried forward.

       Pure: existing env + settings + the key generator are injected, so the smoke
       exercises every branch with no real environment, RNG, or filesystem. #>
    param(
        [bool]$InjectAuth,
        [string]$RequestedApiKey = '',
        [string]$RequestedPfxPath = '',
        [string]$RequestedPfxPassword = '',
        [hashtable]$ExistingSettings,
        [hashtable]$ExistingEnv,
        [scriptblock]$KeyGenerator
    )
    if ($null -eq $ExistingEnv) { $ExistingEnv = @{} }
    $envGet = {
        param($n)
        if ($ExistingEnv.ContainsKey($n) -and $null -ne $ExistingEnv[$n] -and "$($ExistingEnv[$n])" -ne '') { [string]$ExistingEnv[$n] } else { '' }
    }
    $envApiKey = & $envGet 'REPO_MGMT_API_KEY'
    $envPfx    = & $envGet 'REPO_MGMT_TLS_PFX'
    $envPfxPw  = & $envGet 'REPO_MGMT_TLS_PFX_PASSWORD'

    # Legacy settings.json copies (pre-fix installs wrote secrets here; we migrate
    # them out to env vars and then strip them from the tracked file).
    $setKey = ''; $setPfx = ''; $setPfxPw = ''
    if ($ExistingSettings) {
        if ($ExistingSettings.ContainsKey('auth') -and $ExistingSettings.auth -is [System.Collections.IDictionary] -and $ExistingSettings.auth.ContainsKey('apiKey')) {
            $setKey = [string]$ExistingSettings.auth.apiKey
        }
        if ($ExistingSettings.ContainsKey('network') -and $ExistingSettings.network -is [System.Collections.IDictionary] -and
            $ExistingSettings.network.ContainsKey('tls') -and $ExistingSettings.network.tls -is [System.Collections.IDictionary]) {
            if ($ExistingSettings.network.tls.ContainsKey('pfxPath')) { $setPfx = [string]$ExistingSettings.network.tls.pfxPath }
            if ($ExistingSettings.network.tls.ContainsKey('pfxPassword')) { $setPfxPw = [string]$ExistingSettings.network.tls.pfxPassword }
        }
    }

    # API key: param -> env -> legacy settings -> generate (only when auth required).
    $apiKey = ''; $apiKeySource = 'none'
    if ($InjectAuth) {
        if ($RequestedApiKey) { $apiKey = $RequestedApiKey; $apiKeySource = 'param' }
        elseif ($envApiKey)   { $apiKey = $envApiKey;       $apiKeySource = 'env' }
        elseif ($setKey)      { $apiKey = $setKey;          $apiKeySource = 'settings' }
        elseif ($KeyGenerator){ $apiKey = [string](& $KeyGenerator); $apiKeySource = 'generated' }
    }

    # TLS pfx path: param -> env -> legacy settings.
    $pfxPath = ''; $pfxSource = 'none'
    if ($RequestedPfxPath) { $pfxPath = $RequestedPfxPath; $pfxSource = 'param' }
    elseif ($envPfx)       { $pfxPath = $envPfx;           $pfxSource = 'env' }
    elseif ($setPfx)       { $pfxPath = $setPfx;           $pfxSource = 'settings' }

    # TLS password (only meaningful with a path): param -> env -> legacy settings.
    $pfxPw = ''
    if ($pfxPath) {
        if ($RequestedPfxPassword) { $pfxPw = $RequestedPfxPassword }
        elseif ($envPfxPw)         { $pfxPw = $envPfxPw }
        elseif ($setPfxPw)         { $pfxPw = $setPfxPw }
    }

    return [pscustomobject]@{
        RequireApiKey = [bool]$InjectAuth
        ApiKey        = $apiKey
        ApiKeySource  = $apiKeySource
        PfxPath       = $pfxPath
        PfxPathSource = $pfxSource
        PfxPassword   = $pfxPw
        UseTls        = [bool]$pfxPath
    }
}

function Remove-SettingsSecretKeys {
    <# Return $Settings with every installer-injected secret/policy key removed so
       the git-TRACKED settings.json carries NO secrets (they live in machine env
       vars instead): auth.apiKey, auth.requireApiKey, network.tls.pfxPath,
       network.tls.pfxPassword. Prunes now-empty auth / network.tls / network
       containers. All other keys are preserved untouched. Pure. #>
    param([Parameter(Mandatory)][hashtable]$Settings)
    if ($Settings.ContainsKey('auth') -and $Settings.auth -is [System.Collections.IDictionary]) {
        [void]$Settings.auth.Remove('apiKey')
        [void]$Settings.auth.Remove('requireApiKey')
        if ($Settings.auth.Count -eq 0) { [void]$Settings.Remove('auth') }
    }
    if ($Settings.ContainsKey('network') -and $Settings.network -is [System.Collections.IDictionary]) {
        if ($Settings.network.ContainsKey('tls') -and $Settings.network.tls -is [System.Collections.IDictionary]) {
            [void]$Settings.network.tls.Remove('pfxPath')
            [void]$Settings.network.tls.Remove('pfxPassword')
            if ($Settings.network.tls.Count -eq 0) { [void]$Settings.network.Remove('tls') }
        }
        if ($Settings.network.Count -eq 0) { [void]$Settings.Remove('network') }
    }
    return $Settings
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
function New-InstallerApiKey {
    # 32 random bytes -> 64 hex chars (matches the host's New-ApiKey).
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function Set-PortalSecretEnvironment {
    <# Persist the auth + TLS secrets as MACHINE env vars (inherited by the
       LocalSystem service on its next start, invisible to `sc qc`, never in git).
       An empty value CLEARS the variable, so turning auth/TLS off removes the
       stale secret rather than leaving it behind. #>
    param([bool]$RequireApiKey, [string]$ApiKey, [string]$PfxPath, [string]$PfxPassword)
    $setEnv = {
        param($n, $v)
        if ([string]::IsNullOrEmpty($v)) { [System.Environment]::SetEnvironmentVariable($n, $null, 'Machine') }
        else { [System.Environment]::SetEnvironmentVariable($n, $v, 'Machine') }
    }
    & $setEnv 'REPO_MGMT_REQUIRE_API_KEY' $(if ($RequireApiKey) { 'true' } else { '' })
    & $setEnv 'REPO_MGMT_API_KEY'            $ApiKey
    & $setEnv 'REPO_MGMT_TLS_PFX'            $PfxPath
    & $setEnv 'REPO_MGMT_TLS_PFX_PASSWORD'   $PfxPassword
    $bits = New-Object System.Collections.Generic.List[string]
    if ($RequireApiKey) { $bits.Add('REPO_MGMT_API_KEY + REQUIRE_API_KEY') }
    if ($PfxPath)       { $bits.Add('REPO_MGMT_TLS_PFX (+ _PASSWORD)') }
    if ($bits.Count -gt 0) { Write-Ok ("Stored secrets as MACHINE env vars ({0}) — not the ImagePath, not settings.json." -f ($bits -join ', ')) }
    else { Write-Ok 'No auth/TLS secrets to store.' }
}

function Clear-SettingsSecretsOnDisk {
    <# Strip installer-injected secrets from the git-tracked settings.json and, once
       it holds no secrets, restore normal ACL inheritance (older installs locked
       it). Writes only when something actually changed. #>
    param([string]$SettingsPath)
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return }
    $raw = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    $obj = $raw | ConvertFrom-Json -AsHashtable
    $before = ($obj | ConvertTo-Json -Depth 20 -Compress)
    $obj = Remove-SettingsSecretKeys -Settings $obj
    $after = ($obj | ConvertTo-Json -Depth 20 -Compress)
    if ($after -ne $before) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
        Write-Ok 'Stripped secrets from settings.json (auth.apiKey / network.tls.*) — now secret-free and git-safe.'
        try { & icacls $SettingsPath /reset *> $null } catch { }
    }
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
    param([string]$Scheme = 'http')
    if ($NoWatchdog) { Write-Warn2 'Watchdog skipped (-NoWatchdog). A frozen host will NOT self-recover.'; return }
    if (-not (Test-Path -LiteralPath $watchdogInstaller)) { Write-Warn2 "Watchdog installer not found ($watchdogInstaller) — skipping."; return }
    $ans = if ($Host.UI.RawUI) { Read-Host '  Install the freeze watchdog (recommended)? [Y/n]' } else { 'y' }
    if ($ans -and $ans.Trim().ToLowerInvariant() -eq 'n') { Write-Warn2 'Watchdog declined.'; return }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $watchdogInstaller -WorkspaceRoot $WorkspaceRoot -BaseUrl ("{0}://{1}:{2}" -f $Scheme, $probeHost, $Port) -Port $Port -ServiceName $ServiceName
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
    $injectAuth = $false; $needInsecureAck = $false
    if ($AllowInsecureBind) {
        if (-not $isLoopback) { $needInsecureAck = $true; Write-Warn2 'Binding non-loopback WITHOUT auth (acknowledged).' }
    }
    elseif (-not $isLoopback -or $ApiKey) {
        $injectAuth = $true
    }

    # Resolve EFFECTIVE secrets/TLS, carrying forward existing config (env first,
    # then any legacy settings copy) so a reconfigure that omits -PfxPath / -ApiKey
    # keeps HTTPS on and reuses the key instead of downgrading / regenerating.
    $existingSettings = @{}
    if (Test-Path -LiteralPath $settings) {
        try { $existingSettings = (Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable) } catch { $existingSettings = @{} }
    }
    $existingEnv = @{
        REPO_MGMT_API_KEY          = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_API_KEY', 'Machine')
        REPO_MGMT_TLS_PFX          = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_TLS_PFX', 'Machine')
        REPO_MGMT_TLS_PFX_PASSWORD = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_TLS_PFX_PASSWORD', 'Machine')
    }
    $sec = Resolve-PortalSecretConfig -InjectAuth $injectAuth -RequestedApiKey $ApiKey `
        -RequestedPfxPath $PfxPath -RequestedPfxPassword $PfxPassword `
        -ExistingSettings $existingSettings -ExistingEnv $existingEnv -KeyGenerator { New-InstallerApiKey }
    $effectiveApiKey = $sec.ApiKey
    switch ($sec.ApiKeySource) {
        'generated' { Write-Ok 'Generated an API key for the service (shown at the end).' }
        'env'       { Write-Ok 'Reusing the existing API key (from the machine env var).' }
        'settings'  { Write-Ok 'Reusing the existing API key (migrated out of settings.json).' }
        default     { }
    }

    # Effective TLS may differ from the -PfxPath param (carry-forward can enable
    # HTTPS even when it was not passed this run). Recompute scheme accordingly.
    $useTls = [bool]$sec.UseTls
    $scheme = if ($useTls) { 'https' } else { 'http' }
    if ($useTls) {
        if (-not (Test-Path -LiteralPath $sec.PfxPath)) { throw "TLS pfx not found: $($sec.PfxPath) (source: $($sec.PfxPathSource)). Pass -PfxPath to a real .pfx (generate one with scripts\New-RepoManagementTlsCertificate.ps1)." }
        $sec.PfxPath = (Resolve-Path -LiteralPath $sec.PfxPath).Path
        Write-Ok ("TLS enabled — serving HTTPS with $($sec.PfxPath) (source: $($sec.PfxPathSource))")
    }
    elseif (-not $needInsecureAck) {
        Write-Warn2 'No TLS certificate configured — serving plain HTTP. Pass -PfxPath + -PfxPassword to enable HTTPS.'
    }

    # SECRETS -> MACHINE ENV VARS (never the ImagePath, never the git-tracked
    # settings.json). The host reads REPO_MGMT_API_KEY / REPO_MGMT_REQUIRE_API_KEY /
    # REPO_MGMT_TLS_PFX / REPO_MGMT_TLS_PFX_PASSWORD natively and env wins over
    # settings.json — then strip any secret a prior installer left in settings.json.
    Set-PortalSecretEnvironment -RequireApiKey $sec.RequireApiKey -ApiKey $effectiveApiKey -PfxPath $(if ($useTls) { $sec.PfxPath } else { '' }) -PfxPassword $sec.PfxPassword
    Clear-SettingsSecretsOnDisk -SettingsPath $settings

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
            Write-Host '  Auth   : API-key gate ENABLED (key in the REPO_MGMT_API_KEY machine env var).' -ForegroundColor Green
            Write-Host '  API key (for automation / dashboard):' -ForegroundColor Yellow
            Write-Host "    $effectiveApiKey" -ForegroundColor Yellow
        }
        elseif ($needInsecureAck) { Write-Warn2 'Auth is OFF (-AllowInsecureBind). Dashboard is unauthenticated on this network.' }
        Invoke-WatchdogFoldIn -Scheme $scheme
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

    if ($wmi.PathName -match 'REPO_MGMT_API_KEY=|REPO_MGMT_TLS_PFX_PASSWORD=') {
        Write-Warn2 'Secrets still present in the ImagePath — run -Action Reconfigure to re-register without --env secrets.'
    }
    else { Write-Ok 'No secrets in the ImagePath.' }

    # Migrate any secret still in the git-tracked settings.json OUT to machine env
    # vars (carry-forward, no new values), then strip settings.json. Fixes an
    # install that parked the key in tracked config — non-destructive, no teardown.
    $existingSettings = @{}
    if (Test-Path -LiteralPath $settings) {
        try { $existingSettings = (Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable) } catch { $existingSettings = @{} }
    }
    $existingEnv = @{
        REPO_MGMT_API_KEY          = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_API_KEY', 'Machine')
        REPO_MGMT_TLS_PFX          = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_TLS_PFX', 'Machine')
        REPO_MGMT_TLS_PFX_PASSWORD = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_TLS_PFX_PASSWORD', 'Machine')
    }
    $reqEnv = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_REQUIRE_API_KEY', 'Machine')
    $existingRequire = ($reqEnv -match '^(?i)(1|true|yes|on)$') -or
        ($existingSettings.ContainsKey('auth') -and $existingSettings.auth -is [System.Collections.IDictionary] -and $existingSettings.auth.ContainsKey('requireApiKey') -and [bool]$existingSettings.auth.requireApiKey)
    $rsec = Resolve-PortalSecretConfig -InjectAuth $existingRequire -ExistingSettings $existingSettings -ExistingEnv $existingEnv -KeyGenerator { New-InstallerApiKey }
    Set-PortalSecretEnvironment -RequireApiKey $rsec.RequireApiKey -ApiKey $rsec.ApiKey -PfxPath $(if ($rsec.UseTls) { $rsec.PfxPath } else { '' }) -PfxPassword $rsec.PfxPassword
    Clear-SettingsSecretsOnDisk -SettingsPath $settings

    # Effective scheme for the health probe + watchdog (env/settings carry-forward).
    $repairTls = [bool]$rsec.UseTls -and (Test-Path -LiteralPath $rsec.PfxPath)
    $repairScheme = if ($repairTls) { 'https' } else { 'http' }

    # Re-apply SCM config idempotently.
    & sc.exe config $ServiceName start= auto | Out-Null
    & sc.exe config $ServiceName DisplayName= "$DisplayName" | Out-Null
    & sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    Write-Ok 'Re-applied boot-start + SCM recovery.'

    Write-Step 'Restarting service...'
    Restart-Service -Name $ServiceName -Force
    $probeUrl = "${repairScheme}://${probeHost}:${Port}/health/live"
    if (Wait-PortalHealthy -Url $probeUrl -Tls $repairTls) { Write-Ok "Healthy at $probeUrl ($repairScheme)." }
    else { Write-Fail "Not healthy at $probeUrl after restart — check $logDir." }

    Invoke-WatchdogFoldIn -Scheme $repairScheme
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

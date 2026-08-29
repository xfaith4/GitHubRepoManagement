#requires -Version 7
<#
.SYNOPSIS
    Move the portal from a loopback-only bind to an authenticated shared-LAN
    bind, in one elevated pass, with a verification that proves it landed.

.DESCRIPTION
    Release 2.9 — "Operator-verify the auth + shared-LAN path so automation runs
    on a bound, authenticated host."

    The portal binds 127.0.0.1 today because the Release 2.2 guard refuses a
    non-loopback bind while API auth is off, and auth was never configured. This
    script turns auth on and rebinds, in the order that never leaves the API
    exposed without a key:

      1. generate an API key and set it Machine-scope FIRST
      2. set the auth toggle Machine-scope
      3. open the firewall for the port on Private profiles only
      4. reconfigure the service to bind every interface
      5. verify: LAN reachable, anonymous rejected, keyed accepted

    Both environment variables are set together, deliberately. Setting the
    toggle alone makes the host generate its own key — which now lands in
    output\auth\api-key (outside version control) rather than in the tracked
    backend\config\settings.json, but pinning your own key is still what you
    want for a host other devices talk to.

    Nothing here writes a secret into the repository. The key is a Machine
    environment variable; this script prints it once so you can enter it on the
    phone, and never stores it in the workspace.

.PARAMETER Port
    The API port. Defaults to 7071, matching the installed service.

.PARAMETER BindAddress
    What the service should bind. 0.0.0.0 (default) serves every interface,
    which is what a phone on the LAN needs.

.PARAMETER ApiKey
    Use an existing key instead of generating one. Omit to generate a fresh
    64-character key.

.PARAMETER ServiceName
    The installed service. Defaults to RepoMgmtPortal.

.PARAMETER SkipFirewall
    Do not touch Windows Firewall. Use when a rule already exists.

.EXAMPLE
    # From an ELEVATED PowerShell 7 prompt:
    pwsh -File .\scripts\Enable-SharedLanAccess.ps1 -WhatIf   # show the plan
    pwsh -File .\scripts\Enable-SharedLanAccess.ps1           # do it

.NOTES
    Requires elevation: the service runs as LocalSystem, so the environment
    variables must be Machine-scope, and both the firewall rule and the service
    reconfigure need admin.

    This script does NOT enable TLS. The portal serves plain HTTP, so the API
    key crosses the LAN in the clear. See the TLS note printed at the end.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()][int]$Port = 7071,
    [Parameter()][string]$BindAddress = '0.0.0.0',
    [Parameter()][string]$ApiKey = '',
    [Parameter()][string]$ServiceName = 'RepoMgmtPortal',
    [Parameter()][switch]$SkipFirewall,
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Host "[STEP] $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "       $Message" -ForegroundColor DarkGray }

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# -WhatIf is allowed unelevated on purpose: reading the plan before running an
# outward-facing change should not itself require admin.
if (-not $isElevated -and -not $WhatIfPreference) {
    throw 'This script must run elevated: the service is LocalSystem, so the environment variables must be Machine-scope, and the firewall rule and service reconfigure both need admin. Re-run with -WhatIf to preview the plan without elevation.'
}
if (-not $isElevated) { Write-Host 'Preview only — not elevated, so nothing below would actually run.' -ForegroundColor Yellow }

# ── The LAN address the phone will use ───────────────────────────────────────
$lanIp = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notlike '*WSL*' -and $_.InterfaceAlias -notlike '*Default Switch*' } |
        Select-Object -First 1 -ExpandProperty IPAddress)
if ([string]::IsNullOrWhiteSpace($lanIp)) { $lanIp = '<this machine LAN IP>' }
$portalUrl = "http://${lanIp}:$Port"

Write-Host ''
Write-Host 'Shared-LAN + auth enablement' -ForegroundColor White
Write-Note "service    : $ServiceName"
Write-Note "bind       : ${BindAddress}:$Port"
Write-Note "phone URL  : $portalUrl"
Write-Host ''

# ── 1. The key, set BEFORE the toggle ────────────────────────────────────────
# Order matters: with the toggle set and no key, the host generates one. That is
# survivable now (it goes to output\auth\, outside version control) but it would
# not be the key you wrote down.
$generatedHere = $false
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $bytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $ApiKey = (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
    $generatedHere = $true
}

Write-Step 'Setting REPO_MGMT_API_KEY (Machine scope)'
if ($PSCmdlet.ShouldProcess('Machine environment', 'set REPO_MGMT_API_KEY')) {
    [Environment]::SetEnvironmentVariable('REPO_MGMT_API_KEY', $ApiKey, 'Machine')
    Write-Note ("set ({0} chars){1}" -f $ApiKey.Length, $(if ($generatedHere) { ', newly generated' } else { ', supplied' }))
}

Write-Step 'Setting REPO_MGMT_REQUIRE_API_KEY=true (Machine scope)'
if ($PSCmdlet.ShouldProcess('Machine environment', 'set REPO_MGMT_REQUIRE_API_KEY')) {
    [Environment]::SetEnvironmentVariable('REPO_MGMT_REQUIRE_API_KEY', 'true', 'Machine')
    Write-Note 'the bind guard will now allow a non-loopback bind'
}

# ── 2. Firewall, Private profile only ────────────────────────────────────────
if (-not $SkipFirewall) {
    $ruleName = "RepoManager API $Port"
    Write-Step "Firewall rule '$ruleName' (inbound TCP $Port, Private profile)"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Note 'rule already exists; leaving it alone'
    } elseif ($PSCmdlet.ShouldProcess('Windows Firewall', "add inbound TCP $Port (Private)")) {
        $null = New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $Port -Profile Private
        Write-Note 'added — Private profile only, so a public network stays closed'
    }
} else {
    Write-Step 'Firewall: skipped by request'
}

# ── 3. Rebind the service ────────────────────────────────────────────────────
Write-Step "Reconfiguring $ServiceName to bind $BindAddress"
$installer = Join-Path $WorkspaceRoot 'scripts\Install-RepoManagementService.ps1'
if (-not (Test-Path -LiteralPath $installer)) { throw "Installer not found: $installer" }
if ($PSCmdlet.ShouldProcess($ServiceName, "reconfigure -BindAddress $BindAddress -Port $Port")) {
    & $installer -Action Reconfigure -BindAddress $BindAddress -Port $Port -ServiceName $ServiceName -WorkspaceRoot $WorkspaceRoot
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "Service reconfigure failed with exit code $LASTEXITCODE" }
}

# ── 4. Verify, rather than trust ─────────────────────────────────────────────
Write-Step 'Verifying the live host'
if ($PSCmdlet.ShouldProcess($portalUrl, 'verify auth over the LAN bind')) {
    # Probe BOTH schemes rather than assuming http. Once a TLS certificate is
    # configured (Lane 0.2) the host serves https ONLY and http stops answering,
    # so a hardcoded http probe would burn the full 90s and then blame the
    # service. The scheme that answers first is used for the auth probes below;
    # -SkipCertificateCheck because the portal's certificate is self-signed by
    # design and these probes assert reachability and auth, not trust.
    $probeHost = if ($lanIp -match '^\d') { $lanIp } else { '127.0.0.1' }
    $probeBase = $null
    $lastProbeError = ''
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline -and -not $probeBase) {
        foreach ($probeScheme in @('https', 'http')) {
            try {
                $candidate = "${probeScheme}://${probeHost}:$Port"
                $h = Invoke-WebRequest -Uri "$candidate/health/live" -SkipHttpErrorCheck -SkipCertificateCheck -TimeoutSec 5
                if ([int]$h.StatusCode -ge 200) { $probeBase = $candidate; break }
            } catch {
                # A scheme the host is not serving refuses or resets the
                # connection -- that IS this probe's negative answer, kept so a
                # total timeout can say what the last attempt actually saw.
                $lastProbeError = "${probeScheme}: $($_.Exception.Message)"
            }
        }
        if (-not $probeBase) { Start-Sleep -Seconds 2 }
    }
    $up = [bool]$probeBase
    if (-not $up) { throw "The service did not answer on ${probeHost}:$Port (https or http) within 90s. Last probe error: $lastProbeError. Check: Get-Service $ServiceName; and backend\modules\output\logs\apihost.log" }
    Write-Note "reachable on $probeBase"

    $probe = "$probeBase/api/persistence/status"
    $anon = Invoke-WebRequest -Uri $probe -SkipHttpErrorCheck -SkipCertificateCheck -TimeoutSec 30
    if ([int]$anon.StatusCode -ne 401) {
        throw "SECURITY: an unauthenticated request to $probe returned $([int]$anon.StatusCode), not 401. The API is exposed on the LAN without a key — revert with -BindAddress 127.0.0.1 now."
    }
    Write-Note 'anonymous request rejected (401)'

    $keyed = Invoke-WebRequest -Uri $probe -Headers @{ 'X-Api-Key' = $ApiKey } -SkipHttpErrorCheck -SkipCertificateCheck -TimeoutSec 30
    if ([int]$keyed.StatusCode -ne 200) {
        throw "A keyed request returned $([int]$keyed.StatusCode), not 200. The key in the Machine environment and the one the service loaded disagree — restart $ServiceName and retry."
    }
    Write-Note 'keyed request accepted (200)'

    # The URL the operator carries away reflects the scheme the host actually
    # answered on, not the http this script assumed before probing.
    if ($probeBase -match '^(https?)://') {
        $portalUrl = "$($Matches[1])://${lanIp}:$Port"
        $script:ProbedScheme = $Matches[1]
    }
}

Write-Host ''
if ($WhatIfPreference) {
    Write-Host 'Preview complete — nothing was changed.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "  Portal URL would be : $portalUrl" -ForegroundColor White
    Write-Note 'A key is generated and printed only on a real run; the one above was never set.'
    Write-Host ''
    return
}
Write-Host 'Shared-LAN access is live.' -ForegroundColor Green
Write-Host ''
Write-Host "  Portal URL   : $portalUrl" -ForegroundColor White
Write-Host "  API key      : $ApiKey" -ForegroundColor Yellow
Write-Host ''
Write-Note 'The key is shown once. It lives in the Machine environment, not in the repository.'
Write-Note 'On the phone: open the portal URL and paste the key when prompted; it is stored client-side'
Write-Note 'and sent as X-Api-Key on every request.'
Write-Host ''
# State the transport the verification actually saw, never an assumption. The
# old text said "TLS is NOT enabled" unconditionally, which became false the day
# the certificate was repaired (Lane 0.2, 2026-08-29) — a script asserting a
# security posture it did not check is the exact defect the transport indicator
# exists to prevent.
if ((Get-Variable -Name ProbedScheme -Scope Script -ErrorAction SilentlyContinue) -and $script:ProbedScheme -eq 'https') {
    Write-Host 'TLS is enabled.' -ForegroundColor Green
    Write-Note 'The portal answered over https; the key and anything typed into it are encrypted in transit.'
    Write-Note 'The certificate is self-signed — import backend\config\tls\portal.cer on the phone to avoid the warning.'
} else {
    Write-Host 'TLS is NOT enabled.' -ForegroundColor Yellow
    Write-Note 'The portal serves plain HTTP, so this key crosses the LAN in the clear and so does'
    Write-Note 'anything typed into the portal. To fix, in this same elevated session:'
    Write-Note '  pwsh -File .\scripts\New-RepoManagementTlsCertificate.ps1 -Force'
    Write-Note '  pwsh -File .\scripts\Install-RepoManagementService.ps1 -Action Reconfigure'
    Write-Note 'That flips the portal to https://, and every plain http:// URL stops working.'
}
Write-Host ''
Write-Note 'To revert entirely:'
Write-Note "  pwsh -File .\scripts\Install-RepoManagementService.ps1 -Action Reconfigure -BindAddress 127.0.0.1 -Port $Port"
Write-Note '  [Environment]::SetEnvironmentVariable(''REPO_MGMT_REQUIRE_API_KEY'', $null, ''Machine'')'
Write-Note '  [Environment]::SetEnvironmentVariable(''REPO_MGMT_API_KEY'', $null, ''Machine'')'
Write-Host ''
Write-Note 'Then record the proof:'
Write-Note '  pwsh -File .\scripts\Add-OperatorVerification.ps1   # see -? for the arguments'
Write-Host ''

<#
.SYNOPSIS
    Release 2.2 auth smoke — proves the API-key gate and the non-loopback bind
    guard end-to-end against a live host.

.DESCRIPTION
    The broad Invoke-ApiHostSmokeTest.ps1 runs the host WITHOUT auth (its
    default), so it can only assert the open-mode contract. This script stands
    up short-lived hosts with auth enforced (via the REPO_MGMT_REQUIRE_API_KEY /
    REPO_MGMT_API_KEY env overrides) to prove:

      1. A non-health /api route returns 401 without a key and succeeds with it.
      2. GET /api/auth/status reflects authEnforced + per-request authenticated.
      3. POST /setup/config writes a valid settings.json (exempt from the gate).
      4. Binding a non-loopback address without auth is refused at startup.

    settings.json is captured before and restored after so the run leaves no
    change on disk.
#>
[CmdletBinding()]
param(
    # Derived from this script's location rather than a hardcoded drive letter,
    # so the suite runs unmodified from any clone location (ROADMAP Lane 0.3).
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$Port = 7091,
    [int]$BindGuardPort = 7092,
    [int]$CorsRatePort = 7093,
    [int]$TlsPort = 7095,
    [int]$RequestTimeoutSec = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$smokeRoot = Join-Path $WorkspaceRoot 'output\smoke\auth'
$null = New-Item -ItemType Directory -Path $smokeRoot -Force
$logPath = Join-Path $smokeRoot 'auth-smoke.log'
$settingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$settingsBackup = if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw } else { $null }
$testKey = ([guid]::NewGuid().ToString('n') + [guid]::NewGuid().ToString('n'))

function Invoke-AuthRequest {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [object]$Body)
    $splat = @{ Uri = $Uri; Method = $Method; SkipHttpErrorCheck = $true; TimeoutSec = $RequestTimeoutSec }
    if ($Headers) { $splat.Headers = $Headers }
    if ($null -ne $Body) { $splat.ContentType = 'application/json'; $splat.Body = ($Body | ConvertTo-Json -Depth 6) }
    $resp = Invoke-WebRequest @splat
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($resp.Content) -and $resp.Content.TrimStart() -match '^[\{\[]') {
        try { $json = $resp.Content | ConvertFrom-Json } catch { $json = $null }
    }
    return [pscustomobject]@{ StatusCode = [int]$resp.StatusCode; Content = [string]$resp.Content; Json = $json; Headers = $resp.Headers }
}

function Wait-Ready {
    param([string]$Uri, [System.Management.Automation.Job]$Job, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($Job.State -in @('Failed', 'Stopped', 'Completed')) {
            $out = Receive-Job -Job $Job -Keep -ErrorAction SilentlyContinue | Out-String
            throw "Auth host job exited before readiness. State=$($Job.State). Output=$($out.Trim())"
        }
        try {
            $r = Invoke-WebRequest -Uri $Uri -Method Get -SkipHttpErrorCheck -TimeoutSec 5
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return }
        } catch { Start-Sleep -Milliseconds 400 }
        Start-Sleep -Milliseconds 400
    }
    throw "Auth host did not become ready within $TimeoutSeconds seconds."
}

$enforceSignal = Join-Path $smokeRoot 'auth-enforce.signal'
$guardSignal = Join-Path $smokeRoot 'auth-guard.signal'
Remove-Item -LiteralPath $enforceSignal, $guardSignal -Force -ErrorAction SilentlyContinue

$enforceJob = $null
$guardJob = $null
$rateJob = $null
$tlsJob = $null
try {
    # ── Part 1: enforced-auth host on loopback ──────────────────────────────
    Write-Host '[STEP] Starting auth-enforced host (loopback)' -ForegroundColor Cyan
    $enforceJob = Start-Job -ScriptBlock {
        param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath, $ApiKey)
        $env:REPO_MGMT_REQUIRE_API_KEY = 'true'
        $env:REPO_MGMT_API_KEY = $ApiKey
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
    } -ArgumentList $hostScript, $WorkspaceRoot, $logPath, $Port, $enforceSignal, $testKey

    $base = "http://127.0.0.1:$Port"
    Wait-Ready -Uri "$base/health/live" -Job $enforceJob

    Write-Host '[STEP] Health route is exempt from auth' -ForegroundColor Cyan
    $health = Invoke-AuthRequest -Method Get -Uri "$base/health/live"
    if ($health.StatusCode -ne 200) { throw "/health/live expected 200 with auth enforced, got $($health.StatusCode)" }

    Write-Host '[STEP] Protected /api route without key -> 401' -ForegroundColor Cyan
    $noKey = Invoke-AuthRequest -Method Get -Uri "$base/api/persistence/status"
    if ($noKey.StatusCode -ne 401) { throw "/api/persistence/status without key expected 401, got $($noKey.StatusCode). Body=$($noKey.Content)" }

    Write-Host '[STEP] Protected /api route with X-Api-Key -> not 401' -ForegroundColor Cyan
    $withKey = Invoke-AuthRequest -Method Get -Uri "$base/api/persistence/status" -Headers @{ 'X-Api-Key' = $testKey }
    if ($withKey.StatusCode -eq 401) { throw "/api/persistence/status with valid X-Api-Key must not be 401" }
    if ($withKey.StatusCode -ne 200) { throw "/api/persistence/status with valid key expected 200, got $($withKey.StatusCode). Body=$($withKey.Content)" }

    Write-Host '[STEP] Authorization: Bearer also accepted' -ForegroundColor Cyan
    $bearer = Invoke-AuthRequest -Method Get -Uri "$base/api/persistence/status" -Headers @{ 'Authorization' = "Bearer $testKey" }
    if ($bearer.StatusCode -eq 401) { throw "Authorization: Bearer <key> must be accepted" }

    Write-Host '[STEP] auth-status reflects enforcement + per-request authenticated' -ForegroundColor Cyan
    $authNoKey = Invoke-AuthRequest -Method Get -Uri "$base/api/auth/status"
    if ($authNoKey.Json.data.authEnforced -ne $true) { throw "auth/status expected authEnforced=true" }
    if ($authNoKey.Json.data.authenticated -ne $false) { throw "auth/status without key expected authenticated=false" }
    $authWithKey = Invoke-AuthRequest -Method Get -Uri "$base/api/auth/status" -Headers @{ 'X-Api-Key' = $testKey }
    if ($authWithKey.Json.data.authenticated -ne $true) { throw "auth/status with key expected authenticated=true" }

    Write-Host '[STEP] /setup/config writes a valid settings.json (exempt from gate)' -ForegroundColor Cyan
    # This step asserts that VALID roots return 200, so it has to supply roots
    # that are valid on the machine running the test — not whatever the tracked
    # settings.json happens to name. Tracked config carries the operator's own
    # workspace path, which does not exist on a CI runner.
    #
    # This used to pass on CI only by accident: Invoke-ApiHostSmokeTest runs
    # earlier in the same job and left its runner-local fixture path behind in
    # settings.json, which this step then read back. Once that smoke started
    # restoring the file byte-exact (ROADMAP Lane 0.1), the borrowed value went
    # away and the hidden cross-test dependency surfaced as a 400 here.
    $currentRoots = @()
    if ($settingsBackup) {
        try { $currentRoots = @((ConvertFrom-Json $settingsBackup).inventory.localRoots) } catch { $currentRoots = @() }
    }
    $currentRoots = @($currentRoots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath ([string]$_)) })
    if (@($currentRoots).Count -eq 0) { $currentRoots = @($WorkspaceRoot) }
    $setup = Invoke-AuthRequest -Method Post -Uri "$base/setup/config" -Body @{ localRoots = $currentRoots }
    if ($setup.StatusCode -ne 200) { throw "/setup/config (valid roots) expected 200, got $($setup.StatusCode). Body=$($setup.Content)" }
    if ($setup.Json.data.needsSetup -ne $false) { throw "/setup/config should report needsSetup=false after writing" }
    $null = ConvertFrom-Json (Get-Content -LiteralPath $settingsPath -Raw)  # must still parse

    Write-Host '[STEP] Stopping auth-enforced host' -ForegroundColor Cyan
    Set-Content -LiteralPath $enforceSignal -Value 'stop' -Encoding ASCII
    Wait-Job -Job $enforceJob -Timeout 20 | Out-Null

    # ── Part 2: non-loopback bind guard ─────────────────────────────────────
    Write-Host '[STEP] Non-loopback bind without auth is refused at startup' -ForegroundColor Cyan
    $guardJob = Start-Job -ScriptBlock {
        param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath)
        # No auth env set -> a 0.0.0.0 bind must be refused before Start().
        $env:REPO_MGMT_REQUIRE_API_KEY = ''
        $env:REPO_MGMT_API_KEY = ''
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '0.0.0.0' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
    } -ArgumentList $hostScript, $WorkspaceRoot, ("$logPath.guard"), $BindGuardPort, $guardSignal

    Wait-Job -Job $guardJob -Timeout 40 | Out-Null
    $guardLog = "$logPath.guard"
    $guardOut = ''
    if (Test-Path -LiteralPath $guardLog) { $guardOut = (Get-Content -LiteralPath $guardLog -Raw -ErrorAction SilentlyContinue) }
    $guardOut += (Receive-Job -Job $guardJob -ErrorAction SilentlyContinue 2>&1 | Out-String)
    $guardHealthReachable = $false
    try {
        $g = Invoke-WebRequest -Uri "http://127.0.0.1:$BindGuardPort/health/live" -Method Get -SkipHttpErrorCheck -TimeoutSec 3
        $guardHealthReachable = ($g.StatusCode -ge 200)
    } catch { $guardHealthReachable = $false }
    if ($guardHealthReachable) { throw "Bind guard failed: host came up on a non-loopback bind without auth" }
    if ($guardOut -notmatch 'Refusing to bind') { throw "Bind guard did not emit the expected refusal. Captured: $($guardOut.Trim())" }

    # ── Part 3: scoped CORS + rate limiting + github auth status ─────────────
    Write-Host '[STEP] Starting host with scoped CORS + rate limit (no auth)' -ForegroundColor Cyan
    $corsOrigin = 'https://smoke.example.test'
    $rateSignal = Join-Path $smokeRoot 'auth-rate.signal'
    Remove-Item -LiteralPath $rateSignal -Force -ErrorAction SilentlyContinue
    $rateJob = Start-Job -ScriptBlock {
        param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath, $Origin)
        $env:REPO_MGMT_REQUIRE_API_KEY = ''
        $env:REPO_MGMT_API_KEY = ''
        $env:REPO_MGMT_CORS_ORIGIN = $Origin
        $env:REPO_MGMT_RATE_LIMIT_MAX = '3'
        $env:REPO_MGMT_RATE_LIMIT_WINDOW = '60'
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
    } -ArgumentList $hostScript, $WorkspaceRoot, ("$logPath.rate"), $CorsRatePort, $rateSignal, $corsOrigin

    $rbase = "http://127.0.0.1:$CorsRatePort"
    Wait-Ready -Uri "$rbase/health/live" -Job $rateJob

    Write-Host '[STEP] Scoped CORS origin echoed on responses' -ForegroundColor Cyan
    $corsResp = Invoke-AuthRequest -Method Get -Uri "$rbase/api/persistence/status"
    $allowOrigin = [string]$corsResp.Headers['Access-Control-Allow-Origin']
    if ($allowOrigin -ne $corsOrigin) { throw "CORS scoping failed: expected Access-Control-Allow-Origin '$corsOrigin', got '$allowOrigin'" }

    Write-Host '[STEP] GitHub auth status route reports a mode + precedence' -ForegroundColor Cyan
    $ghStatus = Invoke-AuthRequest -Method Get -Uri "$rbase/api/auth/github/status"
    if ($null -eq $ghStatus.Json -or $ghStatus.Json.success -ne $true) { throw "/api/auth/github/status did not return success=true. Body=$($ghStatus.Content)" }
    if ([string]::IsNullOrWhiteSpace([string]$ghStatus.Json.data.mode)) { throw "/api/auth/github/status missing data.mode" }
    if (@($ghStatus.Json.data.precedence).Count -lt 1) { throw "/api/auth/github/status missing data.precedence" }

    Write-Host '[STEP] Rate limit trips 429 past the window budget' -ForegroundColor Cyan
    $got429 = $false
    for ($i = 0; $i -lt 8; $i++) {
        $r = Invoke-AuthRequest -Method Get -Uri "$rbase/api/persistence/status"
        if ($r.StatusCode -eq 429) { $got429 = $true; break }
    }
    if (-not $got429) { throw "Rate limit did not return 429 after exceeding the configured budget (max=3/60s)" }

    Write-Host '[STEP] Stopping CORS/rate host' -ForegroundColor Cyan
    Set-Content -LiteralPath $rateSignal -Value 'stop' -Encoding ASCII
    Wait-Job -Job $rateJob -Timeout 20 | Out-Null

    # ── Part 4: optional TLS termination ────────────────────────────────────
    Write-Host '[STEP] Generating self-signed cert + starting host with TLS' -ForegroundColor Cyan
    $pfxPath = Join-Path $smokeRoot 'tls-smoke.pfx'
    $pfxPass = 'tls-smoke-pass'
    $rsaCert = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $certReq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=localhost', $rsaCert, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $selfCert = $certReq.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(30))
        [System.IO.File]::WriteAllBytes($pfxPath, $selfCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pfxPass))
    } finally { $rsaCert.Dispose() }
    $tlsSignal = Join-Path $smokeRoot 'auth-tls.signal'
    Remove-Item -LiteralPath $tlsSignal -Force -ErrorAction SilentlyContinue
    $tlsJob = Start-Job -ScriptBlock {
        param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath, $Pfx, $PfxPass)
        # This step asserts TLS transport, not the auth gate, so the gate is
        # explicitly off — same as the non-loopback guard job above. Start-Job
        # inherits the parent environment, and on a machine where the installed
        # service has set REPO_MGMT_REQUIRE_API_KEY/REPO_MGMT_API_KEY at Machine
        # scope this host would otherwise enforce auth and answer 401, failing a
        # TLS assertion for a reason that has nothing to do with TLS. CI runners
        # start clean, which is why this only ever bit local runs.
        $env:REPO_MGMT_REQUIRE_API_KEY = ''
        $env:REPO_MGMT_API_KEY = ''
        $env:REPO_MGMT_TLS_PFX = $Pfx
        $env:REPO_MGMT_TLS_PFX_PASSWORD = $PfxPass
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
    } -ArgumentList $hostScript, $WorkspaceRoot, ("$logPath.tls"), $TlsPort, $tlsSignal, $pfxPath, $pfxPass

    $tlsBase = "https://127.0.0.1:$TlsPort"
    $tlsReady = $false
    $tlsDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $tlsDeadline) {
        if ($tlsJob.State -in @('Failed', 'Stopped', 'Completed')) {
            $o = Receive-Job -Job $tlsJob -Keep -ErrorAction SilentlyContinue | Out-String
            throw "TLS host job exited before readiness. Output=$($o.Trim())"
        }
        try {
            $r = Invoke-WebRequest -Uri "$tlsBase/health/live" -Method Get -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 5
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { $tlsReady = $true; break }
        } catch { Start-Sleep -Milliseconds 400 }
        Start-Sleep -Milliseconds 400
    }
    if (-not $tlsReady) { throw 'TLS host did not become ready over https within 30s' }

    Write-Host '[STEP] HTTPS health + /api route over TLS' -ForegroundColor Cyan
    $tlsHealth = Invoke-WebRequest -Uri "$tlsBase/health/live" -Method Get -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 10
    if ([int]$tlsHealth.StatusCode -ne 200) { throw "TLS /health/live expected 200, got $($tlsHealth.StatusCode)" }
    $tlsApi = Invoke-WebRequest -Uri "$tlsBase/api/persistence/status" -Method Get -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 15
    if ([int]$tlsApi.StatusCode -ne 200) { throw "TLS /api/persistence/status expected 200, got $($tlsApi.StatusCode)" }
    Write-Host '  TLS ok: https health + /api route return 200 over an SslStream connection' -ForegroundColor DarkGray
    Set-Content -LiteralPath $tlsSignal -Value 'stop' -Encoding ASCII
    Wait-Job -Job $tlsJob -Timeout 20 | Out-Null

    Write-Host '[PASS] Auth smoke completed' -ForegroundColor Green
}
finally {
    Set-Content -LiteralPath $enforceSignal -Value 'stop' -Encoding ASCII -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $guardSignal -Value 'stop' -Encoding ASCII -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $smokeRoot 'auth-rate.signal') -Value 'stop' -Encoding ASCII -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $smokeRoot 'auth-tls.signal') -Value 'stop' -Encoding ASCII -ErrorAction SilentlyContinue
    foreach ($j in @($enforceJob, $guardJob, $rateJob, $tlsJob)) {
        if ($j) { Stop-Job -Job $j -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue }
    }
    foreach ($p in @($Port, $BindGuardPort, $CorsRatePort, $TlsPort)) {
        Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique |
            ForEach-Object { try { Stop-Process -Id $_ -Force -ErrorAction Stop } catch { } }
    }
    # Restore settings.json exactly as it was before the run.
    if ($null -ne $settingsBackup) { Set-Content -LiteralPath $settingsPath -Value $settingsBackup -Encoding UTF8 -NoNewline }
}

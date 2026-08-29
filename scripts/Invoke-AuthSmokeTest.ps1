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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '',
    Justification = 'Every Start-Job block here declares its own param() and is bound through -ArgumentList, which is the correct pattern and the one $using: exists to replace. The analyzer cannot follow -ArgumentList binding, so it reports each parameter as an undeclared capture. Suppressed file-wide rather than banked as baseline debt: a real $using: omission in this file would be a param() the ArgumentList does not fill, which fails the job outright and is caught by the smoke, not by lint.')]
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
# The git-TRACKED settings file. This smoke used to write it -- the
# /setup/config step below persists a config -- and put it back in the finally.
# It no longer does: every host started here resolves settings through
# Get-PortalSettingsPath, which honours REPO_MGMT_SETTINGS_PATH. The tracked
# bytes are captured only to PROVE the file was never touched.
$trackedSettingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$trackedSettingsAtStart = if (Test-Path -LiteralPath $trackedSettingsPath) {
    Get-Content -LiteralPath $trackedSettingsPath -Raw
} else { $null }

# The file every host in this smoke actually reads and writes, seeded from the
# operator's real configuration so the run starts from their settings rather
# than a synthetic one. Every assertion below that checks "the host must not
# persist a secret into settings" points HERE deliberately: pointed at the
# tracked file instead, those checks would pass because the host cannot write
# it any more, which is a vacuous green, not a proof.
$settingsPath = Join-Path $smokeRoot 'settings.smoke.json'
Set-Content -LiteralPath $settingsPath `
    -Value $(if ($null -ne $trackedSettingsAtStart) { $trackedSettingsAtStart } else { '{}' }) `
    -Encoding UTF8 -NoNewline

# Set on THIS process, which is the whole of the blast radius: the suite invokes
# this script with `pwsh -File`, so the variable dies with it, and the Start-Job
# children below inherit it exactly as the hosts need. The finally clears it
# anyway for the case where an operator runs this script in their own session.
$env:REPO_MGMT_SETTINGS_PATH = $settingsPath
Write-Host ("  settings isolated to {0} (the operator's tracked settings.json is never written)" -f $settingsPath) -ForegroundColor DarkGray

# Every host started here except the TLS step speaks plain HTTP, and Start-Job
# inherits this process's environment. An inherited REPO_MGMT_TLS_PFX -- set at
# MACHINE scope by the installed service -- would wrap those listeners in an
# SslStream and fail their readiness checks in the handshake. Cleared here for
# all of them; the TLS step sets its own pfx explicitly in its own job, so it is
# unaffected. Inert until 2026-08-29 only because the operator's certificate
# could not be loaded; repairing it turned a latent trap into three red gates.
$env:REPO_MGMT_TLS_PFX = ''
$env:REPO_MGMT_TLS_PFX_PASSWORD = ''
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
    if ($trackedSettingsAtStart) {
        try { $currentRoots = @((ConvertFrom-Json $trackedSettingsAtStart).inventory.localRoots) } catch { $currentRoots = @() }
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

    # ── Part 2b: the shared-LAN path — auth ENFORCES over a non-loopback bind ─
    # Part 1 proved the gate on loopback and Part 2 proved refusal off it, so
    # nothing proved the claim the shared-LAN item actually makes: that a host
    # bound off-loopback is both reachable AND gated. Without this, "bind it to
    # the LAN with auth on" was an untested combination.
    #
    # 0.0.0.0 rather than a hardcoded LAN IP: it is non-loopback by
    # Test-IsLoopbackAddress (so it exercises the same guard the LAN bind hits),
    # it binds every interface including 127.0.0.1 so the probe is portable, and
    # it is exactly what the installed service uses.
    Write-Host '[STEP] Non-loopback bind WITH auth binds and still enforces the key' -ForegroundColor Cyan
    $lanSignal = Join-Path $smokeRoot 'auth-lan.signal'
    Remove-Item -LiteralPath $lanSignal -Force -ErrorAction SilentlyContinue
    $lanKey = ([guid]::NewGuid().ToString('n') + [guid]::NewGuid().ToString('n'))
    $lanJob = Start-Job -ScriptBlock {
        param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath, $Key)
        $env:REPO_MGMT_REQUIRE_API_KEY = 'true'
        $env:REPO_MGMT_API_KEY = $Key
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '0.0.0.0' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
    } -ArgumentList $hostScript, $WorkspaceRoot, ("$logPath.lan"), $BindGuardPort, $lanSignal, $lanKey

    try {
        $lanBase = "http://127.0.0.1:$BindGuardPort"
        # Wait-Ready throws on failure and returns nothing on success — do not
        # test its return value.
        Wait-Ready -Uri "$lanBase/health/live" -Job $lanJob -TimeoutSeconds 40
        $lanLog = if (Test-Path -LiteralPath "$logPath.lan") { Get-Content -LiteralPath "$logPath.lan" -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($lanLog -match 'Refusing to bind') {
            throw 'The bind guard refused a non-loopback bind even though auth was enforced'
        }
        # The exposure only becomes safe if the gate is actually live over it.
        $lanAnon = Invoke-AuthRequest -Method Get -Uri "$lanBase/api/persistence/status"
        if ($lanAnon.StatusCode -ne 401) {
            throw "Off-loopback, an unauthenticated /api request must be 401, got $($lanAnon.StatusCode). An open API on the LAN is the failure this item exists to prevent."
        }
        $lanKeyed = Invoke-AuthRequest -Method Get -Uri "$lanBase/api/persistence/status" -Headers @{ 'X-Api-Key' = $lanKey }
        if ($lanKeyed.StatusCode -ne 200) {
            throw "Off-loopback, a keyed /api request expected 200, got $($lanKeyed.StatusCode). Body=$($lanKeyed.Content)"
        }
        $lanStatus = Invoke-AuthRequest -Method Get -Uri "$lanBase/api/auth/status"
        if ($lanStatus.Json.data.authEnforced -ne $true) {
            throw 'auth/status must report authEnforced=true over a non-loopback bind'
        }
        # The env-var path must NOT have persisted a key into the tracked config.
        $lanSettings = ConvertFrom-Json (Get-Content -LiteralPath $settingsPath -Raw)
        $persistedKey = ''
        if ($null -ne $lanSettings.PSObject.Properties['auth'] -and $null -ne $lanSettings.auth -and
            $null -ne $lanSettings.auth.PSObject.Properties['apiKey']) { $persistedKey = [string]$lanSettings.auth.apiKey }
        if (-not [string]::IsNullOrWhiteSpace($persistedKey)) {
            throw "Enabling auth by environment variable wrote an API key into the host's settings file ($settingsPath). The key must stay in the environment and never be persisted."
        }
        Write-Host '  non-loopback bind: reachable, gated, and no key written to tracked config' -ForegroundColor DarkGray
    } finally {
        Set-Content -LiteralPath $lanSignal -Value 'stop' -Encoding ASCII
        Wait-Job -Job $lanJob -Timeout 20 | Out-Null
        Stop-Job -Job $lanJob -ErrorAction SilentlyContinue
        Remove-Job -Job $lanJob -Force -ErrorAction SilentlyContinue
    }

    # ── Part 2c: a generated key never lands in a git-tracked file ───────────
    # The half-step an operator naturally takes on the service path — set the
    # toggle, forget the key — used to make the host write a 64-char plaintext
    # key into backend/config/settings.json. That file is listed in .gitignore
    # but is still TRACKED (committed before the rule), so the ignore entry does
    # nothing and one `git add -A` publishes the key.
    Write-Host '[STEP] Auth enabled without a key stores it outside version control' -ForegroundColor Cyan
    $genSignal = Join-Path $smokeRoot 'auth-gen.signal'
    Remove-Item -LiteralPath $genSignal -Force -ErrorAction SilentlyContinue
    $generatedKeyPath = Join-Path $WorkspaceRoot 'output\auth\api-key'
    $generatedKeyBackup = if (Test-Path -LiteralPath $generatedKeyPath) { Get-Content -LiteralPath $generatedKeyPath -Raw } else { $null }
    Remove-Item -LiteralPath $generatedKeyPath -Force -ErrorAction SilentlyContinue
    $settingsHashBefore = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
    $genJob = Start-Job -ScriptBlock {
        param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath)
        # The toggle, and deliberately NO key.
        $env:REPO_MGMT_REQUIRE_API_KEY = 'true'
        $env:REPO_MGMT_API_KEY = ''
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
    } -ArgumentList $hostScript, $WorkspaceRoot, ("$logPath.gen"), $BindGuardPort, $genSignal
    try {
        Wait-Ready -Uri "http://127.0.0.1:$BindGuardPort/health/live" -Job $genJob -TimeoutSeconds 40
        $settingsHashAfter = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
        if ($settingsHashAfter -ne $settingsHashBefore) {
            $genSettings = ConvertFrom-Json (Get-Content -LiteralPath $settingsPath -Raw)
            $wrote = ''
            if ($null -ne $genSettings.PSObject.Properties['auth'] -and $null -ne $genSettings.auth -and
                $null -ne $genSettings.auth.PSObject.Properties['apiKey']) { $wrote = [string]$genSettings.auth.apiKey }
            throw ("Enabling auth without a key modified the host's settings file ($settingsPath)." +
                $(if ($wrote) { " It now holds a $($wrote.Length)-character API key. A generated secret must never reach a tracked file." } else { '' }))
        }
        if (-not (Test-Path -LiteralPath $generatedKeyPath -PathType Leaf)) {
            throw "The generated key was not persisted to $generatedKeyPath; it would change on every restart."
        }
        $genKeyText = (Get-Content -LiteralPath $generatedKeyPath -Raw).Trim()
        if ($genKeyText.Length -lt 32) { throw "The generated key looks too short to be a credential ($($genKeyText.Length) chars)." }
        # And it must actually be the key the gate is enforcing.
        $genProbe = Invoke-AuthRequest -Method Get -Uri "http://127.0.0.1:$BindGuardPort/api/persistence/status" -Headers @{ 'X-Api-Key' = $genKeyText }
        if ($genProbe.StatusCode -ne 200) {
            throw "The stored generated key was rejected by the running host (HTTP $($genProbe.StatusCode)); persisting it is pointless if it is not the live key."
        }
        Write-Host ("  generated key stored at output\auth\api-key ({0} chars), settings.json untouched" -f $genKeyText.Length) -ForegroundColor DarkGray
    } finally {
        Set-Content -LiteralPath $genSignal -Value 'stop' -Encoding ASCII
        Wait-Job -Job $genJob -Timeout 20 | Out-Null
        Stop-Job -Job $genJob -ErrorAction SilentlyContinue
        Remove-Job -Job $genJob -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $generatedKeyPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $generatedKeyBackup) { Set-Content -LiteralPath $generatedKeyPath -Value $generatedKeyBackup -NoNewline }
    }

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
    $env:REPO_MGMT_SETTINGS_PATH = $null
    # PROVE the tracked config was never written rather than putting it back.
    # With the host redirected there is no write path to it, so a difference
    # here means a call site went round Get-PortalSettingsPath -- a regression
    # that must fail loudly, not be silently repaired.
    if ($null -ne $trackedSettingsAtStart) {
        $trackedNow = if (Test-Path -LiteralPath $trackedSettingsPath) {
            Get-Content -LiteralPath $trackedSettingsPath -Raw
        } else { $null }
        if ($trackedNow -ne $trackedSettingsAtStart) {
            Set-Content -LiteralPath $trackedSettingsPath -Value $trackedSettingsAtStart -Encoding UTF8 -NoNewline
            throw 'auth smoke mutated the git-tracked backend/config/settings.json (restored); a call site is resolving the settings path inline.'
        }
        Write-Host '  verified: tracked settings.json byte-identical across the run' -ForegroundColor DarkGray
    }
}

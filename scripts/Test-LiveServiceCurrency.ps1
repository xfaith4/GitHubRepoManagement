<#
.SYNOPSIS
    Is the running portal serving the code that is in this working tree?

.DESCRIPTION
    A health check proves the service is UP. It does not prove the service is
    CURRENT. On 2026-08-20 the live service had been running for weeks while
    main moved twenty pull requests ahead, and nothing in the product said so:
    /health/live answered 200 the whole time.

    This answers the other question. It derives the GET routes the source
    declares, asks the running service for each, and reports the ones it does
    not have -- which is the same thing as reporting how far behind it is.

    THE TRAP THIS AVOIDS: unmatched routes do not 404 here. The host serves
    the SPA's index.html for anything it does not recognise, so an absent
    route answers 200 with `text/html`. A check written against STATUS CODES
    would call every missing route present. Content type is the signal; status
    is not. (Recorded the hard way -- the same fallback has fooled a
    route-existence check in this repo before.)

    Read-only. It issues GET requests and changes nothing, so it is safe to
    run against a live service at any time, and needs no elevation.

.PARAMETER BaseUrl
    The running portal. Defaults to the service's own bind address and port.

.PARAMETER WorkspaceRoot
    Source of truth for what routes SHOULD exist. Defaults to this repo.

.PARAMETER ApiKey
    Sent as X-Api-Key. Only needed once API authentication is enabled; a 401 from
    a route that exists would otherwise still read as present, so this is about
    speaking to the portal normally rather than about the verdict.

.PARAMETER SkipCertificateCheck
    Accept the portal's self-signed certificate. Implied when BaseUrl is https on
    a loopback address, because that is the only certificate it can be.

.EXAMPLE
    pwsh -File scripts/Test-LiveServiceCurrency.ps1
.EXAMPLE
    # After an elevated repair, prove the upgrade actually landed:
    pwsh -File scripts/Install-RepoManagementService.ps1 -Action Repair
    pwsh -File scripts/Test-LiveServiceCurrency.ps1
#>
[CmdletBinding()]
param(
    # https, not http: the portal has served TLS since Lane 0.2 (2026-08-29) and
    # plain http stopped answering that day. This default said http for two weeks
    # after that, so the script reported "Is the service running?" against a
    # perfectly healthy service -- the one answer it must never give wrongly,
    # because its whole job is telling an operator whether a deploy landed.
    [Parameter()][string]$BaseUrl = 'https://127.0.0.1:7071',
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][int]$TimeoutSeconds = 10,
    [Parameter()][string]$ApiKey = $env:REPO_MGMT_API_KEY,
    [Parameter()][switch]$SkipCertificateCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DeclaredGetRoute {
    <#
    .SYNOPSIS
        The GET routes the source declares, derived rather than listed.
    .DESCRIPTION
        A maintained list would drift the moment someone adds a route, and a
        currency check that misses new routes reports currency it has not
        established. Parameterised routes ({id}) are skipped: they need a real
        identifier, and a 404 for a made-up one proves nothing about the code.
        Expensive scan routes are skipped too -- this must be safe to run
        against a live service.
    #>
    param([Parameter(Mandatory = $true)][string]$HostScriptPath)

    $text = Get-Content -LiteralPath $HostScriptPath -Raw -Encoding UTF8
    $routes = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($text, "(?m)^\s*'GET (/[^']+)'\s*\{")) {
        $path = $match.Groups[1].Value
        if ($path -match '\{') { continue }
        if ($path -match '\*') { continue }
        # Read-only and cheap only. These either scan, or stream, or need a
        # body; none of them tell us anything about code currency that the
        # rest do not.
        if ($path -in @('/api/portfolio/assessment', '/api/operations/repos', '/api/status', '/api/roadmap/audit', '/api/docs/audit')) { continue }
        if (-not $routes.Contains($path)) { $routes.Add($path) | Out-Null }
    }
    return $routes.ToArray()
}

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
if (-not (Test-Path -LiteralPath $hostScript)) { throw "API host source not found at $hostScript" }

$declared = @(Get-DeclaredGetRoute -HostScriptPath $hostScript)
if ($declared.Count -eq 0) {
    throw 'Derived zero GET routes from the host source. The route syntax changed, or this check has stopped checking anything.'
}

Write-Host ("Checking {0} against {1} declared GET route(s)..." -f $BaseUrl, $declared.Count) -ForegroundColor Cyan

$present = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
# Routes this run could not decide about, kept apart from the ones it decided.
# A timeout is not evidence of absence -- an absent route hits the SPA fallback
# and returns 200 text/html immediately, so it cannot be the slow one.
$timedOut = [System.Collections.Generic.List[string]]::new()
$errored = [System.Collections.Generic.List[string]]::new()
$unreachable = $false

# One request shape for every route. The certificate on a loopback https bind is
# the portal's own self-signed one, so requiring -SkipCertificateCheck there would
# only be a flag the operator has to remember at the moment the tool is meant to
# be answering a question for them.
$requestArgs = @{
    Method          = 'Get'
    TimeoutSec      = $TimeoutSeconds
    UseBasicParsing = $true
    ErrorAction     = 'Stop'
}
$isLoopbackTls = $BaseUrl -match '^https://(127\.0\.0\.1|\[::1\]|localhost)\b'
if ($SkipCertificateCheck.IsPresent -or $isLoopbackTls) { $requestArgs.SkipCertificateCheck = $true }
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $requestArgs.Headers = @{ 'X-Api-Key' = $ApiKey } }

foreach ($route in $declared) {
    try {
        $response = Invoke-WebRequest -Uri ($BaseUrl + $route) @requestArgs
        $contentType = [string]$response.Headers['Content-Type']
        # The SPA fallback answers 200 text/html for anything unmatched, so a
        # JSON content type -- not a 2xx -- is what proves the route exists.
        if ($contentType -like '*application/json*') { $present.Add($route) | Out-Null }
        else { $missing.Add($route) | Out-Null }
    }
    catch {
        # One classification path, deliberately. When this had two catch blocks
        # they disagreed about what counts as "the service is down", and the
        # narrower one won for the wrong reason.
        $statusCode = 0
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
        if ($statusCode -ge 400 -and $statusCode -lt 600) {
            # A 4xx/5xx from a route that EXISTS still proves the code is there;
            # only the SPA fallback means absent, and that arrives as a 200.
            # 401 lands here whenever API authentication is on, which is normal.
            $present.Add($route) | Out-Null
            continue
        }

        # A slow route is not a dead service. Measured 2026-09-13:
        # /api/maintenance/ledgers exceeded the 10s timeout on a healthy portal
        # and this script answered "Could not reach ... Is the service running?"
        # -- about a service that was serving. That is the worst answer this tool
        # can give, because an operator reads it to decide whether a deploy
        # landed and it points them at the wrong problem entirely.
        if ($_.Exception -is [System.Threading.Tasks.TaskCanceledException] -or
            $_.Exception -is [System.TimeoutException] -or
            $_.Exception -is [System.OperationCanceledException]) {
            $timedOut.Add($route) | Out-Null
            continue
        }

        # A genuine connection failure. Only the service can be unreachable, and
        # only while nothing has answered yet: once a route has responded, a
        # broken one is a route problem and the run should finish and say so.
        if ($present.Count -eq 0 -and $missing.Count -eq 0 -and $timedOut.Count -eq 0) {
            $unreachable = $true
            break
        }
        $errored.Add($route) | Out-Null
    }
}

if ($unreachable) {
    Write-Host ("Could not reach {0} on the first route. Is the service running?" -f $BaseUrl) -ForegroundColor Red
    Write-Host '  If it is running, check the scheme: the portal has served TLS since 2026-08-29 and plain http does not answer.' -ForegroundColor DarkGray
    return [pscustomobject]@{
        current = $false; reachable = $false; declaredCount = $declared.Count
        missing = @(); timedOut = @(); errored = @()
    }
}

# Undecided routes must not read as current. Saying "all served" while some were
# never proven is the false green half of the same defect as the false red above.
$isCurrent = ($missing.Count -eq 0 -and $timedOut.Count -eq 0 -and $errored.Count -eq 0)

Write-Host ''
if ($isCurrent) {
    Write-Host ("CURRENT: all {0} declared GET route(s) are served." -f $declared.Count) -ForegroundColor Green
}
elseif ($missing.Count -eq 0) {
    Write-Host ("REACHABLE, NOT PROVEN: {0} of {1} route(s) answered; none is missing, but {2} could not be decided." -f $present.Count, $declared.Count, ($timedOut.Count + $errored.Count)) -ForegroundColor Yellow
    foreach ($route in $timedOut) { Write-Host ("  timed out after {0}s: {1}" -f $TimeoutSeconds, $route) -ForegroundColor DarkYellow }
    foreach ($route in $errored) { Write-Host ("  errored: {0}" -f $route) -ForegroundColor DarkYellow }
    Write-Host ''
    Write-Host ("A slow route is not a missing one. Re-run with a longer budget to decide it:" ) -ForegroundColor Cyan
    Write-Host ("  pwsh -File scripts/Test-LiveServiceCurrency.ps1 -TimeoutSeconds 30") -ForegroundColor Cyan
}
else {
    Write-Host ("STALE: {0} of {1} declared GET route(s) are missing from the running service." -f $missing.Count, $declared.Count) -ForegroundColor Yellow
    foreach ($route in $missing) { Write-Host ("  missing: {0}" -f $route) -ForegroundColor DarkYellow }
    Write-Host ''
    Write-Host 'Upgrade it from an ELEVATED PowerShell:' -ForegroundColor Cyan
    Write-Host '  pwsh -File scripts/Install-RepoManagementService.ps1 -Action Repair' -ForegroundColor Cyan
    Write-Host 'then re-run this check to prove the upgrade landed.' -ForegroundColor Cyan
}

return [pscustomobject]@{
    current       = $isCurrent
    reachable     = $true
    declaredCount = $declared.Count
    presentCount  = $present.Count
    missing       = $missing.ToArray()
    timedOut      = $timedOut.ToArray()
    errored       = $errored.ToArray()
}

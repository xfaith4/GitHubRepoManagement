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

.EXAMPLE
    pwsh -File scripts/Test-LiveServiceCurrency.ps1
.EXAMPLE
    # After an elevated repair, prove the upgrade actually landed:
    pwsh -File scripts/Install-RepoManagementService.ps1 -Action Repair
    pwsh -File scripts/Test-LiveServiceCurrency.ps1
#>
[CmdletBinding()]
param(
    [Parameter()][string]$BaseUrl = 'http://127.0.0.1:7071',
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][int]$TimeoutSeconds = 10
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
$unreachable = $false

foreach ($route in $declared) {
    try {
        $response = Invoke-WebRequest -Uri ($BaseUrl + $route) -Method Get -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
        $contentType = [string]$response.Headers['Content-Type']
        # The SPA fallback answers 200 text/html for anything unmatched, so a
        # JSON content type -- not a 2xx -- is what proves the route exists.
        if ($contentType -like '*application/json*') { $present.Add($route) | Out-Null }
        else { $missing.Add($route) | Out-Null }
    }
    catch [System.Net.WebException] {
        $unreachable = $true
        break
    }
    catch {
        # A 4xx/5xx from a route that EXISTS still proves the code is there;
        # only the SPA fallback means absent, and that arrives as a 200.
        $statusCode = 0
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
        if ($statusCode -ge 400 -and $statusCode -lt 600) { $present.Add($route) | Out-Null }
        else { $unreachable = $true; break }
    }
}

if ($unreachable) {
    Write-Host ("Could not reach {0}. Is the service running?" -f $BaseUrl) -ForegroundColor Red
    return [pscustomobject]@{ current = $false; reachable = $false; declaredCount = $declared.Count; missing = @() }
}

$isCurrent = ($missing.Count -eq 0)

Write-Host ''
if ($isCurrent) {
    Write-Host ("CURRENT: all {0} declared GET route(s) are served." -f $declared.Count) -ForegroundColor Green
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
}

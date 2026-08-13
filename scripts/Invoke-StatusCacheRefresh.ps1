<#
.SYNOPSIS
    Refreshes the portfolio status cache out of process, so no HTTP request
    ever waits on a portfolio scan.

.DESCRIPTION
    Measured on the live portal, 2026-08-11:

      * a cold portfolio sweep costs 196.7s
      * the status cache TTL is 120s
      * a cache miss ran the sweep INLINE on the request thread

    The API host serves requests one at a time, so those three facts together
    meant the portal spent roughly two thirds of its life unable to answer
    anything - /health/live included, which is what the watchdog probes. The
    refresh interval was shorter than the refresh took, so it could never
    reach a steady state.

    This script is the other half of the fix. The host now kicks it and returns
    what it already has; this process does the scan and writes the cache.

    It deliberately dot-sources the API host with -LoadDefinitionsOnly rather
    than reimplementing the scan: the cache key, the GitHub metadata join and
    the on-disk cache format must not drift from the host that reads them.
    -WorkspaceRoot and -LogPath are passed through with the values this script
    already holds, so the host's parameter assignment into this scope is a
    no-op instead of a clobber (see PR #119).

.NOTES
    Invoked with & (call), never dot-sourced. Single-flight is the caller's
    job - the host holds a lock file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string[]]$LocalRoots,

    [Parameter()]
    [int]$MaxDepth = 2,

    [Parameter()]
    [switch]$IncludeNonGitFolders,

    [Parameter()]
    [string]$LogPath,

    # Removed on completion however this process exits, so a crashed refresh
    # cannot wedge the portal into "a scan is already running" forever.
    [Parameter()]
    [string]$LockPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$exitCode = 0
try {
    $apiHost = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
    if (-not (Test-Path -LiteralPath $apiHost)) {
        throw "API host not found at: $apiHost"
    }

    # Dot-sourcing assigns the host's param() variables into THIS scope, and two
    # of them collide with ours. Passing our values through already makes the
    # assignment a no-op, but the restore is explicit anyway: that is the idiom
    # the module smoke's dot-source sweep enforces, and "it happens to be
    # harmless" is exactly the reasoning that hid the Release 3.0 defect.
    $callerWorkspaceRoot = $WorkspaceRoot
    $callerLogPath = $LogPath
    . $apiHost -WorkspaceRoot $WorkspaceRoot -LogPath $LogPath -LoadDefinitionsOnly
    $WorkspaceRoot = $callerWorkspaceRoot
    $LogPath = $callerLogPath

    $settings = Get-HostSettings
    $cacheKey = Get-StatusCacheKey -LocalRoots $LocalRoots -MaxDepth $MaxDepth -IncludeNonGitFolders ([bool]$IncludeNonGitFolders)

    Write-HostLog ("[TRACE] status.refresh.worker start roots={0} depth={1} key={2}" -f ($LocalRoots -join ','), $MaxDepth, $cacheKey)
    $started = Get-Date

    $result = Get-StatusAdapterResult -LocalRoots $LocalRoots -MaxDepth $MaxDepth `
        -IncludeNonGitFolders:$IncludeNonGitFolders -LogPath $LogPath

    if ($null -eq $result -or -not $result.success) {
        $reason = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'error') { [string]$result.error } else { 'unknown error' }
        throw "Status scan failed: $reason"
    }

    $result = Add-GitHubMetadataToStatusResult -StatusResult $result -Settings $settings
    $result = Add-StatusCacheMeta -Result $result -CacheMeta (Get-StatusCacheMeta -Hit $false -Source 'background-refresh' `
        -TtlSeconds (Get-StatusCacheTtlSeconds -Settings $settings) -AgeSeconds 0 -BypassRequested:$false `
        -CachedAt ((Get-Date).ToUniversalTime().ToString('o')))

    Save-StatusCache -Key $cacheKey -Response $result
    $statusMs = [int]((Get-Date) - $started).TotalMilliseconds

    # The roadmap and doc-audit scans belong here for the same reason the status
    # scan does: GET /api/portfolio/assessment ran both inline. Its own budget
    # line measured prepMs=40669 on this workspace - and the roadmap branch never
    # called Save-RoadmapCache, so it paid that 40s on EVERY request rather than
    # once per TTL. Scanning here fixes both the freeze and the missing write.
    $roadmapStarted = Get-Date
    $roadmapEntries = @(Invoke-RoadmapScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
    Save-RoadmapCache -Entries $roadmapEntries -ScannedAt ((Get-Date).ToUniversalTime().ToString('o'))
    $roadmapMs = [int]((Get-Date) - $roadmapStarted).TotalMilliseconds

    $docStarted = Get-Date
    $docAuditEntries = @(Invoke-DocAuditScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
    Save-DocAuditCache -Entries $docAuditEntries -AuditedAt ((Get-Date).ToUniversalTime().ToString('o'))
    $docMs = [int]((Get-Date) - $docStarted).TotalMilliseconds

    $auditStarted = Get-Date
    $roadmapAuditEntries = @(Invoke-RoadmapAuditScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
    Save-RoadmapAuditCache -Entries $roadmapAuditEntries -AuditedAt ((Get-Date).ToUniversalTime().ToString('o'))
    $auditMs = [int]((Get-Date) - $auditStarted).TotalMilliseconds

    $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
    Write-HostLog ("[TRACE] status.refresh.worker done repos={0} roadmap={1} docAudit={2} roadmapAudit={3} statusMs={4} roadmapMs={5} docAuditMs={6} roadmapAuditMs={7} totalMs={8}" -f `
        @($result.data.repos).Count, @($roadmapEntries).Count, @($docAuditEntries).Count, @($roadmapAuditEntries).Count, `
        $statusMs, $roadmapMs, $docMs, $auditMs, $elapsed)
}
catch {
    # Reported, never swallowed: a refresh that keeps failing must be visible in
    # the host log rather than presenting as a cache that is merely always cold.
    $message = "status.refresh.worker FAILED: $($_.Exception.Message)"
    try { Write-HostLog ("[ERROR] {0}" -f $message) } catch { Write-Error $message }
    $exitCode = 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($LockPath)) {
        try {
            Remove-Item -LiteralPath $LockPath -Force -ErrorAction Stop
        }
        catch {
            # Not swallowed: a lock this process cannot remove suppresses every
            # future refresh until the host notices the pid is gone. Say so.
            Write-Warning ("status.refresh.worker could not remove lock '{0}': {1}" -f $LockPath, $_.Exception.Message)
        }
    }
}

exit $exitCode

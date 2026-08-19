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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ProgressPath',
    Justification = 'Read by Write-ScanProgress through the call stack; the analyzer cannot see dynamic-scope use.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PhaseDelayMs',
    Justification = 'Read by Test-ScanPhaseGate through the call stack; the analyzer cannot see dynamic-scope use.')]
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
    [string]$LockPath,

    # Release 3.2 milestone 1: the scan is observable and cancellable.
    # ProgressPath receives phase/heartbeat writes the host's scan-status route
    # serves; CancelPath is a marker file checked at phase boundaries -- the
    # progress callbacks deliberately swallow exceptions (a failing tick must
    # not abort a healthy scan), so cancellation lives in the worker's own
    # control flow where nothing can swallow it.
    [Parameter()]
    [string]$ProgressPath,

    [Parameter()]
    [string]$CancelPath,

    # Test hook: stretch each phase so the smoke can prove a cancel lands
    # mid-scan deterministically. Production callers never pass it.
    [Parameter()]
    [int]$PhaseDelayMs = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScanStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$script:LastProgressWrite = [datetime]::MinValue
$script:ScanReposTotal = $null
$script:ScanReposDone = 0

function Write-ScanProgress {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter()][string]$Phase = '',
        [Parameter()][int]$PhasesDone = 0,
        [Parameter()][string]$ErrorMessage = '',
        # Per-repo ticks arrive many times a second during the walk; a terminal
        # state must always land, but heartbeats are throttled to ~1/s.
        [Parameter()][switch]$Force
    )
    if ([string]::IsNullOrWhiteSpace($ProgressPath)) { return }
    $now = Get-Date
    if (-not $Force -and ($now - $script:LastProgressWrite).TotalMilliseconds -lt 1000) { return }
    $script:LastProgressWrite = $now
    $body = @{
        schemaVersion = '1'
        state         = $State
        phase         = $Phase
        phasesDone    = $PhasesDone
        phaseTotal    = 4
        reposDone     = $script:ScanReposDone
        reposTotal    = $script:ScanReposTotal
        startedAt     = $script:ScanStartedAtUtc
        updatedAt     = $now.ToUniversalTime().ToString('o')
        processId     = $PID
        error         = $(if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { $null } else { $ErrorMessage })
    } | ConvertTo-Json -Compress
    try { Set-Content -LiteralPath $ProgressPath -Value $body -Encoding UTF8 }
    catch {
        # A progress write that fails must not fail the scan it describes.
        try { Write-HostLog ("[WARN] status.refresh.worker progress write failed: {0}" -f $_.Exception.Message) } catch { $null = $_ }
    }
}

function Test-ScanCancelRequested {
    if ([string]::IsNullOrWhiteSpace($CancelPath)) { return $false }
    return (Test-Path -LiteralPath $CancelPath)
}

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

    # Cancellation is checked here at phase boundaries and nowhere deeper:
    # both progress-callback sites (the inventory walk and the bounded git
    # sweep) swallow callback exceptions by design, so a cancel raised inside
    # them would be logged and ignored. The bound this gives an operator: a
    # cancel lands within the current phase's remaining time, and M2 bounded
    # the longest phase's git work.
    function Test-ScanPhaseGate {
        param([Parameter(Mandatory = $true)][int]$PhasesDone, [Parameter(Mandatory = $true)][string]$NextPhase)
        if ($PhaseDelayMs -gt 0) { Start-Sleep -Milliseconds $PhaseDelayMs }
        if (Test-ScanCancelRequested) {
            Write-ScanProgress -State 'cancelled' -Phase $NextPhase -PhasesDone $PhasesDone -Force
            Write-HostLog ("[TRACE] status.refresh.worker cancelled before phase {0} ({1}/4 phases complete)" -f $NextPhase, $PhasesDone)
            return $true
        }
        Write-ScanProgress -State 'running' -Phase $NextPhase -PhasesDone $PhasesDone -Force
        return $false
    }

    $cancelled = $false
    $statusMs = 0; $roadmapMs = 0; $docMs = 0; $auditMs = 0
    $result = $null; $roadmapEntries = @(); $docAuditEntries = @(); $roadmapAuditEntries = @()

    # Phase 1: inventory (status sweep). Per-repo ticks flow through the
    # existing -OnProgress plumbing into the progress file, so updatedAt keeps
    # moving while the walk and the bounded git sweep run.
    $cancelled = Test-ScanPhaseGate -PhasesDone 0 -NextPhase 'inventory'
    if (-not $cancelled) {
        $result = Get-StatusAdapterResult -LocalRoots $LocalRoots -MaxDepth $MaxDepth `
            -IncludeNonGitFolders:$IncludeNonGitFolders -LogPath $LogPath `
            -OnProgress {
                param($itemCount)
                $script:ScanReposDone = [int]$itemCount
                Write-ScanProgress -State 'running' -Phase 'inventory' -PhasesDone 0
            }

        if ($null -eq $result -or -not $result.success) {
            $reason = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'error') { [string]$result.error } else { 'unknown error' }
            throw "Status scan failed: $reason"
        }

        $result = Add-GitHubMetadataToStatusResult -StatusResult $result -Settings $settings
        $result = Add-StatusCacheMeta -Result $result -CacheMeta (Get-StatusCacheMeta -Hit $false -Source 'background-refresh' `
            -TtlSeconds (Get-StatusCacheTtlSeconds -Settings $settings) -AgeSeconds 0 -BypassRequested:$false `
            -CachedAt ((Get-Date).ToUniversalTime().ToString('o')))

        Save-StatusCache -Key $cacheKey -Response $result
        $script:ScanReposTotal = @($result.data.repos).Count
        $script:ScanReposDone = $script:ScanReposTotal
        $statusMs = [int]((Get-Date) - $started).TotalMilliseconds
    }

    # The roadmap and doc-audit scans belong here for the same reason the status
    # scan does: GET /api/portfolio/assessment ran both inline. Its own budget
    # line measured prepMs=40669 on this workspace - and the roadmap branch never
    # called Save-RoadmapCache, so it paid that 40s on EVERY request rather than
    # once per TTL. Scanning here fixes both the freeze and the missing write.
    if (-not $cancelled) {
        $cancelled = Test-ScanPhaseGate -PhasesDone 1 -NextPhase 'roadmap'
    }
    if (-not $cancelled) {
        $roadmapStarted = Get-Date
        $roadmapEntries = @(Invoke-RoadmapScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
        Save-RoadmapCache -Entries $roadmapEntries -ScannedAt ((Get-Date).ToUniversalTime().ToString('o'))
        $roadmapMs = [int]((Get-Date) - $roadmapStarted).TotalMilliseconds
    }

    if (-not $cancelled) {
        $cancelled = Test-ScanPhaseGate -PhasesDone 2 -NextPhase 'doc-audit'
    }
    if (-not $cancelled) {
        $docStarted = Get-Date
        $docAuditEntries = @(Invoke-DocAuditScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
        Save-DocAuditCache -Entries $docAuditEntries -AuditedAt ((Get-Date).ToUniversalTime().ToString('o'))
        $docMs = [int]((Get-Date) - $docStarted).TotalMilliseconds
    }

    if (-not $cancelled) {
        $cancelled = Test-ScanPhaseGate -PhasesDone 3 -NextPhase 'roadmap-audit'
    }
    if (-not $cancelled) {
        $auditStarted = Get-Date
        $roadmapAuditEntries = @(Invoke-RoadmapAuditScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
        Save-RoadmapAuditCache -Entries $roadmapAuditEntries -AuditedAt ((Get-Date).ToUniversalTime().ToString('o'))
        $auditMs = [int]((Get-Date) - $auditStarted).TotalMilliseconds
    }

    if ($cancelled) {
        # A cancel is a deliberate operator action, not a failure. Caches keep
        # whatever completed phases wrote; nothing partial is invented.
        $exitCode = 0
    }
    else {
        Write-ScanProgress -State 'completed' -Phase 'done' -PhasesDone 4 -Force
        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        Write-HostLog ("[TRACE] status.refresh.worker done repos={0} roadmap={1} docAudit={2} roadmapAudit={3} statusMs={4} roadmapMs={5} docAuditMs={6} roadmapAuditMs={7} totalMs={8}" -f `
            @($result.data.repos).Count, @($roadmapEntries).Count, @($docAuditEntries).Count, @($roadmapAuditEntries).Count, `
            $statusMs, $roadmapMs, $docMs, $auditMs, $elapsed)
    }
}
catch {
    # Reported, never swallowed: a refresh that keeps failing must be visible in
    # the host log rather than presenting as a cache that is merely always cold.
    $message = "status.refresh.worker FAILED: $($_.Exception.Message)"
    try { Write-HostLog ("[ERROR] {0}" -f $message) } catch { Write-Error $message }
    Write-ScanProgress -State 'failed' -Phase 'error' -ErrorMessage $_.Exception.Message -Force
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
    # The cancel marker is consumed however this run ended: a marker left
    # behind would silently cancel the NEXT scan at its first phase gate.
    if (-not [string]::IsNullOrWhiteSpace($CancelPath) -and (Test-Path -LiteralPath $CancelPath)) {
        try {
            Remove-Item -LiteralPath $CancelPath -Force -ErrorAction Stop
        }
        catch {
            Write-Warning ("status.refresh.worker could not consume cancel marker '{0}': {1}" -f $CancelPath, $_.Exception.Message)
        }
    }
}

exit $exitCode

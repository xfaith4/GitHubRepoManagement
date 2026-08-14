<#
.SYNOPSIS
    Classify a repository as behind / ahead / current from timestamps the
    portfolio scan already collects.

.DESCRIPTION
    Release 3.1 — the dashboard has shipped a "Stale" column, a stale-only
    quick filter, a group-by-stale control and an ahead/behind badge since
    Release 1.x, all bound to `isStale`, `localAhead` and `remoteAhead`. Every
    one of those three was a hardcoded literal in both GitHub scan paths
    (`$false`, `0`, `0`) and was never computed anywhere. The column read "No"
    for all 80+ repositories, the filter always returned empty, and the badge
    never rendered — not because the data was fresh, but because nothing ever
    looked.

    A 2026-08-14 measurement of the 60 local clones found 11 of the 49 with
    upstreams sitting behind, several last fetched over six months ago. The
    scan had both facts in hand the whole time and threw the comparison away:
    the local side records the last commit date from
    `git log -1 --format=%cI`, and the GitHub side records `pushed_at`, and
    they meet on the same object in Add-GitHubMetadataToStatusResult.

    This function is the comparison, and nothing more. It is deliberately
    PURE — dates in, classification out — so the matrix is unit-testable
    without a network, a clone, or a scan, in the same shape as
    Resolve-RunnerPresence.

    WHAT THIS BASIS CANNOT DO, stated rather than implied: two timestamps
    cannot yield an exact ahead/behind commit count. That needs a real ref
    comparison (`git ls-remote` or a fetch) and costs a network round trip per
    repository. `exactCountsAvailable` is therefore always $false here, and
    callers must render an absent count as absent rather than as zero — the
    same rule this release applies to unmeasured token cost.
#>

Set-StrictMode -Version Latest

# Push latency and clock skew mean the remote push timestamp is normally a few
# seconds later than the local commit it carries. Anything inside this window is
# "current" rather than a divergence, so a freshly-pushed repo does not light up
# the dashboard.
$script:RepoStalenessToleranceSeconds = 300

function ConvertTo-StalenessDateTime {
    <#
    .SYNOPSIS
        Parse an ISO-8601 timestamp to UTC, returning $null rather than throwing.
    .DESCRIPTION
        A repo with no commits, a scan that failed to read one, or a GitHub
        payload without pushed_at must all degrade to "unknown", never to an
        exception in the middle of a portfolio sweep.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param([Parameter()][AllowNull()][AllowEmptyString()][object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    [datetime]$parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
              [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Resolve-RepoStaleness {
    <#
    .SYNOPSIS
        Pure — classify local-vs-remote drift from two timestamps.
    .PARAMETER LocalCommitDate
        The local HEAD commit date (`git log -1 --format=%cI`).
    .PARAMETER RemotePushedAt
        GitHub's `pushed_at` for the same repository. Deliberately not
        `updated_at`: that moves when a description or star count changes, so a
        repo nobody has pushed to for a year can look freshly updated.
    .OUTPUTS
        state:  behind | ahead-or-unpushed | current | unknown
        isStale is true ONLY for 'behind'. An unknown reading is not stale —
        absence of evidence is not evidence of divergence, the same rule
        Resolve-RunnerPresence applies to an unreadable heartbeat.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][AllowEmptyString()][object]$LocalCommitDate,
        [Parameter()][AllowNull()][AllowEmptyString()][object]$RemotePushedAt,
        [Parameter()][int]$ToleranceSeconds = $script:RepoStalenessToleranceSeconds
    )

    if ($ToleranceSeconds -lt 0) { $ToleranceSeconds = 0 }

    $local  = ConvertTo-StalenessDateTime -Value $LocalCommitDate
    $remote = ConvertTo-StalenessDateTime -Value $RemotePushedAt

    $result = [ordered]@{
        state                = 'unknown'
        isStale              = $false
        # Names the engine that produced this, per the release's rule that a
        # surface must never leave the operator guessing what computed a value.
        basis                = 'remote-push-vs-local-commit'
        localCommitDate      = if ($null -ne $local)  { $local.ToString('o') }  else { $null }
        remotePushedAt       = if ($null -ne $remote) { $remote.ToString('o') } else { $null }
        driftSeconds         = $null
        behindByDays         = $null
        toleranceSeconds     = $ToleranceSeconds
        exactCountsAvailable = $false
        summary              = ''
    }

    if ($null -eq $local -or $null -eq $remote) {
        $missing = if ($null -eq $local -and $null -eq $remote) {
            'neither a local commit date nor a remote push time'
        }
        elseif ($null -eq $local) { 'no local commit date' }
        else { 'no remote push time' }
        $result.summary = "Drift unknown: the scan has $missing for this repository."
        return [pscustomobject]$result
    }

    # Positive drift means the remote moved after the local commit — someone
    # else pushed, or you pushed from elsewhere.
    $drift = [int][Math]::Round(($remote - $local).TotalSeconds)
    $result.driftSeconds = $drift

    if ($drift -gt $ToleranceSeconds) {
        $days = [Math]::Round(($drift / 86400.0), 1)
        $result.state        = 'behind'
        $result.isStale      = $true
        $result.behindByDays = $days
        $result.summary      = if ($days -ge 1) {
            "Remote has moved since this clone's last commit — behind by about $days day(s). Pull before writing to it."
        }
        else {
            "Remote has moved since this clone's last commit. Pull before writing to it."
        }
    }
    elseif ($drift -lt (-1 * $ToleranceSeconds)) {
        $result.state   = 'ahead-or-unpushed'
        $result.summary = "This clone has local work newer than the last push to the remote."
    }
    else {
        $result.state   = 'current'
        $result.summary = 'Local and remote last moved at the same time.'
    }

    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Remembers GitHub owners that do not exist, so the portfolio sweep stops
    paying for them on every request.

.DESCRIPTION
    A local remote can name a github.com account that is not there: a renamed
    user, a deleted organisation, or an enterprise host pasted into a
    github.com URL. Every owner-scoped call for such an owner returns 404, and
    the sweep makes several of them per owner per request.

    Measured on 2026-08-11 against the live portal: a single repo whose origin
    named an absent account held the host's one request thread for over three
    minutes with no log output. Because the host serves requests serially, that
    starved every other route - /health/live included, which is what the
    watchdog probes.

    This library is deliberately parameter-less. Dot-sourcing a script that
    declares param() runs it in the CALLER's scope and assigns every parameter
    there, blanking same-named caller variables; that defect cost Release 3.0
    its dispatch route (PR #119). Nothing here takes parameters at load time.

.NOTES
    TTL rather than permanent: an owner that appears later must be picked up
    without restarting the host.
#>

Set-StrictMode -Version Latest

$script:GitHubDeadOwnerCache = [hashtable]::Synchronized(@{})
$script:GitHubDeadOwnerTtlSeconds = 3600

function Write-GitHubOwnerCacheLog {
    <#
    .SYNOPSIS
        Writes through to the host logger when one is present.
    .DESCRIPTION
        This is a capability probe, not error suppression: the library is
        loaded both by the API host (where Write-HostLog exists) and by the
        module smoke test (where it does not). A missing logger must not turn
        a cache hit into a terminating error, and nothing here is a failure
        worth swallowing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $logger = Get-Command -Name 'Write-HostLog' -CommandType Function -ErrorAction Ignore
    if ($null -ne $logger) {
        & $logger $Message
    }
    else {
        Write-Verbose $Message
    }
}

function Test-GitHubErrorIsOwnerAbsent {
    <#
    .SYNOPSIS
        True when an API failure means "this owner does not exist on github.com".
    .DESCRIPTION
        Only a 404 proves absence. A 401/403 means the token cannot see the
        owner, a 422 means the query was malformed, and a timeout means nothing
        at all - none of those may poison the cache, because doing so would
        hide a real owner behind a transient credential or network fault for
        the whole TTL.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $status = 0
    try { $status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { $status = 0 }

    if ($status -ne 0) {
        return ($status -eq 404)
    }

    # Windows PowerShell surfaces the status only in the message text. \b, not
    # (^|\D): a letter next to a digit is not a word boundary, so \b404\b leaves
    # a repo like "build404tools" alone, while (^|\D)404(\D|$) matched it. The
    # module smoke asserts exactly that case.
    return ([string]$ErrorRecord.Exception.Message -match '\b404\b')
}

function Test-GitHubOwnerKnownAbsent {
    <#
    .SYNOPSIS
        True when this owner 404'd recently and the record has not expired.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner
    )

    $key = $Owner.ToLowerInvariant()
    if (-not $script:GitHubDeadOwnerCache.ContainsKey($key)) { return $false }

    if ((Get-Date) -ge $script:GitHubDeadOwnerCache[$key]) {
        $script:GitHubDeadOwnerCache.Remove($key)
        return $false
    }

    return $true
}

function Set-GitHubOwnerKnownAbsent {
    <#
    .SYNOPSIS
        Records that an owner returned 404, and says so once at WARN.
    .DESCRIPTION
        Logged at WARN rather than TRACE because it is a portfolio finding, not
        host noise: a repo whose remote names an account that does not exist
        will never sync, and the operator should fix the remote or drop the
        repo. Repeat hits inside the TTL stay silent so one bad remote cannot
        flood the log.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Writes one entry to an in-process, TTL-bounded memo of 404 responses. Nothing is persisted and nothing outside the host observes it, so -WhatIf plumbing on a per-request path would give an operator nothing to confirm.')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner
    )

    $key = $Owner.ToLowerInvariant()
    if (-not $script:GitHubDeadOwnerCache.ContainsKey($key)) {
        Write-GitHubOwnerCacheLog ("[WARN] github.owner absent owner={0} - skipping owner-scoped API calls for {1}s. A local remote names a github.com account that does not exist; fix the remote or remove the repo from the portfolio." -f $Owner, $script:GitHubDeadOwnerTtlSeconds)
    }

    $script:GitHubDeadOwnerCache[$key] = (Get-Date).AddSeconds($script:GitHubDeadOwnerTtlSeconds)
}

function Clear-GitHubOwnerCache {
    <#
    .SYNOPSIS
        Forgets every recorded absent owner. Used by tests and cache clears.
    #>
    $script:GitHubDeadOwnerCache.Clear()
}

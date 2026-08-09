Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    GitHub rate-limit observation (ROADMAP Lane 0.2).

    Every GitHub REST response already carries X-RateLimit-Limit / -Remaining /
    -Reset. The insights payload used to discard them and hardcode
    `rateLimit = $null`, so the GitHub view's rate-limit readout was permanently
    blank even though the data arrived on every call.

    These helpers live in their own dot-sourced file — the same shape
    RequestDeadline.ps1 uses — because functions defined inside
    Start-RepoManagementApiHost.ps1 cannot be loaded without starting the
    listener, and a parser that is only reachable through a live HTTP request is
    a parser nothing tests.
#>

function Get-HttpHeaderValue {
    <#
    .SYNOPSIS
        Case-insensitive single-value read from a response header collection.
    .DESCRIPTION
        Pure. Windows PowerShell hands back Dictionary[string,string] and
        PowerShell 7 hands back Dictionary[string,string[]], so a caller that
        assumes either shape works on one edition and silently reads nothing on
        the other. Both are handled here rather than at each call site.
    .PARAMETER Headers
        Any dictionary-like header collection, or $null.
    .PARAMETER Name
        Header name, matched case-insensitively.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()][object]$Headers,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Headers) { return '' }

    $raw = $null
    try {
        foreach ($key in @($Headers.Keys)) {
            if ($null -ne $key -and ([string]$key).Equals($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $raw = $Headers[$key]
                break
            }
        }
    }
    catch { return '' }

    if ($null -eq $raw) { return '' }
    if ($raw -is [string]) { return $raw }
    if ($raw -is [System.Collections.IEnumerable]) {
        foreach ($item in $raw) { if ($null -ne $item) { return [string]$item } }
        return ''
    }
    return [string]$raw
}

function ConvertFrom-GitHubRateLimitHeader {
    <#
    .SYNOPSIS
        Parse X-RateLimit-* into the shape the dashboard renders, or $null.
    .DESCRIPTION
        Pure, so the module smoke can assert both editions' header shapes
        without a network call.

        Returns $null rather than a zeroed object when the headers are absent or
        unparseable. A fabricated "0/0" readout would be worse than the blank
        one this replaces: it would read as "no requests left" and look like a
        real measurement.
    #>
    [CmdletBinding()]
    param([Parameter()][object]$Headers)

    $limitText     = Get-HttpHeaderValue -Headers $Headers -Name 'X-RateLimit-Limit'
    $remainingText = Get-HttpHeaderValue -Headers $Headers -Name 'X-RateLimit-Remaining'
    $resetText     = Get-HttpHeaderValue -Headers $Headers -Name 'X-RateLimit-Reset'

    $limit = 0
    $remaining = 0
    $reset = 0
    if (-not [int]::TryParse($limitText, [ref]$limit)) { return $null }
    if (-not [int]::TryParse($remainingText, [ref]$remaining)) { return $null }
    $null = [int]::TryParse($resetText, [ref]$reset)

    $resetAt = $null
    if ($reset -gt 0) {
        try { $resetAt = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$reset).UtcDateTime.ToString('o') }
        catch { $resetAt = $null }
    }

    # X-RateLimit-Used is not sent by every endpoint; derive it when absent so
    # the field is always populated rather than sometimes missing.
    $usedText = Get-HttpHeaderValue -Headers $Headers -Name 'X-RateLimit-Used'
    $used = 0
    if (-not [int]::TryParse($usedText, [ref]$used)) { $used = [math]::Max(0, $limit - $remaining) }

    return [pscustomobject]@{
        limit     = $limit
        remaining = $remaining
        reset     = $reset
        used      = $used
        resetAt   = $resetAt
        resource  = (Get-HttpHeaderValue -Headers $Headers -Name 'X-RateLimit-Resource')
    }
}

function ConvertFrom-GitHubRateLimitPayload {
    <#
    .SYNOPSIS
        Parse a GET /rate_limit response body into the same shape, or $null.
    .DESCRIPTION
        The `gh` CLI fallback path has no response object to read headers from —
        `gh repo list` returns only the JSON it was asked for. GitHub's
        /rate_limit endpoint answers the same question, and querying it does not
        itself consume quota, so the CLI path reports a real figure instead of a
        second permanently-blank readout.

        Pure: takes already-parsed JSON (or a JSON string) so the module smoke
        can cover it without invoking `gh`.
    .PARAMETER Payload
        The parsed object or raw JSON text from GET /rate_limit.
    .PARAMETER Resource
        Which bucket to report. 'core' is the one repo listing consumes.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][object]$Payload,
        [Parameter()][string]$Resource = 'core'
    )

    if ($null -eq $Payload) { return $null }

    $obj = $Payload
    if ($Payload -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Payload)) { return $null }
        try { $obj = ConvertFrom-Json -InputObject $Payload } catch { return $null }
    }

    $resources = $null
    if ($obj -is [System.Collections.IDictionary]) {
        if ($obj.Contains('resources')) { $resources = $obj['resources'] }
    }
    elseif ($null -ne $obj.PSObject -and ($obj.PSObject.Properties.Name -contains 'resources')) {
        $resources = $obj.resources
    }
    if ($null -eq $resources) { return $null }

    $bucket = $null
    if ($resources -is [System.Collections.IDictionary]) {
        if ($resources.Contains($Resource)) { $bucket = $resources[$Resource] }
    }
    elseif ($null -ne $resources.PSObject -and ($resources.PSObject.Properties.Name -contains $Resource)) {
        $bucket = $resources.$Resource
    }
    if ($null -eq $bucket) { return $null }

    # Reuse the header parser so the two paths cannot produce different shapes.
    $headerLike = @{}
    foreach ($pair in @(
            @{ Field = 'limit';     Header = 'X-RateLimit-Limit' },
            @{ Field = 'remaining'; Header = 'X-RateLimit-Remaining' },
            @{ Field = 'reset';     Header = 'X-RateLimit-Reset' },
            @{ Field = 'used';      Header = 'X-RateLimit-Used' })) {
        $value = $null
        if ($bucket -is [System.Collections.IDictionary]) {
            if ($bucket.Contains($pair.Field)) { $value = $bucket[$pair.Field] }
        }
        elseif ($null -ne $bucket.PSObject -and ($bucket.PSObject.Properties.Name -contains $pair.Field)) {
            $value = $bucket.($pair.Field)
        }
        if ($null -ne $value) { $headerLike[$pair.Header] = [string]$value }
    }
    $headerLike['X-RateLimit-Resource'] = $Resource

    return (ConvertFrom-GitHubRateLimitHeader -Headers $headerLike)
}

function Clear-GitHubRateLimitSnapshot {
    <#
    .SYNOPSIS
        Drop the observed snapshot at the start of an insights request.
    .DESCRIPTION
        Without this the readout could describe calls made hours ago in an
        unrelated request and still look current.
    #>
    [CmdletBinding()]
    param()
    $script:GitHubRateLimitSnapshot = $null
}

function Update-GitHubRateLimitSnapshot {
    <#
    .SYNOPSIS
        Record the rate limit from one response, if it reported one.
    .DESCRIPTION
        Last writer wins on purpose: the newest response carries the smallest
        remaining count, which is the only figure that is still true by the time
        the payload is built.
    #>
    [CmdletBinding()]
    param([Parameter()][object]$Headers)

    $parsed = ConvertFrom-GitHubRateLimitHeader -Headers $Headers
    if ($null -ne $parsed) { $script:GitHubRateLimitSnapshot = $parsed }
    return $parsed
}

function Get-GitHubRateLimitSnapshot {
    <#
    .SYNOPSIS
        The most recently observed rate limit, or $null if none was seen.
    #>
    [CmdletBinding()]
    param()
    if (Test-Path -LiteralPath 'variable:script:GitHubRateLimitSnapshot') { return $script:GitHubRateLimitSnapshot }
    return $null
}

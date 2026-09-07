<#
.SYNOPSIS
    Release 3.8 M2 — what is left with a provider, in that provider's own unit.

.DESCRIPTION
    The execution governance spec is blunt about this: capacity MUST NOT be
    represented by one universal `tokensRemaining` value. Each provider has its
    own native windows, and the Governor "MUST preserve the provider's native
    unit" rather than invent a token conversion for a subscription allowance the
    provider never exposed as tokens. This module is that normalized record.

    Nothing like it existed. The only budget object in the codebase,
    `Test-AgentDispatchQuota` in `BudgetLedger.ps1`, is a work-unit figure per
    repository per month -- a portfolio spending limit, not a provider
    allowance. The two measure different things and neither substitutes for the
    other, so this record sits beside it rather than replacing it.

    **A missing ratio is an answer.** A window whose `remainingRatio` is `$null`
    is valid and reports `confidence = 'none'`. That is deliberate: for a
    subscription whose allowance is not published, "unknown" is the truth, and
    an invented number would be indistinguishable from a measured one at exactly
    the moment the Governor is deciding whether to spend it. Every function here
    is built so that the honest answer never costs more than the guess.

    **Confidence comes from where the observation came from, not from how
    recent it is.** The spec ranks six sources; `Get-CapacitySourceRank` is that
    ladder, and `Merge-ProviderCapacityWindow` refuses to let a worse source
    overwrite a better one. Without that rule a historical estimate written a
    second ago would displace a provider's own machine-readable status, and the
    record would get less trustworthy the more often it was updated.

    This packet is the contract and its persistence only. H38-09 adds the
    reserve arithmetic and the verdict; H38-11 derives `activeExecutions` from
    live runner evidence, which is why this module always writes it as 0.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The spec's confidence ladder, HIGHEST confidence first. The index is the
# rank, so "better" is numerically lower and comparisons read the way the spec
# is written.
$script:CapacitySourceRank = @(
    'provider-status',      # 1. provider-supported machine-readable status
    'provider-cli',         # 2. provider CLI / account status
    'provider-warning',     # 3. provider-reported warning or remaining percentage
    'accumulated-usage',    # 4. usage accumulated from completed executions
    'rate-limit-response',  # 5. observed rate-limit response and reset time
    'historical-estimate'   # 6. historical estimate
)

# Deliberately a second copy of H38-07's list rather than a reference to it.
# Reaching into another module's $script: scope would make load order
# load-bearing; the module smoke asserts the two lists are identical instead, so
# drift fails a gate rather than surfacing as a wrong validation months later.
$script:ProviderCapacityUnit = @('provider-allowance', 'tokens', 'ai-credits', 'premium-requests', 'currency', 'unknown')

function _PCR_Field {
    <# Read a field from a hashtable or a PSCustomObject. Same shape as
       _APR_Field in Execution.ProviderRegistry.ps1. #>
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function _PCR_HasKey {
    <# Whether a field is PRESENT, regardless of whether its value is null.
       _PCR_Field cannot answer this: it folds "absent" and "null" together,
       which is right for reading a value and wrong for deciding whether an
       operator supplied one. A window that explicitly carries
       "remainingRatio": null is making a claim -- I do not know -- and must not
       be treated as though the key were missing. #>
    param([object]$Obj, [string]$Name)
    if ($null -eq $Obj) { return $false }
    if ($Obj -is [System.Collections.IDictionary]) { return $Obj.Contains($Name) }
    if ($null -ne $Obj.PSObject) { return (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name) }
    return $false
}

function _PCR_TryRatio {
    <# Parse a ratio. Returns $null for absent-or-unparseable, so callers can
       tell "no ratio" from a real 0.0 -- and 0.0 is a legitimate, important
       value meaning the window is exhausted. #>
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parsed = 0.0
    if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $null }
    return $parsed
}

<#
.SYNOPSIS
    The spec's 1-based confidence rank for a capacity source.

.DESCRIPTION
    Throws on an unknown source rather than returning a worst-case rank. A typo
    in a source name would otherwise be silently demoted to "historical
    estimate" and quietly lose a merge against a genuinely worse observation.
#>
function Get-CapacitySourceRank {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Source)

    $index = [array]::IndexOf($script:CapacitySourceRank, $Source)
    if ($index -lt 0) {
        throw ("Unknown capacity source '{0}'. Allowed: {1}" -f $Source, ($script:CapacitySourceRank -join ', '))
    }
    return ($index + 1)
}

<#
.SYNOPSIS
    Confidence for one window: high (rank 1-2), medium (3-4), low (5-6), or
    none when there is no ratio at all.
#>
function Get-CapacityWindowConfidence {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Source,
        [object]$RemainingRatio = $null
    )

    # No ratio means nothing was measured, so the source it did not come from is
    # irrelevant. Checked BEFORE the rank lookup so an unmeasured window from an
    # unknown source still reports honestly instead of throwing.
    if ($null -eq $RemainingRatio) { return 'none' }

    $rank = Get-CapacitySourceRank -Source $Source
    if ($rank -le 2) { return 'high' }
    if ($rank -le 4) { return 'medium' }
    return 'low'
}

<#
.SYNOPSIS
    Build the spec's normalized capacity record for one provider.

.DESCRIPTION
    `activeExecutions` is always 0 here. Live execution counts come from runner
    evidence -- a heartbeat and a pid -- which this module cannot see and a file
    on disk cannot be trusted to remember: a runner that dies mid-run would
    leave a stale count behind forever. H38-11 derives it on read.
#>
function New-ProviderCapacityRecord {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns a record in memory and touches nothing. Save-ProviderCapacityRecord is the only writer, and the New- verb is fixed by the M2 task contract.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Provider,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Windows,
        [bool]$Available = $true,
        [AllowEmptyString()][string]$ObservedAt = '',
        [AllowEmptyString()][string]$CooldownUntil = ''
    )

    $observed = $ObservedAt
    if ([string]::IsNullOrWhiteSpace($observed)) {
        # UTC with an explicit Z: every timestamp in this repository carries its
        # own timezone basis, so a reader never has to guess whose clock it is.
        $observed = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    # Normalized inline rather than through a helper. Returning a collection
    # from a PowerShell function ENUMERATES it, so an empty windows array would
    # come back as $null and a caller would get a broken record instead of an
    # invalid one it could report on.
    $normalized = @()
    foreach ($window in @($Windows)) {
        $source = [string](_PCR_Field -Obj $window -Name 'source' -Default '')

        # Present-but-null is a real claim ("I do not know"), so presence is
        # what decides whether a ratio was offered -- not truthiness.
        $ratio = $null
        if (_PCR_HasKey -Obj $window -Name 'remainingRatio') {
            $ratio = _PCR_TryRatio (_PCR_Field -Obj $window -Name 'remainingRatio' -Default $null)
        }

        $resetAt = [string](_PCR_Field -Obj $window -Name 'resetAt' -Default '')

        $entry = [ordered]@{
            name           = [string](_PCR_Field -Obj $window -Name 'name' -Default '')
            unit           = [string](_PCR_Field -Obj $window -Name 'unit' -Default '')
            remainingRatio = $ratio
            resetAt        = $(if ([string]::IsNullOrWhiteSpace($resetAt)) { $null } else { $resetAt })
            source         = $source
            confidence     = (Get-CapacityWindowConfidence -Source $source -RemainingRatio $ratio)
        }
        $normalized += , $entry
    }

    return [ordered]@{
        provider         = $Provider
        available        = [bool]$Available
        observedAt       = $observed
        activeExecutions = 0
        windows          = @($normalized)
        cooldownUntil    = $(if ([string]::IsNullOrWhiteSpace($CooldownUntil)) { $null } else { $CooldownUntil })
    }
}

<#
.SYNOPSIS
    Validate a capacity record. Every error at once, each naming the exact key.
#>
function Test-ProviderCapacityRecord {
    param([Parameter(Mandatory)][object]$Record)

    $errors = @()

    if ([string]::IsNullOrWhiteSpace([string](_PCR_Field -Obj $Record -Name 'provider' -Default ''))) {
        $errors += 'provider is required'
    }

    # Read inline for the same reason New- builds inline: a function returning
    # an empty array hands back $null, which would be reported as the wrong
    # error entirely.
    $windows = @()
    if ($Record -is [System.Collections.IDictionary]) {
        if ($Record.Contains('windows')) { $windows = @($Record['windows']) }
    }
    elseif ($null -ne $Record -and $null -ne $Record.PSObject -and ($Record.PSObject.Properties.Name -contains 'windows')) {
        $windows = @($Record.windows)
    }

    if ($windows.Count -eq 0) {
        $errors += 'windows must be a non-empty array'
    }
    else {
        for ($i = 0; $i -lt $windows.Count; $i++) {
            $window = $windows[$i]

            $unit = [string](_PCR_Field -Obj $window -Name 'unit' -Default '')
            if ($unit -notin $script:ProviderCapacityUnit) {
                $errors += ('windows[{0}].unit must be one of: {1}' -f $i, ($script:ProviderCapacityUnit -join ', '))
            }

            # A null ratio is VALID -- it is how the record says "not measured".
            # Only a present, non-null value that is not a number in 0..1 fails.
            $rawRatio = _PCR_Field -Obj $window -Name 'remainingRatio' -Default $null
            if ($null -ne $rawRatio) {
                $ratio = _PCR_TryRatio $rawRatio
                if ($null -eq $ratio -or $ratio -lt 0.0 -or $ratio -gt 1.0) {
                    $errors += ('windows[{0}].remainingRatio must be null or between 0 and 1' -f $i)
                }
            }

            $source = [string](_PCR_Field -Obj $window -Name 'source' -Default '')
            if ($source -notin $script:CapacitySourceRank) {
                $errors += ('windows[{0}].source must be one of: {1}' -f $i, ($script:CapacitySourceRank -join ', '))
            }
        }
    }

    return [pscustomobject]@{
        valid  = ($errors.Count -eq 0)
        errors = @($errors)
    }
}

<#
.SYNOPSIS
    The one place a provider's capacity file path is decided.
#>
function Get-ProviderCapacityRecordPath {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Provider
    )
    return (Join-Path $WorkspaceRoot ('output\provider-capacity\{0}.json' -f $Provider))
}

<#
.SYNOPSIS
    Validate and persist one provider's capacity record. Returns the path.
#>
function Save-ProviderCapacityRecord {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][object]$Record
    )

    $validation = Test-ProviderCapacityRecord -Record $Record
    if (-not $validation.valid) {
        throw ('Provider capacity record is invalid: {0}' -f ($validation.errors -join '; '))
    }

    $provider = [string](_PCR_Field -Obj $Record -Name 'provider' -Default '')
    $path = Get-ProviderCapacityRecordPath -WorkspaceRoot $WorkspaceRoot -Provider $provider
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    Set-Content -LiteralPath $path -Value ($Record | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $path
}

<#
.SYNOPSIS
    Read one provider's capacity record; $null when absent or unparseable.

.DESCRIPTION
    Absent and corrupt answer the same way on purpose, so a caller has one case
    to handle. A missing capacity record is the ordinary state on a fresh
    install, not an error.
#>
function Read-ProviderCapacityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Provider
    )

    $path = Get-ProviderCapacityRecordPath -WorkspaceRoot $WorkspaceRoot -Provider $Provider
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    }
    catch {
        return $null
    }
    return $parsed
}

<#
.SYNOPSIS
    Merge one observed window into a record, refusing a lower-confidence source.

.DESCRIPTION
    The rule that makes an accumulating record trustworthy: a window is replaced
    only when the incoming observation comes from a source at least as good as
    the stored one. A historical estimate must never overwrite the provider's
    own status just because it arrived later.

    Returns `merged`, a `reason` when it refused, and the resulting `record`.
    The record is rebuilt rather than mutated in place, because mutating an
    array property of a JSON-round-tripped object behaves differently depending
    on whether it came from `ConvertFrom-Json` or from `New-`.
#>
function Merge-ProviderCapacityWindow {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][object]$Window
    )

    $incomingName = [string](_PCR_Field -Obj $Window -Name 'name' -Default '')
    $incomingSource = [string](_PCR_Field -Obj $Window -Name 'source' -Default '')
    $incomingRank = Get-CapacitySourceRank -Source $incomingSource

    $existing = @()
    if ($Record -is [System.Collections.IDictionary]) {
        if ($Record.Contains('windows')) { $existing = @($Record['windows']) }
    }
    elseif ($null -ne $Record -and $null -ne $Record.PSObject -and ($Record.PSObject.Properties.Name -contains 'windows')) {
        $existing = @($Record.windows)
    }

    $incomingRatio = $null
    if (_PCR_HasKey -Obj $Window -Name 'remainingRatio') {
        $incomingRatio = _PCR_TryRatio (_PCR_Field -Obj $Window -Name 'remainingRatio' -Default $null)
    }
    $incomingResetAt = [string](_PCR_Field -Obj $Window -Name 'resetAt' -Default '')

    $normalizedIncoming = [ordered]@{
        name           = $incomingName
        unit           = [string](_PCR_Field -Obj $Window -Name 'unit' -Default '')
        remainingRatio = $incomingRatio
        resetAt        = $(if ([string]::IsNullOrWhiteSpace($incomingResetAt)) { $null } else { $incomingResetAt })
        source         = $incomingSource
        confidence     = (Get-CapacityWindowConfidence -Source $incomingSource -RemainingRatio $incomingRatio)
    }

    $merged = $false
    $reason = ''
    $result = @()
    $matchedName = $false

    foreach ($window in $existing) {
        if ([string](_PCR_Field -Obj $window -Name 'name' -Default '') -ne $incomingName) {
            $result += , $window
            continue
        }

        $matchedName = $true
        $storedRank = Get-CapacitySourceRank -Source ([string](_PCR_Field -Obj $window -Name 'source' -Default ''))
        if ($incomingRank -le $storedRank) {
            $result += , $normalizedIncoming
            $merged = $true
        }
        else {
            $result += , $window
            $reason = 'lower-confidence source'
        }
    }

    # A window the record has never seen is an addition, not a contest -- there
    # is nothing better to protect.
    if (-not $matchedName) {
        $result += , $normalizedIncoming
        $merged = $true
    }

    $rebuilt = [ordered]@{
        provider         = [string](_PCR_Field -Obj $Record -Name 'provider' -Default '')
        available        = [bool](_PCR_Field -Obj $Record -Name 'available' -Default $true)
        observedAt       = [string](_PCR_Field -Obj $Record -Name 'observedAt' -Default '')
        activeExecutions = 0
        windows          = @($result)
        cooldownUntil    = (_PCR_Field -Obj $Record -Name 'cooldownUntil' -Default $null)
    }

    return [pscustomobject]@{
        merged = $merged
        reason = $reason
        record = $rebuilt
    }
}

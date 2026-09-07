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

function _PCR_Stamp {
    <# Normalize a timestamp to an ISO-8601 UTC string.

       This exists because PowerShell 7's ConvertFrom-Json silently converts an
       ISO-8601 STRING into a [datetime] object. A record built in memory
       therefore has a different shape from the same record read back off disk,
       and `[string]$value` on the datetime renders in the CURRENT CULTURE --
       so an operator-facing reason would read "cooling-down until 10.09.2026
       14:00:00" on one machine and the ISO stamp on another, and a gate
       asserting the sentence would pass only where it was written. #>
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
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

        $resetAt = _PCR_Stamp (_PCR_Field -Obj $window -Name 'resetAt' -Default '')

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
    if ($null -eq $parsed) { return $null }

    # Timestamps come back from ConvertFrom-Json as [datetime], not as the
    # strings that were written (see _PCR_Stamp). Normalizing here -- the one
    # place records enter from disk -- means every consumer sees the same shape
    # whether the record was just built or just read, instead of each one
    # having to remember which it was handed.
    $windows = @()
    if ($null -ne $parsed.PSObject -and ($parsed.PSObject.Properties.Name -contains 'windows')) {
        foreach ($window in @($parsed.windows)) {
            $rebuiltWindow = [ordered]@{}
            foreach ($property in @($window.PSObject.Properties | ForEach-Object { $_.Name })) {
                $rebuiltWindow[$property] = $(if ($property -eq 'resetAt') { $(if ($null -eq $window.$property) { $null } else { _PCR_Stamp $window.$property }) } else { $window.$property })
            }
            $windows += , ([pscustomobject]$rebuiltWindow)
        }
    }

    $rebuilt = [ordered]@{}
    foreach ($property in @($parsed.PSObject.Properties | ForEach-Object { $_.Name })) {
        if ($property -eq 'windows') { $rebuilt[$property] = @($windows); continue }
        if ($property -in @('observedAt', 'cooldownUntil')) {
            $rebuilt[$property] = $(if ($null -eq $parsed.$property) { $null } else { _PCR_Stamp $parsed.$property })
            continue
        }
        $rebuilt[$property] = $parsed.$property
    }
    return [pscustomobject]$rebuilt
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
    $incomingResetAt = _PCR_Stamp (_PCR_Field -Obj $Window -Name 'resetAt' -Default '')

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
        observedAt       = _PCR_Stamp (_PCR_Field -Obj $Record -Name 'observedAt' -Default '')
        activeExecutions = 0
        windows          = @($result)
        cooldownUntil    = $(if ($null -eq (_PCR_Field -Obj $Record -Name 'cooldownUntil' -Default $null)) { $null } else { _PCR_Stamp (_PCR_Field -Obj $Record -Name 'cooldownUntil' -Default $null) })
    }

    return [pscustomobject]@{
        merged = $merged
        reason = $reason
        record = $rebuilt
    }
}

<#
.SYNOPSIS
    Did this text come from a provider refusing on capacity rather than failing?

.DESCRIPTION
    The spec's rule that this exists to serve: a provider limit response is
    STATE, not an execution failure. Telling the two apart from a CLI's error
    text is guesswork, so the patterns are data -- `providers.<name>.limitSignals`
    in agent-providers.json -- and can be corrected without a code change when a
    provider rewords its message (A7).

    The reset time is extracted from the same text when it is there, and is
    `$null` when it is not. A17 decides what happens then; this function does not
    invent one, because a guessed reset time would be indistinguishable from a
    provider's own.
#>
function Test-ProviderLimitSignal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Provider,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][object]$Config
    )

    $verdict = [ordered]@{
        matched = $false
        pattern = $null
        resetAt = $null
    }
    if ([string]::IsNullOrWhiteSpace($Text)) { return [pscustomobject]$verdict }

    $providers = _PCR_Field -Obj $Config -Name 'providers' -Default $null
    $entry = _PCR_Field -Obj $providers -Name $Provider -Default $null

    # Read inline: a helper returning an empty patterns array would hand back
    # $null and this would look like a provider with no signals configured.
    $patterns = @()
    if ($entry -is [System.Collections.IDictionary]) {
        if ($entry.Contains('limitSignals')) { $patterns = @($entry['limitSignals']) }
    }
    elseif ($null -ne $entry -and $null -ne $entry.PSObject -and ($entry.PSObject.Properties.Name -contains 'limitSignals')) {
        $patterns = @($entry.limitSignals)
    }

    foreach ($pattern in $patterns) {
        $patternText = [string]$pattern
        if ([string]::IsNullOrWhiteSpace($patternText)) { continue }
        # A malformed regex in config must not take the runner down with it: an
        # unusable pattern is a config defect, not a reason to fail a task that
        # may simply have succeeded.
        try { $isMatch = [regex]::IsMatch($Text, $patternText) }
        catch { continue }
        if ($isMatch) {
            $verdict.matched = $true
            $verdict.pattern = $patternText
            break
        }
    }

    if ($verdict.matched) {
        $stamp = [regex]::Match($Text, '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?Z')
        if ($stamp.Success) { $verdict.resetAt = $stamp.Value }
    }

    return [pscustomobject]$verdict
}

<#
.SYNOPSIS
    Record that a provider is cooling down until a given time.

.DESCRIPTION
    Creates a minimal record when the provider has none, because the first thing
    ever learned about a provider is often that it just refused. That record
    carries no windows: a limit response says "not now", not how much is left,
    and inventing a 0.0 ratio from it would claim a measurement nobody made.

    `resetAssumed` marks a cooldown whose end time WE picked because the
    provider did not say (A17). It is a separate field rather than a silent
    default so the board can show an assumed wait differently from a promised
    one, and so a later real reset time can overwrite it without ambiguity.
#>
function Set-ProviderCooldown {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Until,
        [string]$Source = 'rate-limit-response',
        [switch]$ResetAssumed
    )

    if (-not $PSCmdlet.ShouldProcess($Provider, 'set provider cooldown')) { return '' }

    $record = Read-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Provider $Provider
    if ($null -eq $record) {
        # `available` stays TRUE. A rate limit does not make a provider
        # unavailable, it makes it unavailable UNTIL a time -- which is exactly
        # what cooldownUntil expresses, and it expires on its own. Writing
        # available = false here would leave the provider ineligible forever
        # after its window reopened, because nothing ever sets it back, and the
        # verdict would report 'provider-unavailable' instead of naming the wait
        # and when it ends.
        $record = New-ProviderCapacityRecord -Provider $Provider -Windows @(
            @{ name = 'short-term'; unit = 'unknown'; source = $Source }
        ) -Available $true
    }

    $windows = @()
    if ($record -is [System.Collections.IDictionary]) {
        if ($record.Contains('windows')) { $windows = @($record['windows']) }
    }
    elseif ($null -ne $record.PSObject -and ($record.PSObject.Properties.Name -contains 'windows')) {
        $windows = @($record.windows)
    }

    $rebuilt = [ordered]@{
        provider         = $Provider
        available        = [bool](_PCR_Field -Obj $record -Name 'available' -Default $true)
        observedAt       = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        activeExecutions = 0
        windows          = @($windows)
        cooldownUntil    = $(if ([string]::IsNullOrWhiteSpace($Until)) { $null } else { $Until })
        cooldownSource   = $Source
        resetAssumed     = [bool]$ResetAssumed
    }

    return (Save-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Record $rebuilt)
}

function _PCR_ReadSummary {
    <# Parse one run summary; $null when absent or unparseable. A corrupt
       summary must not take a poll loop down with it. #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)) }
    catch { return $null }
}

function _PCR_SummaryProvider {
    <# Which provider a run summary belongs to. selectedProvider is written by
       the router (H38-17), dispatchTarget by the queue; an entry from before
       either is claude, which is what the runner did unconditionally. #>
    param([object]$Summary)
    $selected = [string](_PCR_Field -Obj $Summary -Name 'selectedProvider' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($selected)) { return $selected }
    $dispatch = [string](_PCR_Field -Obj $Summary -Name 'dispatchTarget' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($dispatch) -and $dispatch -ne 'operator-runner') { return $dispatch }
    return 'claude'
}

<#
.SYNOPSIS
    How many executions this provider has actually running right now.

.DESCRIPTION
    Derived on every read, never stored (A6). A stored count is a number that
    can only be wrong: a runner killed mid-task never decrements it, and the
    slot stays occupied by a run that ended hours ago.

    But derived from summaries ALONE it is just as wrong in the other direction
    -- a crashed runner leaves `status = running` on disk forever, which would
    refuse every future claim. So a run counts only while it is LIVE (A19): the
    heartbeat file exists, its beat is recent, and its pid matches the pid the
    summary recorded. One runner means one pid, and the heartbeat is the
    liveness evidence the portal already trusts.

    A summary with no `runnerPid` was written before H38-11 and is never live.
    That is deliberate: an old running summary is exactly the stuck slot this
    rule exists to release.
#>
function Get-ProviderActiveExecutionCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$RunsDir,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][AllowEmptyString()][string]$HeartbeatPath,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [int]$StaleAfterMinutes = 10
    )

    if (-not (Test-Path -LiteralPath $RunsDir)) { return 0 }

    # Resolve liveness once: if no runner is alive, nothing is running, and
    # every summary on disk is a leftover.
    $livePid = $null
    $heartbeat = $null
    if (-not [string]::IsNullOrWhiteSpace($HeartbeatPath)) { $heartbeat = _PCR_ReadSummary -Path $HeartbeatPath }
    if ($null -ne $heartbeat) {
        $beatRaw = _PCR_Stamp (_PCR_Field -Obj $heartbeat -Name 'lastHeartbeatAt' -Default '')
        $beatAt = [datetime]::MinValue
        $beatParsed = [datetime]::TryParse(
            $beatRaw,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$beatAt)
        if ($beatParsed -and ($NowUtc - $beatAt).TotalMinutes -le $StaleAfterMinutes -and $beatAt -le $NowUtc.AddMinutes($StaleAfterMinutes)) {
            $livePid = _PCR_Field -Obj $heartbeat -Name 'pid' -Default $null
        }
    }
    if ($null -eq $livePid) { return 0 }

    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $RunsDir -Filter '*.summary.json' -File -ErrorAction SilentlyContinue)) {
        $summary = _PCR_ReadSummary -Path $file.FullName
        if ($null -eq $summary) { continue }
        if ([string](_PCR_Field -Obj $summary -Name 'status' -Default '') -ne 'running') { continue }
        if ((_PCR_SummaryProvider -Summary $summary) -ne $Provider) { continue }
        $summaryPid = _PCR_Field -Obj $summary -Name 'runnerPid' -Default $null
        if ($null -eq $summaryPid) { continue }
        if ([string]$summaryPid -ne [string]$livePid) { continue }
        $count++
    }
    return $count
}

<#
.SYNOPSIS
    Mark local runs abandoned by a dead runner as failed, once at startup.

.DESCRIPTION
    The other half of A19. Liveness stops an orphan from HOLDING a slot, but the
    summary still says `running` forever, so the board shows a run that will
    never finish and nobody can tell it apart from one in progress. This names
    it: failed, category `orphaned`, with the pid that abandoned it.

    Only local providers. A github-hosted run continues on GitHub's machines
    whether or not this runner lives, so declaring it orphaned would be a lie
    about work that is still happening.

    branch, attempt, providerSessionId and workPacketPath are left untouched --
    the run failed, but everything needed to retry or resume it is still true.
#>
function Repair-OrphanedRunSummary {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$RunsDir,
        [Parameter(Mandatory)][int]$CurrentPid,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [Parameter(Mandatory)][object]$Config
    )

    $repaired = @()
    if (-not (Test-Path -LiteralPath $RunsDir)) { return $repaired }

    $providers = _PCR_Field -Obj $Config -Name 'providers' -Default $null
    $stamp = $NowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

    foreach ($file in @(Get-ChildItem -LiteralPath $RunsDir -Filter '*.summary.json' -File -ErrorAction SilentlyContinue)) {
        $summary = _PCR_ReadSummary -Path $file.FullName
        if ($null -eq $summary) { continue }
        if ([string](_PCR_Field -Obj $summary -Name 'status' -Default '') -ne 'running') { continue }

        $provider = _PCR_SummaryProvider -Summary $summary
        $mode = [string](_PCR_Field -Obj (_PCR_Field -Obj $providers -Name $provider -Default $null) -Name 'executionMode' -Default '')
        if ($mode -ne 'local') { continue }

        $summaryPid = _PCR_Field -Obj $summary -Name 'runnerPid' -Default $null
        if ($null -ne $summaryPid -and [string]$summaryPid -eq [string]$CurrentPid) { continue }

        $runId = [string](_PCR_Field -Obj $summary -Name 'runId' -Default ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '\.summary$', ''))
        if (-not $PSCmdlet.ShouldProcess($runId, 'mark orphaned run failed')) { continue }

        $rebuilt = [ordered]@{}
        foreach ($property in @($summary.PSObject.Properties | ForEach-Object { $_.Name })) {
            $rebuilt[$property] = $summary.$property
        }
        $rebuilt['status'] = 'failed'
        $rebuilt['failureCategory'] = 'orphaned'
        $rebuilt['error'] = ('runner pid {0} is not this runner ({1}); run abandoned at {2}' -f $(if ($null -eq $summaryPid) { 'none' } else { [string]$summaryPid }), $CurrentPid, $stamp)
        $rebuilt['orphanedAt'] = $stamp

        Set-Content -LiteralPath $file.FullName -Value ([pscustomobject]$rebuilt | ConvertTo-Json -Depth 10) -Encoding UTF8
        $repaired += , $runId
    }

    return $repaired
}

function _PCR_Ratio {
    <# Format a ratio for an operator-facing reason string. Invariant culture,
       so a machine with a comma decimal separator produces the same sentence a
       gate asserts against. #>
    param([object]$Value)
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.####}', [double]$Value)
}

<#
.SYNOPSIS
    Is there room to run a task on this provider, after the reserve is held back?

.DESCRIPTION
    The spec's reserve rules: normal implementation work cannot consume the
    reserve, remediation MAY consume it, and an operator MAY explicitly override
    it. This applies them to a capacity record and reports WHY, because a
    provider that silently stops being chosen is indistinguishable from one that
    is broken.

    **Unmeasured is not exhausted.** A record whose windows carry no ratio is
    eligible with the reason `capacity unmeasured`. The spec's `unknown` unit
    exists precisely so a provider that does not publish an allowance can still
    be used; treating silence as empty would strand Copilot permanently.

    **`enforced` needs BOTH provisional flags clear.** D-011 (2026-09-07) ruled
    the reserves -- 15% short, 20% weekly, remediation inside the weekly -- but
    deliberately left the per-task consumption estimate provisional, because
    nobody can know that number before real runs report usage. A reserve can
    only refuse work if you know what a task costs, so enforcing on a decided
    reserve and a guessed cost would refuse dispatches on an unmeasured number.
    Until observed consumption replaces the guess, every verdict here is
    computed and recorded and refuses nobody: H38-11 reads `enforced` and
    declines to act while it is false.
#>
function Resolve-ProviderCapacityVerdict {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Record,
        [Parameter(Mandatory)][object]$Config,
        [ValidateSet('normal', 'remediation')][string]$TaskClass = 'normal',
        [AllowNull()][object]$EstimatedConsumptionRatio = $null,
        [bool]$OperatorOverride = $false,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [AllowEmptyString()][string]$Provider = ''
    )

    $reserves = _PCR_Field -Obj $Config -Name 'reserves' -Default $null
    $estimates = _PCR_Field -Obj $Config -Name 'estimates' -Default $null

    # Both halves, never the reserves alone. See the D-011 note above.
    $reservesProvisional = [bool](_PCR_Field -Obj $reserves -Name 'provisional' -Default $false)
    $estimatesProvisional = [bool](_PCR_Field -Obj $estimates -Name 'provisional' -Default $false)
    $enforced = ((-not $reservesProvisional) -and (-not $estimatesProvisional))

    $estimate = _PCR_TryRatio $EstimatedConsumptionRatio
    if ($null -eq $estimate) {
        $estimate = _PCR_TryRatio (_PCR_Field -Obj $estimates -Name 'defaultTaskConsumptionRatio' -Default $null)
    }
    if ($null -eq $estimate) { $estimate = 0.0 }

    $shortReserve = [double](_PCR_TryRatio (_PCR_Field -Obj $reserves -Name 'shortWindowRatio' -Default 0.0))
    $weeklyReserve = [double](_PCR_TryRatio (_PCR_Field -Obj $reserves -Name 'weeklyRatio' -Default 0.0))
    $remediationInsideWeekly = [bool](_PCR_Field -Obj $reserves -Name 'remediationInsideWeekly' -Default $false)

    $recordProvider = [string](_PCR_Field -Obj $Record -Name 'provider' -Default '')
    $namedProvider = $(if ([string]::IsNullOrWhiteSpace($recordProvider)) { $Provider } else { $recordProvider })

    $verdict = [ordered]@{
        provider      = $namedProvider
        eligible      = $false
        reason        = ''
        window        = $null
        usableRatio   = $null
        reserveRatio  = $null
        cooldownUntil = $null
        enforced      = $enforced
    }

    # 1. No record at all. Ordinary on a fresh install, so it is a reason and
    #    not an error -- but it is not eligibility either, because nothing is
    #    known about what is left.
    if ($null -eq $Record) {
        $verdict.reason = 'no-capacity-record'
        return [pscustomobject]$verdict
    }

    # 2. The provider itself said no.
    if (-not [bool](_PCR_Field -Obj $Record -Name 'available' -Default $true)) {
        $verdict.reason = 'provider-unavailable'
        return [pscustomobject]$verdict
    }

    # 3. A cooldown in the future. A cooldown in the PAST is spent and ignored,
    #    which is what lets a provider come back on its own without anyone
    #    clearing the field.
    $cooldownRaw = _PCR_Stamp (_PCR_Field -Obj $Record -Name 'cooldownUntil' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($cooldownRaw)) {
        $cooldownAt = [datetime]::MinValue
        $parsedCooldown = [datetime]::TryParse(
            $cooldownRaw,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$cooldownAt)
        if ($parsedCooldown -and $cooldownAt -gt $NowUtc) {
            $verdict.reason = ('cooling-down until {0}' -f $cooldownRaw)
            $verdict.cooldownUntil = $cooldownRaw
            return [pscustomobject]$verdict
        }
    }

    $windows = @()
    if ($Record -is [System.Collections.IDictionary]) {
        if ($Record.Contains('windows')) { $windows = @($Record['windows']) }
    }
    elseif ($null -ne $Record.PSObject -and ($Record.PSObject.Properties.Name -contains 'windows')) {
        $windows = @($Record.windows)
    }

    $overrideSuffix = $(if ($OperatorOverride) { ' (operator override)' } else { '' })

    # 4. Every measured window must fit. The tightest one is what the verdict
    #    reports, because that is the one that will run out first.
    $tightestName = $null
    $tightestUsable = $null
    $tightestReserve = $null
    $measured = 0

    foreach ($window in $windows) {
        $ratio = $null
        if (_PCR_HasKey -Obj $window -Name 'remainingRatio') {
            $ratio = _PCR_TryRatio (_PCR_Field -Obj $window -Name 'remainingRatio' -Default $null)
        }
        if ($null -eq $ratio) { continue }
        $measured++

        $name = [string](_PCR_Field -Obj $window -Name 'name' -Default '')
        $reserve = 0.0
        if ($name -eq 'short-term') { $reserve = $shortReserve }
        elseif ($name -eq 'weekly') { $reserve = $weeklyReserve }

        # Remediation may draw from inside the weekly reserve; an operator
        # override releases every reserve. Both are the spec's, and both are
        # recorded in the reason so a released reserve is never invisible.
        $usable = [double]$ratio - $reserve
        if ($usable -lt 0.0) { $usable = 0.0 }
        if ($TaskClass -eq 'remediation' -and $remediationInsideWeekly -and $name -eq 'weekly') { $usable = [double]$ratio }
        if ($OperatorOverride) { $usable = [double]$ratio }

        if ($usable -lt $estimate) {
            $verdict.reason = ('insufficient {0} capacity: usable {1} < estimate {2}{3}' -f $name, (_PCR_Ratio $usable), (_PCR_Ratio $estimate), $overrideSuffix)
            $verdict.window = $name
            $verdict.usableRatio = $usable
            $verdict.reserveRatio = $reserve
            return [pscustomobject]$verdict
        }

        if ($null -eq $tightestUsable -or $usable -lt $tightestUsable) {
            $tightestUsable = $usable
            $tightestName = $name
            $tightestReserve = $reserve
        }
    }

    # 5. Nothing was measured. Unknown is not exhausted.
    if ($measured -eq 0) {
        $verdict.eligible = $true
        $verdict.reason = ('capacity unmeasured{0}' -f $overrideSuffix)
        return [pscustomobject]$verdict
    }

    # 6. Everything fits.
    $verdict.eligible = $true
    $verdict.reason = ('fits{0}' -f $overrideSuffix)
    $verdict.window = $tightestName
    $verdict.usableRatio = $tightestUsable
    $verdict.reserveRatio = $tightestReserve
    return [pscustomobject]$verdict
}

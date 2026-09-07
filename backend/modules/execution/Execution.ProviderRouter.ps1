<#
.SYNOPSIS
    Release 3.8 M3 (H38-17) — provider selection: eligibility, then ranking,
    with the reason recorded.

.DESCRIPTION
    Two stages, deliberately separate, because they answer different questions
    and confusing them is how a router becomes unexplainable.

      Stage 1 — ELIGIBILITY. May this provider run this packet at all? Each
                condition is recorded by name on the candidate, pass or fail,
                and the FIRST failure becomes `ineligibleBecause`. A provider
                that is never chosen has to be explainable without reading a
                log, which is the milestone's acceptance criterion.

      Stage 2 — RANKING. Among those that may, which should? A weighted sum of
                factors each normalised to [0,1], so a weight in config means
                what it looks like it means.

    Neither provider is globally preferred (spec, *Default routing policy*).
    Nothing here hardcodes claude, codex or copilot: the candidate set comes
    from the registry, and the only provider-shaped fact this module knows is
    that a `github-hosted` executionMode cannot run against an empty repository
    and is the only thing that can satisfy `githubWrite`.

    An UNENFORCED capacity verdict is advisory and does not exclude. D-011 left
    the per-task estimate provisional, so refusing work on a guessed cost would
    block real execution on a number nobody has measured. The check is still
    recorded — as `advisory` — so the reason string tells the truth about what
    was known rather than silently omitting it.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
    Pure: reads no file, launches nothing, and takes every input as a parameter.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# One week, the horizon `timeToReset` normalises against. A reset further out
# than this scores 0 rather than negative: "further away than a week" is one
# fact, not a range worth ordering.
$script:ProviderRouterResetHorizonHours = 168.0

function _PRT_Field {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    # ForEach-Object rather than `.Properties.Name`: under StrictMode,
    # member-access enumeration over an EMPTY property collection throws, and an
    # empty object is an ordinary input here.
    if ($null -ne $Obj.PSObject -and (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function _PRT_Ratio {
    <# A number in [0,1], or $null when it is not one. Never a guess. #>
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $parsed = 0.0
    if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $null }
    if ($parsed -lt 0.0 -or $parsed -gt 1.0) { return $null }
    return $parsed
}

function _PRT_Utc {
    <# Parse an ISO-8601 stamp to UTC, or $null. #>
    param([object]$Value)
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$parsed)
    if (-not $ok) { return $null }
    return $parsed
}

function _PRT_MapValue {
    <#
        Read one key from a hashtable-or-object map, answering $Default when the
        map is absent or the key is missing. AuthStatus in particular must
        default to NOT-authenticated: an absent entry means nothing was
        detected, and treating that as permission would route work to a provider
        no one has confirmed exists on this machine.
    #>
    param([object]$Map, [string]$Key, [object]$Default = $null)
    if ($null -eq $Map) { return $Default }
    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Key)) { return $Map[$Key] }
        return $Default
    }
    return (_PRT_Field -Obj $Map -Name $Key -Default $Default)
}

function _PRT_EarliestReset {
    <# The soonest resetAt across a capacity record's windows, or $null. #>
    param([object]$Record)
    if ($null -eq $Record) { return $null }
    $windows = @(_PRT_Field -Obj $Record -Name 'windows' -Default @())
    $earliest = $null
    foreach ($window in $windows) {
        $at = _PRT_Utc (_PRT_Field -Obj $window -Name 'resetAt' -Default '')
        if ($null -eq $at) { continue }
        if ($null -eq $earliest -or $at -lt $earliest) { $earliest = $at }
    }
    return $earliest
}

<#
.SYNOPSIS
    Success ratio and recent failure rate for one provider against one
    repository, from run history. Pure.

.DESCRIPTION
    Returns $null for both when there is no history: an unmeasured provider and
    a provider with a 0% success rate are different claims, and the caller
    substitutes a neutral 0.5 for the first rather than punishing a provider for
    never having been tried.

    `recentFailureRate` deliberately reads the last 10 entries for the provider
    REGARDLESS of repository. A provider failing everywhere is a fact about the
    provider; a provider failing in one repository is a fact about that pairing,
    which is what `history` measures.
#>
function Get-ProviderHistoryStat {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$History = @(),
        [Parameter(Mandatory)][string]$Provider,
        [Parameter()][AllowEmptyString()][string]$Repository = '',
        [Parameter()][int]$RecentWindow = 10
    )

    $mine = @(@($History) | Where-Object {
            $null -ne $_ -and [string](_PRT_Field -Obj $_ -Name 'provider' -Default '') -eq $Provider
        })

    $successRatio = $null
    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        $sameRepo = @($mine | Where-Object { [string](_PRT_Field -Obj $_ -Name 'repository' -Default '') -eq $Repository })
        if ($sameRepo.Count -gt 0) {
            $ok = @($sameRepo | Where-Object { [string](_PRT_Field -Obj $_ -Name 'status' -Default '') -eq 'implementation_complete' }).Count
            $successRatio = [double]$ok / [double]$sameRepo.Count
        }
    }

    $failureRate = $null
    if ($mine.Count -gt 0) {
        $recent = @($mine)
        if ($recent.Count -gt $RecentWindow) { $recent = @($recent[($recent.Count - $RecentWindow)..($recent.Count - 1)]) }
        $failed = @($recent | Where-Object { [string](_PRT_Field -Obj $_ -Name 'status' -Default '') -eq 'implementation_failed' }).Count
        $failureRate = [double]$failed / [double]$recent.Count
    }

    return [pscustomobject]@{
        successRatio = $successRatio
        failureRate  = $failureRate
        runs         = $mine.Count
    }
}

<#
.SYNOPSIS
    Choose a provider for one WorkPacket, and record why.

.OUTPUTS
    [pscustomobject] selected (string or $null), reason (string[]),
    candidates (object[]), tie (bool), tieBreak (string).
#>
function Resolve-ProviderSelection {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][object]$Packet = $null,
        [Parameter()][AllowEmptyCollection()][string[]]$Registry = @(),
        [Parameter()][AllowNull()][object]$CapacityRecords = $null,
        [Parameter()][AllowNull()][object]$AuthStatus = $null,
        [Parameter()][AllowNull()][object]$ActiveCounts = $null,
        [Parameter()][AllowEmptyCollection()][object[]]$History = @(),
        [Parameter()][AllowNull()][object]$Config = $null,
        [Parameter()][ValidateSet('normal', 'remediation')][string]$TaskClass = 'normal',
        [Parameter()][datetime]$NowUtc = [datetime]::UtcNow
    )

    $providersConfig = _PRT_Field -Obj $Config -Name 'providers' -Default $null
    $ranking = _PRT_Field -Obj $Config -Name 'ranking' -Default $null
    $weights = _PRT_Field -Obj $ranking -Name 'weights' -Default $null
    $tieBreak = [string](_PRT_Field -Obj $ranking -Name 'tieBreak' -Default 'alphabetical')

    $estimates = _PRT_Field -Obj $Config -Name 'estimates' -Default $null
    $estimate = _PRT_Ratio (_PRT_Field -Obj $estimates -Name 'defaultTaskConsumptionRatio' -Default $null)
    if ($null -eq $estimate) { $estimate = 0.0 }

    $execution = _PRT_Field -Obj $Packet -Name 'execution' -Default $null
    $preferred = [string](_PRT_Field -Obj $execution -Name 'preferredProvider' -Default 'auto')
    if ([string]::IsNullOrWhiteSpace($preferred)) { $preferred = 'auto' }
    $previousProvider = [string](_PRT_Field -Obj $execution -Name 'previousProvider' -Default '')
    $repository = [string](_PRT_Field -Obj $Packet -Name 'repository' -Default '')
    $permissions = _PRT_Field -Obj $Packet -Name 'permissions' -Default (_PRT_Field -Obj $Packet -Name 'permissionEnvelope' -Default $null)
    $needsGithubWrite = [bool](_PRT_Field -Obj $permissions -Name 'githubWrite' -Default $false)

    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($provider in @($Registry)) {
        $name = [string]$provider
        if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'auto') { continue }

        $entry = _PRT_Field -Obj $providersConfig -Name $name -Default $null
        $executionMode = [string](_PRT_Field -Obj $entry -Name 'executionMode' -Default 'local')
        $isHosted = ($executionMode -eq 'github-hosted')
        $maxConcurrent = [int](_PRT_Field -Obj $entry -Name 'maxConcurrentExecutions' -Default 1)

        # Checks are collected as DATA and rendered afterwards, so the order
        # they are declared in is the order they are reported in and the first
        # failure is found by reading the list rather than by a side effect.
        $checkList = [System.Collections.Generic.List[object]]::new()

        # A20: `supported` is the repository fact -- an adapter exists in this
        # build. Whether the tool is installed here is availability, which
        # arrives on AuthStatus and is a different question.
        $supported = [bool](_PRT_Field -Obj $entry -Name 'supported' -Default $false)
        $checkList.Add([pscustomobject]@{ label = 'supported'; passed = $supported; detail = '' }) | Out-Null

        # Absent means NOT available. An undetected provider is not permission.
        $available = [bool](_PRT_MapValue -Map $AuthStatus -Key $name -Default $false)
        $checkList.Add([pscustomobject]@{ label = 'available here'; passed = $available; detail = '' }) | Out-Null

        $capabilityOk = $true
        $capabilityDetail = ''
        if ($preferred -ne 'auto' -and $preferred -ne $name) {
            $capabilityOk = $false
            $capabilityDetail = ("the packet asks for '{0}'" -f $preferred)
        }
        elseif ($isHosted -and [string]::IsNullOrWhiteSpace($repository)) {
            # Nothing on GitHub to run against.
            $capabilityOk = $false
            $capabilityDetail = 'github-hosted execution needs a repository and the packet names none'
        }
        $checkList.Add([pscustomobject]@{ label = 'required capabilities'; passed = $capabilityOk; detail = $capabilityDetail }) | Out-Null

        # The spec's boundary: only a GitHub-hosted run can write to GitHub.
        $permissionsOk = ((-not $needsGithubWrite) -or $isHosted)
        $permissionsDetail = ''
        if (-not $permissionsOk) { $permissionsDetail = 'githubWrite requires a github-hosted provider' }
        $checkList.Add([pscustomobject]@{ label = 'permissions compatible'; passed = $permissionsOk; detail = $permissionsDetail }) | Out-Null

        $active = [int](_PRT_MapValue -Map $ActiveCounts -Key $name -Default 0)
        $slotOk = ($active -lt $maxConcurrent)
        $checkList.Add([pscustomobject]@{ label = 'concurrency slot'; passed = $slotOk; detail = ("{0} of {1} in use" -f $active, $maxConcurrent) }) | Out-Null

        $record = _PRT_MapValue -Map $CapacityRecords -Key $name -Default $null
        $verdict = $null
        if (Get-Command -Name 'Resolve-ProviderCapacityVerdict' -ErrorAction SilentlyContinue) {
            $verdict = Resolve-ProviderCapacityVerdict -Record $record -Config $Config -TaskClass $TaskClass `
                -EstimatedConsumptionRatio $estimate -NowUtc $NowUtc -Provider $name
        }

        $enforced = [bool](_PRT_Field -Obj $verdict -Name 'enforced' -Default $false)
        $verdictReason = [string](_PRT_Field -Obj $verdict -Name 'reason' -Default 'no capacity verdict')
        $capacityEligible = [bool](_PRT_Field -Obj $verdict -Name 'eligible' -Default $false)
        $cooldownUntil = [string](_PRT_Field -Obj $verdict -Name 'cooldownUntil' -Default '')
        $coolingDown = (-not [string]::IsNullOrWhiteSpace($cooldownUntil))

        if ($enforced) {
            $checkList.Add([pscustomobject]@{ label = 'not cooling down'; passed = (-not $coolingDown); detail = $verdictReason }) | Out-Null
            $checkList.Add([pscustomobject]@{ label = 'capacity fits'; passed = $capacityEligible; detail = $verdictReason }) | Out-Null
        }
        else {
            # Recorded, and deliberately not binding. D-011 left the per-task
            # estimate provisional; refusing on a guessed cost would block real
            # work on a number nobody measured. `advisory = $null` is the third
            # state: it is neither a pass nor a failure, so it never becomes
            # ineligibleBecause while still appearing in the reason.
            $checkList.Add([pscustomobject]@{ label = 'not cooling down'; passed = $null; detail = $verdictReason }) | Out-Null
            $checkList.Add([pscustomobject]@{ label = 'capacity fits'; passed = $null; detail = $verdictReason }) | Out-Null
        }

        $checks = [System.Collections.Generic.List[string]]::new()
        $ineligible = ''
        foreach ($check in $checkList) {
            $state = 'advisory'
            if ($null -ne $check.passed) { $state = $(if ([bool]$check.passed) { 'ok' } else { 'no' }) }
            $line = ("{0}: {1}" -f $check.label, $state)
            if (-not [string]::IsNullOrWhiteSpace([string]$check.detail)) { $line = ("{0} ({1})" -f $line, $check.detail) }
            $checks.Add($line) | Out-Null
            if ($null -ne $check.passed -and -not [bool]$check.passed -and [string]::IsNullOrWhiteSpace($ineligible)) {
                $ineligible = $line
            }
        }
        $eligible = [string]::IsNullOrWhiteSpace($ineligible)

        $candidates.Add([pscustomobject]@{
                provider          = $name
                eligible          = $eligible
                ineligibleBecause = $ineligible
                checks            = @($checks)
                executionMode     = $executionMode
                verdict           = $verdict
                score             = $null
                factors           = $null
                earliestReset     = _PRT_EarliestReset -Record $record
            }) | Out-Null
    }

    $eligibleCandidates = @($candidates | Where-Object { $_.eligible })

    if ($eligibleCandidates.Count -eq 0) {
        $reason = [System.Collections.Generic.List[string]]::new()
        $reason.Add('no eligible provider') | Out-Null
        foreach ($candidate in $candidates) {
            $why = [string]$candidate.ineligibleBecause
            if ([string]::IsNullOrWhiteSpace($why)) { $why = 'no reason recorded' }
            $reason.Add(("{0}: {1}" -f $candidate.provider, $why)) | Out-Null
        }
        return [pscustomobject]@{
            selected   = $null
            reason     = @($reason)
            candidates = @($candidates)
            tie        = $false
            tieBreak   = $tieBreak
        }
    }

    # ---- Stage 2: ranking -------------------------------------------------
    foreach ($candidate in $eligibleCandidates) {
        $name = [string]$candidate.provider
        $verdict = $candidate.verdict

        $usable = _PRT_Ratio (_PRT_Field -Obj $verdict -Name 'usableRatio' -Default $null)
        $usableFactor = 0.5
        if ($null -ne $usable) { $usableFactor = $usable }

        $suitability = 0.5
        if ($preferred -ne 'auto' -and $preferred -eq $name) { $suitability = 1.0 }

        $stat = Get-ProviderHistoryStat -History @($History) -Provider $name -Repository $repository
        $historyFactor = 0.5
        if ($null -ne $stat.successRatio) { $historyFactor = [double]$stat.successRatio }

        $fitsWindow = 0.5
        if ($null -ne $usable -and $estimate -gt 0.0 -and $usable -ge (2.0 * $estimate)) { $fitsWindow = 1.0 }

        $sessionReuse = 0.0
        if (-not [string]::IsNullOrWhiteSpace($previousProvider) -and $previousProvider -eq $name) { $sessionReuse = 1.0 }

        $timeToReset = 0.5
        if ($null -ne $candidate.earliestReset) {
            $hours = ([datetime]$candidate.earliestReset - $NowUtc).TotalHours
            if ($hours -lt 0.0) { $hours = 0.0 }
            $timeToReset = 1.0 - ($hours / $script:ProviderRouterResetHorizonHours)
            if ($timeToReset -lt 0.0) { $timeToReset = 0.0 }
            if ($timeToReset -gt 1.0) { $timeToReset = 1.0 }
        }

        $failureFactor = 0.0
        if ($null -ne $stat.failureRate) { $failureFactor = [double]$stat.failureRate }

        $factors = [ordered]@{
            suitability          = $suitability
            usableCapacity       = $usableFactor
            history              = $historyFactor
            fitsWindow           = $fitsWindow
            sessionReuse         = $sessionReuse
            timeToReset          = $timeToReset
            estimatedConsumption = $estimate
            recentFailureRate    = $failureFactor
        }

        $score = 0.0
        foreach ($factorName in @($factors.Keys)) {
            $weight = _PRT_Field -Obj $weights -Name $factorName -Default 0
            $parsedWeight = 0.0
            if (-not [double]::TryParse([string]$weight, [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedWeight)) { $parsedWeight = 0.0 }
            $score += ($parsedWeight * [double]$factors[$factorName])
        }

        $candidate.factors = $factors
        # Rounded before comparison, so two providers that differ only by
        # floating-point noise register as the TIE they actually are and the
        # configured tie-break decides instead of the last bit of a double.
        $candidate.score = [math]::Round($score, 6)
    }

    $ordered = @($eligibleCandidates | Sort-Object -Property @{ Expression = { [double]$_.score }; Descending = $true }, @{ Expression = { [string]$_.provider }; Ascending = $true })
    $topScore = [double]$ordered[0].score
    $tied = @($ordered | Where-Object { [double]$_.score -eq $topScore })
    $isTie = ($tied.Count -gt 1)

    $winner = $ordered[0]
    $tieBreakUsed = ''
    if ($isTie) {
        switch ($tieBreak) {
            'nearest-reset-first' {
                # A candidate with no resetAt sorts LAST: "no known reset" is not
                # the same as "resets soon", and treating it as soonest would
                # prefer the provider we know least about.
                $withReset = @($tied | Where-Object { $null -ne $_.earliestReset } | Sort-Object -Property @{ Expression = { [datetime]$_.earliestReset } })
                if ($withReset.Count -gt 0) {
                    $winner = $withReset[0]
                    $tieBreakUsed = 'nearest-reset-first'
                }
                else {
                    $winner = @($tied | Sort-Object -Property @{ Expression = { [string]$_.provider } })[0]
                    $tieBreakUsed = 'nearest-reset-first (no candidate reported a reset time, so alphabetical)'
                }
            }
            'alphabetical' {
                $winner = @($tied | Sort-Object -Property @{ Expression = { [string]$_.provider } })[0]
                $tieBreakUsed = 'alphabetical'
            }
            default {
                $winner = @($tied | Sort-Object -Property @{ Expression = { [string]$_.provider } })[0]
                $tieBreakUsed = ("unknown tieBreak '{0}', fell back to alphabetical" -f $tieBreak)
            }
        }
    }

    $reason = [System.Collections.Generic.List[string]]::new()
    $reason.Add('eligible') | Out-Null
    foreach ($candidate in $ordered) {
        $detail = @(@($candidate.factors.Keys) | ForEach-Object { ("{0}={1}" -f $_, [math]::Round([double]$candidate.factors[$_], 3)) })
        $reason.Add(("{0} for {1}: {2}" -f $candidate.score, $candidate.provider, ($detail -join ' '))) | Out-Null
    }
    $reason.Add(("selected {0}" -f $winner.provider)) | Out-Null
    if ($isTie) {
        $reason.Add(("tie broken by {0} among {1}" -f $tieBreakUsed, (@($tied | ForEach-Object { $_.provider }) -join ', '))) | Out-Null
    }
    foreach ($candidate in @($candidates | Where-Object { -not $_.eligible })) {
        $reason.Add(("{0} excluded: {1}" -f $candidate.provider, $candidate.ineligibleBecause)) | Out-Null
    }

    return [pscustomobject]@{
        selected   = [string]$winner.provider
        reason     = @($reason)
        candidates = @($candidates)
        tie        = $isTie
        tieBreak   = $tieBreak
    }
}

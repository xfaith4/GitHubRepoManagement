<#
.SYNOPSIS
    Classifies open roadmap lines before anything ranks them (Lane 0.22, loop step 1).

.DESCRIPTION
    The 2026-10-16 evaluation found runner runs failing on "no actionable items"
    and the queue offering lines that were never work: a done statement left
    unticked, a [non-blocker] recorded on purpose, a standing rule, a lead-in to
    a nested list. Every open checkbox is now classified

        actionable | done-statement | deferred | guidance | fragment

    and only `actionable` is ranked, queued or offered for dispatch. Every other
    line is KEPT, with the rule that excluded it, because steering 2.3 forbids a
    silent drop: the repository shows "Excluded (n)" with a reason per line.

    The rules are data in backend/config/roadmap-item-rules.json (steering 2.6).
    This file only evaluates them: classes in order, first matching rule wins,
    no match means actionable. Pure functions; nothing here reads a repository.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RoadmapItemClasses = @('actionable', 'done-statement', 'deferred', 'guidance', 'fragment')
$script:RoadmapItemRuleFields = @('text', 'section', 'tag')

function Get-RoadmapItemRuleConfig {
    <#
    .SYNOPSIS
        Loads and validates the work-item quality model; throws rather than degrade.
    .DESCRIPTION
        A missing or malformed model throws. The alternative -- treating every
        line as actionable -- is exactly the failure this model exists to stop,
        and it would arrive silently (the trap Get-PortfolioValueScoringConfig
        documents for the executor classifier). Each pattern is compiled here,
        once, so a bad regex fails at load with its rule id rather than mid-scan.
    #>
    [CmdletBinding()]
    param([string]$ConfigPath = '')

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $PSScriptRoot '..\..\config\roadmap-item-rules.json'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Roadmap item rules not found at '$ConfigPath'."
    }

    $raw = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8)
    if ([string]$raw.schemaVersion -ne 'v1') {
        throw "Roadmap item rules at '$ConfigPath' carry schemaVersion '$($raw.schemaVersion)'; expected 'v1'."
    }
    if ([string]::IsNullOrWhiteSpace([string]$raw.modelVersion)) {
        throw "Roadmap item rules at '$ConfigPath' carry no modelVersion."
    }

    $classes = [System.Collections.Generic.List[object]]::new()
    foreach ($cls in @($raw.classes)) {
        $name = [string]$cls.class
        if ($script:RoadmapItemClasses -notcontains $name -or $name -eq 'actionable') {
            throw "Roadmap item rules: '$name' is not an exclusion class (expected one of done-statement, deferred, guidance, fragment)."
        }
        $rules = [System.Collections.Generic.List[object]]::new()
        foreach ($rule in @($cls.rules)) {
            $id = [string]$rule.id
            $field = [string]$rule.field
            if ([string]::IsNullOrWhiteSpace($id)) { throw "Roadmap item rules: a '$name' rule has no id." }
            if ($script:RoadmapItemRuleFields -notcontains $field) {
                throw "Roadmap item rules: rule '$id' tests field '$field'; expected text, section or tag."
            }
            if ([string]::IsNullOrWhiteSpace([string]$rule.reason)) { throw "Roadmap item rules: rule '$id' has no reason." }
            try {
                $regex = [regex]::new([string]$rule.pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            } catch {
                throw "Roadmap item rules: rule '$id' has an invalid pattern: $($_.Exception.Message)"
            }
            $rules.Add([pscustomobject]@{ id = $id; field = $field; regex = $regex; reason = [string]$rule.reason }) | Out-Null
        }
        $minWords = 0
        if ($cls.PSObject.Properties.Name -contains 'minWords') { $minWords = [int]$cls.minWords }
        $minWordsReason = ''
        if ($cls.PSObject.Properties.Name -contains 'minWordsReason') { $minWordsReason = [string]$cls.minWordsReason }
        if ($minWords -gt 0 -and [string]::IsNullOrWhiteSpace($minWordsReason)) {
            throw "Roadmap item rules: class '$name' sets minWords without a minWordsReason."
        }
        $classes.Add([pscustomobject]@{
            name           = $name
            minWords       = $minWords
            minWordsReason = $minWordsReason
            rules          = $rules.ToArray()
        }) | Out-Null
    }
    if ($classes.Count -eq 0) { throw "Roadmap item rules at '$ConfigPath' define no classes." }

    $cooldownHours = 0
    if ($raw.PSObject.Properties.Name -contains 'cooldown' -and $null -ne $raw.cooldown) {
        $cooldownHours = [double]$raw.cooldown.hours
    }

    return [pscustomobject]@{
        schemaVersion = 'v1'
        modelVersion  = [string]$raw.modelVersion
        sourcePath    = $ConfigPath
        classes       = $classes.ToArray()
        cooldownHours = $cooldownHours
    }
}

function _RIQ_CountWord {
    param([string]$Text)
    # Markdown emphasis, code ticks and link targets are not words.
    $plain = [regex]::Replace($Text, '\]\([^)]*\)', ']')
    $plain = [regex]::Replace($plain, '[*_`~\[\]]', ' ')
    return @([regex]::Matches($plain, '[A-Za-z0-9][A-Za-z0-9''.-]*')).Count
}

function Get-RoadmapItemClass {
    <#
    .SYNOPSIS
        One open roadmap line's class, with the rule and reason that decided it.
    .OUTPUTS
        { itemClass, ruleId, reason, modelVersion }. ruleId and reason are empty
        for an actionable line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$Section = '',
        [AllowEmptyCollection()][string[]]$Tags = @(),
        [Parameter(Mandatory)][object]$Config
    )

    foreach ($cls in @($Config.classes)) {
        if ($cls.minWords -gt 0 -and (_RIQ_CountWord -Text $Text) -lt $cls.minWords) {
            return [pscustomobject]@{ itemClass = $cls.name; ruleId = "$($cls.name)-min-words"; reason = $cls.minWordsReason; modelVersion = $Config.modelVersion }
        }
        foreach ($rule in @($cls.rules)) {
            $hit = $false
            switch ($rule.field) {
                'text'    { $hit = $rule.regex.IsMatch($Text) }
                'section' { $hit = (-not [string]::IsNullOrWhiteSpace($Section)) -and $rule.regex.IsMatch($Section) }
                'tag'     { foreach ($t in @($Tags)) { if ($rule.regex.IsMatch(([string]$t).ToLowerInvariant())) { $hit = $true; break } } }
            }
            if ($hit) {
                return [pscustomobject]@{ itemClass = $cls.name; ruleId = $rule.id; reason = $rule.reason; modelVersion = $Config.modelVersion }
            }
        }
    }
    return [pscustomobject]@{ itemClass = 'actionable'; ruleId = ''; reason = ''; modelVersion = $Config.modelVersion }
}

function Get-RoadmapItemHash {
    <#
    .SYNOPSIS
        A stable identity for one roadmap item: repository plus normalized text.
    .DESCRIPTION
        Case and runs of whitespace do not change the hash, so re-wrapping a line
        or fixing its capitalisation cannot reset a dispatch cooldown. Rewording
        it does, deliberately: reworded work is a different request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RepoName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    $norm = ('{0}|{1}' -f $RepoName.Trim().ToLowerInvariant(), ([regex]::Replace($Text, '\s+', ' ')).Trim().ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))
    } finally {
        $sha.Dispose()
    }
    return (-join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') }))
}

function Split-RoadmapItemByQuality {
    <#
    .SYNOPSIS
        Splits pending items into the actionable ones and the explained rest.
    .DESCRIPTION
        Order is preserved in both lists. An actionable item is passed through
        unchanged, so ranking sees exactly what it saw before for every line
        that survives. An excluded item becomes
        { text, section, tags, itemClass, ruleId, reason, itemHash }.
    .OUTPUTS
        { actionable = object[]; excluded = object[]; modelVersion }
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [AllowEmptyString()][string]$RepoName = '',
        [Parameter(Mandatory)][object]$Config
    )

    $actionable = [System.Collections.Generic.List[object]]::new()
    $excluded = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $text = [string]$item.text
        $section = ''
        if ($item.PSObject.Properties.Name -contains 'section') { $section = [string]$item.section }
        $tags = @()
        if ($item.PSObject.Properties.Name -contains 'tags') { $tags = @($item.tags | ForEach-Object { [string]$_ }) }

        $verdict = Get-RoadmapItemClass -Text $text -Section $section -Tags $tags -Config $Config
        if ($verdict.itemClass -eq 'actionable') {
            $actionable.Add($item) | Out-Null
            continue
        }
        $excluded.Add([pscustomobject]@{
            text      = $text
            section   = $section
            tags      = @($tags)
            itemClass = $verdict.itemClass
            ruleId    = $verdict.ruleId
            reason    = $verdict.reason
            itemHash  = Get-RoadmapItemHash -RepoName $RepoName -Text $text
        }) | Out-Null
    }

    return [pscustomobject]@{
        actionable   = $actionable.ToArray()
        excluded     = $excluded.ToArray()
        modelVersion = $Config.modelVersion
    }
}

function _RIQ_RepoKey {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ($Path.Trim() -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

function Get-RoadmapItemDispatchRecord {
    <#
    .SYNOPSIS
        Every item the runner actually launched, read from its run summaries.
    .DESCRIPTION
        A run counts as a dispatch once the runner claimed it, which is when it
        writes runnerStartedAt. A queued, previewed or refused run never reached
        an agent and so starts no cooldown. An unreadable summary is skipped:
        it cannot say what was dispatched.
    .OUTPUTS
        { runId, repoKey, repoName, text, startedAtUtc } per claimed run.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$RunsDir)

    $records = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($RunsDir) -or -not (Test-Path -LiteralPath $RunsDir -PathType Container)) { return , $records.ToArray() }
    foreach ($file in @(Get-ChildItem -LiteralPath $RunsDir -Filter '*.summary.json' -File)) {
        $summary = $null
        try { $summary = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) } catch { continue }
        if ($null -eq $summary) { continue }
        $names = @($summary.PSObject.Properties.Name)
        if ($names -notcontains 'runnerStartedAt' -or $names -notcontains 'selectedTask') { continue }
        $text = [string]$summary.selectedTask
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        # ConvertFrom-Json on PowerShell 7 already turns an ISO timestamp into a
        # DateTime; stringifying that would drop its offset, so use it directly.
        $rawStarted = $summary.runnerStartedAt
        $started = [datetimeoffset]::MinValue
        if ($rawStarted -is [datetime]) {
            $started = [datetimeoffset]$rawStarted.ToUniversalTime()
        } elseif ($rawStarted -is [datetimeoffset]) {
            $started = $rawStarted
        } elseif (-not [datetimeoffset]::TryParse([string]$rawStarted, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$started)) {
            continue
        }
        $localPath = if ($names -contains 'localRepoPath') { [string]$summary.localRepoPath } else { '' }
        $runId = if ($names -contains 'runId') { [string]$summary.runId } else { $file.Name -replace '\.summary\.json$', '' }
        $repoKey = _RIQ_RepoKey $localPath
        $repoName = if ($repoKey) { Split-Path -Leaf $repoKey } else { '' }
        $records.Add([pscustomobject]@{
            runId        = $runId
            repoKey      = $repoKey
            repoName     = $repoName
            text         = $text
            startedAtUtc = $started.UtcDateTime
        }) | Out-Null
    }
    return , $records.ToArray()
}

function Test-RoadmapItemCooldown {
    <#
    .SYNOPSIS
        Was this item dispatched to this repository inside the cooldown window?
    .DESCRIPTION
        Pure. The same item is the same repository (by local path) and the same
        item hash, so re-wrapping or re-casing the line does not reset the
        window. The run being decided is passed as -ExcludeRunId so it never
        cools itself down. A window of 0 hours never cools anything.
    .OUTPUTS
        { coolingDown, itemHash, lastRunId, lastStartedAtUtc, untilUtc, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RepoPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowEmptyCollection()][object[]]$Records = @(),
        [Parameter(Mandatory)][object]$Config,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [AllowEmptyString()][string]$ExcludeRunId = ''
    )

    $repoKey = _RIQ_RepoKey $RepoPath
    $repoName = if ($repoKey) { Split-Path -Leaf $repoKey } else { '' }
    $hash = Get-RoadmapItemHash -RepoName $repoName -Text $Text
    $result = [ordered]@{ coolingDown = $false; itemHash = $hash; lastRunId = $null; lastStartedAtUtc = $null; untilUtc = $null; reason = $null }
    $hours = [double]$Config.cooldownHours
    if ($hours -le 0 -or -not $repoKey -or [string]::IsNullOrWhiteSpace($Text)) { return [pscustomobject]$result }

    $now = $NowUtc.ToUniversalTime()
    $latest = $null
    foreach ($r in @($Records)) {
        if ($null -eq $r -or $r.repoKey -ne $repoKey) { continue }
        if ($ExcludeRunId -and $r.runId -eq $ExcludeRunId) { continue }
        if ((Get-RoadmapItemHash -RepoName $repoName -Text ([string]$r.text)) -ne $hash) { continue }
        if ($null -eq $latest -or $r.startedAtUtc -gt $latest.startedAtUtc) { $latest = $r }
    }
    if ($null -eq $latest) { return [pscustomobject]$result }

    $until = $latest.startedAtUtc.AddHours($hours)
    $result.lastRunId = $latest.runId
    $result.lastStartedAtUtc = $latest.startedAtUtc.ToString('o')
    $result.untilUtc = $until.ToString('o')
    if ($until -gt $now) {
        $result.coolingDown = $true
        $result.reason = ("this item was dispatched to {0} by run {1} at {2:u}; the {3}-hour cooldown runs until {4:u}. Re-queue with -OverrideCooldown to dispatch it again now." -f $repoName, $latest.runId, $latest.startedAtUtc, $hours, $until)
    }
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Roadmap contract normalization and rule-based auditor.
.DESCRIPTION
    Provides two exported functions:

      Invoke-NormalizeRoadmapContract
        Maps a parsed roadmap result (from Invoke-ParseRoadmapContent) plus raw
        content and metadata into the stable RoadmapContract internal model
        defined by roadmap-contract.schema.json.

      Invoke-AuditRoadmapContract
        Applies the weighted rule pack from roadmap-audit-rules.json to a
        normalized contract, returning a scored contract with maturity level
        (L0-Absent through L4-Orchestration-Ready) and per-rule findings.

.NOTES
    Dot-source this file after Roadmap.Parser.ps1 to load both functions:
        . (Join-Path $moduleRoot 'Roadmap.Parser.ps1')
        . (Join-Path $moduleRoot 'Roadmap.Auditor.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Shared detection contract
# ---------------------------------------------------------------------------
#
# Detection is DATA, not code. The canonical patterns live in
# standards/roadmap/roadmap-audit-rules.json under "detection", and both this
# module and tools/Test-RoadmapContract.ps1 read them from there. The literals
# below are a mirror used only when a caller supplies no rule pack (or an
# older one without the block) — keep them byte-identical to the JSON.
#
# Before 2026-08-08 the two evaluators each carried their own release-heading
# regex, product-intent vocabulary, and acceptance-criteria scope. The result
# was that no repository in the estate scored the same under both, and three
# straddled the L3 dispatch threshold depending on which tool ran. Do not
# reintroduce a private copy of any pattern here.

$script:RoadmapDetectionDefaults = [pscustomobject]@{
    releaseHeadingPattern            = '(?im)^#{2,}\s+Release\s+([0-9]+(?:\.[0-9]+)*)\s*[—–-]+\s*(.+?)\s*$'
    releaseStatusPattern             = '(?im)^\s*>?\s*\**\s*Status\s*\**\s*:\s*\**\s*([A-Za-z][A-Za-z \-]*?)\s*\**\s*(?:$|[—–\-(.,;])'
    activeStatuses                   = @('active')
    statusAliases                    = @{
        'in progress' = 'active'
        'in-progress' = 'active'
        'inprogress'  = 'active'
        'wip'         = 'active'
        'current'     = 'active'
        'ongoing'     = 'active'
        'complete'    = 'done'
        'completed'   = 'done'
        'delivered'   = 'done'
        'shipped'     = 'done'
        'released'    = 'done'
        'finished'    = 'done'
        'pending'     = 'planned'
        'not started' = 'planned'
        'upcoming'    = 'planned'
        'deferred'    = 'planned'
        'proposed'    = 'planned'
        'on hold'     = 'blocked'
        'paused'      = 'blocked'
        'in review'   = 'validation'
        'review'      = 'validation'
        'validating'  = 'validation'
    }
    productIntentHeadingPattern      = '(?im)^#{1,6}\s*(?:[0-9]+\.\s*)?(?:product\s+intent|product\s+scope|product\s+direction|overview|about|purpose|background|what\s+this\s+(?:does|is))\b'
    acceptanceCriteriaHeadingAliases = @('Acceptance criteria', 'Done criteria', 'Definition of done')
    outOfScopeHeadingAliases         = @('Out of scope', 'Out-of-scope', 'Not in scope', 'Non-goals', 'Non goals', 'Not included', 'Excluded', 'Exclusions')
    releaseScopedSignals             = @('hasAcceptanceCriteria', 'hasOutOfScope')
    meaningfulBodyMinimumCharacters  = 4
    meaningfulBodyPlaceholderPattern = '(?i)\b(tbd|todo|none yet|not yet|n/a)\b'
    scoringMode                      = 'normalized'
}

<#
.SYNOPSIS
    Resolve the detection contract for an audit run.
.PARAMETER AuditRules
    A loaded roadmap-audit-rules.json object, or $null.
.OUTPUTS
    [pscustomobject] with every detection field populated — values from the
    rule pack's "detection" block where present, canonical defaults otherwise.
#>
function Get-RoadmapDetectionProfile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowNull()]
        [pscustomobject]$AuditRules
    )

    $detectionProfile = $script:RoadmapDetectionDefaults.PSObject.Copy()
    if ($null -eq $AuditRules -or $AuditRules.PSObject.Properties.Name -notcontains 'detection') {
        return $detectionProfile
    }

    $d = $AuditRules.detection
    if ($null -eq $d) { return $detectionProfile }

    $names = @($d.PSObject.Properties.Name)
    if ($names -contains 'releaseHeadingPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.releaseHeadingPattern)) {
        $detectionProfile.releaseHeadingPattern = [string]$d.releaseHeadingPattern
    }
    if ($names -contains 'productIntentHeadingPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.productIntentHeadingPattern)) {
        $detectionProfile.productIntentHeadingPattern = [string]$d.productIntentHeadingPattern
    }
    if ($names -contains 'releaseStatusPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.releaseStatusPattern)) {
        $detectionProfile.releaseStatusPattern = [string]$d.releaseStatusPattern
    }
    if ($names -contains 'statusVocabulary' -and $null -ne $d.statusVocabulary) {
        $svNames = @($d.statusVocabulary.PSObject.Properties.Name)
        if ($svNames -contains 'activeStatuses' -and @($d.statusVocabulary.activeStatuses).Count -gt 0) {
            $detectionProfile.activeStatuses = @($d.statusVocabulary.activeStatuses | ForEach-Object { ([string]$_).ToLowerInvariant() })
        }
        if ($svNames -contains 'statusAliases' -and $null -ne $d.statusVocabulary.statusAliases) {
            $aliasMap = @{}
            foreach ($p in $d.statusVocabulary.statusAliases.PSObject.Properties) {
                $aliasMap[$p.Name.ToLowerInvariant()] = ([string]$p.Value).ToLowerInvariant()
            }
            if ($aliasMap.Count -gt 0) { $detectionProfile.statusAliases = $aliasMap }
        }
    }
    if ($names -contains 'acceptanceCriteriaHeadingAliases' -and @($d.acceptanceCriteriaHeadingAliases).Count -gt 0) {
        $detectionProfile.acceptanceCriteriaHeadingAliases = @($d.acceptanceCriteriaHeadingAliases)
    }
    if ($names -contains 'outOfScopeHeadingAliases' -and @($d.outOfScopeHeadingAliases).Count -gt 0) {
        $detectionProfile.outOfScopeHeadingAliases = @($d.outOfScopeHeadingAliases)
    }
    if ($names -contains 'releaseScopedSignals') {
        $detectionProfile.releaseScopedSignals = @($d.releaseScopedSignals)
    }
    if ($names -contains 'meaningfulBody' -and $null -ne $d.meaningfulBody) {
        $mbNames = @($d.meaningfulBody.PSObject.Properties.Name)
        if ($mbNames -contains 'minimumCharacters') {
            $detectionProfile.meaningfulBodyMinimumCharacters = [int]$d.meaningfulBody.minimumCharacters
        }
        if ($mbNames -contains 'placeholderPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.meaningfulBody.placeholderPattern)) {
            $detectionProfile.meaningfulBodyPlaceholderPattern = [string]$d.meaningfulBody.placeholderPattern
        }
    }
    if ($names -contains 'scoring' -and $null -ne $d.scoring -and
        @($d.scoring.PSObject.Properties.Name) -contains 'mode' -and
        -not [string]::IsNullOrWhiteSpace([string]$d.scoring.mode)) {
        $detectionProfile.scoringMode = [string]$d.scoring.mode
    }

    return $detectionProfile
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _DetectProductIntent {
    param([string]$Content, [pscustomobject]$Detection)
    if ([string]::IsNullOrWhiteSpace($Content)) { return $false }
    return ([regex]::IsMatch($Content, $Detection.productIntentHeadingPattern))
}

# Split the document into release blocks: the text from one release heading up
# to the next (or end of file). Returns [pscustomobject] with headingLevel and
# text so subsection detection can require a heading DEEPER than its release.
function _GetReleaseBlocks {
    param([string]$Content, [pscustomobject]$Detection)

    $blocks = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $headingMatches = [regex]::Matches($Content, $Detection.releaseHeadingPattern)
    for ($i = 0; $i -lt $headingMatches.Count; $i++) {
        $start = $headingMatches[$i].Index
        $end = if ($i + 1 -lt $headingMatches.Count) { $headingMatches[$i + 1].Index } else { $Content.Length }
        $headingText = $headingMatches[$i].Value.TrimStart("`r", "`n")
        $hashes = [regex]::Match($headingText, '^#+')
        $blocks.Add([pscustomobject]@{
            headingLevel = if ($hashes.Success) { $hashes.Value.Length } else { 2 }
            text         = $Content.Substring($start, $end - $start)
        }) | Out-Null
    }

    return @($blocks.ToArray())
}

function _TestMeaningfulBody {
    param([string]$Body, [pscustomobject]$Detection)

    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    $compact = ($Body -replace '[\s\-_*`#>]', '').Trim()
    if ($compact.Length -lt [int]$Detection.meaningfulBodyMinimumCharacters) { return $false }
    if ([regex]::IsMatch($Body, $Detection.meaningfulBodyPlaceholderPattern)) { return $false }
    return $true
}

# True when at least one release block carries a subsection matching one of
# $Aliases with a meaningful body. Release-scoped by contract: ROADMAP-006 and
# ROADMAP-007 both read "at least one release section includes ...".
function _TestReleaseScopedSubsection {
    param([object[]]$ReleaseBlocks, [string[]]$Aliases, [pscustomobject]$Detection)

    if ($null -eq $ReleaseBlocks -or @($ReleaseBlocks).Count -eq 0) { return $false }
    if ($null -eq $Aliases -or @($Aliases).Count -eq 0) { return $false }

    $aliasAlternation = (@($Aliases) | ForEach-Object { [regex]::Escape([string]$_) }) -join '|'

    foreach ($block in @($ReleaseBlocks)) {
        $lines = @($block.text -split "`r?`n")
        $minDepth = [int]$block.headingLevel + 1
        $capturing = $false
        $buffer = [System.Collections.Generic.List[string]]::new()

        foreach ($line in $lines) {
            $heading = [regex]::Match($line, '^(#{1,6})\s+(.+?)\s*$')
            if ($heading.Success) {
                if ($capturing) {
                    if (_TestMeaningfulBody -Body ($buffer -join "`n") -Detection $Detection) { return $true }
                    $capturing = $false
                    $buffer.Clear()
                }
                $level = $heading.Groups[1].Value.Length
                $text = $heading.Groups[2].Value.Trim()
                if ($level -ge $minDepth -and $text -match ('(?i)^\s*(?:' + $aliasAlternation + ')\s*$')) {
                    $capturing = $true
                }
                continue
            }
            if ($capturing) { $buffer.Add($line) | Out-Null }
        }

        if ($capturing -and (_TestMeaningfulBody -Body ($buffer -join "`n") -Detection $Detection)) { return $true }
    }

    return $false
}

# Document-scoped variant, used only when the rule pack removes a signal from
# detection.releaseScopedSignals. Any heading depth, anywhere in the file.
function _TestDocumentScopedSubsection {
    param([string]$Content, [string[]]$Aliases, [pscustomobject]$Detection)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $false }
    $whole = @([pscustomobject]@{ headingLevel = 0; text = $Content })
    return (_TestReleaseScopedSubsection -ReleaseBlocks $whole -Aliases $Aliases -Detection $Detection)
}

# Count release blocks whose declared status normalizes to 'active'. The
# canonical form in ROADMAP_TEMPLATE.md is a blockquote — "> Status: active" —
# so a leading '>' must be tolerated; "**Status:** active", "Status: In
# Progress", and "**Status: active**" are also accepted. Matching is
# case-insensitive and alias-normalized so legacy wording scores the same as
# the canonical wording.
function _DetectActiveReleaseCount {
    param([object[]]$ReleaseBlocks, [pscustomobject]$Detection)

    if ($null -eq $ReleaseBlocks -or @($ReleaseBlocks).Count -eq 0) { return 0 }
    if ($null -eq $Detection) { $Detection = Get-RoadmapDetectionProfile -AuditRules $null }

    $activeStatuses = @($Detection.activeStatuses)
    $aliases        = $Detection.statusAliases

    $activeCount = 0
    foreach ($block in @($ReleaseBlocks)) {
        $m = [regex]::Match($block.text, $Detection.releaseStatusPattern)
        if (-not $m.Success) { continue }

        $raw = $m.Groups[1].Value.Trim().ToLowerInvariant()
        # Normalize through the shared alias map before asking whether it is an
        # active status, so 'In progress' and 'active' resolve identically here
        # and in tools/Test-RoadmapContract.ps1.
        if ($null -ne $aliases -and $aliases.ContainsKey($raw)) { $raw = [string]$aliases[$raw] }
        if ($activeStatuses -contains $raw) { $activeCount++ }
    }

    return $activeCount
}

function _CountVagueItems {
    param([array]$ParsedSections, [array]$VaguePatterns)
    $count = 0
    if ($null -eq $ParsedSections -or $ParsedSections.Count -eq 0) { return $count }
    if ($null -eq $VaguePatterns -or $VaguePatterns.Count -eq 0) { return $count }
    foreach ($sec in $ParsedSections) {
        $allItems = @()
        if ($sec.pendingItems)   { $allItems += @($sec.pendingItems) }
        if ($sec.completedItems) { $allItems += @($sec.completedItems) }
        foreach ($item in $allItems) {
            foreach ($pattern in $VaguePatterns) {
                if ($item -imatch $pattern) { $count++; break }
            }
        }
    }
    return $count
}

function _ScoreToMaturityLevel {
    param([int]$Score, [pscustomobject]$MaturityThresholds)
    if ($null -eq $MaturityThresholds) { return 'L1-Informal' }
    foreach ($propName in @('L4-Orchestration-Ready','L3-Contract-Ready','L2-Structured','L1-Informal','L0-Absent')) {
        $threshold = $MaturityThresholds.$propName
        if ($null -eq $threshold) { continue }
        $minScore = [int]$threshold.minScore
        $maxScore = [int]$threshold.maxScore
        if ($Score -ge $minScore -and $Score -le $maxScore) {
            return $propName
        }
    }
    return 'L1-Informal'
}

# ---------------------------------------------------------------------------
# Invoke-NormalizeRoadmapContract
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Normalize a parsed roadmap result into the stable RoadmapContract model.
.PARAMETER ParsedResult
    Output of Invoke-ParseRoadmapContent.
.PARAMETER RawContent
    The raw markdown text of the roadmap file (used for structural detection).
.PARAMETER RepoName
    Short repository name.
.PARAMETER RepoPath
    Optional absolute path to the repository root.
.PARAMETER RoadmapPath
    Optional absolute path to the ROADMAP.md file.
.PARAMETER AuditRules
    Optional loaded roadmap-audit-rules.json. Supplies the "detection" block so
    this module and tools/Test-RoadmapContract.ps1 read one set of patterns.
    Omit it and the canonical defaults in $script:RoadmapDetectionDefaults apply.
.OUTPUTS
    [pscustomobject] matching roadmap-contract.schema.json (schemaVersion "1.0").
    maturityLevel and maturityScore are set to defaults (L0-Absent / 0) until
    Invoke-AuditRoadmapContract fills them in.
#>
function Invoke-NormalizeRoadmapContract {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [pscustomobject]$ParsedResult,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RawContent = '',

        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RepoPath = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [AllowNull()]
        [pscustomobject]$AuditRules = $null
    )

    $detection = Get-RoadmapDetectionProfile -AuditRules $AuditRules
    $parsedAt = (Get-Date).ToUniversalTime().ToString('o')

    # Missing roadmap — no parsed result
    if ($null -eq $ParsedResult) {
        return [pscustomobject]@{
            schemaVersion        = '1.0'
            repoName             = $RepoName
            repoPath             = if ([string]::IsNullOrWhiteSpace($RepoPath)) { $null } else { $RepoPath }
            roadmapPath          = if ([string]::IsNullOrWhiteSpace($RoadmapPath)) { $null } else { $RoadmapPath }
            roadmapState         = 'missing'
            maturityLevel        = 'L0-Absent'
            maturityScore        = 0
            pendingCount         = 0
            completedCount       = 0
            totalCount           = 0
            nextPendingItem      = $null
            sections             = @()
            hasProductIntent     = $false
            hasReleaseSections   = $false
            hasAcceptanceCriteria = $false
            hasOutOfScope        = $false
            releaseCount         = 0
            activeReleaseCount   = 0
            vagueItemCount       = 0
            parseError           = 'No roadmap file found.'
            auditFindings        = $null
            parsedAt             = $parsedAt
        }
    }

    $content = if ([string]::IsNullOrWhiteSpace($RawContent)) { '' } else { $RawContent }
    $releaseBlocks = @(_GetReleaseBlocks -Content $content -Detection $detection)

    # ROADMAP-006 / ROADMAP-007 are release-scoped by contract: a heading found
    # elsewhere in the document does not satisfy either rule.
    $scoped = @($detection.releaseScopedSignals)
    $hasAcceptance = if ($scoped -contains 'hasAcceptanceCriteria') {
        _TestReleaseScopedSubsection -ReleaseBlocks $releaseBlocks -Aliases @($detection.acceptanceCriteriaHeadingAliases) -Detection $detection
    } else {
        _TestDocumentScopedSubsection -Content $content -Aliases @($detection.acceptanceCriteriaHeadingAliases) -Detection $detection
    }
    $hasOutOfScope = if ($scoped -contains 'hasOutOfScope') {
        _TestReleaseScopedSubsection -ReleaseBlocks $releaseBlocks -Aliases @($detection.outOfScopeHeadingAliases) -Detection $detection
    } else {
        _TestDocumentScopedSubsection -Content $content -Aliases @($detection.outOfScopeHeadingAliases) -Detection $detection
    }

    return [pscustomobject]@{
        schemaVersion         = '1.0'
        repoName              = $RepoName
        repoPath              = if ([string]::IsNullOrWhiteSpace($RepoPath)) { $null } else { $RepoPath }
        roadmapPath           = if ([string]::IsNullOrWhiteSpace($RoadmapPath)) { $null } else { $RoadmapPath }
        roadmapState          = [string]$ParsedResult.roadmapState
        maturityLevel         = 'L0-Absent'   # filled by Invoke-AuditRoadmapContract
        maturityScore         = 0             # filled by Invoke-AuditRoadmapContract
        pendingCount          = [int]$ParsedResult.pendingCount
        completedCount        = [int]$ParsedResult.completedCount
        totalCount            = [int]$ParsedResult.totalCount
        nextPendingItem       = $ParsedResult.nextPendingItem
        sections              = @($ParsedResult.sections)
        hasProductIntent      = (_DetectProductIntent -Content $content -Detection $detection)
        hasReleaseSections    = ($releaseBlocks.Count -gt 0)
        hasAcceptanceCriteria = $hasAcceptance
        hasOutOfScope         = $hasOutOfScope
        releaseCount          = [int]$releaseBlocks.Count
        activeReleaseCount    = (_DetectActiveReleaseCount -ReleaseBlocks $releaseBlocks -Detection $detection)
        vagueItemCount        = 0  # filled below
        parseError            = $ParsedResult.parseError
        auditFindings         = $null
        parsedAt              = $parsedAt
    }
}

# ---------------------------------------------------------------------------
# Invoke-AuditRoadmapContract
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Apply the weighted roadmap audit rule pack to a normalized contract.
.PARAMETER Contract
    Output of Invoke-NormalizeRoadmapContract.
.PARAMETER AuditRules
    Output of Get-RoadmapStandard (pscustomobject with .rules and .maturityThresholds).
    If $null the function returns the contract unchanged with maturityLevel=L0-Absent.
.OUTPUTS
    The same [pscustomobject] contract, with maturityLevel, maturityScore, and
    auditFindings populated in place, and the object returned for chaining.
#>
function Invoke-AuditRoadmapContract {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Contract,

        [Parameter()]
        [AllowNull()]
        [pscustomobject]$AuditRules
    )

    if ($null -eq $AuditRules) {
        # No rules available — leave defaults
        return $Contract
    }

    $rules      = @($AuditRules.rules)
    $thresholds = $AuditRules.maturityThresholds

    # Compute vagueItemCount from vague patterns in ROADMAP-010
    $vagueRule = $rules | Where-Object { $_.id -eq 'ROADMAP-010' } | Select-Object -First 1
    if ($null -ne $vagueRule -and $vagueRule.vaguePatterns) {
        $Contract.vagueItemCount = _CountVagueItems -ParsedSections $Contract.sections -VaguePatterns @($vagueRule.vaguePatterns)
    }

    # Total maximum score = sum of all rule weights
    $maxPossibleScore = ($rules | Measure-Object -Property scoreWeight -Sum).Sum
    if ($maxPossibleScore -le 0) { $maxPossibleScore = 100 }

    $totalPenalty = 0
    $findings     = [System.Collections.Generic.List[pscustomobject]]::new()
    $hasActiveCount = ($Contract.PSObject.Properties.Name -contains 'activeReleaseCount')

    foreach ($rule in $rules) {
        $ruleId     = [string]$rule.id
        $weight     = [int]$rule.scoreWeight
        $severity   = [string]$rule.severity
        $message    = [string]$rule.message
        $recommended = if ($rule.PSObject.Properties.Name -contains 'recommendedAction') { [string]$rule.recommendedAction } else { $null }

        # Evaluate fail condition against the contract values
        $failed = $false
        switch ($ruleId) {
            'ROADMAP-001' { $failed = ($Contract.roadmapState -eq 'missing') }
            'ROADMAP-002' { $failed = ($Contract.roadmapState -in @('no-checklist', 'parse-error')) }
            'ROADMAP-003' { $failed = ($Contract.roadmapState -eq 'complete') }
            'ROADMAP-004' { $failed = (-not $Contract.hasProductIntent) }
            'ROADMAP-005' { $failed = (-not $Contract.hasReleaseSections) }
            'ROADMAP-006' { $failed = (-not $Contract.hasAcceptanceCriteria) }
            'ROADMAP-007' { $failed = (-not $Contract.hasOutOfScope) }
            'ROADMAP-008' { $failed = ($Contract.pendingCount -lt 3 -and $Contract.roadmapState -eq 'pending') }
            'ROADMAP-009' { $failed = ($null -ne $Contract.releaseCount -and [int]$Contract.releaseCount -lt 2) }
            'ROADMAP-010' { $failed = ([int]$Contract.vagueItemCount -gt 0) }
            # activeReleaseCount is read defensively: a contract deserialized from
            # a pre-1.1 cache will not carry the property, and StrictMode makes a
            # bare property access on it throw.
            'ROADMAP-011' { $failed = ($hasActiveCount -and [int]$Contract.activeReleaseCount -gt 1) }
            'ROADMAP-012' { $failed = ($hasActiveCount -and [int]$Contract.releaseCount -gt 0 -and [int]$Contract.activeReleaseCount -eq 0) }
            default       { $failed = $false }  # unknown rule — do not penalise
        }

        if ($failed) {
            $totalPenalty += $weight
            $findings.Add([pscustomobject]@{
                ruleId          = $ruleId
                severity        = $severity
                message         = $message
                recommendedAction = $recommended
                scoreImpact     = $weight
            })
        }
    }

    # Score = max possible - penalties, clamped 0..100, normalised to 0-100 scale
    $rawScore = $maxPossibleScore - $totalPenalty
    if ($rawScore -lt 0) { $rawScore = 0 }
    $normalised = [int][math]::Round(($rawScore / $maxPossibleScore) * 100)
    if ($normalised -lt 0) { $normalised = 0 }
    if ($normalised -gt 100) { $normalised = 100 }

    # L0-Absent if roadmap is missing regardless of score
    if ($Contract.roadmapState -eq 'missing') { $normalised = 0 }

    # Maturity caps, per ROADMAP_MATURITY_MODEL.md. Caps compose: the effective
    # ceiling is the lowest one that applies. Capping the SCORE (not just the
    # label) keeps score and level consistent for every downstream consumer.
    #
    # Two of these were documented from the start but never implemented — the
    # auditor did weighted-score arithmetic only, so a roadmap could carry a
    # critical finding and still be scored orchestration-ready.
    $capMax = [int]$normalised
    $levelMax = {
        param([string]$LevelName, [int]$Fallback)
        if ($null -ne $thresholds -and $null -ne $thresholds.$LevelName) {
            return [int]$thresholds.$LevelName.maxScore
        }
        return $Fallback
    }

    $findingSeverities = @($findings | ForEach-Object { [string]$_.severity })

    # Any critical finding caps at L1. Nothing carrying a critical defect is
    # structured, let alone contract-ready.
    if ($findingSeverities -contains 'critical') {
        $capMax = [math]::Min($capMax, [int](& $levelMax 'L1-Informal' 39))
    }

    # Any warning finding caps at L3, because L4 requires no critical or
    # warning findings at all.
    if ($findingSeverities -contains 'warning') {
        $capMax = [math]::Min($capMax, [int](& $levelMax 'L3-Contract-Ready' 84))
    }

    # More than one active release caps at L2 — an ambiguous dispatch target is
    # treated the same as missing structure, because neither an agent nor an
    # operator can safely pick a target on its own. This named cap is why
    # ROADMAP-011 is a WARNING and not a critical (rules v1.5): as a critical it
    # would take the L1 cap above and make this documented L2 cap unreachable.
    if ($hasActiveCount -and [int]$Contract.activeReleaseCount -gt 1) {
        $capMax = [math]::Min($capMax, [int](& $levelMax 'L2-Structured' 64))
    }

    if ($normalised -gt $capMax) { $normalised = $capMax }
    if ($normalised -lt 0) { $normalised = 0 }

    $Contract.maturityScore   = $normalised
    $Contract.maturityLevel   = _ScoreToMaturityLevel -Score $normalised -MaturityThresholds $thresholds
    $Contract.auditFindings   = if ($findings.Count -gt 0) { @($findings) } else { @() }

    return $Contract
}

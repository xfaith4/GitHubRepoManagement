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
# Internal helpers
# ---------------------------------------------------------------------------

function _DetectProductIntent {
    param([string]$Content)
    # Recognise headings that signal product intent (case-insensitive)
    return ($Content -imatch '(^|\n)#+\s*(product\s+intent|product\s+scope|overview|about|purpose|background|what\s+this\s+(does|is))')
}

function _DetectReleaseSections {
    param([string]$Content, [ref]$ReleaseCountOut)
    $matches = [regex]::Matches($Content, '(?im)^#{1,3}\s+release\s+\d+[\.\d]*')
    $count = $matches.Count
    $ReleaseCountOut.Value = $count
    return ($count -gt 0)
}

# Count release blocks whose declared status normalizes to 'active'. The
# canonical form in ROADMAP_TEMPLATE.md is a blockquote — "> Status: active" —
# so a leading '>' must be tolerated; "**Status:** active", "Status: In
# Progress", and "**Status: active**" are also accepted. Matching is
# case-insensitive and alias-normalized so legacy wording scores the same as
# the canonical wording.
function _DetectActiveReleaseCount {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return 0 }

    $aliases = @{
        'active'      = 'active'
        'in progress' = 'active'
        'in-progress' = 'active'
        'inprogress'  = 'active'
        'wip'         = 'active'
    }

    $headings = [regex]::Matches($Content, '(?im)^#{1,3}\s+release\s+\d+[\.\d]*')
    if ($headings.Count -eq 0) { return 0 }

    $activeCount = 0
    for ($i = 0; $i -lt $headings.Count; $i++) {
        $start = $headings[$i].Index
        $end = if ($i + 1 -lt $headings.Count) { $headings[$i + 1].Index } else { $Content.Length }
        $block = $Content.Substring($start, $end - $start)

        $m = [regex]::Match($block, '(?im)^\s*>?\s*\**\s*Status\s*:?\**\s*:?\s*\**\s*([A-Za-z][A-Za-z \-]*?)\s*\**\s*(?:$|[—–\-\(])')
        if (-not $m.Success) { continue }

        $raw = $m.Groups[1].Value.Trim().ToLowerInvariant()
        if ($aliases.ContainsKey($raw)) { $activeCount++ }
    }

    return $activeCount
}

function _DetectAcceptanceCriteria {
    param([string]$Content)
    return ($Content -imatch '(^|\n)#+\s*(acceptance\s+criteria|done\s+criteria|definition\s+of\s+done)')
}

function _DetectOutOfScope {
    param([string]$Content)
    return ($Content -imatch '(^|\n)#+\s*(out\s+of\s+scope|not\s+in\s+scope|excluded|exclusions)')
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
        [string]$RoadmapPath = ''
    )

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
    $releaseCountRef = [ref]0
    $hasRelease = _DetectReleaseSections -Content $content -ReleaseCountOut $releaseCountRef

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
        hasProductIntent      = (_DetectProductIntent -Content $content)
        hasReleaseSections    = $hasRelease
        hasAcceptanceCriteria = (_DetectAcceptanceCriteria -Content $content)
        hasOutOfScope         = (_DetectOutOfScope -Content $content)
        releaseCount          = [int]$releaseCountRef.Value
        activeReleaseCount    = (_DetectActiveReleaseCount -Content $content)
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
        $condStr    = [string]$rule.failCondition

        # Evaluate fail condition against the contract values
        $failed = $false
        switch ($ruleId) {
            'ROADMAP-001' { $failed = ($Contract.roadmapState -eq 'missing') }
            'ROADMAP-002' { $failed = ($Contract.roadmapState -eq 'parse-error') }
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

    # Maturity cap: more than one active release caps the roadmap at L2, per
    # ROADMAP_MATURITY_MODEL.md. An ambiguous dispatch target is treated the
    # same as missing structure, because neither an agent nor an operator can
    # safely pick a target on its own. Capping the score (not just the label)
    # keeps score and level consistent for every downstream consumer.
    if ($hasActiveCount -and [int]$Contract.activeReleaseCount -gt 1) {
        $l2Max = 64
        if ($null -ne $thresholds -and $null -ne $thresholds.'L2-Structured') {
            $l2Max = [int]$thresholds.'L2-Structured'.maxScore
        }
        if ($normalised -gt $l2Max) { $normalised = $l2Max }
    }

    $Contract.maturityScore   = $normalised
    $Contract.maturityLevel   = _ScoreToMaturityLevel -Score $normalised -MaturityThresholds $thresholds
    $Contract.auditFindings   = if ($findings.Count -gt 0) { @($findings) } else { @() }

    return $Contract
}

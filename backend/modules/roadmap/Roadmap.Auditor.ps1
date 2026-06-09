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

    $Contract.maturityScore   = $normalised
    $Contract.maturityLevel   = _ScoreToMaturityLevel -Score $normalised -MaturityThresholds $thresholds
    $Contract.auditFindings   = if ($findings.Count -gt 0) { @($findings) } else { @() }

    return $Contract
}

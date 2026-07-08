<#
.SYNOPSIS
    Structured roadmap parser for ROADMAP.md files.
.DESCRIPTION
    Parses markdown roadmap content to extract checkbox task items, group them by
    section, classify roadmap state, and surface the next actionable pending item.

    Exported functions:
      Invoke-ParseRoadmapContent
      Get-RoadmapReleaseContexts
      Get-RoadmapSelectedReleaseContext

    Roadmap states returned:
      pending     — one or more unchecked items found
      complete    — checkboxes present but none are unchecked
      parse-error — content is empty, null, or contains no checkbox items

.NOTES
    Dot-source this file to load the public functions into the caller scope:
        . (Join-Path $moduleRoot 'Roadmap.Parser.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RoadmapParserMaxLines = 5000

function _RoadmapParserGetBoundedLines {
    param([string]$Content)

    $lines = $Content -split '\r?\n'
    if ($lines.Count -gt $script:RoadmapParserMaxLines) {
        return @($lines[0..($script:RoadmapParserMaxLines - 1)])
    }

    return @($lines)
}

function _RoadmapParserNormalizeTaskKey {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $normalized = [string]$Text
    try {
        $normalized = $normalized.Normalize([Text.NormalizationForm]::FormKC)
    } catch {
        # Fall back to the original value when Unicode normalization is unavailable.
    }

    $normalized = $normalized `
        -replace '[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]', '-' `
        -replace '\s+', ' '

    return $normalized.Trim().ToLowerInvariant()
}

function _RoadmapParserGetItemTagsAndText {
    param([string]$Raw)

    $tags = @([regex]::Matches($Raw, '\[([a-zA-Z0-9_-]+)\]') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
    $cleaned = ([regex]::Replace($Raw, '\s*\[[a-zA-Z0-9_-]+\]', '')).Trim()

    return @{
        text = $cleaned
        tags = $tags
    }
}

function _RoadmapParserExtractSubsectionLines {
    param(
        [string[]]$Lines,
        [string]$HeadingPattern
    )

    $results = [System.Collections.Generic.List[string]]::new()
    $inSection = $false

    foreach ($line in @($Lines)) {
        if ($line -match "^\s*###\s+$HeadingPattern") {
            $inSection = $true
            continue
        }

        if (-not $inSection) {
            continue
        }

        if ($line -match '^\s*###\s+' -or $line -match '^\s*##\s+') {
            break
        }

        if ($line -match '^\s*-\s+(.+)$') {
            $text = $matches[1].Trim()
            $text = $text -replace '^\[[ xX]\]\s+', ''
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $results.Add($text) | Out-Null
            }
        }
    }

    return @($results)
}

function _RoadmapParserExtractGoal {
    param([string[]]$Lines)

    foreach ($line in @($Lines)) {
        if ($line -match '\*\*Goal:\*\*\s*(.+)') {
            return $matches[1].Trim()
        }
    }

    return ''
}

function _RoadmapParserConvertTableLineToCells {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return @()
    }

    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith('|')) {
        return @()
    }

    $trimmed = $trimmed.Trim('|')
    return @(
        ($trimmed -split '\|') |
            ForEach-Object { ([string]$_).Trim() }
    )
}

function _RoadmapParserIsPlaceholderText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $trimmed = $Value.Trim()
    return $trimmed -in @('-', '–', '—')
}

function _RoadmapParserParseWorkUnitsCell {
    param([string]$CellText)

    $raw = [string]$CellText
    if (_RoadmapParserIsPlaceholderText -Value $raw) {
        return [pscustomobject]@{
            raw       = $raw
            estimated = $null
            actual    = $null
        }
    }

    $normalized = $raw.Trim()
    $normalized = $normalized -replace '\s*[→⇒]+\s*', ' -> '
    $normalized = $normalized -replace '\s*=>\s*', ' -> '
    $normalized = $normalized -replace '\s+', ' '

    $estimated = $null
    $actual = $null

    $pairMatch = [regex]::Match($normalized, '(?i)(\d+(?:\.\d+)?)\s*->\s*(\d+(?:\.\d+)?)')
    if ($pairMatch.Success) {
        $estimated = [double]$pairMatch.Groups[1].Value
        $actual = [double]$pairMatch.Groups[2].Value
    } else {
        $singleMatch = [regex]::Match($normalized, '(?i)(?:est(?:\.|imated)?\s*)?(\d+(?:\.\d+)?)')
        if ($singleMatch.Success) {
            $estimated = [double]$singleMatch.Groups[1].Value
        }
    }

    return [pscustomobject]@{
        raw       = $raw
        estimated = $estimated
        actual    = $actual
    }
}

function _RoadmapParserGetPhasePlanFromLines {
    param([string[]]$Lines)

    $headingIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        # Heading-level tolerant: real roadmaps nest releases under a section, so
        # the phase-plan heading appears at ### or deeper (#### is common). Match
        # any depth >= 3 rather than exactly ###.
        if ($Lines[$i] -match '^\s*#{3,}\s+Phase\s+plan\b') {
            $headingIndex = $i
            break
        }
    }

    if ($headingIndex -lt 0) {
        return @()
    }

    $tableLines = [System.Collections.Generic.List[string]]::new()
    for ($i = $headingIndex + 1; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        $trimmed = $line.TrimEnd()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if ($tableLines.Count -gt 0) { break }
            continue
        }

        if ($trimmed -match '^\s*##\s+' -or $trimmed -match '^\s*###\s+') {
            break
        }

        if ($trimmed -notmatch '^\s*\|') {
            if ($tableLines.Count -gt 0) { break }
            continue
        }

        $tableLines.Add($trimmed) | Out-Null
    }

    if ($tableLines.Count -lt 3) {
        return @()
    }

    $headers = @(_RoadmapParserConvertTableLineToCells -Line $tableLines[0])
    if ($headers.Count -eq 0) {
        return @()
    }

    $separator = [string]$tableLines[1]
    if ($separator -notmatch '^\s*\|[\s:\-|]+\|\s*$') {
        return @()
    }

    $normalizedHeaders = @(
        $headers | ForEach-Object {
            ([string]$_).Trim().ToLowerInvariant() -replace '\s+', ' '
        }
    )

    $phaseIndex = [array]::IndexOf($normalizedHeaders, ($normalizedHeaders | Where-Object { $_ -match '^phase\b' } | Select-Object -First 1))
    $scopeIndex = [array]::IndexOf($normalizedHeaders, ($normalizedHeaders | Where-Object { $_ -match '^scope\b' } | Select-Object -First 1))
    $statusIndex = [array]::IndexOf($normalizedHeaders, ($normalizedHeaders | Where-Object { $_ -match '^status\b' } | Select-Object -First 1))
    $completedIndex = [array]::IndexOf($normalizedHeaders, ($normalizedHeaders | Where-Object { $_ -match '^completed\b' } | Select-Object -First 1))
    $tokenUsageIndex = [array]::IndexOf($normalizedHeaders, ($normalizedHeaders | Where-Object { $_ -match '^token usage\b' } | Select-Object -First 1))
    $workUnitsIndex = [array]::IndexOf($normalizedHeaders, ($normalizedHeaders | Where-Object { $_ -match '^work units\b' } | Select-Object -First 1))

    if ($phaseIndex -lt 0 -or $scopeIndex -lt 0 -or $statusIndex -lt 0) {
        return @()
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($rowLine in @($tableLines | Select-Object -Skip 2)) {
        $cells = @(_RoadmapParserConvertTableLineToCells -Line $rowLine)
        if ($cells.Count -eq 0) {
            continue
        }

        while ($cells.Count -lt $headers.Count) {
            $cells += ''
        }

        $phaseName = [string]$cells[$phaseIndex]
        $scope = [string]$cells[$scopeIndex]
        $status = [string]$cells[$statusIndex]
        if ([string]::IsNullOrWhiteSpace($phaseName) -and [string]::IsNullOrWhiteSpace($scope) -and [string]::IsNullOrWhiteSpace($status)) {
            continue
        }

        $completed = if ($completedIndex -ge 0 -and $completedIndex -lt $cells.Count) { [string]$cells[$completedIndex] } else { '' }
        $tokenUsage = if ($tokenUsageIndex -ge 0 -and $tokenUsageIndex -lt $cells.Count) { [string]$cells[$tokenUsageIndex] } else { '' }
        $rawWorkUnits = if ($workUnitsIndex -ge 0 -and $workUnitsIndex -lt $cells.Count) { [string]$cells[$workUnitsIndex] } else { '' }
        $workUnits = _RoadmapParserParseWorkUnitsCell -CellText $rawWorkUnits

        $statusNormalized = $status.ToLowerInvariant()
        $completedNormalized = $completed.Trim()
        $isComplete = ($statusNormalized -match '\bdone\b' -or $statusNormalized -match '\bcomplete\b')
        if (-not $isComplete -and -not (_RoadmapParserIsPlaceholderText -Value $completedNormalized)) {
            $isComplete = $true
        }

        $rows.Add([pscustomobject]@{
            phaseName          = $phaseName
            scope              = $scope
            status             = $status
            completed          = if (_RoadmapParserIsPlaceholderText -Value $completedNormalized) { $null } else { $completedNormalized }
            tokenUsage         = if (_RoadmapParserIsPlaceholderText -Value $tokenUsage) { $null } else { $tokenUsage.Trim() }
            rawWorkUnits       = if (_RoadmapParserIsPlaceholderText -Value $rawWorkUnits) { $null } else { $rawWorkUnits.Trim() }
            workUnitsEstimated = $workUnits.estimated
            workUnitsActual    = $workUnits.actual
            isComplete         = [bool]$isComplete
        }) | Out-Null
    }

    return @($rows)
}

function _RoadmapParserGetBudgetGuardrailFromLines {
    param([string[]]$Lines)

    $headingIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*###\s+Budget\s+guardrail\b') {
            $headingIndex = $i
            break
        }
    }

    if ($headingIndex -lt 0) {
        return $null
    }

    $sectionLines = [System.Collections.Generic.List[string]]::new()
    for ($i = $headingIndex + 1; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if ($line -match '^\s*##\s+' -or $line -match '^\s*###\s+') {
            break
        }
        $sectionLines.Add($line) | Out-Null
    }

    $estimatedReleaseUnits = $null
    $maxUnitsPerPhase = $null
    foreach ($line in @($sectionLines)) {
        $match = [regex]::Match($line, '(?i)Estimated AI work units for this release:\s*(\d+(?:\.\d+)?)\s*[·•|-]\s*Max per phase:\s*(\d+(?:\.\d+)?)')
        if ($match.Success) {
            $estimatedReleaseUnits = [double]$match.Groups[1].Value
            $maxUnitsPerPhase = [double]$match.Groups[2].Value
            break
        }
    }

    return [pscustomobject]@{
        present                    = $true
        estimatedReleaseWorkUnits  = $estimatedReleaseUnits
        maxUnitsPerPhase           = $maxUnitsPerPhase
        beforeDispatchRulePresent  = (@($sectionLines | Where-Object { $_ -match '(?i)Before dispatch:' }).Count -gt 0)
        phaseClosureRulePresent    = (@($sectionLines | Where-Object { $_ -match '(?i)At each phase closure' }).Count -gt 0)
    }
}

function Get-RoadmapReleaseContexts {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RoadmapContent
    )

    if ([string]::IsNullOrWhiteSpace($RoadmapContent)) {
        return @()
    }

    $boundedContent = (_RoadmapParserGetBoundedLines -Content $RoadmapContent) -join "`n"
    # Heading-level tolerant: releases are often nested under a section heading
    # (e.g. "## 6. Future Releases"), so the release heading is ### or deeper.
    # Match any depth >= 2. The mandatory " — Title" dash separator still keeps
    # "### Release 2.0 completion snapshot" (no dash) from being treated as a block.
    $releaseHeadingRx = [regex]'(?im)^#{2,}\s+Release (\d+[\d\.]*)\s*[—–-]+\s*(.+?)$'
    $headingMatches = $releaseHeadingRx.Matches($boundedContent)
    if ($headingMatches.Count -eq 0) {
        return @()
    }

    $blocks = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($m in $headingMatches) {
        $blocks.Add(@{
            version    = $m.Groups[1].Value.Trim()
            title      = $m.Groups[2].Value.Trim()
            startIndex = $m.Index
        }) | Out-Null
    }

    $contexts = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        $block = $blocks[$i]
        $blockStart = $block.startIndex
        $blockEnd = if ($i + 1 -lt $blocks.Count) { $blocks[$i + 1].startIndex } else { $boundedContent.Length }
        $blockText = $boundedContent.Substring($blockStart, $blockEnd - $blockStart)
        $blockLines = @(_RoadmapParserGetBoundedLines -Content $blockText)

        $pendingMilestones = [System.Collections.Generic.List[string]]::new()
        $completedMilestones = [System.Collections.Generic.List[string]]::new()

        foreach ($line in @($blockLines)) {
            if ($line -match '^\s*-\s*\[\s\]\s+(.+)$') {
                $itemText = [string](_RoadmapParserGetItemTagsAndText -Raw $matches[1].Trim()).text
                if (-not [string]::IsNullOrWhiteSpace($itemText)) {
                    $pendingMilestones.Add($itemText) | Out-Null
                }
                continue
            }

            if ($line -match '^\s*-\s*\[[xX]\]\s+(.+)$') {
                $itemText = [string](_RoadmapParserGetItemTagsAndText -Raw $matches[1].Trim()).text
                if (-not [string]::IsNullOrWhiteSpace($itemText)) {
                    $completedMilestones.Add($itemText) | Out-Null
                }
            }
        }

        $phasePlan = @(_RoadmapParserGetPhasePlanFromLines -Lines $blockLines)
        $activePhasePlan = @($phasePlan | Where-Object { -not $_.isComplete } | Select-Object -First 1)
        if ($activePhasePlan.Count -gt 0) {
            $activePhasePlan = $activePhasePlan[0]
        } else {
            $activePhasePlan = $null
        }

        $budgetGuardrail = _RoadmapParserGetBudgetGuardrailFromLines -Lines $blockLines
        $contexts.Add([pscustomobject]@{
            releaseName               = "Release $($block.version) — $($block.title)"
            releaseVersion            = $block.version
            releaseTitle              = $block.title
            releaseGoal               = (_RoadmapParserExtractGoal -Lines $blockLines)
            pendingMilestones         = @($pendingMilestones)
            completedMilestones       = @($completedMilestones)
            acceptanceCriteria        = @(_RoadmapParserExtractSubsectionLines -Lines $blockLines -HeadingPattern 'Acceptance\s+criteria')
            outOfScope                = @(_RoadmapParserExtractSubsectionLines -Lines $blockLines -HeadingPattern 'Out\s+of\s+scope')
            phasePlan                 = @($phasePlan)
            activePhasePlan           = $activePhasePlan
            budgetGuardrail           = $budgetGuardrail
            estimatedSessionWorkUnits = if ($null -ne $activePhasePlan) { $activePhasePlan.workUnitsEstimated } else { $null }
            pendingCount              = @($pendingMilestones).Count
            completedCount            = @($completedMilestones).Count
        }) | Out-Null
    }

    return @($contexts)
}

function Get-RoadmapSelectedReleaseContext {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RoadmapContent,

        [Parameter()]
        [string]$SelectedTask = ''
    )

    $empty = [pscustomobject]@{
        releaseName               = $null
        releaseVersion            = $null
        releaseTitle              = $null
        releaseGoal               = ''
        pendingMilestones         = @()
        completedMilestones       = @()
        acceptanceCriteria        = @()
        outOfScope                = @()
        phasePlan                 = @()
        activePhasePlan           = $null
        budgetGuardrail           = $null
        estimatedSessionWorkUnits = $null
        pendingCount              = 0
        completedCount            = 0
    }

    $releaseContexts = @(Get-RoadmapReleaseContexts -RoadmapContent $RoadmapContent)
    if ($releaseContexts.Count -eq 0) {
        return $empty
    }

    $selectedKey = _RoadmapParserNormalizeTaskKey -Text $SelectedTask
    if (-not [string]::IsNullOrWhiteSpace($selectedKey)) {
        foreach ($ctx in @($releaseContexts)) {
            $allMilestones = @($ctx.pendingMilestones) + @($ctx.completedMilestones)
            foreach ($milestone in @($allMilestones)) {
                if ((_RoadmapParserNormalizeTaskKey -Text ([string]$milestone)) -eq $selectedKey) {
                    return $ctx
                }
            }
        }
    }

    $firstPending = @($releaseContexts | Where-Object { [int]$_.pendingCount -gt 0 } | Select-Object -First 1)
    if ($firstPending.Count -gt 0) {
        return $firstPending[0]
    }

    return $empty
}

<#
.SYNOPSIS
    Parse markdown roadmap content and return a normalized state object.
.PARAMETER Content
    Raw text content of a ROADMAP.md file.
.PARAMETER SourcePath
    Optional file path for diagnostic messages.
.OUTPUTS
    [pscustomobject] with:
      roadmapState      string   pending | complete | parse-error
      pendingCount      int
      completedCount    int
      totalCount        int
      nextPendingItem   pscustomobject { text, section, tags } or $null
      sections          array of { name, pendingItems[], completedItems[] }
      allTags           string[]  unique tags found across all items
      releaseContexts   array of parsed release-context blocks
      activeRelease     parsed release context for the next actionable release
      activePhasePlan   parsed phase-plan row for the active release, if present
      budgetGuardrail   parsed budget-guardrail metadata for the active release, if present
      parseError        string or $null

    Tags are bracketed tokens in item text, e.g. `[security]`, `[infra]`, `[breaking]`.
    They are stripped from the display text stored in pendingItems/completedItems.
#>
function Invoke-ParseRoadmapContent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter()]
        [string]$SourcePath = ''
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [pscustomobject]@{
            roadmapState    = 'parse-error'
            pendingCount    = 0
            completedCount  = 0
            totalCount      = 0
            nextPendingItem = $null
            sections        = @()
            allTags         = @()
            releaseContexts = @()
            activeRelease   = $null
            activePhasePlan = $null
            budgetGuardrail = $null
            parseError      = 'Roadmap content is empty.'
        }
    }

    $lines = @(_RoadmapParserGetBoundedLines -Content $Content)
    $currentSection  = 'General'
    $sections        = [System.Collections.Generic.List[pscustomobject]]::new()
    $sectionMap      = @{}
    $allTagsSet      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $pendingCount    = 0
    $completedCount  = 0
    $nextPendingItem = $null

    foreach ($line in @($lines)) {
        if ($line -match '^#{1,6}\s+(.+)$') {
            $currentSection = $Matches[1].Trim()
            if (-not $sectionMap.ContainsKey($currentSection)) {
                $sec = [pscustomobject]@{
                    name           = $currentSection
                    pendingItems   = [System.Collections.Generic.List[string]]::new()
                    completedItems = [System.Collections.Generic.List[string]]::new()
                }
                $sections.Add($sec) | Out-Null
                $sectionMap[$currentSection] = $sections.Count - 1
            }
            continue
        }

        if (-not $sectionMap.ContainsKey($currentSection)) {
            $sec = [pscustomobject]@{
                name           = $currentSection
                pendingItems   = [System.Collections.Generic.List[string]]::new()
                completedItems = [System.Collections.Generic.List[string]]::new()
            }
            $sections.Add($sec) | Out-Null
            $sectionMap[$currentSection] = $sections.Count - 1
        }

        $sec = $sections[$sectionMap[$currentSection]]

        if ($line -match '^\s*-\s+\[\s\]\s+(.+)$') {
            $parsed   = _RoadmapParserGetItemTagsAndText -Raw $Matches[1].Trim()
            $itemText = [string]$parsed.text
            $itemTags = @($parsed.tags)
            foreach ($t in @($itemTags)) { $null = $allTagsSet.Add($t) }
            $sec.pendingItems.Add($itemText) | Out-Null
            $pendingCount++
            if ($null -eq $nextPendingItem) {
                $nextPendingItem = [pscustomobject]@{
                    text    = $itemText
                    section = $currentSection
                    tags    = $itemTags
                }
            }
            continue
        }

        if ($line -match '^\s*-\s+\[[xX]\]\s+(.+)$') {
            $parsed   = _RoadmapParserGetItemTagsAndText -Raw $Matches[1].Trim()
            $itemText = [string]$parsed.text
            $itemTags = @($parsed.tags)
            foreach ($t in @($itemTags)) { $null = $allTagsSet.Add($t) }
            $sec.completedItems.Add($itemText) | Out-Null
            $completedCount++
            continue
        }
    }

    $totalCount = $pendingCount + $completedCount
    if ($totalCount -eq 0) {
        $state    = 'parse-error'
        $errorMsg = if ([string]::IsNullOrWhiteSpace($SourcePath)) {
            'No checkbox items found in roadmap content.'
        } else {
            "No checkbox items found in roadmap file: $SourcePath"
        }
    } elseif ($pendingCount -gt 0) {
        $state    = 'pending'
        $errorMsg = $null
    } else {
        $state    = 'complete'
        $errorMsg = $null
    }

    $releaseContexts = @(Get-RoadmapReleaseContexts -RoadmapContent (($lines -join "`n")))
    $activeRelease = if ($null -ne $nextPendingItem) {
        Get-RoadmapSelectedReleaseContext -RoadmapContent (($lines -join "`n")) -SelectedTask ([string]$nextPendingItem.text)
    } else {
        Get-RoadmapSelectedReleaseContext -RoadmapContent (($lines -join "`n"))
    }

    if ($null -ne $activeRelease -and [string]::IsNullOrWhiteSpace([string]$activeRelease.releaseName)) {
        $activeRelease = $null
    }

    return [pscustomobject]@{
        roadmapState    = $state
        pendingCount    = $pendingCount
        completedCount  = $completedCount
        totalCount      = $totalCount
        nextPendingItem = $nextPendingItem
        sections        = @($sections)
        allTags         = @($allTagsSet | Sort-Object)
        releaseContexts = @($releaseContexts)
        activeRelease   = $activeRelease
        activePhasePlan = if ($null -ne $activeRelease) { $activeRelease.activePhasePlan } else { $null }
        budgetGuardrail = if ($null -ne $activeRelease) { $activeRelease.budgetGuardrail } else { $null }
        parseError      = $errorMsg
    }
}

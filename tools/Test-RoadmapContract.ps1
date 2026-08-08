<#
.SYNOPSIS
    Parses ROADMAP.md into a normalized roadmap contract, validates the contract
    shape, evaluates standards/roadmap/roadmap-audit-rules.json, and assigns a
    maturity level.

.DESCRIPTION
    This is the JSON-backed maturity validator. It is intentionally separate
    from Test-RoadmapStructure.ps1, which remains a CI hygiene linter.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Path = './ROADMAP.md',
    [Parameter()][string]$StandardsPath = './standards/roadmap',
    [Parameter()][string]$RulesPath = '',
    [Parameter()][string]$SchemaPath = '',
    [Parameter()][string]$ContractOut = '',
    [Parameter()][string]$JsonOut = '',
    [Parameter()][ValidateSet('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')]
    [string]$MinimumMaturity = 'L0-Absent',
    [Parameter()][switch]$FailOnError,
    [Parameter()][switch]$Quiet,
    [Parameter()][switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AuditFindings = [System.Collections.Generic.List[object]]::new()
$script:SchemaFindings = New-Object 'System.Collections.Generic.List[string]'

$script:LevelRank = @{
    'L0-Absent' = 0
    'L1-Informal' = 1
    'L2-Structured' = 2
    'L3-Contract-Ready' = 3
    'L4-Orchestration-Ready' = 4
}

# ---------------------------------------------------------------------------
# Shared detection contract
# ---------------------------------------------------------------------------
#
# Detection is DATA, not code. The canonical patterns live in
# standards/roadmap/roadmap-audit-rules.json under "detection", and both this
# tool and backend/modules/roadmap/Roadmap.Auditor.ps1 read them from there.
# The literals below are a mirror used only when the rule pack predates the
# block — keep them byte-identical to the JSON and to the module's copy.
#
# Before 2026-08-08 this tool carried its own release-heading regex,
# product-intent vocabulary, acceptance-criteria scope, and score arithmetic.
# No repository in the estate scored the same under both evaluators, and three
# straddled the L3 dispatch threshold depending on which one an operator ran.
# Do not reintroduce a private copy of any pattern here.

$script:Detection = [pscustomobject]@{
    releaseHeadingPattern            = '(?im)^#{2,}\s+Release\s+([0-9]+(?:\.[0-9]+)*)\s*[—–-]+\s*(.+?)\s*$'
    productIntentHeadingPattern      = '(?im)^#{1,6}\s*(?:[0-9]+\.\s*)?(?:product\s+intent|product\s+scope|overview|about|purpose|background|what\s+this\s+(?:does|is))\b'
    acceptanceCriteriaHeadingAliases = @('Acceptance criteria', 'Done criteria', 'Definition of done')
    outOfScopeHeadingAliases         = @('Out of scope', 'Out-of-scope', 'Not in scope', 'Non-goals', 'Non goals', 'Not included', 'Excluded', 'Exclusions')
    releaseScopedSignals             = @('hasAcceptanceCriteria', 'hasOutOfScope')
    meaningfulBodyMinimumCharacters  = 4
    meaningfulBodyPlaceholderPattern = '(?i)\b(tbd|todo|none yet|not yet|n/a)\b'
    scoringMode                      = 'normalized'
}

function Set-DetectionProfile {
    <#
    .SYNOPSIS
        Overlay the rule pack's "detection" block onto $script:Detection.
    #>
    param([Parameter(Mandatory=$true)]$Rules)

    if ($Rules.PSObject.Properties.Name -notcontains 'detection') { return }
    $d = $Rules.detection
    if ($null -eq $d) { return }
    $names = @($d.PSObject.Properties.Name)

    if ($names -contains 'releaseHeadingPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.releaseHeadingPattern)) {
        $script:Detection.releaseHeadingPattern = [string]$d.releaseHeadingPattern
    }
    if ($names -contains 'productIntentHeadingPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.productIntentHeadingPattern)) {
        $script:Detection.productIntentHeadingPattern = [string]$d.productIntentHeadingPattern
    }
    if ($names -contains 'acceptanceCriteriaHeadingAliases' -and @($d.acceptanceCriteriaHeadingAliases).Count -gt 0) {
        $script:Detection.acceptanceCriteriaHeadingAliases = @($d.acceptanceCriteriaHeadingAliases)
    }
    if ($names -contains 'outOfScopeHeadingAliases' -and @($d.outOfScopeHeadingAliases).Count -gt 0) {
        $script:Detection.outOfScopeHeadingAliases = @($d.outOfScopeHeadingAliases)
    }
    if ($names -contains 'releaseScopedSignals') {
        $script:Detection.releaseScopedSignals = @($d.releaseScopedSignals)
    }
    if ($names -contains 'meaningfulBody' -and $null -ne $d.meaningfulBody) {
        $mb = @($d.meaningfulBody.PSObject.Properties.Name)
        if ($mb -contains 'minimumCharacters') {
            $script:Detection.meaningfulBodyMinimumCharacters = [int]$d.meaningfulBody.minimumCharacters
        }
        if ($mb -contains 'placeholderPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.meaningfulBody.placeholderPattern)) {
            $script:Detection.meaningfulBodyPlaceholderPattern = [string]$d.meaningfulBody.placeholderPattern
        }
    }
    if ($names -contains 'scoring' -and $null -ne $d.scoring -and
        @($d.scoring.PSObject.Properties.Name) -contains 'mode' -and
        -not [string]::IsNullOrWhiteSpace([string]$d.scoring.mode)) {
        $script:Detection.scoringMode = [string]$d.scoring.mode
    }
}

function Resolve-StandardsFile {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ExplicitPath,
        [Parameter(Mandatory=$true)][string]$DefaultName
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return $ExplicitPath
    }

    return (Join-Path $StandardsPath $DefaultName)
}

function Get-RepoNameFromPath {
    param([Parameter(Mandatory=$true)][string]$RoadmapPath)

    try {
        $resolved = Resolve-Path -LiteralPath $RoadmapPath -ErrorAction Stop
        $parent = Split-Path -Parent $resolved.ProviderPath
        return (Split-Path -Leaf $parent)
    }
    catch {
        $parent = Split-Path -Parent $RoadmapPath
        if ([string]::IsNullOrWhiteSpace($parent)) { return 'unknown-repo' }
        return (Split-Path -Leaf $parent)
    }
}

function Normalize-Status {
    param(
        [Parameter()][AllowNull()][string]$Status,
        [Parameter(Mandatory=$true)]$Rules
    )

    if ([string]::IsNullOrWhiteSpace($Status)) { return $null }

    $value = $Status.Trim().ToLowerInvariant()
    $allowed = @('planned','active','blocked','validation','done','archived')
    $aliases = @{}

    if ($Rules.PSObject.Properties.Name -contains 'statusVocabulary') {
        if ($Rules.statusVocabulary.PSObject.Properties.Name -contains 'allowedStatuses') {
            $allowed = @($Rules.statusVocabulary.allowedStatuses)
        }
        if ($Rules.statusVocabulary.PSObject.Properties.Name -contains 'statusAliases') {
            foreach ($p in $Rules.statusVocabulary.statusAliases.PSObject.Properties) {
                $aliases[$p.Name.ToLowerInvariant()] = [string]$p.Value
            }
        }
    }

    if ($allowed -contains $value) { return $value }
    if ($aliases.ContainsKey($value)) { return $aliases[$value] }
    return $null
}

function Get-HeadingMatch {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Line)

    $m = [regex]::Match($Line, '^(#{1,6})\s+(.+?)\s*$')
    if (-not $m.Success) { return $null }

    return [pscustomobject]@{
        Level = $m.Groups[1].Value.Length
        Text = $m.Groups[2].Value.Trim()
    }
}

function Get-ReleaseHeadingMatch {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Line)

    $m = [regex]::Match($Line, $script:Detection.releaseHeadingPattern)
    if (-not $m.Success) { return $null }

    $hashes = [regex]::Match($Line, '^#+')
    return [pscustomobject]@{
        Id = $m.Groups[1].Value.Trim()
        Title = $m.Groups[2].Value.Trim()
        Level = if ($hashes.Success) { $hashes.Value.Length } else { 2 }
    }
}

function Get-SectionBodiesFromBlock {
    # Subsection headings are recognised RELATIVE to the release heading that
    # opened the block: '### Acceptance criteria' under '## Release 2.7', or
    # '#### Acceptance criteria' under a '### Release 2.7' nested inside a
    # numbered parent. A fixed '###' would silently miss the nested form.
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string[]]$Lines,
        [Parameter()][int]$ReleaseHeadingLevel = 2
    )

    $bodies = @{}
    $current = $null
    $buffer = New-Object 'System.Collections.Generic.List[string]'
    $minDepth = $ReleaseHeadingLevel + 1
    $subHeadingRx = "^#{$minDepth,6}\s+(.+?)\s*$"

    foreach ($line in $Lines) {
        $m = [regex]::Match($line, $subHeadingRx)
        if ($m.Success) {
            if ($null -ne $current) {
                $bodies[$current] = ($buffer -join "`n")
                $buffer.Clear()
            }
            $current = $m.Groups[1].Value.Trim()
            continue
        }
        if ($null -ne $current) {
            [void]$buffer.Add($line)
        }
    }

    if ($null -ne $current) {
        $bodies[$current] = ($buffer -join "`n")
    }

    return $bodies
}

function Get-BodyForAliases {
    param(
        [Parameter(Mandatory=$true)]$Bodies,
        [Parameter(Mandatory=$true)][string[]]$Aliases
    )

    foreach ($name in $Bodies.Keys) {
        foreach ($alias in $Aliases) {
            if ($name -match ("(?i)^\s*" + [regex]::Escape($alias) + "\s*$")) {
                return [string]$Bodies[$name]
            }
        }
    }
    return ''
}

function Test-MeaningfulBody {
    param([Parameter()][AllowNull()][string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    $compact = ($Body -replace '[\s\-_*`#>]', '').Trim()
    if ($compact.Length -lt [int]$script:Detection.meaningfulBodyMinimumCharacters) { return $false }
    if ([regex]::IsMatch($Body, $script:Detection.meaningfulBodyPlaceholderPattern)) { return $false }
    return $true
}

function Test-TextMatchesAnyPattern {
    param(
        [Parameter()][AllowNull()][string]$Text,
        [Parameter()][object[]]$Patterns
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    foreach ($pattern in @($Patterns)) {
        if ($Text -match ([string]$pattern)) { return $true }
    }
    return $false
}

function Get-ChecklistItemsFromLines {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string[]]$Lines)

    $items = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $m = [regex]::Match($Lines[$i], '^\s*[-*]\s+\[([ xX])\]\s+(.+?)\s*$')
        if ($m.Success) {
            $checked = ($m.Groups[1].Value -match '[xX]')
            [void]$items.Add([pscustomobject]@{
                Checked = $checked
                Text = $m.Groups[2].Value.Trim()
                Line = $i + 1
            })
        }
    }
    return $items.ToArray()
}

function New-BaseContract {
    param(
        [Parameter(Mandatory=$true)][string]$RoadmapState,
        [Parameter()][AllowNull()][string]$ParseError,
        [Parameter(Mandatory=$true)][string]$RequestedPath
    )

    $repoName = Get-RepoNameFromPath -RoadmapPath $RequestedPath
    $repoPath = $null
    $roadmapPath = $null

    try {
        $resolved = Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop
        $roadmapPath = $resolved.ProviderPath
        $repoPath = Split-Path -Parent $roadmapPath
    }
    catch {
        $roadmapPath = $RequestedPath
    }

    return [ordered]@{
        schemaVersion = '2.0'
        repoName = $repoName
        repoPath = $repoPath
        roadmapPath = $roadmapPath
        roadmapState = $RoadmapState
        maturityLevel = 'L0-Absent'
        maturityScore = $null
        pendingCount = 0
        completedCount = 0
        totalCount = 0
        nextPendingItem = $null
        sections = @()
        releases = @()
        activeRelease = $null
        hasProductIntent = $false
        hasReleaseSections = $false
        hasAcceptanceCriteria = $false
        hasOutOfScope = $false
        releaseCount = 0
        activeReleaseCount = 0
        releasesMissingAcceptanceCriteria = 0
        releasesMissingOutOfScope = 0
        vagueItemCount = 0
        unknownStatusCount = 0
        doneReleaseUncheckedItemCount = 0
        activeReleaseHasValidationPlan = $false
        activeReleaseHasTraceability = $false
        parseError = $ParseError
        schemaFindings = @()
        auditFindings = @()
        parsedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function ConvertTo-RoadmapContract {
    param(
        [Parameter(Mandatory=$true)][string]$RoadmapPath,
        [Parameter(Mandatory=$true)]$Rules
    )

    if (-not (Test-Path -LiteralPath $RoadmapPath)) {
        return [pscustomobject](New-BaseContract -RoadmapState 'missing' -ParseError 'ROADMAP.md was not found at the requested path.' -RequestedPath $RoadmapPath)
    }

    $contract = [pscustomobject](New-BaseContract -RoadmapState 'pending' -ParseError $null -RequestedPath $RoadmapPath)
    $lines = @(Get-Content -LiteralPath $RoadmapPath)
    $allItems = @(Get-ChecklistItemsFromLines -Lines $lines)

    $sectionList = [System.Collections.Generic.List[object]]::new()
    $currentSectionName = '(root)'
    $currentSectionLevel = 0
    $currentSectionLine = 1
    $currentPending = New-Object 'System.Collections.Generic.List[string]'
    $currentCompleted = New-Object 'System.Collections.Generic.List[string]'

    function Flush-Section {
        if ($currentSectionName -ne '(root)' -or $currentPending.Count -gt 0 -or $currentCompleted.Count -gt 0) {
            [void]$sectionList.Add([pscustomobject]@{
                name = $currentSectionName
                level = [int]$currentSectionLevel
                line = [int]$currentSectionLine
                pendingItems = @($currentPending)
                completedItems = @($currentCompleted)
            })
        }
    }

    $releaseStarts = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $heading = Get-HeadingMatch -Line $line
        if ($null -ne $heading) {
            Flush-Section
            $currentSectionName = $heading.Text
            $currentSectionLevel = $heading.Level
            $currentSectionLine = $i + 1
            $currentPending = New-Object 'System.Collections.Generic.List[string]'
            $currentCompleted = New-Object 'System.Collections.Generic.List[string]'

            # Product intent is document-scoped and matched against the whole
            # heading line, so the shared pattern sees the '#' depth it anchors on.
            if ([regex]::IsMatch($line, $script:Detection.productIntentHeadingPattern)) {
                $contract.hasProductIntent = $true
            }
        }

        $releaseHeading = Get-ReleaseHeadingMatch -Line $line
        if ($null -ne $releaseHeading) {
            [void]$releaseStarts.Add([pscustomobject]@{
                id = $releaseHeading.Id
                title = $releaseHeading.Title
                level = $releaseHeading.Level
                lineIndex = $i
                line = $i + 1
            })
        }

        $itemMatch = [regex]::Match($line, '^\s*[-*]\s+\[([ xX])\]\s+(.+?)\s*$')
        if ($itemMatch.Success) {
            $itemText = $itemMatch.Groups[2].Value.Trim()
            if ($itemMatch.Groups[1].Value -match '[xX]') {
                [void]$currentCompleted.Add($itemText)
            }
            else {
                [void]$currentPending.Add($itemText)
            }
        }
    }
    Flush-Section

    $contract.sections = $sectionList.ToArray()
    $contract.pendingCount = @($allItems | Where-Object { -not $_.Checked }).Count
    $contract.completedCount = @($allItems | Where-Object { $_.Checked }).Count
    $contract.totalCount = $allItems.Count

    if ($contract.totalCount -eq 0) {
        $contract.roadmapState = 'parse-error'
        $contract.parseError = 'No markdown checklist items were found.'
    }
    elseif ($contract.pendingCount -eq 0) {
        $contract.roadmapState = 'complete'
    }
    else {
        $contract.roadmapState = 'pending'
    }

    $releaseList = [System.Collections.Generic.List[object]]::new()
    $activeStatuses = @('active','blocked','validation')
    if ($Rules.PSObject.Properties.Name -contains 'statusVocabulary' -and $Rules.statusVocabulary.PSObject.Properties.Name -contains 'activeStatuses') {
        $activeStatuses = @($Rules.statusVocabulary.activeStatuses)
    }

    for ($r = 0; $r -lt $releaseStarts.Count; $r++) {
        $start = $releaseStarts[$r]
        $endIndex = $lines.Count - 1
        if ($r + 1 -lt $releaseStarts.Count) {
            $endIndex = [int]$releaseStarts[$r + 1].lineIndex - 1
        }

        $startIndex = [int]$start.lineIndex
        $blockLines = @($lines[$startIndex..$endIndex])
        $blockText = $blockLines -join "`n"
        $blockItems = @(Get-ChecklistItemsFromLines -Lines $blockLines)
        $bodies = Get-SectionBodiesFromBlock -Lines $blockLines -ReleaseHeadingLevel ([int]$start.level)

        $status = $null
        $statusMatch = [regex]::Match($blockText, '(?im)^\s*>\s*Status:\s*(.+?)\s*$')
        if ($statusMatch.Success) { $status = $statusMatch.Groups[1].Value.Trim() }
        $normalizedStatus = Normalize-Status -Status $status -Rules $Rules

        $goal = $null
        $goalMatch = [regex]::Match($blockText, '(?im)^\s*\*\*Goal:\*\*\s*(.+?)\s*$')
        if ($goalMatch.Success) { $goal = $goalMatch.Groups[1].Value.Trim() }
        else {
            $goalBody = Get-BodyForAliases -Bodies $bodies -Aliases @('Goal')
            if (-not [string]::IsNullOrWhiteSpace($goalBody)) { $goal = $goalBody.Trim() }
        }

        $acceptanceBody = Get-BodyForAliases -Bodies $bodies -Aliases @($script:Detection.acceptanceCriteriaHeadingAliases)
        $outOfScopeBody = Get-BodyForAliases -Bodies $bodies -Aliases @($script:Detection.outOfScopeHeadingAliases)
        $validationBody = Get-BodyForAliases -Bodies $bodies -Aliases @('Validation plan','Validation','Test plan')
        $traceabilityBody = Get-BodyForAliases -Bodies $bodies -Aliases @('Traceability','References','Links')

        $validationSignals = @()
        if ($Rules.PSObject.Properties.Name -contains 'validationSignals') { $validationSignals = @($Rules.validationSignals) }
        $traceabilityPatterns = @()
        if ($Rules.PSObject.Properties.Name -contains 'traceabilityPatterns') { $traceabilityPatterns = @($Rules.traceabilityPatterns) }

        $release = [pscustomobject]@{
            id = [string]$start.id
            title = [string]$start.title
            line = [int]$start.line
            status = $status
            normalizedStatus = $normalizedStatus
            goal = $goal
            pendingCount = @($blockItems | Where-Object { -not $_.Checked }).Count
            completedCount = @($blockItems | Where-Object { $_.Checked }).Count
            totalCount = $blockItems.Count
            hasAcceptanceCriteria = (Test-MeaningfulBody -Body $acceptanceBody)
            hasOutOfScope = (Test-MeaningfulBody -Body $outOfScopeBody)
            hasValidationPlan = (Test-MeaningfulBody -Body $validationBody)
            hasConcreteValidationPlan = (Test-TextMatchesAnyPattern -Text $validationBody -Patterns $validationSignals)
            hasTraceability = (Test-TextMatchesAnyPattern -Text $traceabilityBody -Patterns $traceabilityPatterns)
            sections = @($bodies.Keys)
        }
        [void]$releaseList.Add($release)
    }

    $contract.releases = $releaseList.ToArray()
    $contract.releaseCount = $releaseList.Count
    $contract.hasReleaseSections = ($contract.releaseCount -gt 0)
    $contract.hasAcceptanceCriteria = (@($releaseList | Where-Object { $_.hasAcceptanceCriteria }).Count -gt 0)
    $contract.hasOutOfScope = (@($releaseList | Where-Object { $_.hasOutOfScope }).Count -gt 0)

    $nonArchived = @($releaseList | Where-Object { $_.normalizedStatus -ne 'archived' })
    $contract.releasesMissingAcceptanceCriteria = @($nonArchived | Where-Object { -not $_.hasAcceptanceCriteria }).Count
    $contract.releasesMissingOutOfScope = @($nonArchived | Where-Object { -not $_.hasOutOfScope }).Count
    $contract.unknownStatusCount = @($releaseList | Where-Object { -not [string]::IsNullOrWhiteSpace($_.status) -and $null -eq $_.normalizedStatus }).Count
    $contract.doneReleaseUncheckedItemCount = @($releaseList | Where-Object { $_.normalizedStatus -eq 'done' } | ForEach-Object { $_.pendingCount } | Measure-Object -Sum).Sum
    if ($null -eq $contract.doneReleaseUncheckedItemCount) { $contract.doneReleaseUncheckedItemCount = 0 }

    $active = @($releaseList | Where-Object { $activeStatuses -contains $_.normalizedStatus })
    $contract.activeReleaseCount = $active.Count
    if ($active.Count -gt 0) {
        $firstActive = $active[0]
        $contract.activeRelease = [pscustomobject]@{
            id = $firstActive.id
            title = $firstActive.title
            status = $firstActive.normalizedStatus
        }
        $contract.activeReleaseHasValidationPlan = ($firstActive.hasValidationPlan -and $firstActive.hasConcreteValidationPlan)
        $contract.activeReleaseHasTraceability = $firstActive.hasTraceability
    }

    $firstPending = $null
    foreach ($section in $contract.sections) {
        if ($section.pendingItems.Count -gt 0) {
            $firstPending = [pscustomobject]@{
                text = [string]$section.pendingItems[0]
                section = [string]$section.name
                releaseId = $null
            }
            break
        }
    }
    $contract.nextPendingItem = $firstPending

    return [pscustomobject]$contract
}

function Get-ContractFieldValue {
    param(
        [Parameter(Mandatory=$true)]$Contract,
        [Parameter(Mandatory=$true)][string]$Field
    )

    $prop = $Contract.PSObject.Properties[$Field]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Test-Condition {
    param(
        [Parameter(Mandatory=$true)]$Condition,
        [Parameter(Mandatory=$true)]$Contract
    )

    if ($Condition.PSObject.Properties.Name -contains 'all') {
        foreach ($child in @($Condition.all)) {
            if (-not (Test-Condition -Condition $child -Contract $Contract)) { return $false }
        }
        return $true
    }

    if ($Condition.PSObject.Properties.Name -contains 'any') {
        foreach ($child in @($Condition.any)) {
            if (Test-Condition -Condition $child -Contract $Contract) { return $true }
        }
        return $false
    }

    $field = [string]$Condition.field
    $operator = [string]$Condition.operator
    $expected = $null
    if ($Condition.PSObject.Properties.Name -contains 'value') { $expected = $Condition.value }
    $actual = Get-ContractFieldValue -Contract $Contract -Field $field

    switch ($operator) {
        'eq' { return ($actual -eq $expected) }
        'ne' { return ($actual -ne $expected) }
        'lt' { return ([double]$actual -lt [double]$expected) }
        'lte' { return ([double]$actual -le [double]$expected) }
        'gt' { return ([double]$actual -gt [double]$expected) }
        'gte' { return ([double]$actual -ge [double]$expected) }
        'isTrue' { return ($actual -eq $true) }
        'isFalse' { return ($actual -ne $true) }
        default { throw "Unsupported rule condition operator: $operator" }
    }
}

function Set-VagueItemMetric {
    param(
        [Parameter(Mandatory=$true)]$Contract,
        [Parameter(Mandatory=$true)]$Rules
    )

    $patterns = @()
    foreach ($rule in @($Rules.rules)) {
        if ($rule.id -eq 'ROADMAP-010' -and $rule.PSObject.Properties.Name -contains 'vaguePatterns') {
            $patterns = @($rule.vaguePatterns)
            break
        }
    }

    if ($patterns.Count -eq 0) { return }

    $count = 0
    foreach ($section in @($Contract.sections)) {
        foreach ($item in @($section.pendingItems + $section.completedItems)) {
            foreach ($pattern in $patterns) {
                if ($item -match ([string]$pattern)) {
                    $count++
                    break
                }
            }
        }
    }
    $Contract.vagueItemCount = $count
}

function Get-MaturityFromScore {
    param(
        [Parameter(Mandatory=$true)][double]$Score,
        [Parameter(Mandatory=$true)]$Rules
    )

    $thresholds = $Rules.maturityThresholds
    foreach ($name in @('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')) {
        if ($thresholds.PSObject.Properties.Name -contains $name) {
            $t = $thresholds.$name
            if ($Score -ge [double]$t.minScore -and $Score -le [double]$t.maxScore) { return $name }
        }
    }
    return 'L1-Informal'
}

function Cap-MaturityLevel {
    param(
        [Parameter(Mandatory=$true)][string]$CurrentLevel,
        [Parameter(Mandatory=$true)][string]$MaxLevel
    )

    if ($script:LevelRank[$CurrentLevel] -gt $script:LevelRank[$MaxLevel]) { return $MaxLevel }
    return $CurrentLevel
}

function Test-KnownRuleFailure {
    # Fallback for rule packs whose rules carry only a failCondition string
    # (schema v1.0). Mirrors the hardcoded evaluation switch in
    # backend/modules/roadmap/Roadmap.Auditor.ps1 so this tool and the
    # product auditor agree on what each rule means.
    param(
        [Parameter(Mandatory=$true)][string]$RuleId,
        [Parameter(Mandatory=$true)]$Contract
    )

    switch ($RuleId) {
        'ROADMAP-001' { return ($Contract.roadmapState -eq 'missing') }
        'ROADMAP-002' { return ($Contract.roadmapState -eq 'parse-error') }
        'ROADMAP-003' { return ($Contract.roadmapState -eq 'complete') }
        'ROADMAP-004' { return (-not $Contract.hasProductIntent) }
        'ROADMAP-005' { return (-not $Contract.hasReleaseSections) }
        'ROADMAP-006' { return (-not $Contract.hasAcceptanceCriteria) }
        'ROADMAP-007' { return (-not $Contract.hasOutOfScope) }
        'ROADMAP-008' { return ($Contract.pendingCount -lt 3 -and $Contract.roadmapState -eq 'pending') }
        'ROADMAP-009' { return ($null -ne $Contract.releaseCount -and [int]$Contract.releaseCount -lt 2) }
        'ROADMAP-010' { return ([int]$Contract.vagueItemCount -gt 0) }
        'ROADMAP-011' { return ([int]$Contract.activeReleaseCount -gt 1) }
        'ROADMAP-012' { return ([int]$Contract.releaseCount -gt 0 -and [int]$Contract.activeReleaseCount -eq 0) }
        default       { return $false }  # unknown rule — do not penalise
    }
}

function Invoke-RoadmapAuditRules {
    param(
        [Parameter(Mandatory=$true)]$Contract,
        [Parameter(Mandatory=$true)]$Rules
    )

    Set-VagueItemMetric -Contract $Contract -Rules $Rules

    $script:AuditFindings.Clear()

    # detection.scoring.mode = "normalized": the rule weights do not sum to 100
    # (they sum to 125 in v1.2), so the score is the surviving fraction of the
    # total weight, rescaled to 0-100. Subtracting penalties from a flat 100 —
    # what this tool did before 2026-08-08 — produces a different number than
    # the backend auditor on the very same file.
    $maxPossibleScore = ($Rules.rules | Measure-Object -Property scoreWeight -Sum).Sum
    if ($null -eq $maxPossibleScore -or [double]$maxPossibleScore -le 0) { $maxPossibleScore = 100 }
    $totalPenalty = 0.0

    foreach ($rule in @($Rules.rules)) {
        $failed = if ($rule.PSObject.Properties.Name -contains 'condition' -and $null -ne $rule.condition) {
            Test-Condition -Condition $rule.condition -Contract $Contract
        } else {
            Test-KnownRuleFailure -RuleId ([string]$rule.id) -Contract $Contract
        }
        if ($failed) {
            $impact = 0.0
            if ($rule.PSObject.Properties.Name -contains 'scoreWeight') { $impact = [double]$rule.scoreWeight }
            $totalPenalty += $impact
            [void]$script:AuditFindings.Add([pscustomobject]@{
                ruleId = [string]$rule.id
                name = [string]$rule.name
                severity = [string]$rule.severity
                message = [string]$rule.message
                recommendedAction = [string]$rule.recommendedAction
                scoreImpact = $impact
            })
        }
    }

    $rawScore = [double]$maxPossibleScore - $totalPenalty
    if ($rawScore -lt 0) { $rawScore = 0 }
    $score = [double][int][math]::Round(($rawScore / [double]$maxPossibleScore) * 100)
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    # A missing roadmap is L0-Absent regardless of which other rules happened
    # not to fire.
    if ($Contract.roadmapState -eq 'missing') { $score = 0 }

    $Contract.maturityScore = $score
    $level = Get-MaturityFromScore -Score $Contract.maturityScore -Rules $Rules

    $criticalCount = @($script:AuditFindings | Where-Object { $_.severity -eq 'critical' }).Count
    $warningCount = @($script:AuditFindings | Where-Object { $_.severity -eq 'warning' }).Count

    if (-not ($Contract.PSObject.Properties.Name -contains 'criticalFindingCount')) {
        $Contract | Add-Member -NotePropertyName criticalFindingCount -NotePropertyValue $criticalCount -Force
    } else { $Contract.criticalFindingCount = $criticalCount }
    if (-not ($Contract.PSObject.Properties.Name -contains 'warningFindingCount')) {
        $Contract | Add-Member -NotePropertyName warningFindingCount -NotePropertyValue $warningCount -Force
    } else { $Contract.warningFindingCount = $warningCount }

    if ($Rules.PSObject.Properties.Name -contains 'maturityCaps') {
        foreach ($cap in @($Rules.maturityCaps)) {
            if (Test-Condition -Condition $cap.when -Contract $Contract) {
                $level = Cap-MaturityLevel -CurrentLevel $level -MaxLevel ([string]$cap.maxLevel)
            }
        }
    }

    # More than one active release caps the roadmap at L2 per
    # ROADMAP_MATURITY_MODEL.md: an ambiguous dispatch target is as unusable as
    # missing structure. The SCORE is capped too, not just the label, so score
    # and level stay consistent for every consumer — same as the backend
    # auditor's cap.
    if ([int]$Contract.activeReleaseCount -gt 1) {
        $l2Max = 64
        if ($Rules.PSObject.Properties.Name -contains 'maturityThresholds' -and
            $Rules.maturityThresholds.PSObject.Properties.Name -contains 'L2-Structured') {
            $l2Max = [int]$Rules.maturityThresholds.'L2-Structured'.maxScore
        }
        if ($Contract.maturityScore -gt $l2Max) {
            $Contract.maturityScore = $l2Max
            $level = Get-MaturityFromScore -Score $Contract.maturityScore -Rules $Rules
        }
    }

    $Contract.maturityLevel = $level
    $Contract.auditFindings = $script:AuditFindings.ToArray()

    # Remove transient cap helper fields before schema validation/output.
    if ($Contract.PSObject.Properties.Name -contains 'criticalFindingCount') {
        $Contract.PSObject.Properties.Remove('criticalFindingCount')
    }
    if ($Contract.PSObject.Properties.Name -contains 'warningFindingCount') {
        $Contract.PSObject.Properties.Remove('warningFindingCount')
    }

    return $Contract
}

function Test-ContractAgainstSchemaLite {
    param(
        [Parameter(Mandatory=$true)]$Contract,
        [Parameter(Mandatory=$true)]$Schema
    )

    $script:SchemaFindings.Clear()

    foreach ($required in @($Schema.required)) {
        if (-not ($Contract.PSObject.Properties.Name -contains $required)) {
            [void]$script:SchemaFindings.Add("Missing required property: $required")
        }
    }

    if ($Schema.PSObject.Properties.Name -contains 'additionalProperties' -and $Schema.additionalProperties -eq $false) {
        $allowed = @($Schema.properties.PSObject.Properties.Name)
        foreach ($prop in $Contract.PSObject.Properties.Name) {
            if ($allowed -notcontains $prop) {
                [void]$script:SchemaFindings.Add("Unexpected property: $prop")
            }
        }
    }

    $stateAllowed = @('pending','complete','missing','parse-error')
    if ($stateAllowed -notcontains $Contract.roadmapState) {
        [void]$script:SchemaFindings.Add("Invalid roadmapState: $($Contract.roadmapState)")
    }

    $levelAllowed = @('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')
    if ($levelAllowed -notcontains $Contract.maturityLevel) {
        [void]$script:SchemaFindings.Add("Invalid maturityLevel: $($Contract.maturityLevel)")
    }

    if ($null -ne $Contract.maturityScore -and ($Contract.maturityScore -lt 0 -or $Contract.maturityScore -gt 100)) {
        [void]$script:SchemaFindings.Add("maturityScore out of range: $($Contract.maturityScore)")
    }

    $Contract.schemaFindings = @($script:SchemaFindings)
    return ($script:SchemaFindings.Count -eq 0)
}

function Write-AuditSummary {
    param([Parameter(Mandatory=$true)]$Contract)

    Write-Host "Roadmap contract audit"
    Write-Host "  Repo:        $($Contract.repoName)"
    Write-Host "  State:       $($Contract.roadmapState)"
    Write-Host "  Score:       $($Contract.maturityScore)"
    Write-Host "  Maturity:    $($Contract.maturityLevel)"
    Write-Host "  Items:       $($Contract.pendingCount) pending / $($Contract.completedCount) complete / $($Contract.totalCount) total"
    Write-Host "  Releases:    $($Contract.releaseCount)"

    if ($Contract.auditFindings.Count -gt 0) {
        Write-Host ''
        Write-Host 'Findings:'
        foreach ($f in @($Contract.auditFindings)) {
            Write-Host ("  [{0}] {1} {2} - {3}" -f $f.severity.ToUpperInvariant(), $f.ruleId, $f.name, $f.message)
            if (-not [string]::IsNullOrWhiteSpace($f.recommendedAction)) {
                Write-Host ("      Action: {0}" -f $f.recommendedAction)
            }
        }
    }

    if ($Contract.schemaFindings.Count -gt 0) {
        Write-Host ''
        Write-Host 'Schema findings:'
        foreach ($s in @($Contract.schemaFindings)) {
            Write-Host "  [SCHEMA] $s"
        }
    }
}

if (-not $LoadFunctionsOnly) {
    $rulesFile = Resolve-StandardsFile -ExplicitPath $RulesPath -DefaultName 'roadmap-audit-rules.json'
    $schemaFile = Resolve-StandardsFile -ExplicitPath $SchemaPath -DefaultName 'roadmap-contract.schema.json'

    if (-not (Test-Path -LiteralPath $rulesFile)) { throw "Rules file not found: $rulesFile" }
    if (-not (Test-Path -LiteralPath $schemaFile)) { throw "Schema file not found: $schemaFile" }

    $rules = Get-Content -LiteralPath $rulesFile -Raw | ConvertFrom-Json
    $schema = Get-Content -LiteralPath $schemaFile -Raw | ConvertFrom-Json

    # Adopt the rule pack's detection contract before parsing anything, so this
    # tool and the backend auditor read the same file the same way.
    Set-DetectionProfile -Rules $rules

    $contract = ConvertTo-RoadmapContract -RoadmapPath $Path -Rules $rules
    $contract = Invoke-RoadmapAuditRules -Contract $contract -Rules $rules
    [void](Test-ContractAgainstSchemaLite -Contract $contract -Schema $schema)

    if (-not $Quiet) { Write-AuditSummary -Contract $contract }

    if (-not [string]::IsNullOrWhiteSpace($ContractOut)) {
        $parent = Split-Path -Parent $ContractOut
        if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $contract | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ContractOut -Encoding UTF8
    }

    if (-not [string]::IsNullOrWhiteSpace($JsonOut)) {
        $parent = Split-Path -Parent $JsonOut
        if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        @($contract.auditFindings + @($contract.schemaFindings | ForEach-Object {
            [pscustomobject]@{ ruleId = 'SCHEMA'; name = 'schema-validation'; severity = 'critical'; message = $_; recommendedAction = 'Fix the contract parser or schema alignment.'; scoreImpact = $null }
        })) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $JsonOut -Encoding UTF8
    }

    $exitCode = 0
    $hasCritical = @($contract.auditFindings | Where-Object { $_.severity -eq 'critical' }).Count -gt 0
    $hasSchema = $contract.schemaFindings.Count -gt 0
    if ($FailOnError -and ($hasCritical -or $hasSchema)) { $exitCode = 1 }
    if ($script:LevelRank[$contract.maturityLevel] -lt $script:LevelRank[$MinimumMaturity]) { $exitCode = 1 }

    exit $exitCode
}

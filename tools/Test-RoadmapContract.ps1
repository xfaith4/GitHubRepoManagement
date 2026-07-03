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

$script:AuditFindings = New-Object 'System.Collections.Generic.List[object]'
$script:SchemaFindings = New-Object 'System.Collections.Generic.List[string]'

$script:LevelRank = @{
    'L0-Absent' = 0
    'L1-Informal' = 1
    'L2-Structured' = 2
    'L3-Contract-Ready' = 3
    'L4-Orchestration-Ready' = 4
}

function Resolve-StandardsFile {
    param(
        [Parameter(Mandatory=$true)][string]$ExplicitPath,
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
    param([Parameter(Mandatory=$true)][string]$Line)

    $m = [regex]::Match($Line, '^(#{1,6})\s+(.+?)\s*$')
    if (-not $m.Success) { return $null }

    return [pscustomobject]@{
        Level = $m.Groups[1].Value.Length
        Text = $m.Groups[2].Value.Trim()
    }
}

function Get-ReleaseHeadingMatch {
    param([Parameter(Mandatory=$true)][string]$Line)

    $m = [regex]::Match($Line, '^##\s+Release\s+([0-9]+(?:\.[0-9]+)*)\s+[—-]\s+(.+?)\s*$')
    if (-not $m.Success) { return $null }

    return [pscustomobject]@{
        Id = $m.Groups[1].Value.Trim()
        Title = $m.Groups[2].Value.Trim()
    }
}

function Get-SectionBodiesFromBlock {
    param([Parameter(Mandatory=$true)][string[]]$Lines)

    $bodies = @{}
    $current = $null
    $buffer = New-Object 'System.Collections.Generic.List[string]'

    foreach ($line in $Lines) {
        $m = [regex]::Match($line, '^###\s+(.+?)\s*$')
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
    if ($compact.Length -lt 4) { return $false }
    if ($Body -match '(?i)\b(tbd|todo|none yet|not yet|n/a)\b') { return $false }
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
    param([Parameter(Mandatory=$true)][string[]]$Lines)

    $items = New-Object 'System.Collections.Generic.List[object]'
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
    return @($items)
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

    $sectionList = New-Object 'System.Collections.Generic.List[object]'
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

    $releaseStarts = New-Object 'System.Collections.Generic.List[object]'

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

            if ($heading.Text -match '(?i)\b(product intent|scope|purpose)\b') {
                $contract.hasProductIntent = $true
            }
        }

        $releaseHeading = Get-ReleaseHeadingMatch -Line $line
        if ($null -ne $releaseHeading) {
            [void]$releaseStarts.Add([pscustomobject]@{
                id = $releaseHeading.Id
                title = $releaseHeading.Title
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

    $contract.sections = @($sectionList)
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

    $releaseList = New-Object 'System.Collections.Generic.List[object]'
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
        $bodies = Get-SectionBodiesFromBlock -Lines $blockLines

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

        $acceptanceBody = Get-BodyForAliases -Bodies $bodies -Aliases @('Acceptance criteria','Acceptance Criteria')
        $outOfScopeBody = Get-BodyForAliases -Bodies $bodies -Aliases @('Out of scope','Out-of-scope','Non-goals','Non goals','Not included')
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

    $contract.releases = @($releaseList)
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

function Invoke-RoadmapAuditRules {
    param(
        [Parameter(Mandatory=$true)]$Contract,
        [Parameter(Mandatory=$true)]$Rules
    )

    Set-VagueItemMetric -Contract $Contract -Rules $Rules

    $script:AuditFindings.Clear()
    $score = 100.0

    foreach ($rule in @($Rules.rules)) {
        $failed = Test-Condition -Condition $rule.condition -Contract $Contract
        if ($failed) {
            $impact = 0.0
            if ($rule.PSObject.Properties.Name -contains 'scoreWeight') { $impact = [double]$rule.scoreWeight }
            $score -= $impact
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

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    $Contract.maturityScore = [math]::Round($score, 2)
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

    $Contract.maturityLevel = $level
    $Contract.auditFindings = @($script:AuditFindings)

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

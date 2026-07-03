<#
.SYNOPSIS
    Roadmap execution-hygiene linter for CI.

.DESCRIPTION
    This script validates the readable ROADMAP.md layout and active-release
    hygiene. It does not compute maturity. Use Test-RoadmapContract.ps1 for
    JSON-backed maturity scoring.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Path = './ROADMAP.md',
    [Parameter()][string]$Config = '',
    [Parameter()][string]$JsonOut = '',
    [Parameter()][string]$CsvOut = '',
    [Parameter()][switch]$FailOnError,
    [Parameter()][switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Findings = New-Object 'System.Collections.Generic.List[object]'

$script:DefaultConfig = @{
    requiredTopLevelSections = @('Product Intent','Product Principles','Current State Summary','Release Index','Definition of Done')
    requiredReleaseSections = @('Product outcomes','Engineering milestones','Acceptance criteria','Out of scope')
    activeReleaseRequiredSections = @('Validation plan','Risks and blockers','Dependencies','Known issues','Traceability')
    allowedStatuses = @('planned','active','blocked','validation','done','archived')
    statusAliases = @{
        'pending' = 'planned'; 'in progress' = 'active'; 'in-progress' = 'active'; 'wip' = 'active'
        'complete' = 'done'; 'completed' = 'done'; 'shipped' = 'done'; 'released' = 'done'
    }
    activeStatuses = @('active','blocked','validation')
    maxActiveRoadmapLines = 900
    maxFutureReleaseLines = 120
    allowImmediateNextFocus = $false
    requireSingleActiveRelease = $true
    treatDoneWithUncheckedCriteriaAsError = $true
    flagFutureReleaseRecommendations = $true
    validationSignals = @('npm test','npm run test','npm run build','npm run lint','dotnet test','pytest','invoke-pester','pester','psscriptanalyzer','manual smoke test','smoke test','ci','github actions','deployment verification','api smoke','frontend smoke','backend health check','playwright','curl ')
    weakAcceptanceTerms = @('works','work','done','complete','completed','good enough','polish','improve','improved','finalize','finalized','cleanup','clean up','misc','tbd','etc','various')
    traceabilityPatterns = @('#\d+','PR\s*#?\d+','commit\s+[a-f0-9]{7,40}','ADR-?\d+','docs/','tests?/','\.github/workflows/','JIRA-[0-9]+','GH-[0-9]+')
}

function Add-Finding {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('error','warning','info')][string]$Severity,
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter()][string]$Release = '',
        [Parameter()][int]$Line = 0,
        [Parameter()][string]$RecommendedAction = ''
    )

    [void]$script:Findings.Add([pscustomobject]@{
        severity = $Severity
        code = $Code
        message = $Message
        release = $Release
        line = $Line
        recommendedAction = $RecommendedAction
    })
}

function Merge-Config {
    param([Parameter()][string]$ConfigPath)

    $merged = @{}
    foreach ($k in $script:DefaultConfig.Keys) { $merged[$k] = $script:DefaultConfig[$k] }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $candidates = @(
            './standards/roadmap/roadmap-validation.config.json',
            './tools/roadmap-validation.config.json'
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) { $ConfigPath = $candidate; break }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            Add-Finding -Severity error -Code 'RQ000-CONFIG-MISSING' -Message "Config file not found: $ConfigPath" -RecommendedAction 'Fix the -Config path or omit it to use defaults.'
            return $merged
        }
        try {
            $json = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) {
                if ($merged.ContainsKey($p.Name)) { $merged[$p.Name] = $p.Value }
            }
        }
        catch {
            Add-Finding -Severity error -Code 'RQ000-CONFIG-INVALID' -Message "Config file could not be parsed: $($_.Exception.Message)" -RecommendedAction 'Fix JSON syntax.'
        }
    }

    return $merged
}

function Get-Heading {
    param([Parameter(Mandatory=$true)][string]$Line)
    $m = [regex]::Match($Line, '^(#{1,6})\s+(.+?)\s*$')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{ Level = $m.Groups[1].Value.Length; Text = $m.Groups[2].Value.Trim() }
}

function Get-ReleaseHeading {
    param([Parameter(Mandatory=$true)][string]$Line)
    $m = [regex]::Match($Line, '^##\s+Release\s+([0-9]+(?:\.[0-9]+)*)\s+[—-]\s+(.+?)\s*$')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{ Id = $m.Groups[1].Value.Trim(); Title = $m.Groups[2].Value.Trim() }
}

function Convert-VersionToTuple {
    param([Parameter(Mandatory=$true)][string]$Version)
    return @($Version.Split('.') | ForEach-Object { [int]$_ })
}

function Test-VersionLessThan {
    param([string]$Left, [string]$Right)
    $a = Convert-VersionToTuple $Left
    $b = Convert-VersionToTuple $Right
    $max = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $av = if ($i -lt $a.Count) { $a[$i] } else { 0 }
        $bv = if ($i -lt $b.Count) { $b[$i] } else { 0 }
        if ($av -lt $bv) { return $true }
        if ($av -gt $bv) { return $false }
    }
    return $false
}

function Normalize-Status {
    param([AllowNull()][string]$Status, [hashtable]$ConfigData)
    if ([string]::IsNullOrWhiteSpace($Status)) { return $null }
    $s = $Status.Trim().ToLowerInvariant()
    if (@($ConfigData.allowedStatuses) -contains $s) { return $s }
    $aliases = @{}
    $aliasSource = $ConfigData.statusAliases
    if ($aliasSource -is [System.Collections.IDictionary]) {
        foreach ($entry in $aliasSource.GetEnumerator()) { $aliases[[string]$entry.Key.ToLowerInvariant()] = [string]$entry.Value }
    }
    else {
        foreach ($p in $aliasSource.PSObject.Properties) { $aliases[$p.Name.ToLowerInvariant()] = [string]$p.Value }
    }
    if ($aliases.ContainsKey($s)) { return $aliases[$s] }
    return $null
}

function Get-ReleaseBlocks {
    param([string[]]$Lines, [hashtable]$ConfigData)

    $starts = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $rh = Get-ReleaseHeading -Line $Lines[$i]
        if ($null -ne $rh) {
            [void]$starts.Add([pscustomobject]@{ Id = $rh.Id; Title = $rh.Title; Start = $i; Line = $i + 1 })
        }
    }

    $blocks = New-Object 'System.Collections.Generic.List[object]'
    for ($r = 0; $r -lt $starts.Count; $r++) {
        $start = $starts[$r]
        $end = $Lines.Count - 1
        if ($r + 1 -lt $starts.Count) { $end = [int]$starts[$r + 1].Start - 1 }
        $startIndex = [int]$start.Start
        $blockLines = @($Lines[$startIndex..$end])
        $text = $blockLines -join "`n"
        $status = $null
        $m = [regex]::Match($text, '(?im)^\s*>\s*Status:\s*(.+?)\s*$')
        if ($m.Success) { $status = $m.Groups[1].Value.Trim() }
        $sections = @()
        foreach ($line in $blockLines) {
            $hm = [regex]::Match($line, '^###\s+(.+?)\s*$')
            if ($hm.Success) { $sections += $hm.Groups[1].Value.Trim() }
        }
        [void]$blocks.Add([pscustomobject]@{
            Id = $start.Id
            Title = $start.Title
            StartLine = $start.Line
            LineCount = $blockLines.Count
            Text = $text
            Lines = $blockLines
            Status = $status
            NormalizedStatus = (Normalize-Status -Status $status -ConfigData $ConfigData)
            Sections = $sections
            PendingCount = ([regex]::Matches($text, '(?m)^\s*[-*]\s+\[ \]\s+')).Count
            CompletedCount = ([regex]::Matches($text, '(?m)^\s*[-*]\s+\[[xX]\]\s+')).Count
        })
    }
    return @($blocks)
}

function Test-ReleaseHasSection {
    param($Release, [string]$SectionName)
    foreach ($s in @($Release.Sections)) {
        if ($s -match ("(?i)^\s*" + [regex]::Escape($SectionName) + "\s*$")) { return $true }
    }
    return $false
}

function Get-ReleaseSectionBody {
    param($Release, [string[]]$Aliases)
    $current = $null
    $buffer = New-Object 'System.Collections.Generic.List[string]'
    $capturing = $false
    foreach ($line in @($Release.Lines)) {
        $m = [regex]::Match($line, '^###\s+(.+?)\s*$')
        if ($m.Success) {
            if ($capturing) { break }
            $name = $m.Groups[1].Value.Trim()
            foreach ($alias in $Aliases) {
                if ($name -match ("(?i)^\s*" + [regex]::Escape($alias) + "\s*$")) {
                    $capturing = $true
                    $current = $name
                    break
                }
            }
            continue
        }
        if ($capturing) { [void]$buffer.Add($line) }
    }
    return ($buffer -join "`n")
}

function Test-BodyMeaningful {
    param([AllowNull()][string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    if ($Body -match '(?i)\b(tbd|todo|none yet|not yet|n/a)\b') { return $false }
    return (($Body -replace '[\s\-_*`#>]', '').Length -ge 4)
}

function Invoke-StructureValidation {
    param([string]$RoadmapPath, [hashtable]$ConfigData)

    if (-not (Test-Path -LiteralPath $RoadmapPath)) {
        Add-Finding -Severity error -Code 'R001-MISSING-ROADMAP' -Message "Roadmap file not found: $RoadmapPath" -RecommendedAction 'Create ROADMAP.md from standards/roadmap/ROADMAP_TEMPLATE.md.'
        return
    }

    $lines = @(Get-Content -LiteralPath $RoadmapPath)
    $text = $lines -join "`n"
    $releases = @(Get-ReleaseBlocks -Lines $lines -ConfigData $ConfigData)

    if ($lines.Count -gt [int]$ConfigData.maxActiveRoadmapLines) {
        Add-Finding -Severity warning -Code 'R002-ROADMAP-TOO-LONG' -Message "Roadmap has $($lines.Count) lines; maximum configured is $($ConfigData.maxActiveRoadmapLines)." -RecommendedAction 'Archive completed history and keep the active roadmap concise.'
    }

    foreach ($required in @($ConfigData.requiredTopLevelSections)) {
        if ($text -notmatch ("(?im)^##\s+\d*\.?\s*" + [regex]::Escape($required) + "\s*$|^##\s+" + [regex]::Escape($required) + "\s*$")) {
            Add-Finding -Severity warning -Code 'R003-MISSING-TOP-LEVEL-SECTION' -Message "Missing top-level section: $required" -RecommendedAction "Add a '$required' section."
        }
    }

    if ($releases.Count -eq 0) {
        Add-Finding -Severity error -Code 'R004-NO-RELEASE-SECTIONS' -Message 'No release sections found.' -RecommendedAction "Add release headings using '## Release X.Y — Title'."
        return
    }

    $seen = @{}
    $previous = $null
    foreach ($release in $releases) {
        if ($seen.ContainsKey($release.Id)) {
            Add-Finding -Severity error -Code 'R005-DUPLICATE-RELEASE' -Message "Duplicate release id: $($release.Id)" -Release $release.Id -Line $release.StartLine -RecommendedAction 'Merge duplicate release sections or assign a stable unique release id.'
        }
        else { $seen[$release.Id] = $true }

        if ($null -ne $previous -and (Test-VersionLessThan -Left $release.Id -Right $previous)) {
            Add-Finding -Severity warning -Code 'R006-RELEASE-ORDER' -Message "Release $($release.Id) appears after later release $previous." -Release $release.Id -Line $release.StartLine -RecommendedAction 'Keep release sections in ascending order.'
        }
        $previous = $release.Id

        foreach ($required in @($ConfigData.requiredReleaseSections)) {
            if (-not (Test-ReleaseHasSection -Release $release -SectionName $required)) {
                Add-Finding -Severity warning -Code 'R007-MISSING-RELEASE-SECTION' -Message "Release $($release.Id) is missing section: $required" -Release $release.Id -Line $release.StartLine -RecommendedAction "Add a '$required' subsection to this release."
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($release.Status) -and $null -eq $release.NormalizedStatus) {
            Add-Finding -Severity warning -Code 'RQ001-UNKNOWN-STATUS' -Message "Release $($release.Id) has unknown status '$($release.Status)'." -Release $release.Id -Line $release.StartLine -RecommendedAction 'Use planned, active, blocked, validation, done, or archived.'
        }

        $criteria = Get-ReleaseSectionBody -Release $release -Aliases @('Acceptance criteria','Acceptance Criteria')
        foreach ($term in @($ConfigData.weakAcceptanceTerms)) {
            if ($criteria -match ("(?im)^\s*[-*]?\s*" + [regex]::Escape([string]$term) + "\s*\.?\s*$")) {
                Add-Finding -Severity warning -Code 'RQ002-WEAK-ACCEPTANCE-CRITERIA' -Message "Release $($release.Id) has weak acceptance criteria term: $term" -Release $release.Id -Line $release.StartLine -RecommendedAction 'Replace vague acceptance criteria with observable verification conditions.'
            }
        }

        if ($release.NormalizedStatus -eq 'done' -and $release.PendingCount -gt 0) {
            $sev = if ($ConfigData.treatDoneWithUncheckedCriteriaAsError) { 'error' } else { 'warning' }
            Add-Finding -Severity $sev -Code 'RQ003-DONE-WITH-UNCHECKED-WORK' -Message "Release $($release.Id) is done but still has $($release.PendingCount) unchecked item(s)." -Release $release.Id -Line $release.StartLine -RecommendedAction 'Complete, move, or explicitly block unchecked work before marking the release done.'
        }

        if ($release.NormalizedStatus -eq 'planned' -and $ConfigData.flagFutureReleaseRecommendations -and $release.LineCount -gt [int]$ConfigData.maxFutureReleaseLines) {
            Add-Finding -Severity info -Code 'RQ004-FUTURE-RELEASE-TOO-DETAILED' -Message "Future release $($release.Id) has $($release.LineCount) lines." -Release $release.Id -Line $release.StartLine -RecommendedAction 'Keep future releases concise until they become active.'
        }
    }

    $active = @($releases | Where-Object { @($ConfigData.activeStatuses) -contains $_.NormalizedStatus })
    if ($ConfigData.requireSingleActiveRelease -and $active.Count -gt 1) {
        Add-Finding -Severity error -Code 'RQ005-MULTIPLE-ACTIVE-RELEASES' -Message "Found $($active.Count) active execution releases." -RecommendedAction 'Keep only one release active, blocked, or in validation.'
    }

    foreach ($release in $active) {
        foreach ($required in @($ConfigData.activeReleaseRequiredSections)) {
            if (-not (Test-ReleaseHasSection -Release $release -SectionName $required)) {
                Add-Finding -Severity warning -Code 'RQ006-MISSING-ACTIVE-SECTION' -Message "Active release $($release.Id) is missing section: $required" -Release $release.Id -Line $release.StartLine -RecommendedAction "Add a '$required' section to the active release."
            }
        }

        $validation = Get-ReleaseSectionBody -Release $release -Aliases @('Validation plan','Validation','Test plan')
        $hasSignal = $false
        foreach ($signal in @($ConfigData.validationSignals)) {
            if ($validation -match [regex]::Escape([string]$signal)) { $hasSignal = $true; break }
        }
        if (-not $hasSignal) {
            Add-Finding -Severity warning -Code 'RQ007-WEAK-VALIDATION-PLAN' -Message "Active release $($release.Id) does not include a concrete validation signal." -Release $release.Id -Line $release.StartLine -RecommendedAction 'Add commands or smoke-test steps such as npm test, dotnet test, Pester, CI, or manual smoke test.'
        }

        $trace = Get-ReleaseSectionBody -Release $release -Aliases @('Traceability','References','Links')
        $hasTrace = $false
        foreach ($pattern in @($ConfigData.traceabilityPatterns)) {
            if ($trace -match ([string]$pattern)) { $hasTrace = $true; break }
        }
        if (-not $hasTrace) {
            Add-Finding -Severity info -Code 'RQ008-MISSING-TRACEABILITY' -Message "Active release $($release.Id) has no issue, PR, commit, ADR, workflow, test, or doc reference." -Release $release.Id -Line $release.StartLine -RecommendedAction 'Add explicit traceability references.'
        }
    }

    if (-not $ConfigData.allowImmediateNextFocus -and $text -match '(?im)^##\s+\d*\.?\s*Immediate Next Focus\s*$|^##\s+Immediate Next Focus\s*$') {
        Add-Finding -Severity warning -Code 'R008-IMMEDIATE-NEXT-FOCUS-DISALLOWED' -Message 'Immediate Next Focus section is disallowed by config.' -RecommendedAction 'Use the single active release as the execution focus instead.'
    }
}

function Write-Findings {
    if ($script:Findings.Count -eq 0) {
        Write-Host 'Roadmap structure validation passed.'
        return
    }
    Write-Host 'Roadmap structure findings:'
    foreach ($f in @($script:Findings)) {
        $location = if ($f.Release) { " release $($f.Release)" } else { '' }
        if ($f.Line -gt 0) { $location += " line $($f.Line)" }
        Write-Host ("  [{0}] {1}{2} - {3}" -f $f.severity.ToUpperInvariant(), $f.code, $location, $f.message)
        if (-not [string]::IsNullOrWhiteSpace($f.recommendedAction)) {
            Write-Host "      Action: $($f.recommendedAction)"
        }
    }
}

if (-not $LoadFunctionsOnly) {
    $configData = Merge-Config -ConfigPath $Config
    Invoke-StructureValidation -RoadmapPath $Path -ConfigData $configData
    Write-Findings

    if (-not [string]::IsNullOrWhiteSpace($JsonOut)) {
        $parent = Split-Path -Parent $JsonOut
        if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        @($script:Findings) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $JsonOut -Encoding UTF8
    }

    if (-not [string]::IsNullOrWhiteSpace($CsvOut)) {
        $parent = Split-Path -Parent $CsvOut
        if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        @($script:Findings) | Export-Csv -LiteralPath $CsvOut -NoTypeInformation -Encoding UTF8
    }

    $hasError = @($script:Findings | Where-Object { $_.severity -eq 'error' }).Count -gt 0
    if ($FailOnError -and $hasError) { exit 1 }
    exit 0
}

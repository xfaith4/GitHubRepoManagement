<#
.SYNOPSIS
    Validates ROADMAP.md structural integrity for the GitHub Repo Management
    portfolio execution console.

.DESCRIPTION
    Read-only static analysis of ROADMAP.md. Detects:
      - Release headings out of numerical order
      - Missing release sections referenced by an "Immediate Next Focus"
      - Releases missing required sub-sections (Goal / Product outcomes /
        Engineering milestones / Acceptance criteria)
      - Title vs goal mismatches via simple keyword heuristics
      - Completed-section dominance (active roadmap drowned in history)
      - Duplicate release headings
      - Unchecked future releases with no acceptance criteria
      - Missing Release 1.2 when later 1.x releases exist

    The script does not modify the roadmap. Findings are emitted to the
    console (always) and optionally to JSON or CSV files.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Path
    Path to ROADMAP.md. Defaults to ./ROADMAP.md.

.PARAMETER JsonOut
    Optional path; when supplied, structured findings are written as JSON.

.PARAMETER CsvOut
    Optional path; when supplied, flat findings are written as CSV.

.PARAMETER FailOnError
    When set, the script exits with a non-zero code if any error-severity
    finding is reported. Default is exit 0 regardless (warnings are
    informational).

.EXAMPLE
    pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md

.EXAMPLE
    pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md -JsonOut ./out/roadmap-findings.json -CsvOut ./out/roadmap-findings.csv

.EXAMPLE
    # CI gate (will fail the build only on error-severity findings)
    pwsh ./tools/Test-RoadmapStructure.ps1 -FailOnError

.NOTES
    No external modules required. Uses only built-in .NET types and core
    cmdlets so it runs anywhere PowerShell does.
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Path = './ROADMAP.md',
    [Parameter()][string]$JsonOut = '',
    [Parameter()][string]$CsvOut = '',
    [Parameter()][switch]$FailOnError
)

# StrictMode Latest catches typos and missing properties — keep it on.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants — each finding carries a stable code so consumers can suppress.
# ---------------------------------------------------------------------------

$script:RequiredReleaseSections = @(
    'Goal',
    'Product outcomes',
    'Engineering milestones',
    'Acceptance criteria'
)

# Heuristic title-vs-goal keyword pairs. Hit if the title contains the LHS
# but the goal text does NOT contain any RHS keyword (or vice versa).
$script:TitleGoalKeywords = @{
    'Authentication' = @('auth','token','api key','tls','https','cors')
    'Containerized'  = @('docker','container','image','compose')
    'Persistent'     = @('sqlite','database','db','sql','schema')
    'Onboarding'     = @('setup','wizard','first-run','onboard')
    'Analytics'      = @('chart','trend','graph','sparkline','dashboard')
    'Repair'         = @('repair','fix','rewrite','standardiz')
    'Evaluation'     = @('evaluat','assess','suggest','score')
    'Status'         = @('status','badge','dirty','ahead','behind','stash')
    'Mission'        = @('lifecycle','assess','collection','portfolio')
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Emit a finding into the global findings list. Severity is one of
# 'error', 'warning', 'info'.
function Add-Finding {
    param(
        [Parameter(Mandatory=$true)][string]$Severity,
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter()][string]$Release = '',
        [Parameter()][int]$Line = 0,
        [Parameter()][string]$RecommendedAction = ''
    )
    [void]$script:Findings.Add([pscustomobject]@{
        severity          = $Severity
        code              = $Code
        message           = $Message
        release           = $Release
        line              = $Line
        recommendedAction = $RecommendedAction
    })
}

# Parse "1.2.3" or "1.2" into a sortable [version]-like tuple.
# Use $($var):suffix interpolation throughout this script for PS 5.1 safety.
function ConvertTo-VersionTuple {
    param([Parameter(Mandatory=$true)][string]$VersionText)

    $parts = $VersionText -split '\.'
    $major = 0; $minor = 0; $patch = 0
    if ($parts.Count -ge 1) { [void][int]::TryParse($parts[0], [ref]$major) }
    if ($parts.Count -ge 2) { [void][int]::TryParse($parts[1], [ref]$minor) }
    if ($parts.Count -ge 3) { [void][int]::TryParse($parts[2], [ref]$patch) }

    # Use a sortable composite key: 1000000 * major + 1000 * minor + patch.
    return [int64](($major * 1000000) + ($minor * 1000) + $patch)
}

# Compare two version tuples for ordering.
function Test-VersionLessThan {
    param([int64]$A, [int64]$B)
    return $A -lt $B
}

# Build a lookup of release section -> { title; goal; rawText; line; sortKey }.
function Get-ReleaseSections {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string[]]$Lines)

    $releases = [System.Collections.Generic.List[object]]::new()
    $current = $null
    $headingRegex = '^#{2,3}\s+Release\s+(\d+(?:\.\d+){1,2})\s*[-—–]\s*(.+?)\s*$'

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($line -match $headingRegex) {
            # Close out the previous release block before starting a new one.
            if ($null -ne $current) {
                $current.endLine = $i - 1
                $current.rawText = ($Lines[$current.startLine..($i - 1)] -join "`n")
                [void]$releases.Add([pscustomobject]$current)
            }

            $current = [ordered]@{
                version   = $matches[1]
                title     = $matches[2].Trim()
                startLine = $i
                endLine   = $Lines.Count - 1
                rawText   = ''
                sortKey   = (ConvertTo-VersionTuple -VersionText $matches[1])
            }
            continue
        }

        # Stop accumulating a release block when we hit the next section-level
        # heading that is NOT a release heading. The refactored roadmap nests
        # releases under active/future groups, so accept both ## and ###.
        if ($null -ne $current -and $line -match '^#{2,3}\s+' -and $line -notmatch $headingRegex) {
            $current.endLine = $i - 1
            $current.rawText = ($Lines[$current.startLine..($i - 1)] -join "`n")
            [void]$releases.Add([pscustomobject]$current)
            $current = $null
        }
    }

    # Final flush.
    if ($null -ne $current) {
        $current.rawText = ($Lines[$current.startLine..$current.endLine] -join "`n")
        [void]$releases.Add([pscustomobject]$current)
    }

    return $releases
}

# Extract the "Goal" sentence from a release's raw text, if present.
function Get-ReleaseGoalText {
    param([Parameter(Mandatory=$true)][string]$RawText)

    # Match "**Goal:**" or "Goal:" at the start of a line, capture the
    # sentence (one paragraph) that follows.
    $m = [regex]::Match($RawText, '(?im)^\*{0,2}Goal\*{0,2}\s*:\s*(.+?)(?:\r?\n\r?\n|\r?\n#|\Z)', 'Singleline')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

# Test whether a release section contains a given heading or bold label.
# We accept both '### Heading' and '**Heading**' framings.
function Test-ReleaseHasSection {
    param(
        [Parameter(Mandatory=$true)][string]$RawText,
        [Parameter(Mandatory=$true)][string]$SectionName
    )

    $escaped = [regex]::Escape($SectionName)
    if ($RawText -match "(?im)^#{2,4}\s+$escaped\s*$")         { return $true }
    if ($RawText -match "(?im)^\*\*$escaped\*\*\s*:?\s*")      { return $true }
    if ($RawText -match "(?im)^\*\*$escaped\s*:?\*\*\s*")      { return $true }
    return $false
}

# Count checked vs unchecked checkboxes in the release.
function Get-ReleaseCheckboxStats {
    param([Parameter(Mandatory=$true)][string]$RawText)

    $checked   = ([regex]::Matches($RawText, '(?im)^\s*-\s+\[[xX]\]')).Count
    $unchecked = ([regex]::Matches($RawText, '(?im)^\s*-\s+\[\s\]')).Count
    return [pscustomobject]@{ checked = $checked; unchecked = $unchecked }
}

# Print findings to console with color, grouped by severity.
function Write-FindingsToConsole {
    param([Parameter(Mandatory=$true)][object[]]$Findings)

    # Make grouping safe even when zero findings of a severity exist.
    $errs  = @($Findings | Where-Object { $_.severity -eq 'error' })
    $warns = @($Findings | Where-Object { $_.severity -eq 'warning' })
    $info  = @($Findings | Where-Object { $_.severity -eq 'info' })

    Write-Host ''
    Write-Host '== ROADMAP.md Structural Validation ==' -ForegroundColor Cyan
    Write-Host ('  Errors:   {0}' -f $errs.Count)  -ForegroundColor $(if ($errs.Count  -gt 0) { 'Red'    } else { 'Green' })
    Write-Host ('  Warnings: {0}' -f $warns.Count) -ForegroundColor $(if ($warns.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ('  Info:     {0}' -f $info.Count)  -ForegroundColor 'DarkGray'
    Write-Host ''

    foreach ($group in @(
        @{ Items = $errs;  Color = 'Red';      Tag = '[ERROR]  ' },
        @{ Items = $warns; Color = 'Yellow';   Tag = '[WARN]   ' },
        @{ Items = $info;  Color = 'DarkGray'; Tag = '[INFO]   ' }
    )) {
        foreach ($f in $group.Items) {
            $rel = if ([string]::IsNullOrWhiteSpace($f.release)) { '' } else { (' release={0}' -f $f.release) }
            $ln  = if ([int]$f.line -gt 0) { (' line={0}' -f $f.line) } else { '' }
            Write-Host ('{0}{1} {2}{3}{4}' -f $group.Tag, $f.code, $f.message, $rel, $ln) -ForegroundColor $group.Color
            if (-not [string]::IsNullOrWhiteSpace($f.recommendedAction)) {
                Write-Host ('           -> {0}' -f $f.recommendedAction) -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ''
}

# Export findings to a JSON file. Uses [System.IO.Path] for parent-dir
# extraction (Split-Path is fine here too, but the spec asks for the
# .NET method).
function Export-FindingsJson {
    param(
        [Parameter(Mandatory=$true)][object[]]$Findings,
        [Parameter(Mandatory=$true)][string]$OutPath
    )
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutPath))
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    ($Findings | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host ('JSON findings written: {0}' -f $OutPath) -ForegroundColor Cyan
}

# Export findings to CSV (flat one-row-per-finding format).
function Export-FindingsCsv {
    param(
        [Parameter(Mandatory=$true)][object[]]$Findings,
        [Parameter(Mandatory=$true)][string]$OutPath
    )
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutPath))
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $Findings | Select-Object severity, code, message, release, line, recommendedAction |
        Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8
    Write-Host ('CSV findings written: {0}' -f $OutPath) -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Validation rules — each adds findings to $script:Findings.
# ---------------------------------------------------------------------------

# Rule R001: detect duplicate release headings.
function Invoke-RuleDuplicateReleases {
    param([Parameter(Mandatory=$true)][object[]]$Releases)

    $byVersion = @{}
    foreach ($r in $Releases) {
        if ($byVersion.ContainsKey($r.version)) {
            Add-Finding -Severity 'error' -Code 'R001-DUP-RELEASE' `
                -Message ("Duplicate release heading for $($r.version): " + $r.title) `
                -Release $r.version -Line ($r.startLine + 1) `
                -RecommendedAction 'Merge or rename the duplicate release section.'
        } else {
            $byVersion[$r.version] = $r
        }
    }
}

# Rule R002: detect releases that appear out of numerical order.
function Invoke-RuleReleaseOrder {
    param([Parameter(Mandatory=$true)][object[]]$Releases)

    for ($i = 1; $i -lt $Releases.Count; $i++) {
        $prev = $Releases[$i - 1]
        $cur  = $Releases[$i]
        if (Test-VersionLessThan -A $cur.sortKey -B $prev.sortKey) {
            Add-Finding -Severity 'warning' -Code 'R002-RELEASE-ORDER' `
                -Message ("Release $($cur.version) appears after $($prev.version) but is numerically lower") `
                -Release $cur.version -Line ($cur.startLine + 1) `
                -RecommendedAction 'Reorder release sections in ascending version order.'
        }
    }
}

# Rule R003: detect missing 1.2 when later 1.x exist.
function Invoke-RuleMissing12 {
    param([Parameter(Mandatory=$true)][object[]]$Releases)

    $has12 = @($Releases | Where-Object { $_.version -eq '1.2' }).Count -gt 0
    $hasLater1x = @($Releases | Where-Object {
        $parts = $_.version -split '\.'
        if ($parts.Count -ge 2) {
            $maj = 0; $min = 0
            [void][int]::TryParse($parts[0], [ref]$maj)
            [void][int]::TryParse($parts[1], [ref]$min)
            ($maj -eq 1 -and $min -gt 2)
        } else { $false }
    }).Count -gt 0

    if ((-not $has12) -and $hasLater1x) {
        Add-Finding -Severity 'error' -Code 'R003-MISSING-1.2' `
            -Message 'Release 1.2 is missing from the main release list, but later 1.x releases exist.' `
            -RecommendedAction 'Add a Release 1.2 section in its proper position, or document why it was skipped.'
    }
}

# Rule R004: every release must have Goal / Product outcomes / Engineering
# milestones / Acceptance criteria sub-sections.
function Invoke-RuleRequiredSections {
    param([Parameter(Mandatory=$true)][object[]]$Releases)

    foreach ($r in $Releases) {
        foreach ($section in $script:RequiredReleaseSections) {
            if (-not (Test-ReleaseHasSection -RawText $r.rawText -SectionName $section)) {
                Add-Finding -Severity 'warning' -Code 'R004-MISSING-SECTION' `
                    -Message ("Release " + $r.version + ' is missing required sub-section: ' + $section) `
                    -Release $r.version -Line ($r.startLine + 1) `
                    -RecommendedAction ('Add a `' + $section + '` sub-section to the release.')
            }
        }
    }
}

# Rule R005: simple title-vs-goal keyword mismatch heuristic.
function Invoke-RuleTitleGoalMismatch {
    param([Parameter(Mandatory=$true)][object[]]$Releases)

    foreach ($r in $Releases) {
        $goal = Get-ReleaseGoalText -RawText $r.rawText
        if ([string]::IsNullOrWhiteSpace($goal)) { continue }

        foreach ($titleKeyword in $script:TitleGoalKeywords.Keys) {
            if ($r.title -match [regex]::Escape($titleKeyword)) {
                $expected = $script:TitleGoalKeywords[$titleKeyword]
                $hit = $false
                foreach ($e in $expected) {
                    if ($goal -match [regex]::Escape($e)) { $hit = $true; break }
                }
                if (-not $hit) {
                    Add-Finding -Severity 'warning' -Code 'R005-TITLE-GOAL-MISMATCH' `
                        -Message ("Release " + $r.version + " title mentions '" + $titleKeyword + "' but goal text contains none of: " + ($expected -join ', ')) `
                        -Release $r.version -Line ($r.startLine + 1) `
                        -RecommendedAction 'Confirm the release title and goal describe the same scope.'
                }
            }
        }
    }
}

# Rule R006: detect "Immediate Next Focus" referencing a release that is
# not in the main list. The active roadmap should not have a side channel.
function Invoke-RuleImmediateNextFocus {
    param(
        [Parameter(Mandatory=$true)][string]$RoadmapText,
        [Parameter(Mandatory=$true)][object[]]$Releases
    )

    $section = [regex]::Match($RoadmapText, '(?ims)^##\s+\d*\.?\s*Immediate\s+Next\s+Focus.*?(?=^##\s+|\Z)')
    if (-not $section.Success) { return }

    Add-Finding -Severity 'warning' -Code 'R006-IMMEDIATE-NEXT-FOCUS-PRESENT' `
        -Message '"Immediate Next Focus" section is present. Prefer a "Current Active Release" pointer in the release roadmap.' `
        -RecommendedAction 'Remove the "Immediate Next Focus" section once the active release is identified at the top of section 5.'

    foreach ($refMatch in [regex]::Matches($section.Value, 'Release\s+(\d+(?:\.\d+){1,2})')) {
        $refVersion = $refMatch.Groups[1].Value
        $exists = @($Releases | Where-Object { $_.version -eq $refVersion }).Count -gt 0
        if (-not $exists) {
            Add-Finding -Severity 'error' -Code 'R006-DANGLING-NEXT-FOCUS' `
                -Message ('"Immediate Next Focus" references Release ' + $refVersion + ' but no such release section exists.') `
                -RecommendedAction 'Promote the referenced release into the main release list, or update the focus pointer.'
        }
    }
}

# Rule R007: future / unchecked release with no acceptance criteria.
function Invoke-RuleUncheckedNoAcceptance {
    param([Parameter(Mandatory=$true)][object[]]$Releases)

    foreach ($r in $Releases) {
        $stats = Get-ReleaseCheckboxStats -RawText $r.rawText
        if ($stats.unchecked -gt 0 -and $stats.checked -eq 0) {
            if (-not (Test-ReleaseHasSection -RawText $r.rawText -SectionName 'Acceptance criteria')) {
                Add-Finding -Severity 'warning' -Code 'R007-UNCHECKED-NO-ACCEPTANCE' `
                    -Message ('Future release ' + $r.version + ' has unchecked items but no acceptance criteria section.') `
                    -Release $r.version -Line ($r.startLine + 1) `
                    -RecommendedAction 'Add acceptance criteria so the release is judged complete in observable terms.'
            }
        }
    }
}

# Rule R008: completed sections dominate the active roadmap (heuristic).
# Active body weight = chars outside completed-release sections.
function Invoke-RuleCompletedDominance {
    param(
        [Parameter(Mandatory=$true)][string]$RoadmapText,
        [Parameter(Mandatory=$true)][object[]]$Releases
    )

    $totalLen = $RoadmapText.Length
    if ($totalLen -eq 0) { return }

    $completedLen = 0
    foreach ($r in $Releases) {
        $stats = Get-ReleaseCheckboxStats -RawText $r.rawText
        if ($stats.unchecked -eq 0 -and $stats.checked -gt 0) {
            $completedLen += $r.rawText.Length
        }
    }

    $ratio = [math]::Round(($completedLen / $totalLen), 3)
    if ($ratio -gt 0.55) {
        Add-Finding -Severity 'info' -Code 'R008-COMPLETED-DOMINANCE' `
            -Message ('Completed-release content occupies ' + ($ratio * 100) + '% of ROADMAP.md.') `
            -RecommendedAction 'Move completed releases to docs/history/completed-releases.md to keep the active roadmap scannable.'
    }
}

# Rule R009: missing implementation-state vocabulary section.
function Invoke-RuleStateVocabulary {
    param([Parameter(Mandatory=$true)][string]$RoadmapText)

    $hasVocab = $RoadmapText -match '(?im)^##\s+\d*\.?\s*Implementation[- ]State Vocabulary'
    if (-not $hasVocab) {
        Add-Finding -Severity 'info' -Code 'R009-MISSING-STATE-VOCAB' `
            -Message 'Roadmap does not declare an Implementation-State Vocabulary section.' `
            -RecommendedAction 'Add a vocabulary section so [x] checkboxes carry consistent meaning (planned / scaffolded / backend-complete / ui-connected / smoke-tested / operator-verified / done).'
    }
}

# Rule R010: ROADMAP.md should not be excessively long for an active doc.
# Threshold is intentionally generous; warning only.
function Invoke-RuleFileLength {
    param([Parameter(Mandatory=$true)][int]$LineCount)
    if ($LineCount -gt 900) {
        Add-Finding -Severity 'warning' -Code 'R010-FILE-LENGTH' `
            -Message ('ROADMAP.md is ' + $LineCount + ' lines long. Active roadmaps should be scannable.') `
            -RecommendedAction 'Move completed-release detail to docs/history/completed-releases.md.'
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Initialize accumulator. Use a script-scoped list so rule functions can
# append without passing the list around.
$script:Findings = [System.Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host ('ERROR: ROADMAP.md not found at: ' + $Path) -ForegroundColor Red
    exit 2
}

# Read once. Lines for line-number reporting; full text for whole-file rules.
$lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path).Path)
$text  = ($lines -join "`n")

$releases = Get-ReleaseSections -Lines $lines

if ($releases.Count -eq 0) {
    Add-Finding -Severity 'error' -Code 'R000-NO-RELEASES' `
        -Message 'No "## Release X.Y — Title" headings found in the file.' `
        -RecommendedAction 'Confirm this is the correct ROADMAP.md and that release headings follow the canonical format.'
}

Invoke-RuleDuplicateReleases     -Releases $releases
Invoke-RuleReleaseOrder          -Releases $releases
Invoke-RuleMissing12             -Releases $releases
Invoke-RuleRequiredSections      -Releases $releases
Invoke-RuleTitleGoalMismatch     -Releases $releases
Invoke-RuleImmediateNextFocus    -RoadmapText $text -Releases $releases
Invoke-RuleUncheckedNoAcceptance -Releases $releases
Invoke-RuleCompletedDominance    -RoadmapText $text -Releases $releases
Invoke-RuleStateVocabulary       -RoadmapText $text
Invoke-RuleFileLength            -LineCount $lines.Count

# Pretty-print release sequence summary so the operator sees what was parsed.
Write-Host ''
Write-Host ('Releases found ({0}):' -f $releases.Count) -ForegroundColor Cyan
foreach ($r in $releases) {
    Write-Host ('  {0,-7}  {1}' -f $r.version, $r.title) -ForegroundColor DarkGray
}

# Summary + per-finding output.
$findingsArray = @($script:Findings)
Write-FindingsToConsole -Findings $findingsArray

if (-not [string]::IsNullOrWhiteSpace($JsonOut)) {
    Export-FindingsJson -Findings $findingsArray -OutPath $JsonOut
}
if (-not [string]::IsNullOrWhiteSpace($CsvOut)) {
    Export-FindingsCsv -Findings $findingsArray -OutPath $CsvOut
}

# Exit code policy:
# - default exit 0 (warnings are informational)
# - if -FailOnError supplied, exit 1 when any error-severity finding present
$errCount = @($findingsArray | Where-Object { $_.severity -eq 'error' }).Count
if ($FailOnError -and $errCount -gt 0) {
    exit 1
}
exit 0

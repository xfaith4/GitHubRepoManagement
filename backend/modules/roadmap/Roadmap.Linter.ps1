<#
.SYNOPSIS
    Roadmap content linter for Release 1.1.
.DESCRIPTION
    Provides one exported function:

      Invoke-LintRoadmapContent
        Runs a suite of lint rules against raw ROADMAP.md content and returns
        structured findings with severity, line numbers, and recommended actions.

    Rules:
      LINT-001 (error)   Release headings must match '## Release X.Y — Title'
      LINT-002 (error)   Checkbox items must use '- [ ]' or '- [x]' format
      LINT-003 (warning) Required 'Product Intent' (or similar) section must exist
      LINT-004 (warning) Required completed-work section must exist
      LINT-005 (warning) Each release section should have at least one checklist item
      LINT-006 (info)    Vague checklist item text detected
      LINT-007 (info)    Release version numbers should not have gaps

.NOTES
    Dot-source this file to load the function:
        . (Join-Path $moduleRoot 'Roadmap.Linter.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _BuildFinding {
    param(
        [string]$RuleId,
        [string]$Severity,
        [string]$Message,
        [object]$Line,
        [string]$RecommendedAction
    )
    return [pscustomobject]@{
        ruleId            = $RuleId
        severity          = $Severity
        message           = $Message
        line              = $Line
        recommendedAction = $RecommendedAction
    }
}

# LINT-001: Release headings must match '## Release X.Y — Title'
function _LintRule001 {
    param([string[]]$Lines)
    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    # Pattern: a line that starts a release heading but is malformed
    $releaseHeading  = [regex]'^##\s+Release\s+'
    $validHeading    = [regex]'^##\s+Release\s+\d+\.\d+\s+[—–-]'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($releaseHeading.IsMatch($line) -and -not $validHeading.IsMatch($line)) {
            $findings.Add((_BuildFinding `
                -RuleId 'LINT-001' `
                -Severity 'error' `
                -Message "Release heading on line $($i+1) does not match required format '## Release X.Y — Title': '$line'" `
                -Line ($i + 1) `
                -RecommendedAction "Rename to '## Release X.Y — Short Title' using a major.minor version and an em-dash (—) separator."
            ))
        }
    }
    return $findings
}

# LINT-002: Checkbox items must use '- [ ]' or '- [x]' format
function _LintRule002 {
    param([string[]]$Lines)
    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    # A valid checkbox is exactly: optional-indent dash single-space [ or x ] whitespace-or-EOL
    $validCheckbox = [regex]'^\s*-\s\[(x| )\](\s|$)'
    # Detect lines that look like checkbox attempts but are malformed
    $malformedPatterns = @(
        [regex]'^\s*-\s*\[\]',          # - [] (empty brackets, no space)
        [regex]'^\s*-\s*\[\s{2,}\]',    # - [  ] (two or more spaces inside brackets)
        [regex]'^\s*-\[\s',             # -[ ] (no space between dash and bracket)
        [regex]'^\s*\*\s*\[(x| )\]',   # * [ ] (asterisk instead of dash)
        [regex]'^\s*-\s+\[',           # -  [ ] (multiple spaces between dash and bracket)
        [regex]'^\s*-\s\[(?!(?:x| )\])' # - [anything other than single 'x' or single ' ']
    )
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        # Skip lines that are already valid
        if ($validCheckbox.IsMatch($line)) { continue }
        foreach ($pattern in $malformedPatterns) {
            if ($pattern.IsMatch($line)) {
                $findings.Add((_BuildFinding `
                    -RuleId 'LINT-002' `
                    -Severity 'error' `
                    -Message "Malformed checkbox on line $($i+1): '$($line.Trim())'" `
                    -Line ($i + 1) `
                    -RecommendedAction "Use '- [ ] Task description' for pending or '- [x] Task description' for completed items."
                ))
                break
            }
        }
    }
    return $findings
}

# LINT-003: Required 'Product Intent' (or similar) heading must exist
function _LintRule003 {
    param([string]$Content)
    $intentPattern = [regex]'(?im)^#+\s*(product\s+intent|product\s+scope|overview|about|purpose|background|what\s+this\s+(does|is))'
    if (-not $intentPattern.IsMatch($Content)) {
        return @(_BuildFinding `
            -RuleId 'LINT-003' `
            -Severity 'warning' `
            -Message "No 'Product Intent' (or equivalent) section found." `
            -Line $null `
            -RecommendedAction "Add a '## Product Intent' section describing what this project does and why it exists."
        )
    }
    return @()
}

# LINT-004: Required completed-work section must exist
function _LintRule004 {
    param([string]$Content)
    $completedPattern = [regex]'(?im)^#+\s*(recently\s+completed|completed|done|shipped|released|what.s\s+(been\s+)?done|history)'
    if (-not $completedPattern.IsMatch($Content)) {
        return @(_BuildFinding `
            -RuleId 'LINT-004' `
            -Severity 'warning' `
            -Message "No completed-work section found (e.g. 'Recently Completed', 'Shipped', 'Done')." `
            -Line $null `
            -RecommendedAction "Add a '## Recently Completed' section to document previously shipped work."
        )
    }
    return @()
}

# LINT-005: Each release section should have at least one checklist item
function _LintRule005 {
    param([string[]]$Lines)
    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $releaseHeading = [regex]'^##\s+Release\s+'
    $checkboxItem   = [regex]'^\s*-\s\[(x| )\]'
    $anyHeading     = [regex]'^#{1,6}\s+'

    $currentRelease = $null
    $currentLine    = 0
    $hasChecklist   = $false

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($releaseHeading.IsMatch($line)) {
            # Flush previous release section
            if ($null -ne $currentRelease -and -not $hasChecklist) {
                $findings.Add((_BuildFinding `
                    -RuleId 'LINT-005' `
                    -Severity 'warning' `
                    -Message "Release section '$currentRelease' (line $currentLine) has no checklist items." `
                    -Line $currentLine `
                    -RecommendedAction "Add at least one '- [ ] Task' item to this release section."
                ))
            }
            $currentRelease = $line.Trim()
            $currentLine    = $i + 1
            $hasChecklist   = $false
        } elseif ($null -ne $currentRelease) {
            if ($checkboxItem.IsMatch($line)) {
                $hasChecklist = $true
            } elseif ($anyHeading.IsMatch($line) -and $releaseHeading.IsMatch($line) -eq $false) {
                # Sub-heading inside release section - keep tracking
            }
        }
    }
    # Flush final release section
    if ($null -ne $currentRelease -and -not $hasChecklist) {
        $findings.Add((_BuildFinding `
            -RuleId 'LINT-005' `
            -Severity 'warning' `
            -Message "Release section '$currentRelease' (line $currentLine) has no checklist items." `
            -Line $currentLine `
            -RecommendedAction "Add at least one '- [ ] Task' item to this release section."
        ))
    }
    return $findings
}

# LINT-006: Vague checklist item text
function _LintRule006 {
    param([string[]]$Lines)
    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $checkboxItem   = [regex]'^\s*-\s\[(x| )\]\s+(.+)$'
    $vagueWords     = @('\bimprove\b', '\bfix\b', '\brefactor\b', '\bfinish\b', '\bupdate\b',
                        '\badd\b', '\bdo\b', '\btodo\b', '\bmisc\b', '\bcleanup\b', '\bclean up\b',
                        '\bvarious\b', '\bother\b', '\bstuff\b', '\bthings\b')
    $vaguePattern   = [regex]("(?i)(" + ($vagueWords -join '|') + ")")

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $m = $checkboxItem.Match($line)
        if ($m.Success) {
            $itemText = $m.Groups[2].Value.Trim()
            if ($vaguePattern.IsMatch($itemText)) {
                $findings.Add((_BuildFinding `
                    -RuleId 'LINT-006' `
                    -Severity 'info' `
                    -Message "Vague checklist item on line $($i+1): '$itemText'" `
                    -Line ($i + 1) `
                    -RecommendedAction "Replace vague language with a concrete, specific task description (what, why, acceptance criteria)."
                ))
            }
        }
    }
    return $findings
}

# LINT-007: Release version numbers should not have gaps
function _LintRule007 {
    param([string[]]$Lines)
    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $versionPattern = [regex]'^##\s+Release\s+(\d+)\.(\d+)'
    $versions = [System.Collections.Generic.List[pscustomobject]]::new()

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $m = $versionPattern.Match($Lines[$i])
        if ($m.Success) {
            $versions.Add([pscustomobject]@{
                major = [int]$m.Groups[1].Value
                minor = [int]$m.Groups[2].Value
                line  = $i + 1
            })
        }
    }

    if ($versions.Count -lt 2) { return $findings }

    # Group by major, sort by minor within each major and detect gaps
    $byMajor = $versions | Group-Object -Property major
    foreach ($group in $byMajor) {
        $sorted = @($group.Group | Sort-Object minor)
        for ($j = 1; $j -lt $sorted.Count; $j++) {
            $prev = $sorted[$j - 1]
            $curr = $sorted[$j]
            if ($curr.minor - $prev.minor -gt 1) {
                $missing = ($prev.minor + 1)..($curr.minor - 1) | ForEach-Object { "$($group.Name).$_" }
                $missingStr = $missing -join ', '
                $findings.Add((_BuildFinding `
                    -RuleId 'LINT-007' `
                    -Severity 'info' `
                    -Message "Version gap detected between $($group.Name).$($prev.minor) and $($group.Name).$($curr.minor). Missing: $missingStr" `
                    -Line $curr.line `
                    -RecommendedAction "Either add the missing release sections or renumber releases to be sequential."
                ))
            }
        }
    }
    return $findings
}

# ---------------------------------------------------------------------------
# Invoke-LintRoadmapContent
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Run all roadmap lint rules against raw markdown content.
.PARAMETER RawContent
    The raw string content of ROADMAP.md.
.PARAMETER RepoName
    The repository name (used for reporting only).
.OUTPUTS
    [pscustomobject] with repoName, lintPassed, findings, summary, lintedAt.
#>
function Invoke-LintRoadmapContent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RawContent,

        [Parameter(Mandatory = $true)]
        [string]$RepoName
    )

    $allFindings = [System.Collections.Generic.List[pscustomobject]]::new()

    if ([string]::IsNullOrWhiteSpace($RawContent)) {
        $allFindings.Add((_BuildFinding `
            -RuleId 'LINT-000' `
            -Severity 'error' `
            -Message 'Roadmap content is empty or missing.' `
            -Line $null `
            -RecommendedAction 'Create a ROADMAP.md file with content before linting.'
        ))
        return [pscustomobject]@{
            repoName   = $RepoName
            lintPassed = $false
            findings   = $allFindings.ToArray()
            summary    = '1 finding(s): 1 error(s), 0 warning(s), 0 info(s). Lint FAILED.'
            lintedAt   = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    # Guard against pathologically large content that would produce meaningless results
    $script:MaxLintSizeBytes = 512 * 1024   # 512 KB
    $script:MaxLintLines     = 5000

    # Normalise line endings and split early so we can check line count
    $lines = $RawContent -replace "`r`n", "`n" -replace "`r", "`n" -split "`n"

    if ($RawContent.Length -gt $script:MaxLintSizeBytes -or $lines.Count -gt $script:MaxLintLines) {
        $allFindings.Add((_BuildFinding `
            -RuleId 'LINT-SIZE' `
            -Severity 'warning' `
            -Message "Roadmap content is large ($($lines.Count) lines, $([Math]::Round($RawContent.Length / 1024, 1)) KB) — content has been truncated to the first $($script:MaxLintLines) lines for linting. Results may be incomplete." `
            -Line $null `
            -RecommendedAction 'Consider splitting the roadmap into smaller release-scoped files.'
        ))
    }

    # Trim to the maximum line budget before running any per-line rule
    if ($lines.Count -gt $script:MaxLintLines) {
        $lines = $lines[0..($script:MaxLintLines - 1)]
    }

    foreach ($finding in (_LintRule001 -Lines $lines))         { $allFindings.Add($finding) }
    foreach ($finding in (_LintRule002 -Lines $lines))         { $allFindings.Add($finding) }
    foreach ($finding in (_LintRule003 -Content $RawContent))  { $allFindings.Add($finding) }
    foreach ($finding in (_LintRule004 -Content $RawContent))  { $allFindings.Add($finding) }
    foreach ($finding in (_LintRule005 -Lines $lines))         { $allFindings.Add($finding) }
    foreach ($finding in (_LintRule006 -Lines $lines))         { $allFindings.Add($finding) }
    foreach ($finding in (_LintRule007 -Lines $lines))         { $allFindings.Add($finding) }

    $errors   = @($allFindings | Where-Object { $_.severity -eq 'error'   }).Count
    $warnings = @($allFindings | Where-Object { $_.severity -eq 'warning' }).Count
    $infos    = @($allFindings | Where-Object { $_.severity -eq 'info'    }).Count
    $passed   = ($errors -eq 0)
    $status   = if ($passed) { 'PASSED' } else { 'FAILED' }
    $summary  = "$($allFindings.Count) finding(s): $errors error(s), $warnings warning(s), $infos info(s). Lint $status."

    return [pscustomobject]@{
        repoName   = $RepoName
        lintPassed = $passed
        findings   = $allFindings.ToArray()
        summary    = $summary
        lintedAt   = (Get-Date).ToUniversalTime().ToString('o')
    }
}


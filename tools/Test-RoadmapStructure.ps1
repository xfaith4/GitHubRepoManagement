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
            - Active release pointer/detail mismatches
      - Title vs goal mismatches via simple keyword heuristics
      - Completed-section dominance (active roadmap drowned in history)
            - Completed release detail that should live in the archive
      - Duplicate release headings
      - Unchecked future releases with no acceptance criteria
            - Overgrown future release sections that should be summarized
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

.PARAMETER Config
    Optional path to a roadmap-validation.config.json file. When omitted, the
    script auto-discovers config at standards/roadmap/roadmap-validation.config.json
    or tools/roadmap-validation.config.json (relative to the roadmap or the
    script). When supplied explicitly and the file is missing or malformed, an
    RQ000-CONFIG-ERROR finding is raised (which only fails the build under
    -FailOnError). When no config is present anywhere, built-in defaults apply
    and behavior is identical to the original structure linter plus the new
    quality layer's default rules.

.DESCRIPTION ADDENDUM — Roadmap-quality layer (RQ rules)
    On top of the structural R-rules above, this script evaluates roadmap
    *execution quality* against the canonical release contract documented in
    docs/reference/roadmap-contracts.md:
      - explicit release Status parsing, using the shared status contract in
        standards/roadmap/roadmap-audit-rules.json (detection.releaseStatusPattern
        and detection.statusVocabulary) so this linter, the backend auditor, and
        tools/Test-RoadmapContract.ps1 all read one roadmap the same way
      - validation-plan presence and concreteness
      - acceptance-criteria quality (vague-term heuristics)
      - risks/blockers, dependencies, known-issues/pipeline-feedback sections
      - traceability to issues, PRs, tests, ADRs, workflows, or docs
    These RQ rules are additive and never remove or rename existing fields.

.EXAMPLE
    pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md

.EXAMPLE
    pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md -JsonOut ./out/roadmap-findings.json -CsvOut ./out/roadmap-findings.csv

.EXAMPLE
    # CI gate (will fail the build only on error-severity findings)
    pwsh ./tools/Test-RoadmapStructure.ps1 -FailOnError

.EXAMPLE
    # Use a repo-specific config to override required sections / thresholds
    pwsh ./tools/Test-RoadmapStructure.ps1 -Config ./standards/roadmap/roadmap-validation.config.json

.NOTES
    No external modules required. Uses only built-in .NET types and core
    cmdlets so it runs anywhere PowerShell does (Windows PowerShell 5.1 and
    PowerShell 7+).
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Path = './ROADMAP.md',
    [Parameter()][string]$JsonOut = '',
    [Parameter()][string]$CsvOut = '',
    [Parameter()][switch]$FailOnError,
    [Parameter()][string]$Config = '',
    # Dot-source the script with this switch to load its functions without
    # running the validation pass (used by the Pester suite). Mirrors the
    # convention used elsewhere in this repo.
    [Parameter()][switch]$LoadFunctionsOnly
)

# StrictMode Latest catches typos and missing properties — keep it on.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Defaults — each finding carries a stable code so consumers can suppress.
# These are the built-in defaults. A roadmap-validation.config.json file (when
# present) is merged over them by Get-RoadmapValidationConfig so repo-specific
# opinions can be expressed as data rather than code edits.
# ---------------------------------------------------------------------------

# Canonical default config. Merge-RoadmapValidationConfig overlays file values.
# A plain hashtable (not [ordered]) so dot-access works under StrictMode Latest
# and the alias map exposes .Contains()/indexing.
$script:DefaultConfig = @{
    # Sub-sections every release block must carry (existing R004 behavior).
    requiredSections = @(
        'Goal',
        'Product outcomes',
        'Engineering milestones',
        'Acceptance criteria'
    )
    # Sections strongly expected on active/blocked/validation execution blocks.
    activeReleaseRequiredSections = @(
        'Validation plan',
        'Risks and blockers',
        'Dependencies',
        'Known issues',
        'Traceability'
    )
    # Status contract — MIRROR ONLY. The canonical vocabulary and pattern live
    # in standards/roadmap/roadmap-audit-rules.json under "detection"; see the
    # note below Import-RoadmapStatusContract. Keep byte-identical to the JSON.
    releaseStatusPattern = '(?im)^\s*>?\s*\**\s*Status\s*\**\s*:\s*\**\s*([A-Za-z][A-Za-z \-]*?)\s*\**\s*(?:$|[—–\-(.,;])'
    allowedStatuses = @('planned','active','blocked','validation','done','archived')
    activeStatuses  = @('active')
    statusAliases = @{
        'in progress'  = 'active'
        'in-progress'  = 'active'
        'inprogress'   = 'active'
        'wip'          = 'active'
        'current'      = 'active'
        'ongoing'      = 'active'
        'complete'     = 'done'
        'completed'    = 'done'
        'delivered'    = 'done'
        'shipped'      = 'done'
        'released'     = 'done'
        'finished'     = 'done'
        'pending'      = 'planned'
        'not started'  = 'planned'
        'upcoming'     = 'planned'
        'deferred'     = 'planned'
        'proposed'     = 'planned'
        'on hold'      = 'blocked'
        'paused'       = 'blocked'
        'in review'    = 'validation'
        'review'       = 'validation'
        'validating'   = 'validation'
    }
    # Releases that must exist. '1.2' keeps its special "only required when a
    # later 1.x release exists" semantics (R003); any other listed version is
    # treated as a hard requirement (R003-MISSING-RELEASE).
    requiredReleases = @('1.2')
    maxActiveRoadmapLines = 900
    maxFutureReleaseLines = 120
    allowImmediateNextFocus = $false
    # When true, a missing Implementation-State Vocabulary section is a warning
    # rather than the default info (R009).
    requireImplementationStateVocabulary = $false
    # When true, a done release with unchecked items is an error (RQ008).
    treatDoneWithUncheckedCriteriaAsError = $false
    # When true, planned/future releases missing a Status line emit an info
    # finding (RQ001). Off by default to keep routine output quiet.
    flagMissingStatusOnFutureReleases = $false
    # When true, planned/future releases missing recommended sections
    # (Dependencies -> RQ011, Non-goals -> RQ012) emit info findings. Off by
    # default; "Out of scope" counts as a Non-goals alias.
    flagFutureReleaseRecommendations = $false
    # Concrete validation signals that make a Validation plan meaningful.
    validationSignals = @(
        'npm test','npm run test','npm run build','npm run lint','dotnet test',
        'pytest','invoke-pester','pester','psscriptanalyzer','manual smoke test',
        'smoke test','smoke-test','ci','github actions','deployment verification',
        'api smoke','frontend smoke','backend health check','playwright','curl '
    )
    # Vague acceptance-criteria terms (whole-item, not substrings of real work).
    weakAcceptanceTerms = @(
        'works','work','done','complete','completed','good enough','polish',
        'improve','improved','finalize','finalized','cleanup','clean up','misc',
        'tbd','etc','various'
    )
    # Pipeline / discovered-issue keywords for the known-issues feedback rule.
    pipelineKeywords = @(
        'bug','regression','failed','failure','ci','build','test','lint',
        'security','audit','vulnerability','dependency','blocked','rollback',
        'deployment','smoke'
    )
}

# ---------------------------------------------------------------------------
# Shared status contract
# ---------------------------------------------------------------------------
#
# Status detection is DATA, not code. The canonical pattern and vocabulary live
# in standards/roadmap/roadmap-audit-rules.json under "detection", and the
# backend auditor (backend/modules/roadmap/Roadmap.Auditor.ps1) and the maturity
# scorer (tools/Test-RoadmapContract.ps1) already read them from there.
#
# Until 2026-08-08 this linter carried a third private copy. It knew two aliases
# the pack did not ('pending', 'released') and was missing twelve the pack had
# ('deferred', 'on hold', 'in review', 'paused', ...), so the same roadmap could
# report a clean status here and RQ002-INVALID-STATUS-equivalent divergence in
# the scorer. Its regex was also the more tolerant of the two: it read
# 'Status: done. Shipped 2026-05.', which the 1.3 pack pattern did not match at
# all. Rule pack 1.4 adopts that tolerance rather than dropping it.
#
# The literals in $script:DefaultConfig above are a MIRROR, used only when the
# rule pack is not reachable — this script is designed to run standalone inside
# a managed repo that may not vendor the standards tree. Keep them
# byte-identical to the JSON; do not reintroduce a private vocabulary here.

function Resolve-RoadmapRulePackPath {
    param(
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = ''
    )

    $roots = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) {
        try {
            $rp = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($RoadmapPath))
            if (-not [string]::IsNullOrWhiteSpace($rp)) { [void]$roots.Add($rp) }
        } catch { }
    }
    if ($PSScriptRoot) {
        # tools/ -> repo root is the parent of the script directory.
        [void]$roots.Add((Split-Path -Parent $PSScriptRoot))
        [void]$roots.Add($PSScriptRoot)
    }
    [void]$roots.Add((Get-Location).Path)

    $relatives = @(
        (Join-Path 'standards' (Join-Path 'roadmap' 'roadmap-audit-rules.json')),
        (Join-Path 'spec' (Join-Path 'roadmap-contract' 'roadmap-audit-rules.json'))
    )

    foreach ($root in $roots) {
        foreach ($rel in $relatives) {
            $candidate = Join-Path $root $rel
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return ''
}

# Overlay the rule pack's detection.statusVocabulary / releaseStatusPattern onto
# a config hashtable, in place. Returns a result object describing what happened
# so main can surface a parse failure as a finding (the findings list does not
# exist yet at load time, so this function never calls Add-Finding).
function Import-RoadmapStatusContract {
    param(
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Config,
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = ''
    )

    $result = [pscustomobject]@{ loaded = $false; path = ''; error = '' }

    $packPath = Resolve-RoadmapRulePackPath -RoadmapPath $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($packPath)) { return $result }
    $result.path = $packPath

    try {
        $raw  = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $packPath).Path)
        $pack = ConvertFrom-Json -InputObject $raw
    } catch {
        $result.error = $_.Exception.Message
        return $result
    }

    if (@($pack.PSObject.Properties.Name) -notcontains 'detection') { return $result }
    $d = $pack.detection
    if ($null -eq $d) { return $result }
    $names = @($d.PSObject.Properties.Name)

    if ($names -contains 'releaseStatusPattern' -and -not [string]::IsNullOrWhiteSpace([string]$d.releaseStatusPattern)) {
        $Config['releaseStatusPattern'] = [string]$d.releaseStatusPattern
    }
    if ($names -contains 'statusVocabulary' -and $null -ne $d.statusVocabulary) {
        $sv = @($d.statusVocabulary.PSObject.Properties.Name)
        if ($sv -contains 'allowedStatuses' -and @($d.statusVocabulary.allowedStatuses).Count -gt 0) {
            $Config['allowedStatuses'] = @($d.statusVocabulary.allowedStatuses | ForEach-Object { ([string]$_).ToLowerInvariant() })
        }
        if ($sv -contains 'activeStatuses' -and @($d.statusVocabulary.activeStatuses).Count -gt 0) {
            $Config['activeStatuses'] = @($d.statusVocabulary.activeStatuses | ForEach-Object { ([string]$_).ToLowerInvariant() })
        }
        if ($sv -contains 'statusAliases' -and $null -ne $d.statusVocabulary.statusAliases) {
            $aliasMap = @{}
            foreach ($p in $d.statusVocabulary.statusAliases.PSObject.Properties) {
                $aliasMap[$p.Name.ToLowerInvariant()] = ([string]$p.Value).ToLowerInvariant()
            }
            if ($aliasMap.Count -gt 0) { $Config['statusAliases'] = $aliasMap }
        }
    }

    $result.loaded = $true
    return $result
}

# Apply the shared contract at load time so a dot-sourced session
# (-LoadFunctionsOnly, used by the Pester suite) sees the same vocabulary a
# real run does. A repo-local roadmap-validation.config.json can still override
# these keys through Merge-RoadmapValidationConfig — that is a declared opt-out,
# not a private copy.
$script:StatusContract = Import-RoadmapStatusContract -Config $script:DefaultConfig -RoadmapPath $Path

# Active-config holder; populated in main from defaults + file overrides.
$script:ActiveConfig = $script:DefaultConfig

# Back-compat script vars used by the original R-rules; routed through config.
$script:RequiredReleaseSections = $script:DefaultConfig.requiredSections
$script:MaxActiveRoadmapLines   = $script:DefaultConfig.maxActiveRoadmapLines
$script:MaxFutureReleaseLines   = $script:DefaultConfig.maxFutureReleaseLines

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
        [Parameter()][string]$RecommendedAction = '',
        # Additive metadata fields. Existing consumers ignore these; the six
        # original fields keep their names, order, and meaning.
        [Parameter()][string]$Category = 'structure',
        [Parameter()][string]$Section = '',
        [Parameter()][string]$Rule = ''
    )
    [void]$script:Findings.Add([pscustomobject]@{
        severity          = $Severity
        code              = $Code
        message           = $Message
        release           = $Release
        line              = $Line
        recommendedAction = $RecommendedAction
        category          = $Category
        section           = $Section
        rule              = $Rule
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

function Get-LineCountForText {
    param([Parameter(Mandatory=$true)][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return ([regex]::Matches($Text, "`n")).Count + 1
}

function Get-ActiveReleaseVersion {
    param([Parameter(Mandatory=$true)][string]$RoadmapText)

    $m = [regex]::Match($RoadmapText, '(?im)^>\s*\*\*Active release:\*\*\s*\*\*Release\s+(\d+(?:\.\d+){1,2})\b')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-ActiveReleaseDetailVersion {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string[]]$Lines)

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^###\s+Active release detail\s+[—–-]\s+(\d+(?:\.\d+){1,2})\b') {
            return [pscustomobject]@{
                version = $matches[1]
                line    = $i + 1
            }
        }
    }

    return [pscustomobject]@{
        version = ''
        line    = 0
    }
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
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Findings)

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
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Findings,
        [Parameter(Mandatory=$true)][string]$OutPath
    )
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutPath))
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    # Always emit a valid JSON document. With zero findings, a piped empty
    # array yields no output (and thus no file), so fall back to '[]'.
    $json = ($Findings | ConvertTo-Json -Depth 6)
    if ([string]::IsNullOrWhiteSpace($json)) { $json = '[]' }
    Set-Content -LiteralPath $OutPath -Value $json -Encoding UTF8
    Write-Host ('JSON findings written: {0}' -f $OutPath) -ForegroundColor Cyan
}

# Export findings to CSV (flat one-row-per-finding format).
function Export-FindingsCsv {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Findings,
        [Parameter(Mandatory=$true)][string]$OutPath
    )
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutPath))
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    # Existing six columns keep their names and order; category/section/rule
    # are appended so header-keyed and fixed-6-column consumers both keep working.
    $Findings |
        Select-Object severity, code, message, release, line, recommendedAction, category, section, rule |
        Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8
    Write-Host ('CSV findings written: {0}' -f $OutPath) -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Validation rules — each adds findings to $script:Findings.
# ---------------------------------------------------------------------------

# Rule R001: detect duplicate release headings.
function Invoke-RuleDuplicateReleases {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases)

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
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases)

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

# Rule R003: detect missing required releases. '1.2' keeps its special
# "only required when a later 1.x release exists" semantics; any other version
# in config.requiredReleases is treated as a hard requirement.
function Invoke-RuleMissing12 {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases,
        [Parameter()][object]$Cfg = $script:ActiveConfig
    )

    $required = @($Cfg.requiredReleases)
    foreach ($req in $required) {
        $present = @($Releases | Where-Object { $_.version -eq $req }).Count -gt 0
        if ($present) { continue }

        if ($req -eq '1.2') {
            $hasLater1x = @($Releases | Where-Object {
                $parts = $_.version -split '\.'
                if ($parts.Count -ge 2) {
                    $maj = 0; $min = 0
                    [void][int]::TryParse($parts[0], [ref]$maj)
                    [void][int]::TryParse($parts[1], [ref]$min)
                    ($maj -eq 1 -and $min -gt 2)
                } else { $false }
            }).Count -gt 0

            if ($hasLater1x) {
                Add-Finding -Severity 'error' -Code 'R003-MISSING-1.2' `
                    -Message 'Release 1.2 is missing from the main release list, but later 1.x releases exist.' `
                    -RecommendedAction 'Add a Release 1.2 section in its proper position, or document why it was skipped.'
            }
        } else {
            Add-Finding -Severity 'error' -Code 'R003-MISSING-RELEASE' `
                -Message ("Required release " + $req + " is missing from the release list (declared in roadmap-validation.config.json).") `
                -RecommendedAction ('Add a Release ' + $req + ' section, or remove it from requiredReleases in the config.')
        }
    }
}

# Rule R004: every release must have Goal / Product outcomes / Engineering
# milestones / Acceptance criteria sub-sections.
function Invoke-RuleRequiredSections {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases)

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
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases)

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
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases
    )

    $section = [regex]::Match($RoadmapText, '(?ims)^##\s+\d*\.?\s*Immediate\s+Next\s+Focus.*?(?=^##\s+|\Z)')
    if (-not $section.Success) { return }

    # The bare presence is only flagged when config disallows it (default).
    if (-not $script:ActiveConfig.allowImmediateNextFocus) {
        Add-Finding -Severity 'warning' -Code 'R006-IMMEDIATE-NEXT-FOCUS-PRESENT' `
            -Message '"Immediate Next Focus" section is present. Prefer a "Current Active Release" pointer in the release roadmap.' `
            -RecommendedAction 'Remove the "Immediate Next Focus" section once the active release is identified at the top of section 5.'
    }

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
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases)

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
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases
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
        # Default info; escalate to warning when config requires the vocabulary.
        $sev = if ($script:ActiveConfig.requireImplementationStateVocabulary) { 'warning' } else { 'info' }
        Add-Finding -Severity $sev -Code 'R009-MISSING-STATE-VOCAB' `
            -Message 'Roadmap does not declare an Implementation-State Vocabulary section.' `
            -RecommendedAction 'Add a vocabulary section so [x] checkboxes carry consistent meaning (planned / scaffolded / backend-complete / ui-connected / smoke-tested / operator-verified / done).'
    }
}

# Rule R010: ROADMAP.md should not be excessively long for an active doc.
# Threshold is intentionally generous; warning only.
function Invoke-RuleFileLength {
    param([Parameter(Mandatory=$true)][int]$LineCount)
    if ($LineCount -gt $script:MaxActiveRoadmapLines) {
        Add-Finding -Severity 'warning' -Code 'R010-FILE-LENGTH' `
            -Message ('ROADMAP.md is ' + $LineCount + ' lines long. Active roadmaps should be scannable.') `
            -RecommendedAction 'Move completed-release detail to docs/history/completed-releases.md.'
    }
}

# Rule R011: the top active-release pointer and the section 5 active-release
# detail heading must exist and agree.
function Invoke-RuleActiveReleasePointer {
    param(
        [Parameter(Mandatory=$true)][string]$RoadmapText,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string[]]$Lines
    )

    $pointerVersion = Get-ActiveReleaseVersion -RoadmapText $RoadmapText
    $detail = Get-ActiveReleaseDetailVersion -Lines $Lines

    if ([string]::IsNullOrWhiteSpace($pointerVersion)) {
        Add-Finding -Severity 'warning' -Code 'R011-MISSING-ACTIVE-POINTER' `
            -Message 'ROADMAP.md is missing the top-level "Active release" pointer.' `
            -RecommendedAction 'Add a top summary line that names the active release version and title.'
    }

    if ([string]::IsNullOrWhiteSpace($detail.version)) {
        Add-Finding -Severity 'warning' -Code 'R011-MISSING-ACTIVE-DETAIL' `
            -Message 'ROADMAP.md is missing the section 5 "Active release detail" heading.' `
            -RecommendedAction 'Add an "Active release detail — X.Y Title" heading for the active release execution contract.'
    }

    if ((-not [string]::IsNullOrWhiteSpace($pointerVersion)) -and
        (-not [string]::IsNullOrWhiteSpace($detail.version)) -and
        $pointerVersion -ne $detail.version) {
        Add-Finding -Severity 'error' -Code 'R011-ACTIVE-MISMATCH' `
            -Message ('Top-level active release pointer (' + $pointerVersion + ') does not match the active release detail heading (' + $detail.version + ').') `
            -Release $detail.version -Line $detail.line `
            -RecommendedAction 'Make the top active-release pointer and the active release detail heading refer to the same version.'
    }
}

# Rule R012: completed release detail should not live in the active roadmap.
function Invoke-RuleCompletedReleaseSections {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases)

    foreach ($r in $Releases) {
        $stats = Get-ReleaseCheckboxStats -RawText $r.rawText
        if ($stats.checked -gt 0 -and $stats.unchecked -eq 0) {
            Add-Finding -Severity 'warning' -Code 'R012-COMPLETED-IN-ACTIVE' `
                -Message ('Completed release detail for ' + $r.version + ' is still in the active roadmap.') `
                -Release $r.version -Line ($r.startLine + 1) `
                -RecommendedAction 'Move completed release detail to docs/history/completed-releases.md and leave only an index/archive reference here.'
        }
    }
}

# Rule R013: FUTURE release sections should stay summarized enough to keep the
# active roadmap scannable. The ACTIVE release is deliberately exempt:
# ROADMAP_TEMPLATE.md puts the full execution contract — goal, outcomes,
# milestones, acceptance criteria, validation plan, risks, traceability — inside
# the active release block, so a conformant active release necessarily exceeds
# the cap. Firing here penalized the very structure the template requires, which
# is the opposite of what this rule is for.
function Invoke-RuleFutureReleaseSize {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases,
        [Parameter()][object]$Cfg
    )

    foreach ($r in $Releases) {
        if ($null -ne $Cfg) {
            $releaseStatus = Get-ReleaseStatus -RawText $r.rawText -Cfg $Cfg
            if ($releaseStatus.found -and $releaseStatus.normalized -eq 'active') { continue }
        }
        $lineCount = Get-LineCountForText -Text $r.rawText
        if ($lineCount -gt $script:MaxFutureReleaseLines) {
            Add-Finding -Severity 'warning' -Code 'R013-FUTURE-RELEASE-SIZE' `
                -Message ('Release ' + $r.version + ' spans ' + $lineCount + ' lines. Future releases should stay summarized in the active roadmap.') `
                -Release $r.version -Line ($r.startLine + 1) `
                -RecommendedAction 'Compress milestone detail or move deeper implementation planning to a supporting doc.'
        }
    }
}

# ---------------------------------------------------------------------------
# Config loading + merge (RQ layer)
# ---------------------------------------------------------------------------

# Locate a config file. Explicit -Config wins. Otherwise probe the standard
# locations relative to the roadmap directory and the script directory.
function Resolve-RoadmapValidationConfigPath {
    param(
        [Parameter()][string]$ExplicitPath = '',
        [Parameter()][string]$RoadmapPath  = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return [pscustomobject]@{ path = $ExplicitPath; explicit = $true }
    }

    $roots = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) {
        $rp = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($RoadmapPath))
        if (-not [string]::IsNullOrWhiteSpace($rp)) { [void]$roots.Add($rp) }
    }
    if ($PSScriptRoot) {
        # tools/ -> repo root is the parent of the script directory.
        [void]$roots.Add((Split-Path -Parent $PSScriptRoot))
        [void]$roots.Add($PSScriptRoot)
    }
    [void]$roots.Add((Get-Location).Path)

    $relatives = @(
        (Join-Path 'standards' (Join-Path 'roadmap' 'roadmap-validation.config.json')),
        (Join-Path 'tools' 'roadmap-validation.config.json')
    )

    foreach ($root in $roots) {
        foreach ($rel in $relatives) {
            $candidate = Join-Path $root $rel
            if (Test-Path -LiteralPath $candidate) {
                return [pscustomobject]@{ path = $candidate; explicit = $false }
            }
        }
    }
    return [pscustomobject]@{ path = ''; explicit = $false }
}

# Overlay a parsed-JSON config object onto the default config hashtable.
# Only known keys are honored; unknown keys are ignored (forward-compatible).
function Merge-RoadmapValidationConfig {
    param(
        [Parameter(Mandatory=$true)][object]$Defaults,
        [Parameter()][object]$Override
    )

    # Clone defaults into a fresh hashtable so we never mutate $script:DefaultConfig.
    $merged = @{}
    foreach ($key in $Defaults.Keys) { $merged[$key] = $Defaults[$key] }
    if ($null -eq $Override) { return $merged }

    foreach ($prop in $Override.PSObject.Properties) {
        $name = $prop.Name
        if (-not $merged.Contains($name)) { continue }  # ignore unknown keys
        $value = $prop.Value
        if ($null -eq $value) { continue }

        # statusAliases is an object map; convert to an ordered hashtable.
        if ($name -eq 'statusAliases' -and $value -is [psobject]) {
            $map = @{}
            foreach ($p in $value.PSObject.Properties) { $map[[string]$p.Name] = [string]$p.Value }
            $merged[$name] = $map
            continue
        }
        $merged[$name] = $value
    }
    return $merged
}

# Load + merge config. On explicit-but-broken config, record a finding and
# fall back to defaults. Returns the merged config hashtable.
function Get-RoadmapValidationConfig {
    param(
        [Parameter()][string]$ExplicitPath = '',
        [Parameter()][string]$RoadmapPath  = ''
    )

    $resolved = Resolve-RoadmapValidationConfigPath -ExplicitPath $ExplicitPath -RoadmapPath $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($resolved.path)) {
        return $script:DefaultConfig
    }

    if (-not (Test-Path -LiteralPath $resolved.path)) {
        if ($resolved.explicit) {
            Add-Finding -Severity 'error' -Code 'RQ000-CONFIG-ERROR' -Category 'config' -Rule 'config-load' `
                -Message ("Config file not found at: " + $resolved.path) `
                -RecommendedAction 'Correct the -Config path or omit it to use built-in defaults.'
        }
        return $script:DefaultConfig
    }

    try {
        $raw    = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $resolved.path).Path)
        $parsed = ConvertFrom-Json -InputObject $raw
        $merged = Merge-RoadmapValidationConfig -Defaults $script:DefaultConfig -Override $parsed
        Write-Host ('Roadmap validation config loaded: {0}' -f $resolved.path) -ForegroundColor DarkCyan
        return $merged
    } catch {
        $sev = if ($resolved.explicit) { 'error' } else { 'warning' }
        Add-Finding -Severity $sev -Code 'RQ000-CONFIG-ERROR' -Category 'config' -Rule 'config-load' `
            -Message ("Roadmap validation config could not be parsed (" + $resolved.path + "): " + $_.Exception.Message) `
            -RecommendedAction 'Fix the JSON syntax, or omit -Config to use built-in defaults.'
        return $script:DefaultConfig
    }
}

# ---------------------------------------------------------------------------
# Quality helpers (RQ layer)
# ---------------------------------------------------------------------------

# Capture every '##'/'###' heading block with its body so status-bearing
# blocks (e.g. "Active release detail", "completion snapshot") can be
# evaluated, not just '### Release X.Y' headings. Returns blocks in order.
function Get-RoadmapBlocks {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string[]]$Lines)

    $blocks = [System.Collections.Generic.List[object]]::new()
    $headingRegex = '^#{2,3}\s+(.+?)\s*$'
    $current = $null

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match $headingRegex) {
            if ($null -ne $current) {
                $current.endLine = $i - 1
                $current.rawText = ($Lines[$current.startLine..($i - 1)] -join "`n")
                [void]$blocks.Add([pscustomobject]$current)
            }
            $heading = $matches[1].Trim()
            $ver = ''
            $vm = [regex]::Match($heading, '(\d+(?:\.\d+){1,2})')
            if ($vm.Success) { $ver = $vm.Groups[1].Value }
            $current = [ordered]@{
                heading        = $heading
                version        = $ver
                startLine      = $i
                endLine        = $Lines.Count - 1
                rawText        = ''
                isActiveDetail = ($heading -match '(?i)^Active release detail\b')
            }
            continue
        }
    }
    if ($null -ne $current) {
        $current.rawText = ($Lines[$current.startLine..$current.endLine] -join "`n")
        [void]$blocks.Add([pscustomobject]$current)
    }
    return $blocks
}

# Parse and normalize a release Status from a block's raw text.
# Accepts "**Status:** active", "Status: active", "> **Status:** active",
# trailing prose ("active. Foo bar"). Returns an object describing the result.
function Get-ReleaseStatus {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$RawText,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    # Pattern comes from the shared contract (rule pack -> detection
    # .releaseStatusPattern), falling back to the mirror when a caller passes a
    # config that predates it. Never hardcode a second spelling here.
    $pattern = [string]$script:DefaultConfig.releaseStatusPattern
    if ($Cfg -is [System.Collections.IDictionary] -and $Cfg.Contains('releaseStatusPattern') -and
        -not [string]::IsNullOrWhiteSpace([string]$Cfg['releaseStatusPattern'])) {
        $pattern = [string]$Cfg['releaseStatusPattern']
    }

    $m = [regex]::Match($RawText, $pattern)
    if (-not $m.Success) {
        return [pscustomobject]@{ found = $false; raw = ''; normalized = ''; valid = $false }
    }

    # Take the first word/phrase token before punctuation/sentence break.
    $rawVal = $m.Groups[1].Value.Trim()
    $token  = ($rawVal -split '[\.\,;:\(\)]')[0].Trim().ToLowerInvariant()

    $normalized = $token
    if ($Cfg.statusAliases -and $Cfg.statusAliases.Contains($token)) {
        $normalized = [string]$Cfg.statusAliases[$token]
    }

    $valid = @($Cfg.allowedStatuses) -contains $normalized
    return [pscustomobject]@{
        found      = $true
        raw        = $rawVal
        token      = $token
        normalized = $normalized
        valid      = $valid
    }
}

# Return the text body of a named section inside a release block, whether the
# section is framed as '#### Name', '### Name', or '**Name:**'. Captures up to
# the next heading or bold-label line. Returns '' when absent.
function Get-ReleaseSectionText {
    param(
        [Parameter(Mandatory=$true)][string]$RawText,
        [Parameter(Mandatory=$true)][string]$SectionName
    )

    $escaped = [regex]::Escape($SectionName)
    # Heading-framed section: '#### Validation plan' ... until next heading.
    $hm = [regex]::Match($RawText, "(?ims)^#{2,6}\s+$escaped\b.*?\n(.*?)(?=^#{2,6}\s+|\Z)")
    if ($hm.Success) { return $hm.Groups[1].Value.Trim() }
    # Bold-label section: '**Validation plan:**' ... until blank line / next label / heading.
    $bm = [regex]::Match($RawText, "(?ims)^\*\*$escaped[^*]*\*\*\s*:?\s*(.*?)(?=\r?\n\r?\n|^\*\*[A-Z]|^#{2,6}\s+|\Z)")
    if ($bm.Success) { return $bm.Groups[1].Value.Trim() }
    return ''
}

# True when a section exists AND has non-whitespace, non-placeholder content.
function Test-ReleaseSectionHasMeaningfulContent {
    param(
        [Parameter(Mandatory=$true)][string]$RawText,
        [Parameter(Mandatory=$true)][string[]]$SectionAliases
    )
    foreach ($name in $SectionAliases) {
        if (Test-ReleaseHasSection -RawText $RawText -SectionName $name) {
            $body = Get-ReleaseSectionText -RawText $RawText -SectionName $name
            $stripped = ($body -replace '(?m)^\s*[-*]\s*', '').Trim()
            if (-not [string]::IsNullOrWhiteSpace($stripped)) { return $true }
        }
    }
    return $false
}

# A validation plan is concrete when it references at least one real validation
# mechanism (test/build/lint/smoke/CI/etc.) from the configured signal list.
function Test-ValidationPlanIsConcrete {
    param(
        [Parameter(Mandatory=$true)][string]$PlanText,
        [Parameter(Mandatory=$true)][object]$Cfg
    )
    if ([string]::IsNullOrWhiteSpace($PlanText)) { return $false }
    $lower = $PlanText.ToLowerInvariant()
    foreach ($signal in @($Cfg.validationSignals)) {
        if ($lower.Contains([string]$signal.ToLowerInvariant())) { return $true }
    }
    return $false
}

# Flag acceptance-criteria items that are vague (e.g. "- [ ] works"). Returns
# the list of weak item texts. Only short items dominated by a vague term hit.
function Test-AcceptanceCriteriaAreWeak {
    param(
        [Parameter(Mandatory=$true)][string]$RawText,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    $weak = [System.Collections.Generic.List[string]]::new()
    $body = Get-ReleaseSectionText -RawText $RawText -SectionName 'Acceptance criteria'
    if ([string]::IsNullOrWhiteSpace($body)) { return $weak }

    $terms = @($Cfg.weakAcceptanceTerms)
    foreach ($itemMatch in [regex]::Matches($body, '(?im)^\s*-\s+(?:\[[ xX]\]\s*)?(.+?)\s*$')) {
        $item = $itemMatch.Groups[1].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $clean = ($item -replace '[*_`]', '').Trim().ToLowerInvariant()
        $wordCount = @($clean -split '\s+' | Where-Object { $_ -ne '' }).Count
        # Only treat short items as suspect — long, specific criteria are fine.
        if ($wordCount -gt 4) { continue }
        foreach ($t in $terms) {
            $tl = ([string]$t).ToLowerInvariant()
            if ($clean -eq $tl -or $clean -match ('(?i)^' + [regex]::Escape($tl) + '\b') -or $clean -match ('(?i)\b' + [regex]::Escape($tl) + '$')) {
                [void]$weak.Add($item)
                break
            }
        }
    }
    return $weak
}

# True when the block contains any traceability signal (issue/PR/test/doc/ADR/workflow).
function Test-ReleaseHasTraceability {
    param([Parameter(Mandatory=$true)][string]$RawText)

    $patterns = @(
        '(?im)(?:^|\s)#\d{1,6}\b',                 # #123
        '(?i)\bGH-\d+\b',                          # GH-123
        '(?i)\bIssue\s*:?\s*#?\d+',                # Issue: #123
        '(?i)\bPR\s*:?\s*#?\d+',                   # PR: #456
        '(?i)\bpull request\b',
        '(?i)\btests?/[\w\.\-/]+',                 # tests/...
        '(?i)\b[\w\.\-/]+\.Tests\.ps1\b',
        '(?i)\b[\w\.\-/]+\.(?:test|spec)\.(?:ts|tsx|js|jsx)\b',
        '(?i)\bdocs/[\w\.\-/]+',                   # docs/...
        '(?i)\.github/workflows/[\w\.\-/]+'        # workflow paths
    )
    foreach ($p in $patterns) {
        if ([regex]::IsMatch($RawText, $p)) { return $true }
    }
    return $false
}

# Locate a known-issues / pipeline-feedback section under any accepted alias.
function Get-PipelineFeedbackBody {
    param([Parameter(Mandatory=$true)][string]$RawText)

    $aliases = @(
        'Known issues / discovered during development',
        'Known issues',
        'Discovered issues / follow-up',
        'Discovered issues',
        'Pipeline findings',
        'Validation findings'
    )
    foreach ($a in $aliases) {
        if (Test-ReleaseHasSection -RawText $RawText -SectionName $a) {
            return [pscustomobject]@{ found = $true; alias = $a; body = (Get-ReleaseSectionText -RawText $RawText -SectionName $a) }
        }
    }
    return [pscustomobject]@{ found = $false; alias = ''; body = '' }
}

# True when a block explicitly declares no known issues ("None currently known").
function Test-KnownIssuesExplicitlyEmpty {
    param([Parameter(Mandatory=$true)][string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    return [regex]::IsMatch($Body, '(?i)\b(none(?:\s+currently)?\s+known|no\s+known\s+issues|none\s+at\s+this\s+time|n/?a)\b')
}

# ---------------------------------------------------------------------------
# Quality rules (RQ layer) — each adds findings to $script:Findings.
# ---------------------------------------------------------------------------

# Build the list of status-bearing blocks once and share across RQ rules.
function Get-StatusBearingBlocks {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Blocks,
        [Parameter(Mandatory=$true)][object]$Cfg
    )
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($b in $Blocks) {
        $status = Get-ReleaseStatus -RawText $b.rawText -Cfg $Cfg
        if ($status.found) {
            [void]$result.Add([pscustomobject]@{ block = $b; status = $status })
        }
    }
    return $result
}

# RQ001/RQ002/RQ003: status presence, validity, single-active, pointer match.
function Invoke-RuleReleaseStatus {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks,
        [Parameter()][AllowEmptyString()][string]$PointerVersion = '',
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    # RQ002 — invalid status value (error).
    foreach ($sb in $StatusBlocks) {
        if (-not $sb.status.valid) {
            Add-Finding -Severity 'error' -Code 'RQ002-INVALID-STATUS' -Category 'quality' -Rule 'release-status' `
                -Message ("Block '" + $sb.block.heading + "' declares an unrecognized status '" + $sb.status.raw + "'.") `
                -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Status' `
                -RecommendedAction ('Use one of: ' + (@($Cfg.allowedStatuses) -join ', ') + ' (aliases are defined in standards/roadmap/roadmap-audit-rules.json under detection.statusVocabulary.statusAliases).')
        }
    }

    # RQ003 — more than one block marked active (error). 'Active' is whatever
    # the shared contract says it is: the scorer's ROADMAP-011 counts the same
    # set, so a roadmap must not be single-active here and multi-active there.
    $activeStatuses = @($Cfg.activeStatuses)
    if ($activeStatuses.Count -eq 0) { $activeStatuses = @('active') }
    $activeBlocks = @($StatusBlocks | Where-Object { $activeStatuses -contains $_.status.normalized })
    if ($activeBlocks.Count -gt 1) {
        foreach ($ab in $activeBlocks) {
            Add-Finding -Severity 'error' -Code 'RQ003-MULTIPLE-ACTIVE-RELEASES' -Category 'quality' -Rule 'release-status' `
                -Message ("More than one release is marked active (block '" + $ab.block.heading + "'). Exactly one release may be active.") `
                -Release $ab.block.version -Line ($ab.block.startLine + 1) -Section 'Status' `
                -RecommendedAction 'Keep a single active release; move the others to validation, done, or planned.'
        }
    }

    # RQ003 — active pointer/status mismatch (error), when both are known.
    if ($activeBlocks.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($PointerVersion)) {
        $av = $activeBlocks[0].block.version
        if (-not [string]::IsNullOrWhiteSpace($av) -and $av -ne $PointerVersion) {
            Add-Finding -Severity 'error' -Code 'RQ003-ACTIVE-POINTER-MISMATCH' -Category 'quality' -Rule 'release-status' `
                -Message ("Top active-release pointer (" + $PointerVersion + ") does not match the release marked active (" + $av + ").") `
                -Release $av -Line ($activeBlocks[0].block.startLine + 1) -Section 'Status' `
                -RecommendedAction 'Align the active-release pointer with the release whose Status is active.'
        }
    }
}

# RQ001 — missing status, evaluated over all blocks (active-detail = warning,
# future/planned = optional info gated by config).
function Invoke-RuleMissingStatus {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Blocks,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    # A release that declares its own status is the single source of truth for
    # it. ROADMAP_TEMPLATE.md allows the active-release snapshot to be a bare
    # POINTER at that release — a heading whose whole job is letting this
    # validator resolve the active version, deliberately restating nothing.
    # Demanding a Status line there would force the roadmap to declare the same
    # status twice, which RQ003 then reports as an error: the two rules
    # contradicted each other on any conformant roadmap.
    $versionsDeclaringStatus = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Releases) {
        $releaseStatus = Get-ReleaseStatus -RawText $r.rawText -Cfg $Cfg
        if ($releaseStatus.found -and $releaseStatus.valid) {
            [void]$versionsDeclaringStatus.Add([string]$r.version)
        }
    }

    foreach ($b in $Blocks) {
        if (-not $b.isActiveDetail) { continue }
        $status = Get-ReleaseStatus -RawText $b.rawText -Cfg $Cfg
        if (-not $status.found) {
            if ($versionsDeclaringStatus.Contains([string]$b.version)) { continue }
            Add-Finding -Severity 'warning' -Code 'RQ001-MISSING-STATUS' -Category 'quality' -Rule 'release-status' `
                -Message ("Active release detail '" + $b.heading + "' has no explicit Status line, and release " + $b.version + " does not declare one either.") `
                -Release $b.version -Line ($b.startLine + 1) -Section 'Status' `
                -RecommendedAction 'Add a "**Status:** active" line to the release section so the execution contract declares its state exactly once.'
        }
    }

    if ($Cfg.flagMissingStatusOnFutureReleases) {
        foreach ($r in $Releases) {
            $status = Get-ReleaseStatus -RawText $r.rawText -Cfg $Cfg
            if (-not $status.found) {
                Add-Finding -Severity 'info' -Code 'RQ001-MISSING-STATUS' -Category 'quality' -Rule 'release-status' `
                    -Message ("Release " + $r.version + " has no explicit Status line.") `
                    -Release $r.version -Line ($r.startLine + 1) -Section 'Status' `
                    -RecommendedAction 'Add a "**Status:** planned" line to make the release lifecycle explicit.'
            }
        }
    }
}

# RQ-required-sections — active/blocked/validation blocks should carry the
# execution-contract sections (validation plan, risks, deps, known issues,
# traceability). Emits per-section warnings via specific codes.
function Invoke-RuleActiveReleaseSections {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    $sectionCodes = @{
        'Validation plan'    = @{ aliases = @('Validation plan','Validation','Test plan'); code = 'RQ004-MISSING-VALIDATION-PLAN'; section = 'Validation plan' }
        'Risks and blockers' = @{ aliases = @('Risks and blockers','Risks','Blockers','Risks/blockers'); code = 'R004-MISSING-SECTION'; section = 'Risks and blockers' }
        'Dependencies'       = @{ aliases = @('Dependencies'); code = 'RQ011-MISSING-DEPENDENCIES-SECTION'; section = 'Dependencies' }
        'Known issues'       = @{ aliases = @('Known issues / discovered during development','Known issues','Discovered issues / follow-up','Pipeline findings','Validation findings'); code = 'RQ009-MISSING-PIPELINE-FEEDBACK'; section = 'Known issues' }
        'Traceability'       = @{ aliases = @('Traceability'); code = 'RQ006-MISSING-TRACEABILITY'; section = 'Traceability' }
    }

    foreach ($sb in $StatusBlocks) {
        $st = $sb.status.normalized
        if ($st -ne 'active' -and $st -ne 'blocked' -and $st -ne 'validation') { continue }

        foreach ($wanted in @($Cfg.activeReleaseRequiredSections)) {
            # Traceability is owned by the signal-based Invoke-RuleTraceability
            # rule (a literal heading is not required), so skip it here to
            # avoid a duplicate RQ006 finding.
            if ($wanted -ieq 'Traceability') { continue }

            # Map the configured section name to the alias/code descriptor.
            $descriptor = $null
            foreach ($key in $sectionCodes.Keys) {
                if ($key -ieq $wanted -or (@($sectionCodes[$key].aliases) -contains $wanted)) { $descriptor = $sectionCodes[$key]; break }
            }
            if ($null -eq $descriptor) {
                $descriptor = @{ aliases = @($wanted); code = 'R004-MISSING-SECTION'; section = $wanted }
            }

            if (-not (Test-ReleaseSectionHasMeaningfulContent -RawText $sb.block.rawText -SectionAliases $descriptor.aliases)) {
                Add-Finding -Severity 'warning' -Code $descriptor.code -Category 'quality' -Rule 'active-contract' `
                    -Message ("The " + $st + " release '" + $sb.block.heading + "' is missing a meaningful '" + $descriptor.section + "' section.") `
                    -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section $descriptor.section `
                    -RecommendedAction ('Add a "' + $descriptor.section + '" section to the active execution contract so its state can be verified.')
            }
        }
    }
}

# RQ004 — validation plan exists but is not concrete (weak).
function Invoke-RuleValidationPlanQuality {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    foreach ($sb in $StatusBlocks) {
        $st = $sb.status.normalized
        if ($st -ne 'active' -and $st -ne 'blocked' -and $st -ne 'validation') { continue }

        $hasSection = (Test-ReleaseHasSection -RawText $sb.block.rawText -SectionName 'Validation plan') -or
                      (Test-ReleaseHasSection -RawText $sb.block.rawText -SectionName 'Validation')
        if (-not $hasSection) { continue }  # absence handled by Invoke-RuleActiveReleaseSections

        $plan = Get-ReleaseSectionText -RawText $sb.block.rawText -SectionName 'Validation plan'
        if ([string]::IsNullOrWhiteSpace($plan)) { $plan = Get-ReleaseSectionText -RawText $sb.block.rawText -SectionName 'Validation' }

        # RQ for validation-status releases: a meaningful plan is required.
        if (-not (Test-ValidationPlanIsConcrete -PlanText $plan -Cfg $Cfg)) {
            Add-Finding -Severity 'warning' -Code 'RQ004-WEAK-VALIDATION-PLAN' -Category 'quality' -Rule 'validation-plan' `
                -Message ("Release '" + $sb.block.heading + "' has a validation plan with no concrete validation signal.") `
                -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Validation plan' `
                -RecommendedAction 'Add concrete validation commands or smoke checks such as npm test, npm run build, Invoke-Pester, CI, or manual smoke-test steps.'
        }
    }
}

# RQ005 — weak / vague acceptance criteria (warning). Applies to all blocks
# that declare an acceptance-criteria section, regardless of status.
function Invoke-RuleAcceptanceCriteriaQuality {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Blocks,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    foreach ($b in $Blocks) {
        if (-not (Test-ReleaseHasSection -RawText $b.rawText -SectionName 'Acceptance criteria')) { continue }
        $weak = @(Test-AcceptanceCriteriaAreWeak -RawText $b.rawText -Cfg $Cfg)
        if ($weak.Count -gt 0) {
            $sample = ($weak | Select-Object -First 3) -join '; '
            Add-Finding -Severity 'warning' -Code 'RQ005-WEAK-ACCEPTANCE-CRITERIA' -Category 'quality' -Rule 'acceptance-criteria' `
                -Message ("Release '" + $b.heading + "' has " + $weak.Count + " vague acceptance criterion/criteria: " + $sample) `
                -Release $b.version -Line ($b.startLine + 1) -Section 'Acceptance criteria' `
                -RecommendedAction 'Rewrite acceptance criteria so each item describes an observable result, test command, UI behavior, API behavior, artifact, or operator-verifiable outcome.'
        }
    }
}

# RQ006 — active/validation blocks should carry traceability signals.
function Invoke-RuleTraceability {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks)

    foreach ($sb in $StatusBlocks) {
        $st = $sb.status.normalized
        if ($st -ne 'active' -and $st -ne 'validation') { continue }
        if (-not (Test-ReleaseHasTraceability -RawText $sb.block.rawText)) {
            Add-Finding -Severity 'warning' -Code 'RQ006-MISSING-TRACEABILITY' -Category 'quality' -Rule 'traceability' `
                -Message ("Release '" + $sb.block.heading + "' (" + $st + ") has no traceability signals (issues, PRs, tests, workflows, ADRs, or docs).") `
                -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Traceability' `
                -RecommendedAction 'Link the release to issues, PRs, tests, workflows, ADRs, or supporting docs so roadmap status can be verified against repo activity.'
        }
    }
}

# RQ009/RQ010 — pipeline / known-issues feedback for in-flight releases.
function Invoke-RulePipelineFeedback {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    foreach ($sb in $StatusBlocks) {
        $st = $sb.status.normalized
        if ($st -ne 'active' -and $st -ne 'blocked' -and $st -ne 'validation') { continue }

        $fb = Get-PipelineFeedbackBody -RawText $sb.block.rawText
        if (-not $fb.found) {
            # Missing section is handled by Invoke-RuleActiveReleaseSections
            # (RQ009) when 'Known issues' is in activeReleaseRequiredSections.
            if (@($Cfg.activeReleaseRequiredSections) -notcontains 'Known issues') {
                Add-Finding -Severity 'warning' -Code 'RQ009-MISSING-PIPELINE-FEEDBACK' -Category 'quality' -Rule 'pipeline-feedback' `
                    -Message ("Release '" + $sb.block.heading + "' (" + $st + ") has no known-issues / pipeline-feedback section.") `
                    -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Known issues' `
                    -RecommendedAction 'Add a "Known issues / discovered during development" section to capture bugs, failed tests, CI/build failures, and follow-ups found during execution.'
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace(($fb.body -replace '(?m)^\s*[-*]\s*', '').Trim())) {
            Add-Finding -Severity 'info' -Code 'RQ010-EMPTY-KNOWN-ISSUES' -Category 'quality' -Rule 'pipeline-feedback' `
                -Message ("Release '" + $sb.block.heading + "' has an empty '" + $fb.alias + "' section.") `
                -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Known issues' `
                -RecommendedAction 'List discovered issues, or state "None currently known" so the empty section is intentional.'
            continue
        }

        # If the section reports pipeline trouble, expect a follow-up signal.
        if (-not (Test-KnownIssuesExplicitlyEmpty -Body $fb.body)) {
            $lower = $fb.body.ToLowerInvariant()
            $mentionsTrouble = $false
            foreach ($kw in @($Cfg.pipelineKeywords)) {
                if ($lower -match ('(?i)\b' + [regex]::Escape([string]$kw) + '\b')) { $mentionsTrouble = $true; break }
            }
            if ($mentionsTrouble) {
                $hasFollowUp = ($fb.body -match '(?m)^\s*-\s+\[[ xX]\]') -or
                               (Test-ReleaseHasTraceability -RawText $fb.body) -or
                               ($fb.body -match '(?i)\b(owner|follow[- ]?up|tracked|assigned|TODO)\b')
                if (-not $hasFollowUp) {
                    Add-Finding -Severity 'info' -Code 'RQ010-EMPTY-KNOWN-ISSUES' -Category 'quality' -Rule 'pipeline-feedback' `
                        -Message ("Release '" + $sb.block.heading + "' lists pipeline/discovered issues without a checkbox, owner, follow-up, or traceability signal.") `
                        -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Known issues' `
                        -RecommendedAction 'Attach a checkbox, owner, follow-up note, or issue/PR link to each discovered problem so it stays tracked.'
                }
            }
        }
    }
}

# RQ007 — a blocked release must list at least one blocker.
function Invoke-RuleBlockedReleaseHasBlocker {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks)

    foreach ($sb in $StatusBlocks) {
        if ($sb.status.normalized -ne 'blocked') { continue }
        $hasBlocker = (Test-ReleaseSectionHasMeaningfulContent -RawText $sb.block.rawText -SectionAliases @('Risks and blockers','Blockers','Risks')) -or
                      [regex]::IsMatch($sb.block.rawText, '(?im)^\s*[-*]\s+.*\bblock(?:ed|er|ing)?\b')
        if (-not $hasBlocker) {
            Add-Finding -Severity 'warning' -Code 'RQ007-BLOCKED-WITHOUT-BLOCKER' -Category 'quality' -Rule 'blocked-release' `
                -Message ("Release '" + $sb.block.heading + "' is marked blocked but lists no blocker.") `
                -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Risks and blockers' `
                -RecommendedAction 'List the specific blocker(s) under "Risks and blockers" so the block reason is auditable.'
        }
    }
}

# RQ011/RQ012 — recommended sections for planned/future releases (info only,
# gated by config). A release is "planned/future" when it has no in-flight or
# done status. "Out of scope" satisfies the Non-goals recommendation.
function Invoke-RulePlannedReleaseRecommendations {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Releases,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    if (-not $Cfg.flagFutureReleaseRecommendations) { return }

    foreach ($r in $Releases) {
        $status = Get-ReleaseStatus -RawText $r.rawText -Cfg $Cfg
        $st = if ($status.found) { $status.normalized } else { 'planned' }
        if ($st -ne 'planned') { continue }

        if (-not (Test-ReleaseSectionHasMeaningfulContent -RawText $r.rawText -SectionAliases @('Dependencies'))) {
            Add-Finding -Severity 'info' -Code 'RQ011-MISSING-DEPENDENCIES-SECTION' -Category 'quality' -Rule 'planned-release' `
                -Message ("Planned release " + $r.version + " has no Dependencies section.") `
                -Release $r.version -Line ($r.startLine + 1) -Section 'Dependencies' `
                -RecommendedAction 'List upstream releases, services, or external work this release depends on.'
        }
        if (-not (Test-ReleaseSectionHasMeaningfulContent -RawText $r.rawText -SectionAliases @('Non-goals','Non goals','Out of scope'))) {
            Add-Finding -Severity 'info' -Code 'RQ012-MISSING-NON-GOALS' -Category 'quality' -Rule 'planned-release' `
                -Message ("Planned release " + $r.version + " has no Non-goals / Out-of-scope section.") `
                -Release $r.version -Line ($r.startLine + 1) -Section 'Non-goals' `
                -RecommendedAction 'Add a Non-goals or Out-of-scope section to bound the release and prevent scope creep.'
        }
    }
}

# RQ008 — a done release should not retain unchecked items.
function Invoke-RuleDoneReleaseCompletion {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$StatusBlocks,
        [Parameter(Mandatory=$true)][object]$Cfg
    )

    $severity = if ($Cfg.treatDoneWithUncheckedCriteriaAsError) { 'error' } else { 'warning' }

    foreach ($sb in $StatusBlocks) {
        if ($sb.status.normalized -ne 'done') { continue }
        $stats = Get-ReleaseCheckboxStats -RawText $sb.block.rawText
        if ($stats.unchecked -gt 0) {
            Add-Finding -Severity $severity -Code 'RQ008-DONE-WITH-UNCHECKED-CRITERIA' -Category 'quality' -Rule 'done-release' `
                -Message ("Release '" + $sb.block.heading + "' is marked done but has " + $stats.unchecked + " unchecked item(s).") `
                -Release $sb.block.version -Line ($sb.block.startLine + 1) -Section 'Acceptance criteria' `
                -RecommendedAction 'Check off completed items, move the release detail to docs/history/completed-releases.md, or re-open the release status if work remains.'
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# When dot-sourced for unit testing, stop here — all functions are defined.
if ($LoadFunctionsOnly) { return }

# Initialize accumulator. Use a script-scoped list so rule functions can
# append without passing the list around.
$script:Findings = [System.Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host ('ERROR: ROADMAP.md not found at: ' + $Path) -ForegroundColor Red
    exit 2
}

# Load + merge config (writes RQ000-CONFIG-ERROR on explicit-but-broken file),
# then route the back-compat script vars through the resolved config so the
# original R-rules honor config overrides too.
$script:ActiveConfig = Get-RoadmapValidationConfig -ExplicitPath $Config -RoadmapPath $Path
$script:RequiredReleaseSections = @($script:ActiveConfig.requiredSections)
$script:MaxActiveRoadmapLines   = [int]$script:ActiveConfig.maxActiveRoadmapLines
$script:MaxFutureReleaseLines   = [int]$script:ActiveConfig.maxFutureReleaseLines

# Read once. Lines for line-number reporting; full text for whole-file rules.
$lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path).Path)
$text  = ($lines -join "`n")

# @() because Get-ReleaseSections returns $null when a file has no release
# headings at all — exactly the case R000-NO-RELEASES below exists to report.
# Under StrictMode a bare $null.Count threw before that finding could be added,
# so the linter died on the very files it was supposed to diagnose (the
# ROADMAP_TEMPLATE.md placeholder file is one).
$releases = @(Get-ReleaseSections -Lines $lines)

# Richer block model for the RQ layer: every '##'/'###' heading block, so
# status-bearing blocks (Active release detail, completion snapshots) are
# evaluated, not just '### Release X.Y' headings.
$blocks         = @(Get-RoadmapBlocks -Lines $lines)
$statusBlocks   = @(Get-StatusBearingBlocks -Blocks $blocks -Cfg $script:ActiveConfig)
$pointerVersion = Get-ActiveReleaseVersion -RoadmapText $text

if ($releases.Count -eq 0) {
    Add-Finding -Severity 'error' -Code 'R000-NO-RELEASES' `
        -Message 'No "## Release X.Y — Title" headings found in the file.' `
        -RecommendedAction 'Confirm this is the correct ROADMAP.md and that release headings follow the canonical format.'
}

# --- Structural rules (R-codes) ---
Invoke-RuleDuplicateReleases     -Releases $releases
Invoke-RuleReleaseOrder          -Releases $releases
Invoke-RuleMissing12             -Releases $releases -Cfg $script:ActiveConfig
Invoke-RuleRequiredSections      -Releases $releases
Invoke-RuleTitleGoalMismatch     -Releases $releases
Invoke-RuleImmediateNextFocus    -RoadmapText $text -Releases $releases
Invoke-RuleUncheckedNoAcceptance -Releases $releases
Invoke-RuleCompletedDominance    -RoadmapText $text -Releases $releases
Invoke-RuleStateVocabulary       -RoadmapText $text
Invoke-RuleFileLength            -LineCount $lines.Count
Invoke-RuleActiveReleasePointer  -RoadmapText $text -Lines $lines
Invoke-RuleCompletedReleaseSections -Releases $releases
Invoke-RuleFutureReleaseSize     -Releases $releases -Cfg $script:ActiveConfig

# --- Roadmap-quality rules (RQ-codes) ---
Invoke-RuleReleaseStatus           -StatusBlocks $statusBlocks -PointerVersion $pointerVersion -Cfg $script:ActiveConfig
Invoke-RuleMissingStatus           -Blocks $blocks -Releases $releases -Cfg $script:ActiveConfig
Invoke-RuleActiveReleaseSections   -StatusBlocks $statusBlocks -Cfg $script:ActiveConfig
Invoke-RuleValidationPlanQuality   -StatusBlocks $statusBlocks -Cfg $script:ActiveConfig
Invoke-RuleAcceptanceCriteriaQuality -Blocks $blocks -Cfg $script:ActiveConfig
Invoke-RuleTraceability            -StatusBlocks $statusBlocks
Invoke-RulePipelineFeedback        -StatusBlocks $statusBlocks -Cfg $script:ActiveConfig
Invoke-RuleBlockedReleaseHasBlocker -StatusBlocks $statusBlocks
Invoke-RuleDoneReleaseCompletion   -StatusBlocks $statusBlocks -Cfg $script:ActiveConfig
Invoke-RulePlannedReleaseRecommendations -Releases $releases -Cfg $script:ActiveConfig

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

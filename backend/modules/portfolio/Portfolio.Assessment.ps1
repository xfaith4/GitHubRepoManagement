<#
.SYNOPSIS
    Portfolio assessment — combines git, doc audit, roadmap state, roadmap maturity,
    structure audit, and execution state into one operator-facing record per repo.

.DESCRIPTION
    Release 1.7.5 — Portfolio Mission Alignment.

    This module exposes:

      Get-RepoStructureStandards
        Loads backend/config/repo-structure-standards.json.

      Invoke-RepoStructureAudit -RepoPath -Standards
        Runs a fast structural check against a single repo (Test-Path only,
        no subprocesses) and returns missing-element findings.

      Invoke-PortfolioAssessment -LocalRepos -RoadmapEntries -DocAuditEntries
                                 -RoadmapAuditEntries -ExecutionEntries
                                 -GitHubRepos -StructureStandards -ValueScoringConfig
        Produces a normalized assessment record per repo combining every input
        signal, plus a single lifecycleState per repo and a portfolio-level
        summary.

    The lifecycle state precedence is deterministic — see _ResolveLifecycleState.

.NOTES
    Dot-source from Start-RepoManagementApiHost.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Standards loader
# ---------------------------------------------------------------------------

function Get-RepoStructureStandards {
    [CmdletBinding()]
    param([string]$StandardsPath = '')

    if ([string]::IsNullOrWhiteSpace($StandardsPath) -or -not (Test-Path -LiteralPath $StandardsPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $StandardsPath -Raw -Encoding UTF8 -ErrorAction Stop
        return ConvertFrom-Json -InputObject $raw
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Internal: detect repo type from on-disk manifests (mirrors Roadmap.Evaluator
# detection but kept local so this module has no roadmap-evaluator dependency).
# ---------------------------------------------------------------------------

function _DetectRepoTypeForStructure {
    param([string]$LocalPath)
    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path -LiteralPath $LocalPath -ErrorAction SilentlyContinue)) { return 'other' }

    if (Test-Path -LiteralPath (Join-Path $LocalPath 'package.json') -PathType Leaf) { return 'node' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'go.mod')       -PathType Leaf) { return 'go' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'Cargo.toml')   -PathType Leaf) { return 'rust' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'pyproject.toml') -PathType Leaf) { return 'python' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'setup.py')       -PathType Leaf) { return 'python' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'requirements.txt') -PathType Leaf) { return 'python' }

    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.csproj' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.sln'    -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.fsproj' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }

    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.psd1' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.psm1' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1'  -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }

    return 'other'
}

function _HasTestSignal {
    # NOTE: patterns are hard-coded by repo type below. The JSON config exposes
    # repoTypes.<type>.testSignalGlobs as a forward-compatibility hook; it is
    # not consumed yet. A future enhancement can switch to data-driven globs
    # without changing this function's contract.
    param([string]$LocalPath, [string]$RepoType, [object]$Standards)

    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path -LiteralPath $LocalPath -ErrorAction SilentlyContinue)) { return $false }

    foreach ($d in @('test', 'tests', '__tests__', 'spec', 'specs')) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath $d) -PathType Container) { return $true }
    }
    switch ($RepoType) {
        'node'       { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.test.*'   -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'dotnet'     { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*Tests*'    -Recurse -Depth 3 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'python'     { return @(Get-ChildItem -LiteralPath $LocalPath -Filter 'test_*.py'  -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'powershell' { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.Tests.ps1' -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'go'         { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*_test.go'   -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'rust'       { return Test-Path -LiteralPath (Join-Path $LocalPath 'tests') -PathType Container }
    }
    return $false
}

function _TestPathAny {
    param([string]$Base, [string[]]$Names)
    foreach ($n in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        if (Test-Path -LiteralPath (Join-Path $Base $n)) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Per-repo structure audit (Test-Path only — fast and side-effect free)
# ---------------------------------------------------------------------------

function Invoke-RepoStructureAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter()][object]$Standards
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $repoType = _DetectRepoTypeForStructure -LocalPath $RepoPath

    # NOTE: parens around `-contains` are required — `-not` binds tighter than
    # `-contains`, so without them this guard becomes `(-not <array>) -contains 'common'`
    # which is always false and silently lets a malformed Standards object through.
    if ($null -eq $Standards -or -not ($Standards.PSObject.Properties.Name -contains 'common')) {
        return [pscustomobject]@{
            repoType   = $repoType
            findings   = @()
            missingCount = 0
            criticalMissingCount = 0
            warningMissingCount  = 0
            hasTestSignal = $false
            hasCiSignal   = $false
        }
    }

    $common = $Standards.common

    foreach ($spec in @($common.requiredRootFiles)) {
        if ($null -eq $spec) { continue }
        $names = @([string]$spec.name)
        if ($spec.PSObject.Properties.Name -contains 'altNames' -and $spec.altNames) {
            $names += @($spec.altNames | ForEach-Object { [string]$_ })
        }
        if (-not (_TestPathAny -Base $RepoPath -Names $names)) {
            $findings.Add([pscustomobject]@{
                kind              = 'missing-root-file'
                target            = [string]$spec.name
                category          = [string]$spec.category
                severity          = [string]$spec.severity
                recommendedAction = [string]$spec.recommendedAction
            })
        }
    }

    foreach ($spec in @($common.requiredRootFolders)) {
        if ($null -eq $spec) { continue }
        $names = @([string]$spec.name)
        if ($spec.PSObject.Properties.Name -contains 'altNames' -and $spec.altNames) {
            $names += @($spec.altNames | ForEach-Object { [string]$_ })
        }
        $found = $false
        foreach ($n in $names) {
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            if (Test-Path -LiteralPath (Join-Path $RepoPath $n) -PathType Container) { $found = $true; break }
        }
        if (-not $found) {
            $findings.Add([pscustomobject]@{
                kind              = 'missing-root-folder'
                target            = [string]$spec.name
                category          = [string]$spec.category
                severity          = [string]$spec.severity
                recommendedAction = [string]$spec.recommendedAction
            })
        }
    }

    $hasCiSignal = $false
    foreach ($spec in @($common.ciSignals)) {
        if ($null -eq $spec) { continue }
        $p = Join-Path $RepoPath ([string]$spec.path)
        $present = $false
        if (Test-Path -LiteralPath $p -PathType Container) {
            $present = @(Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue).Count -gt 0
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $present = $true
        }
        if ($present) {
            $hasCiSignal = $true
        } else {
            $findings.Add([pscustomobject]@{
                kind              = 'missing-ci-signal'
                target            = [string]$spec.path
                category          = [string]$spec.category
                severity          = [string]$spec.severity
                recommendedAction = [string]$spec.recommendedAction
            })
        }
    }

    $hasTestSignal = _HasTestSignal -LocalPath $RepoPath -RepoType $repoType -Standards $Standards
    if (-not $hasTestSignal -and $null -ne $common.testSignals) {
        $findings.Add([pscustomobject]@{
            kind              = 'missing-test-signal'
            target            = 'tests'
            category          = [string]$common.testSignals.category
            severity          = [string]$common.testSignals.severity
            recommendedAction = [string]$common.testSignals.recommendedAction
        })
    }

    $criticalMissing = @($findings | Where-Object { [string]$_.severity -eq 'critical' }).Count
    $warningMissing  = @($findings | Where-Object { [string]$_.severity -eq 'warning'  }).Count

    return [pscustomobject]@{
        repoType             = $repoType
        findings             = @($findings)
        missingCount         = @($findings).Count
        criticalMissingCount = $criticalMissing
        warningMissingCount  = $warningMissing
        hasTestSignal        = [bool]$hasTestSignal
        hasCiSignal          = [bool]$hasCiSignal
    }
}

# ---------------------------------------------------------------------------
# Lifecycle state resolution — single source of truth
# ---------------------------------------------------------------------------
#
# Precedence (first match wins):
#   archived            isArchived flag set
#   parse-error         roadmap state == parse-error
#   running             execution state == running
#   needs-readme        README missing (any structure finding kind=missing-root-file target=README.md)
#   needs-roadmap       no roadmap on disk
#   needs-roadmap-repair  execution contract is insufficient
#   needs-structure     critical/warning structure findings remain (other than README which was caught above)
#   ready-for-work      shared execution contract is sufficient and has pending items
#   completed           roadmap state == complete
#   monitored           none of the above (clean, stable, no pending work)
#   discovered          fallback when signals were missing
#
# `recommendedAction` is a short operator-facing next-step phrase.
#
# `blockingReasons` is a list of human-readable strings explaining why the repo
# is in this state (or why it's not yet ready) — used by the report and panel
# to make every state self-explanatory.
# ---------------------------------------------------------------------------

function _ResolveLifecycleState {
    param(
        [bool]$IsArchived,
        [string]$RoadmapState,
        [string]$DispatchReadiness,
        [string]$MaturityLevel,
        [string]$ExecutionState,
        [bool]$HasReadme,
        [bool]$HasRoadmap,
        [int]$PendingItemCount,
        [object]$ExecutionContract = $null,
        [object[]]$StructureFindings = @()
    )

    $blocking = [System.Collections.Generic.List[string]]::new()
    $state = ''
    $action = ''

    $safeFindings = @()
    if ($null -ne $StructureFindings) {
        $safeFindings = @($StructureFindings | Where-Object { $null -ne $_ })
    }
    $criticalStruct = @($safeFindings | Where-Object {
        $sev = if ($_.PSObject.Properties.Name -contains 'severity') { [string]$_.severity } else { '' }
        $tgt = if ($_.PSObject.Properties.Name -contains 'target')   { [string]$_.target }   else { '' }
        $sev -eq 'critical' -and $tgt -ne 'README.md'
    })
    $warningStruct  = @($safeFindings | Where-Object {
        $sev = if ($_.PSObject.Properties.Name -contains 'severity') { [string]$_.severity } else { '' }
        $tgt = if ($_.PSObject.Properties.Name -contains 'target')   { [string]$_.target }   else { '' }
        $sev -eq 'warning' -and $tgt -ne 'README.md'
    })

    if ($IsArchived) {
        $state = 'archived'
        $action = 'No action — repo is archived. Restore via settings if work resumes.'
        $blocking.Add('Repository is marked archived.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($RoadmapState -eq 'no-checklist') {
        # The file is readable and the plan is real; this console just cannot
        # track it item-by-item. Say that, and name what would change it —
        # never send the operator to repair a document that is not broken.
        $state = 'no-checklist'
        $action = 'This roadmap plans in prose, not in checklist items. Convert its next actions to "- [ ]" items — or record that it is tracked elsewhere — before this console can rank or dispatch its work.'
        $blocking.Add('The roadmap records no "- [ ]" checklist items, so there is no unit of work to rank or dispatch.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($RoadmapState -eq 'parse-error') {
        $state = 'parse-error'
        $action = 'Open the roadmap and fix the parse error before this repo can be assessed.'
        $blocking.Add('Roadmap could not be parsed.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($ExecutionState -eq 'running') {
        $state = 'running'
        $action = 'Wait for the active Copilot task to complete.'
        $blocking.Add('A Copilot task is already in flight.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if (-not $HasReadme) {
        $state = 'needs-readme'
        $action = "Generate a README first — use the Work Queue 'Generate README' action."
        $blocking.Add('README.md is missing.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if (-not $HasRoadmap) {
        $state = 'needs-roadmap'
        $action = 'Run repo evaluation to draft a roadmap from the current code and docs.'
        $blocking.Add('No ROADMAP.md found.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    $executionSufficient = ($null -ne $ExecutionContract -and [bool](_GetField -Obj $ExecutionContract -Name 'sufficient' -Default $false))
    if (-not $executionSufficient -and $RoadmapState -ne 'complete') {
        $state = 'needs-roadmap-repair'
        $action = 'Open the Roadmap Repair preview and complete the named execution-contract gap.'
        $blocking.Add([string](_GetField -Obj $ExecutionContract -Name 'explanation' -Default 'Execution-contract sufficiency could not be established.')) | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($criticalStruct.Count -gt 0 -or $warningStruct.Count -gt 0) {
        $state = 'needs-structure'
        $missing = @($criticalStruct + $warningStruct | ForEach-Object { [string]$_.target })
        $action = ('Add missing structural elements: {0}.' -f ($missing -join ', '))
        foreach ($f in $criticalStruct + $warningStruct) {
            $blocking.Add(("Missing {0} ({1})" -f $f.target, $f.severity)) | Out-Null
        }
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($DispatchReadiness -in @('needs-doc-standardization','blocked') -and $PendingItemCount -gt 0) {
        $state = 'needs-structure'
        $action = 'Resolve outstanding documentation findings before dispatching.'
        $blocking.Add(("Dispatch readiness is '{0}'." -f $DispatchReadiness)) | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($executionSufficient -and $PendingItemCount -gt 0) {
        # The same execution-contract verdict is consumed by interactive
        # dispatch and scheduled packaging. Doc-audit remains a supporting
        # signal rather than a second private readiness model.
        $state = 'ready-for-work'
        $action = 'Dispatch the next pending roadmap item to Copilot.'
        return @{ state = $state; recommendedAction = $action; blockingReasons = @() }
    }
    if ($RoadmapState -eq 'complete') {
        $state = 'completed'
        $action = 'No pending work — consider drafting a follow-up release or marking monitored.'
        return @{ state = $state; recommendedAction = $action; blockingReasons = @() }
    }
    if ($PendingItemCount -eq 0) {
        $state = 'monitored'
        $action = 'No pending work and no blockers — keep monitored.'
        return @{ state = $state; recommendedAction = $action; blockingReasons = @() }
    }

    # Fallback: signals were inconsistent or partial.
    return @{
        state             = 'discovered'
        recommendedAction = 'Re-run a portfolio scan to refresh roadmap, docs-audit, and maturity signals.'
        blockingReasons   = @('Assessment signals are incomplete; rescan recommended.')
    }
}

# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

function _NormalizeKey { param([string]$Value) return ([string]$Value).ToLowerInvariant() }

function _NormalizePathKey {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([string]$Value).Trim().TrimEnd('\', '/').Replace('/', '\').ToLowerInvariant()
}

function _IndexByRepoPath {
    param([object[]]$Items, [string]$PathField = 'repoPath')
    $map = @{}
    foreach ($it in @($Items)) {
        if ($null -eq $it) { continue }
        $value = ''
        if ($it -is [System.Collections.IDictionary]) {
            if ($it.Contains($PathField)) { $value = [string]$it[$PathField] }
        } elseif ($it.PSObject.Properties.Name -contains $PathField) {
            $value = [string]$it.$PathField
        }
        $pathKey = _NormalizePathKey $value
        if ([string]::IsNullOrWhiteSpace($pathKey)) { continue }
        $map[$pathKey] = $it
    }
    return $map
}

# A repository's identity is where it lives, not what its folder is called.
# Joining scanner output on the folder name silently dropped every repo whose
# local directory differs from its GitHub name: on 2026-08-27 the live index
# reported CupHandleDetectionv2 (in a folder called CupHandleDetection) and
# GenesysCloud-API-Explorer_v3 (in GenesysCloudOpsConsole) as having no roadmap
# at all -- L0-Absent, needs-roadmap, dispatch blocked -- while the second of
# those had 53 pending items on disk. The scanners key their output by folder
# name and the index keys repos by remote name, so the two never met. Prefer the
# path, which both sides already carry, and keep the name as the fallback for
# synthetic callers that have no path.
function _ResolveScanEntry {
    param(
        [hashtable]$PathMap,
        [hashtable]$NameMap,
        [string]$PathKey,
        [string]$NameKey
    )
    if ($null -ne $PathMap -and -not [string]::IsNullOrWhiteSpace($PathKey) -and $PathMap.ContainsKey($PathKey)) {
        return $PathMap[$PathKey]
    }
    if ($null -ne $NameMap -and -not [string]::IsNullOrWhiteSpace($NameKey) -and $NameMap.ContainsKey($NameKey)) {
        return $NameMap[$NameKey]
    }
    return $null
}

function _IndexByRepoName {
    param([object[]]$Items, [string]$NameField = 'repoName')
    $map = @{}
    foreach ($it in @($Items)) {
        if ($null -eq $it) { continue }
        $name = ''
        if ($it -is [System.Collections.IDictionary]) {
            if ($it.Contains($NameField)) { $name = [string]$it[$NameField] }
        } elseif ($it.PSObject.Properties.Name -contains $NameField) {
            $name = [string]$it.$NameField
        }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $map[(_NormalizeKey $name)] = $it
    }
    return $map
}

function _GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

function Select-CanonicalLocalCheckout {
    <#
    .SYNOPSIS
        Pure -- decide which local checkout represents a repository when the
        same repository has been cloned more than once.

    .DESCRIPTION
        Two clones of one repository reach the assessment as two rows under one
        identity. Dropping whichever arrived second made the portfolio depend on
        directory enumeration order: for MusicLibrary_v2 the index snapshot kept
        the active checkout and the status cache kept the archived one, on the
        same day, for the same repository (Lane 0.12). Whichever survived, the
        other vanished with no trace -- so the operator could not tell that a
        second checkout existed, let alone that the wrong one was on screen.

        Preference, in order, so the answer is a property of the checkouts and
        never of the order they happened to be read in:

          1. a checkout the scope policy left IN SCOPE beats one it excluded
             (archived / vendored / excluded-path) -- filing a clone under
             Archive/ is the operator's own answer to this question
          2. a folder name matching the repository name beats one that differs
             -- the rule Select-CanonicalRoadmapFile already applies to files
          3. ordinal path comparison -- a stable tiebreak, so enumeration order
             decides nothing even when the checkouts are otherwise equivalent

        Returns the winner AND the checkouts it displaced. A discarded clone
        that leaves no record is the failure this function exists to prevent.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowEmptyCollection()][object[]]$Candidates = @())

    $list = @(@($Candidates) | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return $null }
    if ($list.Count -eq 1) {
        return [pscustomobject]@{ winner = $list[0]; dropped = @(); reason = '' }
    }

    $describe = {
        param([object]$Repo)
        $path = [string](_GetField -Obj $Repo -Name 'path' -Default (_GetField -Obj $Repo -Name 'localPath' -Default ''))
        $scope = _GetField -Obj $Repo -Name 'scope' -Default $null
        # No scope block at all means the classifier never ran; treat it as in
        # scope rather than inventing an exclusion this repo never earned.
        $inScope = if ($null -eq $scope) { $true } else { [bool](_GetField -Obj $scope -Name 'inScope' -Default $true) }
        $name = [string](_GetField -Obj $Repo -Name 'name' -Default '')
        $folder = [string](_GetField -Obj $Repo -Name 'folderName' -Default '')
        if ([string]::IsNullOrWhiteSpace($folder) -and -not [string]::IsNullOrWhiteSpace($path)) {
            $folder = Split-Path -Path ($path.TrimEnd('\', '/')) -Leaf
        }
        [pscustomobject]@{
            repo          = $Repo
            path          = $path
            inScope       = $inScope
            folderMatches = ((-not [string]::IsNullOrWhiteSpace($folder)) -and ((_NormalizeKey $folder) -eq (_NormalizeKey $name)))
            scopeReason   = [string](_GetField -Obj $scope -Name 'reason' -Default '')
        }
    }

    $ordered = @(@($list | ForEach-Object { & $describe $_ }) | Sort-Object `
            @{ Expression = { -not $_.inScope }; Ascending = $true }, `
            @{ Expression = { -not $_.folderMatches }; Ascending = $true }, `
            @{ Expression = { _NormalizePathKey $_.path }; Ascending = $true })

    $winner = $ordered[0]
    $losers = @($ordered | Select-Object -Skip 1)

    $why = if ($winner.inScope -and @($losers | Where-Object { -not $_.inScope }).Count -gt 0) {
        'it is the working-portfolio checkout and the others sit outside the scope policy'
    } elseif ($winner.folderMatches -and @($losers | Where-Object { -not $_.folderMatches }).Count -gt 0) {
        'its folder name matches the repository name'
    } else {
        'it sorts first by path; the checkouts are otherwise equivalent'
    }

    return [pscustomobject]@{
        winner  = $winner.repo
        dropped = @($losers | ForEach-Object {
                [pscustomobject]@{
                    localPath = $_.path
                    inScope   = $_.inScope
                    reason    = $_.scopeReason
                }
            })
        reason  = ("Selected {0} because {1}." -f $winner.path, $why)
    }
}

function _GetPendingRoadmapItems {
    param([object]$RoadmapEntry, [object]$MaturityEntry)

    $source = if ($null -ne $MaturityEntry) { $MaturityEntry } else { $RoadmapEntry }
    $items = [System.Collections.Generic.List[object]]::new()
    $nextPending = _GetField -Obj $source -Name 'nextPendingItem' -Default (_GetField -Obj $RoadmapEntry -Name 'nextPendingItem' -Default $null)
    $nextText = if ($null -ne $nextPending) { [string](_GetField -Obj $nextPending -Name 'text' -Default '') } else { '' }
    $nextTags = if ($null -ne $nextPending) { @(_GetField -Obj $nextPending -Name 'tags' -Default @() | ForEach-Object { [string]$_ }) } else { @() }

    foreach ($sec in @(_GetField -Obj $source -Name 'sections' -Default @())) {
        if ($null -eq $sec) { continue }
        $sectionName = [string](_GetField -Obj $sec -Name 'name' -Default '')
        foreach ($pending in @(_GetField -Obj $sec -Name 'pendingItems' -Default @())) {
            $text = [string]$pending
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $tags = if (-not [string]::IsNullOrWhiteSpace($nextText) -and $text -eq $nextText) { $nextTags } else { @() }
            $items.Add([pscustomobject]@{
                text    = $text
                section = $sectionName
                tags    = @($tags)
            }) | Out-Null
        }
    }

    if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($nextText)) {
        $items.Add([pscustomobject]@{
            text    = $nextText
            section = [string](_GetField -Obj $nextPending -Name 'section' -Default '')
            tags    = @($nextTags)
        }) | Out-Null
    }

    return $items.ToArray()
}

function _ScorePendingRoadmapItems {
    param(
        [object[]]$PendingItems = @(),
        [object]$RepoContext,
        [object]$ValueScoringConfig
    )

    if (@($PendingItems).Count -eq 0) { return @() }
    if (Get-Command -Name Invoke-PortfolioValueScores -ErrorAction SilentlyContinue) {
        return @(Invoke-PortfolioValueScores -PendingItems $PendingItems -RepoContext $RepoContext -ScoringConfig $ValueScoringConfig)
    }

    $fallback = [System.Collections.Generic.List[object]]::new()
    $i = 0
    foreach ($item in @($PendingItems)) {
        $fallback.Add([pscustomobject]@{
            text           = [string](_GetField -Obj $item -Name 'text' -Default '')
            section        = [string](_GetField -Obj $item -Name 'section' -Default '')
            tags           = @(_GetField -Obj $item -Name 'tags' -Default @() | ForEach-Object { [string]$_ })
            roadmapOrder   = $i + 1
            valueScore     = 0
            valueTier      = 'unscored'
            valueRationale = @('value scorer module was not loaded')
            scoringSignals = [pscustomobject]@{}
        }) | Out-Null
        $i++
    }
    return $fallback.ToArray()
}

function _SelectTopValueItem {
    param([object[]]$ScoredItems = @())

    $validItems = [System.Collections.Generic.List[object]]::new()
    foreach ($scored in @($ScoredItems)) {
        if ($null -eq $scored) { continue }
        if ($scored -is [System.Array]) {
            foreach ($nested in @($scored)) {
                if ($null -ne $nested) { $validItems.Add($nested) | Out-Null }
            }
            continue
        }
        $validItems.Add($scored) | Out-Null
    }

    if ($validItems.Count -eq 0) { return $null }
    $selected = @($validItems.ToArray() | Sort-Object `
        @{ Expression = { [int](_GetField -Obj $_ -Name 'valueScore' -Default 0) }; Descending = $true },
        @{ Expression = { [int](_GetField -Obj $_ -Name 'roadmapOrder' -Default 999999) }; Ascending = $true } |
        Select-Object -First 1)
    if ($selected.Count -eq 0) { return $null }
    return $selected[0]
}

# ---------------------------------------------------------------------------
# Main orchestrator
# ---------------------------------------------------------------------------

function Invoke-PortfolioAssessment {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$LocalRepos = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$RoadmapEntries      = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$DocAuditEntries     = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$RoadmapAuditEntries = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$ExecutionEntries    = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$GitHubRepos         = @(),
        [Parameter()][object]$StructureStandards,
        [Parameter()][object]$ValueScoringConfig
    )

    $roadmapMap     = _IndexByRepoName -Items $RoadmapEntries     -NameField 'repoName'
    $docAuditMap    = _IndexByRepoName -Items $DocAuditEntries    -NameField 'repoName'
    $maturityMap    = _IndexByRepoName -Items $RoadmapAuditEntries -NameField 'repoName'
    $executionMap   = _IndexByRepoName -Items $ExecutionEntries   -NameField 'repoName'
    $githubMap      = _IndexByRepoName -Items $GitHubRepos        -NameField 'name'

    # Path-keyed companions. Every local scanner records the directory it read,
    # so these join correctly even when the folder name and the remote name
    # disagree; the name maps above remain the fallback.
    $roadmapPathMap  = _IndexByRepoPath -Items $RoadmapEntries      -PathField 'repoPath'
    $docAuditPathMap = _IndexByRepoPath -Items $DocAuditEntries     -PathField 'repoPath'
    $maturityPathMap = _IndexByRepoPath -Items $RoadmapAuditEntries -PathField 'repoPath'
    $execPathMap     = _IndexByRepoPath -Items $ExecutionEntries    -PathField 'repoPath'

    $assessments = [System.Collections.Generic.List[object]]::new()
    $seenLocalKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Lane 0.12 -- group the checkouts BEFORE the loop and decide once. Deciding
    # inside it ("first one wins") made the surviving clone a function of
    # directory enumeration order, and silently discarded the other.
    $checkoutsByKey = @{}
    foreach ($candidate in @($LocalRepos)) {
        if ($null -eq $candidate) { continue }
        $candidateName = [string](_GetField -Obj $candidate -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($candidateName)) { continue }
        $candidateKey = _NormalizeKey $candidateName
        if (-not $checkoutsByKey.ContainsKey($candidateKey)) {
            $checkoutsByKey[$candidateKey] = [System.Collections.Generic.List[object]]::new()
        }
        $checkoutsByKey[$candidateKey].Add($candidate) | Out-Null
    }
    $canonicalByKey = @{}
    foreach ($candidateKey in @($checkoutsByKey.Keys)) {
        $canonicalByKey[$candidateKey] = Select-CanonicalLocalCheckout -Candidates @($checkoutsByKey[$candidateKey].ToArray())
    }

    foreach ($repo in @($LocalRepos)) {
        if ($null -eq $repo) { continue }
        $repoName = [string](_GetField -Obj $repo -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
        $key = _NormalizeKey $repoName
        if (-not $seenLocalKeys.Add($key)) { continue }

        # One row per repository, but the row is the CHOSEN checkout — not
        # whichever one this loop reached first — and it names the ones it
        # displaced so a second clone can never vanish unremarked.
        $duplicateCheckouts = $null
        $canonical = $canonicalByKey[$key]
        if ($null -ne $canonical -and @($canonical.dropped).Count -gt 0) {
            $repo = $canonical.winner
            $duplicateCheckouts = [pscustomobject]@{
                selectedPath    = [string](_GetField -Obj $canonical.winner -Name 'path' -Default (_GetField -Obj $canonical.winner -Name 'localPath' -Default ''))
                selectionReason = [string]$canonical.reason
                dropped         = @($canonical.dropped)
            }
        }

        # Status-scan repos expose the repo directory as 'path'; only synthetic
        # callers (fixtures, index conversions) use 'localPath'. Accept both —
        # reading 'localPath' alone left every real assessment and index row
        # with an empty local path (and pushed repoId onto gh:/repo: keys).
        $localPath  = [string](_GetField -Obj $repo -Name 'localPath' -Default (_GetField -Obj $repo -Name 'path' -Default ''))
        $isArchived = [bool](_GetField -Obj $repo -Name 'isArchived' -Default $false)
        $htmlUrl    = [string](_GetField -Obj $repo -Name 'htmlUrl' -Default '')
        $branch     = [string](_GetField -Obj $repo -Name 'branch' -Default '')
        $gitStatus  = [string](_GetField -Obj $repo -Name 'status' -Default 'unknown')
        $pathKey    = _NormalizePathKey $localPath

        # Roadmap state
        $roadmapEntry = _ResolveScanEntry -PathMap $roadmapPathMap -NameMap $roadmapMap -PathKey $pathKey -NameKey $key
        $roadmapPath  = [string](_GetField -Obj $roadmapEntry -Name 'roadmapPath' -Default '')
        $roadmapState = [string](_GetField -Obj $roadmapEntry -Name 'roadmapState' -Default 'missing')
        $hasRoadmap   = -not [string]::IsNullOrWhiteSpace($roadmapPath) -and (Test-Path -LiteralPath $roadmapPath -ErrorAction SilentlyContinue)
        $pendingCount = [int](_GetField -Obj $roadmapEntry -Name 'pendingCount' -Default 0)
        $nextItemRaw  = _GetField -Obj $roadmapEntry -Name 'nextPendingItem' -Default $null
        $nextItemText = if ($null -ne $nextItemRaw) { [string](_GetField -Obj $nextItemRaw -Name 'text' -Default '') } else { '' }
        $activeRelease = _GetField -Obj $roadmapEntry -Name 'activeRelease' -Default $null
        $activePhasePlan = _GetField -Obj $roadmapEntry -Name 'activePhasePlan' -Default $null
        $budgetGuardrail = _GetField -Obj $roadmapEntry -Name 'budgetGuardrail' -Default $null
        $estimatedSessionWorkUnits = if ($null -ne $activePhasePlan) {
            _GetField -Obj $activePhasePlan -Name 'workUnitsEstimated' -Default (_GetField -Obj $roadmapEntry -Name 'estimatedSessionWorkUnits' -Default $null)
        } else {
            _GetField -Obj $roadmapEntry -Name 'estimatedSessionWorkUnits' -Default $null
        }

        # Doc audit
        $docEntry = _ResolveScanEntry -PathMap $docAuditPathMap -NameMap $docAuditMap -PathKey $pathKey -NameKey $key
        $rawDispatchReadiness = [string](_GetField -Obj $docEntry -Name 'dispatchReadiness' -Default 'missing-roadmap')
        $docFindings = @()
        $rawDocFindings = _GetField -Obj $docEntry -Name 'docFindings' -Default @()
        if ($null -ne $rawDocFindings) { $docFindings = @($rawDocFindings | Where-Object { $null -ne $_ }) }
        $hasReadme = $true
        if ($null -ne $docEntry) {
            $missingReadme = @($docFindings | Where-Object {
                ([string](_GetField -Obj $_ -Name 'file' -Default '')) -eq 'README.md' -and
                ([string](_GetField -Obj $_ -Name 'message' -Default '')) -match 'missing'
            })
            $hasReadme = $missingReadme.Count -eq 0
        } elseif (-not [string]::IsNullOrWhiteSpace($localPath)) {
            $hasReadme = Test-Path -LiteralPath (Join-Path $localPath 'README.md') -PathType Leaf
        }

        # Roadmap maturity
        $maturityEntry = _ResolveScanEntry -PathMap $maturityPathMap -NameMap $maturityMap -PathKey $pathKey -NameKey $key
        $maturityLevel = [string](_GetField -Obj $maturityEntry -Name 'maturityLevel' -Default 'L0-Absent')
        $maturityScore = [int](_GetField -Obj $maturityEntry -Name 'maturityScore' -Default 0)

        # Execution
        $execEntry = _ResolveScanEntry -PathMap $execPathMap -NameMap $executionMap -PathKey $pathKey -NameKey $key
        $execState = [string](_GetField -Obj $execEntry -Name 'executionState' -Default 'idle')

        # Structure audit
        $structAudit = $null
        if (-not [string]::IsNullOrWhiteSpace($localPath) -and (Test-Path -LiteralPath $localPath -ErrorAction SilentlyContinue)) {
            $structAudit = Invoke-RepoStructureAudit -RepoPath $localPath -Standards $StructureStandards
        }
        $structFindings = if ($null -ne $structAudit) { @($structAudit.findings) } else { @() }
        $repoType = if ($null -ne $structAudit) { [string]$structAudit.repoType } else { 'other' }

        $roadmapExecutionContext = if ($null -ne $activeRelease) { $activeRelease } else { $roadmapEntry }
        $executionContract = if (($null -ne (Get-Command -Name 'Test-RoadmapExecutionContract' -ErrorAction SilentlyContinue)) -and $null -ne $roadmapExecutionContext) {
            Test-RoadmapExecutionContract `
                -RoadmapContext $roadmapExecutionContext `
                -MaturityLevel $maturityLevel `
                -RepoType $repoType
        } else {
            [pscustomobject]@{
                schemaVersion = '1.0'
                model = 'execution-contract-sufficiency'
                sufficient = $false
                code = 'execution-contract-evaluator-unavailable'
                explanation = 'Execution-contract sufficiency could not be evaluated.'
                maturityLevel = $maturityLevel
                repoType = $repoType
                selectedTask = $null
                checks = @()
            }
        }

        $githubRepo = if ($githubMap.ContainsKey($key)) { $githubMap[$key] } else { $null }

        # Source coverage
        $sourceCoverage = if ($githubMap.ContainsKey($key) -or -not [string]::IsNullOrWhiteSpace($htmlUrl)) {
            'local+github'
        } else {
            'local'
        }

        $lifecycle = _ResolveLifecycleState `
            -IsArchived $isArchived `
            -RoadmapState $roadmapState `
            -DispatchReadiness $rawDispatchReadiness `
            -MaturityLevel $maturityLevel `
            -ExecutionState $execState `
            -HasReadme $hasReadme `
            -HasRoadmap $hasRoadmap `
            -PendingItemCount $pendingCount `
            -ExecutionContract $executionContract `
            -StructureFindings $structFindings

        $dispatchReadiness = _Get-EffectiveDispatchReadiness `
            -RawDispatchReadiness $rawDispatchReadiness `
            -LifecycleState $lifecycle.state `
            -HasReadme $hasReadme `
            -HasRoadmap $hasRoadmap `
            -RoadmapState $roadmapState `
            -PendingItemCount $pendingCount

        $pendingItemsRaw = @(_GetPendingRoadmapItems -RoadmapEntry $roadmapEntry -MaturityEntry $maturityEntry)
        $hasCiSignal = if ($null -ne $structAudit) { [bool]$structAudit.hasCiSignal } else { $false }
        $hasTestSignal = if ($null -ne $structAudit) { [bool]$structAudit.hasTestSignal } else { $false }
        $repoContext = [pscustomobject]@{
            repoName          = $repoName
            repoType          = $repoType
            lifecycleState    = $lifecycle.state
            maturityLevel     = $maturityLevel
            maturityScore     = $maturityScore
            dispatchReadiness = $dispatchReadiness
            hasCiSignal       = $hasCiSignal
            hasTestSignal     = $hasTestSignal
            sourceCoverage    = $sourceCoverage
            docFindingCount   = @($docFindings).Count
            pendingItemCount  = $pendingCount
        }
        $scoredPendingItems = @(_ScorePendingRoadmapItems -PendingItems $pendingItemsRaw -RepoContext $repoContext -ValueScoringConfig $ValueScoringConfig)
        $topValueItem = _SelectTopValueItem -ScoredItems $scoredPendingItems
        $readmeScore = _Get-ReadmeScore -HasReadme $hasReadme -DocFindingCount @($docFindings).Count
        $roadmapScore = _Get-RoadmapScore -HasRoadmap $hasRoadmap -RoadmapState $roadmapState -MaturityScore $maturityScore -PendingItemCount $pendingCount
        $documentationHealthScore = _Get-DocumentationHealthScore -ReadmeScore $readmeScore -RoadmapScore $roadmapScore -DocFindingCount @($docFindings).Count -HasCiSignal $hasCiSignal -HasTestSignal $hasTestSignal
        $dispatchReadinessExplanation = if ($dispatchReadiness -ne 'ready' -and @($lifecycle.blockingReasons).Count -gt 0) {
            [string]$lifecycle.blockingReasons[0]
        } else {
            _Get-DispatchReadinessExplanation -DispatchReadiness $dispatchReadiness
        }
        $openPrCount = [int](_GetField -Obj $githubRepo -Name 'openPrCount' -Default (_GetField -Obj $repo -Name 'openPrCount' -Default 0))
        $pendingReviewPrCount = [int](_GetField -Obj $githubRepo -Name 'pendingReviewPrCount' -Default (_GetField -Obj $repo -Name 'pendingReviewPrCount' -Default 0))

        $assessments.Add([pscustomobject]@{
            repoName            = $repoName
            localPath           = $localPath
            htmlUrl             = $htmlUrl
            branch              = $branch
            gitStatus           = $gitStatus
            isArchived          = $isArchived
            sourceCoverage      = $sourceCoverage
            hasPages            = [bool](_GetField -Obj $githubRepo -Name 'hasPages' -Default (_GetField -Obj $repo -Name 'hasPages' -Default $false))
            pagesUrl            = _GetField -Obj $githubRepo -Name 'pagesUrl' -Default (_GetField -Obj $repo -Name 'pagesUrl' -Default $null)
            createdAt           = _GetField -Obj $githubRepo -Name 'createdAt' -Default (_GetField -Obj $repo -Name 'createdAt' -Default $null)
            updatedAt           = _GetField -Obj $githubRepo -Name 'updatedAt' -Default (_GetField -Obj $repo -Name 'updatedAt' -Default $null)
            latestWorkflowRunStatus = _GetField -Obj $githubRepo -Name 'latestWorkflowRunStatus' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunStatus' -Default $null)
            latestWorkflowRunConclusion = _GetField -Obj $githubRepo -Name 'latestWorkflowRunConclusion' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunConclusion' -Default $null)
            latestWorkflowRunName = _GetField -Obj $githubRepo -Name 'latestWorkflowRunName' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunName' -Default $null)
            latestWorkflowRunTimestamp = _GetField -Obj $githubRepo -Name 'latestWorkflowRunTimestamp' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunTimestamp' -Default $null)
            openPrCount         = $openPrCount
            pendingReviewPrCount = $pendingReviewPrCount
            repoType            = $repoType
            lifecycleState      = $lifecycle.state
            recommendedAction   = $lifecycle.recommendedAction
            blockingReasons     = @($lifecycle.blockingReasons)
            roadmapState        = $roadmapState
            roadmapPath         = $roadmapPath
            hasRoadmap          = [bool]$hasRoadmap
            pendingCount        = $pendingCount
            nextPendingItem     = $nextItemRaw
            pendingItemCount    = $pendingCount
            nextPendingItemText = $nextItemText
            pendingItems        = @($scoredPendingItems)
            topValueItem        = $topValueItem
            activeRelease       = $activeRelease
            activePhasePlan     = $activePhasePlan
            budgetGuardrail     = $budgetGuardrail
            estimatedSessionWorkUnits = $estimatedSessionWorkUnits
            maturityLevel       = $maturityLevel
            maturityScore       = $maturityScore
            dispatchReadiness   = $dispatchReadiness
            executionContract   = $executionContract
            executionState      = $execState
            hasReadme           = [bool]$hasReadme
            readmeScore         = $readmeScore
            roadmapScore        = $roadmapScore
            documentationHealthScore = $documentationHealthScore
            hasCiSignal         = if ($null -ne $structAudit) { [bool]$structAudit.hasCiSignal } else { $false }
            hasTestSignal       = if ($null -ne $structAudit) { [bool]$structAudit.hasTestSignal } else { $false }
            structureFindings   = @($structFindings)
            docFindingCount     = @($docFindings).Count
            dispatchReadinessExplanation = $dispatchReadinessExplanation
            duplicateCheckouts  = $duplicateCheckouts
        }) | Out-Null
    }

    # GitHub-only repos — those discovered on GitHub but not present locally.
    foreach ($gh in @($GitHubRepos)) {
        if ($null -eq $gh) { continue }
        $name = [string](_GetField -Obj $gh -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $key = _NormalizeKey $name
        if ($seenLocalKeys.Contains($key)) { continue }

        $assessments.Add([pscustomobject]@{
            repoName            = $name
            localPath           = ''
            htmlUrl             = [string](_GetField -Obj $gh -Name 'htmlUrl' -Default '')
            branch              = [string](_GetField -Obj $gh -Name 'branch' -Default '')
            gitStatus           = 'unknown'
            isArchived          = [bool](_GetField -Obj $gh -Name 'isArchived' -Default $false)
            sourceCoverage      = 'github'
            hasPages            = [bool](_GetField -Obj $gh -Name 'hasPages' -Default $false)
            pagesUrl            = _GetField -Obj $gh -Name 'pagesUrl' -Default $null
            createdAt           = _GetField -Obj $gh -Name 'createdAt' -Default $null
            updatedAt           = _GetField -Obj $gh -Name 'updatedAt' -Default $null
            latestWorkflowRunStatus = _GetField -Obj $gh -Name 'latestWorkflowRunStatus' -Default $null
            latestWorkflowRunConclusion = _GetField -Obj $gh -Name 'latestWorkflowRunConclusion' -Default $null
            latestWorkflowRunName = _GetField -Obj $gh -Name 'latestWorkflowRunName' -Default $null
            latestWorkflowRunTimestamp = _GetField -Obj $gh -Name 'latestWorkflowRunTimestamp' -Default $null
            openPrCount         = [int](_GetField -Obj $gh -Name 'openPrCount' -Default 0)
            pendingReviewPrCount = [int](_GetField -Obj $gh -Name 'pendingReviewPrCount' -Default 0)
            repoType            = 'other'
            lifecycleState      = 'discovered'
            recommendedAction   = 'Clone the repo locally so it can participate in the work queue.'
            blockingReasons     = @('Repository exists on GitHub but is not present in any configured local root.')
            roadmapState        = 'missing'
            roadmapPath         = ''
            hasRoadmap          = $false
            pendingCount        = 0
            nextPendingItem     = $null
            pendingItemCount    = 0
            nextPendingItemText = ''
            pendingItems        = @()
            topValueItem        = $null
            activeRelease       = $null
            activePhasePlan     = $null
            budgetGuardrail     = $null
            estimatedSessionWorkUnits = $null
            maturityLevel       = 'L0-Absent'
            maturityScore       = 0
            dispatchReadiness   = 'missing-roadmap'
            executionContract   = $null
            executionState      = 'idle'
            hasReadme           = $false
            readmeScore         = 0
            roadmapScore        = 0
            documentationHealthScore = 0
            hasCiSignal         = $false
            hasTestSignal       = $false
            structureFindings   = @()
            docFindingCount     = 0
            dispatchReadinessExplanation = (_Get-DispatchReadinessExplanation -DispatchReadiness 'missing-roadmap')
        }) | Out-Null
    }

    return ,@($assessments)
}

# ---------------------------------------------------------------------------
# Portfolio summary aggregation — used by the dashboard mission panel.
# ---------------------------------------------------------------------------

function Get-PortfolioAssessmentSummary {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyCollection()][object[]]$Assessments = @())

    $entries = @($Assessments)
    $total = $entries.Count

    $byLifecycle = @{}
    foreach ($state in @(
        'discovered','needs-readme','needs-roadmap','needs-roadmap-repair',
        'needs-structure','ready-for-work','running','completed','monitored',
        'archived','no-checklist','parse-error'
    )) { $byLifecycle[$state] = 0 }

    $byCoverage = @{ 'local' = 0; 'github' = 0; 'local+github' = 0 }
    $missingReadme = 0
    $missingRoadmap = 0
    $weakRoadmap = 0
    $readyForWork = 0
    $running = 0
    $blocked = 0

    foreach ($a in $entries) {
        $lc = [string](_GetField -Obj $a -Name 'lifecycleState' -Default 'discovered')
        if ($byLifecycle.ContainsKey($lc)) { $byLifecycle[$lc] = $byLifecycle[$lc] + 1 } else { $byLifecycle[$lc] = 1 }

        $cov = [string](_GetField -Obj $a -Name 'sourceCoverage' -Default 'local')
        if ($byCoverage.ContainsKey($cov)) { $byCoverage[$cov] = $byCoverage[$cov] + 1 } else { $byCoverage[$cov] = 1 }

        if (-not [bool](_GetField -Obj $a -Name 'hasReadme' -Default $true)) { $missingReadme++ }
        if (-not [bool](_GetField -Obj $a -Name 'hasRoadmap' -Default $true)) { $missingRoadmap++ }

        $ml = [string](_GetField -Obj $a -Name 'maturityLevel' -Default 'L0-Absent')
        if ($ml -in @('L0-Absent','L1-Informal','L2-Structured') -and [bool](_GetField -Obj $a -Name 'hasRoadmap' -Default $false)) {
            $weakRoadmap++
        }

        switch ($lc) {
            'ready-for-work' { $readyForWork++ }
            'running'        { $running++ }
            'needs-readme'    { $blocked++ }
            'needs-roadmap'   { $blocked++ }
            'needs-roadmap-repair' { $blocked++ }
            'needs-structure' { $blocked++ }
            'no-checklist'    { $blocked++ }
            'parse-error'     { $blocked++ }
        }
    }

    return [pscustomobject]@{
        totalRepos     = $total
        byLifecycle    = $byLifecycle
        bySourceCoverage = $byCoverage
        missingReadmeCount    = $missingReadme
        missingRoadmapCount   = $missingRoadmap
        weakRoadmapCount      = $weakRoadmap
        readyForWorkCount     = $readyForWork
        runningCount          = $running
        blockedCount          = $blocked
    }
}

function _ClampScore {
    param([int]$Value)

    if ($Value -lt 0) { return 0 }
    if ($Value -gt 100) { return 100 }
    return $Value
}

function _Get-DispatchReadinessExplanation {
    param([string]$DispatchReadiness)

    switch ([string]$DispatchReadiness) {
        'ready' {
            return 'Documentation and roadmap signals are strong enough for dispatch.'
        }
        'needs-doc-standardization' {
            return 'Core docs exist, but the repo still needs documentation cleanup before dispatch.'
        }
        'roadmap-complete' {
            return 'The roadmap has no pending work, so dispatch should move to a new release or maintenance task.'
        }
        'no-checklist' {
            return 'The roadmap was read in full and records no "- [ ]" checklist items, so this console has no unit of work to dispatch. The file is not damaged.'
        }
        'parse-error' {
            return 'The roadmap exists, but it could not be parsed into the standard contract format.'
        }
        'blocked' {
            return 'Blocking findings prevent reliable execution and should be resolved before dispatch.'
        }
        default {
            return 'A roadmap or supporting documentation is missing, so the repo is not yet dispatch-ready.'
        }
    }
}

function _Get-EffectiveDispatchReadiness {
    param(
        [string]$RawDispatchReadiness,
        [string]$LifecycleState,
        [bool]$HasReadme,
        [bool]$HasRoadmap,
        [string]$RoadmapState,
        [int]$PendingItemCount
    )

    if (-not $HasReadme) { return 'blocked' }
    if (-not $HasRoadmap) { return 'missing-roadmap' }

    switch ([string]$RoadmapState) {
        'no-checklist' { return 'no-checklist' }
        'parse-error' { return 'parse-error' }
        'complete' { return 'roadmap-complete' }
    }

    if ($PendingItemCount -le 0) {
        return 'roadmap-complete'
    }

    switch ([string]$LifecycleState) {
        'ready-for-work' { return 'ready' }
        'needs-roadmap-repair' { return 'blocked' }
        'running' { return 'blocked' }
        'archived' { return 'blocked' }
        'no-checklist' { return 'no-checklist' }
        'parse-error' { return 'parse-error' }
        'needs-roadmap' { return 'missing-roadmap' }
        'needs-readme' { return 'blocked' }
        'needs-structure' {
            if ($RawDispatchReadiness -in @('needs-doc-standardization', 'blocked')) {
                return [string]$RawDispatchReadiness
            }
            return 'blocked'
        }
        'completed' { return 'roadmap-complete' }
        'monitored' { return 'roadmap-complete' }
    }

    if ($RawDispatchReadiness -in @('ready', 'needs-doc-standardization', 'missing-roadmap', 'roadmap-complete', 'parse-error', 'blocked')) {
        return [string]$RawDispatchReadiness
    }

    return 'blocked'
}

function _Get-ReadmeScore {
    param(
        [bool]$HasReadme,
        [int]$DocFindingCount
    )

    if (-not $HasReadme) { return 0 }

    $penalty = [Math]::Min(25, ([Math]::Max(0, $DocFindingCount) * 5))
    return _ClampScore -Value (100 - $penalty)
}

function _Get-RoadmapScore {
    param(
        [bool]$HasRoadmap,
        [string]$RoadmapState,
        [int]$MaturityScore,
        [int]$PendingItemCount
    )

    if (-not $HasRoadmap) { return 0 }

    switch ([string]$RoadmapState) {
        'no-checklist' {
            # A real plan this console cannot track item-by-item. Scoring it as
            # a damaged file understated repositories carrying 200 KB of
            # roadmap; the maturity auditor still reads their structure, so
            # take whichever signal is stronger.
            return _ClampScore -Value ([Math]::Max(40, $MaturityScore))
        }
        'parse-error' {
            return 20
        }
        'complete' {
            return _ClampScore -Value ([Math]::Max(90, $MaturityScore))
        }
        'pending' {
            $base = [Math]::Max(55, $MaturityScore)
            if ($PendingItemCount -le 3) { $base += 10 }
            return _ClampScore -Value $base
        }
        default {
            return _ClampScore -Value ([Math]::Max(35, $MaturityScore))
        }
    }
}

function _Get-DocumentationHealthScore {
    param(
        [int]$ReadmeScore,
        [int]$RoadmapScore,
        [int]$DocFindingCount,
        [bool]$HasCiSignal,
        [bool]$HasTestSignal
    )

    $base = [Math]::Round((([double]$ReadmeScore) + ([double]$RoadmapScore)) / 2.0)
    $bonus = 0
    if ($HasCiSignal) { $bonus += 5 }
    if ($HasTestSignal) { $bonus += 5 }
    $penalty = [Math]::Min(15, ([Math]::Max(0, $DocFindingCount) * 2))
    return _ClampScore -Value ([int]($base + $bonus - $penalty))
}

function _Get-GitHubIdentityFromRemoteUrl {
    param([string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        return [pscustomobject]@{
            owner    = ''
            repo     = ''
            fullName = ''
        }
    }

    $trimmed = $RemoteUrl.Trim()
    $patterns = @(
        'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$',
        '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($trimmed, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $owner = $match.Groups['owner'].Value
            $repo = $match.Groups['repo'].Value
            return [pscustomobject]@{
                owner    = $owner
                repo     = $repo
                fullName = if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) { '' } else { '{0}/{1}' -f $owner, $repo }
            }
        }
    }

    return [pscustomobject]@{
        owner    = ''
        repo     = ''
        fullName = ''
    }
}

function _Get-FileLastWriteUtcIso {
    param([string]$FilePath)

    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf -ErrorAction SilentlyContinue)) {
        return ''
    }

    try {
        return ([System.IO.File]::GetLastWriteTimeUtc($FilePath)).ToString('o')
    } catch {
        return ''
    }
}

function _Get-PortfolioStableHash {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) { return '' }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
}

function Get-PortfolioScanFingerprintFromSignals {
    [CmdletBinding()]
    param(
        [Parameter()][object]$LocalRepo,
        [Parameter()][object]$GitHubRepo,
        [Parameter()][string]$LocalPath = '',
        [Parameter()][string]$SourceCoverage = 'local'
    )

    $effectiveLocalPath = if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        [string](_GetField -Obj $LocalRepo -Name 'path' -Default '')
    } else {
        [string]$LocalPath
    }

    $readmePath = if ([string]::IsNullOrWhiteSpace($effectiveLocalPath)) { '' } else { Join-Path $effectiveLocalPath 'README.md' }
    $roadmapPath = if ([string]::IsNullOrWhiteSpace($effectiveLocalPath)) { '' } else { Join-Path $effectiveLocalPath 'ROADMAP.md' }

    $tokens = [ordered]@{
        sourceCoverage             = [string]$SourceCoverage
        localPath                  = $effectiveLocalPath
        localBranch                = [string](_GetField -Obj $LocalRepo -Name 'branch' -Default '')
        localHeadCommitSha         = [string](_GetField -Obj $LocalRepo -Name 'headCommitSha' -Default '')
        localStatus                = [string](_GetField -Obj $LocalRepo -Name 'status' -Default '')
        localOriginUrl             = [string](_GetField -Obj $LocalRepo -Name 'originUrl' -Default '')
        localLastCommitDate        = [string](_GetField -Obj $LocalRepo -Name 'lastCommitDate' -Default '')
        localCommitsLastWeek       = [int](_GetField -Obj $LocalRepo -Name 'commitsLastWeek' -Default 0)
        localCommitsLastMonth      = [int](_GetField -Obj $LocalRepo -Name 'commitsLastMonth' -Default 0)
        localModifiedCount         = [int](_GetField -Obj $LocalRepo -Name 'modifiedCount' -Default 0)
        localUntrackedCount        = [int](_GetField -Obj $LocalRepo -Name 'untrackedCount' -Default 0)
        localDirtyCount            = [int](_GetField -Obj $LocalRepo -Name 'dirtyCount' -Default 0)
        readmeLastWriteUtc         = (_Get-FileLastWriteUtcIso -FilePath $readmePath)
        roadmapLastWriteUtc        = (_Get-FileLastWriteUtcIso -FilePath $roadmapPath)
        githubUpdatedAt            = [string](_GetField -Obj $GitHubRepo -Name 'updatedAt' -Default '')
        githubOpenPrCount          = [int](_GetField -Obj $GitHubRepo -Name 'openPrCount' -Default 0)
        githubPendingReviewPrCount = [int](_GetField -Obj $GitHubRepo -Name 'pendingReviewPrCount' -Default 0)
        githubLatestRunStatus      = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunStatus' -Default '')
        githubLatestRunConclusion  = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunConclusion' -Default '')
        githubLatestRunName        = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunName' -Default '')
        githubLatestRunTimestamp   = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunTimestamp' -Default '')
        githubHasPages             = [string]([bool](_GetField -Obj $GitHubRepo -Name 'hasPages' -Default $false))
        githubPagesUrl             = [string](_GetField -Obj $GitHubRepo -Name 'pagesUrl' -Default '')
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $tokens.Keys) {
        $parts.Add(('{0}={1}' -f $k, [string]$tokens[$k])) | Out-Null
    }
    return _Get-PortfolioStableHash -InputText ($parts -join '|')
}

function Get-PortfolioScanFingerprintFromIndexedRepo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$IndexedRepo)

    $existing = [string](_GetField -Obj $IndexedRepo -Name 'scanFingerprint' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return $existing
    }

    $tokens = [ordered]@{
        sourceCoverage             = [string](_GetField -Obj $IndexedRepo -Name 'sourceCoverage' -Default '')
        localPath                  = [string](_GetField -Obj $IndexedRepo -Name 'localPath' -Default '')
        localBranch                = [string](_GetField -Obj $IndexedRepo -Name 'currentBranch' -Default '')
        localHeadCommitSha         = [string](_GetField -Obj $IndexedRepo -Name 'headCommitSha' -Default '')
        localStatus                = [string](_GetField -Obj $IndexedRepo -Name 'gitStatus' -Default '')
        localOriginUrl             = [string](_GetField -Obj $IndexedRepo -Name 'remoteUrl' -Default '')
        localLastCommitDate        = [string](_GetField -Obj $IndexedRepo -Name 'localLastCommitDate' -Default '')
        localCommitsLastWeek       = [int](_GetField -Obj $IndexedRepo -Name 'localCommitsLastWeek' -Default 0)
        localCommitsLastMonth      = [int](_GetField -Obj $IndexedRepo -Name 'localCommitsLastMonth' -Default 0)
        localModifiedCount         = [int](_GetField -Obj $IndexedRepo -Name 'localModifiedCount' -Default 0)
        localUntrackedCount        = [int](_GetField -Obj $IndexedRepo -Name 'localUntrackedCount' -Default 0)
        localDirtyCount            = [int](_GetField -Obj $IndexedRepo -Name 'localDirtyCount' -Default 0)
        readmeLastWriteUtc         = [string](_GetField -Obj $IndexedRepo -Name 'readmeLastWriteUtc' -Default '')
        roadmapLastWriteUtc        = [string](_GetField -Obj $IndexedRepo -Name 'roadmapLastWriteUtc' -Default '')
        githubUpdatedAt            = [string](_GetField -Obj $IndexedRepo -Name 'updatedAt' -Default '')
        githubOpenPrCount          = [int](_GetField -Obj $IndexedRepo -Name 'openPrCount' -Default 0)
        githubPendingReviewPrCount = [int](_GetField -Obj $IndexedRepo -Name 'pendingReviewPrCount' -Default 0)
        githubLatestRunStatus      = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunStatus' -Default '')
        githubLatestRunConclusion  = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunConclusion' -Default '')
        githubLatestRunName        = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunName' -Default '')
        githubLatestRunTimestamp   = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunTimestamp' -Default '')
        githubHasPages             = [string]([bool](_GetField -Obj $IndexedRepo -Name 'hasPages' -Default $false))
        githubPagesUrl             = [string](_GetField -Obj $IndexedRepo -Name 'pagesUrl' -Default '')
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $tokens.Keys) {
        $parts.Add(('{0}={1}' -f $k, [string]$tokens[$k])) | Out-Null
    }
    return _Get-PortfolioStableHash -InputText ($parts -join '|')
}

function Get-PortfolioRepoId {
    [CmdletBinding()]
    param(
        [Parameter()][string]$ScanFingerprint = '',
        [Parameter()][string]$LocalPath = '',
        [Parameter()][string]$GitHubFullName = '',
        [Parameter()][string]$RepoName = ''
    )

    # Stable identity keys first: the scan fingerprint hashes volatile
    # signals (head SHA, dirty counts, doc mtimes), so using it as repoId
    # re-keys the repo on every change and orphans curation state keyed by
    # the old id. It is only the last resort before a random id.
    if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
        return ('path:{0}' -f $LocalPath.ToLowerInvariant())
    }
    if (-not [string]::IsNullOrWhiteSpace($GitHubFullName)) {
        return ('gh:{0}' -f $GitHubFullName.ToLowerInvariant())
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoName)) {
        return ('repo:{0}' -f $RepoName.ToLowerInvariant())
    }
    if (-not [string]::IsNullOrWhiteSpace($ScanFingerprint)) {
        return $ScanFingerprint
    }
    return [guid]::NewGuid().Guid
}

function New-PortfolioIndexPayload {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$LocalRepos = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$GitHubRepos = @(),
        [Parameter()][object]$Summary,
        [Parameter()][object]$SignalSources,
        [Parameter()][hashtable]$CurationByRepoId = @{},
        [Parameter(Mandatory = $true)][string]$GeneratedAt
    )

    $localMap = _IndexByRepoName -Items $LocalRepos -NameField 'name'
    $githubMap = _IndexByRepoName -Items $GitHubRepos -NameField 'name'

    $ordered = @($Assessments | Sort-Object `
        @{ Expression = { [string](_GetField -Obj $_ -Name 'repoName' -Default '') }; Ascending = $true },
        @{ Expression = { [string](_GetField -Obj $_ -Name 'sourceCoverage' -Default '') }; Ascending = $true })

    $repos = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $assessment = $ordered[$i]
        if ($null -eq $assessment) { continue }

        $repoName = [string](_GetField -Obj $assessment -Name 'repoName' -Default '')
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

        $key = _NormalizeKey $repoName
        $localRepo = if ($localMap.ContainsKey($key)) { $localMap[$key] } else { $null }
        $githubRepo = if ($githubMap.ContainsKey($key)) { $githubMap[$key] } else { $null }

        $localPath = [string](_GetField -Obj $assessment -Name 'localPath' -Default (_GetField -Obj $localRepo -Name 'path' -Default ''))
        $remoteUrl = [string](_GetField -Obj $localRepo -Name 'originUrl' -Default '')
        $remoteIdentity = _Get-GitHubIdentityFromRemoteUrl -RemoteUrl $remoteUrl

        $githubOwner = [string](_GetField -Obj $githubRepo -Name 'owner' -Default $remoteIdentity.owner)
        $githubRepoName = if ($null -ne $githubRepo) {
            [string](_GetField -Obj $githubRepo -Name 'name' -Default $remoteIdentity.repo)
        } else {
            $remoteIdentity.repo
        }
        $githubFullName = if (-not [string]::IsNullOrWhiteSpace($githubOwner) -and -not [string]::IsNullOrWhiteSpace($githubRepoName)) {
            '{0}/{1}' -f $githubOwner, $githubRepoName
        } else {
            [string](_GetField -Obj $githubRepo -Name 'fullName' -Default $remoteIdentity.fullName)
        }
        $currentBranch = [string](_GetField -Obj $assessment -Name 'branch' -Default (_GetField -Obj $localRepo -Name 'branch' -Default ''))
        $defaultBranch = [string](_GetField -Obj $githubRepo -Name 'branch' -Default $currentBranch)
        $htmlUrl = [string](_GetField -Obj $assessment -Name 'htmlUrl' -Default (_GetField -Obj $githubRepo -Name 'htmlUrl' -Default ''))
        $hasPages = [bool](_GetField -Obj $assessment -Name 'hasPages' -Default (_GetField -Obj $githubRepo -Name 'hasPages' -Default $false))
        $pagesUrl = [string](_GetField -Obj $assessment -Name 'pagesUrl' -Default (_GetField -Obj $githubRepo -Name 'pagesUrl' -Default ''))
        $createdAt = [string](_GetField -Obj $assessment -Name 'createdAt' -Default (_GetField -Obj $githubRepo -Name 'createdAt' -Default ''))
        $updatedAt = [string](_GetField -Obj $assessment -Name 'updatedAt' -Default (_GetField -Obj $githubRepo -Name 'updatedAt' -Default ''))
        $latestWorkflowRunStatus = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunStatus' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunStatus' -Default ''))
        $latestWorkflowRunConclusion = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunConclusion' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunConclusion' -Default ''))
        $latestWorkflowRunName = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunName' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunName' -Default ''))
        $latestWorkflowRunTimestamp = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunTimestamp' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunTimestamp' -Default ''))
        $openPrCount = [int](_GetField -Obj $assessment -Name 'openPrCount' -Default (_GetField -Obj $githubRepo -Name 'openPrCount' -Default 0))
        $pendingReviewPrCount = [int](_GetField -Obj $assessment -Name 'pendingReviewPrCount' -Default (_GetField -Obj $githubRepo -Name 'pendingReviewPrCount' -Default 0))
        $localLastCommitDate = [string](_GetField -Obj $localRepo -Name 'lastCommitDate' -Default '')
        $headCommitSha = [string](_GetField -Obj $localRepo -Name 'headCommitSha' -Default '')
        $localCommitsLastWeek = [int](_GetField -Obj $localRepo -Name 'commitsLastWeek' -Default 0)
        $localCommitsLastMonth = [int](_GetField -Obj $localRepo -Name 'commitsLastMonth' -Default 0)
        $localModifiedCount = [int](_GetField -Obj $localRepo -Name 'modifiedCount' -Default 0)
        $localUntrackedCount = [int](_GetField -Obj $localRepo -Name 'untrackedCount' -Default 0)
        $localDirtyCount = [int](_GetField -Obj $localRepo -Name 'dirtyCount' -Default 0)
        $readmeLastWriteUtc = if ([string]::IsNullOrWhiteSpace($localPath)) { '' } else { _Get-FileLastWriteUtcIso -FilePath (Join-Path $localPath 'README.md') }
        $roadmapLastWriteUtc = if ([string]::IsNullOrWhiteSpace($localPath)) { '' } else { _Get-FileLastWriteUtcIso -FilePath (Join-Path $localPath 'ROADMAP.md') }
        $scanFingerprint = Get-PortfolioScanFingerprintFromSignals -LocalRepo $localRepo -GitHubRepo $githubRepo -LocalPath $localPath -SourceCoverage ([string](_GetField -Obj $assessment -Name 'sourceCoverage' -Default 'local'))
        $repoId = Get-PortfolioRepoId -ScanFingerprint $scanFingerprint -LocalPath $localPath -GitHubFullName $githubFullName -RepoName $repoName
        $curation = if ($CurationByRepoId.ContainsKey($repoId)) { $CurationByRepoId[$repoId] } else { $null }
        $curationState = if ($null -ne $curation -and -not [string]::IsNullOrWhiteSpace([string]$curation.curationState)) { [string]$curation.curationState } else { 'none' }
        $curationUpdatedAt = if ($null -ne $curation -and -not [string]::IsNullOrWhiteSpace([string]$curation.updatedAt)) { [string]$curation.updatedAt } else { $null }
        $scanDecisionReason = [string](_GetField -Obj $assessment -Name 'scanDecisionReason' -Default 'cache-miss')
        $changeState = [string](_GetField -Obj $assessment -Name 'changeState' -Default 'needs-rescan')
        $lastIndexedBranch = if ([string]::IsNullOrWhiteSpace($currentBranch)) { $null } else { $currentBranch }
        $lastIndexedCommitDate = if ([string]::IsNullOrWhiteSpace($localLastCommitDate)) { $null } else { $localLastCommitDate }
        $lastIndexedCommitSha = if ([string]::IsNullOrWhiteSpace($headCommitSha)) { $null } else { $headCommitSha }
        $lastMetadataHash = if ([string]::IsNullOrWhiteSpace($scanFingerprint)) { $null } else { $scanFingerprint }

        $repos.Add([pscustomobject]@{
            ordinal             = $i + 1
            repoId              = $repoId
            repoName            = $repoName
            sourceCoverage      = [string](_GetField -Obj $assessment -Name 'sourceCoverage' -Default 'local')
            localPath           = $localPath
            remoteUrl           = $remoteUrl
            githubOwner         = $githubOwner
            githubRepo          = $githubRepoName
            githubFullName      = $githubFullName
            htmlUrl             = $htmlUrl
            defaultBranch       = $defaultBranch
            currentBranch       = $currentBranch
            hasPages            = $hasPages
            pagesUrl            = if ([string]::IsNullOrWhiteSpace($pagesUrl)) { $null } else { $pagesUrl }
            createdAt           = if ([string]::IsNullOrWhiteSpace($createdAt)) { $null } else { $createdAt }
            updatedAt           = if ([string]::IsNullOrWhiteSpace($updatedAt)) { $null } else { $updatedAt }
            latestWorkflowRunStatus = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunStatus)) { $null } else { $latestWorkflowRunStatus }
            latestWorkflowRunConclusion = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunConclusion)) { $null } else { $latestWorkflowRunConclusion }
            latestWorkflowRunName = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunName)) { $null } else { $latestWorkflowRunName }
            latestWorkflowRunTimestamp = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunTimestamp)) { $null } else { $latestWorkflowRunTimestamp }
            openPrCount         = $openPrCount
            pendingReviewPrCount = $pendingReviewPrCount
            headCommitSha       = if ([string]::IsNullOrWhiteSpace($headCommitSha)) { $null } else { $headCommitSha }
            localLastCommitDate = if ([string]::IsNullOrWhiteSpace($localLastCommitDate)) { $null } else { $localLastCommitDate }
            localCommitsLastWeek = $localCommitsLastWeek
            localCommitsLastMonth = $localCommitsLastMonth
            localModifiedCount = $localModifiedCount
            localUntrackedCount = $localUntrackedCount
            localDirtyCount = $localDirtyCount
            readmeLastWriteUtc = if ([string]::IsNullOrWhiteSpace($readmeLastWriteUtc)) { $null } else { $readmeLastWriteUtc }
            roadmapLastWriteUtc = if ([string]::IsNullOrWhiteSpace($roadmapLastWriteUtc)) { $null } else { $roadmapLastWriteUtc }
            scanFingerprint     = $scanFingerprint
            lastIndexedBranch   = $lastIndexedBranch
            lastIndexedCommitDate = $lastIndexedCommitDate
            lastIndexedCommitSha = $lastIndexedCommitSha
            lastMetadataHash    = $lastMetadataHash
            lastScannedAt       = $GeneratedAt
            lastScanStatus      = 'ok'
            lastScanError       = $null
            changeState         = $changeState
            scanDecisionReason  = $scanDecisionReason
            curationState       = $curationState
            curationUpdatedAt   = $curationUpdatedAt
            repoType            = [string](_GetField -Obj $assessment -Name 'repoType' -Default 'other')
            lifecycleState      = [string](_GetField -Obj $assessment -Name 'lifecycleState' -Default 'discovered')
            recommendedAction   = [string](_GetField -Obj $assessment -Name 'recommendedAction' -Default '')
            blockingReasons     = @(_GetField -Obj $assessment -Name 'blockingReasons' -Default @())
            roadmapState        = [string](_GetField -Obj $assessment -Name 'roadmapState' -Default 'missing')
            roadmapPath         = [string](_GetField -Obj $assessment -Name 'roadmapPath' -Default '')
            hasRoadmap          = [bool](_GetField -Obj $assessment -Name 'hasRoadmap' -Default $false)
            hasReadme           = [bool](_GetField -Obj $assessment -Name 'hasReadme' -Default $false)
            readmeScore         = [int](_GetField -Obj $assessment -Name 'readmeScore' -Default 0)
            roadmapScore        = [int](_GetField -Obj $assessment -Name 'roadmapScore' -Default 0)
            documentationHealthScore = [int](_GetField -Obj $assessment -Name 'documentationHealthScore' -Default 0)
            pendingCount        = [int](_GetField -Obj $assessment -Name 'pendingCount' -Default (_GetField -Obj $assessment -Name 'pendingItemCount' -Default 0))
            nextPendingItem     = _GetField -Obj $assessment -Name 'nextPendingItem' -Default $null
            pendingItemCount    = [int](_GetField -Obj $assessment -Name 'pendingItemCount' -Default 0)
            nextPendingItemText = [string](_GetField -Obj $assessment -Name 'nextPendingItemText' -Default '')
            topValueItem        = _GetField -Obj $assessment -Name 'topValueItem' -Default $null
            activeRelease       = _GetField -Obj $assessment -Name 'activeRelease' -Default $null
            activePhasePlan     = _GetField -Obj $assessment -Name 'activePhasePlan' -Default $null
            budgetGuardrail     = _GetField -Obj $assessment -Name 'budgetGuardrail' -Default $null
            estimatedSessionWorkUnits = _GetField -Obj $assessment -Name 'estimatedSessionWorkUnits' -Default $null
            maturityLevel       = [string](_GetField -Obj $assessment -Name 'maturityLevel' -Default 'L0-Absent')
            maturityScore       = [int](_GetField -Obj $assessment -Name 'maturityScore' -Default 0)
            dispatchReadiness   = [string](_GetField -Obj $assessment -Name 'dispatchReadiness' -Default 'missing-roadmap')
            executionContract   = _GetField -Obj $assessment -Name 'executionContract' -Default $null
            dispatchReadinessExplanation = [string](_GetField -Obj $assessment -Name 'dispatchReadinessExplanation' -Default '')
            executionState      = [string](_GetField -Obj $assessment -Name 'executionState' -Default 'idle')
            gitStatus           = [string](_GetField -Obj $assessment -Name 'gitStatus' -Default 'unknown')
            hasCiSignal         = [bool](_GetField -Obj $assessment -Name 'hasCiSignal' -Default $false)
            hasTestSignal       = [bool](_GetField -Obj $assessment -Name 'hasTestSignal' -Default $false)
            docFindingCount     = [int](_GetField -Obj $assessment -Name 'docFindingCount' -Default 0)
            structureFindings   = @(_GetField -Obj $assessment -Name 'structureFindings' -Default @())
            duplicateCheckouts  = _GetField -Obj $assessment -Name 'duplicateCheckouts' -Default $null
        }) | Out-Null
    }

    return [pscustomobject]@{
        schemaVersion = 1
        kind          = 'portfolio-index'
        generatedAt   = $GeneratedAt
        repoCount     = $repos.Count
        signalSources = $SignalSources
        summary       = $Summary
        repos         = @($repos)
    }
}

function Save-PortfolioIndexArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$LocalRepos = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$GitHubRepos = @(),
        [Parameter()][object]$Summary,
        [Parameter()][object]$SignalSources,
        [Parameter()][hashtable]$CurationByRepoId = @{},
        [Parameter(Mandatory = $true)][string]$GeneratedAt
    )

    $indexRoot = Join-Path $WorkspaceRoot 'output\index'
    $scansRoot = Join-Path $indexRoot 'scans'
    if (-not (Test-Path -LiteralPath $indexRoot)) {
        $null = New-Item -ItemType Directory -Path $indexRoot -Force
    }
    if (-not (Test-Path -LiteralPath $scansRoot)) {
        $null = New-Item -ItemType Directory -Path $scansRoot -Force
    }

    $payload = New-PortfolioIndexPayload `
        -Assessments $Assessments `
        -LocalRepos $LocalRepos `
        -GitHubRepos $GitHubRepos `
        -Summary $Summary `
        -SignalSources $SignalSources `
        -CurationByRepoId $CurationByRepoId `
        -GeneratedAt $GeneratedAt

    # Stamp the logic that produced this index. Without it, an index written
    # before a correctness fix is indistinguishable from one written after —
    # which is how a six-hour-old index reported 0 of 9 dispatch-ready repos
    # with nothing noticing (2026-08-27).
    Add-Member -InputObject $payload -NotePropertyName 'producedBy' -NotePropertyValue ([pscustomobject]@{
            logicFingerprint = (Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $WorkspaceRoot)
            generatedAt      = $GeneratedAt
        }) -Force

    $json = $payload | ConvertTo-Json -Depth 12
    $indexPath = Join-Path $indexRoot 'repos.index.json'
    Set-Content -LiteralPath $indexPath -Value $json -Encoding UTF8

    $artifactName = ('portfolio-scan-{0}.json' -f ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')))
    $artifactPath = Join-Path $scansRoot $artifactName
    Set-Content -LiteralPath $artifactPath -Value $json -Encoding UTF8

    return [pscustomobject]@{
        indexPath    = $indexPath
        artifactPath = $artifactPath
        repoCount    = [int]$payload.repoCount
        generatedAt  = $GeneratedAt
    }
}

function Get-PortfolioIndexLogicFingerprint {
    <#
    .SYNOPSIS
        A fingerprint of the code that decides what an index row says.

    .DESCRIPTION
        Derived, never maintained. The producer set is every .ps1 under the
        module directories that compose an index row — portfolio, roadmap,
        docaudit — so adding a module moves the fingerprint on its own and
        editing one makes every index written beforehand read as stale.
        A hand-listed set would drift the first time someone added a file,
        which is the failure mode this repository already refuses elsewhere.

        Line endings are normalized before hashing: the working tree is LF and
        a CI checkout is CRLF, and a fingerprint that changed with the checkout
        would report every index as stale everywhere.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $producerRoots = @(
        (Join-Path $WorkspaceRoot 'backend\modules\portfolio'),
        (Join-Path $WorkspaceRoot 'backend\modules\roadmap'),
        (Join-Path $WorkspaceRoot 'backend\modules\docaudit')
    )

    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $producerRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
            $files.Add([string]$file.FullName) | Out-Null
        }
    }
    if ($files.Count -eq 0) { return '' }

    # Ordinal sort so enumeration order cannot move the fingerprint.
    $ordered = @($files.ToArray() | Sort-Object -Property { $_ })
    $builder = [System.Text.StringBuilder]::new()
    foreach ($path in $ordered) {
        $content = ''
        try { $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop } catch { $content = '' }
        if ($null -eq $content) { $content = '' }
        [void]$builder.Append((Split-Path -Path $path -Leaf))
        [void]$builder.Append("`n")
        [void]$builder.Append(($content -replace "`r`n", "`n"))
        [void]$builder.Append("`n")
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)
    } finally {
        $sha.Dispose()
    }
}

function Get-PortfolioIndexStaleness {
    <#
    .SYNOPSIS
        Pure -- is this index still a fair description of the portfolio?

    .DESCRIPTION
        On 2026-08-27 the served index was generated at 09:46Z and reported 58
        repositories, all L0-Absent, none ready for work. The repository-identity
        fix had merged at 10:47Z; the audit cache written at 16:09Z held 10
        L3-Contract-Ready, and re-running the join produced 71 repositories with
        9 of them dispatch-ready. The index was simply old — and NOTHING in the
        product noticed, recorded, or said so, so every surface rendered a
        portfolio that was wrong about a third of its inputs.

        Two ways an index goes stale, and they are not the same:

          * by CLOCK  - it was generated too long ago to be trusted as current
          * by LOGIC  - it was produced by different code than is running now,
                        so its rows may be wrong in ways time cannot explain

        The second is the dangerous one, because an index minutes old can still
        be wrong about every row. Both are reported; either makes it stale.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][object]$Index = $null,
        [Parameter()][AllowEmptyString()][string]$CurrentFingerprint = '',
        [Parameter()][AllowNull()][object]$Now = $null,
        [Parameter()][int]$MaxAgeHours = 24
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Now) { $Now = (Get-Date).ToUniversalTime() }
    $nowUtc = ([datetime]$Now).ToUniversalTime()

    if ($null -eq $Index) {
        return [pscustomobject]@{
            stale              = $true
            ageHours           = $null
            generatedAt        = $null
            producedBy         = ''
            currentFingerprint = $CurrentFingerprint
            reasons            = @('No portfolio index has been written yet; nothing has been scanned.')
        }
    }

    $generatedAt = [string](_GetField -Obj $Index -Name 'generatedAt' -Default '')
    $ageHours = $null
    if (-not [string]::IsNullOrWhiteSpace($generatedAt)) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($generatedAt, [ref]$parsed)) {
            $ageHours = [math]::Round(($nowUtc - $parsed.ToUniversalTime()).TotalHours, 1)
            if ($MaxAgeHours -gt 0 -and $ageHours -gt $MaxAgeHours) {
                $reasons.Add(("The index was generated {0} hour(s) ago, past the {1}-hour freshness window." -f $ageHours, $MaxAgeHours)) | Out-Null
            }
        } else {
            $reasons.Add("The index does not carry a readable generatedAt timestamp, so its age cannot be established.") | Out-Null
        }
    } else {
        $reasons.Add('The index does not record when it was generated, so its age cannot be established.') | Out-Null
    }

    $producedBy = [string](_GetField -Obj (_GetField -Obj $Index -Name 'producedBy' -Default $null) -Name 'logicFingerprint' -Default '')
    if ([string]::IsNullOrWhiteSpace($CurrentFingerprint)) {
        # Not knowing which code is running is itself uncertainty, and reading
        # it as freshness would repeat the defect this function exists to end.
        $reasons.Add('The version of the assessment logic running now could not be determined, so this index cannot be confirmed current.') | Out-Null
    } elseif ([string]::IsNullOrWhiteSpace($producedBy)) {
        $reasons.Add('The index does not record which version of the assessment logic produced it, so it predates this check and cannot be trusted as current.') | Out-Null
    } elseif ($producedBy -ne $CurrentFingerprint) {
        $reasons.Add(("The index was produced by assessment logic '{0}'; the code running now is '{1}'. Its rows may be wrong in ways age does not explain — rescan before drawing a conclusion from it." -f $producedBy, $CurrentFingerprint)) | Out-Null
    }

    return [pscustomobject]@{
        stale              = ($reasons.Count -gt 0)
        ageHours           = $ageHours
        generatedAt        = $(if ([string]::IsNullOrWhiteSpace($generatedAt)) { $null } else { $generatedAt })
        producedBy         = $producedBy
        currentFingerprint = $CurrentFingerprint
        reasons            = @($reasons)
    }
}

function Get-PortfolioIndexPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $indexPath = Join-Path (Join-Path $WorkspaceRoot 'output\index') 'repos.index.json'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $payload = ConvertFrom-Json -InputObject $raw
    } catch {
        return $null
    }

    # Attached on read, in the one place every consumer already goes through,
    # so a surface cannot render index data without the staleness verdict
    # sitting on the same object it rendered from.
    try {
        $staleness = Get-PortfolioIndexStaleness -Index $payload `
            -CurrentFingerprint (Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $WorkspaceRoot)
        Add-Member -InputObject $payload -NotePropertyName 'staleness' -NotePropertyValue $staleness -Force
    } catch {
        # A staleness verdict that cannot be computed must not hide the index,
        # but it must not silently read as fresh either.
        Add-Member -InputObject $payload -NotePropertyName 'staleness' -NotePropertyValue ([pscustomobject]@{
                stale              = $true
                ageHours           = $null
                generatedAt        = $null
                producedBy         = ''
                currentFingerprint = ''
                reasons            = @("The staleness of this index could not be established: $($_.Exception.Message)")
            }) -Force
    }

    return $payload
}

function Convert-PortfolioIndexReposToAssessments {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyCollection()][object[]]$IndexRepos = @())

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($repo in @($IndexRepos)) {
        if ($null -eq $repo) { continue }

        $out.Add([pscustomobject]@{
            repoId              = [string](_GetField -Obj $repo -Name 'repoId' -Default '')
            repoName            = [string](_GetField -Obj $repo -Name 'repoName' -Default '')
            localPath           = [string](_GetField -Obj $repo -Name 'localPath' -Default '')
            htmlUrl             = [string](_GetField -Obj $repo -Name 'htmlUrl' -Default '')
            branch              = [string](_GetField -Obj $repo -Name 'currentBranch' -Default '')
            headCommitSha       = _GetField -Obj $repo -Name 'headCommitSha' -Default $null
            gitStatus           = [string](_GetField -Obj $repo -Name 'gitStatus' -Default 'unknown')
            isArchived          = [bool](_GetField -Obj $repo -Name 'isArchived' -Default $false)
            sourceCoverage      = [string](_GetField -Obj $repo -Name 'sourceCoverage' -Default 'local')
            hasPages            = [bool](_GetField -Obj $repo -Name 'hasPages' -Default $false)
            pagesUrl            = _GetField -Obj $repo -Name 'pagesUrl' -Default $null
            createdAt           = _GetField -Obj $repo -Name 'createdAt' -Default $null
            updatedAt           = _GetField -Obj $repo -Name 'updatedAt' -Default $null
            latestWorkflowRunStatus = _GetField -Obj $repo -Name 'latestWorkflowRunStatus' -Default $null
            latestWorkflowRunConclusion = _GetField -Obj $repo -Name 'latestWorkflowRunConclusion' -Default $null
            latestWorkflowRunName = _GetField -Obj $repo -Name 'latestWorkflowRunName' -Default $null
            latestWorkflowRunTimestamp = _GetField -Obj $repo -Name 'latestWorkflowRunTimestamp' -Default $null
            openPrCount         = [int](_GetField -Obj $repo -Name 'openPrCount' -Default 0)
            pendingReviewPrCount = [int](_GetField -Obj $repo -Name 'pendingReviewPrCount' -Default 0)
            repoType            = [string](_GetField -Obj $repo -Name 'repoType' -Default 'other')
            lifecycleState      = [string](_GetField -Obj $repo -Name 'lifecycleState' -Default 'discovered')
            recommendedAction   = [string](_GetField -Obj $repo -Name 'recommendedAction' -Default '')
            blockingReasons     = @(_GetField -Obj $repo -Name 'blockingReasons' -Default @())
            roadmapState        = [string](_GetField -Obj $repo -Name 'roadmapState' -Default 'missing')
            roadmapPath         = [string](_GetField -Obj $repo -Name 'roadmapPath' -Default '')
            hasRoadmap          = [bool](_GetField -Obj $repo -Name 'hasRoadmap' -Default $false)
            pendingCount        = [int](_GetField -Obj $repo -Name 'pendingCount' -Default (_GetField -Obj $repo -Name 'pendingItemCount' -Default 0))
            nextPendingItem     = _GetField -Obj $repo -Name 'nextPendingItem' -Default $null
            pendingItemCount    = [int](_GetField -Obj $repo -Name 'pendingItemCount' -Default 0)
            nextPendingItemText = [string](_GetField -Obj $repo -Name 'nextPendingItemText' -Default '')
            pendingItems        = @()
            topValueItem        = _GetField -Obj $repo -Name 'topValueItem' -Default $null
            activeRelease       = _GetField -Obj $repo -Name 'activeRelease' -Default $null
            activePhasePlan     = _GetField -Obj $repo -Name 'activePhasePlan' -Default $null
            budgetGuardrail     = _GetField -Obj $repo -Name 'budgetGuardrail' -Default $null
            estimatedSessionWorkUnits = _GetField -Obj $repo -Name 'estimatedSessionWorkUnits' -Default $null
            maturityLevel       = [string](_GetField -Obj $repo -Name 'maturityLevel' -Default 'L0-Absent')
            maturityScore       = [int](_GetField -Obj $repo -Name 'maturityScore' -Default 0)
            dispatchReadiness   = [string](_GetField -Obj $repo -Name 'dispatchReadiness' -Default 'missing-roadmap')
            executionContract   = _GetField -Obj $repo -Name 'executionContract' -Default $null
            executionState      = [string](_GetField -Obj $repo -Name 'executionState' -Default 'idle')
            hasReadme           = [bool](_GetField -Obj $repo -Name 'hasReadme' -Default $false)
            readmeScore         = [int](_GetField -Obj $repo -Name 'readmeScore' -Default 0)
            roadmapScore        = [int](_GetField -Obj $repo -Name 'roadmapScore' -Default 0)
            documentationHealthScore = [int](_GetField -Obj $repo -Name 'documentationHealthScore' -Default 0)
            hasCiSignal         = [bool](_GetField -Obj $repo -Name 'hasCiSignal' -Default $false)
            hasTestSignal       = [bool](_GetField -Obj $repo -Name 'hasTestSignal' -Default $false)
            structureFindings   = @(_GetField -Obj $repo -Name 'structureFindings' -Default @())
            docFindingCount     = [int](_GetField -Obj $repo -Name 'docFindingCount' -Default 0)
            dispatchReadinessExplanation = [string](_GetField -Obj $repo -Name 'dispatchReadinessExplanation' -Default '')
            changeState         = [string](_GetField -Obj $repo -Name 'changeState' -Default 'needs-rescan')
            scanDecisionReason  = [string](_GetField -Obj $repo -Name 'scanDecisionReason' -Default 'cache-miss')
            lastIndexedBranch   = _GetField -Obj $repo -Name 'lastIndexedBranch' -Default $null
            lastIndexedCommitDate = _GetField -Obj $repo -Name 'lastIndexedCommitDate' -Default $null
            lastIndexedCommitSha = _GetField -Obj $repo -Name 'lastIndexedCommitSha' -Default $null
            lastMetadataHash    = _GetField -Obj $repo -Name 'lastMetadataHash' -Default $null
            lastScannedAt       = _GetField -Obj $repo -Name 'lastScannedAt' -Default $null
            lastScanStatus      = [string](_GetField -Obj $repo -Name 'lastScanStatus' -Default 'ok')
            lastScanError       = _GetField -Obj $repo -Name 'lastScanError' -Default $null
            curationState       = [string](_GetField -Obj $repo -Name 'curationState' -Default 'none')
            curationUpdatedAt   = _GetField -Obj $repo -Name 'curationUpdatedAt' -Default $null
            duplicateCheckouts  = _GetField -Obj $repo -Name 'duplicateCheckouts' -Default $null
        }) | Out-Null
    }

    return ,@($out)
}

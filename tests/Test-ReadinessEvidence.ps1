#Requires -Version 7.0
<#
.SYNOPSIS
    One readiness rule for "ready for automated work", proved offline against
    fixtures.

.DESCRIPTION
    Proves that Get-RepositoryReadiness calls a repository ready only when the
    lifecycle resolver reads ready-for-work, the dispatch-eligibility rule
    passes, an actionable agent item exists and a GitHub remote can receive the
    pull request; that it names every hold, not the first; that an entry
    assessed before the actionable-line classifier is held as unmeasured, not
    as ready and not as a roadmap with nothing to do; that a LICENSE-only
    structure finding still holds (the rule loosens nothing); and that the
    census counts, groups and finds the repositories one hold from ready.

.EXAMPLE
    pwsh ./tests/Test-ReadinessEvidence.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Ranking.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/execution/Execution.Eligibility.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Readiness.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

function Get-ReadyFixture {
    # Every input a ready repository carries, as the index records it.
    param([string]$Name = 'ok')
    [pscustomobject]@{
        repoName                = $Name
        localPath               = "C:\repos\$Name"
        githubFullName          = "owner/$Name"
        lifecycleState          = 'ready-for-work'
        roadmapState            = 'pending'
        hasRoadmap              = $true
        hasReadme               = $true
        curationState           = 'none'
        executionState          = 'ready'
        localDirtyCount         = 0
        pendingItemCount        = 3
        dispatchReadiness       = 'ready'
        executionContract       = [pscustomobject]@{ sufficient = $true; explanation = 'Execution contract is sufficient for dispatch.'; checks = @() }
        structureFindings       = @([pscustomobject]@{ target = 'SECURITY.md'; severity = 'info' })
        topDispatchableItem     = [pscustomobject]@{ text = 'Add a parser test'; section = 'Release 1' }
        itemQualityModelVersion = '1.0'
        excludedItemCount       = 0
    }
}
function With { param($Entry, [hashtable]$Set) foreach ($k in $Set.Keys) { $Entry | Add-Member -NotePropertyName $k -NotePropertyValue $Set[$k] -Force }; $Entry }
function Get-HoldCode { param($Result) @($Result.holds | ForEach-Object { $_.code }) }

# 1. the fully evidenced repository is ready, and info findings do not hold
$ok = Get-RepositoryReadiness -PortfolioEntry (Get-ReadyFixture)
Assert-That ($ok.ready -and @($ok.holds).Count -eq 0) 'a repository with every input recorded is ready with no holds'
Assert-That ($ok.repoName -eq 'ok') 'the result names its repository'

# 2. each hold, alone, prevents ready and names itself
$cases = @(
    @{ code = 'uncommitted-changes'; set = @{ localDirtyCount = 4 } }
    @{ code = 'archived'; set = @{ curationState = 'archived-ignore'; lifecycleState = 'curated-out' } }
    @{ code = 'no-github-remote'; set = @{ githubFullName = '' } }
    @{ code = 'no-actionable-item'; set = @{ topDispatchableItem = $null; excludedItemCount = 3 } }
    @{ code = 'item-quality-unmeasured'; set = @{ topDispatchableItem = $null; itemQualityModelVersion = '' } }
    @{ code = 'contract-gap'; set = @{ lifecycleState = 'needs-roadmap-repair'; executionContract = [pscustomobject]@{ sufficient = $false; explanation = 'x'; checks = @([pscustomobject]@{ passed = $false; explanation = 'Name an exact command, script, or API request in the validation plan.' }) } } }
    @{ code = 'structure'; set = @{ lifecycleState = 'needs-structure'; structureFindings = @([pscustomobject]@{ target = '.github/workflows'; severity = 'warning' }) } }
    @{ code = 'doc-readiness'; set = @{ lifecycleState = 'needs-structure'; dispatchReadiness = 'blocked'; dispatchReadinessExplanation = 'Missing CI' } }
    @{ code = 'no-roadmap'; set = @{ hasRoadmap = $false; lifecycleState = 'needs-roadmap' } }
    @{ code = 'no-checklist'; set = @{ roadmapState = 'no-checklist'; lifecycleState = 'no-checklist' } }
    @{ code = 'no-readme'; set = @{ hasReadme = $false; lifecycleState = 'needs-readme' } }
    @{ code = 'running'; set = @{ executionState = 'running'; lifecycleState = 'running' } }
    @{ code = 'no-pending-work'; set = @{ pendingItemCount = 0; lifecycleState = 'monitored' } }
)
foreach ($c in $cases) {
    $r = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) $c.set)
    $codes = @(Get-HoldCode $r)
    Assert-That ((-not $r.ready) -and $codes.Count -eq 1 -and $codes[0] -eq $c.code) ("'{0}' alone holds the repository and is its only hold (got: {1})" -f $c.code, ($codes -join ', '))
}

# 3. hold details carry the recorded fact, not a generic phrase
$dirty = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) @{ localDirtyCount = 4 })
Assert-That ($dirty.holds[0].detail -match '4 uncommitted files') 'the dirty hold names the file count (from the eligibility rule)'
$gap = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) $cases[5].set)
Assert-That ($gap.holds[0].detail -match 'exact command') 'the contract hold names the failing contract check'
$none = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) @{ topDispatchableItem = $null; excludedItemCount = 3 })
Assert-That ($none.holds[0].detail -match '3 excluded') 'the no-actionable hold names how many lines were excluded'

# 4. a blocked ledger entry holds, through the eligibility rule
$blocked = Get-RepositoryReadiness -PortfolioEntry (Get-ReadyFixture) -LedgerEntry ([pscustomobject]@{ repoName = 'ok'; repoPath = 'C:\repos\ok'; executionState = 'blocked'; errorMessage = 'needs a human' })
Assert-That ((Get-HoldCode $blocked) -contains 'blocked' -and $blocked.holds[0].detail -eq 'needs a human') 'a blocked ledger entry holds with its own detail'

# 5. every hold is listed, not only the first the lifecycle resolver would stop at
$many = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) @{ localDirtyCount = 2; githubFullName = ''; lifecycleState = 'needs-structure'; structureFindings = @([pscustomobject]@{ target = 'tests'; severity = 'warning' }) })
Assert-That (@(Get-HoldCode $many).Count -eq 3) 'structure, uncommitted changes and no remote are all listed'

# 6. the rule loosens nothing
$licenseOnly = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) @{ lifecycleState = 'needs-structure'; structureFindings = @([pscustomobject]@{ target = 'LICENSE'; severity = 'warning' }) })
Assert-That ((-not $licenseOnly.ready) -and (Get-HoldCode $licenseOnly) -contains 'structure') 'a LICENSE-only warning still holds until the owner changes the structure rule'
$readmeOnly = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) @{ structureFindings = @([pscustomobject]@{ target = 'README.md'; severity = 'warning' }) })
Assert-That $readmeOnly.ready 'a README structure finding is the no-readme hold''s concern, as in the lifecycle resolver'
$lifecycleDisagrees = Get-RepositoryReadiness -PortfolioEntry (With (Get-ReadyFixture) @{ lifecycleState = 'discovered' })
Assert-That ((-not $lifecycleDisagrees.ready) -and (Get-HoldCode $lifecycleDisagrees) -contains 'lifecycle') 'never ready when the lifecycle resolver does not read ready-for-work'
$sparse = Get-RepositoryReadiness -PortfolioEntry ([pscustomobject]@{ repoName = 'bare' })
Assert-That (-not $sparse.ready) 'an entry with no recorded inputs is never ready'

# 7. the census: count, groups, one-hold-away, ledger matching
$entries = @(
    (Get-ReadyFixture 'a'),
    (Get-ReadyFixture 'b'),
    (With (Get-ReadyFixture 'c') @{ localDirtyCount = 1 }),
    (With (Get-ReadyFixture 'd') @{ localDirtyCount = 1; githubFullName = '' })
)
$ledger = @([pscustomobject]@{ repoName = 'b'; repoPath = 'C:\repos\b'; executionState = 'blocked'; errorMessage = 'held' })
$census = Get-ReadinessCensus -PortfolioEntries $entries -LedgerEntries $ledger -IndexGeneratedAt '2026-11-12T00:00:00Z'
Assert-That ($census.repoCount -eq 4 -and $census.readyCount -eq 1 -and @($census.ready) -join ',' -eq 'a') 'the census counts one ready of four (b blocked by the ledger)'
Assert-That (@($census.oneHoldAway | ForEach-Object repoName) -join ',' -eq 'b,c') 'b and c are one hold from ready; d is two'
$dirtyGroup = @($census.holdsByCode | Where-Object code -eq 'uncommitted-changes')
Assert-That ($dirtyGroup.Count -eq 1 -and $dirtyGroup[0].count -eq 2 -and (@($dirtyGroup[0].repos) -join ',') -eq 'c,d') 'holds group by code with the repositories named'
Assert-That ($census.holdsByCode[0].code -eq 'uncommitted-changes') 'groups sort by size, largest first'
Assert-That ($census.schemaVersion -eq 'v1' -and $census.modelVersion -and $census.indexGeneratedAt -eq '2026-11-12T00:00:00Z') 'the census carries schemaVersion, modelVersion and the index time it describes'
$empty = Get-ReadinessCensus -PortfolioEntries @()
Assert-That ($empty.repoCount -eq 0 -and $empty.readyCount -eq 0) 'an empty index yields an empty census, which the tool refuses to report'

# 8. the tool refuses a census of nothing
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("readiness-{0}" -f [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tmp
try {
    $idxPath = Join-Path $tmp 'repos.index.json'
    '{"schemaVersion":"v1","generatedAt":"2026-11-12T00:00:00Z","repos":[]}' | Set-Content -LiteralPath $idxPath
    $threw = $false
    try { $null = & (Join-Path $WorkspaceRoot 'tools/Get-ReadinessCensus.ps1') -WorkspaceRoot $WorkspaceRoot -IndexPath $idxPath -LedgerPath (Join-Path $tmp 'none.json') 3>$null } catch { $threw = $_.Exception.Message -match 'holds no repositories' }
    Assert-That $threw 'the census tool fails on an index with zero repositories'

    @{ schemaVersion = 'v1'; generatedAt = '2026-11-12T00:00:00Z'; repos = @((Get-ReadyFixture 'a'), (With (Get-ReadyFixture 'c') @{ localDirtyCount = 1 })) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $idxPath
    $outPath = Join-Path $tmp 'out/census.json'
    $fromTool = & (Join-Path $WorkspaceRoot 'tools/Get-ReadinessCensus.ps1') -WorkspaceRoot $WorkspaceRoot -IndexPath $idxPath -LedgerPath (Join-Path $tmp 'none.json') -OutputPath $outPath 3>$null
    Assert-That ($fromTool.readyCount -eq 1 -and (Test-Path -LiteralPath $outPath)) 'the tool reads an index file, counts it and writes the census JSON where asked'
    $written = Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json
    Assert-That ($written.kind -eq 'readiness-census' -and $written.repoCount -eq 2) 'the written census round-trips'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force
}

Write-Host ("Readiness evidence: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }

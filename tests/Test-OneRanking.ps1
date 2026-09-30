#Requires -Version 7.0
<#
.SYNOPSIS
    One ranking for Today and the Dispatch Board (Release 4.0 phase A).

.DESCRIPTION
    Today ranked the operations index in the browser; the board sorted the
    execution ledger by priorityScore. One repository read #1 on Today and #8
    on the board, on scales with nothing in common.

    This gate proves, offline and against fixtures:

      1. the ranking keys hold, in order - conclusion, curation, an offered
         action, readiness for unattended work (unmeasured last), foundation
         gaps, cheaper effort, then the name - and business value orders
         nothing (the rules todayRanking.test.ts used to hold, now server-side);
      2. the ranking is deterministic: shuffled input gives the same order;
      3. one scale: every ledger entry the board shows carries the rank Today
         shows, the board's order is Today's order, and an entry the index does
         not hold is unranked with a reason and listed last;
      4. with no portfolio ranking the board says so and lists by name - it
         never falls back to priorityScore;
      5. the frontend holds no ranking arithmetic: every module Today and the
         board import (derived from their imports, not a list) is scanned for a
         sort on a ranking input, and the scan is itself shown red on a
         violating snippet and on zero files examined.

.EXAMPLE
    pwsh ./tests/Test-OneRanking.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Ranking.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.Ledger.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

function Get-FixtureOutcome {
    param([string]$Conclusion, [int]$GapCount = 0, [string[]]$GapDomains = @(), [bool]$WithAction = $true, [string]$Reason = '')
    [pscustomobject]@{
        conclusion      = $Conclusion
        reason          = $(if ($Reason) { $Reason } else { "reason for $Conclusion" })
        kind            = 'unknown'
        gapCount        = $GapCount
        gapDomains      = @($GapDomains)
        nextActionRoute = $(if ($WithAction -and $Conclusion -eq 'strengthen') { '/api/roadmap/repair/preview' } else { $null })
        nextActionLabel = $(if ($WithAction -and $Conclusion -eq 'strengthen') { 'Preview the smallest credible plan' } else { $null })
        holds           = $true
    }
}

function Get-FixtureRepo {
    param([string]$Name, [hashtable]$Over = @{})
    $repo = [ordered]@{
        repoId        = "repo:$Name"
        repoName      = $Name
        localPath     = "C:\repos\$Name"
        outcome       = (Get-FixtureOutcome -Conclusion 'strengthen')
        curationState = 'none'
    }
    foreach ($key in $Over.Keys) { $repo[$key] = $Over[$key] }
    return [pscustomobject]$repo
}

function Get-RankOrder {
    param([object[]]$Entries)
    return @(Add-PortfolioRanking -Entries $Entries | ForEach-Object { $_.repoName })
}

$ready4 = @{ hasReadme = $true; hasRoadmap = $true; roadmapState = 'pending'; localDirtyCount = 0; hasCiSignal = $true }
function With { param([hashtable]$A, [hashtable]$B) $m = @{}; foreach ($k in $A.Keys) { $m[$k] = $A[$k] }; foreach ($k in $B.Keys) { $m[$k] = $B[$k] }; return $m }

# ---------------------------------------------------------------------------
# 1. The keys, in order.
# ---------------------------------------------------------------------------
$names = Get-RankOrder @(
    (Get-FixtureRepo 'healthy' @{ outcome = (Get-FixtureOutcome 'appropriate-as-is') }),
    (Get-FixtureRepo 'needs-work'),
    (Get-FixtureRepo 'unclear' @{ outcome = (Get-FixtureOutcome 'insufficiently-understood') })
)
Assert-That (($names -join ',') -eq 'needs-work,unclear,healthy') "conclusion order: got $($names -join ',')"

$names = Get-RankOrder @((Get-FixtureRepo 'ordinary'), (Get-FixtureRepo 'favourite' @{ curationState = 'favorite' }), (Get-FixtureRepo 'candidate' @{ curationState = 'portfolio-candidate' }))
Assert-That (($names -join ',') -eq 'favourite,candidate,ordinary') "curation order: got $($names -join ',')"

$names = Get-RankOrder @((Get-FixtureRepo 'no-action' @{ outcome = (Get-FixtureOutcome 'strengthen' -WithAction $false) }), (Get-FixtureRepo 'actionable'))
Assert-That ($names[0] -eq 'actionable') "an offered action leads: got $($names -join ',')"

$names = Get-RankOrder @(
    (Get-FixtureRepo 'not-ready' @{ hasReadme = $false; hasRoadmap = $false; roadmapState = 'missing'; localDirtyCount = 9; hasCiSignal = $false }),
    (Get-FixtureRepo 'ready' $ready4)
)
Assert-That (($names -join ',') -eq 'ready,not-ready') "readiness order: got $($names -join ',')"

$names = Get-RankOrder @(
    (Get-FixtureRepo 'never-assessed'),
    (Get-FixtureRepo 'measured-zero' @{ hasReadme = $false; hasRoadmap = $false; roadmapState = 'missing'; localDirtyCount = 4; hasCiSignal = $false })
)
Assert-That (($names -join ',') -eq 'measured-zero,never-assessed') "unmeasured sorts below measured zero: got $($names -join ',')"

$names = Get-RankOrder @(
    (Get-FixtureRepo 'one-gap' @{ outcome = (Get-FixtureOutcome 'strengthen' -GapCount 1 -GapDomains @('planning')) }),
    (Get-FixtureRepo 'three-gaps' @{ outcome = (Get-FixtureOutcome 'strengthen' -GapCount 3 -GapDomains @('planning', 'structure', 'purpose')) })
)
Assert-That (($names -join ',') -eq 'three-gaps,one-gap') "more gaps first: got $($names -join ',')"

$names = Get-RankOrder @((Get-FixtureRepo 'expensive' @{ estimatedSessionWorkUnits = 12 }), (Get-FixtureRepo 'cheap' @{ estimatedSessionWorkUnits = 2 }))
Assert-That (($names -join ',') -eq 'cheap,expensive') "cheaper effort first: got $($names -join ',')"

$names = Get-RankOrder @(
    (Get-FixtureRepo 'zulu-rich' @{ topValueItem = [pscustomobject]@{ text = 'x'; valueScore = 99; valueTier = 'highest' } }),
    (Get-FixtureRepo 'alpha-poor' @{ topValueItem = [pscustomobject]@{ text = 'y'; valueScore = 1; valueTier = 'low' } })
)
Assert-That (($names -join ',') -eq 'alpha-poor,zulu-rich') "business value orders nothing: got $($names -join ',')"

# Rank basis, why-now and effort ride on the entry.
$demo = @(Add-PortfolioRanking -Entries @(Get-FixtureRepo 'demo' @{
            curationState = 'favorite'
            outcome = (Get-FixtureOutcome 'strengthen' -GapCount 2 -GapDomains @('planning', 'structure') -Reason 'Planning is missing: no plan recorded.')
            topValueItem = [pscustomobject]@{ text = 'x'; valueScore = 88; valueTier = 'highest' }
            estimatedSessionWorkUnits = 5
        }))[0].ranking
$expectedBasis = 'conclusion=strengthen|curation=favorite|2 foundation gap(s): planning, structure|unattendedReadiness=unmeasured|effort=5'
Assert-That ((@($demo.basis) -join '|') -eq $expectedBasis) "rank basis: got $(@($demo.basis) -join '|')"
Assert-That ($demo.rank -eq 1 -and $demo.scale -eq 'portfolio') 'rank is 1-based on the portfolio scale'
Assert-That ($demo.whyNow -like 'Planning is missing*' -and $demo.whyNow -like '*scores 88 (highest)*') "whyNow leads with the reason: got $($demo.whyNow)"
Assert-That ($demo.effort.label -eq '5 work units' -and $demo.effort.band -eq 'medium') "effort: got $($demo.effort.label)/$($demo.effort.band)"
$none = @(Add-PortfolioRanking -Entries @(Get-FixtureRepo 'x' @{ outcome = $null }))[0].ranking
Assert-That ($none.whyNow -like '*no recorded outcome*') 'no conclusion is said plainly, not invented'
$asIs = @(Add-PortfolioRanking -Entries @(Get-FixtureRepo 'x' @{ outcome = (Get-FixtureOutcome 'appropriate-as-is'); topValueItem = [pscustomobject]@{ text = 'x'; valueScore = 88; valueTier = 'highest' } }))[0].ranking
Assert-That ($asIs.whyNow -notlike '*scores 88*') 'appropriate-as-is carries no value signal'

Assert-That ((Get-RankingEffort -WorkUnits 1).label -eq '1 work unit') 'effort singular'
Assert-That ((Get-RankingEffort -WorkUnits 2.25).workUnits -eq 2.3) 'effort rounds half away from zero'
Assert-That ((Get-RankingEffort -WorkUnits 20).band -eq 'large') 'effort large band'
Assert-That ((Get-RankingEffort -WorkUnits $null).band -eq 'unknown' -and (Get-RankingEffort -WorkUnits 0).band -eq 'unknown') 'effort never guessed'

# Readiness: the denominator is what was measured.
$r = Get-UnattendedReadiness -Entry ([pscustomobject]@{ hasReadme = $true; hasRoadmap = $true; roadmapState = 'no-checklist'; localDirtyCount = 1 })
Assert-That ($r.ready -eq 1 -and $r.measured -eq 3 -and $r.summary -like '1 of 3 ready*ci present unmeasured') "readiness summary: got $($r.summary)"
Assert-That ((@($r.factors | Where-Object key -eq 'clean-tree'))[0].detail -eq '1 uncommitted file block dispatch.') 'dirty singular'
Assert-That ((@($r.factors | Where-Object key -eq 'roadmap-machine-readable'))[0].detail -like '*sound*') 'no-checklist is never called damaged'
Assert-That ((Get-UnattendedReadiness -Entry ([pscustomobject]@{})).summary -like 'unmeasured*') 'nothing measured reads unmeasured'
# The cases unattendedReadiness.test.ts held while the assessment ran in the browser.
$full = [pscustomobject]$ready4
Assert-That ((Get-UnattendedReadiness -Entry $full).summary -eq '4 of 4 ready') 'four ready checks'
$noReadme = [pscustomobject](With $ready4 @{ hasReadme = $false })
Assert-That ((@((Get-UnattendedReadiness -Entry $noReadme).factors | Where-Object key -eq 'docs'))[0].detail -like 'README.md is missing*') 'names the missing document'
$noCi = [pscustomobject](With $ready4 @{ hasCiSignal = $null })
Assert-That ((Get-UnattendedReadiness -Entry $noCi).summary -eq ('3 of 3 ready {0} ci present unmeasured' -f [char]0x00B7)) 'absent CI is unmeasured and leaves the denominator'
$parseError = [pscustomobject](With $ready4 @{ roadmapState = 'parse-error' })
Assert-That ((@((Get-UnattendedReadiness -Entry $parseError).factors | Where-Object key -eq 'roadmap-machine-readable'))[0].detail -like '*could not be parsed*') 'parse error reads as a parse error'
$veryDirty = [pscustomobject](With $ready4 @{ localDirtyCount = 1993 })
Assert-That ((@((Get-UnattendedReadiness -Entry $veryDirty).factors | Where-Object key -eq 'clean-tree'))[0].detail -like '*1993 uncommitted files*') 'says how dirty'
$unread = [pscustomobject](With $ready4 @{ localDirtyCount = $null })
Assert-That ((@((Get-UnattendedReadiness -Entry $unread).factors | Where-Object key -eq 'clean-tree'))[0].state -eq 'unmeasured') 'an unread tree is never called clean'

# Pin reasons: set only on a row above a readier one, naming the key that won.
$rows = @(Add-PortfolioRanking -Entries @((Get-FixtureRepo 'Fav' @{ curationState = 'favorite' }), (Get-FixtureRepo 'Readier' $ready4)))
Assert-That ($rows[0].repoName -eq 'Fav' -and $rows[0].ranking.pinReason -like '*favorite*' -and $null -eq $rows[1].ranking.pinReason) 'pin names curation'
$rows = @(Add-PortfolioRanking -Entries @((Get-FixtureRepo 'Strengthen'), (Get-FixtureRepo 'HealthyReadier' (With $ready4 @{ outcome = (Get-FixtureOutcome 'appropriate-as-is') }))))
Assert-That ($rows[0].ranking.pinReason -like '*next step*') 'pin names the conclusion'
$rows = @(Add-PortfolioRanking -Entries @((Get-FixtureRepo 'Actionable'), (Get-FixtureRepo 'NoActionReadier' (With $ready4 @{ outcome = (Get-FixtureOutcome 'strengthen' -WithAction $false) }))))
Assert-That ($rows[0].ranking.pinReason -like '*offers an action*') 'pin names actionability'
$rows = @(Add-PortfolioRanking -Entries @((Get-FixtureRepo 'Top' $ready4), (Get-FixtureRepo 'Next' (With $ready4 @{ localDirtyCount = 3 }))))
Assert-That ($null -eq $rows[0].ranking.pinReason -and $null -eq $rows[1].ranking.pinReason) 'pin silent in readiness order'

# ---------------------------------------------------------------------------
# 2. Deterministic.
# ---------------------------------------------------------------------------
function Get-FixturePortfolio {
    return @(
        (Get-FixtureRepo 'charlie' $ready4),
        (Get-FixtureRepo 'alpha' (With $ready4 @{ localDirtyCount = 2 })),
        (Get-FixtureRepo 'bravo' @{ curationState = 'favorite' }),
        (Get-FixtureRepo 'delta' @{ outcome = (Get-FixtureOutcome 'appropriate-as-is') }),
        (Get-FixtureRepo 'echo' @{ outcome = (Get-FixtureOutcome 'insufficiently-understood') }),
        (Get-FixtureRepo 'foxtrot' @{ outcome = (Get-FixtureOutcome 'strengthen' -GapCount 2 -GapDomains @('planning', 'purpose')) }),
        (Get-FixtureRepo 'golf' @{ estimatedSessionWorkUnits = 2 })
    )
}
$first = Get-RankOrder (Get-FixturePortfolio)
$reversed = Get-FixturePortfolio; [array]::Reverse($reversed)
$again = Get-RankOrder $reversed
Assert-That (($first -join ',') -eq ($again -join ',')) "same inputs, same order: $($first -join ',') vs $($again -join ',')"
Assert-That (($first -join ',') -eq 'bravo,charlie,alpha,foxtrot,golf,echo,delta') "fixture order: got $($first -join ',')"

# ---------------------------------------------------------------------------
# 3. One scale: the board reads Today's rank.
# ---------------------------------------------------------------------------
$today = @(Add-PortfolioRanking -Entries (Get-FixturePortfolio))
$todayRank = @{}; foreach ($t in $today) { $todayRank[$t.repoName] = $t.ranking.rank }

# priorityScore deliberately inverts Today's order: the old board ranked by it.
$ledger = @{
    entries = @(
        @{ repoName = 'delta'; repoPath = 'C:\repos\delta'; executionState = 'ready'; priorityScore = 190 },
        @{ repoName = 'alpha'; repoPath = 'C:/Repos/Alpha/'; executionState = 'ready'; priorityScore = 150 },
        @{ repoName = 'golf'; repoPath = ''; executionState = 'ready'; priorityScore = 140 },
        @{ repoName = 'charlie'; repoPath = 'C:\repos\charlie'; executionState = 'blocked'; priorityScore = 120 },
        @{ repoName = 'bravo'; repoPath = 'C:\repos\bravo'; executionState = 'ready'; priorityScore = 10 },
        @{ repoName = 'not-indexed'; repoPath = 'C:\elsewhere\not-indexed'; executionState = 'ready'; priorityScore = 999 }
    )
}
$board = Get-BoardOrder -Ledger $ledger -PortfolioEntries $today
$boardNames = @($board.entries | ForEach-Object { $_.repoName })
Assert-That ($board.rankSource -eq 'portfolio') 'board ranks on the portfolio scale'
Assert-That (($boardNames -join ',') -eq 'bravo,charlie,alpha,golf,delta,not-indexed') "board order is Today's order: got $($boardNames -join ',')"
foreach ($e in @($board.entries | Where-Object { $_.repoName -ne 'not-indexed' })) {
    Assert-That ($e.portfolioRank -eq $todayRank[$e.repoName]) "board #$($e.portfolioRank) for $($e.repoName) is Today's #$($todayRank[$e.repoName])"
    Assert-That (@($e.rankBasis).Count -gt 0) "board row $($e.repoName) carries its rank basis"
}
$stray = @($board.entries | Where-Object { $_.repoName -eq 'not-indexed' })[0]
Assert-That ($null -eq $stray.portfolioRank -and $stray.rankNote -like '*Not in the portfolio index*') 'an unindexed ledger entry is unranked, says why, and sorts last'
$ready = @(Get-RankedQueue -Ledger $ledger -PortfolioEntries $today | ForEach-Object { $_.repoName })
Assert-That (($ready -join ',') -eq 'bravo,alpha,golf,delta,not-indexed') "ranked queue is the ready subset in board order: got $($ready -join ',')"

# Two indexed repositories sharing a name are not guessed between.
$twins = @(Add-PortfolioRanking -Entries @((Get-FixtureRepo 'twin' @{ repoId = 'path:a'; localPath = 'C:\a\twin' }), (Get-FixtureRepo 'twin' @{ repoId = 'path:b'; localPath = 'C:\b\twin' })))
$twinBoard = Get-BoardOrder -Ledger @{ entries = @(@{ repoName = 'twin'; repoPath = ''; executionState = 'ready'; priorityScore = 1 }) } -PortfolioEntries $twins
Assert-That ($null -eq @($twinBoard.entries)[0].portfolioRank -and @($twinBoard.entries)[0].rankNote -like '*share this name*') 'ambiguous name is unranked with its reason'
$twinByPath = Get-BoardOrder -Ledger @{ entries = @(@{ repoName = 'twin'; repoPath = 'C:\b\twin'; executionState = 'ready'; priorityScore = 1 }) } -PortfolioEntries $twins
Assert-That (@($twinByPath.entries)[0].portfolioRank -eq @($twins | Where-Object localPath -eq 'C:\b\twin')[0].ranking.rank) 'path resolves the ambiguity'

# ---------------------------------------------------------------------------
# 4. No ranking to read: say so, never fall back to priorityScore.
# ---------------------------------------------------------------------------
$blind = Get-BoardOrder -Ledger $ledger -PortfolioEntries $null
Assert-That ($blind.rankSource -eq 'unavailable' -and $blind.rankUnavailableReason) 'no ranking is reported unavailable'
Assert-That ((@($blind.entries | ForEach-Object { $_.repoName }) -join ',') -eq 'alpha,bravo,charlie,delta,golf,not-indexed') 'unavailable lists by name, not priorityScore'

# ---------------------------------------------------------------------------
# 5. The frontend holds no ranking arithmetic.
# ---------------------------------------------------------------------------
# A sort whose comparator reads a ranking input is a second ranking. The only
# order Today and the board may apply is the server's `rank`.
$rankingInputs = 'priorityScore|valueScore|conclusion|curationState|readiness|gapCount|estimatedSessionWorkUnits|dispatchReadiness|lifecycleState'
$forbiddenIdentifiers = 'CONCLUSION_PRECEDENCE|CURATION_PRECEDENCE|assessUnattendedReadiness'

# The comparator a `.sort(` call applies: the text up to its matching close
# paren, and - when that is a bare name - the body of the function it names.
function Get-SortComparator {
    param([string]$Text, [int]$Start)
    $depth = 1
    $i = $Start
    while ($i -lt $Text.Length -and $depth -gt 0 -and ($i - $Start) -lt 800) {
        if ($Text[$i] -eq '(') { $depth++ } elseif ($Text[$i] -eq ')') { $depth-- }
        $i++
    }
    $comparator = $Text.Substring($Start, [math]::Max(0, $i - $Start - 1))
    if ($comparator.Trim() -match '^[A-Za-z_$][\w$]*$') {
        $name = [regex]::Escape($comparator.Trim())
        $definition = [regex]::Match($Text, "(function\s+$name\s*\(|(const|let)\s+$name\s*=)")
        if ($definition.Success) {
            $end = $Text.IndexOf("`n}", $definition.Index)
            if ($end -lt 0) { $end = [math]::Min($Text.Length, $definition.Index + 1200) }
            $comparator = $Text.Substring($definition.Index, $end - $definition.Index)
        }
    }
    return $comparator
}

function Find-RankingArithmetic {
    param([string]$Text, [string]$Label)
    $found = [System.Collections.Generic.List[string]]::new()
    $lineOf = { param([int]$Index) ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count + 1 }
    foreach ($m in [regex]::Matches($Text, "\b($forbiddenIdentifiers)\b")) {
        $found.Add("${Label}:$(& $lineOf $m.Index) names $($m.Groups[1].Value)")
    }
    foreach ($m in [regex]::Matches($Text, '\.sort\(')) {
        $comparator = Get-SortComparator -Text $Text -Start ($m.Index + $m.Length)
        $hit = [regex]::Match($comparator, "\b($rankingInputs)\b")
        if ($hit.Success) { $found.Add("${Label}:$(& $lineOf $m.Index) sorts on $($hit.Groups[1].Value)") }
    }
    return $found.ToArray()
}

# Shown red first: a gate that cannot fail proves nothing.
$redSnippet = "const ranked = [...entries].sort((a, b) => b.priorityScore - a.priorityScore);"
Assert-That (@(Find-RankingArithmetic -Text $redSnippet -Label 'fixture').Count -eq 1) 'the scan flags a priorityScore sort'
Assert-That (@(Find-RankingArithmetic -Text "const CONCLUSION_PRECEDENCE = {};" -Label 'fixture').Count -eq 1) 'the scan flags a precedence table'
$namedRed = "function compare(a, b) {`n  return rank(a.conclusion) - rank(b.conclusion);`n}`nrows.sort(compare);"
Assert-That (@(Find-RankingArithmetic -Text $namedRed -Label 'fixture').Count -eq 1) 'the scan reads a named comparator'
$allowed = "rows.sort((a, b) => (a.ranking?.rank ?? 0) - (b.ranking?.rank ?? 0));`nconst conclusion = row.conclusion;"
Assert-That (@(Find-RankingArithmetic -Text $allowed -Label 'fixture').Count -eq 0) 'the scan allows ordering by the server rank'

# Scope is derived: the two views and every frontend module they import.
$frontendRoot = Join-Path $WorkspaceRoot 'frontend'
function Resolve-FrontendImport {
    param([string]$FromFile, [string]$Spec)
    if (-not $Spec.StartsWith('.')) { return $null }
    $base = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $FromFile) $Spec))
    foreach ($candidate in @($base, "$base.ts", "$base.tsx", (Join-Path $base 'index.ts'), (Join-Path $base 'index.tsx'))) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}
$queue = [System.Collections.Generic.Queue[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($root in @('components\TodayView.tsx', 'components\ExecutionQueuePanel.tsx')) {
    $p = Join-Path $frontendRoot $root
    if (Test-Path -LiteralPath $p) { $queue.Enqueue($p); $null = $seen.Add($p) }
}
while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, "(?m)^\s*import\s[^;]*?from\s+'([^']+)'")) {
        $resolved = Resolve-FrontendImport -FromFile $file -Spec $m.Groups[1].Value
        # types.ts and the API client are data shapes and transport, not views.
        if ($resolved -and $resolved -notmatch '\\(types|services\\apiClient)\.ts$' -and $seen.Add($resolved)) { $queue.Enqueue($resolved) }
    }
}
$scanned = @($seen)
Assert-That ($scanned.Count -ge 2) "the scan examined $($scanned.Count) file(s); zero examined is a failure, not a pass"
$violations = @()
foreach ($file in $scanned) {
    $rel = $file.Substring($WorkspaceRoot.Length + 1)
    $violations += @(Find-RankingArithmetic -Text (Get-Content -LiteralPath $file -Raw -Encoding UTF8) -Label $rel)
}
Assert-That ($violations.Count -eq 0) ("ranking arithmetic in the frontend: " + ($violations -join '; '))

# ---------------------------------------------------------------------------
Write-Host ("One ranking: {0} assertion(s) passed, {1} failed; {2} frontend module(s) scanned." -f $passed, $failures.Count, $scanned.Count)
foreach ($f in $failures) { Write-Host "  FAIL $f" -ForegroundColor Red }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }

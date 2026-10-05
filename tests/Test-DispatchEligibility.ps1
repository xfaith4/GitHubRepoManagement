#Requires -Version 7.0
<#
.SYNOPSIS
    One dispatch-eligibility rule (Lane 0.22), proved offline against fixtures.

.DESCRIPTION
    Proves that Get-DispatchEligibility answers { ok, reasons[] } and holds a
    repository for each recorded cause - uncommitted changes, archived curation,
    a blocked ledger entry, a folder missing from the index - and never for an
    unmeasured one; that the board queue lists only eligible entries; and that
    held entries collapse into a per-reason summary.

.EXAMPLE
    pwsh ./tests/Test-DispatchEligibility.ps1 -FailOnError
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
. (Join-Path $WorkspaceRoot 'backend/modules/execution/Execution.Ledger.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/execution/Execution.Eligibility.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

function New-Ledger { param([string]$Name, [string]$State = 'ready', [string]$Err = $null)
    $e = New-LedgerEntry -RepoName $Name -RepoPath "C:\repos\$Name" -ExecutionState $State
    $e['errorMessage'] = $Err
    $e
}
function New-Indexed { param([string]$Name, [object]$Dirty = 0, [string]$Curation = 'none')
    [pscustomobject]@{ repoName = $Name; localPath = "C:\repos\$Name"; localDirtyCount = $Dirty; curationState = $Curation
        ranking = [pscustomobject]@{ rank = 1; basis = @() } }
}
function Get-Codes { param($Result) @($Result.reasons | ForEach-Object { $_.code }) }

# 1. each recorded cause holds, alone
$clean = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a') -PortfolioEntry (New-Indexed 'a')
Assert-That ($clean.ok -eq $true -and @($clean.reasons).Count -eq 0) 'a clean, indexed, ready repository is eligible with no reasons'

$dirty = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a') -PortfolioEntry (New-Indexed 'a' -Dirty 3)
Assert-That ((-not $dirty.ok) -and (Get-Codes $dirty) -contains 'uncommitted-changes') 'uncommitted changes hold'
Assert-That ($dirty.reasons[0].detail -match '3 uncommitted files') 'the dirty reason names the count'

$arch = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a') -PortfolioEntry (New-Indexed 'a' -Curation 'archived-ignore')
Assert-That ((-not $arch.ok) -and (Get-Codes $arch) -contains 'archived') 'archived curation holds'

$blocked = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a' 'blocked' 'needs a human') -PortfolioEntry (New-Indexed 'a')
Assert-That ((-not $blocked.ok) -and (Get-Codes $blocked) -contains 'blocked' -and $blocked.reasons[0].detail -eq 'needs a human') 'a blocked ledger entry holds and carries its own detail'

$missing = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a') -PortfolioEntry $null
Assert-That ((-not $missing.ok) -and (Get-Codes $missing) -contains 'not-in-index') 'a folder not in the index holds'

# 2. unmeasured is not a hold
$unmeasured = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a') -PortfolioEntry ([pscustomobject]@{ repoName = 'a'; localPath = 'C:\repos\a' })
Assert-That $unmeasured.ok 'an unread working tree is not a dirty one'

# 3. every cause is reported, not only the first
$many = Get-DispatchEligibility -LedgerEntry (New-Ledger 'a' 'blocked') -PortfolioEntry (New-Indexed 'a' -Dirty 1 -Curation 'archived-ignore')
Assert-That (@($many.reasons).Count -eq 3) 'all three causes are listed'

# 4. matching: path first, unique name second, ambiguous name matches nothing
$idx = @((New-Indexed 'ok'), (New-Indexed 'dup' -Dirty 2), ([pscustomobject]@{ repoName = 'dup'; localPath = 'D:\other\dup'; localDirtyCount = 0; curationState = 'none' }))
Assert-That ($null -ne (Find-EligibilityPortfolioEntry -LedgerEntry (New-Ledger 'ok') -PortfolioEntries $idx)) 'matches by path'
$byNameOnly = [ordered]@{ repoName = 'ok'; repoPath = '' }
Assert-That ($null -ne (Find-EligibilityPortfolioEntry -LedgerEntry $byNameOnly -PortfolioEntries $idx)) 'matches a unique name when no path is recorded'
$ambiguous = [ordered]@{ repoName = 'dup'; repoPath = '' }
Assert-That ($null -eq (Find-EligibilityPortfolioEntry -LedgerEntry $ambiguous -PortfolioEntries $idx)) 'a name shared by two indexed repositories matches neither'

# 5. the board queue and the held summary
$ws = Join-Path ([System.IO.Path]::GetTempPath()) ("elig-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $ws | Out-Null
try {
    $ledger = @{ schemaVersion = 1; updatedAt = 'now'; history = @()
        entries = @((New-Ledger 'good'), (New-Ledger 'messy'), (New-Ledger 'old'), (New-Ledger 'ghost')) }
    function Read-ExecutionLedger { param($WorkspaceRoot) $script:ledger }
    $index = @((New-Indexed 'good'), (New-Indexed 'messy' -Dirty 4), (New-Indexed 'old' -Curation 'archived-ignore'))
    $summary = Get-ExecutionQueueSummary -WorkspaceRoot $ws -PortfolioEntries $index
    $queued = @($summary.rankedQueue | ForEach-Object { $_.repoName })
    Assert-That ($queued.Count -eq 1 -and $queued[0] -eq 'good') "only the eligible repository is queued (got: $($queued -join ','))"
    Assert-That ($summary.heldSummary.heldCount -eq 3) 'three repositories are held'
    $codes = @($summary.heldSummary.byReason | ForEach-Object { $_.code })
    Assert-That (($codes -contains 'uncommitted-changes') -and ($codes -contains 'archived') -and ($codes -contains 'not-in-index')) 'held entries collapse by reason'
    Assert-That (@($summary.entries).Count -eq 4) 'held entries stay in entries[] for the "N held" list'
    Assert-That (@($summary.entries | Where-Object { $null -eq $_.eligibility }).Count -eq 0) 'every entry carries eligibility'
} finally {
    Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
}

# 6. the rule is the same function on every path: the host and board hold no second copy
$hits = @(Get-ChildItem -Path (Join-Path $WorkspaceRoot 'backend') -Recurse -Filter *.ps1 |
    Where-Object { $_.Name -ne 'Execution.Eligibility.ps1' } |
    Select-String -Pattern "function\s+(Get|Test)-DispatchEligib" -List)
Assert-That ($hits.Count -eq 0) 'no second dispatch-eligibility function exists'

Write-Host ("Test-DispatchEligibility: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }

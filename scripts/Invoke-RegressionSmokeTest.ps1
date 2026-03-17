[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tempRoot = Join-Path $WorkspaceRoot 'output\smoke\regression'
$null = New-Item -ItemType Directory -Path $tempRoot -Force

Write-Host '[STEP] Duplicate detection regression check' -ForegroundColor Cyan
. (Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.ps1') -LoadFunctionsOnly

$dupeItems = @(
    [pscustomobject]@{
        LocalPath = 'G:\Repos\A'
        FolderName = 'A'
        ParentPath = 'G:\Repos'
        GitRepoName = 'alpha'
        GitOriginUrl = 'https://github.com/org/alpha.git'
        CurrentBranch = 'main'
        LastCommitDate = ''
        ModifiedCount = 0
        Fingerprint = [pscustomobject]@{
            TopLevelDirs = @('src', 'docs')
            KeyFiles = @('README.md', 'LICENSE')
            Extensions = @('.ps1:4', '.md:2')
        }
    },
    [pscustomobject]@{
        LocalPath = 'G:\Repos\B'
        FolderName = 'B'
        ParentPath = 'G:\Repos'
        GitRepoName = 'alpha'
        GitOriginUrl = 'https://github.com/org/alpha.git'
        CurrentBranch = 'main'
        LastCommitDate = ''
        ModifiedCount = 0
        Fingerprint = [pscustomobject]@{
            TopLevelDirs = @('src', 'docs')
            KeyFiles = @('README.md', 'LICENSE')
            Extensions = @('.ps1:3', '.md:1')
        }
    }
)
$dupes = @(Get-PotentialLocalDuplicates -LocalItems $dupeItems)
if ($dupes.Count -lt 1) {
    throw 'Expected at least one duplicate candidate from regression fixture.'
}

Write-Host '[STEP] Doc queue scoring regression check' -ForegroundColor Cyan
$queuePath = Join-Path $WorkspaceRoot 'tests\fixtures\regression\docreview-queue.json'
if (-not (Test-Path -LiteralPath $queuePath)) {
    throw "Queue regression source artifact not found: $queuePath"
}

$queue = @(Get-Content -LiteralPath $queuePath -Raw | ConvertFrom-Json)
if ($queue.Count -lt 1) {
    throw 'Queue regression output is empty.'
}

$scores = @($queue | Select-Object -ExpandProperty QueueScore)
for ($i = 1; $i -lt $scores.Count; $i++) {
    if ([double]$scores[$i] -gt [double]$scores[$i - 1]) {
        throw 'Queue scoring order regression detected (not sorted descending).'
    }
}

Write-Host '[PASS] Regression smoke completed' -ForegroundColor Green

[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',
    [string]$StagingRoot = 'G:\Development\20_Staging',
    [string[]]$LocalRoots = @('G:\Development'),
    [string]$GitHubOwner = '',
    [switch]$SkipDocReview,
    [switch]$SkipReconciliation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$baselineRoot = Join-Path $WorkspaceRoot 'evidence\baseline'
$runDir = Join-Path $baselineRoot $timestamp
$null = New-Item -ItemType Directory -Force -Path $runDir

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Assert-Path {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required path not found: $Path"
    }
}

function Resolve-Stage1ManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PreferredDir,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $preferred = Join-Path $PreferredDir 'doc-review-manifest.json'
    if (Test-Path -LiteralPath $preferred) {
        return $preferred
    }

    $fallbackCandidates = @(
        (Join-Path $WorkspaceRoot 'backend\modules\output\inventory\doc-review-manifest.json'),
        (Join-Path $WorkspaceRoot 'backend\output\inventory\doc-review-manifest.json')
    )

    foreach ($candidate in $fallbackCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "Unable to locate doc-review-manifest.json in preferred or fallback locations."
}

Write-Step 'Validating source repositories and local module paths'
$requiredPaths = @(
    'G:\Development\20_Staging\GitHubRepoManagerDashboard',
    'G:\Development\Doc_Review_Inventory',
    'G:\Development\Repo_reconciliation-dashboard',
    (Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewInventory.ps1'),
    (Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.ps1')
)
$requiredPaths | ForEach-Object { Assert-Path -Path $_ }

$manifest = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    WorkspaceRoot = $WorkspaceRoot
    StagingRoot = $StagingRoot
    LocalRoots = @($LocalRoots)
    GitHubOwner = $GitHubOwner
    SkipDocReview = $SkipDocReview.IsPresent
    SkipReconciliation = $SkipReconciliation.IsPresent
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'baseline-run.json') -Encoding UTF8

if (-not $SkipDocReview) {
    Write-Step 'Running doc review Stage 1 inventory baseline'
    $docOut = Join-Path $runDir 'docreview'
    $null = New-Item -ItemType Directory -Force -Path $docOut

    & (Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewInventory.ps1') `
        -RootPath $StagingRoot `
        -OutDir $docOut `
        -MaxDepth 3

    $stage1ManifestPath = Resolve-Stage1ManifestPath -PreferredDir $docOut -WorkspaceRoot $WorkspaceRoot
    $stage1Dir = Split-Path -Path $stage1ManifestPath -Parent
    if ($stage1Dir -ne $docOut) {
        Write-Step "Stage 1 outputs detected in fallback path: $stage1Dir; copying to baseline folder"
        Copy-Item -Force (Join-Path $stage1Dir 'doc-review-manifest.json') (Join-Path $docOut 'doc-review-manifest.json')
        if (Test-Path -LiteralPath (Join-Path $stage1Dir 'doc-review-summary.csv')) {
            Copy-Item -Force (Join-Path $stage1Dir 'doc-review-summary.csv') (Join-Path $docOut 'doc-review-summary.csv')
        }
        if (Test-Path -LiteralPath (Join-Path $stage1Dir 'doc-review-report.md')) {
            Copy-Item -Force (Join-Path $stage1Dir 'doc-review-report.md') (Join-Path $docOut 'doc-review-report.md')
        }
    }

    Write-Step 'Running doc review Stage 2a queue baseline'
    & (Join-Path $WorkspaceRoot 'backend\modules\docreview\Build-DocReviewQueue.ps1') `
        -ManifestPath (Join-Path $docOut 'doc-review-manifest.json') `
        -OutDir (Join-Path $docOut 'queue') `
        -MaxFilesPerBatch 5
}

if (-not $SkipReconciliation) {
    Write-Step 'Running reconciliation baseline (local inventory; optional GitHub comparison)'
    $recOut = Join-Path $runDir 'reconciliation'
    $null = New-Item -ItemType Directory -Force -Path $recOut
    $logPath = Join-Path $recOut 'reconciliation.log'

    $args = @{
        LocalRoots = @($LocalRoots)
        OutDir = $recOut
        LogPath = $logPath
        OpenHtmlReport = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($GitHubOwner)) {
        $args['GitHubOwner'] = $GitHubOwner
    }

    & (Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.ps1') @args
}

Write-Step "Baseline capture complete: $runDir"
Write-Host "Output: $runDir" -ForegroundColor Green

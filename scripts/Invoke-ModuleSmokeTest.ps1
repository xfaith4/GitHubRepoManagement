[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

$docInventory = Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewInventory.ps1'
$docQueue = Join-Path $WorkspaceRoot 'backend\modules\docreview\Build-DocReviewQueue.ps1'
$docBatch = Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewBatchPlan.ps1'
$reconcile = Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.ps1'
$reconcileModular = Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.Modular.ps1'
$reconcileTests = Join-Path $WorkspaceRoot 'backend\modules\reconcile\repo_reconciliation.Tests.ps1'

Write-Step 'Loading reconciliation module functions only'
& $reconcile -LoadFunctionsOnly
Write-Host 'Loaded reconciliation module successfully' -ForegroundColor Green

Write-Step 'Validating copied module files exist'
@($docInventory, $docQueue, $docBatch, $reconcile, $reconcileModular, $reconcileTests) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        throw "Missing module file: $_"
    }
}
Write-Host 'All expected module files are present' -ForegroundColor Green

Write-Step 'Running reconciliation preflight check'
& (Join-Path $WorkspaceRoot 'backend\modules\reconcile\preflight-check.ps1')

Write-Step 'Running modular reconciliation smoke test (narrow scope)'
& $reconcileModular `
    -LocalRoots @($WorkspaceRoot) `
    -OutDir (Join-Path $WorkspaceRoot 'evidence\baseline\smoke-modular') `
    -IncludeNonGitFolders:$false `
    -MaxDepth 2 | Out-Null

Write-Step 'Smoke test completed'

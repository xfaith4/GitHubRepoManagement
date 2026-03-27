[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $WorkspaceRoot 'backend\adapters\Adapters.ps1')

Write-Host '[STEP] Status adapter smoke run' -ForegroundColor Cyan
$status = Get-StatusAdapterResult -LocalRoots @($WorkspaceRoot) -MaxDepth 2 -IncludeNonGitFolders:$false
if (-not $status.success) {
    throw "Status adapter failed: $($status.error)"
}

Write-Host '[STEP] Reconcile adapter smoke run' -ForegroundColor Cyan
$reconcileOut = Join-Path $WorkspaceRoot 'output\smoke\adapter\reconcile'
$reconcile = Invoke-ReconcileAdapter -LocalRoots @($WorkspaceRoot) -OutDir $reconcileOut -IncludeNonGitFolders:$false -MaxDepth 2
if (-not $reconcile.success) {
    throw "Reconcile adapter failed: $($reconcile.error)"
}

Write-Host '[STEP] DocReview adapter smoke run' -ForegroundColor Cyan
$docOut = Join-Path $WorkspaceRoot 'output\smoke\adapter\docreview'
$docreview = Invoke-DocReviewAdapter -RootPath $WorkspaceRoot -OutDir $docOut -GenerateQueue:$false -GenerateBatchPlan:$false
if (-not $docreview.success) {
    throw "DocReview adapter failed: $($docreview.error)"
}

Write-Host '[PASS] Adapter smoke completed' -ForegroundColor Green
[pscustomobject]@{
    statusSuccess = $status.success
    reconcileSuccess = $reconcile.success
    docreviewSuccess = $docreview.success
    reconcileJsonPath = $reconcile.data.JsonPath
    docManifestPath = $docreview.data.inventoryManifestPath
} | Format-List

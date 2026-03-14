[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',
    [string]$BaseUrl = 'http://localhost:7071'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$logPath = Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke.log'

$job = Start-Job -ScriptBlock {
    param($ScriptPath, $Root, $Log)
    & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port 7071 -LogPath $Log
} -ArgumentList $hostScript, $WorkspaceRoot, $logPath

Start-Sleep -Seconds 2

try {
    Write-Host '[STEP] Health checks' -ForegroundColor Cyan
    $live = Invoke-RestMethod -Uri "$BaseUrl/health/live" -Method Get
    $ready = Invoke-RestMethod -Uri "$BaseUrl/health/ready" -Method Get
    $depsResponse = Invoke-WebRequest -Uri "$BaseUrl/health/dependencies" -Method Get -SkipHttpErrorCheck
    $deps = $depsResponse.Content | ConvertFrom-Json

    Write-Host '[STEP] Status route' -ForegroundColor Cyan
    $status = Invoke-RestMethod -Uri "$BaseUrl/api/status?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=2&includeNonGitFolders=false" -Method Get

    Write-Host '[STEP] Reconcile route' -ForegroundColor Cyan
    $reconcileBody = @{
        localRoots = @($WorkspaceRoot)
        maxDepth = 2
        includeNonGitFolders = $false
        outDir = (Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke\reconcile')
    } | ConvertTo-Json -Depth 5
    $reconcile = Invoke-RestMethod -Uri "$BaseUrl/api/reconcile" -Method Post -ContentType 'application/json' -Body $reconcileBody

    Write-Host '[STEP] DocReview route' -ForegroundColor Cyan
    $docBody = @{
        rootPath = $WorkspaceRoot
        maxDepth = 2
        outDir = (Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke\docreview')
        generateQueue = $false
        generateBatchPlan = $false
    } | ConvertTo-Json -Depth 5
    $doc = Invoke-RestMethod -Uri "$BaseUrl/api/docreview/run" -Method Post -ContentType 'application/json' -Body $docBody

    Write-Host '[STEP] Artifacts route' -ForegroundColor Cyan
    $artifacts = Invoke-RestMethod -Uri "$BaseUrl/api/report/artifacts" -Method Get

    Write-Host '[STEP] Metrics route' -ForegroundColor Cyan
    $metrics = Invoke-RestMethod -Uri "$BaseUrl/metrics" -Method Get

    Write-Host '[STEP] Roadmap index route' -ForegroundColor Cyan
    $roadmapIndex = Invoke-RestMethod -Uri "$BaseUrl/api/roadmap/index?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=3" -Method Get
    if (-not $roadmapIndex.success) { throw 'roadmap/index returned success=false' }

    Write-Host '[STEP] Roadmap scan route' -ForegroundColor Cyan
    $roadmapScanBody = @{
        localRoots = @($WorkspaceRoot)
        maxDepth = 3
    } | ConvertTo-Json -Depth 3
    $roadmapScan = Invoke-RestMethod -Uri "$BaseUrl/api/roadmap/scan" -Method Post -ContentType 'application/json' -Body $roadmapScanBody
    if (-not $roadmapScan.success) { throw 'roadmap/scan returned success=false' }

    Write-Host '[STEP] Roadmap content route' -ForegroundColor Cyan
    $roadmapContentOk = $false
    $firstEntry = @($roadmapScan.data.entries)[0]
    if ($firstEntry) {
        $encodedRepo = [uri]::EscapeDataString($firstEntry.repoName)
        $contentResponse = Invoke-WebRequest -Uri "$BaseUrl/api/roadmap/content?repo=$encodedRepo" -Method Get -SkipHttpErrorCheck
        $roadmapContentOk = ($contentResponse.StatusCode -eq 200)
    } else {
        Write-Host '  (no roadmap entries found — content route skipped)' -ForegroundColor Yellow
        $roadmapContentOk = $true
    }

    Write-Host '[STEP] Log tail route' -ForegroundColor Cyan
    $logTail = Invoke-RestMethod -Uri "$BaseUrl/api/log/tail?lines=10" -Method Get
    if (-not $logTail.success) { throw 'api/log/tail returned success=false' }

    Write-Host '[PASS] API host smoke completed' -ForegroundColor Green
    [pscustomobject]@{
        liveStatus = $live.status
        readyStatus = $ready.status
        dependenciesStatus = $deps.status
        dependenciesHttpCode = [int]$depsResponse.StatusCode
        statusSuccess = $status.success
        reconcileSuccess = $reconcile.success
        docreviewSuccess = $doc.success
        artifactsCount = @($artifacts.artifacts).Count
        metricsGeneratedAt = $metrics.generatedAt
        roadmapIndexCount = $roadmapIndex.data.count
        roadmapScanCount = $roadmapScan.data.count
        roadmapContentOk = $roadmapContentOk
        logTailEntryCount = $logTail.count
    } | Format-List
}
finally {
    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
}

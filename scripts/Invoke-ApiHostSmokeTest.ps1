[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',
    [string]$BaseUrl = 'http://localhost:7071',
    [int]$Port = 7071
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$logPath = Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke.log'

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter()]
        [object]$Body
    )

    $invokeSplat = @{
        Uri = $Uri
        Method = $Method
        SkipHttpErrorCheck = $true
        TimeoutSec = 30
    }

    if ($null -ne $Body) {
        $invokeSplat.ContentType = 'application/json'
        $invokeSplat.Body = ($Body | ConvertTo-Json -Depth 8)
    }

    $response = Invoke-WebRequest @invokeSplat
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content) -and $response.Headers['Content-Type'] -like 'application/json*') {
        $json = $response.Content | ConvertFrom-Json
    }

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        ContentType = [string]$response.Headers['Content-Type']
        Content = [string]$response.Content
        Json = $json
    }
}

function Assert-Not503 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    if ([int]$Response.StatusCode -eq 503) {
        throw "$Name returned HTTP 503"
    }
}

$job = Start-Job -ScriptBlock {
    param($ScriptPath, $Root, $Log, $ListenPort)
    & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log
} -ArgumentList $hostScript, $WorkspaceRoot, $logPath, $Port

Start-Sleep -Seconds 2

try {
    Write-Host '[STEP] Health checks' -ForegroundColor Cyan
    $liveResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/live"
    $readyResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/ready"
    $depsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/dependencies"
    Assert-Not503 -Name '/health/live' -Response $liveResponse
    Assert-Not503 -Name '/health/ready' -Response $readyResponse
    Assert-Not503 -Name '/health/dependencies' -Response $depsResponse
    $live = $liveResponse.Json
    $ready = $readyResponse.Json
    $deps = $depsResponse.Json

    Write-Host '[STEP] Status route' -ForegroundColor Cyan
    $statusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/status?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=2&includeNonGitFolders=false"
    Assert-Not503 -Name '/api/status' -Response $statusResponse
    $status = $statusResponse.Json

    Write-Host '[STEP] Status cache routes' -ForegroundColor Cyan
    $statusCache = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/status/cache"
    $statusCacheClear = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/status/cache/clear" -Body @{}
    Assert-Not503 -Name '/api/status/cache' -Response $statusCache
    Assert-Not503 -Name '/api/status/cache/clear' -Response $statusCacheClear

    Write-Host '[STEP] Settings routes' -ForegroundColor Cyan
    $settingsGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/settings"
    Assert-Not503 -Name '/api/settings (GET)' -Response $settingsGet
    $settingsJson = $settingsGet.Json
    $settingsPostBody = @{
        basePath = [string]($settingsJson.data.inventory.localRoots[0] ?? $WorkspaceRoot)
        scanDepth = [int]($settingsJson.data.inventory.maxDepth ?? 3)
        daysInactive = [int]($settingsJson.data.retention.days ?? 30)
        githubUser = [string]($settingsJson.data.reconcile.gitHubOwner ?? '')
    }
    $settingsPost = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" -Body $settingsPostBody
    Assert-Not503 -Name '/api/settings (POST)' -Response $settingsPost

    Write-Host '[STEP] Placeholder and git operation routes' -ForegroundColor Cyan
    $initResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/init" -Body @{ githubUser = 'smoke-test'; cloneOwned = $false }
    $updateResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/update" -Body @{ repoNames = @('__smoke_test_missing_repo__') }
    $syncResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/sync" -Body @{ repoNames = @('__smoke_test_missing_repo__') }
    $archiveResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/archive" -Body @{}
    Assert-Not503 -Name '/api/init' -Response $initResponse
    Assert-Not503 -Name '/api/update' -Response $updateResponse
    Assert-Not503 -Name '/api/sync' -Response $syncResponse
    Assert-Not503 -Name '/api/archive' -Response $archiveResponse

    Write-Host '[STEP] Reconcile route' -ForegroundColor Cyan
    $reconcileBody = @{
        localRoots = @($WorkspaceRoot)
        maxDepth = 2
        includeNonGitFolders = $false
        outDir = (Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke\reconcile')
    }
    $reconcileResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/reconcile" -Body $reconcileBody
    Assert-Not503 -Name '/api/reconcile' -Response $reconcileResponse
    $reconcile = $reconcileResponse.Json

    Write-Host '[STEP] DocReview route' -ForegroundColor Cyan
    $docBody = @{
        rootPath = $WorkspaceRoot
        maxDepth = 2
        outDir = (Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke\docreview')
        generateQueue = $false
        generateBatchPlan = $false
    }
    $docResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/docreview/run" -Body $docBody
    Assert-Not503 -Name '/api/docreview/run' -Response $docResponse
    $doc = $docResponse.Json

    Write-Host '[STEP] Report and artifact routes' -ForegroundColor Cyan
    $artifactsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/report/artifacts"
    Assert-Not503 -Name '/api/report/artifacts' -Response $artifactsResponse
    $artifacts = $artifactsResponse.Json
    Write-Host '  /api/report/artifacts complete' -ForegroundColor DarkGray
    $artifactByRepoResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/artifacts/$([uri]::EscapeDataString((Split-Path $WorkspaceRoot -Leaf)))"
    Assert-Not503 -Name '/api/artifacts/:repoName' -Response $artifactByRepoResponse
    Write-Host '  /api/artifacts/:repoName complete' -ForegroundColor DarkGray

    $exportBody = @{
        repos = @(
            @{
                name = 'smoke-export'
                branch = 'main'
                status = 'clean'
                lastCommitDate = (Get-Date).ToString('o')
                lastCommitAuthor = 'smoke-test'
                openPrCount = 0
                commitsLastWeek = 1
                commitsLastMonth = 2
                uncommittedChanges = 0
                isArchived = $false
                isStale = $false
                owner = 'local'
                visibility = 'private'
                language = 'PowerShell'
                topics = @('smoke', 'export')
                localPath = $WorkspaceRoot
                htmlUrl = 'https://example.invalid/smoke-export'
            }
        )
        sourceLabel = 'Smoke Test'
    }
    $exportResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/export" -Body $exportBody
    Assert-Not503 -Name '/api/export' -Response $exportResponse
    $export = if ($null -ne $exportResponse.Json) { $exportResponse.Json } elseif (-not [string]::IsNullOrWhiteSpace($exportResponse.Content)) { $exportResponse.Content | ConvertFrom-Json } else { $null }
    Write-Host '  /api/export complete' -ForegroundColor DarkGray
    if ($null -eq $export -or -not ($export.PSObject.Properties.Name -contains 'data') -or [string]::IsNullOrWhiteSpace([string]$export.data.reportUrl)) {
        throw '/api/export did not return reportUrl in the response payload'
    }
    $reportOpenResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl$($export.data.reportUrl)"
    Assert-Not503 -Name '/api/reports/:reportName' -Response $reportOpenResponse
    Write-Host '  /api/reports/:reportName complete' -ForegroundColor DarkGray

    Write-Host '[STEP] Metrics route' -ForegroundColor Cyan
    $metricsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/metrics"
    Assert-Not503 -Name '/metrics' -Response $metricsResponse
    $metrics = $metricsResponse.Json

    Write-Host '[STEP] Roadmap index route' -ForegroundColor Cyan
    $roadmapIndexResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/index?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=3"
    Assert-Not503 -Name '/api/roadmap/index' -Response $roadmapIndexResponse
    $roadmapIndex = $roadmapIndexResponse.Json
    if (-not $roadmapIndex.success) { throw 'roadmap/index returned success=false' }

    Write-Host '[STEP] Roadmap scan route' -ForegroundColor Cyan
    $roadmapScanBody = @{
        localRoots = @($WorkspaceRoot)
        maxDepth = 3
    }
    $roadmapScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/scan" -Body $roadmapScanBody
    Assert-Not503 -Name '/api/roadmap/scan' -Response $roadmapScanResponse
    $roadmapScan = $roadmapScanResponse.Json
    if (-not $roadmapScan.success) { throw 'roadmap/scan returned success=false' }

    Write-Host '[STEP] Roadmap scan entry state fields' -ForegroundColor Cyan
    $roadmapStateFieldsOk = $true
    $firstEntry = @($roadmapScan.data.entries)[0]
    if ($firstEntry) {
        $validStates = @('pending', 'complete', 'parse-error')
        if (-not ($firstEntry.PSObject.Properties.Name -contains 'roadmapState')) {
            throw "roadmap/scan entry missing 'roadmapState' field"
        }
        if ([string]$firstEntry.roadmapState -notin $validStates) {
            throw ("roadmap/scan entry has unexpected roadmapState: '{0}'" -f $firstEntry.roadmapState)
        }
        if (-not ($firstEntry.PSObject.Properties.Name -contains 'pendingCount')) {
            throw "roadmap/scan entry missing 'pendingCount' field"
        }
        if (-not ($firstEntry.PSObject.Properties.Name -contains 'completedCount')) {
            throw "roadmap/scan entry missing 'completedCount' field"
        }
        Write-Host ("  entry state={0} pendingCount={1} completedCount={2}" -f $firstEntry.roadmapState, $firstEntry.pendingCount, $firstEntry.completedCount) -ForegroundColor DarkGray
    } else {
        Write-Host '  (no roadmap entries found — state field check skipped)' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Roadmap content route' -ForegroundColor Cyan
    $roadmapContentOk = $false
    if ($firstEntry) {
        $encodedRepo = [uri]::EscapeDataString($firstEntry.repoName)
        $contentResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/content?repo=$encodedRepo"
        Assert-Not503 -Name '/api/roadmap/content?repo=' -Response $contentResponse
        $roadmapContentOk = ($contentResponse.StatusCode -eq 200)
    } else {
        Write-Host '  (no roadmap entries found — content route skipped)' -ForegroundColor Yellow
        $roadmapContentOk = $true
    }

    $largeRoadmapPath = Join-Path $WorkspaceRoot 'evidence\baseline\api-host-smoke\full-roadmap-test.md'
    $largeRoadmapDir = Split-Path $largeRoadmapPath -Parent
    $null = New-Item -ItemType Directory -Path $largeRoadmapDir -Force
    $largeRoadmapContent = ('# LARGE ROADMAP' + "`n") + ('0123456789abcdef' * 40000)
    Set-Content -LiteralPath $largeRoadmapPath -Value $largeRoadmapContent -Encoding UTF8
    $expectedLargeRoadmapContent = Get-Content -LiteralPath $largeRoadmapPath -Raw -Encoding UTF8
    $encodedPath = [uri]::EscapeDataString($largeRoadmapPath)
    $fullRoadmapResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/content?path=$encodedPath"
    Assert-Not503 -Name '/api/roadmap/content?path=' -Response $fullRoadmapResponse
    $fullRoadmapJson = $fullRoadmapResponse.Json
    $fullRoadmapReturnedAll = ($fullRoadmapJson.success -and [string]$fullRoadmapJson.data.content -eq $expectedLargeRoadmapContent)

    Write-Host '[STEP] Roadmap cache routes' -ForegroundColor Cyan
    $roadmapCache = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/cache"
    $roadmapCacheClear = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/cache/clear" -Body @{}
    Assert-Not503 -Name '/api/roadmap/cache' -Response $roadmapCache
    Assert-Not503 -Name '/api/roadmap/cache/clear' -Response $roadmapCacheClear

    Write-Host '[STEP] Roadmap standard assets route (Release 0.7)' -ForegroundColor Cyan
    $roadmapStandardResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/standard"
    Assert-Not503 -Name '/api/roadmap/standard' -Response $roadmapStandardResponse
    $roadmapStandardJson = $roadmapStandardResponse.Json
    if ($roadmapStandardJson -and $roadmapStandardJson.success -eq $true) {
        $std = $roadmapStandardJson.data
        if ($null -eq $std.rules -or @($std.rules).Count -eq 0) { throw '/api/roadmap/standard returned no rules' }
        if ($null -eq $std.maturityThresholds)                   { throw '/api/roadmap/standard missing maturityThresholds' }
        Write-Host ("  /api/roadmap/standard -> ruleCount={0} maturityLevels={1}" -f $std.ruleCount, (@($std.maturityLevels) -join ',')) -ForegroundColor DarkGray
    } elseif ($roadmapStandardResponse.StatusCode -eq 404) {
        Write-Host '  /api/roadmap/standard -> 404 (standards/roadmap/roadmap-audit-rules.json not found — acceptable in non-workspace CI)' -ForegroundColor Yellow
    } else {
        throw ('/api/roadmap/standard returned unexpected status {0}' -f $roadmapStandardResponse.StatusCode)
    }

    Write-Host '[STEP] Docs audit routes' -ForegroundColor Cyan
    $docsAuditGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/docs-audit"
    $docsAuditScan = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/docs-audit/scan" -Body @{}
    Assert-Not503 -Name '/api/docs-audit' -Response $docsAuditGet
    Assert-Not503 -Name '/api/docs-audit/scan' -Response $docsAuditScan
    $docsAuditData = $docsAuditGet.Json
    $docsAuditScanData = $docsAuditScan.Json
    if (-not $docsAuditData.success) { throw '/api/docs-audit returned success=false' }
    if (-not $docsAuditScanData.success) { throw '/api/docs-audit/scan returned success=false' }
    Write-Host ("  docs-audit: {0} repos audited" -f $docsAuditData.data.count) -ForegroundColor DarkGray

    Write-Host '[STEP] GitHub and roadmap-agent routes' -ForegroundColor Cyan
    $githubStatusResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/github/status" -Body @{}
    $roadmapPreviewResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/preview" -Body @{}
    $roadmapStartResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/start" -Body @{}
    $roadmapHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap-agent/history?limit=5"
    Assert-Not503 -Name '/api/github/status' -Response $githubStatusResponse
    Assert-Not503 -Name '/api/roadmap-agent/preview' -Response $roadmapPreviewResponse
    Assert-Not503 -Name '/api/roadmap-agent/start' -Response $roadmapStartResponse
    Assert-Not503 -Name '/api/roadmap-agent/history' -Response $roadmapHistoryResponse

    Write-Host '[STEP] Copilot task packet routes (Release 0.6)' -ForegroundColor Cyan
    # Preview with a missing repoName should return non-503 (400/500 is acceptable)
    $copilotPreviewMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/copilot-task/preview" -Body @{}
    Assert-Not503 -Name '/api/copilot-task/preview (no repoName)' -Response $copilotPreviewMissingBody
    Write-Host ("  /api/copilot-task/preview (no repoName) -> HTTP {0}" -f $copilotPreviewMissingBody.StatusCode) -ForegroundColor DarkGray

    # Preview with workspace repo name — may succeed if roadmap index is warm, or fail gracefully
    $workspaceRepoName = Split-Path $WorkspaceRoot -Leaf
    $copilotPreviewResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/copilot-task/preview" -Body @{ repoName = $workspaceRepoName }
    Assert-Not503 -Name '/api/copilot-task/preview' -Response $copilotPreviewResponse
    $copilotPreviewJson = $copilotPreviewResponse.Json
    $copilotPreviewPacketOk = $false
    if ($copilotPreviewJson -and $copilotPreviewJson.success -eq $true) {
        $packet = $copilotPreviewJson.data
        if ($packet -and $packet.packetVersion -and $packet.runId -and $packet.repoContext -and $packet.selectedRoadmapItem -and $packet.generatedPrompt) {
            $copilotPreviewPacketOk = $true
            Write-Host ("  /api/copilot-task/preview -> packet runId={0} section='{1}'" -f $packet.runId, $packet.selectedRoadmapItem.section) -ForegroundColor DarkGray
        } else {
            Write-Host '  /api/copilot-task/preview returned success=true but packet fields missing' -ForegroundColor Yellow
        }
    } else {
        Write-Host ("  /api/copilot-task/preview -> HTTP {0} (non-ready repo or missing roadmap index — acceptable)" -f $copilotPreviewResponse.StatusCode) -ForegroundColor DarkGray
        $copilotPreviewPacketOk = $true  # graceful error is OK in smoke context
    }

    $copilotHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/copilot-task/history?limit=5"
    Assert-Not503 -Name '/api/copilot-task/history' -Response $copilotHistoryResponse
    $copilotHistoryJson = $copilotHistoryResponse.Json
    if (-not $copilotHistoryJson.success) { throw '/api/copilot-task/history returned success=false' }
    $copilotHistoryItemsOk = ($copilotHistoryJson.data -and $copilotHistoryJson.data.PSObject.Properties.Name -contains 'items')
    Write-Host ("  /api/copilot-task/history -> {0} item(s)" -f @($copilotHistoryJson.data.items).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Log tail route' -ForegroundColor Cyan
    $logTailResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/log/tail?lines=10"
    Assert-Not503 -Name '/api/log/tail' -Response $logTailResponse
    $logTail = $logTailResponse.Json
    if (-not $logTail.success) { throw 'api/log/tail returned success=false' }

    Write-Host '[PASS] API host smoke completed' -ForegroundColor Green
    [pscustomobject]@{
        liveStatus = $live.status
        readyStatus = $ready.status
        dependenciesStatus = $deps.status
        dependenciesHttpCode = [int]$depsResponse.StatusCode
        statusSuccess = $status.success
        statusCacheSuccess = $statusCache.Json.success
        settingsGetSuccess = $settingsGet.Json.success
        settingsPostSuccess = $settingsPost.Json.success
        initStatusCode = $initResponse.StatusCode
        updateStatusCode = $updateResponse.StatusCode
        syncStatusCode = $syncResponse.StatusCode
        archiveStatusCode = $archiveResponse.StatusCode
        reconcileSuccess = $reconcile.success
        docreviewSuccess = $doc.success
        artifactsCount = @($artifacts.artifacts).Count
        exportSuccess = $export.success
        reportOpenStatusCode = $reportOpenResponse.StatusCode
        metricsGeneratedAt = $metrics.generatedAt
        roadmapIndexCount = $roadmapIndex.data.count
        roadmapScanCount = $roadmapScan.data.count
        roadmapStateFieldsOk = $roadmapStateFieldsOk
        roadmapContentOk = $roadmapContentOk
        roadmapFullContentOk = $fullRoadmapReturnedAll
        roadmapCacheStatusCode = $roadmapCache.StatusCode
        githubStatusCode = $githubStatusResponse.StatusCode
        roadmapPreviewStatusCode = $roadmapPreviewResponse.StatusCode
        roadmapStartStatusCode = $roadmapStartResponse.StatusCode
        roadmapHistoryStatusCode = $roadmapHistoryResponse.StatusCode
        logTailEntryCount = $logTail.count
        docsAuditGetSuccess = $docsAuditData.success
        docsAuditScanSuccess = $docsAuditScanData.success
        docsAuditRepoCount = $docsAuditData.data.count
        copilotPreviewStatusCode = $copilotPreviewResponse.StatusCode
        copilotPreviewPacketOk = $copilotPreviewPacketOk
        copilotHistorySuccess = $copilotHistoryJson.success
        copilotHistoryItemsOk = $copilotHistoryItemsOk
    } | Format-List
}
finally {
    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
}

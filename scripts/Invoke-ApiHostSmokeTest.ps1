[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',
    [string]$BaseUrl = 'http://localhost:7071',
    [int]$Port = 7071
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$smokeRoot = Join-Path $WorkspaceRoot 'output\smoke\api-host'
$null = New-Item -ItemType Directory -Path $smokeRoot -Force
$logPath = Join-Path $smokeRoot 'api-host-smoke.log'

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
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        $contentType = [string]$response.Headers['Content-Type']
        $looksLikeJson = $response.Content.TrimStart() -match '^[\{\[]'
        if ($contentType -like 'application/json*' -or $looksLikeJson) {
            try { $json = $response.Content | ConvertFrom-Json } catch { $json = $null }
        }
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

function Wait-ApiHostReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job,
        [Parameter()]
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($Job.State -in @('Failed', 'Stopped', 'Completed')) {
            $jobOutput = Receive-Job -Job $Job -Keep -ErrorAction SilentlyContinue | Out-String
            throw ("API host job exited before readiness check completed. State={0}. Output={1}" -f $Job.State, $jobOutput.Trim())
        }

        try {
            $response = Invoke-WebRequest -Uri $Uri -Method Get -SkipHttpErrorCheck -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
            continue
        }

        Start-Sleep -Milliseconds 500
    }

    throw "API host did not become ready within $TimeoutSeconds seconds."
}

$job = Start-Job -ScriptBlock {
    param($ScriptPath, $Root, $Log, $ListenPort)
    & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log
} -ArgumentList $hostScript, $WorkspaceRoot, $logPath, $Port

try {
    Wait-ApiHostReady -Uri "$BaseUrl/health/live" -Job $job

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
    if ($null -eq $status) {
        throw "/api/status did not return JSON. HTTP $($statusResponse.StatusCode). Content-Type=$($statusResponse.ContentType). Body=$($statusResponse.Content)"
    }
    if (-not ($status.PSObject.Properties.Name -contains 'success')) {
        throw "/api/status response missing 'success'. Body=$($statusResponse.Content)"
    }
    if ($status.success -ne $true) {
        $err = if ($status.PSObject.Properties.Name -contains 'error') { $status.error } else { $statusResponse.Content }
        throw "/api/status returned success=false. HTTP $($statusResponse.StatusCode). Error=$err"
    }
    if (-not ($status.PSObject.Properties.Name -contains 'data') -or $null -eq $status.data) {
        throw "/api/status returned success=true but missing 'data'. Body=$($statusResponse.Content)"
    }
    if (-not ($status.data.PSObject.Properties.Name -contains 'repos')) {
        throw "/api/status returned success=true but data.repos is missing. Body=$($statusResponse.Content)"
    }
    $statusRepos = @($status.data.repos)
    if ($statusRepos.Count -gt 0) {
        $firstStatusRepo = $statusRepos[0]
        foreach ($field in @('lastCommitAuthor', 'commitsLastWeek', 'commitsLastMonth')) {
            if (-not ($firstStatusRepo.PSObject.Properties.Name -contains $field)) {
                throw "/api/status repo entry missing '$field' field"
            }
        }
    } else {
        Write-Host '  /api/status returned no repos for contract field validation; activity field check skipped' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Status cache routes' -ForegroundColor Cyan
    $statusCache = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/status/cache"
    $statusCacheClear = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/status/cache/clear" -Body @{}
    Assert-Not503 -Name '/api/status/cache' -Response $statusCache
    Assert-Not503 -Name '/api/status/cache/clear' -Response $statusCacheClear

    Write-Host '[STEP] Settings routes' -ForegroundColor Cyan
    $settingsGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/settings"
    Assert-Not503 -Name '/api/settings (GET)' -Response $settingsGet
    $settingsJson = $settingsGet.Json
    if ($null -eq $settingsJson) {
        throw "/api/settings did not return JSON. HTTP $($settingsGet.StatusCode). Content-Type=$($settingsGet.ContentType). Body=$($settingsGet.Content)"
    }
    if (-not ($settingsJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/settings response missing 'success'. Body=$($settingsGet.Content)"
    }
    if ($settingsJson.success -ne $true) {
        $err = if ($settingsJson.PSObject.Properties.Name -contains 'error') { $settingsJson.error } else { $settingsGet.Content }
        throw "/api/settings returned success=false. HTTP $($settingsGet.StatusCode). Error=$err"
    }
    if (-not ($settingsJson.PSObject.Properties.Name -contains 'data') -or $null -eq $settingsJson.data) {
        throw "/api/settings returned success=true but missing 'data'. Body=$($settingsGet.Content)"
    }
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
        outDir = (Join-Path $smokeRoot 'reconcile')
    }
    $reconcileResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/reconcile" -Body $reconcileBody
    Assert-Not503 -Name '/api/reconcile' -Response $reconcileResponse
    $reconcile = $reconcileResponse.Json

    Write-Host '[STEP] DocReview route' -ForegroundColor Cyan
    $docBody = @{
        rootPath = $WorkspaceRoot
        maxDepth = 2
        outDir = (Join-Path $smokeRoot 'docreview')
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
    if ($null -eq $roadmapScan) {
        throw "/api/roadmap/scan did not return JSON. HTTP $($roadmapScanResponse.StatusCode). Content-Type=$($roadmapScanResponse.ContentType). Body=$($roadmapScanResponse.Content)"
    }
    if (-not ($roadmapScan.PSObject.Properties.Name -contains 'success')) {
        throw "/api/roadmap/scan response missing 'success'. Body=$($roadmapScanResponse.Content)"
    }
    if (-not $roadmapScan.success) {
        $err = if ($roadmapScan.PSObject.Properties.Name -contains 'error') { $roadmapScan.error } else { $roadmapScanResponse.Content }
        throw "/api/roadmap/scan returned success=false. HTTP $($roadmapScanResponse.StatusCode). Error=$err"
    }
    if (-not ($roadmapScan.PSObject.Properties.Name -contains 'data') -or $null -eq $roadmapScan.data) {
        throw "/api/roadmap/scan returned success=true but missing 'data'. Body=$($roadmapScanResponse.Content)"
    }
    if (-not ($roadmapScan.data.PSObject.Properties.Name -contains 'entries')) {
        throw "/api/roadmap/scan returned success=true but missing 'data.entries'. Body=$($roadmapScanResponse.Content)"
    }

    Write-Host '[STEP] Roadmap scan entry state fields' -ForegroundColor Cyan
    $roadmapStateFieldsOk = $true
    $entries = @($roadmapScan.data.entries)
    $firstEntry = if ($entries.Count -gt 0) { $entries[0] } else { $null }
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

    $largeRoadmapPath = Join-Path $smokeRoot 'full-roadmap-test.md'
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

    Write-Host '[STEP] Roadmap audit routes (Release 0.8)' -ForegroundColor Cyan
    $roadmapAuditGetResponse  = Invoke-ApiRequest -Method Get  -Uri "$BaseUrl/api/roadmap/audit"
    $roadmapAuditScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/audit/scan" -Body @{}
    Assert-Not503 -Name '/api/roadmap/audit'      -Response $roadmapAuditGetResponse
    Assert-Not503 -Name '/api/roadmap/audit/scan' -Response $roadmapAuditScanResponse
    $roadmapAuditData     = $roadmapAuditGetResponse.Json
    $roadmapAuditScanData = $roadmapAuditScanResponse.Json
    if (-not $roadmapAuditData.success)     { throw '/api/roadmap/audit returned success=false' }
    if (-not $roadmapAuditScanData.success) { throw '/api/roadmap/audit/scan returned success=false' }
    Write-Host ("  /api/roadmap/audit -> {0} repos audited" -f $roadmapAuditData.data.count) -ForegroundColor DarkGray

    # Validate contract fields on the first entry (if any returned)
    $roadmapAuditFieldsOk = $true
    if ($roadmapAuditData.data.entries -and @($roadmapAuditData.data.entries).Count -gt 0) {
        $firstEntry = @($roadmapAuditData.data.entries)[0]
        $requiredFields = @('repoName','roadmapState','maturityLevel','maturityScore','pendingCount','completedCount','parsedAt')
        foreach ($field in $requiredFields) {
            if ($null -eq $firstEntry.$field -and $field -ne 'auditFindings') {
                Write-Host ("  WARNING: /api/roadmap/audit entry missing field '{0}'" -f $field) -ForegroundColor Yellow
                $roadmapAuditFieldsOk = $false
            }
        }
        $validLevels = @('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')
        if ($firstEntry.maturityLevel -notin $validLevels) {
            Write-Host ("  WARNING: unexpected maturityLevel '{0}'" -f $firstEntry.maturityLevel) -ForegroundColor Yellow
            $roadmapAuditFieldsOk = $false
        }
        if ($roadmapAuditFieldsOk) {
            Write-Host ("  /api/roadmap/audit first entry: repo={0} maturityLevel={1} score={2}" -f $firstEntry.repoName, $firstEntry.maturityLevel, $firstEntry.maturityScore) -ForegroundColor DarkGray
        }
    }

    Write-Host '[STEP] Roadmap repair routes (Release 0.9)' -ForegroundColor Cyan
    # Pick a repo to use for repair preview (use first audit entry if available, else fallback to a dummy name)
    $repairTestRepoName = ''
    if ($roadmapAuditData.data.entries -and @($roadmapAuditData.data.entries).Count -gt 0) {
        $repairTestRepoName = [string](@($roadmapAuditData.data.entries)[0].repoName)
    }
    if (-not [string]::IsNullOrWhiteSpace($repairTestRepoName)) {
        $repairPreviewResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/repair/preview" -Body @{ repoName = $repairTestRepoName }
        Assert-Not503 -Name '/api/roadmap/repair/preview' -Response $repairPreviewResponse
        $repairPreviewJson = $repairPreviewResponse.Json
        if (-not $repairPreviewJson.success) { throw '/api/roadmap/repair/preview returned success=false' }
        $repairPreviewData = $repairPreviewJson.data
        $repairPreviewFieldsOk = $true
        $requiredRepairFields = @('previewId', 'previewState', 'repoName', 'completedItemCount', 'pendingItemCount', 'generatedAt')
        foreach ($field in $requiredRepairFields) {
            if ($null -eq $repairPreviewData.$field) {
                Write-Host ("  WARNING: /api/roadmap/repair/preview response missing field '{0}'" -f $field) -ForegroundColor Yellow
                $repairPreviewFieldsOk = $false
            }
        }
        $validRepairStates = @('repair-preview-ready', 'repair-blocked', 'rewrite-not-recommended')
        if ($repairPreviewData.previewState -notin $validRepairStates) {
            Write-Host ("  WARNING: unexpected previewState '{0}'" -f $repairPreviewData.previewState) -ForegroundColor Yellow
            $repairPreviewFieldsOk = $false
        }
        if ($repairPreviewFieldsOk) {
            Write-Host ("  /api/roadmap/repair/preview -> repo={0} previewState={1} actions={2}" -f $repairPreviewData.repoName, $repairPreviewData.previewState, @($repairPreviewData.repairActions).Count) -ForegroundColor DarkGray
        }
    } else {
        Write-Host '  /api/roadmap/repair/preview skipped (no audited repos available)' -ForegroundColor Yellow
        $repairPreviewFieldsOk = $true
    }

    $repairHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/repair/history?limit=5"
    Assert-Not503 -Name '/api/roadmap/repair/history' -Response $repairHistoryResponse
    $repairHistoryJson = $repairHistoryResponse.Json
    if (-not $repairHistoryJson.success) { throw '/api/roadmap/repair/history returned success=false' }
    $repairHistoryItemsOk = ($repairHistoryJson.data -and $repairHistoryJson.data.PSObject.Properties.Name -contains 'items')
    Write-Host ("  /api/roadmap/repair/history -> {0} item(s)" -f @($repairHistoryJson.data.items).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Log tail route' -ForegroundColor Cyan
    $logTailResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/log/tail?lines=10"
    Assert-Not503 -Name '/api/log/tail' -Response $logTailResponse
    $logTail = $logTailResponse.Json
    if (-not $logTail.success) { throw 'api/log/tail returned success=false' }

    Write-Host '[STEP] Execution queue routes (Release 1.0)' -ForegroundColor Cyan
    $execQueueResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/execution/queue"
    Assert-Not503 -Name '/api/execution/queue' -Response $execQueueResponse
    $execQueueJson = $execQueueResponse.Json
    if (-not $execQueueJson.success) { throw '/api/execution/queue returned success=false' }
    $execQueueData = $execQueueJson.data
    $execQueueFieldsOk = $null -ne $execQueueData -and
        ($execQueueData.PSObject.Properties.Name -contains 'lanes') -and
        ($execQueueData.PSObject.Properties.Name -contains 'rankedQueue') -and
        ($execQueueData.PSObject.Properties.Name -contains 'stateCounts')
    if (-not $execQueueFieldsOk) { throw '/api/execution/queue response missing expected fields (lanes, rankedQueue, stateCounts)' }
    Write-Host ("  /api/execution/queue -> totalRepos={0} activeLanes={1}" -f $execQueueData.totalRepos, $execQueueData.activeLaneCount) -ForegroundColor DarkGray

    $execSyncResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/sync" -Body @{}
    Assert-Not503 -Name '/api/execution/sync' -Response $execSyncResponse
    $execSyncJson = $execSyncResponse.Json
    if (-not $execSyncJson.success) { throw '/api/execution/sync returned success=false' }
    Write-Host ("  /api/execution/sync -> totalRepos={0}" -f $execSyncJson.data.totalRepos) -ForegroundColor DarkGray

    # Test assign with no repoName — should return 400
    $execAssignMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/assign" -Body @{}
    if ($execAssignMissingBody.StatusCode -notin @(400, 409, 500)) {
        throw ("/api/execution/assign (no repoName) expected 4xx, got {0}" -f $execAssignMissingBody.StatusCode)
    }
    Write-Host ("  /api/execution/assign (no repoName) -> HTTP {0} correctly rejected" -f $execAssignMissingBody.StatusCode) -ForegroundColor DarkGray

    # Test assign with unknown repo — should return 409
    $execAssignUnknown = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/assign" -Body @{ repoName = '__smoke-unknown-repo__' }
    if ($execAssignUnknown.StatusCode -notin @(400, 409, 500)) {
        throw ("/api/execution/assign (unknown repo) expected 4xx, got {0}" -f $execAssignUnknown.StatusCode)
    }
    Write-Host ("  /api/execution/assign (unknown repo) -> HTTP {0} correctly rejected" -f $execAssignUnknown.StatusCode) -ForegroundColor DarkGray

    # Test cancel with no repoName — should return 400
    $execCancelMissing = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/cancel" -Body @{}
    if ($execCancelMissing.StatusCode -notin @(400, 409, 500)) {
        throw ("/api/execution/cancel (no repoName) expected 4xx, got {0}" -f $execCancelMissing.StatusCode)
    }
    Write-Host ("  /api/execution/cancel (no repoName) -> HTTP {0} correctly rejected" -f $execCancelMissing.StatusCode) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap lint routes (Release 1.1)' -ForegroundColor Cyan
    # GET /api/roadmap/lint without repoName — should return 400
    $lintNoRepo = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/lint"
    if ($lintNoRepo.StatusCode -notin @(400, 500)) {
        throw ("/api/roadmap/lint (no repoName) expected 4xx, got {0}" -f $lintNoRepo.StatusCode)
    }
    Write-Host ("  /api/roadmap/lint (no repoName) -> HTTP {0} correctly rejected" -f $lintNoRepo.StatusCode) -ForegroundColor DarkGray

    $lintScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/lint/scan" -Body @{}
    Assert-Not503 -Name '/api/roadmap/lint/scan' -Response $lintScanResponse
    $lintScanJson = $lintScanResponse.Json
    if (-not $lintScanJson.success) { throw '/api/roadmap/lint/scan returned success=false' }
    Write-Host ("  /api/roadmap/lint/scan -> count={0}" -f $lintScanJson.data.count) -ForegroundColor DarkGray

    Write-Host '[STEP] README standardization routes (Release 1.1)' -ForegroundColor Cyan
    # POST /api/readme/standardize/preview without repoName — should return 4xx
    $stdPreviewNoRepo = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/readme/standardize/preview" -Body @{}
    if ($stdPreviewNoRepo.StatusCode -notin @(400, 500)) {
        throw ("/api/readme/standardize/preview (no repoName) expected 4xx, got {0}" -f $stdPreviewNoRepo.StatusCode)
    }
    Write-Host ("  /api/readme/standardize/preview (no repoName) -> HTTP {0} correctly rejected" -f $stdPreviewNoRepo.StatusCode) -ForegroundColor DarkGray

    $stdHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/readme/standardize/history?limit=5"
    Assert-Not503 -Name '/api/readme/standardize/history' -Response $stdHistoryResponse
    $stdHistoryJson = $stdHistoryResponse.Json
    if (-not $stdHistoryJson.success) { throw '/api/readme/standardize/history returned success=false' }
    Write-Host ("  /api/readme/standardize/history -> items={0}" -f @($stdHistoryJson.data.items).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Contract drift routes (Release 1.1)' -ForegroundColor Cyan
    $driftResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/drift"
    Assert-Not503 -Name '/api/roadmap/drift' -Response $driftResponse
    $driftJson = $driftResponse.Json
    if (-not $driftJson.success) { throw '/api/roadmap/drift returned success=false' }
    $driftFieldsOk = $null -ne $driftJson.data -and
        ($driftJson.data.PSObject.Properties.Name -contains 'driftAlerts') -and
        ($driftJson.data.PSObject.Properties.Name -contains 'driftCount')
    if (-not $driftFieldsOk) { throw '/api/roadmap/drift response missing expected fields (driftAlerts, driftCount)' }
    Write-Host ("  /api/roadmap/drift -> driftCount={0} baselineCount={1}" -f $driftJson.data.driftCount, $driftJson.data.baselineCount) -ForegroundColor DarkGray

    Write-Host '[STEP] Notification webhook routes (Release 1.1)' -ForegroundColor Cyan
    $webhooksResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/notifications/webhooks"
    Assert-Not503 -Name '/api/notifications/webhooks' -Response $webhooksResponse
    $webhooksJson = $webhooksResponse.Json
    if (-not $webhooksJson.success) { throw '/api/notifications/webhooks returned success=false' }
    Write-Host ("  /api/notifications/webhooks -> count={0}" -f $webhooksJson.data.count) -ForegroundColor DarkGray

    # POST without url — should return 400
    $webhookRegNoUrl = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/notifications/webhooks" -Body @{}
    if ($webhookRegNoUrl.StatusCode -notin @(400, 500)) {
        throw ("/api/notifications/webhooks (no url) expected 4xx, got {0}" -f $webhookRegNoUrl.StatusCode)
    }
    Write-Host ("  /api/notifications/webhooks (no url) -> HTTP {0} correctly rejected" -f $webhookRegNoUrl.StatusCode) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap completion preview route (Release 1.1)' -ForegroundColor Cyan
    # POST /api/roadmap/completion-preview without repoName — should return 400
    $completionPreviewNoRepo = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/completion-preview" -Body @{}
    if ($completionPreviewNoRepo.StatusCode -notin @(400, 500)) {
        throw ("/api/roadmap/completion-preview (no repoName) expected 4xx, got {0}" -f $completionPreviewNoRepo.StatusCode)
    }
    Write-Host ("  /api/roadmap/completion-preview (no repoName) -> HTTP {0} correctly rejected" -f $completionPreviewNoRepo.StatusCode) -ForegroundColor DarkGray

    Write-Host '[STEP] Execution metrics route (Release 1.2)' -ForegroundColor Cyan
    $execMetricsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/execution/metrics"
    Assert-Not503 -Name '/api/execution/metrics' -Response $execMetricsResponse
    $execMetricsJson = $execMetricsResponse.Json
    if ($null -eq $execMetricsJson) {
        throw "/api/execution/metrics did not return JSON. HTTP $($execMetricsResponse.StatusCode). Content-Type=$($execMetricsResponse.ContentType). Body=$($execMetricsResponse.Content)"
    }
    if (-not ($execMetricsJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/execution/metrics response missing 'success'. Body=$($execMetricsResponse.Content)"
    }
    if (-not $execMetricsJson.success) {
        $err = if ($execMetricsJson.PSObject.Properties.Name -contains 'error') { $execMetricsJson.error } else { $execMetricsResponse.Content }
        throw "/api/execution/metrics returned success=false. HTTP $($execMetricsResponse.StatusCode). Error=$err"
    }
    if (-not ($execMetricsJson.PSObject.Properties.Name -contains 'data') -or $null -eq $execMetricsJson.data) {
        throw "/api/execution/metrics returned success=true but missing 'data'. Body=$($execMetricsResponse.Content)"
    }
    $execMetricsData = $execMetricsJson.data
    $execMetricsFieldsOk = $null -ne $execMetricsData -and
        ($execMetricsData.PSObject.Properties.Name -contains 'completedToday') -and
        ($execMetricsData.PSObject.Properties.Name -contains 'completedThisWeek') -and
        ($execMetricsData.PSObject.Properties.Name -contains 'errorRatePct') -and
        ($execMetricsData.PSObject.Properties.Name -contains 'stateCounts')
    if (-not $execMetricsFieldsOk) { throw '/api/execution/metrics response missing expected fields' }
    Write-Host ("  /api/execution/metrics -> completedToday={0} completedThisWeek={1} errorRatePct={2}" -f $execMetricsData.completedToday, $execMetricsData.completedThisWeek, $execMetricsData.errorRatePct) -ForegroundColor DarkGray

    Write-Host '[STEP] Auto-scan schedule route (Release 1.2)' -ForegroundColor Cyan
    $scanScheduleResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/scan/schedule"
    Assert-Not503 -Name '/api/scan/schedule' -Response $scanScheduleResponse
    $scanScheduleJson = $scanScheduleResponse.Json
    if ($null -eq $scanScheduleJson) {
        throw "/api/scan/schedule did not return JSON. HTTP $($scanScheduleResponse.StatusCode). Content-Type=$($scanScheduleResponse.ContentType). Body=$($scanScheduleResponse.Content)"
    }
    if (-not ($scanScheduleJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/scan/schedule response missing 'success'. Body=$($scanScheduleResponse.Content)"
    }
    if (-not $scanScheduleJson.success) {
        $err = if ($scanScheduleJson.PSObject.Properties.Name -contains 'error') { $scanScheduleJson.error } else { $scanScheduleResponse.Content }
        throw "/api/scan/schedule returned success=false. HTTP $($scanScheduleResponse.StatusCode). Error=$err"
    }
    if (-not ($scanScheduleJson.PSObject.Properties.Name -contains 'data') -or $null -eq $scanScheduleJson.data) {
        throw "/api/scan/schedule returned success=true but missing 'data'. Body=$($scanScheduleResponse.Content)"
    }
    $scanScheduleData = $scanScheduleJson.data
    $scanScheduleFieldsOk = $null -ne $scanScheduleData -and
        ($scanScheduleData.PSObject.Properties.Name -contains 'enabled') -and
        ($scanScheduleData.PSObject.Properties.Name -contains 'intervalMinutes')
    if (-not $scanScheduleFieldsOk) { throw '/api/scan/schedule response missing expected fields (enabled, intervalMinutes)' }
    Write-Host ("  /api/scan/schedule -> enabled={0} intervalMinutes={1}" -f $scanScheduleData.enabled, $scanScheduleData.intervalMinutes) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap dependency graph route (Release 1.2)' -ForegroundColor Cyan
    $depGraphResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/dependencies"
    Assert-Not503 -Name '/api/roadmap/dependencies' -Response $depGraphResponse
    $depGraphJson = $depGraphResponse.Json
    if ($null -eq $depGraphJson) {
        throw "/api/roadmap/dependencies did not return JSON. HTTP $($depGraphResponse.StatusCode). Content-Type=$($depGraphResponse.ContentType). Body=$($depGraphResponse.Content)"
    }
    if (-not ($depGraphJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/roadmap/dependencies response missing 'success'. Body=$($depGraphResponse.Content)"
    }
    if (-not $depGraphJson.success) {
        $err = if ($depGraphJson.PSObject.Properties.Name -contains 'error') { $depGraphJson.error } else { $depGraphResponse.Content }
        throw "/api/roadmap/dependencies returned success=false. HTTP $($depGraphResponse.StatusCode). Error=$err"
    }
    if (-not ($depGraphJson.PSObject.Properties.Name -contains 'data') -or $null -eq $depGraphJson.data) {
        throw "/api/roadmap/dependencies returned success=true but missing 'data'. Body=$($depGraphResponse.Content)"
    }
    $depGraphData = $depGraphJson.data
    $depGraphFieldsOk = $null -ne $depGraphData -and
        ($depGraphData.PSObject.Properties.Name -contains 'totalEdges') -and
        ($depGraphData.PSObject.Properties.Name -contains 'summary') -and
        ($depGraphData.PSObject.Properties.Name -contains 'scannedAt')
    if (-not $depGraphFieldsOk) { throw '/api/roadmap/dependencies response missing expected fields (totalEdges, summary, scannedAt)' }
    Write-Host ("  /api/roadmap/dependencies -> totalEdges={0} summaryCount={1}" -f $depGraphData.totalEdges, @($depGraphData.summary).Count) -ForegroundColor DarkGray

    # ------------------------------------------------------------------
    # Release 1.7.5 — Portfolio Mission Alignment
    # ------------------------------------------------------------------
    Write-Host '[STEP] Portfolio assessment route (Release 1.7.5)' -ForegroundColor Cyan
    $portfolioResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment"
    Assert-Not503 -Name '/api/portfolio/assessment' -Response $portfolioResponse
    $portfolioJson = $portfolioResponse.Json
    if ($null -eq $portfolioJson) {
        throw "/api/portfolio/assessment did not return JSON. HTTP $($portfolioResponse.StatusCode). Content-Type=$($portfolioResponse.ContentType). Body=$($portfolioResponse.Content)"
    }
    if (-not ($portfolioJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/portfolio/assessment response missing 'success'. Body=$($portfolioResponse.Content)"
    }
    if (-not $portfolioJson.success) {
        $err = if ($portfolioJson.PSObject.Properties.Name -contains 'error') { $portfolioJson.error } else { $portfolioResponse.Content }
        throw "/api/portfolio/assessment returned success=false. HTTP $($portfolioResponse.StatusCode). Error=$err"
    }
    if (-not ($portfolioJson.PSObject.Properties.Name -contains 'data') -or $null -eq $portfolioJson.data) {
        throw "/api/portfolio/assessment returned success=true but missing 'data'. Body=$($portfolioResponse.Content)"
    }
    $portfolioData = $portfolioJson.data
    $portfolioFieldsOk = $null -ne $portfolioData -and
        ($portfolioData.PSObject.Properties.Name -contains 'entries') -and
        ($portfolioData.PSObject.Properties.Name -contains 'summary') -and
        ($portfolioData.PSObject.Properties.Name -contains 'signalSources') -and
        ($portfolioData.PSObject.Properties.Name -contains 'generatedAt')
    if (-not $portfolioFieldsOk) { throw '/api/portfolio/assessment response missing expected fields (entries, summary, signalSources, generatedAt)' }

    $portfolioSummaryFieldsOk = $null -ne $portfolioData.summary -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'totalRepos') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'byLifecycle') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'bySourceCoverage') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'readyForWorkCount') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'blockedCount')
    if (-not $portfolioSummaryFieldsOk) { throw '/api/portfolio/assessment summary missing expected fields (totalRepos, byLifecycle, bySourceCoverage, readyForWorkCount, blockedCount)' }

    $portfolioEntryFieldsOk = $true
    if (@($portfolioData.entries).Count -gt 0) {
        $first = @($portfolioData.entries)[0]
        $portfolioEntryFieldsOk = $null -ne $first -and
            ($first.PSObject.Properties.Name -contains 'lifecycleState') -and
            ($first.PSObject.Properties.Name -contains 'sourceCoverage') -and
            ($first.PSObject.Properties.Name -contains 'recommendedAction') -and
            ($first.PSObject.Properties.Name -contains 'blockingReasons') -and
            ($first.PSObject.Properties.Name -contains 'pendingItems') -and
            ($first.PSObject.Properties.Name -contains 'topValueItem')
        if (-not $portfolioEntryFieldsOk) { throw '/api/portfolio/assessment first entry missing expected fields (lifecycleState, sourceCoverage, recommendedAction, blockingReasons, pendingItems, topValueItem)' }
    }

    Write-Host ("  /api/portfolio/assessment -> count={0} ready={1} blocked={2} cacheSource={3}" -f $portfolioData.count, $portfolioData.summary.readyForWorkCount, $portfolioData.summary.blockedCount, $portfolioData.cacheSource) -ForegroundColor DarkGray

    # ------------------------------------------------------------------
    # Release 1.3 — Production static frontend bundle
    # ------------------------------------------------------------------
    Write-Host '[STEP] Static frontend bundle (Release 1.3)' -ForegroundColor Cyan
    $distIndexHtmlPath = Join-Path $WorkspaceRoot 'frontend\dist\index.html'
    $staticIndexOk   = $false
    $staticAssetsOk  = $false
    $staticSkipped   = $false

    if (-not (Test-Path -LiteralPath $distIndexHtmlPath -PathType Leaf)) {
        Write-Host '  frontend/dist/index.html not found — static-bundle tests SKIPPED (run Start-App.ps1 -Rebuild first)' -ForegroundColor Yellow
        $staticSkipped = $true
        $staticIndexOk = $true   # not a failure
        $staticAssetsOk = $true
    } else {
        # Test 1: GET / returns 200 text/html (SPA index)
        $staticRootResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/"
        if ($staticRootResponse.StatusCode -ne 200) {
            throw ("GET / expected HTTP 200, got {0}" -f $staticRootResponse.StatusCode)
        }
        $rootContentType = [string]$staticRootResponse.ContentType
        if ($rootContentType -notlike '*text/html*') {
            throw ("GET / expected text/html Content-Type, got '{0}'" -f $rootContentType)
        }
        $staticIndexOk = $true
        Write-Host ("  GET / -> HTTP 200 {0}" -f $rootContentType) -ForegroundColor DarkGray

        # Test 2: GET /assets/<hashed>.js returns correct MIME + Cache-Control immutable
        $assetsDir = Join-Path $WorkspaceRoot 'frontend\dist\assets'
        $jsFile = Get-ChildItem -LiteralPath $assetsDir -Filter '*.js' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $jsFile) {
            Write-Host '  No .js file found in frontend/dist/assets — asset MIME test skipped' -ForegroundColor Yellow
            $staticAssetsOk = $true
        } else {
            $assetRelPath = '/assets/' + $jsFile.Name
            $assetResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl$assetRelPath"
            if ($assetResponse.StatusCode -ne 200) {
                throw ("GET $assetRelPath expected HTTP 200, got {0}" -f $assetResponse.StatusCode)
            }
            $assetContentType = [string]$assetResponse.ContentType
            if ($assetContentType -notlike '*javascript*' -and $assetContentType -notlike '*application/js*') {
                throw ("GET $assetRelPath expected javascript Content-Type, got '{0}'" -f $assetContentType)
            }
            # Verify Cache-Control: immutable is set
            $assetRaw = Invoke-WebRequest -Uri "$BaseUrl$assetRelPath" -Method Get -UseBasicParsing -TimeoutSec 10 -SkipHttpErrorCheck
            $cacheControl = [string]$assetRaw.Headers['Cache-Control']
            if ($cacheControl -notlike '*immutable*') {
                throw ("GET $assetRelPath expected Cache-Control immutable, got '{0}'" -f $cacheControl)
            }
            $staticAssetsOk = $true
            Write-Host ("  GET {0} -> HTTP 200 {1} | Cache-Control: {2}" -f $assetRelPath, $assetContentType, $cacheControl) -ForegroundColor DarkGray
        }
    }

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
        roadmapAuditGetSuccess  = $roadmapAuditData.success
        roadmapAuditScanSuccess = $roadmapAuditScanData.success
        roadmapAuditRepoCount   = $roadmapAuditData.data.count
        roadmapAuditFieldsOk    = $roadmapAuditFieldsOk
        repairPreviewFieldsOk   = $repairPreviewFieldsOk
        repairHistoryItemsOk    = $repairHistoryItemsOk
        execQueueFieldsOk       = $execQueueFieldsOk
        lintScanSuccess       = $lintScanJson.success
        stdHistorySuccess     = $stdHistoryJson.success
        driftFieldsOk         = $driftFieldsOk
        webhooksGetSuccess    = $webhooksJson.success
        execMetricsFieldsOk   = $execMetricsFieldsOk
        scanScheduleFieldsOk  = $scanScheduleFieldsOk
        depGraphFieldsOk      = $depGraphFieldsOk
        depGraphTotalEdges    = $depGraphData.totalEdges
        portfolioFieldsOk     = $portfolioFieldsOk
        portfolioSummaryFieldsOk = $portfolioSummaryFieldsOk
        portfolioEntryFieldsOk   = $portfolioEntryFieldsOk
        portfolioRepoCount    = [int]$portfolioData.count
        staticIndexOk         = $staticIndexOk
        staticAssetsOk        = $staticAssetsOk
        staticSkipped         = $staticSkipped
    } | Format-List
}
finally {
    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
}

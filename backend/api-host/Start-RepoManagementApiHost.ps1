[CmdletBinding()]
param(
    [Parameter()]
    [string]$BindAddress = '127.0.0.1',

    [Parameter()]
    [int]$Port = 7071,

    [Parameter()]
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',

    [Parameter()]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$adapterRoot = Join-Path $WorkspaceRoot 'backend\adapters'
$commonRoot = Join-Path $WorkspaceRoot 'backend\modules\common'
. (Join-Path $commonRoot 'Metrics.ps1')
. (Join-Path $adapterRoot 'Status.Adapter.ps1')
. (Join-Path $adapterRoot 'Reconcile.Adapter.ps1')
. (Join-Path $adapterRoot 'DocReview.Adapter.ps1')

function Write-HostLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
}

function Parse-Bool {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    return $text -match '^(1|true|yes|on)$'
}

function Send-HttpJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [object]$Payload,
        [Parameter()]
        [string]$StatusText = 'OK',
        [Parameter()]
        [string]$CorrelationId
    )

    $json = $Payload | ConvertTo-Json -Depth 12
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $headers = @(
        "HTTP/1.1 $StatusCode $StatusText",
        'Content-Type: application/json; charset=utf-8',
        "Content-Length: $($bodyBytes.Length)",
        'Connection: close',
        'Access-Control-Allow-Origin: *',
        'Access-Control-Allow-Methods: GET, POST, OPTIONS',
        'Access-Control-Allow-Headers: Content-Type, Authorization',
        $(if ($CorrelationId) { "X-Correlation-Id: $CorrelationId" } else { '' }),
        '',
        ''
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    $Stream.Flush()
}

function Get-ErrorCategory {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return 'internal' }
    $text = $Message.ToLowerInvariant()
    if ($text -match 'validation|invalid|missing required|cannot bind') { return 'validation' }
    if ($text -match 'timeout|timed out') { return 'timeout' }
    if ($text -match 'gh|github|network|dns|socket|connection|api') { return 'dependency' }
    return 'internal'
}

function Send-ErrorJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        [Parameter(Mandatory = $true)]
        [string]$CorrelationId,
        [Parameter()]
        [string]$Operation = 'api.request'
    )

    Add-MetricCounter -Name 'api_requests_total'
    Add-MetricCounter -Name 'operation_failures_total'
    Send-HttpJson -Stream $Stream -StatusCode $StatusCode -StatusText 'Error' -CorrelationId $CorrelationId -Payload @{
        operation = $Operation
        correlationId = $CorrelationId
        success = $false
        timestamp = (Get-Date).ToString('o')
        error = @{
            category = Get-ErrorCategory -Message $ErrorMessage
            message = $ErrorMessage
        }
    }
}

function Read-HttpRequest {
    param([System.Net.Sockets.TcpClient]$Client)

    $stream = $Client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $parts = $requestLine.Split(' ')
    if ($parts.Count -lt 2) {
        return $null
    }

    $method = $parts[0].ToUpperInvariant()
    $target = $parts[1]

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') { break }
        $idx = $line.IndexOf(':')
        if ($idx -gt 0) {
            $key = $line.Substring(0, $idx).Trim().ToLowerInvariant()
            $value = $line.Substring($idx + 1).Trim()
            $headers[$key] = $value
        }
    }

    $body = ''
    $contentLength = 0
    if ($headers.ContainsKey('content-length')) {
        [void][int]::TryParse($headers['content-length'], [ref]$contentLength)
    }

    if ($contentLength -gt 0) {
        $buffer = New-Object char[] $contentLength
        $read = $reader.ReadBlock($buffer, 0, $contentLength)
        $body = -join $buffer[0..($read - 1)]
    }

    $uriObj = [System.Uri]("http://localhost$target")

    return [pscustomobject]@{
        Method = $method
        Target = $target
        Path = $uriObj.AbsolutePath.TrimEnd('/')
        Query = $uriObj.Query.TrimStart('?')
        Headers = $headers
        Body = $body
        Stream = $stream
    }
}

function Parse-QueryString {
    param([string]$Query)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Query)) { return $result }
    foreach ($pair in $Query -split '&') {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $kv = $pair -split '=', 2
        $k = [System.Uri]::UnescapeDataString($kv[0])
        $v = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { '' }
        $result[$k] = $v
    }
    return $result
}

function Parse-JsonBody {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @{} }
    return ConvertFrom-Json -InputObject $Body -AsHashtable
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)
$listener.Start()
Write-HostLog ("Repo Management API host started on http://{0}:{1}" -f $BindAddress, $Port)

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $req = Read-HttpRequest -Client $client
            if ($null -eq $req) {
                $client.Close()
                continue
            }

            $path = if ([string]::IsNullOrWhiteSpace($req.Path)) { '/' } else { $req.Path }
            $correlationId = if ($req.Headers.ContainsKey('x-correlation-id') -and $req.Headers['x-correlation-id']) { $req.Headers['x-correlation-id'] } else { [guid]::NewGuid().ToString('n') }
            $requestStart = Get-Date

            if ($req.Method -eq 'OPTIONS') {
                Add-MetricCounter -Name 'api_requests_total'
                Send-HttpJson -Stream $req.Stream -StatusCode 204 -StatusText 'No Content' -Payload @{} -CorrelationId $correlationId
                $client.Close()
                continue
            }

            switch ("$($req.Method) $path") {
                'GET /health/live' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ status = 'ok'; service = 'repo-management-api'; time = (Get-Date).ToString('o') }
                }
                'GET /health/ready' {
                    $checks = @{
                        adaptersPath = Test-Path -LiteralPath $adapterRoot
                        statusAdapter = Test-Path -LiteralPath (Join-Path $adapterRoot 'Status.Adapter.ps1')
                        reconcileAdapter = Test-Path -LiteralPath (Join-Path $adapterRoot 'Reconcile.Adapter.ps1')
                        docreviewAdapter = Test-Path -LiteralPath (Join-Path $adapterRoot 'DocReview.Adapter.ps1')
                    }
                    $healthy = -not ($checks.Values -contains $false)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($healthy) { 200 } else { 503 }) -CorrelationId $correlationId -Payload @{ status = if ($healthy) { 'ready' } else { 'degraded' }; checks = $checks }
                }
                'GET /health/dependencies' {
                    $depChecks = [ordered]@{
                        git = [bool](Get-Command git -ErrorAction SilentlyContinue)
                        gh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
                        adapterRootExists = Test-Path -LiteralPath $adapterRoot
                        workspaceRootExists = Test-Path -LiteralPath $WorkspaceRoot
                        outputWritable = $false
                    }

                    try {
                        $testOutputRoot = Join-Path $WorkspaceRoot 'backend\modules\output'
                        $null = New-Item -ItemType Directory -Path $testOutputRoot -Force -ErrorAction Stop
                        $probe = Join-Path $testOutputRoot '.health-probe'
                        Set-Content -LiteralPath $probe -Value 'ok' -Encoding UTF8
                        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
                        $depChecks.outputWritable = $true
                    }
                    catch {
                        $depChecks.outputWritable = $false
                    }

                    $healthy = -not ($depChecks.Values -contains $false)
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($healthy) { 200 } else { 503 }) -CorrelationId $correlationId -Payload @{
                        status = if ($healthy) { 'healthy' } else { 'degraded' }
                        dependencies = $depChecks
                    }
                }
                'GET /metrics' {
                    Add-MetricCounter -Name 'api_requests_total'
                    $snapshot = Get-MetricsSnapshot
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload $snapshot
                }
                'GET /api/status' {
                    $q = Parse-QueryString -Query $req.Query
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { @($WorkspaceRoot) }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { 2 }
                    $includeNonGit = if ($q.ContainsKey('includeNonGitFolders')) { Parse-Bool -Value $q.includeNonGitFolders -Default $false } else { $false }

                    $result = Get-StatusAdapterResult -LocalRoots $localRoots -MaxDepth $maxDepth -IncludeNonGitFolders:$includeNonGit -LogPath $LogPath
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'POST /api/reconcile' {
                    $body = Parse-JsonBody -Body $req.Body
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { @($WorkspaceRoot) }
                    $ownerType = if ($body.ContainsKey('ownerType') -and $body.ownerType) { [string]$body.ownerType } else { 'Auto' }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { 3 }
                    $includeNonGit = if ($body.ContainsKey('includeNonGitFolders')) { [bool]$body.includeNonGitFolders } else { $true }
                    $outDir = if ($body.ContainsKey('outDir')) { [string]$body.outDir } else { '' }
                    $githubOwner = if ($body.ContainsKey('githubOwner')) { [string]$body.githubOwner } else { '' }

                    $result = Invoke-ReconcileAdapter -LocalRoots $localRoots -GitHubOwner $githubOwner -OwnerType $ownerType -OutDir $outDir -MaxDepth $maxDepth -IncludeNonGitFolders:$includeNonGit -LogPath $LogPath
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'POST /api/docreview/run' {
                    $body = Parse-JsonBody -Body $req.Body
                    $rootPath = if ($body.ContainsKey('rootPath') -and $body.rootPath) { [string]$body.rootPath } else { $WorkspaceRoot }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { 2 }
                    $outDir = if ($body.ContainsKey('outDir')) { [string]$body.outDir } else { '' }
                    $targetRepo = if ($body.ContainsKey('targetRepo')) { [string]$body.targetRepo } else { '' }
                    $generateQueue = if ($body.ContainsKey('generateQueue')) { [bool]$body.generateQueue } else { $true }
                    $generateBatchPlan = if ($body.ContainsKey('generateBatchPlan')) { [bool]$body.generateBatchPlan } else { $false }

                    $result = Invoke-DocReviewAdapter -RootPath $rootPath -MaxDepth $maxDepth -OutDir $outDir -TargetRepo $targetRepo -GenerateQueue:$generateQueue -GenerateBatchPlan:$generateBatchPlan -LogPath $LogPath
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'GET /api/report/artifacts' {
                    $outputRoot = Join-Path $WorkspaceRoot 'backend\modules\output'
                    $files = @()
                    if (Test-Path -LiteralPath $outputRoot) {
                        $files = Get-ChildItem -Path $outputRoot -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 200 | ForEach-Object {
                            [pscustomobject]@{
                                name = $_.Name
                                path = $_.FullName
                                sizeBytes = $_.Length
                                lastWriteTime = $_.LastWriteTime.ToString('o')
                            }
                        }
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        artifacts = $files
                        outputRoot = $outputRoot
                    }
                }
                'GET /api/settings' {
                    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
                    $config = @{}
                    if (Test-Path -LiteralPath $configPath) {
                        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $config
                    }
                }
                'POST /api/update' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 410 -StatusText 'Gone' -CorrelationId $correlationId -Payload @{
                        success = $false
                        deprecated = $true
                        replacement = '/api/status and /api/reconcile'
                        message = 'Legacy update operation is deprecated in the consolidated host.'
                    }
                }
                'POST /api/sync' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 410 -StatusText 'Gone' -CorrelationId $correlationId -Payload @{
                        success = $false
                        deprecated = $true
                        replacement = '/api/status and /api/reconcile'
                        message = 'Legacy sync operation is deprecated in the consolidated host.'
                    }
                }
                default {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{ error = 'Not Found'; method = $req.Method; path = $path }
                }
            }
        }
        catch {
            if ($client.Connected) {
                $stream = $client.GetStream()
                $requestCorrelationId = [guid]::NewGuid().ToString('n')
                Send-ErrorJson -Stream $stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $requestCorrelationId -Operation 'api.request'
            }
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
    Write-HostLog 'Repo Management API host stopped'
}

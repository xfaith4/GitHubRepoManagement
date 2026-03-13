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

$script:StatusCacheMemory = @{}
$script:StatusCacheDefaultTtlSeconds = 120

$script:RoadmapCacheMemory = @{}
$script:RoadmapCacheDefaultTtlSeconds = 300

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
    return ConvertFrom-JsonCompat -Json $Body
}

function ConvertTo-HashtableRecursive {
    param([Parameter(Mandatory = $true)][object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ConvertTo-HashtableRecursive -InputObject $item
        }
        return ,$list
    }

    if ($InputObject -is [pscustomobject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-HashtableRecursive -InputObject $prop.Value
        }
        return $hash
    }

    return $InputObject
}

function ConvertFrom-JsonCompat {
    param([Parameter(Mandatory = $true)][string]$Json)

    $obj = ConvertFrom-Json -InputObject $Json
    return ConvertTo-HashtableRecursive -InputObject $obj
}

function Get-HostSettings {
    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @{
            inventory = @{ localRoots = @($WorkspaceRoot); maxDepth = 3; includeNonGitFolders = $false }
            reconcile = @{ ownerType = 'Auto'; gitHubOwner = '' }
            retention = @{ days = 30 }
            secrets = @{ gitHubTokenEnvVar = 'GITHUB_TOKEN' }
        }
    }

    return ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
}

function Get-StatusCacheTtlSeconds {
    param([hashtable]$Settings)

    $ttl = $script:StatusCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('inventory') -and
        $Settings.inventory -is [System.Collections.IDictionary] -and
        $Settings.inventory.ContainsKey('statusCacheTtlSeconds') -and
        $Settings.inventory.statusCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.inventory.statusCacheTtlSeconds
        if ($candidate -ge 0) {
            $ttl = $candidate
        }
    }

    return $ttl
}

function Get-StatusCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'status-cache.json'
}

function Get-StatusCacheKey {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,
        [Parameter(Mandatory = $true)]
        [bool]$IncludeNonGitFolders
    )

    $normalizedRoots = @(
        $LocalRoots |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Sort-Object
    )

    return '{0}|depth:{1}|nonGit:{2}' -f ($normalizedRoots -join ';'), $MaxDepth, $IncludeNonGitFolders
}

function Get-StatusCacheMeta {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Hit,
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [int]$TtlSeconds,
        [Parameter()]
        [double]$AgeSeconds = 0,
        [Parameter(Mandatory = $true)]
        [bool]$BypassRequested,
        [Parameter()]
        [string]$CachedAt = ''
    )

    return @{
        hit = $Hit
        source = $Source
        ageSeconds = [math]::Round([double]$AgeSeconds, 3)
        ttlSeconds = $TtlSeconds
        bypassRequested = $BypassRequested
        cachedAt = $CachedAt
    }
}

function Add-StatusCacheMeta {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheMeta
    )

    if ($Result -is [System.Collections.IDictionary]) {
        if (-not $Result.ContainsKey('meta') -or $null -eq $Result.meta) {
            $Result.meta = @{}
        }
        if (-not ($Result.meta -is [System.Collections.IDictionary])) {
            $Result.meta = @{ raw = $Result.meta }
        }
        $Result.meta.statusCache = $CacheMeta
        return $Result
    }

    if (-not ($Result.PSObject.Properties.Name -contains 'meta') -or $null -eq $Result.meta) {
        $Result | Add-Member -NotePropertyName meta -NotePropertyValue @{} -Force
    }
    elseif (-not ($Result.meta -is [System.Collections.IDictionary])) {
        $Result.meta = @{ raw = $Result.meta }
    }

    $Result.meta.statusCache = $CacheMeta
    return $Result
}

function Get-StatusFromCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [int]$TtlSeconds
    )

    $nowUtc = (Get-Date).ToUniversalTime()

    if ($script:StatusCacheMemory.ContainsKey($Key)) {
        $memoryEntry = $script:StatusCacheMemory[$Key]
        $ageSeconds = (($nowUtc) - [datetime]$memoryEntry.CreatedAtUtc).TotalSeconds
        if ($ageSeconds -le $TtlSeconds) {
            return [pscustomobject]@{
                hit = $true
                source = 'memory'
                ageSeconds = $ageSeconds
                cachedAt = ([datetime]$memoryEntry.CreatedAtUtc).ToString('o')
                response = $memoryEntry.Response
            }
        }
    }

    $cacheFile = Get-StatusCacheFilePath
    if (-not (Test-Path -LiteralPath $cacheFile)) {
        return [pscustomobject]@{ hit = $false }
    }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{ hit = $false }
        }
        $diskEntry = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $diskEntry -or -not $diskEntry.ContainsKey('key') -or -not $diskEntry.ContainsKey('createdAtUtc') -or -not $diskEntry.ContainsKey('response')) {
            return [pscustomobject]@{ hit = $false }
        }
        if ([string]$diskEntry.key -ne $Key) {
            return [pscustomobject]@{ hit = $false }
        }

        $createdAtUtc = [datetime]$diskEntry.createdAtUtc
        $ageSeconds = (($nowUtc) - $createdAtUtc).TotalSeconds
        if ($ageSeconds -gt $TtlSeconds) {
            return [pscustomobject]@{ hit = $false }
        }

        $script:StatusCacheMemory[$Key] = @{
            CreatedAtUtc = $createdAtUtc
            Response = $diskEntry.response
        }

        return [pscustomobject]@{
            hit = $true
            source = 'disk'
            ageSeconds = $ageSeconds
            cachedAt = $createdAtUtc.ToString('o')
            response = $diskEntry.response
        }
    }
    catch {
        return [pscustomobject]@{ hit = $false }
    }
}

function Save-StatusCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    $nowUtc = (Get-Date).ToUniversalTime()
    $entry = @{
        key = $Key
        createdAtUtc = $nowUtc.ToString('o')
        response = $Response
    }

    $script:StatusCacheMemory[$Key] = @{
        CreatedAtUtc = $nowUtc
        Response = $Response
    }

    try {
        $cacheFile = Get-StatusCacheFilePath
        ($entry | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch {
        Write-HostLog ("Status cache write skipped: {0}" -f $_.Exception.Message)
    }
}

function Clear-StatusCache {
    $script:StatusCacheMemory = @{}
    try {
        $cacheFile = Get-StatusCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) {
            Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-HostLog ("Status cache clear skipped: {0}" -f $_.Exception.Message)
    }
}

function Get-ConfiguredGitHubToken {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,
        [Parameter()]
        [string]$RequestToken
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestToken)) {
        return $RequestToken
    }

    $envVarName = if ($Settings.ContainsKey('secrets') -and $Settings.secrets.ContainsKey('gitHubTokenEnvVar') -and $Settings.secrets.gitHubTokenEnvVar) {
        [string]$Settings.secrets.gitHubTokenEnvVar
    }
    else {
        'GITHUB_TOKEN'
    }

    $envToken = [Environment]::GetEnvironmentVariable($envVarName)
    if (-not [string]::IsNullOrWhiteSpace($envToken)) {
        return $envToken
    }

    if ($Settings.ContainsKey('secrets') -and $Settings.secrets.ContainsKey('githubToken') -and $Settings.secrets.githubToken) {
        return [string]$Settings.secrets.githubToken
    }

    return ''
}

function Get-GitHubReposViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Token,
        [Parameter()]
        [int]$RepoLimit = 50
    )

    $headers = @{
        Authorization = "Bearer $Token"
        'User-Agent' = 'GitHubRepoManagement'
        Accept = 'application/vnd.github+json'
    }

    $uri = "https://api.github.com/users/$Owner/repos?per_page=100&sort=updated&type=all"
    $reposRaw = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    $repos = @($reposRaw | Select-Object -First $RepoLimit | ForEach-Object {
        [pscustomobject]@{
            name = $_.name
            branch = if ($_.default_branch) { $_.default_branch } else { 'main' }
            status = 'clean'
            lastCommitDate = $_.updated_at
            uncommittedChanges = 0
            isArchived = [bool]$_.archived
            isStale = $false
            localAhead = 0
            remoteAhead = 0
            openPrCount = 0
            htmlUrl = $_.html_url
            owner = $Owner
            visibility = if ([bool]$_.private) { 'private' } else { 'public' }
            language = $_.language
            topics = if ($_.topics) { @($_.topics) } else { @() }
        }
    })

    return [pscustomobject]@{
        source = 'github'
        username = $Owner
        totalRepos = @($repos).Count
        fetchedRepos = @($repos).Count
        repos = $repos
        rateLimit = $null
    }
}

function Invoke-GitOperation {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pull', 'sync')]
        [string]$OperationType,
        [Parameter()]
        [string[]]$RepoNames,
        [Parameter()]
        [string[]]$RepoPaths
    )

    $status = Get-StatusAdapterResult -LocalRoots @($WorkspaceRoot) -MaxDepth 4 -IncludeNonGitFolders:$false -LogPath $LogPath
    if (-not $status.success) {
        throw "Unable to enumerate repositories for ${OperationType}: $($status.error)"
    }

    $repos = @($status.data.repos)
    if ($RepoPaths -and $RepoPaths.Count -gt 0) {
        $pathSet = @{}
        foreach ($p in $RepoPaths) {
            if (-not [string]::IsNullOrWhiteSpace([string]$p)) {
                $pathSet[[string]$p] = $true
            }
        }
        $repos = @($repos | Where-Object { $pathSet.ContainsKey([string]$_.path) })
    }
    elseif ($RepoNames -and $RepoNames.Count -gt 0) {
        $nameSet = @{}
        foreach ($n in $RepoNames) { $nameSet[$n] = $true }
        $repos = @($repos | Where-Object { $nameSet.ContainsKey($_.name) })
    }

    $results = @()
    foreach ($repo in $repos) {
        $repoPath = [string]$repo.path
        $name = [string]$repo.name
        try {
            if ($OperationType -eq 'pull') {
                $output = (& git -C $repoPath pull --ff-only 2>&1) | Out-String
            }
            else {
                $output = (& git -C $repoPath fetch --all --prune 2>&1) | Out-String
            }
            $results += [pscustomobject]@{
                name = $name
                path = $repoPath
                success = $true
                output = $output.Trim()
            }
        }
        catch {
            $results += [pscustomobject]@{
                name = $name
                path = $repoPath
                success = $false
                error = $_.Exception.Message
            }
        }
    }

    return [pscustomobject]@{
        operation = $OperationType
        total = @($results).Count
        succeeded = @($results | Where-Object { $_.success }).Count
        failed = @($results | Where-Object { -not $_.success }).Count
        results = $results
    }
}

function Get-RoadmapCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'roadmap-index-cache.json'
}

function Get-RoadmapCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:RoadmapCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('roadmap') -and
        $Settings.roadmap -is [System.Collections.IDictionary] -and
        $Settings.roadmap.ContainsKey('scanCacheTtlSeconds') -and
        $Settings.roadmap.scanCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.roadmap.scanCacheTtlSeconds
        if ($candidate -ge 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-RoadmapFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-global'

    if ($script:RoadmapCacheMemory.ContainsKey($key)) {
        $entry = $script:RoadmapCacheMemory[$key]
        $age = (($nowUtc) - [datetime]$entry.CreatedAtUtc).TotalSeconds
        if ($age -le $TtlSeconds) {
            return [pscustomobject]@{ hit = $true; source = 'memory'; ageSeconds = $age; cachedAt = ([datetime]$entry.CreatedAtUtc).ToString('o'); entries = $entry.Entries; scannedAt = $entry.ScannedAt }
        }
    }

    $cacheFile = Get-RoadmapCacheFilePath
    if (-not (Test-Path -LiteralPath $cacheFile)) { return [pscustomobject]@{ hit = $false } }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ hit = $false } }
        $disk = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $disk -or -not $disk.ContainsKey('createdAtUtc')) { return [pscustomobject]@{ hit = $false } }
        $created = [datetime]$disk.createdAtUtc
        $age = (($nowUtc) - $created).TotalSeconds
        if ($age -gt $TtlSeconds) { return [pscustomobject]@{ hit = $false } }
        $script:RoadmapCacheMemory[$key] = @{ CreatedAtUtc = $created; Entries = $disk.entries; ScannedAt = [string]$disk.scannedAt }
        return [pscustomobject]@{ hit = $true; source = 'disk'; ageSeconds = $age; cachedAt = $created.ToString('o'); entries = $disk.entries; scannedAt = [string]$disk.scannedAt }
    }
    catch { return [pscustomobject]@{ hit = $false } }
}

function Save-RoadmapCache {
    param([array]$Entries, [string]$ScannedAt)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-global'
    $script:RoadmapCacheMemory[$key] = @{ CreatedAtUtc = $nowUtc; Entries = $Entries; ScannedAt = $ScannedAt }
    try {
        $cacheFile = Get-RoadmapCacheFilePath
        (@{ createdAtUtc = $nowUtc.ToString('o'); scannedAt = $ScannedAt; entries = $Entries } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch { Write-HostLog ("Roadmap cache write skipped: {0}" -f $_.Exception.Message) }
}

function Clear-RoadmapCache {
    $script:RoadmapCacheMemory = @{}
    try {
        $cacheFile = Get-RoadmapCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-HostLog ("Roadmap cache clear skipped: {0}" -f $_.Exception.Message) }
}

function Invoke-RoadmapScan {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter()]
        [int]$MaxDepth = 3
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($root in $LocalRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            $files = Get-ChildItem -Path $root -Recurse -Depth $MaxDepth -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -imatch '^ROADMAP(\..+)?$' }
            foreach ($file in $files) {
                $repoName = $file.Directory.Name
                $repoPath = $file.DirectoryName
                $dir = $file.Directory
                while ($null -ne $dir) {
                    if (Test-Path (Join-Path $dir.FullName '.git')) {
                        $repoName = $dir.Name
                        $repoPath = $dir.FullName
                        break
                    }
                    $dir = $dir.Parent
                }
                $entries.Add([pscustomobject]@{
                    repoName = $repoName
                    repoPath = $repoPath
                    roadmapPath = $file.FullName
                    lastModified = $file.LastWriteTime.ToString('o')
                    sizeBytes = [long]$file.Length
                })
            }
        }
        catch { Write-HostLog ("[TRACE] roadmap.scan root_error root={0} error={1}" -f $root, $_.Exception.Message) }
    }
    return @($entries)
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

            if ($req.Method -eq 'GET' -and $path -like '/api/artifacts/*') {
                $repoName = [System.Uri]::UnescapeDataString($path.Substring('/api/artifacts/'.Length))
                $outputRoot = Join-Path $WorkspaceRoot 'backend\modules\output'
                $files = @()
                if (Test-Path -LiteralPath $outputRoot) {
                    $files = Get-ChildItem -Path $outputRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                        $_.Name -like "*$repoName*" -or $_.FullName -like "*$repoName*"
                    } | Sort-Object LastWriteTime -Descending | Select-Object -First 200 | ForEach-Object {
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
                    repoName = $repoName
                    artifacts = $files
                }
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
                    $settings = Get-HostSettings
                    $defaultRoots = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('localRoots') -and $settings.inventory.localRoots) { @($settings.inventory.localRoots) } else { @($WorkspaceRoot) }
                    $defaultMaxDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 2 }
                    $defaultIncludeNonGit = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('includeNonGitFolders')) { [bool]$settings.inventory.includeNonGitFolders } else { $false }

                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultMaxDepth }
                    $includeNonGit = if ($q.ContainsKey('includeNonGitFolders')) { Parse-Bool -Value $q.includeNonGitFolders -Default $defaultIncludeNonGit } else { $defaultIncludeNonGit }
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $ttlSeconds = Get-StatusCacheTtlSeconds -Settings $settings
                    $cacheKey = Get-StatusCacheKey -LocalRoots $localRoots -MaxDepth $maxDepth -IncludeNonGitFolders $includeNonGit

                    $result = $null
                    if ((-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-StatusFromCache -Key $cacheKey -TtlSeconds $ttlSeconds
                        if ($cacheHit.hit) {
                            $result = Add-StatusCacheMeta -Result $cacheHit.response -CacheMeta (Get-StatusCacheMeta -Hit $true -Source $cacheHit.source -TtlSeconds $ttlSeconds -AgeSeconds $cacheHit.ageSeconds -BypassRequested:$false -CachedAt $cacheHit.cachedAt)
                        }
                    }

                    if ($null -eq $result) {
                        $scanCachedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $result = Get-StatusAdapterResult -LocalRoots $localRoots -MaxDepth $maxDepth -IncludeNonGitFolders:$includeNonGit -LogPath $LogPath
                        $result = Add-StatusCacheMeta -Result $result -CacheMeta (Get-StatusCacheMeta -Hit $false -Source 'fresh-scan' -TtlSeconds $ttlSeconds -AgeSeconds 0 -BypassRequested:$refresh -CachedAt $scanCachedAt)
                        if ($result.success -and ($ttlSeconds -gt 0)) {
                            Save-StatusCache -Key $cacheKey -Response $result
                        }
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'POST /api/reconcile' {
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('localRoots') -and $settings.inventory.localRoots) { @($settings.inventory.localRoots) } else { @($WorkspaceRoot) }
                    $defaultOwnerType = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('ownerType') -and $settings.reconcile.ownerType) { [string]$settings.reconcile.ownerType } else { 'Auto' }
                    $defaultGitHubOwner = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) { [string]$settings.reconcile.gitHubOwner } else { '' }
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $defaultIncludeNonGit = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('includeNonGitFolders')) { [bool]$settings.inventory.includeNonGitFolders } else { $true }

                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $ownerType = if ($body.ContainsKey('ownerType') -and $body.ownerType) { [string]$body.ownerType } else { $defaultOwnerType }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $includeNonGit = if ($body.ContainsKey('includeNonGitFolders')) { [bool]$body.includeNonGitFolders } else { $defaultIncludeNonGit }
                    $outDir = if ($body.ContainsKey('outDir')) { [string]$body.outDir } else { '' }
                    $githubOwner = if ($body.ContainsKey('githubOwner')) { [string]$body.githubOwner } else { $defaultGitHubOwner }

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
                        $config = ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $config
                    }
                }
                'POST /api/settings' {
                    $body = Parse-JsonBody -Body $req.Body
                    $configPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
                    $existing = @{}
                    if (Test-Path -LiteralPath $configPath) {
                        $existing = ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $configPath -Raw)
                    }

                    if (-not $existing.ContainsKey('inventory')) { $existing.inventory = @{} }
                    if (-not $existing.ContainsKey('retention')) { $existing.retention = @{} }
                    if (-not $existing.ContainsKey('docReview')) { $existing.docReview = @{} }

                    if ($body.ContainsKey('basePath') -and $body.basePath) {
                        $existing.inventory.localRoots = @([string]$body.basePath)
                    }
                    if ($body.ContainsKey('scanDepth')) {
                        $existing.inventory.maxDepth = [int]$body.scanDepth
                    }
                    if ($body.ContainsKey('daysInactive')) {
                        $existing.retention.days = [int]$body.daysInactive
                    }
                    if ($body.ContainsKey('githubUser')) {
                        if (-not $existing.ContainsKey('reconcile')) { $existing.reconcile = @{} }
                        $existing.reconcile.gitHubOwner = [string]$body.githubUser
                    }
                    if ($body.ContainsKey('githubToken')) {
                        if (-not $existing.ContainsKey('secrets')) { $existing.secrets = @{} }
                        if ([string]::IsNullOrWhiteSpace([string]$body.githubToken)) {
                            $existing.secrets.Remove('githubToken')
                        }
                        else {
                            $existing.secrets.githubToken = [string]$body.githubToken
                        }
                    }
                    if ($body.ContainsKey('gitHubTokenEnvVar') -and -not [string]::IsNullOrWhiteSpace([string]$body.gitHubTokenEnvVar)) {
                        if (-not $existing.ContainsKey('secrets')) { $existing.secrets = @{} }
                        $existing.secrets.gitHubTokenEnvVar = [string]$body.gitHubTokenEnvVar
                    }

                    ($existing | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $configPath -Encoding UTF8
                    Clear-StatusCache

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $existing
                    }
                }
                'POST /api/init' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 202 -CorrelationId $correlationId -Payload @{
                        success = $true
                        accepted = $true
                        message = 'Clone workflow placeholder accepted. Use existing local repo discovery and reconciliation workflows.'
                    }
                }
                'POST /api/update' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repoNames = if ($body.ContainsKey('repoNames') -and $body.repoNames) { @($body.repoNames) } else { @() }
                    $repoPaths = if ($body.ContainsKey('repoPaths') -and $body.repoPaths) { @($body.repoPaths) } else { @() }
                    $result = Invoke-GitOperation -OperationType 'pull' -RepoNames $repoNames -RepoPaths $repoPaths
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
                    }
                }
                'POST /api/sync' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repoNames = if ($body.ContainsKey('repoNames') -and $body.repoNames) { @($body.repoNames) } else { @() }
                    $repoPaths = if ($body.ContainsKey('repoPaths') -and $body.repoPaths) { @($body.repoPaths) } else { @() }
                    $result = Invoke-GitOperation -OperationType 'sync' -RepoNames $repoNames -RepoPaths $repoPaths
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
                    }
                }
                'POST /api/export' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 202 -CorrelationId $correlationId -Payload @{
                        success = $true
                        accepted = $true
                        message = 'Client-side export supported. Artifact index available at /api/report/artifacts.'
                    }
                }
                'POST /api/archive' {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 202 -CorrelationId $correlationId -Payload @{
                        success = $true
                        accepted = $true
                        message = 'Archive workflow is currently a planned operation in this host.'
                    }
                }
                'POST /api/github/status' {
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $owner = if ($body.ContainsKey('githubUser') -and $body.githubUser) {
                        [string]$body.githubUser
                    }
                    elseif ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) {
                        [string]$settings.reconcile.gitHubOwner
                    }
                    else {
                        ''
                    }
                    $limit = if ($body.ContainsKey('repoLimit') -and $body.repoLimit) { [int]$body.repoLimit } else { 50 }
                    if ([string]::IsNullOrWhiteSpace($owner)) {
                        throw 'githubUser is required for /api/github/status'
                    }
                    $requestToken = if ($body.ContainsKey('apiKey') -and $body.apiKey) { [string]$body.apiKey } else { '' }
                    $token = Get-ConfiguredGitHubToken -Settings $settings -RequestToken $requestToken

                    if (-not [string]::IsNullOrWhiteSpace($token)) {
                        $apiResult = Get-GitHubReposViaApi -Owner $owner -Token $token -RepoLimit $limit
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload $apiResult
                        break
                    }

                    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
                        throw 'GitHub token not configured and GitHub CLI (gh) is not available.'
                    }

                    $json = (& gh repo list $owner --limit $limit --json name,nameWithOwner,url,isArchived,isPrivate,defaultBranchRef,updatedAt 2>&1) | Out-String
                    $reposRaw = $json | ConvertFrom-Json
                    $repos = @($reposRaw | ForEach-Object {
                        [pscustomobject]@{
                            name = $_.name
                            branch = if ($_.defaultBranchRef) { $_.defaultBranchRef.name } else { 'main' }
                            status = 'clean'
                            lastCommitDate = $_.updatedAt
                            uncommittedChanges = 0
                            isArchived = [bool]$_.isArchived
                            isStale = $false
                            localAhead = 0
                            remoteAhead = 0
                            openPrCount = 0
                            htmlUrl = $_.url
                            owner = $owner
                            visibility = if ([bool]$_.isPrivate) { 'private' } else { 'public' }
                        }
                    })

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        source = 'github'
                        username = $owner
                        totalRepos = @($repos).Count
                        fetchedRepos = @($repos).Count
                        repos = $repos
                        rateLimit = $null
                    }
                }
                'GET /api/status/cache' {
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-StatusCacheTtlSeconds -Settings $settings
                    $cacheFile = Get-StatusCacheFilePath
                    $memoryKeys = @($script:StatusCacheMemory.Keys)
                    $diskInfo = $null
                    if (Test-Path -LiteralPath $cacheFile) {
                        try {
                            $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
                            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                                $diskEntry = ConvertFrom-JsonCompat -Json $raw
                                if ($diskEntry -and $diskEntry.ContainsKey('createdAtUtc')) {
                                    $nowUtc = (Get-Date).ToUniversalTime()
                                    $createdAt = [datetime]$diskEntry.createdAtUtc
                                    $diskInfo = @{
                                        key = [string]$diskEntry.key
                                        createdAtUtc = $diskEntry.createdAtUtc
                                        ageSeconds = [math]::Round(($nowUtc - $createdAt).TotalSeconds, 1)
                                        expired = (($nowUtc - $createdAt).TotalSeconds -gt $ttlSeconds)
                                    }
                                }
                            }
                        } catch { }
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        ttlSeconds = $ttlSeconds
                        memoryEntries = $memoryKeys.Count
                        memoryKeys = $memoryKeys
                        disk = $diskInfo
                    }
                }
                'POST /api/status/cache/clear' {
                    Clear-StatusCache
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        message = 'Status cache cleared. Next GET /api/status will perform a fresh scan.'
                    }
                }
                'GET /api/roadmap/index' {
                    Write-HostLog ("[TRACE] roadmap.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $defaultRoots = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('localRoots') -and $settings.inventory.localRoots) { @($settings.inventory.localRoots) } else { @($WorkspaceRoot) }
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }

                    $cacheHit = $null
                    if ((-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                    }

                    if ($null -ne $cacheHit -and $cacheHit.hit) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.index correlationId={0} done source=cache ageSeconds={1} durationMs={2}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1), [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $cacheHit.entries
                                scannedAt = $cacheHit.scannedAt
                                count = @($cacheHit.entries).Count
                                cacheSource = $cacheHit.source
                                cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                            }
                        }
                    } else {
                        $scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $entries = Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth
                        Save-RoadmapCache -Entries $entries -ScannedAt $scannedAt
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.index correlationId={0} done source=fresh-scan count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $entries
                                scannedAt = $scannedAt
                                count = @($entries).Count
                                cacheSource = 'fresh-scan'
                                cacheAgeSeconds = 0
                            }
                        }
                    }
                }
                'GET /api/roadmap/content' {
                    Write-HostLog ("[TRACE] roadmap.content correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $repoName = if ($q.ContainsKey('repo') -and $q.repo) { [System.Uri]::UnescapeDataString([string]$q.repo) } else { '' }
                    $requestedPath = if ($q.ContainsKey('path') -and $q.path) { [System.Uri]::UnescapeDataString([string]$q.path) } else { '' }

                    $targetPath = $requestedPath
                    if ([string]::IsNullOrWhiteSpace($targetPath) -and -not [string]::IsNullOrWhiteSpace($repoName)) {
                        $settings = Get-HostSettings
                        $defaultRoots = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('localRoots') -and $settings.inventory.localRoots) { @($settings.inventory.localRoots) } else { @($WorkspaceRoot) }
                        $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                        $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                        $cached = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
                        $indexEntries = if ($cached.hit) { @($cached.entries) } else { @(Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth) }
                        $match = $indexEntries | Where-Object { [string]$_.repoName -eq $repoName } | Select-Object -First 1
                        if ($null -ne $match) { $targetPath = [string]$match.roadmapPath }
                    }

                    if ([string]::IsNullOrWhiteSpace($targetPath) -or -not (Test-Path -LiteralPath $targetPath)) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error = @{ category = 'validation'; message = 'ROADMAP file not found for the specified repo or path.' }
                        }
                    } else {
                        $fileInfo = Get-Item -LiteralPath $targetPath
                        $maxBytes = 512 * 1024
                        $content = if ($fileInfo.Length -le $maxBytes) {
                            Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 -ErrorAction Stop
                        } else {
                            $stream = [System.IO.File]::OpenRead($targetPath)
                            $buf = New-Object byte[] $maxBytes
                            $null = $stream.Read($buf, 0, $maxBytes)
                            $stream.Close()
                            [System.Text.Encoding]::UTF8.GetString($buf) + "`n`n[... file truncated at 512 KB ...]"
                        }
                        $inferredRepoName = if (-not [string]::IsNullOrWhiteSpace($repoName)) { $repoName } else { $fileInfo.Directory.Name }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.content correlationId={0} done repo={1} sizeBytes={2} durationMs={3}" -f $correlationId, $inferredRepoName, $fileInfo.Length, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                repoName = $inferredRepoName
                                content = $content
                                path = $targetPath
                                sizeBytes = [long]$fileInfo.Length
                                lastModified = $fileInfo.LastWriteTime.ToString('o')
                            }
                        }
                    }
                }
                'POST /api/roadmap/scan' {
                    Write-HostLog ("[TRACE] roadmap.scan correlationId={0} start" -f $correlationId)
                    $settings = Get-HostSettings
                    $defaultRoots = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('localRoots') -and $settings.inventory.localRoots) { @($settings.inventory.localRoots) } else { @($WorkspaceRoot) }
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-RoadmapScan -LocalRoots $defaultRoots -MaxDepth $defaultDepth
                    Save-RoadmapCache -Entries $entries -ScannedAt $scannedAt
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] roadmap.scan correlationId={0} done count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            entries = $entries
                            scannedAt = $scannedAt
                            count = @($entries).Count
                            cacheSource = 'fresh-scan'
                            cacheAgeSeconds = 0
                        }
                    }
                }
                'GET /api/roadmap/cache' {
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $cacheFile = Get-RoadmapCacheFilePath
                    $diskInfo = $null
                    if (Test-Path -LiteralPath $cacheFile) {
                        try {
                            $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
                            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                                $disk = ConvertFrom-JsonCompat -Json $raw
                                if ($disk -and $disk.ContainsKey('createdAtUtc')) {
                                    $nowUtc = (Get-Date).ToUniversalTime()
                                    $created = [datetime]$disk.createdAtUtc
                                    $diskInfo = @{
                                        scannedAt = [string]$disk.scannedAt
                                        createdAtUtc = $disk.createdAtUtc
                                        ageSeconds = [math]::Round(($nowUtc - $created).TotalSeconds, 1)
                                        expired = (($nowUtc - $created).TotalSeconds -gt $ttlSeconds)
                                        entryCount = @($disk.entries).Count
                                    }
                                }
                            }
                        } catch { }
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        ttlSeconds = $ttlSeconds
                        memoryEntries = $script:RoadmapCacheMemory.Count
                        disk = $diskInfo
                    }
                }
                'POST /api/roadmap/cache/clear' {
                    Clear-RoadmapCache
                    Add-MetricCounter -Name 'api_requests_total'
                    Write-HostLog ("[TRACE] roadmap.cache.clear correlationId={0}" -f $correlationId)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        message = 'Roadmap cache cleared. Next GET /api/roadmap/index will perform a fresh scan.'
                    }
                }
                default {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{ error = 'Not Found'; method = $req.Method; path = $path }
                }            }
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

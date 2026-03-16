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
$roadmapModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\roadmap'
$docAuditModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\docaudit'
$executionModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\execution'
. (Join-Path $commonRoot 'Metrics.ps1')
. (Join-Path $adapterRoot 'Status.Adapter.ps1')
. (Join-Path $adapterRoot 'Reconcile.Adapter.ps1')
. (Join-Path $adapterRoot 'DocReview.Adapter.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Parser.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Auditor.ps1')
. (Join-Path $roadmapModuleRoot 'Roadmap.Repairer.ps1')
. (Join-Path $docAuditModuleRoot 'DocAudit.Scanner.ps1')
. (Join-Path $executionModuleRoot 'Execution.Ledger.ps1')
$docStdModuleRoot = Join-Path $WorkspaceRoot 'backend\modules\docstandardization'
. (Join-Path $roadmapModuleRoot 'Roadmap.Linter.ps1')
. (Join-Path $roadmapModuleRoot 'MaturityDrift.Monitor.ps1')
. (Join-Path $docStdModuleRoot 'DocStandardization.Previewer.ps1')
. (Join-Path $commonRoot 'NotificationHub.ps1')

$script:StatusCacheMemory = @{}
$script:StatusCacheDefaultTtlSeconds = 120
$script:StatusCacheSchemaVersion = 3

$script:RoadmapCacheMemory = @{}
$script:RoadmapCacheDefaultTtlSeconds = 300

$script:DocAuditCacheMemory = @{}
$script:DocAuditCacheDefaultTtlSeconds = 300

$script:RoadmapAuditCacheMemory = @{}
$script:RoadmapAuditCacheDefaultTtlSeconds = 300

$script:RoadmapRepairHistoryRoot = Join-Path $WorkspaceRoot 'output\roadmap-repair-history'

# Structured operations log (JSONL) — dashboard /api/log/tail reads this
$script:OpsLogPath = $null
try {
    $opsLogDir = Join-Path $WorkspaceRoot 'backend\modules\output\logs'
    if (-not (Test-Path -LiteralPath $opsLogDir)) {
        $null = New-Item -ItemType Directory -Path $opsLogDir -Force
    }
    $script:OpsLogPath = Join-Path $opsLogDir 'operations.jsonl'
} catch { }

function Write-HostLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    # Also write structured JSONL for the dashboard log tail endpoint
    if ($script:OpsLogPath) {
        try {
            $lvl = if ($Message -match '^ERROR|FAIL|\[ERR\]')   { 'ERROR' }
                   elseif ($Message -match '^WARN|\[WARN\]')     { 'WARN'  }
                   elseif ($Message -match '^\[TRACE\]')         { 'TRACE' }
                   else                                           { 'INFO'  }
            $entry = '{"ts":"{0}","level":"{1}","msg":{2}}' -f `
                (Get-Date).ToUniversalTime().ToString('o'), $lvl,
                ($Message | ConvertTo-Json -Compress)
            Add-Content -LiteralPath $script:OpsLogPath -Value $entry -Encoding UTF8
        } catch { }
    }
}

function Parse-Bool {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    return $text -match '^(1|true|yes|on)$'
}

function Get-ValueOrDefault {
    param(
        [Parameter()]
        [object]$Value,
        [Parameter()]
        [object]$Default = $null
    )

    if ($null -ne $Value) {
        return $Value
    }

    return $Default
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

function Send-HttpContent {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [byte[]]$BodyBytes,
        [Parameter()]
        [string]$ContentType = 'application/octet-stream',
        [Parameter()]
        [string]$StatusText = 'OK',
        [Parameter()]
        [string]$CorrelationId
    )

    $headers = @(
        "HTTP/1.1 $StatusCode $StatusText",
        "Content-Type: $ContentType",
        "Content-Length: $($BodyBytes.Length)",
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
    $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
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

function Get-ReportsRootPath {
    $reportsRoot = Join-Path $WorkspaceRoot 'reports'
    if (-not (Test-Path -LiteralPath $reportsRoot)) {
        $null = New-Item -ItemType Directory -Path $reportsRoot -Force
    }
    return $reportsRoot
}

function Get-ConfiguredLocalRootsOrWorkspace {
    param([hashtable]$Settings)

    # Use separate declaration + assignment to prevent PowerShell from unwrapping
    # a single-element array when the if/else block is used as an expression on the RHS.
    [string[]]$configuredRoots = @()
    if ($Settings.ContainsKey('inventory') -and $Settings.inventory.ContainsKey('localRoots') -and $Settings.inventory.localRoots) {
        $configuredRoots = @($Settings.inventory.localRoots | ForEach-Object { [string]$_ })
    }

    $validRoots = @($configuredRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) })
    if ($validRoots.Count -gt 0) {
        return $validRoots
    }

    return @($WorkspaceRoot)
}

function ConvertTo-HtmlEncodedText {
    param([object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-RepoStatusCsvContent {
    param([object[]]$Repos)

    $rows = @('Repository,Branch,Status,LastCommitDate,LastCommitAuthor,OpenPrCount,CommitsLastWeek,CommitsLastMonth,UncommittedChanges,Archived,Stale,Owner,Visibility,Language,LocalPath,HtmlUrl')
    foreach ($repo in @($Repos)) {
        $values = @(
            [string](Get-ValueOrDefault $repo.name ''),
            [string](Get-ValueOrDefault $repo.branch ''),
            [string](Get-ValueOrDefault $repo.status ''),
            [string](Get-ValueOrDefault $repo.lastCommitDate ''),
            [string](Get-ValueOrDefault $repo.lastCommitAuthor ''),
            [string](Get-ValueOrDefault $repo.openPrCount 0),
            [string](Get-ValueOrDefault $repo.commitsLastWeek 0),
            [string](Get-ValueOrDefault $repo.commitsLastMonth 0),
            [string](Get-ValueOrDefault $repo.uncommittedChanges 0),
            [string]([bool](Get-ValueOrDefault $repo.isArchived $false)),
            [string]([bool](Get-ValueOrDefault $repo.isStale $false)),
            [string](Get-ValueOrDefault $repo.owner ''),
            [string](Get-ValueOrDefault $repo.visibility ''),
            [string](Get-ValueOrDefault $repo.language ''),
            [string](Get-ValueOrDefault (Get-ValueOrDefault $repo.localPath $repo.path) ''),
            [string](Get-ValueOrDefault $repo.htmlUrl '')
        ) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }

        $rows += ($values -join ',')
    }

    return ($rows -join "`r`n")
}

function New-RepoStatusHtmlContent {
    param(
        [object[]]$Repos,
        [string]$SourceLabel,
        [datetime]$GeneratedAt
    )

    $repoList = @($Repos)
    $repoCount = $repoList.Count
    $dirtyCount = @($repoList | Where-Object { [int](Get-ValueOrDefault $_.uncommittedChanges 0) -gt 0 -or [string](Get-ValueOrDefault $_.status '') -eq 'dirty' }).Count
    $archivedCount = @($repoList | Where-Object { [bool](Get-ValueOrDefault $_.isArchived $false) }).Count
    $staleCount = @($repoList | Where-Object { [bool](Get-ValueOrDefault $_.isStale $false) }).Count
    $openPrTotal = ($repoList | Measure-Object -Property openPrCount -Sum).Sum
    $weeklyCommitTotal = ($repoList | Measure-Object -Property commitsLastWeek -Sum).Sum
    $monthlyCommitTotal = ($repoList | Measure-Object -Property commitsLastMonth -Sum).Sum
    $generatedDisplay = $GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')
    $sourceDisplay = if ([string]::IsNullOrWhiteSpace($SourceLabel)) { 'Repository dashboard export' } else { $SourceLabel }

    $rowMarkup = foreach ($repo in $repoList) {
        $name = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.name 'unknown')
        $branch = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.branch '')
        $statusRaw = [string](Get-ValueOrDefault $repo.status 'unknown')
        $status = ConvertTo-HtmlEncodedText $statusRaw
        $statusClass = switch ($statusRaw.ToLowerInvariant()) {
            'dirty' { 'warn' }
            'ahead' { 'accent' }
            'behind' { 'warn' }
            'diverged' { 'danger' }
            default { 'ok' }
        }
        $lastCommitDate = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.lastCommitDate '')
        $lastCommitAuthor = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.lastCommitAuthor '')
        $owner = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.owner '')
        $visibility = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.visibility '')
        $language = ConvertTo-HtmlEncodedText (Get-ValueOrDefault $repo.language '')
        $topics = @($repo.topics)
        $topicMarkup = if ($topics.Count -gt 0) {
            ($topics | Select-Object -First 4 | ForEach-Object { "<span class=""chip"">$(ConvertTo-HtmlEncodedText $_)</span>" }) -join ''
        }
        else {
            '<span class="muted">No topics</span>'
        }
        $pathValue = [string](Get-ValueOrDefault (Get-ValueOrDefault $repo.localPath $repo.path) '')
        $pathMarkup = if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
            "<div class=""meta-line""><span class=""meta-label"">Path</span><code>$(ConvertTo-HtmlEncodedText $pathValue)</code></div>"
        }
        else {
            ''
        }
        $htmlUrlValue = [string](Get-ValueOrDefault $repo.htmlUrl '')
        $htmlLinkMarkup = if (-not [string]::IsNullOrWhiteSpace($htmlUrlValue)) {
            "<div class=""meta-line""><span class=""meta-label"">Remote</span><a href=""$(ConvertTo-HtmlEncodedText $htmlUrlValue)"" target=""_blank"" rel=""noreferrer"">$(ConvertTo-HtmlEncodedText $htmlUrlValue)</a></div>"
        }
        else {
            '<div class="meta-line"><span class="meta-label">Remote</span><span class="muted">n/a</span></div>'
        }

@"
          <tr>
            <td>
              <div class="repo-name">$name</div>
              <div class="repo-meta">
                <span>$owner</span>
                <span>$visibility</span>
                <span>$language</span>
              </div>
              <div class="chip-row">$topicMarkup</div>
            </td>
            <td><code>$branch</code></td>
            <td><span class="badge $statusClass">$status</span></td>
            <td>
              <div>$lastCommitDate</div>
              <div class="muted">$lastCommitAuthor</div>
            </td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.openPrCount 0))</td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.commitsLastWeek 0))</td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.commitsLastMonth 0))</td>
            <td class="numeric">$([int](Get-ValueOrDefault $repo.uncommittedChanges 0))</td>
            <td>
              $pathMarkup
              $htmlLinkMarkup
            </td>
          </tr>
"@
    }

    if (@($rowMarkup).Count -eq 0) {
        $rowMarkup = @'
          <tr>
            <td colspan="9" class="empty-state">No repositories were included in this export.</td>
          </tr>
'@
    }

@"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Repository Report - $generatedDisplay</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #08111f;
      --panel: rgba(10, 24, 45, 0.82);
      --panel-strong: #0d1e36;
      --line: rgba(142, 169, 197, 0.22);
      --text: #e7eef7;
      --muted: #97a8bc;
      --accent: #34d399;
      --accent-strong: #10b981;
      --warn: #f59e0b;
      --danger: #f97316;
      --shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(52, 211, 153, 0.18), transparent 28%),
        radial-gradient(circle at top right, rgba(59, 130, 246, 0.18), transparent 32%),
        linear-gradient(180deg, #09101d 0%, #08111f 52%, #050a12 100%);
      color: var(--text);
      min-height: 100vh;
    }
    .shell {
      width: min(1400px, calc(100% - 32px));
      margin: 32px auto;
      padding: 24px;
      border: 1px solid var(--line);
      border-radius: 28px;
      background: var(--panel);
      backdrop-filter: blur(18px);
      box-shadow: var(--shadow);
    }
    .hero {
      display: grid;
      gap: 20px;
      grid-template-columns: 1.5fr 1fr;
      align-items: end;
      margin-bottom: 28px;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 12px;
      border-radius: 999px;
      background: rgba(52, 211, 153, 0.12);
      color: #b6f4df;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    h1 {
      margin: 14px 0 10px;
      font-size: clamp(32px, 4vw, 54px);
      line-height: 1;
    }
    .lede {
      margin: 0;
      color: var(--muted);
      max-width: 70ch;
      line-height: 1.6;
    }
    .meta-card {
      padding: 20px;
      border-radius: 22px;
      background: linear-gradient(180deg, rgba(13, 30, 54, 0.94), rgba(8, 17, 31, 0.94));
      border: 1px solid var(--line);
    }
    .meta-card strong {
      display: block;
      margin-bottom: 8px;
      font-size: 14px;
      color: #bcd0e8;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }
    .meta-card span {
      display: block;
      color: var(--text);
      line-height: 1.6;
      word-break: break-word;
    }
    .stats {
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      margin-bottom: 24px;
    }
    .stat {
      padding: 18px;
      border-radius: 20px;
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.03);
    }
    .stat .label {
      display: block;
      margin-bottom: 12px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .stat .value {
      display: block;
      font-size: clamp(24px, 3vw, 34px);
      font-weight: 700;
    }
    .table-shell {
      overflow: hidden;
      border-radius: 24px;
      border: 1px solid var(--line);
      background: rgba(4, 10, 20, 0.55);
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    thead th {
      text-align: left;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #a9bdd3;
      background: rgba(13, 30, 54, 0.94);
      padding: 16px 18px;
      border-bottom: 1px solid var(--line);
      position: sticky;
      top: 0;
    }
    tbody td {
      padding: 16px 18px;
      border-bottom: 1px solid rgba(142, 169, 197, 0.12);
      vertical-align: top;
    }
    tbody tr:hover {
      background: rgba(255, 255, 255, 0.03);
    }
    .repo-name {
      font-size: 16px;
      font-weight: 700;
      margin-bottom: 6px;
    }
    .repo-meta, .chip-row, .meta-line {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 10px;
      align-items: center;
    }
    .repo-meta {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(148, 163, 184, 0.12);
      color: #d5dfeb;
      font-size: 12px;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 86px;
      padding: 7px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .badge.ok { background: rgba(16, 185, 129, 0.14); color: #b6f4df; }
    .badge.warn { background: rgba(245, 158, 11, 0.16); color: #f9d48e; }
    .badge.accent { background: rgba(59, 130, 246, 0.16); color: #b9d5ff; }
    .badge.danger { background: rgba(249, 115, 22, 0.16); color: #ffca9c; }
    .muted, .meta-label {
      color: var(--muted);
    }
    .meta-label {
      min-width: 52px;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .numeric {
      text-align: right;
      font-variant-numeric: tabular-nums;
    }
    a { color: #9fd0ff; }
    code {
      font-family: "Cascadia Code", Consolas, monospace;
      font-size: 12px;
      background: rgba(148, 163, 184, 0.1);
      padding: 2px 6px;
      border-radius: 8px;
      word-break: break-all;
    }
    .empty-state {
      text-align: center;
      color: var(--muted);
      padding: 40px 18px;
    }
    @media (max-width: 1100px) {
      .hero, .stats { grid-template-columns: 1fr 1fr; }
    }
    @media (max-width: 820px) {
      .shell { width: min(100% - 20px, 1400px); padding: 18px; margin: 14px auto; }
      .hero, .stats { grid-template-columns: 1fr; }
      .table-shell { overflow-x: auto; }
      table { min-width: 980px; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <div>
        <span class="eyebrow">Repo Management Report</span>
        <h1>Repository Status Snapshot</h1>
        <p class="lede">A saved dashboard export with repository health, activity, and discovery metadata. This file was generated from the current application view and written into the repo-local reports folder for later review.</p>
      </div>
      <aside class="meta-card">
        <strong>Export Context</strong>
        <span>Source: $(ConvertTo-HtmlEncodedText $sourceDisplay)</span>
        <span>Generated: $(ConvertTo-HtmlEncodedText $generatedDisplay)</span>
        <span>Repository Count: $repoCount</span>
      </aside>
    </section>

    <section class="stats">
      <article class="stat"><span class="label">Repositories</span><span class="value">$repoCount</span></article>
      <article class="stat"><span class="label">Dirty</span><span class="value">$dirtyCount</span></article>
      <article class="stat"><span class="label">Archived</span><span class="value">$archivedCount</span></article>
      <article class="stat"><span class="label">Stale</span><span class="value">$staleCount</span></article>
      <article class="stat"><span class="label">Open PRs</span><span class="value">$([int](Get-ValueOrDefault $openPrTotal 0))</span></article>
      <article class="stat"><span class="label">Commits 7d / 30d</span><span class="value">$([int](Get-ValueOrDefault $weeklyCommitTotal 0)) / $([int](Get-ValueOrDefault $monthlyCommitTotal 0))</span></article>
    </section>

    <section class="table-shell">
      <table>
        <thead>
          <tr>
            <th>Repository</th>
            <th>Branch</th>
            <th>Status</th>
            <th>Last Commit</th>
            <th>Open PRs</th>
            <th>Commits 7d</th>
            <th>Commits 30d</th>
            <th>Changes</th>
            <th>Links</th>
          </tr>
        </thead>
        <tbody>
$(($rowMarkup -join "`n"))
        </tbody>
      </table>
    </section>
  </main>
</body>
</html>
"@
}

function Export-RepoStatusReports {
    param(
        [object[]]$Repos,
        [string]$SourceLabel
    )

    $reportsRoot = Get-ReportsRootPath
    $generatedAt = Get-Date
    $timestamp = $generatedAt.ToString('yyyyMMdd_HHmmssfff')
    $htmlFileName = "repo-status-report_$timestamp.html"
    $csvFileName = "repo-status-report_$timestamp.csv"
    $htmlPath = Join-Path $reportsRoot $htmlFileName
    $csvPath = Join-Path $reportsRoot $csvFileName

    $htmlContent = New-RepoStatusHtmlContent -Repos $Repos -SourceLabel $SourceLabel -GeneratedAt $generatedAt
    $csvContent = New-RepoStatusCsvContent -Repos $Repos

    Set-Content -LiteralPath $htmlPath -Value $htmlContent -Encoding UTF8
    Set-Content -LiteralPath $csvPath -Value $csvContent -Encoding UTF8

    return [pscustomobject]@{
        generatedAt = $generatedAt.ToString('o')
        repoCount = @($Repos).Count
        sourceLabel = $SourceLabel
        reportFileName = $htmlFileName
        reportPath = $htmlPath
        reportUrl = "/api/reports/$([System.Uri]::EscapeDataString($htmlFileName))"
        csvFileName = $csvFileName
        csvPath = $csvPath
    }
}

function Invoke-PowerShellScriptFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter()]
        [string[]]$Arguments = @(),
        [Parameter()]
        [switch]$AllowFailure
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    $rawOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $outputText = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"

    if (($exitCode -ne 0) -and (-not $AllowFailure.IsPresent)) {
        if ([string]::IsNullOrWhiteSpace($outputText)) {
            throw "Script failed with exit code ${exitCode}: $ScriptPath"
        }
        throw $outputText
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $outputText
        Lines = @($rawOutput)
    }
}

function Get-JsonObjectFromText {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw 'No output received from script.'
    }

    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        throw 'Script output did not contain a JSON object.'
    }

    $json = $Text.Substring($start, $end - $start + 1)
    return ConvertFrom-JsonCompat -Json $json
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

function Test-StatusResponseHasActivityMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    $repoItems = @()
    if ($Response -is [System.Collections.IDictionary]) {
        if ($Response.ContainsKey('data') -and $Response.data -is [System.Collections.IDictionary] -and $Response.data.ContainsKey('repos')) {
            $repoItems = @($Response.data.repos)
        }
    }
    elseif ($Response.PSObject.Properties.Name -contains 'data' -and $null -ne $Response.data) {
        $data = $Response.data
        if ($data -is [System.Collections.IDictionary]) {
            if ($data.ContainsKey('repos')) {
                $repoItems = @($data.repos)
            }
        }
        elseif ($data.PSObject.Properties.Name -contains 'repos') {
            $repoItems = @($data.repos)
        }
    }

    if (@($repoItems).Count -eq 0) {
        return $true
    }

    foreach ($repo in @($repoItems)) {
        if ($repo -is [System.Collections.IDictionary]) {
            if (
                (-not $repo.ContainsKey('lastCommitAuthor')) -or
                (-not $repo.ContainsKey('commitsLastWeek')) -or
                (-not $repo.ContainsKey('commitsLastMonth'))
            ) {
                return $false
            }
            continue
        }

        $props = @($repo.PSObject.Properties.Name)
        if (
            ($props -notcontains 'lastCommitAuthor') -or
            ($props -notcontains 'commitsLastWeek') -or
            ($props -notcontains 'commitsLastMonth')
        ) {
            return $false
        }
    }

    return $true
}

function Get-StatusFromCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [int]$TtlSeconds,
        # When set, returns cached data regardless of TTL (stale-while-revalidate support)
        [Parameter()]
        [switch]$IgnoreTtl
    )

    $nowUtc = (Get-Date).ToUniversalTime()

    if ($script:StatusCacheMemory.ContainsKey($Key)) {
        $memoryEntry = $script:StatusCacheMemory[$Key]
        $ageSeconds = (($nowUtc) - [datetime]$memoryEntry.CreatedAtUtc).TotalSeconds
        if ($IgnoreTtl.IsPresent -or $ageSeconds -le $TtlSeconds) {
            if (-not (Test-StatusResponseHasActivityMetrics -Response $memoryEntry.Response)) {
                $script:StatusCacheMemory.Remove($Key)
                Write-HostLog ("Status cache miss: memory entry missing activity metrics for key '{0}'" -f $Key)
                return [pscustomobject]@{ hit = $false }
            }
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
        if (-not $diskEntry.ContainsKey('schemaVersion') -or [int]$diskEntry.schemaVersion -ne $script:StatusCacheSchemaVersion) {
            return [pscustomobject]@{ hit = $false }
        }
        if ([string]$diskEntry.key -ne $Key) {
            return [pscustomobject]@{ hit = $false }
        }
        if (-not (Test-StatusResponseHasActivityMetrics -Response $diskEntry.response)) {
            Write-HostLog ("Status cache miss: disk entry missing activity metrics for key '{0}'" -f $Key)
            return [pscustomobject]@{ hit = $false }
        }

        $createdAtUtc = [datetime]$diskEntry.createdAtUtc
        $ageSeconds = (($nowUtc) - $createdAtUtc).TotalSeconds
        if ((-not $IgnoreTtl.IsPresent) -and ($ageSeconds -gt $TtlSeconds)) {
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
        schemaVersion = $script:StatusCacheSchemaVersion
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

function Get-GitHubOwnerTypeViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    try {
        $uri = "https://api.github.com/users/$Owner"
        $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
        if ($response -and $response.type) {
            $typeValue = [string]$response.type
            if ($typeValue -eq 'Organization') { return 'Organization' }
            return 'User'
        }
    }
    catch {
        Write-HostLog ("[TRACE] github.ownerType lookup failed owner={0} error={1}" -f $Owner, $_.Exception.Message)
    }

    return 'User'
}

function Get-GitHubCommitCountViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [int]$SinceDays
    )

    $since = (Get-Date).ToUniversalTime().AddDays(-1 * [math]::Abs($SinceDays)).ToString('o')
    $uri = "https://api.github.com/repos/$Owner/$Repo/commits?per_page=1&since=$([System.Uri]::EscapeDataString($since))"

    try {
        $response = Invoke-WebRequest -Uri $uri -Headers $Headers -Method Get
        $bodyText = [string]$response.Content
        $bodyItems = @()
        if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
            try { $bodyItems = @(ConvertFrom-Json -InputObject $bodyText) } catch { $bodyItems = @() }
        }

        if ($bodyItems.Count -eq 0) {
            return 0
        }

        $linkHeader = [string]$response.Headers['Link']
        if (-not [string]::IsNullOrWhiteSpace($linkHeader)) {
            if ($linkHeader -match 'page=(\d+)>;\s*rel="last"') {
                return [int]$matches[1]
            }
            if ($linkHeader -match 'rel="next"') {
                return 2
            }
        }

        return 1
    }
    catch {
        Write-HostLog ("[TRACE] github.commitCount failed owner={0} repo={1} sinceDays={2} error={3}" -f $Owner, $Repo, $SinceDays, $_.Exception.Message)
        return 0
    }
}

function Get-GitHubReposViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Token,
        [Parameter()]
        [bool]$IncludePrivate = $true,
        [Parameter()]
        [bool]$IncludeForks = $false,
        [Parameter()]
        [bool]$IncludeArchived = $true,
        [Parameter()]
        [bool]$FetchCommitMetrics = $true,
        [Parameter()]
        [int]$RepoLimit = 50
    )

    $headers = @{
        Authorization = "Bearer $Token"
        'User-Agent' = 'GitHubRepoManagement'
        Accept = 'application/vnd.github+json'
    }

    $openPrCounts = @{}
    try {
        $openPrCounts = Get-GitHubOpenPrCountsViaApi -Owner $Owner -Token $Token
    }
    catch {
        Write-HostLog ("[TRACE] github.openpr api aggregation failed owner={0} error={1}" -f $Owner, $_.Exception.Message)
    }

    $ownerType = Get-GitHubOwnerTypeViaApi -Owner $Owner -Headers $headers
    $repoType = if ($IncludePrivate) { 'all' } else { 'public' }

    $uris = @()
    if ($ownerType -eq 'Organization') {
        $uris += "https://api.github.com/orgs/$Owner/repos?per_page=100&sort=updated&type=$repoType"
    }
    else {
        $uris += "https://api.github.com/users/$Owner/repos?per_page=100&sort=updated&type=$repoType"
        if ($IncludePrivate) {
            $uris += "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member"
        }
    }

    $repoMap = @{}
    foreach ($uri in $uris) {
        try {
            $reposRaw = @(Invoke-RestMethod -Uri $uri -Headers $headers -Method Get)
            foreach ($repoItem in $reposRaw) {
                if ($null -eq $repoItem -or -not $repoItem.name) { continue }

                $repoOwner = if ($repoItem.owner -and $repoItem.owner.login) { [string]$repoItem.owner.login } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($repoOwner) -and $repoOwner.ToLowerInvariant() -ne $Owner.ToLowerInvariant()) { continue }

                if ((-not $IncludeForks) -and [bool]$repoItem.fork) { continue }
                if ((-not $IncludeArchived) -and [bool]$repoItem.archived) { continue }

                $key = [string]$repoItem.name
                if (-not $repoMap.ContainsKey($key)) {
                    $repoMap[$key] = $repoItem
                }
            }
        }
        catch {
            Write-HostLog ("[TRACE] github.repos fetch failed owner={0} uri={1} error={2}" -f $Owner, $uri, $_.Exception.Message)
            continue
        }
    }

    $allRepos = @($repoMap.Values | Sort-Object -Property updated_at -Descending)
    $repos = @($allRepos | Select-Object -First $RepoLimit | ForEach-Object {
        $repoOpenPrCount = 0
        if ($openPrCounts.ContainsKey($_.name)) {
            $repoOpenPrCount = [int]$openPrCounts[$_.name]
        }

        $commitCountWeek = 0
        $commitCountMonth = 0
        if ($FetchCommitMetrics) {
            $commitCountWeek = Get-GitHubCommitCountViaApi -Owner $Owner -Repo ([string]$_.name) -Headers $headers -SinceDays 7
            $commitCountMonth = Get-GitHubCommitCountViaApi -Owner $Owner -Repo ([string]$_.name) -Headers $headers -SinceDays 30
        }

        $lastCommitAuthor = ''
        if ($_.owner -and $_.owner.login) {
            $lastCommitAuthor = [string]$_.owner.login
        }

        [pscustomobject]@{
            name = $_.name
            branch = if ($_.default_branch) { $_.default_branch } else { 'main' }
            status = 'clean'
            lastCommitDate = if ($_.pushed_at) { $_.pushed_at } else { $_.updated_at }
            lastCommitMessage = if ($_.description) { [string]$_.description } else { '' }
            lastCommitAuthor = $lastCommitAuthor
            commitsLastWeek = $commitCountWeek
            commitsLastMonth = $commitCountMonth
            uncommittedChanges = 0
            isArchived = [bool]$_.archived
            isStale = $false
            localAhead = 0
            remoteAhead = 0
            openPrCount = $repoOpenPrCount
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
        totalRepos = @($allRepos).Count
        fetchedRepos = @($repos).Count
        repos = $repos
        rateLimit = $null
    }
}

function Get-GitHubOpenPrCountsViaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $headers = @{
        Authorization = "Bearer $Token"
        'User-Agent' = 'GitHubRepoManagement'
        Accept = 'application/vnd.github+json'
    }

    $counts = @{}
    $page = 1
    $maxPages = 10
    while ($page -le $maxPages) {
        $query = [System.Uri]::EscapeDataString("user:$Owner is:pr is:open")
        $uri = "https://api.github.com/search/issues?q=$query&per_page=100&page=$page"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $items = @($response.items)
        if ($items.Count -eq 0) {
            break
        }

        foreach ($item in $items) {
            if ($null -eq $item.repository_url) { continue }
            $segments = ([string]$item.repository_url).TrimEnd('/') -split '/'
            if ($segments.Length -lt 1) { continue }
            $repoName = $segments[$segments.Length - 1]
            if (-not $counts.ContainsKey($repoName)) {
                $counts[$repoName] = 0
            }
            $counts[$repoName] = [int]$counts[$repoName] + 1
        }

        if ($items.Count -lt 100) {
            break
        }

        $page++
    }

    return $counts
}

function Get-GitHubOpenPrCountsViaGh {
    param([Parameter(Mandatory = $true)][string]$Owner)

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        return @{}
    }

    $counts = @{}
    $page = 1
    $maxPages = 10
    while ($page -le $maxPages) {
        $query = "user:$Owner is:pr is:open"
        $json = (& gh api "search/issues" --field q="$query" --field per_page='100' --field page="$page" 2>$null) | Out-String
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
            break
        }

        $response = ConvertFrom-Json $json
        $items = @($response.items)
        if ($items.Count -eq 0) {
            break
        }

        foreach ($item in $items) {
            $repoUrl = [string]$item.repository_url
            if ([string]::IsNullOrWhiteSpace($repoUrl)) { continue }
            $segments = $repoUrl.TrimEnd('/') -split '/'
            if ($segments.Length -lt 1) { continue }
            $repoName = $segments[$segments.Length - 1]
            if (-not $counts.ContainsKey($repoName)) {
                $counts[$repoName] = 0
            }
            $counts[$repoName] = [int]$counts[$repoName] + 1
        }

        if ($items.Count -lt 100) {
            break
        }
        $page++
    }

    return $counts
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

function Get-RoadmapStandard {
    <#
    .SYNOPSIS
        Load and return the roadmap audit rules and maturity thresholds from
        standards/roadmap/roadmap-audit-rules.json.
    .OUTPUTS
        [pscustomobject] with rules, maturityThresholds, version, ruleCount, loadedAt — or $null on failure.
    #>
    $standardPath = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json'
    if (-not (Test-Path -LiteralPath $standardPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $standardPath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsed = ConvertFrom-Json -InputObject $raw
        return [pscustomobject]@{
            version           = [string]$parsed.version
            description       = [string]$parsed.description
            rules             = @($parsed.rules)
            maturityThresholds = $parsed.maturityThresholds
            ruleCount         = @($parsed.rules).Count
            maturityLevels    = @($parsed.maturityThresholds.PSObject.Properties.Name)
            loadedAt          = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    catch {
        return $null
    }
}

function Get-RoadmapAuditCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'roadmap-audit-cache.json'
}

function Get-RoadmapAuditCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:RoadmapAuditCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('roadmap') -and
        $Settings.roadmap -is [System.Collections.IDictionary] -and
        $Settings.roadmap.ContainsKey('auditCacheTtlSeconds') -and
        $Settings.roadmap.auditCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.roadmap.auditCacheTtlSeconds
        if ($candidate -ge 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-RoadmapAuditFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-audit-global'

    if ($script:RoadmapAuditCacheMemory.ContainsKey($key)) {
        $entry = $script:RoadmapAuditCacheMemory[$key]
        $age = (($nowUtc) - [datetime]$entry.CreatedAtUtc).TotalSeconds
        if ($age -le $TtlSeconds) {
            return [pscustomobject]@{ hit = $true; source = 'memory'; ageSeconds = $age; cachedAt = ([datetime]$entry.CreatedAtUtc).ToString('o'); entries = $entry.Entries; auditedAt = $entry.AuditedAt }
        }
    }

    $cacheFile = Get-RoadmapAuditCacheFilePath
    if (-not (Test-Path -LiteralPath $cacheFile)) { return [pscustomobject]@{ hit = $false } }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ hit = $false } }
        $disk = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $disk -or -not $disk.ContainsKey('createdAtUtc')) { return [pscustomobject]@{ hit = $false } }
        $created = [datetime]$disk.createdAtUtc
        $age = (($nowUtc) - $created).TotalSeconds
        if ($age -gt $TtlSeconds) { return [pscustomobject]@{ hit = $false } }
        $script:RoadmapAuditCacheMemory[$key] = @{ CreatedAtUtc = $created; Entries = $disk.entries; AuditedAt = [string]$disk.auditedAt }
        return [pscustomobject]@{ hit = $true; source = 'disk'; ageSeconds = $age; cachedAt = $created.ToString('o'); entries = $disk.entries; auditedAt = [string]$disk.auditedAt }
    }
    catch { return [pscustomobject]@{ hit = $false } }
}

function Save-RoadmapAuditCache {
    param([array]$Entries, [string]$AuditedAt)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'roadmap-audit-global'
    $script:RoadmapAuditCacheMemory[$key] = @{ CreatedAtUtc = $nowUtc; Entries = $Entries; AuditedAt = $AuditedAt }
    try {
        $cacheFile = Get-RoadmapAuditCacheFilePath
        (@{ createdAtUtc = $nowUtc.ToString('o'); auditedAt = $AuditedAt; entries = $Entries } | ConvertTo-Json -Depth 15) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch { Write-HostLog ("Roadmap audit cache write skipped: {0}" -f $_.Exception.Message) }
}

function Clear-RoadmapAuditCache {
    $script:RoadmapAuditCacheMemory = @{}
    try {
        $cacheFile = Get-RoadmapAuditCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-HostLog ("Roadmap audit cache clear skipped: {0}" -f $_.Exception.Message) }
}

function Invoke-RoadmapAuditScan {
    <#
    .SYNOPSIS
        Scan all roadmap entries, normalize each contract, and apply the audit
        rule pack. Returns an array of RoadmapAuditEntry objects.
    #>
    param(
        [string[]]$LocalRoots,
        [int]$MaxDepth = 3
    )

    Write-HostLog '[TRACE] roadmap.audit.scan normalize-start'
    $auditRules = Get-RoadmapStandard
    if ($null -eq $auditRules) {
        Write-HostLog '[WARN] roadmap.audit.scan audit-rules-missing — scoring skipped'
    }

    $roadmapEntries = Invoke-RoadmapScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth
    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($entry in $roadmapEntries) {
        $repoName = [string]$entry.repoName
        $repoPath = [string]$entry.repoPath
        $roadmapPath = [string]$entry.roadmapPath

        try {
            # Read raw content
            $rawContent = ''
            if (-not [string]::IsNullOrWhiteSpace($roadmapPath) -and (Test-Path -LiteralPath $roadmapPath)) {
                $rawContent = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
            }

            # Parse
            Write-HostLog ("[TRACE] roadmap.audit.scan parse repoName={0}" -f $repoName)
            $parsed = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $roadmapPath

            # Normalize
            Write-HostLog ("[TRACE] roadmap.audit.scan normalize repoName={0} state={1}" -f $repoName, $parsed.roadmapState)
            $contract = Invoke-NormalizeRoadmapContract -ParsedResult $parsed -RawContent $rawContent -RepoName $repoName -RepoPath $repoPath -RoadmapPath $roadmapPath

            # Audit / score
            if ($null -ne $auditRules) {
                Write-HostLog ("[TRACE] roadmap.audit.scan score repoName={0}" -f $repoName)
                $contract = Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRules
            }

            $results.Add($contract)
        }
        catch {
            Write-HostLog ("[WARN] roadmap.audit.scan audit-rule-failure repoName={0} error={1}" -f $repoName, $_.Exception.Message)
            $results.Add([pscustomobject]@{
                schemaVersion         = '1.0'
                repoName              = $repoName
                repoPath              = $repoPath
                roadmapPath           = $roadmapPath
                roadmapState          = 'parse-error'
                maturityLevel         = 'L0-Absent'
                maturityScore         = 0
                pendingCount          = 0
                completedCount        = 0
                totalCount            = 0
                nextPendingItem       = $null
                sections              = @()
                hasProductIntent      = $false
                hasReleaseSections    = $false
                hasAcceptanceCriteria = $false
                hasOutOfScope         = $false
                releaseCount          = 0
                vagueItemCount        = 0
                parseError            = $_.Exception.Message
                auditFindings         = @()
                parsedAt              = (Get-Date).ToUniversalTime().ToString('o')
            })
        }
    }

    Write-HostLog ("[TRACE] roadmap.audit.scan done auditedCount={0}" -f $results.Count)
    return @($results)
}

# ---------------------------------------------------------------------------
# Roadmap Repair helpers (Release 0.9)
# ---------------------------------------------------------------------------

function Get-RoadmapRepairHistoryPath {
    if (-not (Test-Path -LiteralPath $script:RoadmapRepairHistoryRoot)) {
        $null = New-Item -ItemType Directory -Path $script:RoadmapRepairHistoryRoot -Force -ErrorAction SilentlyContinue
    }
    return $script:RoadmapRepairHistoryRoot
}

function Save-RoadmapRepairHistoryEntry {
    <#
    .SYNOPSIS
        Persist a repair history record to disk.
    #>
    param(
        [string]$PreviewId,
        [string]$RepoName,
        [string]$RoadmapPath,
        [string]$PreviewState,
        [string]$OriginalMaturityLevel,
        [string]$Event,        # 'preview' or 'apply'
        [string]$AppliedAt     = ''
    )
    try {
        $historyRoot = Get-RoadmapRepairHistoryPath
        $historyFile = Join-Path $historyRoot 'repair-history.jsonl'
        $record = [ordered]@{
            previewId            = $PreviewId
            repoName             = $RepoName
            roadmapPath          = $RoadmapPath
            previewState         = $PreviewState
            originalMaturityLevel = $OriginalMaturityLevel
            event                = $Event
            timestamp            = (Get-Date).ToUniversalTime().ToString('o')
        }
        if (-not [string]::IsNullOrWhiteSpace($AppliedAt)) {
            $record['appliedAt'] = $AppliedAt
        }
        $line = ConvertTo-Json -InputObject $record -Compress -Depth 5
        Add-Content -LiteralPath $historyFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        Write-HostLog ("Roadmap repair history write skipped: {0}" -f $_.Exception.Message)
    }
}

function Get-RoadmapRepairHistory {
    <#
    .SYNOPSIS
        Read the last N repair history entries from disk.
    #>
    param([int]$Limit = 25)
    $historyRoot = Get-RoadmapRepairHistoryPath
    $historyFile = Join-Path $historyRoot 'repair-history.jsonl'
    $items = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $historyFile)) { return @() }
    try {
        $lines = Get-Content -LiteralPath $historyFile -Encoding UTF8 -ErrorAction Stop | Select-Object -Last $Limit
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json
                $items.Add($obj)
            } catch { }
        }
    } catch { }
    return @($items)
}

function Build-RoadmapRepairPreview {
    <#
    .SYNOPSIS
        Build a full repair preview for a named repository.
        Reads the roadmap, runs audit, plans repair, generates proposed content.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RoadmapPath = ''
    )

    # Resolve roadmap path
    $settings  = Get-HostSettings
    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCacheResult = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
    $roadmapEntry = $null
    if ($roadmapCacheResult.hit -and $roadmapCacheResult.entries) {
        $roadmapEntry = @($roadmapCacheResult.entries) | Where-Object { [string]$_.repoName -eq $RepoName } | Select-Object -First 1
    }

    $effectiveRoadmapPath = $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $roadmapEntry) {
        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
    }

    $rawContent = ''
    $parsedResult = $null
    if (-not [string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and (Test-Path -LiteralPath $effectiveRoadmapPath)) {
        Write-HostLog ("[TRACE] roadmap.repair.preview read repoName={0} path={1}" -f $RepoName, $effectiveRoadmapPath)
        $rawContent = Get-Content -LiteralPath $effectiveRoadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsedResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $effectiveRoadmapPath
    }

    # Normalize and audit
    $repoPath = ''
    if ($null -ne $roadmapEntry) {
        $repoPath = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $roadmapEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $roadmapEntry.repoPath '') }
    }
    $contract = Invoke-NormalizeRoadmapContract `
        -ParsedResult $parsedResult `
        -RawContent $rawContent `
        -RepoName $RepoName `
        -RepoPath $repoPath `
        -RoadmapPath $effectiveRoadmapPath

    $auditRules = Get-RoadmapStandard
    if ($null -ne $auditRules) {
        $contract = Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRules
    }

    Write-HostLog ("[TRACE] roadmap.repair.preview plan repoName={0} maturityLevel={1}" -f $RepoName, $contract.maturityLevel)

    # Plan the repair
    $repairPlan = Invoke-PlanRoadmapRepair -Contract $contract

    # Generate preview
    $preview = Invoke-GenerateRepairPreview `
        -Contract    $contract `
        -RepairPlan  $repairPlan `
        -RawContent  $rawContent `
        -RepoName    $RepoName

    # Attach extra context
    $preview | Add-Member -NotePropertyName 'repoName'             -NotePropertyValue $RepoName               -Force
    $preview | Add-Member -NotePropertyName 'roadmapPath'          -NotePropertyValue $effectiveRoadmapPath   -Force
    $preview | Add-Member -NotePropertyName 'originalMaturityLevel' -NotePropertyValue $contract.maturityLevel -Force
    $preview | Add-Member -NotePropertyName 'originalMaturityScore' -NotePropertyValue $contract.maturityScore -Force
    $preview | Add-Member -NotePropertyName 'auditFindings'         -NotePropertyValue @(Get-ValueOrDefault $contract.auditFindings @()) -Force

    # Persist preview event to history
    Save-RoadmapRepairHistoryEntry `
        -PreviewId            $preview.previewId `
        -RepoName             $RepoName `
        -RoadmapPath          $effectiveRoadmapPath `
        -PreviewState         $preview.previewState `
        -OriginalMaturityLevel $contract.maturityLevel `
        -Event                'preview'

    return $preview
}

function Apply-RoadmapRepair {
    <#
    .SYNOPSIS
        Apply a previously generated repair preview to the roadmap file.
        Requires explicit operator approval via the previewId.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$PreviewId,

        [Parameter(Mandatory = $true)]
        [string]$ProposedContent,

        [Parameter()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [string]$OriginalMaturityLevel = ''
    )

    if ([string]::IsNullOrWhiteSpace($ProposedContent)) {
        throw 'proposedContent is required to apply a repair.'
    }

    # Resolve roadmap path
    $settings  = Get-HostSettings
    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCacheResult = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
    $roadmapEntry = $null
    if ($roadmapCacheResult.hit -and $roadmapCacheResult.entries) {
        $roadmapEntry = @($roadmapCacheResult.entries) | Where-Object { [string]$_.repoName -eq $RepoName } | Select-Object -First 1
    }

    $effectiveRoadmapPath = $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $roadmapEntry) {
        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
    }

    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath)) {
        throw "Cannot apply repair: roadmap path could not be resolved for repo '$RepoName'. Run a roadmap scan first."
    }

    # Backup original before write
    $backupDir = Join-Path $script:RoadmapRepairHistoryRoot 'backups'
    $null = New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction SilentlyContinue
    $backupFile = Join-Path $backupDir ("$RepoName-$PreviewId-original.md")
    if (Test-Path -LiteralPath $effectiveRoadmapPath) {
        Copy-Item -LiteralPath $effectiveRoadmapPath -Destination $backupFile -Force -ErrorAction SilentlyContinue
    }

    # Write proposed content to roadmap file
    Write-HostLog ("[TRACE] roadmap.repair.apply write repoName={0} path={1} previewId={2}" -f $RepoName, $effectiveRoadmapPath, $PreviewId)
    Set-Content -LiteralPath $effectiveRoadmapPath -Value $ProposedContent -Encoding UTF8

    # Invalidate roadmap and audit caches so next fetch reflects the new file
    Clear-RoadmapCache
    Clear-RoadmapAuditCache

    $appliedAt = (Get-Date).ToUniversalTime().ToString('o')

    # Persist apply event to history
    Save-RoadmapRepairHistoryEntry `
        -PreviewId            $PreviewId `
        -RepoName             $RepoName `
        -RoadmapPath          $effectiveRoadmapPath `
        -PreviewState         'applied' `
        -OriginalMaturityLevel $OriginalMaturityLevel `
        -Event                'apply' `
        -AppliedAt            $appliedAt

    Write-HostLog ("[TRACE] roadmap.repair.apply done repoName={0} appliedAt={1}" -f $RepoName, $appliedAt)

    return [pscustomobject]@{
        repoName      = $RepoName
        roadmapPath   = $effectiveRoadmapPath
        previewId     = $PreviewId
        appliedAt     = $appliedAt
        backupPath    = $backupFile
    }
}

function Get-DocAuditCacheFilePath {
    $cacheDir = Join-Path $WorkspaceRoot 'backend\modules\output\cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Path $cacheDir -Force
    }
    return Join-Path $cacheDir 'docs-audit-cache.json'
}

function Get-DocAuditCacheTtlSeconds {
    param([hashtable]$Settings)
    $ttl = $script:DocAuditCacheDefaultTtlSeconds
    if (
        $null -ne $Settings -and
        $Settings.ContainsKey('docAudit') -and
        $Settings.docAudit -is [System.Collections.IDictionary] -and
        $Settings.docAudit.ContainsKey('scanCacheTtlSeconds') -and
        $Settings.docAudit.scanCacheTtlSeconds
    ) {
        $candidate = [int]$Settings.docAudit.scanCacheTtlSeconds
        if ($candidate -ge 0) { $ttl = $candidate }
    }
    return $ttl
}

function Get-DocAuditFromCache {
    param([int]$TtlSeconds)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'docaudit-global'

    if ($script:DocAuditCacheMemory.ContainsKey($key)) {
        $entry = $script:DocAuditCacheMemory[$key]
        $age = (($nowUtc) - [datetime]$entry.CreatedAtUtc).TotalSeconds
        if ($age -le $TtlSeconds) {
            return [pscustomobject]@{ hit = $true; source = 'memory'; ageSeconds = $age; cachedAt = ([datetime]$entry.CreatedAtUtc).ToString('o'); entries = $entry.Entries; auditedAt = $entry.AuditedAt }
        }
    }

    $cacheFile = Get-DocAuditCacheFilePath
    if (-not (Test-Path -LiteralPath $cacheFile)) { return [pscustomobject]@{ hit = $false } }

    try {
        $raw = Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ hit = $false } }
        $disk = ConvertFrom-JsonCompat -Json $raw
        if ($null -eq $disk -or -not $disk.ContainsKey('createdAtUtc')) { return [pscustomobject]@{ hit = $false } }
        $created = [datetime]$disk.createdAtUtc
        $age = (($nowUtc) - $created).TotalSeconds
        if ($age -gt $TtlSeconds) { return [pscustomobject]@{ hit = $false } }
        $script:DocAuditCacheMemory[$key] = @{ CreatedAtUtc = $created; Entries = $disk.entries; AuditedAt = [string]$disk.auditedAt }
        return [pscustomobject]@{ hit = $true; source = 'disk'; ageSeconds = $age; cachedAt = $created.ToString('o'); entries = $disk.entries; auditedAt = [string]$disk.auditedAt }
    }
    catch { return [pscustomobject]@{ hit = $false } }
}

function Save-DocAuditCache {
    param([array]$Entries, [string]$AuditedAt)
    $nowUtc = (Get-Date).ToUniversalTime()
    $key = 'docaudit-global'
    $script:DocAuditCacheMemory[$key] = @{ CreatedAtUtc = $nowUtc; Entries = $Entries; AuditedAt = $AuditedAt }
    try {
        $cacheFile = Get-DocAuditCacheFilePath
        (@{ createdAtUtc = $nowUtc.ToString('o'); auditedAt = $AuditedAt; entries = $Entries } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cacheFile -Encoding UTF8
    }
    catch { Write-HostLog ("DocAudit cache write skipped: {0}" -f $_.Exception.Message) }
}

function Clear-DocAuditCache {
    $script:DocAuditCacheMemory = @{}
    try {
        $cacheFile = Get-DocAuditCacheFilePath
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-HostLog ("DocAudit cache clear skipped: {0}" -f $_.Exception.Message) }
}

function Invoke-DocAuditScan {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter()]
        [int]$MaxDepth = 3
    )

    $standardsPath = Join-Path $WorkspaceRoot 'backend\config\doc-standards.json'
    $standards = Get-DocStandards -StandardsPath $standardsPath

    # Reuse the roadmap cache to enrich audit with roadmap state (avoid double scan)
    $settings = Get-HostSettings
    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCached = Get-RoadmapFromCache -TtlSeconds $ttlSeconds
    $roadmapEntries = if ($roadmapCached.hit) { @($roadmapCached.entries) } else {
        @(Invoke-RoadmapScan -LocalRoots $LocalRoots -MaxDepth $MaxDepth)
    }

    $results = Invoke-AuditRepoScan `
        -LocalRoots $LocalRoots `
        -MaxDepth $MaxDepth `
        -RoadmapEntries $roadmapEntries `
        -Standards $standards

    foreach ($r in @($results)) {
        $readinessLabel = [string]$r.dispatchReadiness
        Write-HostLog ("[TRACE] docaudit.scan repoName={0} readiness={1} critical={2} warning={3}" -f $r.repoName, $readinessLabel, $r.criticalCount, $r.warningCount)
    }

    return @($results)
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
                # Parse the roadmap content to classify state and extract next pending item
                $parseResult = $null
                try {
                    $rawContent = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                    $parseResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $file.FullName
                    Write-HostLog ("[TRACE] roadmap.parse repoName={0} state={1} pendingCount={2} completedCount={3}" -f $repoName, $parseResult.roadmapState, $parseResult.pendingCount, $parseResult.completedCount)
                    if ($parseResult.roadmapState -eq 'parse-error') {
                        Write-HostLog ("[WARN] roadmap.parse repoName={0} parseError={1}" -f $repoName, $parseResult.parseError)
                    }
                } catch {
                    Write-HostLog ("[WARN] roadmap.parse repoName={0} error={1}" -f $repoName, $_.Exception.Message)
                    $parseResult = [pscustomobject]@{
                        roadmapState    = 'parse-error'
                        pendingCount    = 0
                        completedCount  = 0
                        totalCount      = 0
                        nextPendingItem = $null
                        parseError      = $_.Exception.Message
                    }
                }

                $nextItem = $null
                if ($null -ne $parseResult -and $null -ne $parseResult.nextPendingItem) {
                    $nextItem = @{
                        text    = [string]$parseResult.nextPendingItem.text
                        section = [string]$parseResult.nextPendingItem.section
                    }
                }

                $entries.Add([pscustomobject]@{
                    repoName        = $repoName
                    repoPath        = $repoPath
                    roadmapPath     = $file.FullName
                    lastModified    = $file.LastWriteTime.ToString('o')
                    sizeBytes       = [long]$file.Length
                    roadmapState    = if ($null -ne $parseResult) { [string]$parseResult.roadmapState } else { 'parse-error' }
                    pendingCount    = if ($null -ne $parseResult) { [int]$parseResult.pendingCount    } else { 0 }
                    completedCount  = if ($null -ne $parseResult) { [int]$parseResult.completedCount  } else { 0 }
                    nextPendingItem = $nextItem
                })
            }
        }
        catch { Write-HostLog ("[TRACE] roadmap.scan root_error root={0} error={1}" -f $root, $_.Exception.Message) }
    }
    return @($entries)
}

function Get-RoadmapTaskHistory {
    param(
        [Parameter()]
        [int]$Limit = 25
    )

    $historyRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history'
    $runsPath = Join-Path $historyRoot 'runs'

    if (-not (Test-Path -LiteralPath $runsPath)) {
        return @()
    }

    $files = Get-ChildItem -Path $runsPath -Filter '*.summary.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First ([math]::Max($Limit, 1))

    $items = @()
    foreach ($file in $files) {
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $summary = ConvertFrom-JsonCompat -Json $raw
            $items += [pscustomobject]@{
                runId = [string]$summary.runId
                status = [string]$summary.status
                repository = [string]$summary.repository
                selectedTask = if ($summary.ContainsKey('selectedTask')) { [string]$summary.selectedTask } else { '' }
                roadmapPath = if ($summary.ContainsKey('roadmapPath')) { [string]$summary.roadmapPath } else { '' }
                startedAt = if ($summary.ContainsKey('startedAt')) { [string]$summary.startedAt } else { '' }
                completedAt = if ($summary.ContainsKey('completedAt')) { [string]$summary.completedAt } else { '' }
                error = if ($summary.ContainsKey('error')) { [string]$summary.error } else { '' }
                summaryPath = $file.FullName
            }
        }
        catch {
            continue
        }
    }

    return @($items)
}

function Build-CopilotTaskPacket {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RoadmapPath = '',

        [Parameter()]
        [object]$AuditEntry = $null
    )

    # Step 1: Resolve roadmap path from cache or parameter
    $settings  = Get-HostSettings
    $roadmapTtl = Get-RoadmapCacheTtlSeconds -Settings $settings
    $roadmapCache = Get-RoadmapFromCache -TtlSeconds $roadmapTtl
    $roadmapEntry = $null
    if ($roadmapCache.hit -and $roadmapCache.entries) {
        $roadmapEntry = @($roadmapCache.entries) | Where-Object { [string]$_.repoName -eq $RepoName } | Select-Object -First 1
    }

    $effectiveRoadmapPath = $RoadmapPath
    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -and $null -ne $roadmapEntry) {
        $rp = if ($roadmapEntry -is [System.Collections.IDictionary]) { $roadmapEntry['roadmapPath'] } else { $roadmapEntry.roadmapPath }
        if (-not [string]::IsNullOrWhiteSpace([string]$rp)) { $effectiveRoadmapPath = [string]$rp }
    }

    if ([string]::IsNullOrWhiteSpace($effectiveRoadmapPath) -or -not (Test-Path -LiteralPath $effectiveRoadmapPath)) {
        throw "Roadmap file not found for repo '$RepoName'. Ensure a roadmap scan has been run (GET /api/roadmap/index or POST /api/roadmap/scan) first."
    }

    # Step 2: Parse roadmap with full section context
    $rawContent = Get-Content -LiteralPath $effectiveRoadmapPath -Raw -Encoding UTF8
    $parseResult = Invoke-ParseRoadmapContent -Content $rawContent -SourcePath $effectiveRoadmapPath

    if ($parseResult.roadmapState -ne 'pending') {
        throw "Repository '$RepoName' has no pending roadmap items (state: $($parseResult.roadmapState))."
    }

    # Step 3: Extract selected item + neighboring context (preserving document order)
    $selected = $parseResult.nextPendingItem
    $allPendingInOrder = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($sec in @($parseResult.sections)) {
        $secName = [string]$sec.name
        foreach ($item in @($sec.pendingItems)) {
            $allPendingInOrder.Add([pscustomobject]@{ text = [string]$item; section = $secName })
        }
    }

    $selectedIdx = -1
    for ($i = 0; $i -lt $allPendingInOrder.Count; $i++) {
        if ($allPendingInOrder[$i].text -eq [string]$selected.text -and $allPendingInOrder[$i].section -eq [string]$selected.section) {
            $selectedIdx = $i
            break
        }
    }

    $previousItem = $null
    $followUpCandidates = @()
    if ($selectedIdx -ge 0) {
        if ($selectedIdx -gt 0) {
            $previousItem = [string]$allPendingInOrder[$selectedIdx - 1].text
        }
        $followUpCandidates = @($allPendingInOrder | Select-Object -Skip ($selectedIdx + 1) -First 3 | ForEach-Object {
            @{ text = [string]$_.text; section = [string]$_.section }
        })
    }

    # Step 4: Extract doc findings from audit entry
    $docFindings = @()
    $repoPath = ''
    $dispatchReadiness = 'ready'
    if ($null -ne $AuditEntry) {
        $docFindings = if ($AuditEntry -is [System.Collections.IDictionary]) {
            if ($AuditEntry.ContainsKey('docFindings') -and $null -ne $AuditEntry['docFindings']) { @($AuditEntry['docFindings']) } else { @() }
        } else {
            if ($null -ne $AuditEntry.PSObject -and ($AuditEntry.PSObject.Properties.Name -contains 'docFindings')) { @($AuditEntry.docFindings) } else { @() }
        }
        $repoPath = if ($AuditEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $AuditEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $AuditEntry.repoPath '') }
        $dispatchReadiness = if ($AuditEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $AuditEntry['dispatchReadiness'] 'ready') } else { [string](Get-ValueOrDefault $AuditEntry.dispatchReadiness 'ready') }
    } elseif ($null -ne $roadmapEntry) {
        $repoPath = if ($roadmapEntry -is [System.Collections.IDictionary]) { [string](Get-ValueOrDefault $roadmapEntry['repoPath'] '') } else { [string](Get-ValueOrDefault $roadmapEntry.repoPath '') }
    }

    # Step 5: Build acceptance criteria
    $acceptanceCriteria = @(
        "The selected roadmap item is implemented end-to-end with production-safe changes.",
        "All affected tests pass and no new test failures are introduced.",
        "Documentation updated to reflect the change (README, CHANGELOG, relevant docs).",
        "Roadmap checkbox for the completed item is marked `- [x]` in $([System.IO.Path]::GetFileName($effectiveRoadmapPath)).",
        "No placeholder stubs or TODO comments left in modified code."
    )
    $criticalFindings = @($docFindings | Where-Object {
        $sev = if ($_ -is [System.Collections.IDictionary]) { [string]$_['severity'] } else { [string]$_.severity }
        $sev -eq 'critical'
    })
    if ($criticalFindings.Count -gt 0) {
        $acceptanceCriteria += "Resolve the $($criticalFindings.Count) critical documentation finding(s) listed in this packet."
    }

    # Step 6: Guardrails
    $guardrails = @(
        @{ rule = "Do not introduce placeholder stub-outs or empty TODO blocks." },
        @{ rule = "Update affected documentation when any workflow or API behavior changes." },
        @{ rule = "Preserve existing launcher, logging, and API host behavior unless the selected roadmap item explicitly changes them." },
        @{ rule = "Keep all changes tightly scoped to the selected roadmap item." },
        @{ rule = "Do not silently mark roadmap items complete without fully implementing them." },
        @{ rule = "Run the relevant tests/quality gates before finalizing." }
    )

    # Step 7: Neighboring-context lines for the prompt
    $neighboringLines = ''
    if (-not [string]::IsNullOrWhiteSpace($previousItem)) {
        $neighboringLines += "`n  Previous item: $previousItem"
    }
    if ($followUpCandidates.Count -gt 0) {
        $followUpLines = @($followUpCandidates | ForEach-Object { "  - $($_['text']) (section: $($_['section']))" })
        $neighboringLines += "`n  Follow-up candidates after this item:`n" + ($followUpLines -join "`n")
    }

    # Doc findings block for prompt
    $docFindingsSummary = ''
    if ($docFindings.Count -gt 0) {
        $lines = @($docFindings | ForEach-Object {
            $sev  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['severity'] } else { [string]$_.severity }
            $file = if ($_ -is [System.Collections.IDictionary]) { [string]$_['file'] } else { [string]$_.file }
            $msg  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['message'] } else { [string]$_.message }
            $rec  = if ($_ -is [System.Collections.IDictionary]) { [string]$_['recommendedAction'] } else { [string]$_.recommendedAction }
            "  [$($sev.ToUpper())] $file`: $msg → $rec"
        })
        $docFindingsSummary = "`n`nDocumentation findings for this repository:`n" + ($lines -join "`n")
    }

    $guardrailLines = @($guardrails | ForEach-Object { "- $($_['rule'])" })
    $criteriLines   = @($acceptanceCriteria | ForEach-Object { "- $_" })

    $generatedPrompt = @"
Continue roadmap execution for repository: $RepoName

Roadmap file: $effectiveRoadmapPath
Selected section: $([string]$selected.section)
Selected task: $([string]$selected.text)$neighboringLines

Dispatch readiness: $dispatchReadiness$docFindingsSummary

Acceptance criteria:
$($criteriLines -join "`n")

Guardrails (must be respected):
$($guardrailLines -join "`n")

Execution requirements:
1. Verify the most recently completed roadmap entries are truly complete across code, tests, and docs.
2. Implement the selected task end-to-end with production-safe changes.
3. Update documentation (README, CHANGELOG, etc.) for completed work.
4. Mark the completed roadmap checkbox as ``- [x]`` in the roadmap file.
5. Run the repo's relevant tests/quality gates before finalizing.
"@

    # Step 8: Stable run ID and history paths
    $runId = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $historyRoot = Join-Path $WorkspaceRoot 'output\roadmap-task-history'
    $runsPath    = Join-Path $historyRoot 'runs'
    $null = New-Item -ItemType Directory -Path $runsPath -Force -ErrorAction SilentlyContinue

    return @{
        packetVersion      = '1.0'
        runId              = $runId
        createdAt          = (Get-Date).ToUniversalTime().ToString('o')
        repoContext        = @{
            repoName          = $RepoName
            repoPath          = $repoPath
            roadmapPath       = $effectiveRoadmapPath
            dispatchReadiness = $dispatchReadiness
        }
        selectedRoadmapItem = @{
            text         = [string]$selected.text
            section      = [string]$selected.section
            previousItem = $previousItem
            nextItem     = if ($followUpCandidates.Count -gt 0) { [string]$followUpCandidates[0]['text'] } else { $null }
        }
        followUpCandidates = @($followUpCandidates)
        docFindings        = @($docFindings)
        acceptanceCriteria = @($acceptanceCriteria)
        guardrails         = @($guardrails)
        generatedPrompt    = $generatedPrompt
        historyPath        = (Join-Path $historyRoot 'history.jsonl')
        runEventsPath      = (Join-Path $runsPath ("{0}.events.jsonl" -f $runId))
        runSummaryPath     = (Join-Path $runsPath ("{0}.summary.json" -f $runId))
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)
$listener.Start()
Write-HostLog ("Repo Management API host started on http://{0}:{1}" -f $BindAddress, $Port)
Write-HostLog ("Ops log: {0}" -f (Get-ValueOrDefault $script:OpsLogPath '(none)'))

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

            if ($req.Method -eq 'GET' -and $path -like '/api/reports/*') {
                $reportName = [System.IO.Path]::GetFileName([System.Uri]::UnescapeDataString($path.Substring('/api/reports/'.Length)))
                $reportsRoot = Get-ReportsRootPath
                $reportPath = Join-Path $reportsRoot $reportName

                if ([string]::IsNullOrWhiteSpace($reportName) -or -not (Test-Path -LiteralPath $reportPath)) {
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-ErrorJson -Stream $req.Stream -StatusCode 404 -ErrorMessage 'Report file not found.' -CorrelationId $correlationId -Operation 'reports.open'
                    $client.Close()
                    continue
                }

                $contentType = switch ([System.IO.Path]::GetExtension($reportPath).ToLowerInvariant()) {
                    '.html' { 'text/html; charset=utf-8' }
                    '.csv' { 'text/csv; charset=utf-8' }
                    default { 'application/octet-stream' }
                }

                Add-MetricCounter -Name 'api_requests_total'
                Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                Send-HttpContent -Stream $req.Stream -StatusCode 200 -ContentType $contentType -CorrelationId $correlationId -BodyBytes ([System.IO.File]::ReadAllBytes($reportPath))
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
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{ status = if ($healthy) { 'ready' } else { 'degraded' }; checks = $checks }
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
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
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
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultMaxDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 2 }
                    $defaultIncludeNonGit = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('includeNonGitFolders')) { [bool]$settings.inventory.includeNonGitFolders } else { $false }
                    $configuredGitHubUser = if ($settings.ContainsKey('reconcile') -and $settings.reconcile.ContainsKey('gitHubOwner') -and $settings.reconcile.gitHubOwner) { [string]$settings.reconcile.gitHubOwner } else { '' }

                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultMaxDepth }
                    $includeNonGit = if ($q.ContainsKey('includeNonGitFolders')) { Parse-Bool -Value $q.includeNonGitFolders -Default $defaultIncludeNonGit } else { $defaultIncludeNonGit }
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    # stale=true: return disk cache immediately regardless of TTL (stale-while-revalidate)
                    $stale = if ($q.ContainsKey('stale')) { Parse-Bool -Value $q.stale -Default $false } else { $false }
                    $ttlSeconds = Get-StatusCacheTtlSeconds -Settings $settings
                    $cacheKey = Get-StatusCacheKey -LocalRoots $localRoots -MaxDepth $maxDepth -IncludeNonGitFolders $includeNonGit

                    $result = $null
                    if (-not $refresh) {
                        # With stale=true we bypass TTL; otherwise only hit cache when TTL > 0
                        if ($stale -or ($ttlSeconds -gt 0)) {
                            $cacheHit = Get-StatusFromCache -Key $cacheKey -TtlSeconds $ttlSeconds -IgnoreTtl:$stale
                            if ($cacheHit.hit) {
                                $result = Add-StatusCacheMeta -Result $cacheHit.response -CacheMeta (Get-StatusCacheMeta -Hit $true -Source $cacheHit.source -TtlSeconds $ttlSeconds -AgeSeconds $cacheHit.ageSeconds -BypassRequested:$false -CachedAt $cacheHit.cachedAt)
                            }
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

                    if ($null -eq $result.meta) {
                        $result | Add-Member -NotePropertyName meta -NotePropertyValue @{} -Force
                    }
                    $result.meta.workspacePath = if (@($localRoots).Count -gt 0) { [string]$localRoots[0] } else { '' }
                    $result.meta.configuredGithubUser = $configuredGitHubUser

                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode $(if ($result.success) { 200 } else { 500 }) -CorrelationId $correlationId -Payload $result
                }
                'POST /api/reconcile' {
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
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
                    $body = Parse-JsonBody -Body $req.Body
                    $repos = if ($body.ContainsKey('repos') -and $body.repos) { @($body.repos) } else { @() }
                    $sourceLabel = if ($body.ContainsKey('sourceLabel') -and $body.sourceLabel) { [string]$body.sourceLabel } else { 'Repository dashboard export' }
                    $result = Export-RepoStatusReports -Repos $repos -SourceLabel $sourceLabel
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $result
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
                    $includePrivate = if ($body.ContainsKey('includePrivate')) { [bool]$body.includePrivate } else { $true }
                    $includeForks = if ($body.ContainsKey('includeForks')) { [bool]$body.includeForks } else { $false }
                    $includeArchived = if ($body.ContainsKey('includeArchived')) { [bool]$body.includeArchived } else { $true }
                    $fetchExtendedMetrics = if ($body.ContainsKey('fetchExtendedMetrics')) { [bool]$body.fetchExtendedMetrics } else { $true }
                    if ([string]::IsNullOrWhiteSpace($owner)) {
                        throw 'githubUser is required for /api/github/status'
                    }
                    $requestToken = if ($body.ContainsKey('apiKey') -and $body.apiKey) { [string]$body.apiKey } else { '' }
                    $token = Get-ConfiguredGitHubToken -Settings $settings -RequestToken $requestToken

                    if (-not [string]::IsNullOrWhiteSpace($token)) {
                        $apiResult = Get-GitHubReposViaApi -Owner $owner -Token $token -RepoLimit $limit -IncludePrivate:$includePrivate -IncludeForks:$includeForks -IncludeArchived:$includeArchived -FetchCommitMetrics:$fetchExtendedMetrics
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload $apiResult
                        break
                    }

                    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
                        throw 'GitHub token not configured and GitHub CLI (gh) is not available.'
                    }

                    $openPrCounts = @{}
                    try {
                        $openPrCounts = Get-GitHubOpenPrCountsViaGh -Owner $owner
                    }
                    catch {
                        Write-HostLog ("[TRACE] github.openpr gh aggregation failed owner={0} error={1}" -f $owner, $_.Exception.Message)
                    }

                    $json = (& gh repo list $owner --limit $limit --json name,nameWithOwner,url,isArchived,isPrivate,isFork,defaultBranchRef,updatedAt,pushedAt 2>&1) | Out-String
                    $reposRaw = $json | ConvertFrom-Json
                    $repos = @($reposRaw | ForEach-Object {
                        if ((-not $includeForks) -and [bool]$_.isFork) { return }
                        if ((-not $includeArchived) -and [bool]$_.isArchived) { return }

                        $repoOpenPrCount = 0
                        if ($openPrCounts.ContainsKey($_.name)) {
                            $repoOpenPrCount = [int]$openPrCounts[$_.name]
                        }

                        [pscustomobject]@{
                            name = $_.name
                            branch = if ($_.defaultBranchRef) { $_.defaultBranchRef.name } else { 'main' }
                            status = 'clean'
                            lastCommitDate = if ($_.pushedAt) { $_.pushedAt } else { $_.updatedAt }
                            lastCommitMessage = ''
                            lastCommitAuthor = $owner
                            commitsLastWeek = 0
                            commitsLastMonth = 0
                            uncommittedChanges = 0
                            isArchived = [bool]$_.isArchived
                            isStale = $false
                            localAhead = 0
                            remoteAhead = 0
                            openPrCount = $repoOpenPrCount
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
                'POST /api/roadmap-agent/preview' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repository = if ($body.ContainsKey('repository') -and $body.repository) { [string]$body.repository } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repository)) {
                        throw 'repository is required for /api/roadmap-agent/preview'
                    }

                    $baseBranch = if ($body.ContainsKey('baseBranch') -and $body.baseBranch) { [string]$body.baseBranch } else { '' }
                    $customAgent = if ($body.ContainsKey('customAgent') -and $body.customAgent) { [string]$body.customAgent } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }

                    $scriptPath = Join-Path $WorkspaceRoot 'scripts\Start-RoadmapCopilotTask.ps1'
                    $scriptArgs = @('-Repository', $repository, '-PreviewOnly')
                    if (-not [string]::IsNullOrWhiteSpace($baseBranch)) { $scriptArgs += @('-BaseBranch', $baseBranch) }
                    if (-not [string]::IsNullOrWhiteSpace($customAgent)) { $scriptArgs += @('-CustomAgent', $customAgent) }
                    if (-not [string]::IsNullOrWhiteSpace($roadmapPath)) { $scriptArgs += @('-RoadmapPath', $roadmapPath) }

                    $runResult = Invoke-PowerShellScriptFile -ScriptPath $scriptPath -Arguments $scriptArgs
                    $previewData = Get-JsonObjectFromText -Text $runResult.Output

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = $previewData
                    }
                }
                'POST /api/roadmap-agent/start' {
                    $body = Parse-JsonBody -Body $req.Body
                    $repository = if ($body.ContainsKey('repository') -and $body.repository) { [string]$body.repository } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repository)) {
                        throw 'repository is required for /api/roadmap-agent/start'
                    }

                    $baseBranch = if ($body.ContainsKey('baseBranch') -and $body.baseBranch) { [string]$body.baseBranch } else { '' }
                    $customAgent = if ($body.ContainsKey('customAgent') -and $body.customAgent) { [string]$body.customAgent } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    $follow = if ($body.ContainsKey('follow')) { [bool]$body.follow } else { $false }

                    $scriptPath = Join-Path $WorkspaceRoot 'scripts\Start-RoadmapCopilotTask.ps1'
                    $scriptArgs = @('-Repository', $repository)
                    if (-not [string]::IsNullOrWhiteSpace($baseBranch)) { $scriptArgs += @('-BaseBranch', $baseBranch) }
                    if (-not [string]::IsNullOrWhiteSpace($customAgent)) { $scriptArgs += @('-CustomAgent', $customAgent) }
                    if (-not [string]::IsNullOrWhiteSpace($roadmapPath)) { $scriptArgs += @('-RoadmapPath', $roadmapPath) }
                    if ($follow) { $scriptArgs += '-Follow' }

                    $runResult = Invoke-PowerShellScriptFile -ScriptPath $scriptPath -Arguments $scriptArgs
                    $historyItems = Get-RoadmapTaskHistory -Limit 1
                    $latest = if ($historyItems.Count -gt 0) { $historyItems[0] } else { $null }

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            message = 'Roadmap Copilot task initiated.'
                            output = $runResult.Output
                            latestHistory = $latest
                        }
                    }
                }
                'GET /api/roadmap-agent/history' {
                    $q = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 25 }
                    $items = Get-RoadmapTaskHistory -Limit $limit

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            items = $items
                            count = @($items).Count
                        }
                    }
                }
                'GET /api/roadmap/index' {
                    Write-HostLog ("[TRACE] roadmap.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapCacheTtlSeconds -Settings $settings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))

                    $cacheHit = $null
                    if ($useDefaultScope -and (-not $refresh) -and ($ttlSeconds -gt 0)) {
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
                        $entries = Invoke-RoadmapScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        if ($useDefaultScope) {
                            Save-RoadmapCache -Entries $entries -ScannedAt $scannedAt
                        }
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
                        $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
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
                        $content = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 -ErrorAction Stop
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
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))
                    $scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-RoadmapScan -LocalRoots $localRoots -MaxDepth $maxDepth
                    if ($useDefaultScope) {
                        Save-RoadmapCache -Entries $entries -ScannedAt $scannedAt
                    }
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
                'GET /api/roadmap/standard' {
                    Write-HostLog ("[TRACE] roadmap.standard correlationId={0} start" -f $correlationId)
                    $standard = Get-RoadmapStandard
                    Add-MetricCounter -Name 'api_requests_total'
                    if ($null -eq $standard) {
                        Write-HostLog ("[TRACE] roadmap.standard correlationId={0} not-found" -f $correlationId)
                        Send-HttpJson -Stream $req.Stream -StatusCode 404 -StatusText 'Not Found' -CorrelationId $correlationId -Payload @{
                            success = $false
                            error   = 'Roadmap standard assets not found. Ensure standards/roadmap/roadmap-audit-rules.json exists in the workspace.'
                        }
                    } else {
                        Write-HostLog ("[TRACE] roadmap.standard correlationId={0} done ruleCount={1}" -f $correlationId, $standard.ruleCount)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $standard
                        }
                    }
                }
                'GET /api/docs-audit' {
                    Write-HostLog ("[TRACE] docs-audit.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-DocAuditCacheTtlSeconds -Settings $settings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))

                    $cacheHit = $null
                    if ($useDefaultScope -and (-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-DocAuditFromCache -TtlSeconds $ttlSeconds
                    }

                    if ($null -ne $cacheHit -and $cacheHit.hit) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] docs-audit.index correlationId={0} done source=cache ageSeconds={1}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1))
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $cacheHit.entries
                                auditedAt = $cacheHit.auditedAt
                                count = @($cacheHit.entries).Count
                                cacheSource = $cacheHit.source
                                cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                            }
                        }
                    } else {
                        $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $entries = Invoke-DocAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        if ($useDefaultScope) {
                            Save-DocAuditCache -Entries $entries -AuditedAt $auditedAt
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] docs-audit.index correlationId={0} done source=fresh-scan count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data = @{
                                entries = $entries
                                auditedAt = $auditedAt
                                count = @($entries).Count
                                cacheSource = 'fresh-scan'
                                cacheAgeSeconds = 0
                            }
                        }
                    }
                }
                'POST /api/docs-audit/scan' {
                    Write-HostLog ("[TRACE] docs-audit.scan correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))
                    $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-DocAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                    if ($useDefaultScope) {
                        Save-DocAuditCache -Entries $entries -AuditedAt $auditedAt
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] docs-audit.scan correlationId={0} done count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data = @{
                            entries = $entries
                            auditedAt = $auditedAt
                            count = @($entries).Count
                            cacheSource = 'fresh-scan'
                            cacheAgeSeconds = 0
                        }
                    }
                }
                'POST /api/copilot-task/preview' {
                    Write-HostLog ("[TRACE] copilot-task.preview correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        throw 'repoName is required for /api/copilot-task/preview'
                    }

                    # Look up doc audit entry from cache (no-TTL miss is acceptable; null → packet built without findings)
                    $settings   = Get-HostSettings
                    $auditTtl   = Get-DocAuditCacheTtlSeconds -Settings $settings
                    $auditCache = Get-DocAuditFromCache -TtlSeconds $auditTtl
                    $auditEntry = $null
                    if ($auditCache.hit -and $auditCache.entries) {
                        $auditEntry = @($auditCache.entries) | Where-Object {
                            $n = if ($_ -is [System.Collections.IDictionary]) { [string]$_['repoName'] } else { [string]$_.repoName }
                            $n -eq $repoName
                        } | Select-Object -First 1
                    }

                    $packet = Build-CopilotTaskPacket -RepoName $repoName -RoadmapPath $roadmapPath -AuditEntry $auditEntry
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] copilot-task.preview correlationId={0} done repoName={1} runId={2}" -f $correlationId, $repoName, $packet.runId)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = $packet
                    }
                }
                'GET /api/copilot-task/history' {
                    $q     = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit) { [int]$q.limit } else { 25 }
                    $rawItems = Get-RoadmapTaskHistory -Limit $limit

                    $items = @($rawItems | ForEach-Object {
                        @{
                            runId       = [string]$_.runId
                            status      = [string]$_.status
                            repoName    = [string]$_.repository
                            roadmapItem = [string]$_.selectedTask
                            roadmapPath = [string]$_.roadmapPath
                            startedAt   = [string]$_.startedAt
                            completedAt = [string]$_.completedAt
                            error       = [string]$_.error
                            summaryPath = [string]$_.summaryPath
                        }
                    })

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            items = $items
                            count = @($items).Count
                        }
                    }
                }
                'GET /api/roadmap/audit' {
                    Write-HostLog ("[TRACE] roadmap.audit.index correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $refresh = if ($q.ContainsKey('refresh')) { Parse-Bool -Value $q.refresh -Default $false } else { $false }
                    $settings = Get-HostSettings
                    $ttlSeconds = Get-RoadmapAuditCacheTtlSeconds -Settings $settings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($q.ContainsKey('localRoots') -and $q.localRoots) { @($q.localRoots -split ';|,') } else { $defaultRoots }
                    $maxDepth = if ($q.ContainsKey('maxDepth') -and $q.maxDepth) { [int]$q.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))

                    $cacheHit = $null
                    if ($useDefaultScope -and (-not $refresh) -and ($ttlSeconds -gt 0)) {
                        $cacheHit = Get-RoadmapAuditFromCache -TtlSeconds $ttlSeconds
                    }

                    if ($null -ne $cacheHit -and $cacheHit.hit) {
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.audit.index correlationId={0} done source=cache ageSeconds={1}" -f $correlationId, [math]::Round($cacheHit.ageSeconds, 1))
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success   = $true
                            data      = @{
                                entries       = $cacheHit.entries
                                auditedAt     = $cacheHit.auditedAt
                                count         = @($cacheHit.entries).Count
                                cacheSource   = $cacheHit.source
                                cacheAgeSeconds = [math]::Round($cacheHit.ageSeconds, 1)
                            }
                        }
                    } else {
                        $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                        $entries = Invoke-RoadmapAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        if ($useDefaultScope) {
                            Save-RoadmapAuditCache -Entries $entries -AuditedAt $auditedAt
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                        Write-HostLog ("[TRACE] roadmap.audit.index correlationId={0} done source=fresh-scan count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                entries         = $entries
                                auditedAt       = $auditedAt
                                count           = @($entries).Count
                                cacheSource     = 'fresh-scan'
                                cacheAgeSeconds = 0
                            }
                        }
                    }
                }
                'POST /api/roadmap/audit/scan' {
                    Write-HostLog ("[TRACE] roadmap.audit.scan correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $settings = Get-HostSettings
                    $defaultRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                    $defaultDepth = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 3 }
                    $localRoots = if ($body.ContainsKey('localRoots') -and $body.localRoots) { @($body.localRoots) } else { $defaultRoots }
                    $maxDepth = if ($body.ContainsKey('maxDepth') -and $body.maxDepth) { [int]$body.maxDepth } else { $defaultDepth }
                    $useDefaultScope = ($maxDepth -eq $defaultDepth) -and ((@($localRoots) -join '|') -eq (@($defaultRoots) -join '|'))
                    $auditedAt = (Get-Date).ToUniversalTime().ToString('o')
                    $entries = Invoke-RoadmapAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                    if ($useDefaultScope) {
                        Save-RoadmapAuditCache -Entries $entries -AuditedAt $auditedAt
                    }
                    Add-MetricCounter -Name 'api_requests_total'
                    Add-MetricHistogramValue -Name 'api_request_duration_ms' -Value ([double]((Get-Date) - $requestStart).TotalMilliseconds)
                    Write-HostLog ("[TRACE] roadmap.audit.scan correlationId={0} done count={1} durationMs={2}" -f $correlationId, @($entries).Count, [int]((Get-Date) - $requestStart).TotalMilliseconds)
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            entries         = $entries
                            auditedAt       = $auditedAt
                            count           = @($entries).Count
                            cacheSource     = 'fresh-scan'
                            cacheAgeSeconds = 0
                        }
                    }
                }
                'POST /api/roadmap/repair/preview' {
                    Write-HostLog ("[TRACE] roadmap.repair.preview correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName = if ($body.ContainsKey('repoName') -and $body.repoName) { [string]$body.repoName } else { '' }
                    $roadmapPath = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath) { [string]$body.roadmapPath } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ error = 'repoName is required for /api/roadmap/repair/preview' }
                    } else {
                        $preview = Build-RoadmapRepairPreview -RepoName $repoName -RoadmapPath $roadmapPath
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] roadmap.repair.preview correlationId={0} done repoName={1} previewId={2} previewState={3}" -f $correlationId, $repoName, $preview.previewId, $preview.previewState)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $preview
                        }
                    }
                }
                'POST /api/roadmap/repair/apply' {
                    Write-HostLog ("[TRACE] roadmap.repair.apply correlationId={0} start" -f $correlationId)
                    $body = Parse-JsonBody -Body $req.Body
                    $repoName       = if ($body.ContainsKey('repoName') -and $body.repoName)             { [string]$body.repoName }             else { '' }
                    $previewId      = if ($body.ContainsKey('previewId') -and $body.previewId)           { [string]$body.previewId }            else { '' }
                    $proposedContent = if ($body.ContainsKey('proposedContent') -and $body.proposedContent) { [string]$body.proposedContent } else { '' }
                    $roadmapPath    = if ($body.ContainsKey('roadmapPath') -and $body.roadmapPath)       { [string]$body.roadmapPath }          else { '' }
                    $origLevel      = if ($body.ContainsKey('originalMaturityLevel') -and $body.originalMaturityLevel) { [string]$body.originalMaturityLevel } else { '' }
                    if ([string]::IsNullOrWhiteSpace($repoName) -or [string]::IsNullOrWhiteSpace($previewId) -or [string]::IsNullOrWhiteSpace($proposedContent)) {
                        Send-HttpJson -Stream $req.Stream -StatusCode 400 -StatusText 'Bad Request' -CorrelationId $correlationId -Payload @{ error = 'repoName, previewId, and proposedContent are required for /api/roadmap/repair/apply' }
                    } else {
                        $result = Apply-RoadmapRepair -RepoName $repoName -PreviewId $previewId -ProposedContent $proposedContent -RoadmapPath $roadmapPath -OriginalMaturityLevel $origLevel
                        Add-MetricCounter -Name 'api_requests_total'
                        Write-HostLog ("[TRACE] roadmap.repair.apply correlationId={0} done repoName={1} previewId={2} appliedAt={3}" -f $correlationId, $repoName, $previewId, $result.appliedAt)
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    }
                }
                'GET /api/roadmap/repair/history' {
                    Write-HostLog ("[TRACE] roadmap.repair.history correlationId={0} start" -f $correlationId)
                    $q = Parse-QueryString -Query $req.Query
                    $limit = if ($q.ContainsKey('limit') -and $q.limit -match '^\d+$') { [int]$q.limit } else { 25 }
                    if ($limit -gt 100) { $limit = 100 }
                    $historyItems = Get-RoadmapRepairHistory -Limit $limit
                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        data    = @{
                            items = @($historyItems)
                            count = @($historyItems).Count
                        }
                    }
                }
                # -------------------------------------------------------
                # Release 1.0 — Execution Queue API Routes
                # -------------------------------------------------------
                'GET /api/execution/queue' {
                    Write-HostLog ("[TRACE] execution.queue correlationId={0} start" -f $correlationId)
                    try {
                        $queueSummary = Get-ExecutionQueueSummary -WorkspaceRoot $WorkspaceRoot
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $queueSummary
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.queue'
                    }
                }
                'POST /api/execution/sync' {
                    Write-HostLog ("[TRACE] execution.sync correlationId={0} start" -f $correlationId)
                    try {
                        # Sync ledger from current cached doc-audit + roadmap-audit data
                        $settings = Get-HostSettings
                        $localRoots = Get-ConfiguredLocalRootsOrWorkspace -Settings $settings
                        $maxDepth   = if ($settings.ContainsKey('inventory') -and $settings.inventory.ContainsKey('maxDepth') -and $settings.inventory.maxDepth) { [int]$settings.inventory.maxDepth } else { 2 }

                        # Load doc-audit (use cache if available)
                        $docAuditResult = $null
                        try {
                            $docAuditResult = Invoke-DocAuditScan -LocalRoots $localRoots -MaxDepth $maxDepth
                        } catch { $docAuditResult = $null }

                        $docEntries = if ($null -ne $docAuditResult -and $null -ne $docAuditResult.entries) { @($docAuditResult.entries) } else { @() }

                        # Load roadmap-audit from cache if available
                        $roadmapAuditEntries = @()
                        $cachedAudit = $script:RoadmapAuditCacheMemory
                        if ($null -ne $cachedAudit -and $cachedAudit.ContainsKey('entries')) {
                            $roadmapAuditEntries = @($cachedAudit.entries)
                        }

                        $syncedLedger = Sync-LedgerFromAudit -WorkspaceRoot $WorkspaceRoot -DocAuditEntries $docEntries -RoadmapAuditEntries $roadmapAuditEntries
                        $queueSummary = Get-ExecutionQueueSummary -WorkspaceRoot $WorkspaceRoot

                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $queueSummary
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.sync'
                    }
                }
                'POST /api/execution/assign' {
                    Write-HostLog ("[TRACE] execution.assign correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName = if ($body -and $body.repoName) { [string]$body.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/assign'
                        }
                        $runId      = if ($body -and $body.runId)      { [string]$body.runId      } else { '' }
                        $taskText   = if ($body -and $body.taskText)    { [string]$body.taskText   } else { '' }
                        $taskSection = if ($body -and $body.taskSection) { [string]$body.taskSection } else { '' }

                        $result = Invoke-AssignLane -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -RunId $runId -TaskText $taskText -TaskSection $taskSection
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ laneSlot = $result.laneSlot; runId = $result.runId; entry = $result.entry } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.assign'
                    }
                }
                'POST /api/execution/complete' {
                    Write-HostLog ("[TRACE] execution.complete correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName = if ($body -and $body.repoName) { [string]$body.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/complete'
                        }
                        $outcome          = if ($body -and $body.outcome)          { [string]$body.outcome }          else { 'success' }
                        $hasRemainingWork = if ($body -and $null -ne $body.hasRemainingWork) { [bool]$body.hasRemainingWork } else { $false }

                        $result = Invoke-CompleteTask -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Outcome $outcome -HasRemainingWork $hasRemainingWork
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ newState = $result.newState } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.complete'
                    }
                }
                'POST /api/execution/cancel' {
                    Write-HostLog ("[TRACE] execution.cancel correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName = if ($body -and $body.repoName) { [string]$body.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/cancel'
                        }
                        $reason     = if ($body -and $body.reason)     { [string]$body.reason }     else { 'cancelled' }
                        $maxRetries = if ($body -and $body.maxRetries) { [int]$body.maxRetries }     else { 3 }

                        $result = Invoke-CancelTask -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Reason $reason -MaxRetries $maxRetries
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ newState = $result.newState; retryCount = $result.retryCount } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.cancel'
                    }
                }
                'POST /api/execution/requeue' {
                    Write-HostLog ("[TRACE] execution.requeue correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName = if ($body -and $body.repoName) { [string]$body.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/execution/requeue'
                        }
                        $force = if ($body -and $null -ne $body.force) { [bool]$body.force } else { $false }

                        $result = Invoke-RequeueRepo -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -Force $force
                        $statusCode = if ($result.success) { 200 } else { 409 }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode $statusCode -CorrelationId $correlationId -Payload @{
                            success = $result.success
                            data    = if ($result.success) { @{ newState = $result.newState } } else { $null }
                            error   = if (-not $result.success) { @{ message = $result.error } } else { $null }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'execution.requeue'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Roadmap Linting
                # -------------------------------------------------------
                'GET /api/roadmap/lint' {
                    Write-HostLog ("[TRACE] roadmap.lint correlationId={0} start" -f $correlationId)
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $repoName = if ($q.ContainsKey('repoName') -and $q.repoName) { [string]$q.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName query parameter is required'
                        }
                        # Load roadmap content from index cache
                        $roadmapPath = $null
                        $rawContent  = ''
                        $roadmapIndexEntries = @()
                        if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                            $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                        }
                        $entry = $roadmapIndexEntries | Where-Object { $_.repoName -eq $repoName } | Select-Object -First 1
                        if ($null -ne $entry -and $entry.roadmapPath -and (Test-Path -LiteralPath $entry.roadmapPath)) {
                            $roadmapPath = $entry.roadmapPath
                            $rawContent  = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                            if ($null -eq $rawContent) { $rawContent = '' }
                        }
                        $lintResult = Invoke-LintRoadmapContent -RawContent $rawContent -RepoName $repoName
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $lintResult
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.lint'
                    }
                }
                'POST /api/roadmap/lint/scan' {
                    Write-HostLog ("[TRACE] roadmap.lint.scan correlationId={0} start" -f $correlationId)
                    try {
                        $results = [System.Collections.Generic.List[object]]::new()
                        $roadmapIndexEntries = @()
                        if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                            $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                        }
                        foreach ($entry in $roadmapIndexEntries) {
                            $rawContent = ''
                            if ($entry.roadmapPath -and (Test-Path -LiteralPath $entry.roadmapPath)) {
                                try {
                                    $rawContent = Get-Content -LiteralPath $entry.roadmapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                                    if ($null -eq $rawContent) { $rawContent = '' }
                                } catch { $rawContent = '' }
                            }
                            $lintResult = Invoke-LintRoadmapContent -RawContent $rawContent -RepoName $entry.repoName
                            $results.Add($lintResult)
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success   = $true
                            data      = @{
                                results   = @($results)
                                count     = $results.Count
                                scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.lint.scan'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — README Standardization
                # -------------------------------------------------------
                'POST /api/readme/standardize/preview' {
                    Write-HostLog ("[TRACE] readme.standardize.preview correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName = if ($body -and $body.repoName) { [string]$body.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) {
                            throw 'repoName is required for /api/readme/standardize/preview'
                        }
                        $repoPath = if ($body -and $body.repoPath) { [string]$body.repoPath } else { '' }

                        # Try to find repo path from roadmap index if not provided
                        if ([string]::IsNullOrWhiteSpace($repoPath)) {
                            $roadmapIndexEntries = @()
                            if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                                $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                            }
                            $indexEntry = $roadmapIndexEntries | Where-Object { $_.repoName -eq $repoName } | Select-Object -First 1
                            if ($null -ne $indexEntry -and $indexEntry.repoPath) {
                                $repoPath = $indexEntry.repoPath
                            }
                        }

                        $preview = Invoke-PreviewReadmeStandardization -RepoName $repoName -RepoPath $repoPath
                        Write-HostLog ("[TRACE] readme.standardize.preview repoName={0} previewState={1}" -f $repoName, $preview.previewState)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $preview
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.standardize.preview'
                    }
                }
                'POST /api/readme/standardize/apply' {
                    Write-HostLog ("[TRACE] readme.standardize.apply correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName       = if ($body -and $body.repoName)       { [string]$body.repoName       } else { $null }
                        $previewId      = if ($body -and $body.previewId)      { [string]$body.previewId      } else { $null }
                        $proposedContent = if ($body -and $body.proposedContent) { [string]$body.proposedContent } else { $null }
                        $repoPath       = if ($body -and $body.repoPath)       { [string]$body.repoPath       } else { '' }
                        if ([string]::IsNullOrWhiteSpace($repoName))       { throw 'repoName is required' }
                        if ([string]::IsNullOrWhiteSpace($previewId))      { throw 'previewId is required' }
                        if ([string]::IsNullOrWhiteSpace($proposedContent)) { throw 'proposedContent is required' }

                        if ([string]::IsNullOrWhiteSpace($repoPath)) {
                            $roadmapIndexEntries = @()
                            if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                                $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                            }
                            $indexEntry = $roadmapIndexEntries | Where-Object { $_.repoName -eq $repoName } | Select-Object -First 1
                            if ($null -ne $indexEntry -and $indexEntry.repoPath) {
                                $repoPath = $indexEntry.repoPath
                            }
                        }

                        $applyResult = Invoke-ApplyReadmeStandardization -RepoName $repoName -PreviewId $previewId -ProposedContent $proposedContent -RepoPath $repoPath
                        Write-HostLog ("[TRACE] readme.standardize.apply repoName={0} success={1}" -f $repoName, $applyResult.success)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $applyResult
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.standardize.apply'
                    }
                }
                'GET /api/readme/standardize/history' {
                    Write-HostLog ("[TRACE] readme.standardize.history correlationId={0} start" -f $correlationId)
                    try {
                        $q = Parse-QueryString -Query $req.Query
                        $limit = if ($q.ContainsKey('limit') -and $q.limit -match '^\d+$') { [int]$q.limit } else { 25 }
                        if ($limit -gt 200) { $limit = 200 }
                        $historyPath = Join-Path $WorkspaceRoot 'output\readme-standardization-history\standardization-history.jsonl'
                        $items = [System.Collections.Generic.List[object]]::new()
                        if (Test-Path -LiteralPath $historyPath) {
                            $lines = Get-Content -LiteralPath $historyPath -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last $limit
                            foreach ($line in $lines) {
                                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                                try { $items.Add(($line | ConvertFrom-Json)) } catch { }
                            }
                        }
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{ items = @($items); count = $items.Count }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'readme.standardize.history'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Contract Drift Alerts
                # -------------------------------------------------------
                'GET /api/roadmap/drift' {
                    Write-HostLog ("[TRACE] roadmap.drift correlationId={0} start" -f $correlationId)
                    try {
                        $roadmapAuditEntries = @()
                        $cachedAudit = $script:RoadmapAuditCacheMemory
                        if ($null -ne $cachedAudit -and $cachedAudit.ContainsKey('entries')) {
                            $roadmapAuditEntries = @($cachedAudit.entries)
                        }
                        $driftResult = Get-MaturityDrift -WorkspaceRoot $WorkspaceRoot -CurrentAuditEntries $roadmapAuditEntries
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $driftResult
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.drift'
                    }
                }
                'POST /api/roadmap/drift/baseline' {
                    Write-HostLog ("[TRACE] roadmap.drift.baseline correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName    = if ($body -and $body.repoName)    { [string]$body.repoName    } else { $null }
                        $targetLevel = if ($body -and $body.targetLevel) { [string]$body.targetLevel } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName))    { throw 'repoName is required' }
                        if ([string]::IsNullOrWhiteSpace($targetLevel)) { throw 'targetLevel is required' }
                        $result = Set-MaturityBaseline -WorkspaceRoot $WorkspaceRoot -RepoName $repoName -TargetLevel $targetLevel
                        Write-HostLog ("[TRACE] roadmap.drift.baseline repoName={0} targetLevel={1}" -f $repoName, $targetLevel)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.drift.baseline'
                    }
                }
                'POST /api/roadmap/drift/acknowledge' {
                    Write-HostLog ("[TRACE] roadmap.drift.acknowledge correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName = if ($body -and $body.repoName) { [string]$body.repoName } else { $null }
                        if ([string]::IsNullOrWhiteSpace($repoName)) { throw 'repoName is required' }
                        $result = Confirm-MaturityDriftAcknowledged -WorkspaceRoot $WorkspaceRoot -RepoName $repoName
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.drift.acknowledge'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Notification Webhooks
                # -------------------------------------------------------
                'GET /api/notifications/webhooks' {
                    Write-HostLog ("[TRACE] notifications.webhooks.get correlationId={0} start" -f $correlationId)
                    try {
                        $webhooks = Get-NotificationWebhooks -WorkspaceRoot $WorkspaceRoot
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{ webhooks = @($webhooks); count = @($webhooks).Count }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 500 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'notifications.webhooks.get'
                    }
                }
                'POST /api/notifications/webhooks' {
                    Write-HostLog ("[TRACE] notifications.webhooks.register correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $webhookUrl = if ($body -and $body.url)    { [string]$body.url    } else { $null }
                        $label      = if ($body -and $body.label)  { [string]$body.label  } else { '' }
                        $events     = if ($body -and $body.events) { @($body.events)       } else { @() }
                        if ([string]::IsNullOrWhiteSpace($webhookUrl)) { throw 'url is required' }
                        $result = Register-NotificationWebhook -WorkspaceRoot $WorkspaceRoot -WebhookUrl $webhookUrl -Events $events -Label $label
                        Write-HostLog ("[TRACE] notifications.webhooks.register id={0} url={1}" -f $result.id, $webhookUrl)
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'notifications.webhooks.register'
                    }
                }
                'POST /api/notifications/webhooks/remove' {
                    Write-HostLog ("[TRACE] notifications.webhooks.remove correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $webhookId = if ($body -and $body.id) { [string]$body.id } else { $null }
                        if ([string]::IsNullOrWhiteSpace($webhookId)) { throw 'id is required' }
                        $result = Remove-NotificationWebhook -WorkspaceRoot $WorkspaceRoot -WebhookId $webhookId
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = $result
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'notifications.webhooks.remove'
                    }
                }
                # -------------------------------------------------------
                # Release 1.1 — Roadmap Completion Update Preview
                # -------------------------------------------------------
                'POST /api/roadmap/completion-preview' {
                    Write-HostLog ("[TRACE] roadmap.completion-preview correlationId={0} start" -f $correlationId)
                    try {
                        $body = $req.Body
                        $repoName        = if ($body -and $body.repoName)        { [string]$body.repoName        } else { $null }
                        $completedItems  = if ($body -and $body.completedItems)  { @($body.completedItems)        } else { @() }
                        if ([string]::IsNullOrWhiteSpace($repoName)) { throw 'repoName is required' }

                        # Load current roadmap content
                        $roadmapPath = $null
                        $rawContent  = ''
                        $roadmapIndexEntries = @()
                        if ($null -ne $script:RoadmapCacheMemory -and $script:RoadmapCacheMemory.ContainsKey('entries')) {
                            $roadmapIndexEntries = @($script:RoadmapCacheMemory.entries)
                        }
                        $indexEntry = $roadmapIndexEntries | Where-Object { $_.repoName -eq $repoName } | Select-Object -First 1
                        if ($null -ne $indexEntry -and $indexEntry.roadmapPath -and (Test-Path -LiteralPath $indexEntry.roadmapPath)) {
                            $roadmapPath = $indexEntry.roadmapPath
                            $rawContent  = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                            if ($null -eq $rawContent) { $rawContent = '' }
                        }

                        if ([string]::IsNullOrWhiteSpace($rawContent)) {
                            throw "No roadmap content found for repo '$repoName'"
                        }

                        # Mark completedItems as done: replace `- [ ] {itemText}` with `- [x] {itemText}`
                        $proposedContent = $rawContent
                        $markedCount = 0
                        foreach ($itemText in $completedItems) {
                            if ([string]::IsNullOrWhiteSpace($itemText)) { continue }
                            $escaped = [regex]::Escape($itemText.Trim())
                            $pattern = "(?m)^(\s*)-\s+\[\s\]\s+" + $escaped
                            if ($proposedContent -match $pattern) {
                                $proposedContent = $proposedContent -replace $pattern, ('$1- [x] ' + $itemText.Trim())
                                $markedCount++
                            }
                        }

                        $previewId = [guid]::NewGuid().ToString('n')
                        Add-MetricCounter -Name 'api_requests_total'
                        Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                            success = $true
                            data    = @{
                                previewId        = $previewId
                                repoName         = $repoName
                                roadmapPath      = $roadmapPath
                                currentContent   = $rawContent
                                proposedContent  = $proposedContent
                                markedCount      = $markedCount
                                completedItems   = @($completedItems)
                                generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
                            }
                        }
                    } catch {
                        Send-ErrorJson -Stream $req.Stream -StatusCode 400 -ErrorMessage $_.Exception.Message -CorrelationId $correlationId -Operation 'roadmap.completion-preview'
                    }
                }
                'GET /api/log/tail' {
                    $q = Parse-QueryString -Query $req.Query
                    $maxLines = if ($q.ContainsKey('lines') -and $q.lines) { [int]$q.lines } else { 100 }
                    if ($maxLines -gt 500) { $maxLines = 500 }
                    # 'since' is epoch milliseconds from the client (Date.now())
                    $sinceMs = if ($q.ContainsKey('since') -and $q.since -match '^\d+$') { [long]$q.since } else { 0 }

                    $entries = [System.Collections.Generic.List[object]]::new()
                    if ($null -ne $script:OpsLogPath -and (Test-Path -LiteralPath $script:OpsLogPath)) {
                        try {
                            $rawLines = Get-Content -LiteralPath $script:OpsLogPath -Encoding UTF8 -ErrorAction Stop |
                                Select-Object -Last $maxLines
                            foreach ($rawLine in $rawLines) {
                                if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
                                try {
                                    $obj = $rawLine | ConvertFrom-Json
                                    if ($sinceMs -gt 0 -and $obj.ts) {
                                        $lineMs = [long](([datetime]$obj.ts).ToUniversalTime() -
                                            [datetime]::UnixEpoch).TotalMilliseconds
                                        if ($lineMs -le $sinceMs) { continue }
                                    }
                                    $entries.Add($obj)
                                } catch { }
                            }
                        } catch { }
                    }

                    Add-MetricCounter -Name 'api_requests_total'
                    Send-HttpJson -Stream $req.Stream -StatusCode 200 -CorrelationId $correlationId -Payload @{
                        success = $true
                        entries = @($entries)
                        count = $entries.Count
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

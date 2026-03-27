<#
.SYNOPSIS
    Copilot-assisted README generation for repositories without a README.md.

.DESCRIPTION
    Provides functions to:
      - Collect repo context (file tree, entry points, key file snippets)
      - Build a structured prompt for the GitHub Copilot chat completions API
      - Call the API and return the generated README markdown
      - Persist generation history to JSONL

.NOTES
    Dot-source after Git.StatusDetail.ps1:
        . (Join-Path $readmeModuleRoot 'Readme.Generator.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ReadmeGenerationHistoryDir = 'output\readme-generation-history'
$script:ReadmeGenerationHistoryLog = 'output\readme-generation-history\generation-history.jsonl'
$script:DefaultCopilotApiUrl       = 'https://api.githubcopilot.com/chat/completions'

# ── Internal helpers ──────────────────────────────────────────────────────────

function _ResolveApiKey {
    param([pscustomobject]$Settings)

    # Priority 1: direct key in settings
    if ($Settings.PSObject.Properties['readme']) {
        $readmeCfg = $Settings.readme
        if ($readmeCfg.PSObject.Properties['copilotApiKey'] -and
            -not [string]::IsNullOrWhiteSpace($readmeCfg.copilotApiKey)) {
            return [string]$readmeCfg.copilotApiKey
        }

        # Priority 2: env var name in settings
        if ($readmeCfg.PSObject.Properties['copilotApiKeyEnvVar'] -and
            -not [string]::IsNullOrWhiteSpace($readmeCfg.copilotApiKeyEnvVar)) {
            $envVarName = [string]$readmeCfg.copilotApiKeyEnvVar
            $envVal = [System.Environment]::GetEnvironmentVariable($envVarName)
            if (-not [string]::IsNullOrWhiteSpace($envVal)) {
                return $envVal
            }
        }
    }

    # Priority 3: standard GitHub token env vars
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) { return $env:GITHUB_TOKEN }
    if (-not [string]::IsNullOrWhiteSpace($env:GitHub_Token))  { return $env:GitHub_Token }

    # Priority 4: gh auth token CLI
    $ghCmd = Get-Command -Name 'gh' -ErrorAction SilentlyContinue
    if ($null -ne $ghCmd) {
        $ghToken = & $ghCmd.Source auth token 2>$null
        if (-not [string]::IsNullOrWhiteSpace($ghToken)) {
            return ([string]$ghToken).Trim()
        }
    }

    return $null
}

function _BuildFileTree {
    param([string]$LocalPath)

    $skipDirs = @('.git', 'node_modules', 'bin', 'obj', 'dist', '.venv', '__pycache__', '.vs', 'packages', '.idea', 'vendor')
    $lines    = [System.Collections.Generic.List[string]]::new()

    function _Walk {
        param([string]$Dir, [int]$Depth, [string]$Prefix)
        if ($Depth -gt 3) { return }

        $entries = @(Get-ChildItem -LiteralPath $Dir -ErrorAction SilentlyContinue |
                     Where-Object { $_.PSIsContainer -notin @($false) -or $true })

        $dirEntries  = @($entries | Where-Object { $_.PSIsContainer } |
                          Where-Object { $skipDirs -notcontains $_.Name } |
                          Sort-Object Name)
        $fileEntries = @($entries | Where-Object { -not $_.PSIsContainer } |
                          Sort-Object Name)

        foreach ($d in $dirEntries) {
            $lines.Add("$Prefix$($d.Name)/")
            if ($lines.Count -lt 80) {
                _Walk -Dir $d.FullName -Depth ($Depth + 1) -Prefix "$Prefix  "
            }
        }
        foreach ($f in $fileEntries) {
            if ($lines.Count -ge 80) { break }
            $lines.Add("$Prefix$($f.Name)")
        }
    }

    _Walk -Dir $LocalPath -Depth 0 -Prefix ''
    return ($lines -join "`n")
}

function _GetRepoContext {
    param([string]$LocalPath, [string]$RepoName)

    # ── File count ────────────────────────────────────────────────────────────
    $allFiles = @(Get-ChildItem -LiteralPath $LocalPath -Recurse -File -Depth 4 -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch '[\\\/](\.git|node_modules|bin|obj|dist|\.venv|__pycache__|packages)[\\\/]' })
    $fileCount = $allFiles.Count

    # ── Repo type detection ───────────────────────────────────────────────────
    $repoType = 'other'
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'package.json')) {
        $repoType = 'node'
    } elseif (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.csproj' -ErrorAction SilentlyContinue) + @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.sln' -ErrorAction SilentlyContinue) | Select-Object -First 1) {
        $repoType = 'dotnet'
    } elseif ((Test-Path -LiteralPath (Join-Path $LocalPath 'requirements.txt')) -or
              (Test-Path -LiteralPath (Join-Path $LocalPath 'setup.py')) -or
              (Test-Path -LiteralPath (Join-Path $LocalPath 'pyproject.toml'))) {
        $repoType = 'python'
    } elseif (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1' -ErrorAction SilentlyContinue).Count -gt 0 -and
              -not (Test-Path -LiteralPath (Join-Path $LocalPath 'package.json'))) {
        $repoType = 'powershell'
    }

    # ── Entry point candidates ────────────────────────────────────────────────
    $entryPointPatterns = switch ($repoType) {
        'node'       { @('index.js', 'index.ts', 'app.js', 'app.ts', 'main.js', 'main.ts', 'src/index.ts', 'src/index.js', 'src/app.ts', 'src/app.js') }
        'dotnet'     { @('Program.cs', 'Startup.cs', 'src/Program.cs') }
        'python'     { @('main.py', 'app.py', '__main__.py', 'src/main.py') }
        'powershell' { @() }  # handled separately below
        default      { @() }
    }

    $entryPoints = [System.Collections.Generic.List[hashtable]]::new()

    if ($repoType -eq 'powershell') {
        # Find ps1 files matching common entry-point names, fall back to largest
        $ps1Files = @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
                       Sort-Object { ($_.BaseName -match 'main|start|app') ? 0 : 1 }, { -$_.Length } |
                       Select-Object -First 3)
        foreach ($f in $ps1Files) {
            $entryPointPatterns += $f.Name
        }
    }

    foreach ($pattern in $entryPointPatterns) {
        if ($entryPoints.Count -ge 3) { break }
        $fullPath = Join-Path $LocalPath $pattern
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $content = ''
            try {
                $lines = @(Get-Content -LiteralPath $fullPath -TotalCount 50 -Encoding UTF8 -ErrorAction SilentlyContinue)
                $content = $lines -join "`n"
            } catch { $content = '(could not read file)' }
            $entryPoints.Add(@{ path = $pattern; content = $content })
        }
    }

    # ── File tree ─────────────────────────────────────────────────────────────
    $fileTree = _BuildFileTree -LocalPath $LocalPath

    $entryPaths = @($entryPoints | ForEach-Object { $_.path })
    $summary = "Detected $repoType repo. Entry points: $($entryPaths -join ', '). File count: $fileCount."

    return [pscustomobject]@{
        repoType    = $repoType
        fileTree    = $fileTree
        fileCount   = $fileCount
        entryPoints = @($entryPoints)
        summary     = $summary
    }
}

function _BuildReadmePrompt {
    param([string]$RepoName, [pscustomobject]$Context)

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("You are a technical documentation expert. Based on the repository information below, write a comprehensive README.md for the `$RepoName` project.")
    $lines.Add('')
    $lines.Add('## Instructions')
    $lines.Add('')
    $lines.Add('Write a professional README.md that includes:')
    $lines.Add('1. **Project title and concise description** — what it does and why it exists')
    $lines.Add('2. **Prerequisites** — required tools, runtimes, versions')
    $lines.Add('3. **Installation** — step-by-step setup instructions with code blocks')
    $lines.Add('4. **Usage** — at least one concrete usage example with code')
    $lines.Add('5. **Configuration** — key settings or environment variables (if present in the code)')
    $lines.Add('6. **License** — brief section (if a LICENSE file exists)')
    $lines.Add('')
    $lines.Add('Be specific about the actual files and features visible in the repository. Do not invent features not evidenced by the code.')
    $lines.Add('Return ONLY the README.md markdown content — no explanatory text before or after.')
    $lines.Add('')
    $lines.Add('---')
    $lines.Add('')
    $lines.Add("## Repository: $RepoName")
    $lines.Add("**Type:** $($Context.repoType)")
    $lines.Add("**File count:** $($Context.fileCount)")
    $lines.Add('')
    $lines.Add('## File Structure')
    $lines.Add('')
    $lines.Add('```')
    $lines.Add($Context.fileTree)
    $lines.Add('```')

    foreach ($ep in $Context.entryPoints) {
        $ext = [System.IO.Path]::GetExtension($ep.path).TrimStart('.')
        $lang = switch ($ext) {
            'ts'   { 'typescript' }
            'js'   { 'javascript' }
            'cs'   { 'csharp' }
            'py'   { 'python' }
            'ps1'  { 'powershell' }
            default { $ext }
        }
        $lines.Add('')
        $lines.Add("## Entry Point: $($ep.path)")
        $lines.Add('')
        $lines.Add("``````$lang")
        $lines.Add($ep.content)
        $lines.Add('``````')
    }

    return ($lines -join "`n")
}

function _InvokeCopilotChatCompletion {
    param(
        [string]$ApiUrl,
        [string]$ApiKey,
        [string]$Prompt
    )

    $headers = @{
        'Authorization' = "Bearer $ApiKey"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    $bodyObj = [ordered]@{
        model       = 'gpt-4o'
        messages    = @(
            [ordered]@{ role = 'system'; content = 'You are a technical documentation expert who writes clear, professional README files for software projects. You produce complete, accurate documentation based on actual code evidence.' }
            [ordered]@{ role = 'user'; content = $Prompt }
        )
        max_tokens  = 2000
        temperature = 0.3
    }

    $body = $bodyObj | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod `
        -Uri         $ApiUrl `
        -Method      Post `
        -Headers     $headers `
        -Body        $body `
        -ContentType 'application/json' `
        -TimeoutSec  90 `
        -ErrorAction Stop

    $content = $response.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "Copilot API returned empty content"
    }

    # Strip any wrapping markdown code fence if the model wrapped the output
    $content = ([string]$content).Trim()
    if ($content -match '^```(?:markdown)?\r?\n([\s\S]*?)\r?\n```$') {
        $content = $Matches[1].Trim()
    }

    return $content
}

# ── Public functions ──────────────────────────────────────────────────────────

function Invoke-CopilotReadmeGeneration {
    <#
    .SYNOPSIS
        Generate a README.md for a repository using the GitHub Copilot chat API.
    .PARAMETER RepoName
        Short repository name (e.g. "MyApp").
    .PARAMETER LocalPath
        Absolute path to the local repository directory.
    .PARAMETER Settings
        Settings hashtable from Get-HostSettings.
    .OUTPUTS
        [pscustomobject] with generationId, repoName, localPath, repoType,
        contextSummary, previewContent, generatedAt.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][pscustomobject]$Settings
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        throw "LocalPath not found: $LocalPath"
    }

    # Resolve API key
    $apiKey = _ResolveApiKey -Settings $Settings
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "412: readme.copilotApiKey is not configured. Add 'readme.copilotApiKey' to Settings, set the env var named by 'readme.copilotApiKeyEnvVar', or ensure GITHUB_TOKEN is set with Copilot access."
    }

    # Resolve API URL
    $apiUrl = $script:DefaultCopilotApiUrl
    if ($Settings.PSObject.Properties['readme']) {
        $readmeCfg = $Settings.readme
        if ($readmeCfg.PSObject.Properties['copilotApiUrl'] -and
            -not [string]::IsNullOrWhiteSpace($readmeCfg.copilotApiUrl)) {
            $apiUrl = [string]$readmeCfg.copilotApiUrl
        }
    }

    # Collect repo context
    $context = _GetRepoContext -LocalPath $LocalPath -RepoName $RepoName

    # Build prompt
    $prompt = _BuildReadmePrompt -RepoName $RepoName -Context $context

    # Call Copilot API
    $generatedContent = _InvokeCopilotChatCompletion -ApiUrl $apiUrl -ApiKey $apiKey -Prompt $prompt

    $generationId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))

    return [pscustomobject]@{
        generationId   = $generationId
        repoName       = $RepoName
        localPath      = $LocalPath
        repoType       = $context.repoType
        contextSummary = $context.summary
        previewContent = $generatedContent
        generatedAt    = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Write-ReadmeGenerationHistoryEntry {
    <#
    .SYNOPSIS
        Append a generation or apply event to the README generation history JSONL.
    .PARAMETER WorkspaceRoot
        Root directory of the workspace.
    .PARAMETER Entry
        Hashtable or pscustomobject with fields to record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)]$Entry
    )

    $historyDir = Join-Path $WorkspaceRoot $script:ReadmeGenerationHistoryDir
    if (-not (Test-Path -LiteralPath $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    $historyPath = Join-Path $WorkspaceRoot $script:ReadmeGenerationHistoryLog
    $json = $Entry | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath $historyPath -Value $json -Encoding UTF8
}

function Get-ReadmeGenerationHistory {
    <#
    .SYNOPSIS
        Read the last N README generation history entries.
    .PARAMETER WorkspaceRoot
        Root directory of the workspace.
    .PARAMETER Limit
        Maximum number of entries to return (default 25, max 100).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [int]$Limit = 25
    )

    if ($Limit -lt 1)   { $Limit = 1 }
    if ($Limit -gt 100) { $Limit = 100 }

    $historyPath = Join-Path $WorkspaceRoot $script:ReadmeGenerationHistoryLog
    if (-not (Test-Path -LiteralPath $historyPath)) {
        return @()
    }

    $lines = @(Get-Content -LiteralPath $historyPath -Encoding UTF8 -ErrorAction SilentlyContinue |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $items = @($lines | Select-Object -Last $Limit | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $null -ne $_ })

    return $items
}

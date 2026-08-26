[CmdletBinding()]
param(
    [Parameter()]
    # Derived from this script's location rather than a hardcoded drive letter,
    # so the suite runs unmodified from any clone location (ROADMAP Lane 0.3).
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TrackedFiles {
    $gitArgs = @('-C', $WorkspaceRoot, 'ls-files')
    $output = & git @gitArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate tracked files with git ls-files.'
    }

    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

$trackedFiles = Get-TrackedFiles
$violations = New-Object System.Collections.Generic.List[string]

$generatedPrefixes = @(
    'backend/modules/output/',
    'output/',
    'reports/',
    'frontend/dist/',
    'frontend/node_modules/',
    '.vscode/'
)
$generatedExplicitPaths = @(
    'README.pdf',
    'docs/roadmap.pdf',
    'docs/roadmap_tmp.html'
)

foreach ($file in $trackedFiles) {
    $normalized = $file.Replace('\', '/')
    $isGeneratedPrefix = $generatedPrefixes | Where-Object { $normalized.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
    if ($isGeneratedPrefix -and -not $normalized.EndsWith('/.gitkeep', [System.StringComparison]::OrdinalIgnoreCase)) {
        $violations.Add("Tracked generated artifact: $normalized")
    }

    if ($generatedExplicitPaths -contains $normalized) {
        $violations.Add("Tracked generated export: $normalized")
    }

    # Generated evidence stays untracked; curated proof under evidence/verified/
    # is tracked deliberately. The roadmap requires a durable evidence entry per
    # operator-verified milestone, so a blanket ban made its own acceptance
    # criteria impossible to satisfy in a PR. The carve-out is one directory
    # wide: run spill under evidence/baseline/ is still a violation.
    if ($normalized.StartsWith('evidence/', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $normalized.StartsWith('evidence/verified/', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $normalized.EndsWith('/.gitkeep', [System.StringComparison]::OrdinalIgnoreCase)) {
        $violations.Add("Tracked evidence output: $normalized")
    }
}

# Secrets must never reach the public bundle or the repository. Two tripwires:
#  1. No tracked environment file except the committed example. `.env*` is
#     gitignored, but an ignore rule does not un-track a file that was forced.
#  2. `frontend/vite.config.ts` must not `define` a secret-shaped key. Every
#     `define` entry is inlined verbatim into the browser bundle, so a key
#     named *API_KEY / *SECRET / *TOKEN / *PASSWORD there is a leak by
#     construction (first seen: GEMINI_API_KEY, removed 2026-08-26).
function Get-ViteSecretDefineKey {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$ConfigText)

    $found = New-Object System.Collections.Generic.List[string]
    $defineBlock = [regex]::Match($ConfigText, '(?s)\bdefine\s*:\s*\{(.*?)\}')
    if (-not $defineBlock.Success) { return @($found) }
    foreach ($m in [regex]::Matches($defineBlock.Groups[1].Value, '[''"]([^''"]+)[''"]\s*:')) {
        $key = $m.Groups[1].Value
        if ($key -match '(?i)(api[_-]?key|secret|token|password|credential)') {
            $found.Add($key)
        }
    }
    return @($found)
}

# The detector must go red on a violating fixture before it is trusted green.
$secretFixture = "define: { 'process.env.API_KEY': JSON.stringify(env.GEMINI_API_KEY), 'process.env.APP_MODE': '""dev""' },"
$secretFixtureHits = @(Get-ViteSecretDefineKey -ConfigText $secretFixture)
if ($secretFixtureHits.Count -ne 1 -or $secretFixtureHits[0] -ne 'process.env.API_KEY') {
    throw "Vite secret-define detector did not flag its own violating fixture (hits=$($secretFixtureHits -join ','))."
}

foreach ($file in $trackedFiles) {
    $leaf = [System.IO.Path]::GetFileName($file)
    if ($leaf -like '.env*' -and $leaf -ne '.env.example') {
        $violations.Add("Tracked environment file (may hold keys): $($file.Replace('\', '/'))")
    }
}

$viteConfigPath = Join-Path $WorkspaceRoot 'frontend\vite.config.ts'
if (Test-Path -LiteralPath $viteConfigPath) {
    $viteConfigText = Get-Content -LiteralPath $viteConfigPath -Raw -Encoding UTF8
    foreach ($key in @(Get-ViteSecretDefineKey -ConfigText $viteConfigText)) {
        $violations.Add("frontend/vite.config.ts defines secret-shaped key '$key' into the public bundle.")
    }
}

$docsIndexPath = Join-Path $WorkspaceRoot 'docs\index.md'
Assert-PathExists -Path $docsIndexPath -Message "Missing docs index: $docsIndexPath"
$docsIndexContent = Get-Content -LiteralPath $docsIndexPath -Raw -Encoding UTF8
if ($docsIndexContent -match '\]\(/') {
    $violations.Add('docs/index.md contains site-root absolute markdown links.')
}

Assert-PathExists -Path (Join-Path $WorkspaceRoot 'docs\governance\repository-structure.md') -Message 'Missing governance structure policy document.'
Assert-PathExists -Path (Join-Path $WorkspaceRoot 'tests\fixtures\regression\docreview-queue.json') -Message 'Missing curated regression fixture.'

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    throw "Repository structure audit failed with $($violations.Count) violation(s)."
}

Write-Host 'Repository structure audit passed.' -ForegroundColor Green

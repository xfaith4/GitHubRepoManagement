[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement'
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

    if ($normalized.StartsWith('evidence/', [System.StringComparison]::OrdinalIgnoreCase) -and -not $normalized.EndsWith('/.gitkeep', [System.StringComparison]::OrdinalIgnoreCase)) {
        $violations.Add("Tracked evidence output: $normalized")
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

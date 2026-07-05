<#
.SYNOPSIS
    Self-contained roadmap structural audit for the roadmap-audit-action.

.DESCRIPTION
    Lightweight, dependency-free checks so the action is publishable and runs on
    any GitHub-hosted runner without the full GitHub Repo Management checkout.
    If the repo's richer validator (tools/Test-RoadmapStructure.ps1) is present,
    it is preferred; otherwise these baseline checks apply:
      - the file exists and is non-empty,
      - it declares at least one release heading,
      - it contains at least one checkbox roadmap item,
      - it has no duplicate top-level headings.

    Emits a summary and, with -FailOnError, exits non-zero on any error so the
    GitHub check run fails.
#>
[CmdletBinding()]
param(
    [string]$Path = "ROADMAP.md",
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "::error::ROADMAP not found at $Path"
    if ($FailOnError) { exit 1 } else { exit 0 }
}

# Prefer the richer validator when this action runs inside the source repo.
# From .github/actions/roadmap-audit-action, the repo tools/ dir is three up.
$richValidator = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\tools\Test-RoadmapStructure.ps1'))
if (Test-Path -LiteralPath $richValidator) {
    Write-Host "Using repo validator: $richValidator"
    $validatorArgs = @{ Path = $Path }
    if ($FailOnError) { $validatorArgs['FailOnError'] = $true }
    & $richValidator @validatorArgs
    exit $LASTEXITCODE
}

$content = Get-Content -LiteralPath $Path -Raw
$lines = Get-Content -LiteralPath $Path
$errors = [System.Collections.Generic.List[string]]::new()

if ([string]::IsNullOrWhiteSpace($content)) { $errors.Add("ROADMAP is empty") }

$releaseHeadings = @($lines | Where-Object { $_ -match '^#{1,3}\s' -and $_ -match '(?i)release\s+\d' })
if (@($releaseHeadings).Count -eq 0) { $errors.Add("no release heading found (expected a '## Release N ...' heading)") }

$checkboxItems = @($lines | Where-Object { $_ -match '^\s*[-*]\s+\[[ xX]\]\s' })
if (@($checkboxItems).Count -eq 0) { $errors.Add("no checkbox roadmap items found ('- [ ] ...' or '- [x] ...')") }

$headings = @($lines | Where-Object { $_ -match '^#{1,6}\s' } | ForEach-Object { $_.Trim() })
$dupes = @($headings | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
foreach ($d in $dupes) { $errors.Add("duplicate heading: $d") }

Write-Host ("Roadmap audit: {0} release heading(s), {1} checkbox item(s), {2} error(s)." -f @($releaseHeadings).Count, @($checkboxItems).Count, $errors.Count)
foreach ($e in $errors) { Write-Host "::error::$e" }

if ($errors.Count -gt 0 -and $FailOnError) { exit 1 }
exit 0

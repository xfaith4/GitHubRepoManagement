[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',

    [Parameter()]
    [int]$RetentionDays = 30,

    [Parameter()]
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cutoff = (Get-Date).AddDays(-1 * [math]::Abs($RetentionDays))
$paths = @(
    (Join-Path $WorkspaceRoot 'output'),
    (Join-Path $WorkspaceRoot 'backend\modules\output'),
    (Join-Path $WorkspaceRoot 'logs')
)

$removed = @()
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
    foreach ($file in $files) {
        if (-not $WhatIf) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
        $removed += $file.FullName
    }
}

[pscustomobject]@{
    cutoffDate = $cutoff.ToString('o')
    retentionDays = $RetentionDays
    whatIf = $WhatIf.IsPresent
    removedCount = $removed.Count
    removed = $removed
} | ConvertTo-Json -Depth 5

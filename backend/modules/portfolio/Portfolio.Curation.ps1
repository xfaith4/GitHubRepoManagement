<#
.SYNOPSIS
    Repository curation state helpers for Release 2.3 Phase 5A.

.DESCRIPTION
    Stores operator-authored repository curation state keyed by stable repoId.

    Primary store: SQLite (when app DB is initialized).
    Fallback/mirror: output/index/repo-curation.json.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PortfolioCurationFilePath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    return (Join-Path (Join-Path $WorkspaceRoot 'output\index') 'repo-curation.json')
}

function Get-AllowedCurationStates {
    [CmdletBinding()]
    param()

    return @('none', 'favorite', 'portfolio-candidate', 'archived-ignore')
}

function Test-ValidCurationState {
    [CmdletBinding()]
    param([Parameter()][string]$CurationState = '')

    $normalized = [string]$CurationState
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $false }
    return $normalized.ToLowerInvariant() -in (Get-AllowedCurationStates)
}

function _NormalizeRepoId {
    param([string]$RepoId)

    if ([string]::IsNullOrWhiteSpace($RepoId)) { return '' }
    return $RepoId.Trim()
}

function Get-PortfolioCurationEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    # Prefer app-db when available.
    try {
        if (Get-Command -Name 'Get-AppDbRepoCurationEntries' -ErrorAction SilentlyContinue) {
            $dbRows = Get-AppDbRepoCurationEntries
            if ($null -ne $dbRows -and $dbRows.available) {
                return ,@($dbRows.entries)
            }
        }
    } catch {
        # Fall back to file mirror.
    }

    $path = Get-PortfolioCurationFilePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = ConvertFrom-Json -InputObject $raw
        $entries = @()
        if ($null -ne $parsed -and $parsed.PSObject.Properties.Name -contains 'entries') {
            $entries = @($parsed.entries)
        }
        return @($entries)
    } catch {
        return @()
    }
}

function Get-PortfolioCurationMap {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $map = @{}
    $entries = Get-PortfolioCurationEntries -WorkspaceRoot $WorkspaceRoot
    foreach ($entry in @($entries)) {
        if ($null -eq $entry) { continue }
        $repoId = _NormalizeRepoId ([string]$entry.repoId)
        if ([string]::IsNullOrWhiteSpace($repoId)) { continue }
        $map[$repoId] = [pscustomobject]@{
            repoId        = $repoId
            curationState = [string]$entry.curationState
            updatedAt     = [string]$entry.updatedAt
            reason        = [string]$entry.reason
        }
    }

    return $map
}

function Save-PortfolioCurationFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][hashtable]$CurationMap = @{}
    )

    $path = Get-PortfolioCurationFilePath -WorkspaceRoot $WorkspaceRoot
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $rows = @($CurationMap.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object repoId)
    $payload = [pscustomobject]@{
        schemaVersion = 1
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
        count         = @($rows).Count
        entries       = @($rows)
    }
    $json = $payload | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8

    return $path
}

function Set-PortfolioRepoCurationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoId,
        [Parameter(Mandatory = $true)][string]$CurationState,
        [Parameter()][string]$Reason = ''
    )

    $normalizedRepoId = _NormalizeRepoId $RepoId
    $normalizedState = [string]$CurationState
    if (-not (Test-ValidCurationState -CurationState $normalizedState)) {
        return [pscustomobject]@{
            success = $false
            error   = "Invalid curationState '$CurationState'. Allowed: $((Get-AllowedCurationStates) -join ', ')."
        }
    }
    $normalizedState = $normalizedState.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($normalizedRepoId)) {
        return [pscustomobject]@{
            success = $false
            error   = 'repoId is required.'
        }
    }

    $updatedAt = (Get-Date).ToUniversalTime().ToString('o')

    # Best-effort SQLite primary write.
    try {
        if (Get-Command -Name 'Write-AppDbRepoCurationEntry' -ErrorAction SilentlyContinue) {
            $dbWrite = Write-AppDbRepoCurationEntry -RepoId $normalizedRepoId -CurationState $normalizedState -UpdatedAt $updatedAt -Reason $Reason
            if ($null -ne $dbWrite -and -not $dbWrite.success -and $dbWrite.reason -ne 'app-db-not-initialized') {
                return [pscustomobject]@{
                    success = $false
                    error   = "Failed to persist curation in app-db: $($dbWrite.reason)"
                }
            }
        }
    } catch {
        return [pscustomobject]@{
            success = $false
            error   = "Failed to persist curation in app-db: $($_.Exception.Message)"
        }
    }

    # Always write file mirror for portability and index-level reuse.
    $map = Get-PortfolioCurationMap -WorkspaceRoot $WorkspaceRoot
    $map[$normalizedRepoId] = [pscustomobject]@{
        repoId        = $normalizedRepoId
        curationState = $normalizedState
        updatedAt     = $updatedAt
        reason        = [string]$Reason
    }
    $mirrorPath = Save-PortfolioCurationFile -WorkspaceRoot $WorkspaceRoot -CurationMap $map

    return [pscustomobject]@{
        success = $true
        data    = [pscustomobject]@{
            repoId        = $normalizedRepoId
            curationState = $normalizedState
            updatedAt     = $updatedAt
            reason        = [string]$Reason
            mirrorPath    = $mirrorPath
        }
    }
}

function Apply-PortfolioCurationToEntries {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter()][hashtable]$CurationMap = @{}
    )

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $repoId = [string]$entry.repoId
        $curation = if (-not [string]::IsNullOrWhiteSpace($repoId) -and $CurationMap.ContainsKey($repoId)) { $CurationMap[$repoId] } else { $null }
        $state = if ($null -ne $curation) { [string]$curation.curationState } else { 'none' }
        if (-not (Test-ValidCurationState -CurationState $state)) { $state = 'none' }

        $entry | Add-Member -NotePropertyName curationState -NotePropertyValue $state -Force
        $entry | Add-Member -NotePropertyName curationUpdatedAt -NotePropertyValue $(if ($null -ne $curation) { [string]$curation.updatedAt } else { $null }) -Force
        $out.Add($entry) | Out-Null
    }

    return ,@($out)
}

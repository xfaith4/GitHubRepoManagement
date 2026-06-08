<#
.SYNOPSIS
    Maturity drift monitor for Release 1.1.
.DESCRIPTION
    Provides three exported functions:

      Set-MaturityBaseline
        Stores (or upserts) a target maturity level baseline for a repo in
        output/maturity-baselines.json.

      Get-MaturityDrift
        Compares current audit results against stored baselines and returns
        drift alerts for repos that have fallen below their target level.

      Confirm-MaturityDriftAcknowledged
        Marks a baseline entry as acknowledged so operators can suppress
        repeat alerts.

    Maturity levels (ranked ascending): L0 < L1 < L2 < L3 < L4

.NOTES
    Dot-source this file to load all three functions:
        . (Join-Path $moduleRoot 'MaturityDrift.Monitor.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:BaselinesFile   = 'output/maturity-baselines.json'
$script:MaturityRank    = @{ 'L0' = 0; 'L1' = 1; 'L2' = 2; 'L3' = 3; 'L4' = 4 }

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _GetBaselinesPath {
    param([string]$WorkspaceRoot)
    return Join-Path $WorkspaceRoot $script:BaselinesFile
}

function _EnsureOutputDir {
    param([string]$WorkspaceRoot)
    $dir = Join-Path $WorkspaceRoot 'output'
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
}

function _ReadBaselines {
    param([string]$WorkspaceRoot)
    $path  = _GetBaselinesPath -WorkspaceRoot $WorkspaceRoot
    $empty = @{ baselines = @() }
    if (-not (Test-Path -LiteralPath $path)) { return $empty }
    try {
        $raw    = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $parsed = ConvertFrom-Json -InputObject $raw
        return @{
            baselines = @($parsed.baselines ?? @())
        }
    } catch {
        return $empty
    }
}

function _WriteBaselines {
    param([string]$WorkspaceRoot, [hashtable]$Data)
    _EnsureOutputDir -WorkspaceRoot $WorkspaceRoot
    $path = _GetBaselinesPath -WorkspaceRoot $WorkspaceRoot
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8 -NoNewline
}

# Extract the short level prefix (e.g. "L3" from "L3-Contract-Ready")
function _LevelPrefix {
    param([string]$Level)
    if ($Level -match '^(L\d)') { return $Matches[1] }
    return $Level
}

function _LevelRank {
    param([string]$Level)
    $prefix = _LevelPrefix -Level $Level
    if ($script:MaturityRank.ContainsKey($prefix)) {
        return $script:MaturityRank[$prefix]
    }
    return -1
}

# ---------------------------------------------------------------------------
# Set-MaturityBaseline
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Store or update a target maturity baseline for a repository.
.PARAMETER WorkspaceRoot
    Path to the workspace root (where output/ lives).
.PARAMETER RepoName
    Repository name.
.PARAMETER TargetLevel
    Target maturity level, e.g. 'L3-Contract-Ready'.
.OUTPUTS
    [pscustomobject] with repoName, targetLevel, setAt.
#>
function Set-MaturityBaseline {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$TargetLevel
    )

    $now  = (Get-Date).ToUniversalTime().ToString('o')
    $data = _ReadBaselines -WorkspaceRoot $WorkspaceRoot

    # Upsert
    $existing = $data.baselines | Where-Object { $_.repoName -eq $RepoName }
    if ($null -ne $existing) {
        # Mutate in-place via index
        $idx = [array]::IndexOf($data.baselines, $existing)
        $data.baselines[$idx] = [pscustomobject]@{
            repoName              = $RepoName
            targetLevel           = $TargetLevel
            setAt                 = $now
            lastAcknowledgedAt    = ($existing.lastAcknowledgedAt ?? $null)
        }
    } else {
        $newEntry = [pscustomobject]@{
            repoName           = $RepoName
            targetLevel        = $TargetLevel
            setAt              = $now
            lastAcknowledgedAt = $null
        }
        $data.baselines = @($data.baselines) + @($newEntry)
    }

    try {
        _WriteBaselines -WorkspaceRoot $WorkspaceRoot -Data $data
    } catch {
        return [pscustomobject]@{
            repoName    = $RepoName
            targetLevel = $TargetLevel
            setAt       = $now
            persisted   = $false
            error       = "Baseline updated in-memory but could not be saved: $_"
        }
    }

    return [pscustomobject]@{
        repoName    = $RepoName
        targetLevel = $TargetLevel
        setAt       = $now
        persisted   = $true
    }
}

# ---------------------------------------------------------------------------
# Get-MaturityDrift
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Compare current audit entries against stored baselines and return drift alerts.
.PARAMETER WorkspaceRoot
    Path to the workspace root.
.PARAMETER CurrentAuditEntries
    Array of audit result objects. Each must have at minimum:
      repoName      - string
      maturityLevel - string (e.g. 'L2-Structured')
      score         - numeric (optional, defaulted to 0 if absent)
.OUTPUTS
    [pscustomobject] with driftAlerts, baselineCount, driftCount, evaluatedAt.
#>
function Get-MaturityDrift {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$CurrentAuditEntries
    )

    $now       = (Get-Date).ToUniversalTime().ToString('o')
    $data      = _ReadBaselines -WorkspaceRoot $WorkspaceRoot
    $baselines = @($data.baselines)
    $alerts    = [System.Collections.Generic.List[pscustomobject]]::new()

    # Build lookup from audit entries
    $auditMap = @{}
    foreach ($entry in $CurrentAuditEntries) {
        if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace($entry.repoName)) {
            $auditMap[$entry.repoName] = $entry
        }
    }

    foreach ($baseline in $baselines) {
        $repoName    = $baseline.repoName
        $targetLevel = $baseline.targetLevel
        $targetRank  = _LevelRank -Level $targetLevel

        $auditEntry = $auditMap[$repoName]
        if ($null -eq $auditEntry) { continue }

        $currentLevel = [string]($auditEntry.maturityLevel ?? 'L0')
        $currentScore = 0
        if ($auditEntry.PSObject.Properties.Name -contains 'score' -and $null -ne $auditEntry.score) {
            $parsed = 0.0
            if ([double]::TryParse([string]$auditEntry.score, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
                $currentScore = $parsed
            }
        }
        elseif ($auditEntry.PSObject.Properties.Name -contains 'maturityScore' -and $null -ne $auditEntry.maturityScore) {
            $parsed = 0.0
            if ([double]::TryParse([string]$auditEntry.maturityScore, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
                $currentScore = $parsed
            }
        }
        $currentRank  = _LevelRank -Level $currentLevel

        if ($currentRank -lt $targetRank) {
            $gap          = $targetRank - $currentRank
            $driftSeverity = if ($gap -ge 2) { 'critical' } else { 'warning' }

            $alerts.Add([pscustomobject]@{
                repoName      = $repoName
                targetLevel   = $targetLevel
                currentLevel  = $currentLevel
                currentScore  = $currentScore
                driftSeverity = $driftSeverity
                detectedAt    = $now
            })
        }
    }

    return [pscustomobject]@{
        driftAlerts    = $alerts.ToArray()
        baselineCount  = $baselines.Count
        driftCount     = $alerts.Count
        evaluatedAt    = $now
    }
}

# ---------------------------------------------------------------------------
# Confirm-MaturityDriftAcknowledged
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Mark a maturity drift alert as acknowledged for a repository.
.PARAMETER WorkspaceRoot
    Path to the workspace root.
.PARAMETER RepoName
    Repository whose drift is being acknowledged.
.OUTPUTS
    [pscustomobject] with success, repoName.
#>
function Confirm-MaturityDriftAcknowledged {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [string]$RepoName
    )

    $now  = (Get-Date).ToUniversalTime().ToString('o')
    $data = _ReadBaselines -WorkspaceRoot $WorkspaceRoot

    $existing = $data.baselines | Where-Object { $_.repoName -eq $RepoName }
    if ($null -eq $existing) {
        return [pscustomobject]@{
            success  = $false
            repoName = $RepoName
            error    = "No baseline found for repo '$RepoName'."
        }
    }

    $idx = [array]::IndexOf($data.baselines, $existing)
    $data.baselines[$idx] = [pscustomobject]@{
        repoName           = $existing.repoName
        targetLevel        = $existing.targetLevel
        setAt              = $existing.setAt
        lastAcknowledgedAt = $now
    }

    try {
        _WriteBaselines -WorkspaceRoot $WorkspaceRoot -Data $data
    } catch {
        return [pscustomobject]@{
            success  = $false
            repoName = $RepoName
            error    = "Failed to persist acknowledgement: $_"
        }
    }

    return [pscustomobject]@{
        success  = $true
        repoName = $RepoName
    }
}


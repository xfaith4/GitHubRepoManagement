<#
.SYNOPSIS
    Register a weekly Windows Scheduled Task for branch hygiene reporting.

.DESCRIPTION
    Creates or updates a user-level scheduled task that runs
    tools/Invoke-BranchHygiene.ps1 in report mode and writes JSON output to
    reports/branch-hygiene-latest.json.

    The task is non-destructive by default (no -Apply switch).

.PARAMETER RepoPath
    Repository root path. Defaults to this script's parent directory.

.PARAMETER TaskName
    Scheduled task name.

.PARAMETER DayOfWeek
    Weekly schedule day. Valid values: MON, TUE, WED, THU, FRI, SAT, SUN.

.PARAMETER Time
    24-hour local time in HH:mm format.

.EXAMPLE
    pwsh ./tools/Register-BranchHygieneScheduledTask.ps1

.EXAMPLE
    pwsh ./tools/Register-BranchHygieneScheduledTask.ps1 -DayOfWeek FRI -Time 16:30
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$RepoPath,
    [Parameter()][string]$TaskName = 'GitHubRepoManagement-BranchHygiene',
    [Parameter()][ValidateSet('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')][string]$DayOfWeek = 'MON',
    [Parameter()][ValidatePattern('^([01][0-9]|2[0-3]):[0-5][0-9]$')][string]$Time = '09:00'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

$hygieneScript = Join-Path $RepoPath 'tools/Invoke-BranchHygiene.ps1'
if (-not (Test-Path -LiteralPath $hygieneScript)) {
    throw "Missing script: $hygieneScript"
}

$reportPath = Join-Path $RepoPath 'reports/branch-hygiene-latest.json'
$taskCommand = 'pwsh.exe'
$taskArguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -RepoPath "{1}" -OutputPath "{2}"' -f $hygieneScript, $RepoPath, $reportPath)

if ($PSCmdlet.ShouldProcess($TaskName, 'register or update scheduled task')) {
    $createArgs = @(
        '/Create',
        '/TN', $TaskName,
        '/SC', 'WEEKLY',
        '/D', $DayOfWeek,
        '/ST', $Time,
        '/TR', ("{0} {1}" -f $taskCommand, $taskArguments),
        '/F'
    )

    $output = & schtasks.exe @createArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register task '$TaskName': $(@($output) -join ' ')"
    }
}

Write-Host ("Scheduled task '{0}' is configured for {1} at {2}." -f $TaskName, $DayOfWeek, $Time) -ForegroundColor Green
Write-Host ("Command: {0} {1}" -f $taskCommand, $taskArguments) -ForegroundColor DarkCyan

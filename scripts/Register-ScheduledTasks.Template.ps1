[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement',

    [Parameter()]
    [string]$TaskPrefix = 'RepoMgmt',

    [Parameter()]
    [string]$DailyRunTime = '02:00'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statusScript = Join-Path $WorkspaceRoot 'scripts\Run-ScheduledStatus.ps1'
$reconcileScript = Join-Path $WorkspaceRoot 'scripts\Run-ScheduledReconcile.ps1'

if (-not (Test-Path -LiteralPath $statusScript)) {
    @"
param([string]`$WorkspaceRoot = '$WorkspaceRoot')
`$baseUrl = 'http://127.0.0.1:7071'
Invoke-RestMethod -Uri "`$baseUrl/api/status?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=2&includeNonGitFolders=false" -Method Get | Out-Null
"@ | Set-Content -LiteralPath $statusScript -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $reconcileScript)) {
    @"
param([string]`$WorkspaceRoot = '$WorkspaceRoot')
`$baseUrl = 'http://127.0.0.1:7071'
`$body = @{ localRoots = @(`$WorkspaceRoot); maxDepth = 3; includeNonGitFolders = `$false } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri "`$baseUrl/api/reconcile" -Method Post -ContentType 'application/json' -Body `$body | Out-Null
"@ | Set-Content -LiteralPath $reconcileScript -Encoding UTF8
}

$statusAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$statusScript`""
$reconcileAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$reconcileScript`""

$statusTrigger = New-ScheduledTaskTrigger -Daily -At $DailyRunTime
$reconcileTrigger = New-ScheduledTaskTrigger -Daily -At ((Get-Date "2000-01-01 $DailyRunTime").AddMinutes(30).ToString('HH:mm'))

Register-ScheduledTask -TaskName "$TaskPrefix-StatusScan" -Action $statusAction -Trigger $statusTrigger -Description 'Runs consolidated repo status scan daily.' -Force | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix-Reconcile" -Action $reconcileAction -Trigger $reconcileTrigger -Description 'Runs consolidated reconciliation daily.' -Force | Out-Null

Write-Host "Registered scheduled tasks: $TaskPrefix-StatusScan, $TaskPrefix-Reconcile" -ForegroundColor Green

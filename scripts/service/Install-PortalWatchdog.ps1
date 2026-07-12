<#
.SYNOPSIS
    Register (or remove) the portal health watchdog as a SYSTEM Scheduled Task.

.DESCRIPTION
    Installs Watch-PortalHealth.ps1 as a Scheduled Task that runs every
    -IntervalMinutes as NT AUTHORITY\SYSTEM (RunLevel Highest) so it can kill the
    frozen, SYSTEM-owned portal host and Restart-Service RepoMgmtPortal. Must be
    run from an elevated (Administrator) shell — registering a SYSTEM task
    requires it. Idempotent: re-running replaces the task. -Uninstall removes it.

    This is the one part of the watchdog that cannot be exercised without
    elevation; the watchdog's own decision logic is covered by the module smoke.

.EXAMPLE
    # from an elevated PowerShell:
    pwsh -File scripts/service/Install-PortalWatchdog.ps1

.EXAMPLE
    pwsh -File scripts/service/Install-PortalWatchdog.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [int]$FailureThreshold = 3,
    [int]$IntervalMinutes = 1,
    [int]$Port = 7071,
    [string]$ServiceName = 'RepoMgmtPortal',
    [string]$BaseUrl = 'https://127.0.0.1:7071',
    [string]$WebhookUrl,
    [string]$TaskName = 'RepoMgmtPortalWatchdog',
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

# ── Elevation gate ───────────────────────────────────────────────────────────
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[FAIL] Run this from an elevated (Administrator) PowerShell — registering a SYSTEM Scheduled Task requires it." -ForegroundColor Red
    exit 1
}

if ($Uninstall) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host ("[OK] Removed scheduled task '{0}'." -f $TaskName) -ForegroundColor Green
    }
    else {
        Write-Host ("[OK] No scheduled task '{0}' to remove." -f $TaskName) -ForegroundColor DarkGray
    }
    exit 0
}

# ── Resolve the PowerShell host to run the watchdog with ─────────────────────
$exe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $exe) { $exe = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
if (-not $exe) { Write-Host "[FAIL] Neither pwsh nor powershell found on PATH." -ForegroundColor Red; exit 1 }

$script = Join-Path $WorkspaceRoot 'scripts\service\Watch-PortalHealth.ps1'
if (-not (Test-Path -LiteralPath $script)) { Write-Host ("[FAIL] Watchdog script not found: {0}" -f $script) -ForegroundColor Red; exit 1 }

$argList = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $script),
    '-WorkspaceRoot', ('"{0}"' -f $WorkspaceRoot),
    '-BaseUrl', ('"{0}"' -f $BaseUrl),
    '-Port', $Port,
    '-ServiceName', ('"{0}"' -f $ServiceName),
    '-FailureThreshold', $FailureThreshold
)
if ($WebhookUrl) { $argList += @('-WebhookUrl', ('"{0}"' -f $WebhookUrl)) }
$argString = $argList -join ' '

$action = New-ScheduledTaskAction -Execute $exe -Argument $argString -WorkingDirectory $WorkspaceRoot
# -Once + -RepetitionInterval repeats indefinitely on Windows 10 1809+/PS 5.1+;
# the AtStartup trigger re-arms it after every reboot.
$triggers = @(
    (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)),
    (New-ScheduledTaskTrigger -AtStartup)
)
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$null = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force -Description 'Liveness watchdog for the RepoMgmtPortal service: probes /health/live and restarts the service if the host freezes.'

Write-Host ("[OK] Registered scheduled task '{0}' (every {1} min, as SYSTEM)." -f $TaskName, $IntervalMinutes) -ForegroundColor Green
Write-Host  "     Watchdog: $exe $argString" -ForegroundColor DarkGray
Write-Host  ""
Write-Host  "Verify:" -ForegroundColor Cyan
Write-Host  "  Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo"
Write-Host  "  Start-ScheduledTask -TaskName $TaskName   # run one cycle now"
Write-Host  "  Get-Content '$WorkspaceRoot\output\logs\service-watchdog.jsonl' -Tail 5"
Write-Host  "Remove:  pwsh -File scripts/service/Install-PortalWatchdog.ps1 -Uninstall" -ForegroundColor DarkGray
exit 0

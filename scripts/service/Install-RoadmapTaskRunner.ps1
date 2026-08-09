<#
.SYNOPSIS
    Register (or remove) the roadmap task runner as a per-user LOGON Scheduled Task.

.DESCRIPTION
    Release 3.0. The portal enqueues work it cannot execute: `gh agent-task`
    needs an OAuth credential and `claude` needs an authenticated session, and
    the LocalSystem portal service holds neither. Invoke-RoadmapTaskRunner.ps1
    supplies that identity by running as the operator — this registers it so the
    operator does not have to remember to start it after every logon.

    Deliberately the MIRROR IMAGE of Install-PortalWatchdog.ps1. That installer
    demands elevation and registers as NT AUTHORITY\SYSTEM, because it must kill
    a SYSTEM-owned process. This one refuses SYSTEM and every service account,
    because a runner that ran as SYSTEM would be back in exactly the credential
    hole Release 3.0 exists to climb out of — it would hold no OAuth token, no
    Claude Code login, and would fail every task it claimed while looking
    perfectly healthy in Task Scheduler.

    Idempotent: re-running replaces the task. -Uninstall removes it.

.PARAMETER LoadFunctionsOnly
    Dot-source the pure functions without registering anything (module smoke).

.EXAMPLE
    # from YOUR normal (non-elevated) PowerShell:
    pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1

.EXAMPLE
    pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [int]$PollSeconds = 15,
    [string]$PermissionMode = 'acceptEdits',
    [switch]$Headless,
    [string]$TaskName = 'RepoMgmtRoadmapTaskRunner',
    [string]$UserId,
    [switch]$Uninstall,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Pure / testable helpers (module smoke covers these; no Task Scheduler) ────

function Get-ForbiddenRunnerPrincipals {
    <# Accounts that cannot hold an interactive credential. A runner registered
       as any of these claims tasks it can never complete. #>
    return @(
        'NT AUTHORITY\SYSTEM',
        'SYSTEM',
        'NT AUTHORITY\LOCAL SERVICE',
        'LOCAL SERVICE',
        'NT AUTHORITY\NETWORK SERVICE',
        'NETWORK SERVICE',
        'LOCALSYSTEM'
    )
}

function Test-RunnerPrincipalSafe {
    <#
    .SYNOPSIS
        Pure — may this account run the task runner? Named reason when not.
    .DESCRIPTION
        The check opts OUT by explicit name rather than trying to recognize a
        "real user", because the failure it prevents is silent: a SYSTEM-owned
        runner registers fine, shows as running, claims queued work, and fails
        every task for a credential reason that looks nothing like the cause.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowEmptyString()][string]$UserId = '')

    if ([string]::IsNullOrWhiteSpace($UserId)) {
        return [pscustomobject]@{
            safe    = $false
            reason  = 'no-principal'
            message = 'No account was resolved for the task. The runner must run as a specific interactive user.'
        }
    }

    $normalized = $UserId.Trim()
    $upper = $normalized.ToUpperInvariant()
    foreach ($forbidden in (Get-ForbiddenRunnerPrincipals)) {
        if ($upper -eq $forbidden.ToUpperInvariant()) {
            return [pscustomobject]@{
                safe    = $false
                reason  = 'service-account'
                message = ("'{0}' is a service account and cannot hold the OAuth or Claude Code credential the runner needs. " +
                           "Register the task as the operator account that runs 'gh auth login' and 'claude'.") -f $normalized
            }
        }
    }

    return [pscustomobject]@{ safe = $true; reason = ''; message = '' }
}

function New-RunnerTaskArgumentString {
    <#
    .SYNOPSIS
        Pure — the argument string the scheduled task launches the runner with.
    .DESCRIPTION
        Every path is quoted: the workspace root routinely contains spaces
        ("C:\Program Files", a OneDrive path), and an unquoted one silently
        truncates at the first space into a -WorkspaceRoot that does not exist.
        Deliberately never passes -Once — a logon task is the long-running poll
        loop, and -Once would exit after one sweep and look installed but idle.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][int]$PollSeconds = 15,
        [Parameter()][string]$PermissionMode = 'acceptEdits',
        [Parameter()][bool]$Headless = $false
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('-NoProfile'); $parts.Add('-ExecutionPolicy'); $parts.Add('Bypass')
    $parts.Add('-File'); $parts.Add(('"{0}"' -f $ScriptPath))
    $parts.Add('-WorkspaceRoot'); $parts.Add(('"{0}"' -f $WorkspaceRoot))
    $parts.Add('-PollSeconds'); $parts.Add([string]$PollSeconds)
    $parts.Add('-PermissionMode'); $parts.Add(('"{0}"' -f $PermissionMode))
    if ($Headless) { $parts.Add('-Headless') }
    return ($parts -join ' ')
}

function Resolve-RunnerTaskAction {
    <# Pure — install / uninstall / uninstall-noop, matching the shape
       Install-RepoManagementService.ps1's resolver uses. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([bool]$Uninstall, [bool]$TaskExists)

    if ($Uninstall) { return $(if ($TaskExists) { 'uninstall' } else { 'uninstall-noop' }) }
    return $(if ($TaskExists) { 'reinstall' } else { 'install' })
}

if ($LoadFunctionsOnly) { return }

# ── Registration ──────────────────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

if ([string]::IsNullOrWhiteSpace($UserId)) {
    $UserId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$action = Resolve-RunnerTaskAction -Uninstall:$Uninstall.IsPresent -TaskExists:([bool]$existingTask)

if ($action -eq 'uninstall') {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host ("[OK] Removed scheduled task '{0}'." -f $TaskName) -ForegroundColor Green
    exit 0
}
if ($action -eq 'uninstall-noop') {
    Write-Host ("[OK] No scheduled task '{0}' to remove." -f $TaskName) -ForegroundColor DarkGray
    exit 0
}

# The one refusal that matters. A SYSTEM-registered runner would look installed
# and healthy while failing every task it claimed.
$principalCheck = Test-RunnerPrincipalSafe -UserId $UserId
if (-not $principalCheck.safe) {
    Write-Host ("[FAIL] {0}" -f $principalCheck.message) -ForegroundColor Red
    exit 1
}

$exe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $exe) { $exe = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
if (-not $exe) { Write-Host '[FAIL] Neither pwsh nor powershell found on PATH.' -ForegroundColor Red; exit 1 }

$runnerScript = Join-Path $WorkspaceRoot 'scripts\Invoke-RoadmapTaskRunner.ps1'
if (-not (Test-Path -LiteralPath $runnerScript)) {
    Write-Host ("[FAIL] Runner script not found: {0}" -f $runnerScript) -ForegroundColor Red
    exit 1
}

$argString = New-RunnerTaskArgumentString `
    -ScriptPath $runnerScript `
    -WorkspaceRoot $WorkspaceRoot `
    -PollSeconds $PollSeconds `
    -PermissionMode $PermissionMode `
    -Headless:$Headless.IsPresent

$taskAction = New-ScheduledTaskAction -Execute $exe -Argument $argString -WorkingDirectory $WorkspaceRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
# Interactive, RunLevel Limited: the runner needs the operator's own logon
# session and no elevation. Highest would gain nothing and widen the blast
# radius of a tool that runs agent-authored code.
$principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited
# No ExecutionTimeLimit: this is a poll loop meant to outlive individual tasks,
# and the default 72-hour limit would kill it mid-run every third day.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)

$null = Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force `
    -Description 'Roadmap task runner: executes portal-queued Claude Code and GitHub Copilot tasks in the operator logon session, where the credentials live.'

Write-Host ("[OK] Registered scheduled task '{0}' at logon, as {1} (interactive, not elevated)." -f $TaskName, $UserId) -ForegroundColor Green
Write-Host  "     Runner: $exe $argString" -ForegroundColor DarkGray
Write-Host  ''
Write-Host  'Verify:' -ForegroundColor Cyan
Write-Host  "  Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo"
Write-Host  "  Start-ScheduledTask -TaskName $TaskName   # start it now without logging out"
Write-Host  "  Invoke-RestMethod http://127.0.0.1:7071/api/roadmap/runner   # portal should report present"
Write-Host  "Remove:  pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1 -Uninstall" -ForegroundColor DarkGray
exit 0

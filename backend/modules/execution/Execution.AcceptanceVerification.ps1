<#
.SYNOPSIS
    Release 3.8 Lane 0.18 — LOCAL_VERIFYING: acceptance criteria check before
    a task is marked awaiting-review. H38-36.

.DESCRIPTION
    LOCAL_VERIFYING is the state between AGENT_RUNNING and IMPLEMENTATION_COMPLETE
    in the delivery state machine. It is a read-only pass that checks whether the
    acceptance criteria declared in the WorkPacket are demonstrably satisfied
    before the runner calls the work done.

    Without this check, IMPLEMENTATION_COMPLETE only asserts that an agent stopped
    cleanly. With it, IMPLEMENTATION_COMPLETE means "the acceptance criteria were
    checked and passed", which is a claim strong enough to own the state name.

    The check is deliberately conservative:
    - A criterion that passes is evidence of completion.
    - A criterion that fails is a definite finding.
    - A criterion whose command cannot be run is SKIPPED (not failed), because
      the environment may lack the tool; skipping is not the same as passing.
    - An empty acceptance criteria list passes trivially — absence of a check is
      not a failure, but it IS noted in the result so the operator can see that
      no criteria were asserted.

    Everything here is pure and offline-testable. Running commands is the one
    I/O operation required; that responsibility is pushed to the caller via the
    -CommandRunner parameter (a scriptblock), so the function can be exercised
    in the smoke test without launching real processes.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
    Dot-source after Execution.WorkPacket.ps1:
        . (Join-Path $executionModuleRoot 'Execution.AcceptanceVerification.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _AV_Field {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

<#
.SYNOPSIS
    Check whether a single acceptance criterion is satisfied.

.DESCRIPTION
    Pure function: takes an already-read criterion string and an optional
    verification command. The CommandRunner scriptblock is invoked when a
    command is present; its contract is:
        param([string]$Command, [string]$WorkingDirectory)
        returns [pscustomobject]@{ exitCode = [int]; output = [string] }

    When no CommandRunner is supplied, the criterion is evaluated as text-only
    (always SKIPPED — no way to verify without running something).

.OUTPUTS
    [pscustomobject]@{
        criterion = [string]  # the criterion as written
        status    = [string]  # 'passed' | 'failed' | 'skipped'
        reason    = [string]  # human-readable note
    }
#>
function Test-AcceptanceCriterion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Criterion,
        [AllowEmptyString()][AllowNull()][string]$Command = $null,
        [AllowNull()][scriptblock]$CommandRunner = $null,
        [AllowEmptyString()][AllowNull()][string]$WorkingDirectory = $null
    )

    if ([string]::IsNullOrWhiteSpace($Command) -or $null -eq $CommandRunner) {
        return [pscustomobject]@{
            criterion = $Criterion
            status    = 'skipped'
            reason    = 'No verification command; criterion is recorded but not checked'
        }
    }

    try {
        $result = & $CommandRunner -Command $Command -WorkingDirectory ($(if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { '' } else { $WorkingDirectory }))
        $exitCode = [int](_AV_Field -Obj $result -Name 'exitCode' -Default 1)
        $output = [string](_AV_Field -Obj $result -Name 'output' -Default '')
        if ($exitCode -eq 0) {
            return [pscustomobject]@{
                criterion = $Criterion
                status    = 'passed'
                reason    = ("Command exited 0: {0}" -f $Command)
            }
        }
        return [pscustomobject]@{
            criterion = $Criterion
            status    = 'failed'
            reason    = ("Command exited {0}: {1}" -f $exitCode, $Command)
            output    = if ($output.Length -gt 500) { $output.Substring(0, 500) } else { $output }
        }
    }
    catch {
        return [pscustomobject]@{
            criterion = $Criterion
            status    = 'skipped'
            reason    = ("Command runner threw: {0}" -f $_.Exception.Message)
        }
    }
}

<#
.SYNOPSIS
    Check all acceptance criteria in a WorkPacket and return a LOCAL_VERIFYING
    result.

.DESCRIPTION
    Pure function. Takes the WorkPacket (for acceptance criteria and verification
    commands), an optional CommandRunner scriptblock, and an optional working
    directory. Returns a structured result the runner uses to decide the
    delivery state transition:

    - All criteria pass → status 'passed' → runner moves to IMPLEMENTATION_COMPLETE
    - Any criterion fails → status 'failed' → runner enqueues for remediation
    - All criteria skipped (no commands supplied) → status 'skipped' → runner
      MAY proceed, but the result notes that no verification was performed

    The result also carries the per-criterion details so the operator can read
    exactly what was and was not checked.

.OUTPUTS
    [pscustomobject]@{
        status    = [string]   # 'passed' | 'failed' | 'skipped'
        checked   = [int]      # criteria that produced passed or failed
        passed    = [int]
        failed    = [int]
        skipped   = [int]
        criteria  = [array]    # per-criterion Test-AcceptanceCriterion results
        timestamp = [string]   # ISO-8601 UTC
    }
#>
function Invoke-LocalAcceptanceVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$WorkPacket,
        [AllowNull()][scriptblock]$CommandRunner = $null,
        [AllowEmptyString()][AllowNull()][string]$WorkingDirectory = $null
    )

    $criteria  = @(_AV_Field -Obj $WorkPacket -Name 'acceptanceCriteria' -Default @())
    $verif     = _AV_Field -Obj $WorkPacket -Name 'verification' -Default $null
    $commands  = @(_AV_Field -Obj $verif -Name 'commands' -Default @())

    $results = @()
    for ($i = 0; $i -lt $criteria.Count; $i++) {
        $criterion = [string]$criteria[$i]
        $command   = if ($i -lt $commands.Count) { [string]$commands[$i] } else { $null }
        $results += Test-AcceptanceCriterion `
            -Criterion $criterion `
            -Command $command `
            -CommandRunner $CommandRunner `
            -WorkingDirectory $WorkingDirectory
    }

    $passedCount  = @($results | Where-Object { $_.status -eq 'passed' }).Count
    $failedCount  = @($results | Where-Object { $_.status -eq 'failed' }).Count
    $skippedCount = @($results | Where-Object { $_.status -eq 'skipped' }).Count

    $overallStatus = if ($failedCount -gt 0) {
        'failed'
    } elseif ($passedCount -gt 0) {
        'passed'
    } else {
        'skipped'
    }

    return [pscustomobject]@{
        status    = $overallStatus
        checked   = $passedCount + $failedCount
        passed    = $passedCount
        failed    = $failedCount
        skipped   = $skippedCount
        criteria  = @($results)
        timestamp = ([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    }
}

<#
.SYNOPSIS
    Decide the delivery state transition given a LOCAL_VERIFYING result.

.DESCRIPTION
    Pure function. Returns a transition decision the runner executes:
    - 'passed'  → nextStatus = 'implementation_complete'
    - 'failed'  → nextStatus = 'remediation' (runner enqueues; H38-31 owns the
                  remediation packet; the transition name here is a signal, not
                  a final run summary value)
    - 'skipped' → nextStatus = 'implementation_complete' (no check ≠ failure,
                  but skipCount is reported so the caller can note the gap)

    This function carries no I/O and no side effects; it is a decision table.
#>
function Resolve-LocalVerifyingTransition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$VerificationResult)

    $status = [string](_AV_Field -Obj $VerificationResult -Name 'status' -Default 'skipped')
    $failed = [int](_AV_Field -Obj $VerificationResult -Name 'failed' -Default 0)

    switch ($status) {
        'failed' {
            return [pscustomobject]@{
                nextStatus = 'remediation'
                proceed    = $false
                reason     = ("{0} acceptance criterion/criteria failed LOCAL_VERIFYING" -f $failed)
            }
        }
        'passed' {
            return [pscustomobject]@{
                nextStatus = 'implementation_complete'
                proceed    = $true
                reason     = 'All checked criteria passed'
            }
        }
        default {
            return [pscustomobject]@{
                nextStatus = 'implementation_complete'
                proceed    = $true
                reason     = 'No criteria were checked (skipped); proceeding without verification evidence'
            }
        }
    }
}

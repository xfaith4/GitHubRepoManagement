#requires -Version 7
<#
.SYNOPSIS
    D-012 - the owner approves the network allowlist one WorkPacket declares.

.DESCRIPTION
    A packet that needs the network declares `permissions.network = true` and
    a `permissions.networkAllowlist` of bare host names. No adapter grants the
    network until this command records the owner's approval of exactly that
    list (Resolve-PacketNetworkAccess). The approval stores a fingerprint of
    the hosts, so a host added later makes it stale rather than covered.

    Run without -Confirm:$false it shows the hosts and asks first; -WhatIf
    shows them and writes nothing.

.PARAMETER TaskId
    The packet's taskId (the run id the dispatch queued).

.PARAMETER ApprovedBy
    Who approves. Recorded verbatim in the packet.

.PARAMETER WorkspaceRoot
    The repository root that holds output\work-packets. Defaults to this
    repository.

.EXAMPLE
    pwsh -NoProfile -File ./tools/Approve-WorkPacketNetwork.ps1 -TaskId 20261110-120000-abcd1234 -ApprovedBy owner
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$ApprovedBy,
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\backend\modules\execution\Execution.WorkPacket.ps1')

$packet = Read-WorkPacket -WorkspaceRoot $WorkspaceRoot -TaskId $TaskId
if ($null -eq $packet) { throw ('No readable WorkPacket for task {0} under {1}.' -f $TaskId, $WorkspaceRoot) }

$validation = Test-WorkPacket -Packet $packet
if (-not $validation.valid) { throw ('The WorkPacket is invalid, so there is nothing to approve: {0}' -f ($validation.errors -join '; ')) }
if ($packet.permissions.network -ne $true) { throw 'The WorkPacket does not ask for the network; there is nothing to approve.' }

$hosts = @($packet.permissions.networkAllowlist)
if ($PSCmdlet.ShouldProcess(('task {0}' -f $TaskId), ('approve network access to {0}' -f ($hosts -join ', ')))) {
    $approval = New-NetworkAllowlistApproval -Allowlist $hosts -ApprovedBy $ApprovedBy
    $packet.permissions | Add-Member -NotePropertyName 'networkApproval' -NotePropertyValue ([pscustomobject]$approval) -Force
    $path = Save-WorkPacket -WorkspaceRoot $WorkspaceRoot -Packet $packet
    $access = Resolve-PacketNetworkAccess -Packet $packet
    [pscustomobject]@{
        taskId      = $TaskId
        path        = $path
        allowlist   = $access.allowlist
        state       = $access.state
        approvedBy  = $approval.approvedBy
        approvedAt  = $approval.approvedAt
        fingerprint = $approval.allowlistFingerprint
    }
}

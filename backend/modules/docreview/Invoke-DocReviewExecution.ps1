[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Validate', 'Complete', 'Skip', 'Status')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$QueuePath,

    [Parameter(Mandatory = $true)]
    [string]$StatePath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [Parameter()]
    [string]$QueueId,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$OpenVSCode,

    [Parameter()]
    [switch]$NoLint,

    [Parameter()]
    [string]$Reason
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DocReview.Execution.psm1') -Force

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
}

try {
    $queueItems = @(Get-DocReviewQueueItems -QueuePath $QueuePath)
    $config = Get-DocReviewConfig -ConfigPath $ConfigPath
    $state = Get-DocReviewState -StatePath $StatePath -QueueItems $queueItems

    switch ($Mode) {
        'Status' {
            $report = Get-DocReviewStatusReport -QueueItems $queueItems -State $state -Config $config

            Write-Section 'Doc Review Status'
            foreach ($k in @($report.totals.Keys | Sort-Object)) {
                Write-Host ("  {0}: {1}" -f $k, $report.totals[$k])
            }

            Write-Section 'Next Eligible (Top 10)'
            if (@($report.nextEligible).Count -eq 0) {
                Write-Host '  none'
            }
            else {
                foreach ($row in @($report.nextEligible)) {
                    Write-Host ("  {0} | {1} | {2} | Score={3} | Dirty={4} | ArchiveOrExample={5}" -f $row.queueId, $row.repoName, $row.batchType, $row.queueScore, $row.gitDirty, $row.containsArchiveOrExample)
                }
            }

            Write-Section 'Blocked By Dirty Repo'
            if (@($report.blockedDirty).Count -eq 0) {
                Write-Host '  none'
            }
            else {
                foreach ($row in @($report.blockedDirty)) {
                    Write-Host ("  {0} | {1}" -f $row.queueId, $row.reason)
                }
            }

            Write-Section 'Retry Exhausted'
            if (@($report.retryExhausted).Count -eq 0) {
                Write-Host '  none'
            }
            else {
                foreach ($row in @($report.retryExhausted)) {
                    Write-Host ("  {0} | {1}" -f $row.queueId, $row.reason)
                }
            }

            Write-Section 'In Progress'
            if (@($report.inProgress).Count -eq 0) {
                Write-Host '  none'
            }
            else {
                foreach ($item in @($report.inProgress)) {
                    Write-Host ("  {0} | {1} | {2}" -f $item.queueId, $item.repoName, $item.runPath)
                }
            }

            Save-DocReviewState -StatePath $StatePath -State $state
        }
        'Start' {
            $selected = $null
            $selectedState = $null

            if ($QueueId) {
                $selected = @($queueItems | Where-Object { (Get-QueueFieldValue -Item $_ -Name 'QueueId') -eq $QueueId } | Select-Object -First 1)
                if ($selected.Count -eq 0) {
                    throw "QueueId '$QueueId' was not found in queue."
                }
                $selected = $selected[0]
                $selectedState = @($state.items | Where-Object { $_.queueId -eq $QueueId } | Select-Object -First 1)
                if ($selectedState.Count -eq 0) {
                    throw "QueueId '$QueueId' was not found in state."
                }
                $selectedState = $selectedState[0]
            }
            else {
                $candidate = Select-DocReviewNextQueueItem -QueueItems $queueItems -State $state -Config $config -Force:$Force
                if ($null -eq $candidate) {
                    throw 'No eligible queue item found.'
                }
                $selected = $candidate.queueItem
                $selectedState = $candidate.stateItem
            }

            try {
                $result = Start-DocReviewQueueItem -QueueItem $selected -StateItem $selectedState -Config $config -RunRoot $RunRoot -Force:$Force -OpenVSCode:$OpenVSCode
                Save-DocReviewState -StatePath $StatePath -State $state

                Write-Section 'Doc Review Start'
                Write-Host ("QueueId: {0}" -f $result.queueId)
                Write-Host ("Repo:    {0}" -f $result.repoName)
                Write-Host ("Path:    {0}" -f $result.repoPath)
                Write-Host ("Branch:  {0}" -f $result.branchName)
                Write-Host ("Packet:  {0}" -f $result.packetPath)
                Write-Host ("Run:     {0}" -f $result.runPath)
                Write-Host 'Scope files:'
                foreach ($file in @($result.files)) {
                    Write-Host ("  - {0}" -f $file)
                }
                if (@($result.warnings).Count -gt 0) {
                    Write-Host 'Warnings:'
                    foreach ($warning in @($result.warnings)) {
                        Write-Host ("  - {0}" -f $warning) -ForegroundColor Yellow
                    }
                }
            }
            catch {
                $selectedState.attemptCount = [int]$selectedState.attemptCount + 1
                Update-DocReviewStateItem -StateItem $selectedState -Status 'failed' -Note $_.Exception.Message
                Save-DocReviewState -StatePath $StatePath -State $state
                throw
            }
        }
        'Skip' {
            if (-not $QueueId) {
                throw 'Skip mode requires -QueueId.'
            }
            if ([string]::IsNullOrWhiteSpace($Reason)) {
                throw 'Skip mode requires -Reason.'
            }
            $status = if ($Force.IsPresent) { 'deferred' } else { 'skipped' }
            $updated = Set-DocReviewItemStatus -State $state -QueueId $QueueId -Status $status -Reason $Reason
            Save-DocReviewState -StatePath $StatePath -State $state
            Write-Host ("QueueId '{0}' marked as {1}. Reason: {2}" -f $updated.queueId, $updated.status, $Reason)
        }
        'Validate' {
            if ($NoLint.IsPresent) {
                Write-Host 'Validate mode scaffold acknowledged with -NoLint.'
            }
            throw 'Validate mode is scaffolded for Phase 3B and is not implemented yet.'
        }
        'Complete' {
            throw 'Complete mode is scaffolded for Phase 3C and is not implemented yet.'
        }
    }
}
catch {
    $details = $_ | Out-String
    Write-Error -Message $details
    exit 1
}

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Validate', 'Complete', 'Skip', 'Status')]
    [string]$Mode,

    [Parameter()]
    [string]$QueuePath = (Join-Path $PSScriptRoot 'output\docreview-adapter\queue\doc-review-queue.json'),

    [Parameter()]
    [string]$StatePath = (Join-Path $PSScriptRoot 'output\docreview-adapter\queue\doc-review-state.json'),

    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'output\docreview-adapter\queue\doc-review-config.json'),

    [Parameter()]
    [string]$RunRoot = (Join-Path $PSScriptRoot 'output\docreview-adapter\_doc_review_runs'),

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

$innerScript = Join-Path $PSScriptRoot 'backend\modules\docreview\Invoke-DocReviewExecution.ps1'
& $innerScript `
    -Mode $Mode `
    -QueuePath $QueuePath `
    -StatePath $StatePath `
    -ConfigPath $ConfigPath `
    -RunRoot $RunRoot `
    -QueueId $QueueId `
    -Force:$Force `
    -OpenVSCode:$OpenVSCode `
    -NoLint:$NoLint `
    -Reason $Reason

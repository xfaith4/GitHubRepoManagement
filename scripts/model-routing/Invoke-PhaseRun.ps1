#Requires -Version 7
<#
.SYNOPSIS
  Launches a Claude Code session with the model, effort, and permission mode
  declared for a roadmap phase step, and records launch intent to the
  model-routing ledger (JSONL).

.EXAMPLE
  ./Invoke-PhaseRun.ps1 -Phase 2.1-P2 -Step plan
  ./Invoke-PhaseRun.ps1 -Phase 2.1-P2 -Step implement
  ./Invoke-PhaseRun.ps1 -Phase 2.1-P4 -Step plan -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Phase,
    [ValidateSet('plan', 'implement')][string]$Step = 'plan',
    [string]$RoutingPath = (Join-Path $PSScriptRoot 'phase-model-routing.json'),
    [switch]$DryRun
)

$routing = Get-Content $RoutingPath -Raw | ConvertFrom-Json
$entry   = $routing.phases | Where-Object { $_.id -eq $Phase }
if (-not $entry) {
    throw "Phase '$Phase' not in routing table. Known: $($routing.phases.id -join ', ')"
}
$cfg = $entry.steps.$Step
if (-not $cfg) { throw "Phase '$Phase' defines no '$Step' step." }

$gitSha = try { (git rev-parse --short HEAD 2>$null) } catch { $null }
if (-not $gitSha) { $gitSha = 'no-git' }

# --- Record launch intent (one JSONL line, append-only) ---
$ledgerPath = $routing.ledger
$null = New-Item -ItemType Directory -Force -Path (Split-Path $ledgerPath)
$intent = [ordered]@{
    ts             = (Get-Date).ToUniversalTime().ToString('o')
    event          = 'launch-intent'
    phase          = $Phase
    step           = $Step
    expectedModel  = $cfg.model
    effort         = $cfg.effort
    permissionMode = $cfg.permissionMode
    gitSha         = $gitSha
    rationale      = $cfg.rationale
    operator       = $env:USERNAME
}
($intent | ConvertTo-Json -Compress) | Add-Content -Path $ledgerPath

# --- Hand expected values to the SessionStart validator hook ---
$env:CLAUDE_EXPECTED_MODEL = $cfg.model
$env:CLAUDE_PHASE_ID       = "$Phase/$Step"
$env:CLAUDE_ROUTING_LEDGER = $ledgerPath

$claudeArgs = @('--model', $cfg.model, '--permission-mode', $cfg.permissionMode)

$prompt = $null
if ($cfg.promptFile) {
    $promptPath = Join-Path $PSScriptRoot $cfg.promptFile
    if (Test-Path $promptPath) { $prompt = Get-Content $promptPath -Raw }
}

Write-Host ''
Write-Host "== Phase $Phase [$Step] ==" -ForegroundColor Cyan
Write-Host "   model : $($cfg.model)"
Write-Host "   effort: $($cfg.effort)   (verify in /model picker; CLI enforces model + mode only)"
Write-Host "   mode  : $($cfg.permissionMode)"
Write-Host "   sha   : $gitSha"
Write-Host "   ledger: $ledgerPath"
Write-Host ''

if ($DryRun) {
    Write-Host "dry-run: claude $($claudeArgs -join ' ')" -ForegroundColor Yellow
    if ($prompt) { Write-Host "with kickoff prompt: $($cfg.promptFile)" -ForegroundColor Yellow }
    return
}

if ($prompt) { claude @claudeArgs $prompt } else { claude @claudeArgs }

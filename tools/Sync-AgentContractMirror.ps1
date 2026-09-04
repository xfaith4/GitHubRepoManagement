<#
.SYNOPSIS
    Regenerates .github/copilot-instructions.md from AGENTS.md.

.DESCRIPTION
    AGENTS.md is the canonical agent contract. Copilot reads
    `.github/copilot-instructions.md` literally, so that file carries a full
    copy, and the "Agent contract mirror" gate in
    scripts/Invoke-ModuleSmokeTest.ps1 fails when the two diverge.

    The gate told the reader to "regenerate the mirror" while no generator
    existed, so every AGENTS.md edit turned into a hand copy-paste that the
    gate then caught in CI rather than locally. This is that generator.

    The mirror is the generated header followed by AGENTS.md verbatim; the
    gate asserts the mirror ENDS WITH the source, so nothing may be appended
    after the copy.

.PARAMETER WorkspaceRoot
    Repository root. Defaults to this script's parent directory.

.PARAMETER Check
    Report drift and exit non-zero without writing. For local use before a
    push; CI already runs the gate itself.

.EXAMPLE
    pwsh ./tools/Sync-AgentContractMirror.ps1
    Rewrites the mirror from AGENTS.md.

.EXAMPLE
    pwsh ./tools/Sync-AgentContractMirror.ps1 -Check
    Exits 1 if the mirror has drifted, writing nothing.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $WorkspaceRoot 'AGENTS.md'
$mirrorPath = Join-Path $WorkspaceRoot '.github\copilot-instructions.md'

foreach ($required in @($sourcePath, $mirrorPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing agent-contract file: $required" }
}

$sourceText = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
$mirrorText = Get-Content -LiteralPath $mirrorPath -Raw -Encoding UTF8

# The header is everything the mirror carries BEFORE the copy begins. Taken
# from the existing file rather than hardcoded here, so the banner's wording
# stays owned by the mirror and this script cannot silently rewrite it.
$firstHeadingIndex = $mirrorText.IndexOf('# GITHUBREPOMANAGEMENT')
if ($firstHeadingIndex -lt 1) {
    throw "Could not find the contract heading in the mirror; refusing to guess where the generated header ends."
}
$header = $mirrorText.Substring(0, $firstHeadingIndex)
if ($header -notmatch 'GENERATED MIRROR') {
    throw 'The mirror header does not declare itself generated; refusing to write a mirror the gate will reject.'
}

$rebuilt = $header + $sourceText

# Compare on normalized line endings, for the same reason the gate does: the
# working tree is LF and a CI checkout is CRLF.
$normalize = { param([string]$Text) $Text -replace "`r`n", "`n" }
$inSync = (& $normalize $mirrorText) -eq (& $normalize $rebuilt)

if ($Check) {
    if ($inSync) {
        Write-Host 'Agent contract mirror is in sync with AGENTS.md.' -ForegroundColor Green
        exit 0
    }
    Write-Host 'Agent contract mirror has DRIFTED from AGENTS.md. Run this script without -Check to regenerate.' -ForegroundColor Red
    exit 1
}

if ($inSync) {
    Write-Host 'Agent contract mirror already in sync; nothing written.' -ForegroundColor DarkGray
    return
}

if ($PSCmdlet.ShouldProcess($mirrorPath, 'Regenerate from AGENTS.md')) {
    # Preserve the file's existing newline convention so the rewrite does not
    # show up as a whole-file diff.
    $newline = if ($mirrorText -match "`r`n") { "`r`n" } else { "`n" }
    $out = ($rebuilt -replace "`r`n", "`n") -replace "`n", $newline
    [System.IO.File]::WriteAllText($mirrorPath, $out, [System.Text.UTF8Encoding]::new($false))
    Write-Host ('Regenerated {0} from AGENTS.md.' -f $mirrorPath) -ForegroundColor Green
}

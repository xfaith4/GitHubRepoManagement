<#
.SYNOPSIS
    Rewrites the one open session-handoff issue, keeping the previous note.

.DESCRIPTION
    The last step of a session (AGENTS.md "Session completion and handoff").
    Validates the new body - every section present, "Next action" filled, at
    most 60 lines - then posts the outgoing body as a comment so the history
    reads top to bottom, and replaces the issue body with the new note.

    The issue lives on GitHub rather than in a file so that a fresh session on
    main reads it immediately, without waiting for a branch to merge.

.PARAMETER BodyPath
    Markdown file holding the new handoff body.

.PARAMETER Template
    Print the empty handoff template and exit.

.PARAMETER Create
    When no open handoff issue exists, create the label and the issue and pin it.

.EXAMPLE
    pwsh ./tools/Publish-SessionHandoff.ps1 -Template > $env:TEMP\handoff.md

.EXAMPLE
    pwsh ./tools/Publish-SessionHandoff.ps1 -BodyPath $env:TEMP\handoff.md
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Publish')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Publish')][string]$BodyPath,
    [Parameter(ParameterSetName = 'Publish')][switch]$Create,
    [Parameter(Mandatory, ParameterSetName = 'Template')][switch]$Template,
    [Parameter()][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'SessionHandoff.ps1')
if (-not $WorkspaceRoot) { $WorkspaceRoot = Split-Path -Parent $PSScriptRoot }

if ($Template) {
    Get-SessionHandoffTemplate
    return
}

function Invoke-Gh {
    param([string[]]$ArgumentList)
    $output = & gh @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($ArgumentList[0..1] -join ' ') failed (exit $LASTEXITCODE): $(@($output) -join ' ')"
    }
    @($output) -join "`n"
}

$BodyPath = (Resolve-Path -LiteralPath $BodyPath).Path
$body = Get-Content -LiteralPath $BodyPath -Raw -Encoding UTF8
$check = Test-SessionHandoffBody -Body $body
if (-not $check.ok) {
    throw ("Handoff body rejected:`n - " + ($check.problems -join "`n - "))
}

Push-Location -LiteralPath (Resolve-Path -LiteralPath $WorkspaceRoot).Path
try {
    $existing = Invoke-Gh @('issue', 'list', '--label', $script:SessionHandoffLabel, '--state', 'open',
        '--json', 'number,title,body,updatedAt,url')
    $resolved = Resolve-SessionHandoffIssue -Issues @(ConvertFrom-JsonArray -Json $existing)

    switch ($resolved.status) {
        'duplicate' { throw $resolved.detail }
        'missing' {
            if (-not $Create) { throw "$($resolved.detail) Re-run with -Create." }
            if ($PSCmdlet.ShouldProcess("label '$script:SessionHandoffLabel' and a pinned 'Session handoff' issue", 'Create')) {
                $labels = Invoke-Gh @('label', 'list', '--search', $script:SessionHandoffLabel, '--json', 'name')
                if (-not (@(ConvertFrom-JsonArray -Json $labels) | Where-Object { $_.name -eq $script:SessionHandoffLabel })) {
                    $null = Invoke-Gh @('label', 'create', $script:SessionHandoffLabel, '--color', '0E8A16',
                        '--description', 'The one open session-handoff note (tools/Publish-SessionHandoff.ps1)')
                }
                $url = (Invoke-Gh @('issue', 'create', '--title', 'Session handoff', '--label', $script:SessionHandoffLabel,
                    '--body-file', $BodyPath)).Trim()
                $null = Invoke-Gh @('issue', 'pin', $url)
                [pscustomobject]@{ action = 'created'; url = $url }
            }
        }
        'ok' {
            $issue = $resolved.issue
            if ($PSCmdlet.ShouldProcess("#$($issue.number)", 'Replace the handoff body, keeping the old one as a comment')) {
                $previous = Join-Path ([System.IO.Path]::GetTempPath()) ("handoff-previous-{0}.md" -f $issue.number)
                $note = "Superseded handoff (body as of $($issue.updatedAt)):`n`n" + [string]$issue.body
                Set-Content -LiteralPath $previous -Value $note -Encoding UTF8
                try {
                    $null = Invoke-Gh @('issue', 'comment', [string]$issue.number, '--body-file', $previous)
                } finally {
                    Remove-Item -LiteralPath $previous -Force
                }
                $null = Invoke-Gh @('issue', 'edit', [string]$issue.number, '--body-file', $BodyPath)
                [pscustomobject]@{ action = 'updated'; url = $issue.url }
            }
        }
    }
} finally {
    Pop-Location
}

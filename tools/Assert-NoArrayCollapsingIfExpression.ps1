[CmdletBinding()]
<#
.SYNOPSIS
    Finds assignments whose value is an if-expression with an array-valued
    branch, where PowerShell silently collapses the array.

.DESCRIPTION
    `$x = if ($c) { @() } else { @(1) }` does not assign an array. The
    if-expression's output goes through the pipeline, which unrolls it: an
    empty branch yields $null and a one-element branch yields the bare
    element. `@($x)` afterwards does not recover it - it wraps the $null,
    producing a one-element array containing null, which serializes as
    `[null]` and reaches a surface as a phantom row.

    Wrapping the WHOLE if-expression fixes it: `$x = @(if ($c) { @() } ...)`.

    Detection is AST-based, not textual, because these expressions span many
    lines and a regex cannot tell a collapsing branch from a scalar one.

    Lane 0.17 (ROADMAP) asked for the audit and this gate.

.PARAMETER WorkspaceRoot
    Repository root to scan. Defaults to the parent of this script's folder.

.PARAMETER BaselinePath
    JSON file holding the accepted site count per relative path. The gate
    fails when a file exceeds its baseline, so existing debt stays visible
    without blocking unrelated work. Ratchets down only.

.PARAMETER UpdateBaseline
    Rewrite the baseline from the current scan instead of asserting.

.EXAMPLE
    pwsh -File tools/Assert-NoArrayCollapsingIfExpression.ps1
#>
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaselinePath,
    [switch]$UpdateBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $BaselinePath) {
    $BaselinePath = Join-Path $WorkspaceRoot 'scripts/array-collapse-baseline.json'
}

function Get-ArrayCollapsingIfExpressionFromAst {
    <#
    .SYNOPSIS
        Emits one record per assignment whose if-expression can collapse.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast,
        [string]$Path = '<memory>'
    )

    # An if-expression only collapses when its value is CONSUMED. As the
    # right-hand side of an assignment it is; as a statement it is not.
    $assignments = $Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst]
        }, $true)

    foreach ($assignment in $assignments) {
        $right = $assignment.Right
        # `$x = if (...)` parses the right side as a pipeline wrapping the
        # if-statement. Unwrap one level so both shapes are reachable.
        if ($right -is [System.Management.Automation.Language.PipelineAst] -and
            @($right.PipelineElements).Count -eq 1) {
            $inner = $right.PipelineElements[0]
            if ($inner -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $right = $inner.Expression
            }
        }

        $ifStatement = $null
        if ($right -is [System.Management.Automation.Language.IfStatementAst]) {
            $ifStatement = $right
        }
        elseif ($right -is [System.Management.Automation.Language.StatementBlockAst]) {
            continue
        }
        if ($null -eq $ifStatement) { continue }

        # Collect every branch body, including the else.
        $branches = [System.Collections.Generic.List[object]]::new()
        foreach ($clause in $ifStatement.Clauses) { $branches.Add($clause.Item2) | Out-Null }
        if ($null -ne $ifStatement.ElseClause) { $branches.Add($ifStatement.ElseClause) | Out-Null }

        # A branch is array-valued when the value it produces is an array
        # expression (@(...)) or an array literal (1,2,3). Those are the
        # shapes the pipeline unrolls.
        $arrayBranches = 0
        foreach ($branch in $branches) {
            $statements = @($branch.Statements)
            if ($statements.Count -eq 0) { continue }
            $last = $statements[-1]
            if ($last -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            if (@($last.PipelineElements).Count -ne 1) { continue }
            $element = $last.PipelineElements[0]
            if ($element -isnot [System.Management.Automation.Language.CommandExpressionAst]) { continue }
            $expression = $element.Expression
            if ($expression -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $expression -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                $arrayBranches++
            }
        }

        if ($arrayBranches -eq 0) { continue }

        [pscustomobject]@{
            Path         = $Path
            Line         = $assignment.Extent.StartLineNumber
            Target       = $assignment.Left.Extent.Text
            ArrayBranch  = $arrayBranches
            BranchCount  = $branches.Count
        }
    }
}

function Get-ArrayCollapsingIfExpression {
    <#
    .SYNOPSIS
        Parses a file and emits its collapsing if-expression assignments.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and @($errors).Count -gt 0) {
        throw ("Cannot parse {0}: {1}" -f $Path, @($errors)[0].Message)
    }
    Get-ArrayCollapsingIfExpressionFromAst -Ast $ast -Path $Path
}

function Assert-DetectorRejectsFixture {
    <#
    .SYNOPSIS
        Proves the detector fails a violating fixture and spares a fixed one.
    .DESCRIPTION
        A sweep that reports zero findings is indistinguishable from a sweep
        that cannot detect anything at all. Run the detector against known
        inputs first so "0 sites" means "none present", not "none findable".
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $violating = @'
$collapses = if ($cond) { @($items) } else { @() }
'@
    $fixed = @'
$safe = @(if ($cond) { @($items) } else { @() })
$scalar = if ($cond) { 'a' } else { 'b' }
'@

    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($violating, [ref]$tokens, [ref]$errors)
    $found = @(Get-ArrayCollapsingIfExpressionFromAst -Ast $ast -Path '<violating-fixture>')
    if ($found.Count -ne 1) {
        throw ("Detector is blind: the violating fixture produced {0} finding(s), expected 1." -f $found.Count)
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($fixed, [ref]$tokens, [ref]$errors)
    $spared = @(Get-ArrayCollapsingIfExpressionFromAst -Ast $ast -Path '<fixed-fixture>')
    if ($spared.Count -ne 0) {
        throw ("Detector is over-eager: the wrapped/scalar fixture produced {0} finding(s), expected 0." -f $spared.Count)
    }

    Write-Host '  detector proof: rejected the collapsing fixture, spared the wrapped and scalar forms'
}

Assert-DetectorRejectsFixture

$scanRoots = @('backend', 'scripts', 'tools') |
    ForEach-Object { Join-Path $WorkspaceRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ }

$files = @(Get-ChildItem -Path $scanRoots -Filter '*.ps1' -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\(node_modules|dist|output)\\' })

$findings = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    foreach ($finding in (Get-ArrayCollapsingIfExpression -Path $file.FullName)) {
        $findings.Add($finding) | Out-Null
    }
}

$all = @($findings.ToArray())
$byFile = @{}
foreach ($finding in $all) {
    $relative = $finding.Path.Substring($WorkspaceRoot.Length).TrimStart('\', '/').Replace('\', '/')
    if (-not $byFile.ContainsKey($relative)) { $byFile[$relative] = 0 }
    $byFile[$relative]++
}

Write-Host ("[STEP] Array-collapsing if-expression sweep: {0} file(s) parsed" -f $files.Count)

if ($UpdateBaseline) {
    $ordered = [ordered]@{}
    foreach ($key in ($byFile.Keys | Sort-Object)) { $ordered[$key] = $byFile[$key] }
    $ordered | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8
    Write-Host ("[PASS] Baseline rewritten: {0} file(s), {1} site(s)" -f $ordered.Count, $all.Count)
    return
}

$baseline = @{}
if (Test-Path -LiteralPath $BaselinePath) {
    $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8)
    foreach ($property in $parsed.PSObject.Properties) { $baseline[$property.Name] = [int]$property.Value }
}

$problems = [System.Collections.Generic.List[string]]::new()
foreach ($relative in ($byFile.Keys | Sort-Object)) {
    $allowed = 0
    if ($baseline.ContainsKey($relative)) { $allowed = $baseline[$relative] }
    if ($byFile[$relative] -gt $allowed) {
        $sites = @($all |
                Where-Object { $_.Path.Substring($WorkspaceRoot.Length).TrimStart('\', '/').Replace('\', '/') -eq $relative } |
                ForEach-Object { "      {0}:{1}  {2}" -f $relative, $_.Line, $_.Target })
        $problems.Add(("{0}: {1} site(s), baseline allows {2}`n{3}" -f $relative, $byFile[$relative], $allowed, ($sites -join "`n"))) | Out-Null
    }
}

if ($problems.Count -gt 0) {
    Write-Host ''
    foreach ($problem in $problems) { Write-Host ("[FAIL] {0}" -f $problem) -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Wrap the WHOLE if-expression: $x = @(if (...) { @() } else { @(1) })' -ForegroundColor Yellow
    throw ("Array-collapsing if-expression gate failed: {0} file(s) above baseline." -f $problems.Count)
}

Write-Host ("[PASS] Array-collapsing if-expressions: {0} site(s) across {1} file(s), none above baseline." -f $all.Count, $byFile.Count)

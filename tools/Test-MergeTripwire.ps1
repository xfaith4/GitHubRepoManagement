#Requires -Version 5.1
<#
.SYNOPSIS
    The merge tripwire: what a green check cannot see, held or failed before
    a branch lands on main.

.DESCRIPTION
    Ben, 2026-09-15 (D-023): the review-by-file-class rule of D-019 is replaced
    by this gate. A green check is the merge. What the light cannot see is
    evaluated here on the diff between the branch and its base:

    HARD findings fail the run and no approval clears them:
      - a secret shape on an added line (token, key, private key, connection
        string) -- a placeholder or example value is not a secret;
      - the permission envelope floor loosened in agent-providers.json
        (network or githubWrite true; .github/workflows/** no longer forbidden);
      - a versioned rules file under backend/config/ changed without its
        modelVersion moving (steering contract 6);
      - a debt ratchet loosened: the eslint --max-warnings cap raised, a
        PSScriptAnalyzer baseline count raised or a rule added to it, a UI
        ratchet count raised.

    HELD findings wait for the operator. The PR label `operator-approved`,
    read from the GitHub event payload, clears them for that CI run:
      - a protected path touched: docs/governance/merge-policy.md, this script
        and its proof test, .github/workflows/**, .github/CODEOWNERS, and the
        contracts section (section 2) of docs/governance/steering.md;
      - a gate removed from scripts/Invoke-TestSuite.ps1, or -FailOnError
        dropped from a gate that had it;
      - a test or check file deleted (tests/Test-*.ps1, tools/Test-*.ps1,
        scripts/Invoke-*Test*.ps1, frontend *.test.ts/tsx).

    The base is the pull request's base commit when GITHUB_EVENT_PATH names
    one, otherwise origin/main, otherwise HEAD~1 with a warning. An empty diff
    (a push to main) passes with nothing to evaluate.

    What this gate does NOT see, by design: a gate hollowed from inside without
    being removed, a decision recorded in the register that the owner did not
    make, a verdict that changed for a reason the evidence line does not
    justify. Those are the review the owner gave up in exchange for momentum;
    the remedy is `git revert -m 1 <merge>` and the audit is
    `git log --merges -- backend/config docs/governance`.

.PARAMETER WorkspaceRoot
    Repository root. Defaults to the parent of tools/.

.PARAMETER BaseRef
    'auto' (default) resolves as described above. Any other value is a git
    revision whose merge-base with HEAD is the base.

.PARAMETER EventPath
    Path to a GitHub webhook payload JSON. Defaults to $env:GITHUB_EVENT_PATH.
    Supplies the base commit and the PR labels.

.PARAMETER FailOnError
    Exit 1 on a HARD finding, or on a HELD finding without the label. Without
    the switch the gate reports and exits 0.

.EXAMPLE
    pwsh ./tools/Test-MergeTripwire.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][string]$BaseRef = 'auto',
    [Parameter()][string]$EventPath = $env:GITHUB_EVENT_PATH,
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
# git writes UTF-8; without this the base copy of a file with an em dash decodes
# differently from the head copy read with -Encoding UTF8, and section 2 of
# steering.md reads as changed on every branch.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ApprovalLabel = 'operator-approved'

# Paths that only the operator changes on green: the trust rule, its enforcement,
# and the CI definition (D-012). Globs are matched against forward-slash paths.
$script:ProtectedPathPatterns = @(
    '^docs/governance/merge-policy\.md$',
    '^tools/Test-MergeTripwire\.ps1$',
    '^tests/Test-MergeTripwire\.ps1$',
    '^\.github/workflows/.+',
    '^\.github/CODEOWNERS$'
)

$script:SteeringPath = 'docs/governance/steering.md'
$script:SuitePath = 'scripts/Invoke-TestSuite.ps1'
$script:EnvelopePath = 'backend/config/agent-providers.json'
$script:EslintPackagePath = 'frontend/package.json'
$script:PssaBaselinePath = 'scripts/pssa-baseline.json'
$script:UiBaselinePath = 'tools/ui-ratchet-baseline.json'

$script:CheckFilePatterns = @(
    '^tests/Test-[^/]+\.ps1$',
    '^tools/Test-[^/]+\.ps1$',
    '^scripts/Invoke-[^/]*Test[^/]*\.ps1$',
    '^frontend/.+\.test\.tsx?$'
)

# Secret shapes. Each is specific enough that a fixture or a doc does not trip
# it; the generic assignment form is exempted for placeholder values below.
$script:SecretPatterns = @(
    @{ Name = 'GitHub token';           Pattern = 'gh[pousr]_[A-Za-z0-9]{36}' },
    @{ Name = 'GitHub fine-grained PAT'; Pattern = 'github_pat_[A-Za-z0-9_]{22,}' },
    @{ Name = 'model provider key';     Pattern = 'sk-(?:proj-|ant-)?[A-Za-z0-9_\-]{32,}' },
    @{ Name = 'AWS access key';         Pattern = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'private key block';      Pattern = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY-----' },
    @{ Name = 'Slack token';            Pattern = 'xox[abprs]-[0-9A-Za-z\-]{10,}' },
    @{ Name = 'connection string';      Pattern = '(?i)(?:Server|Data Source|Host)=[^;]+;.*(?:Password|Pwd)=[^;''"\s]{4,}' },
    @{ Name = 'credential assignment';  Pattern = '(?i)(?:password|passwd|secret|token|apikey|api_key)\s*[=:]\s*[''"][^''"\s]{12,}[''"]' }
)
$script:PlaceholderPattern = '(?i)placeholder|example|dummy|fake|redacted|changeme|your[-_ ]|xxxx|\$\{|\$env:|<[^>]+>'

$hard = [System.Collections.Generic.List[string]]::new()
$held = [System.Collections.Generic.List[string]]::new()

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Argument)
    $raw = (& git -C $WorkspaceRoot @Argument 2>&1) | Out-String
    return [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Text = $raw }
}

function Get-LineSet {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return @() }
    return @(($Text -replace "`r", '') -split "`n")
}

function Get-BaseContent {
    param([Parameter(Mandatory = $true)][string]$Sha, [Parameter(Mandatory = $true)][string]$Path)
    $result = Invoke-Git -Argument @('show', ('{0}:{1}' -f $Sha, $Path))
    if (-not $result.Ok) { return $null }
    return $result.Text
}

function Get-HeadContent {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Join-Path $WorkspaceRoot ($Path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full)) { return $null }
    return (Get-Content -LiteralPath $full -Raw -Encoding UTF8)
}

function Read-EventPayload {
    param([AllowNull()][AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Write-Host ("  event payload at {0} is not JSON: {1}" -f $Path, $_.Exception.Message) -ForegroundColor Yellow; return $null }
}

function Test-PropertyPresent {
    param([AllowNull()]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $false }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Resolve-BaseCommit {
    param([AllowNull()]$Payload, [Parameter(Mandatory = $true)][string]$Base)
    if ($Base -ne 'auto') {
        $mb = Invoke-Git -Argument @('merge-base', $Base, 'HEAD')
        if (-not $mb.Ok) { throw ("Cannot resolve merge-base of '{0}' and HEAD: {1}" -f $Base, $mb.Text.Trim()) }
        return [pscustomobject]@{ Sha = $mb.Text.Trim(); Source = $Base }
    }
    if ($null -ne $Payload -and (Test-PropertyPresent -Object $Payload -Name 'pull_request')) {
        $baseSha = [string]$Payload.pull_request.base.sha
        if (-not [string]::IsNullOrWhiteSpace($baseSha)) {
            $exists = Invoke-Git -Argument @('cat-file', '-e', ('{0}^{{commit}}' -f $baseSha))
            if ($exists.Ok) {
                $mb = Invoke-Git -Argument @('merge-base', $baseSha, 'HEAD')
                if ($mb.Ok) { return [pscustomobject]@{ Sha = $mb.Text.Trim(); Source = ('pull request base {0}' -f $baseSha.Substring(0, 7)) } }
            }
            Write-Host ("  pull request base {0} is not in this checkout; falling back to origin/main." -f $baseSha) -ForegroundColor Yellow
        }
    }
    $originMain = Invoke-Git -Argument @('rev-parse', '--verify', '--quiet', 'origin/main')
    if ($originMain.Ok) {
        $mb = Invoke-Git -Argument @('merge-base', 'origin/main', 'HEAD')
        if ($mb.Ok) { return [pscustomobject]@{ Sha = $mb.Text.Trim(); Source = 'origin/main' } }
    }
    $prev = Invoke-Git -Argument @('rev-parse', '--verify', '--quiet', 'HEAD~1')
    if ($prev.Ok) {
        Write-Host '  origin/main is unavailable (shallow clone?); falling back to HEAD~1.' -ForegroundColor Yellow
        return [pscustomobject]@{ Sha = $prev.Text.Trim(); Source = 'HEAD~1' }
    }
    throw 'Cannot resolve a base commit: neither a pull request base, origin/main nor HEAD~1 exists. Fetch history (actions/checkout fetch-depth: 0) -- an unverifiable check must not report success.'
}

function Get-ChangedPath {
    param([Parameter(Mandatory = $true)][string]$Sha)
    $result = Invoke-Git -Argument @('diff', '--name-status', '-M', $Sha, 'HEAD')
    if (-not $result.Ok) { throw ("git diff --name-status failed: {0}" -f $result.Text.Trim()) }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($line in (Get-LineSet -Text $result.Text)) {
        # A status letter, an optional similarity score, a tab, a path. Anything
        # else on the stream (a CRLF warning from git on a Windows runner) is noise.
        if ($line -notmatch "^[ACDMRTUX]\d*`t") { continue }
        $parts = $line -split "`t"
        $status = $parts[0].Substring(0, 1)
        $path = ($parts[1] -replace '\\', '/')
        $newPath = $path
        if ($status -eq 'R' -and $parts.Count -ge 3) { $newPath = ($parts[2] -replace '\\', '/') }
        $items.Add([pscustomobject]@{ Status = $status; Path = $path; NewPath = $newPath })
    }
    return $items.ToArray()
}

function Test-ProtectedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    foreach ($pattern in $script:ProtectedPathPatterns) { if ($Path -match $pattern) { return $true } }
    return $false
}

function Test-CheckFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    foreach ($pattern in $script:CheckFilePatterns) { if ($Path -match $pattern) { return $true } }
    return $false
}

function Get-ContractSection {
    # Section 2 of steering.md: from its heading to the next second-level heading.
    param([AllowNull()][string]$Text)
    $lines = Get-LineSet -Text $Text
    $inside = $false
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^## 2\.') { $inside = $true; continue }
        if ($inside -and $line -match '^## ') { break }
        if ($inside) { $out.Add($line.TrimEnd()) }
    }
    return ($out -join "`n")
}

function Get-GateTable {
    # Gate name -> the statement line, for every uncommented Invoke-*Gate call.
    param([AllowNull()][string]$Text)
    $table = @{}
    foreach ($line in (Get-LineSet -Text $Text)) {
        if ($line.TrimStart().StartsWith('#')) { continue }
        if ($line -match "Invoke-(?:Script|Npm|InProcess)Gate\s+-Name\s+'([^']+)'") { $table[$Matches[1]] = $line }
    }
    return $table
}

function Get-EslintCap {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    if ($Text -match '--max-warnings[= ](\d+)') { return [int]$Matches[1] }
    return $null
}

function Get-CountTable {
    # A flat { rule: count } object, or the `counts` object of the UI baseline.
    param([AllowNull()][string]$Text, [switch]$Nested)
    $table = @{}
    if ($null -eq $Text) { return $table }
    $obj = $Text | ConvertFrom-Json
    if ($Nested) {
        if (-not (Test-PropertyPresent -Object $obj -Name 'counts')) { return $table }
        $obj = $obj.counts
    }
    foreach ($property in $obj.PSObject.Properties) {
        $value = 0
        if ([int]::TryParse([string]$property.Value, [ref]$value)) { $table[$property.Name] = $value }
    }
    return $table
}

function Find-SecretLine {
    param([Parameter(Mandatory = $true)][string]$Sha)
    $result = Invoke-Git -Argument @('diff', '--unified=0', '--no-color', $Sha, 'HEAD')
    if (-not $result.Ok) { throw ("git diff failed: {0}" -f $result.Text.Trim()) }
    $found = [System.Collections.Generic.List[string]]::new()
    $path = ''
    $lineNo = 0
    foreach ($line in (Get-LineSet -Text $result.Text)) {
        if ($line -match '^\+\+\+ b/(.+)$') { $path = $Matches[1]; continue }
        if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)') { $lineNo = [int]$Matches[1]; continue }
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') {
            $added = $line.Substring(1)
            foreach ($secret in $script:SecretPatterns) {
                if ($added -match $secret.Pattern) {
                    $matched = $Matches[0]
                    if ($secret.Name -eq 'credential assignment' -and $matched -match $script:PlaceholderPattern) { continue }
                    $found.Add(('{0}:{1} looks like a {2}' -f $path, $lineNo, $secret.Name))
                    break
                }
            }
            $lineNo++
        }
    }
    return $found.ToArray()
}

# --- Evaluate ---------------------------------------------------------------

Write-Host 'Merge tripwire (D-023): what a green check cannot see.' -ForegroundColor Cyan
$payload = Read-EventPayload -Path $EventPath
$base = Resolve-BaseCommit -Payload $payload -Base $BaseRef
$head = (Invoke-Git -Argument @('rev-parse', 'HEAD')).Text.Trim()
Write-Host ("  base {0} ({1}), head {2}" -f $base.Sha.Substring(0, 7), $base.Source, $head.Substring(0, 7))

$approved = $false
if ($null -ne $payload -and (Test-PropertyPresent -Object $payload -Name 'pull_request') -and (Test-PropertyPresent -Object $payload.pull_request -Name 'labels')) {
    foreach ($label in @($payload.pull_request.labels)) {
        if ((Test-PropertyPresent -Object $label -Name 'name') -and [string]$label.name -eq $script:ApprovalLabel) { $approved = $true }
    }
}

$changed = @(Get-ChangedPath -Sha $base.Sha)
Write-Host ("  {0} changed path(s)" -f $changed.Count)
foreach ($item in $changed) {
    if ($item.Status -eq 'R') { Write-Host ("    R {0} -> {1}" -f $item.Path, $item.NewPath) } else { Write-Host ("    {0} {1}" -f $item.Status, $item.Path) }
}

if ($changed.Count -gt 0) {
    # HELD: protected paths.
    foreach ($item in $changed) {
        foreach ($candidate in @($item.Path, $item.NewPath) | Select-Object -Unique) {
            if (Test-ProtectedPath -Path $candidate) { $held.Add(('protected path changed: {0}' -f $candidate)) }
        }
    }
    $steeringChanged = @($changed | Where-Object { $_.NewPath -eq $script:SteeringPath -or $_.Path -eq $script:SteeringPath })
    if ($steeringChanged.Count -gt 0) {
        $baseSection = Get-ContractSection -Text (Get-BaseContent -Sha $base.Sha -Path $script:SteeringPath)
        $headSection = Get-ContractSection -Text (Get-HeadContent -Path $script:SteeringPath)
        if ($baseSection -ne $headSection) { $held.Add('steering.md section 2 (the contracts) changed') }
    }

    # HELD: gate removed or weakened; check file deleted.
    $suiteChanged = @($changed | Where-Object { $_.NewPath -eq $script:SuitePath -or $_.Path -eq $script:SuitePath })
    if ($suiteChanged.Count -gt 0) {
        $baseGates = Get-GateTable -Text (Get-BaseContent -Sha $base.Sha -Path $script:SuitePath)
        $headGates = Get-GateTable -Text (Get-HeadContent -Path $script:SuitePath)
        foreach ($name in ($baseGates.Keys | Sort-Object)) {
            if (-not $headGates.ContainsKey($name)) { $held.Add(('gate removed from the suite: {0}' -f $name)); continue }
            if ($baseGates[$name] -match '-FailOnError' -and $headGates[$name] -notmatch '-FailOnError') { $held.Add(('-FailOnError dropped from gate: {0}' -f $name)) }
        }
    }
    foreach ($item in $changed) {
        if ($item.Status -eq 'D' -and (Test-CheckFilePath -Path $item.Path)) { $held.Add(('check file deleted: {0}' -f $item.Path)) }
    }

    # HARD: secrets on added lines.
    foreach ($finding in (Find-SecretLine -Sha $base.Sha)) { $hard.Add($finding) }

    # HARD: versioned config changed without a modelVersion move.
    foreach ($item in @($changed | Where-Object { $_.Status -eq 'M' -and $_.Path -match '^backend/config/[^/]+\.json$' })) {
        $baseText = Get-BaseContent -Sha $base.Sha -Path $item.Path
        $headText = Get-HeadContent -Path $item.Path
        if ($null -eq $baseText -or $null -eq $headText) { continue }
        try { $baseObj = $baseText | ConvertFrom-Json; $headObj = $headText | ConvertFrom-Json } catch { $hard.Add(('{0} does not parse as JSON: {1}' -f $item.Path, $_.Exception.Message)); continue }
        if ((Test-PropertyPresent -Object $baseObj -Name 'modelVersion') -and (Test-PropertyPresent -Object $headObj -Name 'modelVersion')) {
            if ([string]$baseObj.modelVersion -eq [string]$headObj.modelVersion) { $hard.Add(('{0} changed without a modelVersion bump (contract 6); still {1}' -f $item.Path, $headObj.modelVersion)) }
        }
    }

    # HARD: ratchets loosened.
    $eslintChanged = @($changed | Where-Object { $_.NewPath -eq $script:EslintPackagePath })
    if ($eslintChanged.Count -gt 0) {
        $baseCap = Get-EslintCap -Text (Get-BaseContent -Sha $base.Sha -Path $script:EslintPackagePath)
        $headCap = Get-EslintCap -Text (Get-HeadContent -Path $script:EslintPackagePath)
        if ($null -ne $baseCap -and $null -ne $headCap -and $headCap -gt $baseCap) { $hard.Add(('eslint --max-warnings raised {0} -> {1}' -f $baseCap, $headCap)) }
    }
    foreach ($ratchet in @(
            @{ Path = $script:PssaBaselinePath; Nested = $false; Label = 'PSScriptAnalyzer baseline' },
            @{ Path = $script:UiBaselinePath;   Nested = $true;  Label = 'UI ratchet baseline' })) {
        $touched = @($changed | Where-Object { $_.NewPath -eq $ratchet.Path })
        if ($touched.Count -eq 0) { continue }
        $baseCounts = Get-CountTable -Text (Get-BaseContent -Sha $base.Sha -Path $ratchet.Path) -Nested:$ratchet.Nested
        $headCounts = Get-CountTable -Text (Get-HeadContent -Path $ratchet.Path) -Nested:$ratchet.Nested
        foreach ($key in ($headCounts.Keys | Sort-Object)) {
            if (-not $baseCounts.ContainsKey($key)) {
                if ($headCounts[$key] -gt 0) { $hard.Add(('{0}: new debt category {1} = {2}' -f $ratchet.Label, $key, $headCounts[$key])) }
                continue
            }
            if ($headCounts[$key] -gt $baseCounts[$key]) { $hard.Add(('{0}: {1} raised {2} -> {3}' -f $ratchet.Label, $key, $baseCounts[$key], $headCounts[$key])) }
        }
    }
}

# HARD: the permission envelope floor, evaluated on the head tree whenever it exists.
$envelopeText = Get-HeadContent -Path $script:EnvelopePath
if ($null -ne $envelopeText) {
    $envelope = $envelopeText | ConvertFrom-Json
    if ((Test-PropertyPresent -Object $envelope -Name 'defaultPermissions')) {
        $perm = $envelope.defaultPermissions
        if ((Test-PropertyPresent -Object $perm -Name 'network') -and $perm.network -eq $true) { $hard.Add('permission envelope: defaultPermissions.network is true (floor is false; D-012)') }
        if ((Test-PropertyPresent -Object $perm -Name 'githubWrite') -and $perm.githubWrite -eq $true) { $hard.Add('permission envelope: defaultPermissions.githubWrite is true (floor is false; D-012)') }
    }
    $forbidden = @()
    if ((Test-PropertyPresent -Object $envelope -Name 'defaultScope') -and (Test-PropertyPresent -Object $envelope.defaultScope -Name 'forbiddenPaths')) { $forbidden = @($envelope.defaultScope.forbiddenPaths) }
    if ($forbidden -notcontains '.github/workflows/**') { $hard.Add('permission envelope: .github/workflows/** is no longer a forbidden path (D-012)') }
}

# --- Report -----------------------------------------------------------------

foreach ($finding in $hard) { Write-Host ("  [HARD] {0}" -f $finding) -ForegroundColor Red }
foreach ($finding in $held) { Write-Host ("  [HELD] {0}" -f $finding) -ForegroundColor Yellow }

$exitCode = 0
if ($hard.Count -gt 0) {
    Write-Host ("Merge tripwire: FAIL - {0} finding(s) no approval clears." -f $hard.Count) -ForegroundColor Red
    $exitCode = 1
}
elseif ($held.Count -gt 0 -and -not $approved) {
    Write-Host ("Merge tripwire: HELD for the operator - {0} finding(s). Ben adds the '{1}' label and the next CI run (close and reopen, or push) passes." -f $held.Count, $script:ApprovalLabel) -ForegroundColor Yellow
    $exitCode = 1
}
elseif ($held.Count -gt 0) {
    Write-Host ("Merge tripwire: PASS - {0} held finding(s) approved by the '{1}' label." -f $held.Count, $script:ApprovalLabel) -ForegroundColor Green
}
elseif ($changed.Count -eq 0) {
    Write-Host 'Merge tripwire: PASS - nothing to evaluate (head is the base).' -ForegroundColor Green
}
else {
    Write-Host 'Merge tripwire: PASS - nothing the light cannot see.' -ForegroundColor Green
}

if ($exitCode -ne 0 -and -not $FailOnError) { Write-Host '  (report only; pass -FailOnError to exit 1)' -ForegroundColor Yellow; $exitCode = 0 }
exit $exitCode

#Requires -Version 7.0
<#
    Portfolio.KindSignals.ps1 - Release 3.7 M4a: what a repository IS, read
    from its manifests, entry points and README purpose line while the index
    build already has the checkout in hand.

    The index carried only repoType and technologies before this file, and
    neither tells a PowerShell library apart from a PowerShell utility, or an
    Arduino sketch generator from the web page that serves it. Eight of the
    nine Release 3.7 trial repositories therefore concluded "no kind signal".

    This emits one `kindSignals` object per index entry. Kind is NOT decided
    here: foundation-domains.json's kindDetection rules read the hint ids this
    produces. The opinions - which files, dependencies, words and manifest
    keys count - live in backend/config/kind-signals.json with the repositories
    each was observed on (steering contract 6, section 5); this file holds the
    mechanics only, so a wrong hint is a data change and a modelVersion bump.
    Dot-sourced by Portfolio.Assessment.ps1; pure over the filesystem.
#>

Set-StrictMode -Version Latest

function _KS_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) { if ($Obj.Contains($Name)) { return $Obj[$Name] }; return $Default }
    if ($null -eq $Obj.PSObject) { return $Default }
    foreach ($prop in $Obj.PSObject.Properties) { if ($prop.Name -eq $Name) { return $prop.Value } }
    return $Default
}

$script:KindSignalConfigCache = @{}

function Get-KindSignalConfig {
    <#
    .SYNOPSIS
        Load backend/config/kind-signals.json (cached per path); throws when it is absent or not the v1 shape.
    #>
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\kind-signals.json'))

    $key = [System.IO.Path]::GetFullPath($ConfigPath)
    if ($script:KindSignalConfigCache.ContainsKey($key)) { return $script:KindSignalConfigCache[$key] }
    if (-not (Test-Path -LiteralPath $key -PathType Leaf)) { throw "kind-signals.json not found at $key" }
    $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $key -Raw -Encoding UTF8)
    if ([string](_KS_GetField -Obj $parsed -Name 'schemaVersion' -Default '') -ne 'v1') { throw "kind-signals.json schemaVersion must be 'v1'" }
    foreach ($required in @('modelVersion', 'readme', 'firmware', 'powershell', 'servedPage', 'node', 'dotnet', 'python', 'wording')) {
        if ($null -eq (_KS_GetField -Obj $parsed -Name $required -Default $null)) { throw "kind-signals.json is missing '$required'" }
    }
    $script:KindSignalConfigCache[$key] = $parsed
    return $parsed
}

function Get-RepoReadmePurposeLine {
    <#
    .SYNOPSIS
        The first prose line of the root README - the sentence a person reads to learn what the repository is for.
    .DESCRIPTION
        Skips headings, badges, images, HTML, tables, rules and blank lines
        (the skip pattern is config); returns '' when there is no README or no
        prose in its first N lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()][AllowEmptyString()][string]$LocalPath = '',
        [Parameter()][object]$Config = $null
    )

    if ([string]::IsNullOrWhiteSpace($LocalPath)) { return '' }
    if ($null -eq $Config) { $Config = Get-KindSignalConfig }
    $readmeCfg = _KS_GetField -Obj $Config -Name 'readme' -Default $null
    $maxLines = [int](_KS_GetField -Obj $readmeCfg -Name 'maxLines' -Default 40)
    $maxLength = [int](_KS_GetField -Obj $readmeCfg -Name 'maxLength' -Default 240)
    $skip = [string](_KS_GetField -Obj $readmeCfg -Name 'skipLinePattern' -Default '^(#|!\[|<|\||```)')
    $readme = $null
    foreach ($name in @(_KS_GetField -Obj $readmeCfg -Name 'fileNames' -Default @('README.md'))) {
        $candidate = Join-Path $LocalPath ([string]$name)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $readme = $candidate; break }
    }
    if ($null -eq $readme) { return '' }
    $lines = @()
    try { $lines = @(Get-Content -LiteralPath $readme -TotalCount $maxLines -Encoding UTF8 -ErrorAction Stop) } catch { return '' }
    foreach ($raw in $lines) {
        $line = [string]$raw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $t = $line.Trim() -replace '^>\s*', ''
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -match $skip) { continue }
        # Strip emphasis and inline links so the wording patterns see plain words.
        $t = $t -replace '\[([^\]]+)\]\([^)]*\)', '$1' -replace '[*_`]', ''
        $t = $t -replace '\s+', ' '
        if ($t.Length -gt $maxLength) { $t = $t.Substring(0, $maxLength).TrimEnd() }
        return $t
    }
    return ''
}

function Get-RepoKindSignalProfile {
    <#
    .SYNOPSIS
        Manifest, entry-point and README-purpose signals for one checkout, plus the hint ids the kind rules match on.
    .DESCRIPTION
        Returns [pscustomobject]{ signalModel, manifest, entryPoints[], readmePurpose, hints[], evidence[] }.
        `hints` is the contract with foundation-domains.json: a stable list of
        ids, each backed by one evidence line. `signalModel` is the
        kind-signals.json modelVersion that produced them, so an index entry
        says which signal model it was scanned under. A github-only entry (no
        local checkout) gets the empty profile, and the rules resolve 'unknown'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$LocalPath = '',
        [Parameter()][object]$Config = $null
    )

    if ($null -eq $Config) { $Config = Get-KindSignalConfig }
    $signalModel = [string](_KS_GetField -Obj $Config -Name 'modelVersion' -Default 'kind-signals v1')
    $hints = [System.Collections.Generic.List[string]]::new()
    $evidence = [System.Collections.Generic.List[string]]::new()
    $entryPoints = [System.Collections.Generic.List[string]]::new()
    $manifest = 'none'
    $hint = {
        param([string]$Id, [string]$Because)
        if (-not $hints.Contains($Id)) { $hints.Add($Id) | Out-Null; $evidence.Add(('{0}: {1}' -f $Id, $Because)) | Out-Null }
    }
    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path -LiteralPath $LocalPath -PathType Container -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ signalModel = $signalModel; manifest = 'none'; entryPoints = @(); readmePurpose = ''; hints = @(); evidence = @() }
    }

    # --- Firmware targets: the strongest signal, checked first -------------
    $fw = _KS_GetField -Obj $Config -Name 'firmware' -Default $null
    $fwHint = [string](_KS_GetField -Obj $fw -Name 'hint' -Default 'firmware-target')
    $fwDepth = [int](_KS_GetField -Obj $fw -Name 'depth' -Default 2)
    foreach ($file in @(_KS_GetField -Obj $fw -Name 'rootFiles' -Default @())) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath ([string]$file)) -PathType Leaf) { & $hint $fwHint "$file at the repo root"; $manifest = [string](_KS_GetField -Obj $fw -Name 'manifest' -Default 'firmware'); break }
    }
    if (-not $hints.Contains($fwHint)) {
        # -Filter, not -Include: the filter runs in the provider, so a node_modules tree two levels down is not enumerated file by file.
        $sketches = @(Get-ChildItem -LiteralPath $LocalPath -Filter ([string](_KS_GetField -Obj $fw -Name 'sketchGlob' -Default '*.ino')) -Recurse -Depth $fwDepth -File -ErrorAction SilentlyContinue | Select-Object -First 3)
        if ($sketches.Count -gt 0) {
            & $hint $fwHint ('{0} sketch within {1} directory levels' -f $sketches[0].Name, $fwDepth)
            if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $fw -Name 'manifest' -Default 'firmware') }
            foreach ($s in $sketches) { $entryPoints.Add($s.Name) | Out-Null }
        }
    }

    # --- PowerShell: a module manifest is a library; loose scripts are tooling
    $ps = _KS_GetField -Obj $Config -Name 'powershell' -Default $null
    $moduleHint = [string](_KS_GetField -Obj $ps -Name 'moduleHint' -Default 'module-manifest')
    $manifestExclude = [string](_KS_GetField -Obj $ps -Name 'manifestExclude' -Default '(?i)PSScriptAnalyzer(Settings)?\.psd1$')
    $manifestKeys = @(_KS_GetField -Obj $ps -Name 'manifestKeys' -Default @('RootModule', 'ModuleVersion'))
    $manifestKeyPattern = '(?im)^\s*(' + (($manifestKeys | ForEach-Object { [regex]::Escape([string]$_) }) -join '|') + ')\s*='
    $psd1 = @(Get-ChildItem -LiteralPath $LocalPath -Filter ([string](_KS_GetField -Obj $ps -Name 'manifestGlob' -Default '*.psd1')) -Recurse -Depth ([int](_KS_GetField -Obj $ps -Name 'manifestDepth' -Default 1)) -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch $manifestExclude } | Select-Object -First 5)
    foreach ($m in $psd1) {
        $text = ''
        try { $text = Get-Content -LiteralPath $m.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { continue }
        if ($text -match $manifestKeyPattern) {
            & $hint $moduleHint ('{0} declares a PowerShell module' -f $m.Name)
            if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $ps -Name 'moduleManifest' -Default 'powershell-module') }
            break
        }
    }
    $scriptExclude = [string](_KS_GetField -Obj $ps -Name 'scriptExclude' -Default '(?i)\.Tests\.ps1$')
    $rootScripts = @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch $scriptExclude } | Select-Object -First ([int](_KS_GetField -Obj $ps -Name 'maxEntryPoints' -Default 6)))
    if ($rootScripts.Count -gt 0) {
        foreach ($s in $rootScripts) { $entryPoints.Add($s.Name) | Out-Null }
        if (-not $hints.Contains($moduleHint)) {
            & $hint ([string](_KS_GetField -Obj $ps -Name 'scriptHint' -Default 'script-entry')) ('{0} PowerShell script(s) at the repo root, no module manifest' -f $rootScripts.Count)
            if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $ps -Name 'scriptManifest' -Default 'powershell-scripts') }
        }
    }

    # --- Node: bin = tool, framework deps = app, main/exports = library ------
    $node = _KS_GetField -Obj $Config -Name 'node' -Default $null
    $packagePath = Join-Path $LocalPath 'package.json'
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        $pkg = $null
        try { $pkg = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { $pkg = $null }
        if ($null -ne $pkg) {
            if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $node -Name 'manifest' -Default 'package.json') }
            $deps = [System.Collections.Generic.List[string]]::new()
            foreach ($section in @('dependencies', 'devDependencies')) {
                $block = _KS_GetField -Obj $pkg -Name $section -Default $null
                if ($null -ne $block) { foreach ($p in @($block.PSObject.Properties)) { $deps.Add([string]$p.Name) | Out-Null } }
            }
            $bin = _KS_GetField -Obj $pkg -Name 'bin' -Default $null
            $main = [string](_KS_GetField -Obj $pkg -Name 'main' -Default '')
            $exports = _KS_GetField -Obj $pkg -Name 'exports' -Default $null
            $isPrivate = [bool](_KS_GetField -Obj $pkg -Name 'private' -Default $false)
            $workspaces = _KS_GetField -Obj $pkg -Name 'workspaces' -Default $null
            $appDependencyList = @(_KS_GetField -Obj $node -Name 'appDependencies' -Default @() | ForEach-Object { [string]$_ })
            $appDeps = @($deps | Where-Object { $_ -in $appDependencyList })
            if ($null -ne $bin) {
                & $hint ([string](_KS_GetField -Obj $node -Name 'cliHint' -Default 'cli-entry')) 'package.json declares a bin entry'
                if ($bin -is [string]) { $entryPoints.Add($bin) | Out-Null }
                else { foreach ($b in @($bin.PSObject.Properties)) { $entryPoints.Add([string]$b.Value) | Out-Null } }
            }
            if ($appDeps.Count -gt 0) { & $hint ([string](_KS_GetField -Obj $node -Name 'appHint' -Default 'web-app')) ('package.json depends on {0}' -f ($appDeps -join ', ')) }
            if (-not [string]::IsNullOrWhiteSpace($main)) { $entryPoints.Add($main) | Out-Null }
            if (($null -ne $exports -or -not [string]::IsNullOrWhiteSpace($main)) -and $null -eq $bin -and $appDeps.Count -eq 0 -and -not $isPrivate) {
                & $hint ([string](_KS_GetField -Obj $node -Name 'libraryHint' -Default 'library-manifest')) 'package.json is publishable (main/exports, not private, no app framework)'
            }
            if ($null -ne $workspaces) { & $hint ([string](_KS_GetField -Obj $node -Name 'workspaceHint' -Default 'monorepo')) 'package.json declares workspaces' }
        }
    }

    # --- A served page is an application whatever builds it ------------------
    $page = _KS_GetField -Obj $Config -Name 'servedPage' -Default $null
    foreach ($file in @(_KS_GetField -Obj $page -Name 'files' -Default @())) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath ([string]$file)) -PathType Leaf) { & $hint ([string](_KS_GetField -Obj $page -Name 'hint' -Default 'web-app')) "$file is a served page"; $entryPoints.Add([string]$file) | Out-Null; break }
    }

    # --- .NET: OutputType decides; the Web SDK is an app --------------------
    $dn = _KS_GetField -Obj $Config -Name 'dotnet' -Default $null
    $dnDepth = [int](_KS_GetField -Obj $dn -Name 'depth' -Default 2)
    $csproj = @(foreach ($projGlob in @(_KS_GetField -Obj $dn -Name 'projectGlobs' -Default @('*.csproj'))) { Get-ChildItem -LiteralPath $LocalPath -Filter ([string]$projGlob) -Recurse -Depth $dnDepth -File -ErrorAction SilentlyContinue | Select-Object -First 8 })
    foreach ($proj in $csproj) {
        $text = ''
        try { $text = Get-Content -LiteralPath $proj.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { continue }
        if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $dn -Name 'manifest' -Default 'dotnet-project') }
        if ($text -match [string](_KS_GetField -Obj $dn -Name 'webSdkPattern' -Default '(?i)Sdk="Microsoft\.NET\.Sdk\.Web"')) { & $hint ([string](_KS_GetField -Obj $dn -Name 'webHint' -Default 'web-app')) ('{0} uses the ASP.NET Web SDK' -f $proj.Name); $entryPoints.Add($proj.Name) | Out-Null }
        elseif ($text -match [string](_KS_GetField -Obj $dn -Name 'exePattern' -Default '(?i)<OutputType>\s*(Win)?Exe\s*</OutputType>')) { & $hint ([string](_KS_GetField -Obj $dn -Name 'exeHint' -Default 'executable-manifest')) ('{0} builds an executable' -f $proj.Name); $entryPoints.Add($proj.Name) | Out-Null }
        elseif ($text -match [string](_KS_GetField -Obj $dn -Name 'testPattern' -Default '(?i)<IsTestProject>\s*true')) { continue }
        else { & $hint ([string](_KS_GetField -Obj $dn -Name 'libraryHint' -Default 'library-manifest')) ('{0} builds a class library' -f $proj.Name) }
    }

    # --- Python: project.scripts = tool, setup.py/pyproject = library, app.py = app
    $py = _KS_GetField -Obj $Config -Name 'python' -Default $null
    $pyproject = Join-Path $LocalPath 'pyproject.toml'
    if (Test-Path -LiteralPath $pyproject -PathType Leaf) {
        $text = ''
        try { $text = Get-Content -LiteralPath $pyproject -Raw -Encoding UTF8 -ErrorAction Stop } catch { $text = '' }
        if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $py -Name 'pyprojectManifest' -Default 'pyproject') }
        if ($text -match [string](_KS_GetField -Obj $py -Name 'scriptsPattern' -Default '(?im)^\s*\[project\.scripts\]')) { & $hint ([string](_KS_GetField -Obj $py -Name 'cliHint' -Default 'cli-entry')) 'pyproject.toml declares [project.scripts]' }
        elseif ($text -match [string](_KS_GetField -Obj $py -Name 'packagePattern' -Default '(?im)^\s*\[(project|tool\.poetry)\]')) { & $hint ([string](_KS_GetField -Obj $py -Name 'libraryHint' -Default 'library-manifest')) 'pyproject.toml declares a package' }
    }
    elseif (Test-Path -LiteralPath (Join-Path $LocalPath 'setup.py') -PathType Leaf) {
        if ($manifest -eq 'none') { $manifest = [string](_KS_GetField -Obj $py -Name 'setupManifest' -Default 'setup.py') }
        & $hint ([string](_KS_GetField -Obj $py -Name 'libraryHint' -Default 'library-manifest')) 'setup.py at the repo root'
    }
    $webEntries = @(_KS_GetField -Obj $py -Name 'webEntryFiles' -Default @() | ForEach-Object { [string]$_ })
    foreach ($pyApp in @(_KS_GetField -Obj $py -Name 'entryFiles' -Default @())) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath ([string]$pyApp)) -PathType Leaf) {
            $entryPoints.Add([string]$pyApp) | Out-Null
            if ([string]$pyApp -in $webEntries) { & $hint ([string](_KS_GetField -Obj $py -Name 'webHint' -Default 'web-app')) "$pyApp at the repo root" }
        }
    }

    # --- README purpose line: what the owner says it is ---------------------
    $purpose = Get-RepoReadmePurposeLine -LocalPath $LocalPath -Config $Config
    if (-not [string]::IsNullOrWhiteSpace($purpose)) {
        foreach ($rule in @(_KS_GetField -Obj $Config -Name 'wording' -Default @())) {
            $pattern = [string](_KS_GetField -Obj $rule -Name 'pattern' -Default '')
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            if ($purpose -match ('(?i)' + $pattern)) { & $hint ([string](_KS_GetField -Obj $rule -Name 'hint' -Default 'wording')) ('README purpose line says "{0}"' -f $Matches[0]) }
        }
    }

    return [pscustomobject]@{
        signalModel   = $signalModel
        manifest      = $manifest
        entryPoints   = @($entryPoints | Select-Object -Unique)
        readmePurpose = $purpose
        hints         = @($hints)
        evidence      = @($evidence)
    }
}

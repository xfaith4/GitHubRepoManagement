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
    produces, so a wrong call is a data change, not a code change. Dot-sourced
    by Portfolio.Assessment.ps1; pure over the filesystem, never over the API.
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

function Get-RepoReadmePurposeLine {
    <#
    .SYNOPSIS
        The first prose line of the root README - the sentence a person reads to learn what the repository is for.
    .DESCRIPTION
        Skips headings, badges, images, HTML, tables, rules and blank lines;
        returns '' when there is no README or no prose in its first 40 lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowEmptyString()][string]$LocalPath = '')

    if ([string]::IsNullOrWhiteSpace($LocalPath)) { return '' }
    $readme = $null
    foreach ($name in @('README.md', 'readme.md', 'README.MD', 'README', 'README.txt')) {
        $candidate = Join-Path $LocalPath $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $readme = $candidate; break }
    }
    if ($null -eq $readme) { return '' }
    $lines = @()
    try { $lines = @(Get-Content -LiteralPath $readme -TotalCount 40 -Encoding UTF8 -ErrorAction Stop) } catch { return '' }
    foreach ($raw in $lines) {
        $line = [string]$raw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $t = $line.Trim() -replace '^>\s*', ''
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -match '^(#|!\[|<|\[!\[|\[!|---|\*\*\*|___|\||```|>\s*\[!)') { continue }
        # Strip emphasis and inline links so the rule regexes see plain words.
        $t = $t -replace '\[([^\]]+)\]\([^)]*\)', '$1' -replace '[*_`]', ''
        $t = $t -replace '\s+', ' '
        if ($t.Length -gt 240) { $t = $t.Substring(0, 240).TrimEnd() }
        return $t
    }
    return ''
}

function Get-RepoKindSignalProfile {
    <#
    .SYNOPSIS
        Manifest, entry-point and README-purpose signals for one checkout, plus the hint ids the kind rules match on.
    .DESCRIPTION
        Returns [pscustomobject]{ manifest, entryPoints[], readmePurpose, hints[], evidence[] }.
        `hints` is the contract with foundation-domains.json: a stable list of
        ids, each backed by one evidence line. A github-only entry (no local
        checkout) gets the empty profile, and the rules then resolve 'unknown'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowEmptyString()][string]$LocalPath = '')

    $hints = [System.Collections.Generic.List[string]]::new()
    $evidence = [System.Collections.Generic.List[string]]::new()
    $entryPoints = [System.Collections.Generic.List[string]]::new()
    $manifest = 'none'
    $hint = {
        param([string]$Id, [string]$Because)
        if (-not $hints.Contains($Id)) { $hints.Add($Id) | Out-Null; $evidence.Add(('{0}: {1}' -f $Id, $Because)) | Out-Null }
    }
    $empty = [pscustomobject]@{ manifest = 'none'; entryPoints = @(); readmePurpose = ''; hints = @(); evidence = @() }
    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path -LiteralPath $LocalPath -PathType Container -ErrorAction SilentlyContinue)) {
        return $empty
    }

    # --- Firmware targets: the strongest signal, checked first -------------
    foreach ($fw in @('platformio.ini', 'sdkconfig', 'sdkconfig.defaults', 'boards.txt')) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath $fw) -PathType Leaf) { & $hint 'firmware-target' "$fw at the repo root"; $manifest = 'firmware'; break }
    }
    if (-not $hints.Contains('firmware-target')) {
        # -Filter, not -Include: the filter runs in the provider, so a node_modules tree two levels down is not enumerated file by file.
        $sketches = @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ino' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue | Select-Object -First 3)
        if ($sketches.Count -gt 0) {
            & $hint 'firmware-target' ('{0} Arduino sketch within two directory levels' -f $sketches[0].Name)
            if ($manifest -eq 'none') { $manifest = 'firmware' }
            foreach ($s in $sketches) { $entryPoints.Add($s.Name) | Out-Null }
        }
    }

    # --- PowerShell: a module manifest is a library; loose scripts are tooling
    $psd1 = @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.psd1' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(?i)PSScriptAnalyzer(Settings)?\.psd1$' } | Select-Object -First 5)
    foreach ($m in $psd1) {
        $text = ''
        try { $text = Get-Content -LiteralPath $m.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { continue }
        if ($text -match '(?im)^\s*(RootModule|ModuleVersion|FunctionsToExport)\s*=') {
            & $hint 'module-manifest' ('{0} declares a PowerShell module' -f $m.Name)
            if ($manifest -eq 'none') { $manifest = 'powershell-module' }
            break
        }
    }
    $rootScripts = @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(?i)\.Tests\.ps1$' } | Select-Object -First 6)
    if ($rootScripts.Count -gt 0) {
        foreach ($s in $rootScripts) { $entryPoints.Add($s.Name) | Out-Null }
        if (-not $hints.Contains('module-manifest')) {
            & $hint 'script-entry' ('{0} PowerShell script(s) at the repo root, no module manifest' -f $rootScripts.Count)
            if ($manifest -eq 'none') { $manifest = 'powershell-scripts' }
        }
    }

    # --- Node: bin = tool, framework deps = app, main/exports = library ------
    $packagePath = Join-Path $LocalPath 'package.json'
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        $pkg = $null
        try { $pkg = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { $pkg = $null }
        if ($null -ne $pkg) {
            if ($manifest -eq 'none') { $manifest = 'package.json' }
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
            $appDeps = @($deps | Where-Object { $_ -in @('react', 'react-dom', 'next', 'vue', 'nuxt', 'svelte', '@angular/core', 'express', 'fastify', 'koa', 'electron', 'vite', 'firebase') })
            if ($null -ne $bin) {
                & $hint 'cli-entry' 'package.json declares a bin entry'
                foreach ($b in @($bin.PSObject.Properties)) { $entryPoints.Add([string]$b.Value) | Out-Null }
            }
            if ($appDeps.Count -gt 0) { & $hint 'web-app' ('package.json depends on {0}' -f ($appDeps -join ', ')) }
            if (-not [string]::IsNullOrWhiteSpace($main)) { $entryPoints.Add($main) | Out-Null }
            if (($null -ne $exports -or -not [string]::IsNullOrWhiteSpace($main)) -and $null -eq $bin -and $appDeps.Count -eq 0 -and -not $isPrivate) {
                & $hint 'library-manifest' 'package.json is publishable (main/exports, not private, no app framework)'
            }
            if ($null -ne $workspaces) { & $hint 'monorepo' 'package.json declares workspaces' }
        }
    }

    # --- A served page is an application whatever builds it ------------------
    foreach ($page in @('index.html', 'public/index.html', 'web/index.html', 'src/index.html')) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath $page) -PathType Leaf) { & $hint 'web-app' "$page is a served page"; $entryPoints.Add($page) | Out-Null; break }
    }

    # --- .NET: OutputType decides; the Web SDK is an app --------------------
    $csproj = @(foreach ($projGlob in @('*.csproj', '*.fsproj')) { Get-ChildItem -LiteralPath $LocalPath -Filter $projGlob -Recurse -Depth 2 -File -ErrorAction SilentlyContinue | Select-Object -First 8 })
    foreach ($proj in $csproj) {
        $text = ''
        try { $text = Get-Content -LiteralPath $proj.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { continue }
        if ($manifest -eq 'none') { $manifest = 'dotnet-project' }
        if ($text -match '(?i)Sdk="Microsoft\.NET\.Sdk\.Web"') { & $hint 'web-app' ('{0} uses the ASP.NET Web SDK' -f $proj.Name); $entryPoints.Add($proj.Name) | Out-Null }
        elseif ($text -match '(?i)<OutputType>\s*(Win)?Exe\s*</OutputType>') { & $hint 'executable-manifest' ('{0} builds an executable' -f $proj.Name); $entryPoints.Add($proj.Name) | Out-Null }
        elseif ($text -match '(?i)<IsTestProject>\s*true') { continue }
        else { & $hint 'library-manifest' ('{0} builds a class library' -f $proj.Name) }
    }

    # --- Python: project.scripts = tool, setup.py/pyproject = library, app.py = app
    $pyproject = Join-Path $LocalPath 'pyproject.toml'
    if (Test-Path -LiteralPath $pyproject -PathType Leaf) {
        $text = ''
        try { $text = Get-Content -LiteralPath $pyproject -Raw -Encoding UTF8 -ErrorAction Stop } catch { $text = '' }
        if ($manifest -eq 'none') { $manifest = 'pyproject' }
        if ($text -match '(?im)^\s*\[project\.scripts\]') { & $hint 'cli-entry' 'pyproject.toml declares [project.scripts]' }
        elseif ($text -match '(?im)^\s*\[(project|tool\.poetry)\]') { & $hint 'library-manifest' 'pyproject.toml declares a package' }
    }
    elseif (Test-Path -LiteralPath (Join-Path $LocalPath 'setup.py') -PathType Leaf) {
        if ($manifest -eq 'none') { $manifest = 'setup.py' }
        & $hint 'library-manifest' 'setup.py at the repo root'
    }
    foreach ($pyApp in @('app.py', 'main.py', 'manage.py', 'wsgi.py', 'asgi.py')) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath $pyApp) -PathType Leaf) {
            $entryPoints.Add($pyApp) | Out-Null
            if ($pyApp -in @('manage.py', 'wsgi.py', 'asgi.py')) { & $hint 'web-app' "$pyApp at the repo root" }
        }
    }

    # --- README purpose line: what the owner says it is ---------------------
    $purpose = Get-RepoReadmePurposeLine -LocalPath $LocalPath
    if (-not [string]::IsNullOrWhiteSpace($purpose)) {
        $wording = [ordered]@{
            'experiment-wording'  = '\b(experiment(al)?|prototype|proof[- ]of[- ]concept|spike|sandbox|playground|scratch(pad)?|bootstrap|phase[- ]?0)\b'
            'firmware-wording'    = '\b(firmware|arduino|sketch(es)?|esp(32|8266)|microcontroller|platformio|ws2812b?|neopixel|led strip)\b'
            'library-wording'     = '\b(library|module|sdk|client|wrapper|package|api client|bindings?)\b'
            'tooling-wording'     = '\b(tool|utility|utilities|script(s)?|cli|command[- ]line|helper|automation|toolbox|console)\b'
            'application-wording' = '\b(app|application|web app|dashboard|portal|site|website|workbench|studio|engine|server|service)\b'
        }
        foreach ($id in $wording.Keys) {
            if ($purpose -match ('(?i)' + $wording[$id])) { & $hint $id ('README purpose line says "{0}"' -f $Matches[0]) }
        }
    }

    return [pscustomobject]@{
        manifest      = $manifest
        entryPoints   = @($entryPoints | Select-Object -Unique)
        readmePurpose = $purpose
        hints         = @($hints)
        evidence      = @($evidence)
    }
}

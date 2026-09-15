<#
.SYNOPSIS
    Release 3.6 milestone 1 - one explainable conclusion per repository.
.DESCRIPTION
    Composes a per-repo conclusion (strengthen | appropriate-as-is |
    insufficiently-understood) from signals the portfolio index already
    carries: README score, doc finding count, roadmap state and maturity,
    the structure audit, lifecycle and curation. Domains, statuses, kinds and
    per-kind applicability are data in backend/config/foundation-domains.json;
    nothing here names a domain by hand.

    Reads the cached index only. It never scans, so it is safe on the request
    thread (the module smoke's freeze tripwire holds).

    Param-less on purpose: the API host dot-sources this file, and a
    param() block here would overwrite the route's own variables.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _PC_PropertyNames {
    param([object]$Obj)
    if ($null -eq $Obj) { return @() }
    if ($Obj -is [System.Collections.IDictionary]) { return @($Obj.Keys | ForEach-Object { [string]$_ }) }
    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Obj.PSObject) { foreach ($prop in $Obj.PSObject.Properties) { $names.Add([string]$prop.Name) | Out-Null } }
    return @($names)
}

function _PC_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($null -eq $Obj.PSObject) { return $Default }
    foreach ($prop in $Obj.PSObject.Properties) { if ($prop.Name -eq $Name) { return $prop.Value } }
    return $Default
}

function _PC_Strings {
    param([object[]]$Values)
    return @($Values | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-FoundationDomainsConfig {
    <#
    .SYNOPSIS
        Load backend/config/foundation-domains.json; $null when absent or unreadable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    try {
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8)
    } catch {
        return $null
    }
    if ($null -eq $parsed) { return $null }
    if ([string](_PC_GetField -Obj $parsed -Name 'schemaVersion' -Default '') -ne 'v1') { return $null }
    if (@(_PC_GetField -Obj $parsed -Name 'domains' -Default @()).Count -eq 0) { return $null }
    return $parsed
}

function _PC_ResolvePath {
    <#
        Walk a dotted path over an entry. An array along the way maps the rest
        of the path over its elements, so 'technologies.id' yields the id list
        and 'kindSignals.hints' the hint list. Missing -> @().
    #>
    param([object]$Obj, [string]$Path)
    $current = @($Obj)
    foreach ($segment in ($Path -split '\.')) {
        $next = [System.Collections.Generic.List[object]]::new()
        foreach ($node in $current) {
            if ($null -eq $node) { continue }
            $value = _PC_GetField -Obj $node -Name $segment -Default $null
            if ($null -eq $value) { continue }
            if ($value -is [string] -or $value -isnot [System.Collections.IEnumerable]) { $next.Add($value) | Out-Null }
            else { foreach ($v in @($value)) { if ($null -ne $v) { $next.Add($v) | Out-Null } } }
        }
        $current = @($next)
        if ($current.Count -eq 0) { return @() }
    }
    return @($current)
}

function Resolve-RepositoryKind {
    <#
    .SYNOPSIS
        Pick the repository kind from the config's detection rules; 'unknown' when nothing matches.
    .DESCRIPTION
        Rules are tried in file order. Every matching rule is kept as a ranked
        candidate (first per kind wins its basis) so honest ambiguity is
        visible; `kind` is the first candidate. A rule carries `when` (every
        named field equals its value) and/or `whenAny` (every named path holds
        at least one of the listed values). Paths are dotted and array-aware,
        so `kindSignals.hints` and `technologies.id` work. An 'unknown' verdict
        names the hints that were present and matched no rule, so the next
        rule can be added as data (steering Rung 1).
        Returns { kind, basis, candidates[] of { kind, basis, matchedOn[] }, hints[] }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][object]$Config
    )

    $detection = _PC_GetField -Obj $Config -Name 'kindDetection' -Default $null
    $rules = @(_PC_GetField -Obj $detection -Name 'rules' -Default @())
    $hintsPresent = @(_PC_Strings -Values @(_PC_ResolvePath -Obj $Entry -Path 'kindSignals.hints'))
    $candidates = [System.Collections.Generic.List[object]]::new()
    $seenKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in $rules) {
        $when = _PC_GetField -Obj $rule -Name 'when' -Default $null
        $whenAny = _PC_GetField -Obj $rule -Name 'whenAny' -Default $null
        if ($null -eq $when -and $null -eq $whenAny) { continue }
        $matched = $true
        $matchedOn = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @(_PC_PropertyNames -Obj $when)) {
            $expected = [string](_PC_GetField -Obj $when -Name $name -Default '')
            $actual = [string](_PC_GetField -Obj $Entry -Name $name -Default '')
            if ($actual -ne $expected) { $matched = $false; break }
            $matchedOn.Add("$name=$expected") | Out-Null
        }
        if ($matched) {
            foreach ($path in @(_PC_PropertyNames -Obj $whenAny)) {
                $accepted = @(_PC_Strings -Values @(_PC_GetField -Obj $whenAny -Name $path -Default @()))
                $present = @(_PC_Strings -Values @(_PC_ResolvePath -Obj $Entry -Path $path))
                $hit = @($present | Where-Object { $_ -in $accepted } | Select-Object -First 1)
                if ($hit.Count -eq 0) { $matched = $false; break }
                $matchedOn.Add("$path=$($hit[0])") | Out-Null
            }
        }
        if (-not $matched -or $matchedOn.Count -eq 0) { continue }
        $kind = [string](_PC_GetField -Obj $rule -Name 'kind' -Default 'unknown')
        if (-not $seenKinds.Add($kind)) { continue }
        $basis = [string](_PC_GetField -Obj $rule -Name 'basis' -Default '')
        if ([string]::IsNullOrWhiteSpace($basis)) { $basis = $matchedOn -join ', ' }
        $candidates.Add([pscustomobject]@{ kind = $kind; basis = $basis; matchedOn = @($matchedOn) }) | Out-Null
    }
    if ($candidates.Count -gt 0) {
        return [pscustomobject]@{
            kind       = [string]$candidates[0].kind
            basis      = [string]$candidates[0].basis
            candidates = @($candidates)
            hints      = @($hintsPresent)
        }
    }
    $unknownBasis = 'no kind signal in the index; every scored domain applies'
    if ($hintsPresent.Count -gt 0) {
        $unknownBasis = 'no kind rule matched the hints present ({0}); every scored domain applies' -f ($hintsPresent -join ', ')
    }
    return [pscustomobject]@{ kind = 'unknown'; basis = $unknownBasis; candidates = @(); hints = @($hintsPresent) }
}

function _PC_KindCoherenceObservation {
    <#
        Steering extension 2: manifest-vs-README disagreement is its own
        finding - observed, never judged. Emitted only when the manifest hints
        and the wording hints each name kinds and share none. Carries its
        provenance and canonicalEffect: none (steering section 4, rule 1).
    #>
    param([object]$Entry, [object]$Config, [object[]]$Hints)
    $detection = _PC_GetField -Obj $Config -Name 'kindDetection' -Default $null
    $hintKinds = _PC_GetField -Obj $detection -Name 'hintKinds' -Default $null
    if ($null -eq $hintKinds -or @($Hints).Count -eq 0) { return $null }
    $manifestKinds = [System.Collections.Generic.List[string]]::new()
    $manifestHints = [System.Collections.Generic.List[string]]::new()
    $wordingKinds = [System.Collections.Generic.List[string]]::new()
    $wordingHints = [System.Collections.Generic.List[string]]::new()
    foreach ($h in @($Hints)) {
        $kind = [string](_PC_GetField -Obj $hintKinds -Name ([string]$h) -Default '')
        if ([string]::IsNullOrWhiteSpace($kind)) { continue }
        if ([string]$h -like '*-wording') {
            if (-not $wordingKinds.Contains($kind)) { $wordingKinds.Add($kind) | Out-Null }
            $wordingHints.Add([string]$h) | Out-Null
        } else {
            if (-not $manifestKinds.Contains($kind)) { $manifestKinds.Add($kind) | Out-Null }
            $manifestHints.Add([string]$h) | Out-Null
        }
    }
    if ($manifestKinds.Count -eq 0 -or $wordingKinds.Count -eq 0) { return $null }
    $shared = @($manifestKinds | Where-Object { $_ -in $wordingKinds })
    if ($shared.Count -gt 0) { return $null }
    $signals = _PC_GetField -Obj $Entry -Name 'kindSignals' -Default $null
    return [pscustomobject]@{
        id              = 'kind-coherence'
        canonicalEffect = 'none'
        statement       = ('manifests say {0} ({1}); the README purpose line says {2} ({3})' -f ($manifestKinds -join '/'), ($manifestHints -join ', '), ($wordingKinds -join '/'), ($wordingHints -join ', '))
        provenance      = [pscustomobject]@{
            source       = 'kindSignals.hints on the index entry'
            signalModel  = [string](_PC_GetField -Obj $signals -Name 'signalModel' -Default '')
            mapping      = 'foundation-domains.json kindDetection.hintKinds'
            modelVersion = [string](_PC_GetField -Obj $Config -Name 'modelVersion' -Default '')
        }
        changedVerdict  = $false
    }
}

function _PC_KindDefinition {
    param([object]$Config, [string]$Kind)
    $kinds = @(_PC_GetField -Obj $Config -Name 'kinds' -Default @())
    $match = @($kinds | Where-Object { [string](_PC_GetField -Obj $_ -Name 'id' -Default '') -eq $Kind } | Select-Object -First 1)
    if ($match.Count -gt 0) { return $match[0] }
    return $null
}

function _PC_EvaluateDomain {
    <#
        Returns @{ status; evidence[] } for one scored domain against one entry.
        Every evidence string is a positive observation, never "no findings".
    #>
    param([object]$Domain, [object]$Entry)

    $id = [string](_PC_GetField -Obj $Domain -Name 'id' -Default '')
    $thresholds = _PC_GetField -Obj $Domain -Name 'thresholds' -Default $null
    $evidence = [System.Collections.Generic.List[string]]::new()
    $status = 'missing'

    $hasReadme = [bool](_PC_GetField -Obj $Entry -Name 'hasReadme' -Default $false)
    $readmeScore = [int](_PC_GetField -Obj $Entry -Name 'readmeScore' -Default 0)

    switch ($id) {
        'documentation' {
            $present = [int](_PC_GetField -Obj $thresholds -Name 'presentReadmeScore' -Default 70)
            $weak = [int](_PC_GetField -Obj $thresholds -Name 'weakReadmeScore' -Default 30)
            $docFindings = [int](_PC_GetField -Obj $Entry -Name 'docFindingCount' -Default 0)
            if (-not $hasReadme) {
                $status = 'missing'; $evidence.Add('README.md is absent')
            } elseif ($readmeScore -ge $present) {
                $status = 'present'; $evidence.Add("README present, score $readmeScore/100")
            } elseif ($readmeScore -ge $weak) {
                $status = 'weak'; $evidence.Add("README present but thin, score $readmeScore/100")
            } else {
                $status = 'weak'; $evidence.Add("README present but nearly empty, score $readmeScore/100")
            }
            if ($docFindings -gt 0) { $evidence.Add("$docFindings documentation finding(s) recorded by the doc audit") }
        }
        'purpose' {
            $present = [int](_PC_GetField -Obj $thresholds -Name 'presentReadmeScore' -Default 50)
            if (-not $hasReadme) {
                $status = 'missing'; $evidence.Add('nothing written down states what the repository is for (no README.md)')
            } elseif ($readmeScore -ge $present) {
                $status = 'present'; $evidence.Add("README states the purpose (score $readmeScore/100 against the README contract)")
            } else {
                $status = 'weak'; $evidence.Add("README exists but scores $readmeScore/100 against the README contract; the purpose is not clearly stated")
            }
        }
        'planning' {
            $hasRoadmap = [bool](_PC_GetField -Obj $Entry -Name 'hasRoadmap' -Default $false)
            $roadmapState = [string](_PC_GetField -Obj $Entry -Name 'roadmapState' -Default 'missing')
            $maturity = [string](_PC_GetField -Obj $Entry -Name 'maturityLevel' -Default 'L0-Absent')
            $pending = [int](_PC_GetField -Obj $Entry -Name 'pendingCount' -Default 0)
            $presentLevels = @(_PC_GetField -Obj $thresholds -Name 'presentMaturity' -Default @('L3-Contract-Ready', 'L4-Orchestration-Ready'))
            $weakLevels = @(_PC_GetField -Obj $thresholds -Name 'weakMaturity' -Default @('L1-Informal', 'L2-Structured'))
            $absentReadsAs = [string](_PC_GetField -Obj $Domain -Name 'absentReadsAs' -Default 'no plan recorded')
            if (-not $hasRoadmap -or $roadmapState -eq 'missing') {
                $status = 'missing'; $evidence.Add("$absentReadsAs (no ROADMAP.md)")
            } elseif ($roadmapState -eq 'no-checklist') {
                # Not a gap in the repository — a gap in what this console can
                # read. Say which it is, or the operator repairs the wrong thing.
                $status = 'weak'; $evidence.Add('ROADMAP.md was read in full and plans in prose rather than "- [ ]" items, so no unit of work can be tracked from it')
            } elseif ($roadmapState -eq 'parse-error') {
                $status = 'weak'; $evidence.Add('ROADMAP.md exists but could not be parsed')
            } elseif ($maturity -in $presentLevels) {
                $status = 'present'; $evidence.Add("roadmap at $maturity with $pending pending item(s)")
            } elseif ($maturity -in $weakLevels) {
                $status = 'weak'; $evidence.Add("roadmap at $maturity - below the contract-ready bar - with $pending pending item(s)")
            } else {
                $status = 'weak'; $evidence.Add("ROADMAP.md exists but audits as '$maturity' ($absentReadsAs in contract terms)")
            }
            if ($roadmapState -eq 'complete') { $evidence.Add('every recorded item is complete') }
        }
        'structure' {
            $findings = @(_PC_GetField -Obj $Entry -Name 'structureFindings' -Default @())
            $critical = @($findings | Where-Object { [string](_PC_GetField -Obj $_ -Name 'severity' -Default '') -eq 'critical' })
            $warnings = @($findings | Where-Object { [string](_PC_GetField -Obj $_ -Name 'severity' -Default '') -ne 'critical' })
            $repoType = [string](_PC_GetField -Obj $Entry -Name 'repoType' -Default 'other')
            if ($critical.Count -gt 0) {
                $status = 'missing'
                $evidence.Add(("{0} critical structure gap(s) for a {1} repository: {2}" -f $critical.Count, $repoType, (@($critical | ForEach-Object { [string](_PC_GetField -Obj $_ -Name 'target' -Default (_PC_GetField -Obj $_ -Name 'kind' -Default 'item')) }) -join ', ')))
            } elseif ($warnings.Count -gt 0) {
                $status = 'weak'
                $evidence.Add(("{0} structure warning(s) for a {1} repository: {2}" -f $warnings.Count, $repoType, (@($warnings | ForEach-Object { [string](_PC_GetField -Obj $_ -Name 'target' -Default (_PC_GetField -Obj $_ -Name 'kind' -Default 'item')) }) -join ', ')))
            } else {
                $status = 'present'
                $evidence.Add("layout meets the $repoType structure standard")
            }
            if ([bool](_PC_GetField -Obj $Entry -Name 'hasCiSignal' -Default $false)) { $evidence.Add('a CI workflow is present') }
            if ([bool](_PC_GetField -Obj $Entry -Name 'hasTestSignal' -Default $false)) { $evidence.Add('a test signal is present') }
        }
        default {
            $status = 'not-scored'
            $evidence.Add("domain '$id' has no evaluator in this version")
        }
    }
    return @{ status = $status; evidence = @($evidence) }
}

function _PC_ObserveUnscored {
    <# Intentional engineering is defined, not scored: report what is observed. #>
    param([object]$Entry)
    $evidence = [System.Collections.Generic.List[string]]::new()
    if ([bool](_PC_GetField -Obj $Entry -Name 'hasTestSignal' -Default $false)) { $evidence.Add('test signal observed') } else { $evidence.Add('no test signal observed') }
    if ([bool](_PC_GetField -Obj $Entry -Name 'hasCiSignal' -Default $false)) { $evidence.Add('CI workflow observed') } else { $evidence.Add('no CI workflow observed') }
    $conclusion = [string](_PC_GetField -Obj $Entry -Name 'latestWorkflowRunConclusion' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($conclusion)) { $evidence.Add("latest Actions run concluded '$conclusion'") }
    $commits = _PC_GetField -Obj $Entry -Name 'localCommitsLastMonth' -Default $null
    if ($null -ne $commits) { $evidence.Add("$([int]$commits) commit(s) in the last month") }
    $evidence.Add('observed, not judged: this domain is defined but not scored (foundation-domains.json)')
    return @{ status = 'not-scored'; evidence = @($evidence) }
}

function _PC_NextActionFor {
    param([object]$Domain, [object]$Entry)
    $action = _PC_GetField -Obj $Domain -Name 'nextAction' -Default $null
    if ($null -eq $action) { return $null }
    return _PC_ActionFromDefinition -Definition $action -DomainId ([string](_PC_GetField -Obj $Domain -Name 'id' -Default '')) -Entry $Entry
}

function _PC_ActionFromDefinition {
    <# One action object from a config definition ({kind,label,method,route,bodyKeys}) and the entry it targets. #>
    param([object]$Definition, [string]$DomainId, [object]$Entry)
    $action = $Definition
    $body = [ordered]@{}
    foreach ($key in @(_PC_GetField -Obj $action -Name 'bodyKeys' -Default @())) {
        $value = switch ([string]$key) {
            'repoName' { [string](_PC_GetField -Obj $Entry -Name 'repoName' -Default '') }
            'repoPath' { [string](_PC_GetField -Obj $Entry -Name 'localPath' -Default '') }
            default    { [string](_PC_GetField -Obj $Entry -Name $key -Default '') }
        }
        $body[[string]$key] = $value
    }
    return [pscustomobject]@{
        domain = $DomainId
        kind   = [string](_PC_GetField -Obj $action -Name 'kind' -Default '')
        label  = [string](_PC_GetField -Obj $action -Name 'label' -Default '')
        method = [string](_PC_GetField -Obj $action -Name 'method' -Default 'POST')
        route  = [string](_PC_GetField -Obj $action -Name 'route' -Default '')
        body   = [pscustomobject]$body
        previewFirst = $true
    }
}

function _PC_LifecycleConsistency {
    <#
        Steering extension 3: lifecycleState and conclusion are two verdicts
        over the same signals; they may not disagree without saying why. The
        allowed pairs and the explained exceptions are data
        (foundation-domains.json lifecycleConsistency); an exception counts
        only when its `requires` pattern is found in the record's basis lines
        or domain=status facts, and that fact is the explanation's evidence.
        Returns $null when the config carries no table (no claim either way).
    #>
    param([object]$Config, [string]$LifecycleState, [string]$Conclusion, [string[]]$Basis, [object[]]$Domains)
    $table = _PC_GetField -Obj $Config -Name 'lifecycleConsistency' -Default $null
    if ($null -eq $table) { return $null }
    $allowed = _PC_GetField -Obj $table -Name 'allowed' -Default $null
    $states = @(_PC_PropertyNames -Obj $allowed)
    $record = [ordered]@{ lifecycleState = $LifecycleState; conclusion = $Conclusion; holds = $false; agreement = ''; explanation = ''; evidence = @() }
    if ($LifecycleState -notin $states) {
        $record.agreement = 'unknown-lifecycle'
        $record.explanation = "lifecycleState '$LifecycleState' is not in lifecycleConsistency.allowed, so nothing says which conclusions agree with it"
        return [pscustomobject]$record
    }
    $okList = @(_PC_Strings -Values @(_PC_GetField -Obj $allowed -Name $LifecycleState -Default @()))
    if ($Conclusion -in $okList) {
        $record.holds = $true; $record.agreement = 'allowed'
        $record.explanation = "lifecycleState '$LifecycleState' and conclusion '$Conclusion' agree"
        return [pscustomobject]$record
    }
    $facts = [System.Collections.Generic.List[string]]::new()
    foreach ($b in @($Basis)) { if (-not [string]::IsNullOrWhiteSpace($b)) { $facts.Add([string]$b) | Out-Null } }
    foreach ($d in @($Domains)) { $facts.Add(('{0}={1}' -f [string](_PC_GetField -Obj $d -Name 'domain' -Default ''), [string](_PC_GetField -Obj $d -Name 'status' -Default ''))) | Out-Null }
    foreach ($ex in @(_PC_GetField -Obj $table -Name 'exceptions' -Default @())) {
        $exState = [string](_PC_GetField -Obj $ex -Name 'lifecycleState' -Default '*')
        $exConclusion = [string](_PC_GetField -Obj $ex -Name 'conclusion' -Default '*')
        if ($exState -ne '*' -and $exState -ne $LifecycleState) { continue }
        if ($exConclusion -ne '*' -and $exConclusion -ne $Conclusion) { continue }
        $pattern = [string](_PC_GetField -Obj $ex -Name 'requires' -Default '')
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        $hit = @($facts | Where-Object { $_ -match $pattern } | Select-Object -First 1)
        if ($hit.Count -eq 0) { continue }
        $record.holds = $true; $record.agreement = 'explained'
        $record.explanation = [string](_PC_GetField -Obj $ex -Name 'explanation' -Default 'an exception applies')
        $record.evidence = @($hit)
        return [pscustomobject]$record
    }
    $record.agreement = 'contradiction'
    $record.explanation = "lifecycleState '$LifecycleState' and conclusion '$Conclusion' disagree and nothing in the basis explains it"
    return [pscustomobject]$record
}

function Get-RepositoryFoundationConclusion {
    <#
    .SYNOPSIS
        One explainable conclusion for one index entry.
    .OUTPUTS
        [pscustomobject] { repoId, repoName, kind, kindBasis, conclusion, reason,
        basis[], domains[], nextAction, generatedAt }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter()][string]$GeneratedAt = ''
    )

    if ([string]::IsNullOrWhiteSpace($GeneratedAt)) { $GeneratedAt = (Get-Date).ToUniversalTime().ToString('o') }
    $repoId = [string](_PC_GetField -Obj $Entry -Name 'repoId' -Default '')
    $repoName = [string](_PC_GetField -Obj $Entry -Name 'repoName' -Default '')
    $kindVerdict = Resolve-RepositoryKind -Entry $Entry -Config $Config
    $observations = @()
    $coherence = _PC_KindCoherenceObservation -Entry $Entry -Config $Config -Hints @($kindVerdict.hints)
    if ($null -ne $coherence) { $observations = @($coherence) }
    $kindDef = _PC_KindDefinition -Config $Config -Kind $kindVerdict.kind
    $applicability = _PC_GetField -Obj $kindDef -Name 'applicability' -Default $null
    $configDomains = @(_PC_GetField -Obj $Config -Name 'domains' -Default @())

    $domains = [System.Collections.Generic.List[object]]::new()
    $basis = [System.Collections.Generic.List[string]]::new()
    $basis.Add("kind=$($kindVerdict.kind) ($($kindVerdict.basis))")

    # What the product cannot read, it must say so - a finding about the product.
    $sourceCoverage = [string](_PC_GetField -Obj $Entry -Name 'sourceCoverage' -Default 'local')
    $localPath = [string](_PC_GetField -Obj $Entry -Name 'localPath' -Default '')
    $scanStatus = [string](_PC_GetField -Obj $Entry -Name 'lastScanStatus' -Default 'ok')
    $roadmapState = [string](_PC_GetField -Obj $Entry -Name 'roadmapState' -Default 'missing')
    $needs = [System.Collections.Generic.List[string]]::new()
    if ($sourceCoverage -eq 'github' -or [string]::IsNullOrWhiteSpace($localPath)) {
        $needs.Add('a local clone under a scanned root - README, roadmap and layout cannot be read from GitHub metadata alone')
    }
    if ($scanStatus -ne 'ok') {
        $needs.Add("a successful scan (last scan status '$scanStatus')")
    }

    foreach ($domain in $configDomains) {
        $id = [string](_PC_GetField -Obj $domain -Name 'id' -Default '')
        $title = [string](_PC_GetField -Obj $domain -Name 'title' -Default $id)
        $scored = [bool](_PC_GetField -Obj $domain -Name 'scored' -Default $true)
        $naReason = [string](_PC_GetField -Obj $applicability -Name $id -Default '')
        $record = [ordered]@{ domain = $id; title = $title; status = ''; evidence = @(); nextAction = $null }
        if (-not [string]::IsNullOrWhiteSpace($naReason)) {
            $record.status = 'not-applicable'
            $record.evidence = @($naReason)
        } elseif (-not $scored) {
            $observed = _PC_ObserveUnscored -Entry $Entry
            $record.status = $observed.status
            $record.evidence = @($observed.evidence)
        } elseif ($needs.Count -gt 0) {
            $record.status = 'not-scored'
            $record.evidence = @('not evaluated: ' + $needs[0])
        } else {
            $evaluated = _PC_EvaluateDomain -Domain $domain -Entry $Entry
            $record.status = $evaluated.status
            $record.evidence = @($evaluated.evidence)
            if ($record.status -in @('missing', 'weak')) {
                $record.nextAction = _PC_NextActionFor -Domain $domain -Entry $Entry
            }
        }
        $domains.Add([pscustomobject]$record) | Out-Null
    }

    $conclusion = ''
    $reason = ''
    $nextAction = $null
    $kindConclusion = [string](_PC_GetField -Obj $kindDef -Name 'conclusion' -Default '')

    if ($needs.Count -gt 0) {
        $conclusion = 'insufficiently-understood'
        $reason = 'The product cannot reach a conclusion yet; it needs ' + ($needs -join '; ') + '.'
        $basis.Add('sourceCoverage=' + $sourceCoverage)
        $basis.Add('lastScanStatus=' + $scanStatus)
    } elseif ($roadmapState -eq 'no-checklist') {
        $conclusion = 'insufficiently-understood'
        $reason = 'ROADMAP.md was read in full and records its plan in prose rather than "- [ ]" checklist items, so the product needs a checklist-shaped plan before it can rank or dispatch this repository''s work. The file itself is sound. A preview-first repair is offered.'
        $planning = @($domains | Where-Object { $_.domain -eq 'planning' } | Select-Object -First 1)
        if ($planning.Count -gt 0 -and $null -ne $planning[0].nextAction) { $nextAction = $planning[0].nextAction }
        $basis.Add('roadmapState=no-checklist')
    } elseif ($roadmapState -eq 'parse-error') {
        $conclusion = 'insufficiently-understood'
        $reason = 'ROADMAP.md exists but could not be parsed, so the plan cannot be read; the product needs a parseable roadmap. A preview-first repair is offered.'
        $planning = @($domains | Where-Object { $_.domain -eq 'planning' } | Select-Object -First 1)
        if ($planning.Count -gt 0 -and $null -ne $planning[0].nextAction) { $nextAction = $planning[0].nextAction }
        $basis.Add('roadmapState=parse-error')
    } elseif (-not [string]::IsNullOrWhiteSpace($kindConclusion)) {
        $conclusion = $kindConclusion
        $reason = [string](_PC_GetField -Obj $kindDef -Name 'reason' -Default "Kind '$($kindVerdict.kind)' concludes $kindConclusion.")
        $basis.Add('kind rule: ' + $kindVerdict.basis)
    } else {
        $gaps = @($domains | Where-Object { $_.status -in @('missing', 'weak') })
        if ($gaps.Count -gt 0) {
            $conclusion = 'strengthen'
            $first = @($gaps | Where-Object { $_.status -eq 'missing' } | Select-Object -First 1)
            if ($first.Count -eq 0) { $first = @($gaps | Select-Object -First 1) }
            $lead = $first[0]
            $reason = ("{0} is {1}: {2}." -f $lead.title, $lead.status, (@($lead.evidence) -join '; '))
            $nextAction = $lead.nextAction
            foreach ($g in $gaps) { $basis.Add(("{0}={1}" -f $g.domain, $g.status)) }
        } else {
            $conclusion = 'appropriate-as-is'
            $present = @($domains | Where-Object { $_.status -eq 'present' })
            $cited = @($present | ForEach-Object { "{0}: {1}" -f $_.title.ToLowerInvariant(), (@($_.evidence) | Select-Object -First 1) })
            $reason = 'Every applicable foundation is present - ' + ($cited -join '; ') + '.'
            foreach ($p in $present) { $basis.Add(("{0}=present" -f $p.domain)) }
            # Healthy, with recorded pending work: the next action is the
            # packaging flow, preview-first (a readiness check), never a dispatch.
            $pendingWork = [int](_PC_GetField -Obj $Entry -Name 'pendingCount' -Default 0)
            $planningPresent = @($present | Where-Object { $_.domain -eq 'planning' }).Count -gt 0
            $planningDomain = @($configDomains | Where-Object { [string](_PC_GetField -Obj $_ -Name 'id' -Default '') -eq 'planning' } | Select-Object -First 1)
            if ($pendingWork -gt 0 -and $planningPresent -and $planningDomain.Count -gt 0) {
                $pendingAction = _PC_GetField -Obj $planningDomain[0] -Name 'pendingWorkAction' -Default $null
                if ($null -ne $pendingAction) {
                    $nextAction = _PC_ActionFromDefinition -Definition $pendingAction -DomainId 'planning' -Entry $Entry
                    $basis.Add("pendingCount=$pendingWork")
                }
            }
        }
    }

    $consistency = _PC_LifecycleConsistency -Config $Config -LifecycleState ([string](_PC_GetField -Obj $Entry -Name 'lifecycleState' -Default '')) -Conclusion $conclusion -Basis @($basis) -Domains @($domains)

    return [pscustomobject]@{
        schemaVersion = 'v1'
        model         = 'foundation-conclusion'
        repoId        = $repoId
        repoName      = $repoName
        # Release 3.7 M4a: the trial records the index SHA a conclusion was
        # drawn from; modelVersion beside it keeps that comparable across
        # kind-model changes. Read from config so a data-only refinement bumps it.
        modelVersion  = [string](_PC_GetField -Obj $Config -Name 'modelVersion' -Default 'foundation-conclusions v1')
        kind          = $kindVerdict.kind
        kindBasis     = $kindVerdict.basis
        # v2.1: every matching rule, ranked, with the hints each rested on; the
        # hints present even when none matched; and observations - findings
        # with canonicalEffect none that changed no verdict (steering section 4).
        kindCandidates = @($kindVerdict.candidates)
        kindHints     = @($kindVerdict.hints)
        observations  = @($observations)
        conclusion    = $conclusion
        reason        = $reason
        basis         = @($basis)
        domains       = @($domains)
        nextAction    = $nextAction
        maturityLevel = [string](_PC_GetField -Obj $Entry -Name 'maturityLevel' -Default 'L0-Absent')
        lifecycleState = [string](_PC_GetField -Obj $Entry -Name 'lifecycleState' -Default '')
        # Steering extension 3: whether the lifecycle state and this conclusion
        # agree, and when they do not, the configured explanation with the
        # basis fact that earns it. Null only when the config has no table.
        consistency   = $consistency
        generatedAt   = $GeneratedAt
    }
}

function Test-FoundationConclusion {
    <#
    .SYNOPSIS
        Return the ways a conclusion breaks the Release 3.6 contract; empty means it holds.
    .DESCRIPTION
        - a non-empty reason;
        - a conclusion from the config's set and every domain status from its set;
        - strengthen names a next action with a route;
        - appropriate-as-is cites evidence (never an absence of findings);
        - nothing presents 'L0-Absent' as the only thing it has to say;
        - lifecycleState and conclusion agree, or an explained exception applies
          (steering extension 3; the table is foundation-domains.json lifecycleConsistency).
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory = $true)][object]$Conclusion,
        [Parameter(Mandatory = $true)][object]$Config
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    $name = [string](_PC_GetField -Obj $Conclusion -Name 'repoName' -Default '?')
    $verdict = [string](_PC_GetField -Obj $Conclusion -Name 'conclusion' -Default '')
    $reason = [string](_PC_GetField -Obj $Conclusion -Name 'reason' -Default '')
    $allowedConclusions = @()
    $conclusionsDef = _PC_GetField -Obj $Config -Name 'conclusions' -Default $null
    $allowedConclusions = @(_PC_PropertyNames -Obj $conclusionsDef)
    $allowedStatuses = @(_PC_GetField -Obj $Config -Name 'domainStatuses' -Default @())

    if ([string]::IsNullOrWhiteSpace($reason)) { $violations.Add("$name has an empty reason") }
    if ($reason.Trim() -match '^L0-Absent[.!]?$') { $violations.Add("$name presents 'L0-Absent' as its whole reason") }
    if ($verdict -notin $allowedConclusions) { $violations.Add("$name has conclusion '$verdict' outside the configured set") }

    $domains = @(_PC_GetField -Obj $Conclusion -Name 'domains' -Default @())
    if ($domains.Count -eq 0) { $violations.Add("$name carries no domain records") }
    foreach ($d in $domains) {
        $status = [string](_PC_GetField -Obj $d -Name 'status' -Default '')
        if ($status -notin $allowedStatuses) { $violations.Add("$name domain '$(_PC_GetField -Obj $d -Name 'domain' -Default '?')' has status '$status' outside the configured set") }
        $ev = @(_PC_Strings -Values @(_PC_GetField -Obj $d -Name 'evidence' -Default @()))
        if ($ev.Count -eq 0) { $violations.Add("$name domain '$(_PC_GetField -Obj $d -Name 'domain' -Default '?')' has no evidence") }
        foreach ($line in $ev) { if ($line.Trim() -eq 'L0-Absent') { $violations.Add("$name cites bare 'L0-Absent' as evidence") } }
    }

    $consistency = _PC_GetField -Obj $Conclusion -Name 'consistency' -Default $null
    if ($null -ne $consistency -and -not [bool](_PC_GetField -Obj $consistency -Name 'holds' -Default $false)) {
        $violations.Add(("{0}: {1}" -f $name, [string](_PC_GetField -Obj $consistency -Name 'explanation' -Default 'lifecycle and conclusion disagree')))
    }

    switch ($verdict) {
        'strengthen' {
            $action = _PC_GetField -Obj $Conclusion -Name 'nextAction' -Default $null
            $route = [string](_PC_GetField -Obj $action -Name 'route' -Default '')
            if ([string]::IsNullOrWhiteSpace($route)) { $violations.Add("$name concludes strengthen but names no next-action route") }
        }
        'appropriate-as-is' {
            $positive = @($domains | Where-Object { [string](_PC_GetField -Obj $_ -Name 'status' -Default '') -in @('present', 'not-applicable') })
            $cited = @($positive | ForEach-Object { @(_PC_Strings -Values @(_PC_GetField -Obj $_ -Name 'evidence' -Default @())) } | Where-Object { $_ -notmatch '(?i)^no (findings|issues)' })
            if ($cited.Count -eq 0) { $violations.Add("$name concludes appropriate-as-is without citing evidence") }
        }
        'insufficiently-understood' {
            if ($reason -notmatch '(?i)need') { $violations.Add("$name concludes insufficiently-understood without naming what the product needs") }
        }
    }
    return @($violations)
}

function ConvertTo-FoundationOutcomeSummary {
    <#
    .SYNOPSIS
        The card-sized view of a conclusion: what a list row needs to render and filter it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Conclusion,
        [Parameter()][AllowEmptyCollection()][string[]]$Violations = @()
    )

    $action = _PC_GetField -Obj $Conclusion -Name 'nextAction' -Default $null
    $domains = @(_PC_GetField -Obj $Conclusion -Name 'domains' -Default @())
    $gaps = @($domains | Where-Object { [string](_PC_GetField -Obj $_ -Name 'status' -Default '') -in @('missing', 'weak') })
    return [pscustomobject]@{
        conclusion      = [string](_PC_GetField -Obj $Conclusion -Name 'conclusion' -Default '')
        reason          = [string](_PC_GetField -Obj $Conclusion -Name 'reason' -Default '')
        kind            = [string](_PC_GetField -Obj $Conclusion -Name 'kind' -Default 'unknown')
        gapCount        = $gaps.Count
        gapDomains      = @($gaps | ForEach-Object { [string](_PC_GetField -Obj $_ -Name 'domain' -Default '') })
        nextActionKind  = if ($null -eq $action) { $null } else { [string](_PC_GetField -Obj $action -Name 'kind' -Default '') }
        nextActionLabel = if ($null -eq $action) { $null } else { [string](_PC_GetField -Obj $action -Name 'label' -Default '') }
        nextActionRoute = if ($null -eq $action) { $null } else { [string](_PC_GetField -Obj $action -Name 'route' -Default '') }
        holds           = (@($Violations).Count -eq 0)
    }
}

function Add-FoundationOutcome {
    <#
    .SYNOPSIS
        Attach an `outcome` summary to every index entry so list surfaces render
        and filter appropriate-as-is like any other conclusion. Pure and
        in-memory; a null config leaves the entries untouched.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter()][object]$Config = $null
    )

    if ($null -eq $Config) { return @($Entries) }
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $conclusion = Get-RepositoryFoundationConclusion -Entry $entry -Config $Config
        $violations = @(Test-FoundationConclusion -Conclusion $conclusion -Config $Config)
        $summary = ConvertTo-FoundationOutcomeSummary -Conclusion $conclusion -Violations $violations
        if ($entry -is [System.Collections.IDictionary]) {
            $entry['outcome'] = $summary
        } else {
            $entry | Add-Member -NotePropertyName 'outcome' -NotePropertyValue $summary -Force
        }
    }
    return @($Entries)
}

function Get-PortfolioConclusionsPayload {
    <#
    .SYNOPSIS
        Conclusions for every index entry plus the counts a landing page and a trend series need.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter()][string]$GeneratedAt = '',
        # The staleness verdict of the index these entries came from. A
        # conclusion drawn from an index that no longer describes the portfolio
        # is worse than no conclusion, because it reads as a finding.
        [Parameter()][AllowNull()][object]$Staleness = $null
    )

    if ([string]::IsNullOrWhiteSpace($GeneratedAt)) { $GeneratedAt = (Get-Date).ToUniversalTime().ToString('o') }
    $items = [System.Collections.Generic.List[object]]::new()
    $violations = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $c = Get-RepositoryFoundationConclusion -Entry $entry -Config $Config -GeneratedAt $GeneratedAt
        $items.Add($c) | Out-Null
        foreach ($v in @(Test-FoundationConclusion -Conclusion $c -Config $Config)) { $violations.Add($v) | Out-Null }
    }

    $byConclusion = [ordered]@{}
    $conclusionsDef = _PC_GetField -Obj $Config -Name 'conclusions' -Default $null
    $conclusionNames = @(_PC_PropertyNames -Obj $conclusionsDef)
    foreach ($n in $conclusionNames) { $byConclusion[[string]$n] = 0 }
    foreach ($i in $items) { $k = [string]$i.conclusion; if (-not $byConclusion.Contains($k)) { $byConclusion[$k] = 0 }; $byConclusion[$k]++ }

    $byKind = [ordered]@{}
    foreach ($i in $items) { $k = [string]$i.kind; if (-not $byKind.Contains($k)) { $byKind[$k] = 0 }; $byKind[$k]++ }

    # Steering extension 3: how the two verdict models relate across the set.
    $byConsistency = [ordered]@{ allowed = 0; explained = 0; contradiction = 0; 'unknown-lifecycle' = 0; 'not-assessed' = 0 }
    foreach ($i in $items) {
        $c = _PC_GetField -Obj $i -Name 'consistency' -Default $null
        $a = if ($null -eq $c) { 'not-assessed' } else { [string](_PC_GetField -Obj $c -Name 'agreement' -Default 'not-assessed') }
        if (-not $byConsistency.Contains($a)) { $byConsistency[$a] = 0 }
        $byConsistency[$a]++
    }

    $statuses = @(_PC_GetField -Obj $Config -Name 'domainStatuses' -Default @())
    $coverage = [ordered]@{}
    foreach ($domain in @(_PC_GetField -Obj $Config -Name 'domains' -Default @())) {
        $id = [string](_PC_GetField -Obj $domain -Name 'id' -Default '')
        $row = [ordered]@{}
        foreach ($s in $statuses) { $row[[string]$s] = 0 }
        foreach ($i in $items) {
            foreach ($d in @($i.domains)) {
                if ([string]$d.domain -ne $id) { continue }
                $s = [string]$d.status
                if (-not $row.Contains($s)) { $row[$s] = 0 }
                $row[$s]++
            }
        }
        $coverage[$id] = [pscustomobject]$row
    }

    return [pscustomobject]@{
        schemaVersion = 'v1'
        model         = 'foundation-conclusions'
        modelVersion  = [string](_PC_GetField -Obj $Config -Name 'modelVersion' -Default 'foundation-conclusions v1')
        generatedAt   = $GeneratedAt
        count         = $items.Count
        byConsistency = [pscustomobject]$byConsistency
        byConclusion  = [pscustomobject]$byConclusion
        byKind        = [pscustomobject]$byKind
        coverage      = [pscustomobject]$coverage
        contract      = [pscustomobject]@{
            holds          = ($violations.Count -eq 0)
            violationCount = $violations.Count
            violations     = @($violations)
        }
        # Absent means "not established", never "fresh": a caller that does not
        # supply the verdict gets one saying so, so no surface can render these
        # conclusions as current without something having actually checked.
        basis         = [pscustomobject]@{
            indexStale   = $(if ($null -eq $Staleness) { $true } else { [bool](_PC_GetField -Obj $Staleness -Name 'stale' -Default $true) })
            indexAgeHours = _PC_GetField -Obj $Staleness -Name 'ageHours' -Default $null
            indexGeneratedAt = _PC_GetField -Obj $Staleness -Name 'generatedAt' -Default $null
            reasons      = $(if ($null -eq $Staleness) {
                    @('The freshness of the index behind these conclusions was not established, so they cannot be presented as current.')
                } else {
                    @(_PC_GetField -Obj $Staleness -Name 'reasons' -Default @())
                })
        }
        items         = @($items)
    }
}

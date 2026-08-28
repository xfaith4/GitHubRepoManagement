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

function Resolve-RepositoryKind {
    <#
    .SYNOPSIS
        Pick the repository kind from the config's detection rules; 'unknown' when nothing matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][object]$Config
    )

    $detection = _PC_GetField -Obj $Config -Name 'kindDetection' -Default $null
    $rules = @(_PC_GetField -Obj $detection -Name 'rules' -Default @())
    foreach ($rule in $rules) {
        $when = _PC_GetField -Obj $rule -Name 'when' -Default $null
        if ($null -eq $when) { continue }
        $names = @()
        $names = @(_PC_PropertyNames -Obj $when)
        $allMatch = $names.Count -gt 0
        foreach ($name in $names) {
            $expected = [string](_PC_GetField -Obj $when -Name $name -Default '')
            $actual = [string](_PC_GetField -Obj $Entry -Name $name -Default '')
            if ($actual -ne $expected) { $allMatch = $false; break }
        }
        if ($allMatch) {
            return [pscustomobject]@{
                kind  = [string](_PC_GetField -Obj $rule -Name 'kind' -Default 'unknown')
                basis = [string](_PC_GetField -Obj $rule -Name 'basis' -Default 'detection rule')
            }
        }
    }
    return [pscustomobject]@{ kind = 'unknown'; basis = 'no kind signal in the index; every scored domain applies' }
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

    return [pscustomobject]@{
        schemaVersion = 'v1'
        model         = 'foundation-conclusion'
        repoId        = $repoId
        repoName      = $repoName
        kind          = $kindVerdict.kind
        kindBasis     = $kindVerdict.basis
        conclusion    = $conclusion
        reason        = $reason
        basis         = @($basis)
        domains       = @($domains)
        nextAction    = $nextAction
        maturityLevel = [string](_PC_GetField -Obj $Entry -Name 'maturityLevel' -Default 'L0-Absent')
        lifecycleState = [string](_PC_GetField -Obj $Entry -Name 'lifecycleState' -Default '')
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
        - nothing presents 'L0-Absent' as the only thing it has to say.
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
        [Parameter()][string]$GeneratedAt = ''
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
        generatedAt   = $GeneratedAt
        count         = $items.Count
        byConclusion  = [pscustomobject]$byConclusion
        byKind        = [pscustomobject]$byKind
        coverage      = [pscustomobject]$coverage
        contract      = [pscustomobject]@{
            holds          = ($violations.Count -eq 0)
            violationCount = $violations.Count
            violations     = @($violations)
        }
        items         = @($items)
    }
}

<#
.SYNOPSIS
    Collection status report generation for portfolio assessment entries.

.DESCRIPTION
    Release 1.7.5 Phase 7B.

    Produces timestamped HTML and CSV reports that summarize lifecycle state,
    blockers, next actions, and top recommended work for a portfolio slice.

.NOTES
    Dot-source from Start-RepoManagementApiHost.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _GetPortfolioReportField {
    param(
        [Parameter()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [Parameter()][object]$Default = $null
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $Default
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($PropertyName)) {
            $value = $InputObject[$PropertyName]
            if ($null -ne $value) { return $value }
        }
        return $Default
    }

    if ($InputObject.PSObject.Properties.Name -contains $PropertyName) {
        $value = $InputObject.$PropertyName
        if ($null -ne $value) { return $value }
    }

    return $Default
}

function _EncodePortfolioReportHtml {
    param([object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function _ConvertToPortfolioReportCsvField {
    param([object]$Value)
    return '"' + ([string]$Value).Replace('"', '""') + '"'
}

function _JoinPortfolioReportList {
    param([object[]]$Items)

    $values = @($Items | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($values.Count -eq 0) {
        return ''
    }

    return ($values -join ' | ')
}

function _FormatPortfolioReportScore {
    param([object]$Value)

    if ($null -eq $Value) {
        return 'n/a'
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'n/a'
    }

    return $text
}

function _GetPortfolioLifecyclePriority {
    param([string]$LifecycleState)

    switch ($LifecycleState) {
        'ready-for-work'       { return 0 }
        'needs-readme'         { return 1 }
        'needs-roadmap'        { return 2 }
        'needs-roadmap-repair' { return 3 }
        'needs-structure'      { return 4 }
        'running'              { return 5 }
        'no-checklist'         { return 6 }
        'parse-error'          { return 7 }
        'discovered'           { return 8 }
        'monitored'            { return 9 }
        'completed'            { return 10 }
        'archived'             { return 11 }
        default                { return 50 }
    }
}

function _GetPortfolioLifecycleLabel {
    param([string]$LifecycleState)

    switch ($LifecycleState) {
        'ready-for-work'       { return 'Ready For Work' }
        'needs-readme'         { return 'Needs README' }
        'needs-roadmap'        { return 'Needs Roadmap' }
        'needs-roadmap-repair' { return 'Needs Roadmap Repair' }
        'needs-structure'      { return 'Needs Structure' }
        'running'              { return 'Running' }
        'no-checklist'         { return 'No Checklist Items' }
        'parse-error'          { return 'Parse Error' }
        'discovered'           { return 'Discovered' }
        'monitored'            { return 'Monitored' }
        'completed'            { return 'Completed' }
        'archived'             { return 'Archived' }
        default                { return $LifecycleState }
    }
}

function _GetPortfolioLifecycleBadgeClass {
    param([string]$LifecycleState)

    switch ($LifecycleState) {
        'ready-for-work'       { return 'ready' }
        'needs-readme'         { return 'warn' }
        'needs-roadmap'        { return 'warn' }
        'needs-roadmap-repair' { return 'warn' }
        'needs-structure'      { return 'warn' }
        'running'              { return 'accent' }
        'no-checklist'         { return 'warn' }
        'parse-error'          { return 'danger' }
        'archived'             { return 'muted' }
        'completed'            { return 'ok' }
        'monitored'            { return 'ok' }
        default                { return 'muted' }
    }
}

function _GetPortfolioCollectionReportSummary {
    param([object[]]$Entries)

    $summaryCommand = Get-Command -Name 'Get-PortfolioAssessmentSummary' -ErrorAction SilentlyContinue
    if ($null -ne $summaryCommand) {
        return Get-PortfolioAssessmentSummary -Assessments $Entries
    }

    $total = @($Entries).Count
    return [pscustomobject]@{
        totalRepos          = $total
        byLifecycle         = @{}
        bySourceCoverage    = @{}
        missingReadmeCount  = 0
        missingRoadmapCount = 0
        weakRoadmapCount    = 0
        readyForWorkCount   = 0
        runningCount        = 0
        blockedCount        = 0
    }
}

function New-PortfolioCollectionStatusCsvContent {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyCollection()][object[]]$Entries = @())

    $rows = @(
        'Repository,LifecycleState,SourceCoverage,RecommendedAction,TopRecommendedWork,TopValueScore,BlockingReasons,RoadmapState,MaturityLevel,ReadmeScore,RoadmapScore,DocumentationHealthScore,DispatchReadiness,ExecutionState,PendingItemCount,LocalPath,HtmlUrl'
    )

    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }

        $topValueItem = _GetPortfolioReportField -InputObject $entry -PropertyName 'topValueItem' -Default $null
        $blockingReasons = @(_GetPortfolioReportField -InputObject $entry -PropertyName 'blockingReasons' -Default @())
        $values = @(
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'repoName' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'lifecycleState' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'sourceCoverage' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'recommendedAction' -Default ''),
            [string](_GetPortfolioReportField -InputObject $topValueItem -PropertyName 'text' -Default (_GetPortfolioReportField -InputObject $entry -PropertyName 'nextPendingItemText' -Default '')),
            [string](_GetPortfolioReportField -InputObject $topValueItem -PropertyName 'valueScore' -Default ''),
            (_JoinPortfolioReportList -Items $blockingReasons),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'roadmapState' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'maturityLevel' -Default ''),
            (_FormatPortfolioReportScore (_GetPortfolioReportField -InputObject $entry -PropertyName 'readmeScore' -Default $null)),
            (_FormatPortfolioReportScore (_GetPortfolioReportField -InputObject $entry -PropertyName 'roadmapScore' -Default $null)),
            (_FormatPortfolioReportScore (_GetPortfolioReportField -InputObject $entry -PropertyName 'documentationHealthScore' -Default $null)),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'dispatchReadiness' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'executionState' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'pendingItemCount' -Default 0),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'localPath' -Default ''),
            [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'htmlUrl' -Default '')
        ) | ForEach-Object { _ConvertToPortfolioReportCsvField -Value $_ }

        $rows += ($values -join ',')
    }

    return ($rows -join "`r`n")
}

function New-PortfolioCollectionStatusHtmlContent {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter()][object]$Summary = $null,
        [Parameter()][string]$SourceLabel = 'Portfolio assessment export',
        [Parameter()][datetime]$GeneratedAt = (Get-Date)
    )

    $entryList = @($Entries)
    $summaryObject = if ($null -ne $Summary) { $Summary } else { _GetPortfolioCollectionReportSummary -Entries $entryList }
    # One clock (Release 3.5): a rendered timestamp names its basis.
    $generatedDisplay = $GeneratedAt.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'

    $sortedEntries = @(
        $entryList |
            Sort-Object `
                @{ Expression = { _GetPortfolioLifecyclePriority ([string](_GetPortfolioReportField -InputObject $_ -PropertyName 'lifecycleState' -Default 'discovered')) }; Ascending = $true }, `
                @{ Expression = { [int](_GetPortfolioReportField -InputObject (_GetPortfolioReportField -InputObject $_ -PropertyName 'topValueItem' -Default $null) -PropertyName 'valueScore' -Default -1) }; Descending = $true }, `
                @{ Expression = { [string](_GetPortfolioReportField -InputObject $_ -PropertyName 'repoName' -Default '') }; Ascending = $true }
    )

    $topRecommendations = @(
        $entryList |
            Where-Object {
                $item = _GetPortfolioReportField -InputObject $_ -PropertyName 'topValueItem' -Default $null
                -not [string]::IsNullOrWhiteSpace([string](_GetPortfolioReportField -InputObject $item -PropertyName 'text' -Default ''))
            } |
            Sort-Object `
                @{ Expression = { [int](_GetPortfolioReportField -InputObject (_GetPortfolioReportField -InputObject $_ -PropertyName 'topValueItem' -Default $null) -PropertyName 'valueScore' -Default -1) }; Descending = $true }, `
                @{ Expression = { _GetPortfolioLifecyclePriority ([string](_GetPortfolioReportField -InputObject $_ -PropertyName 'lifecycleState' -Default 'discovered')) }; Ascending = $true }, `
                @{ Expression = { [string](_GetPortfolioReportField -InputObject $_ -PropertyName 'repoName' -Default '') }; Ascending = $true } |
            Select-Object -First 8
    )

    $workflowSteps = @(
        'Assess the collection from the Portfolio Mission panel or a fresh scan.',
        'Fix blockers such as missing README files, weak roadmaps, or structural gaps.',
        'Create or repair roadmap contracts until the repo is ready for work.',
        'Use value-ranked work to choose the highest-payoff pending item.',
        'Refine the Copilot task packet before dispatch.',
        'Dispatch and monitor execution in the queue.',
        'Re-run validation and emit an updated collection report.'
    )

    $workflowMarkup = @(
        $workflowSteps | ForEach-Object {
            "<li>$(_EncodePortfolioReportHtml $_)</li>"
        }
    ) -join ''

    $lifecycleStates = @(
        'ready-for-work',
        'needs-readme',
        'needs-roadmap',
        'needs-roadmap-repair',
        'needs-structure',
        'running',
        'completed',
        'monitored',
        'no-checklist',
        'parse-error',
        'archived',
        'discovered'
    )

    $lifecycleMarkup = foreach ($state in $lifecycleStates) {
        $count = [int](_GetPortfolioReportField -InputObject (_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'byLifecycle' -Default @{}) -PropertyName $state -Default 0)
        if ($count -le 0) { continue }

@"
            <li>
              <span>$(_EncodePortfolioReportHtml (_GetPortfolioLifecycleLabel -LifecycleState $state))</span>
              <strong>$count</strong>
            </li>
"@
    }

    if (@($lifecycleMarkup).Count -eq 0) {
        $lifecycleMarkup = @'
            <li>
              <span>No lifecycle data available</span>
              <strong>0</strong>
            </li>
'@
    }

    $recommendationMarkup = foreach ($entry in $topRecommendations) {
        $item = _GetPortfolioReportField -InputObject $entry -PropertyName 'topValueItem' -Default $null
        $repoName = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'repoName' -Default 'unknown')
        $text = [string](_GetPortfolioReportField -InputObject $item -PropertyName 'text' -Default '')
        $score = [string](_GetPortfolioReportField -InputObject $item -PropertyName 'valueScore' -Default '')
        $action = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'recommendedAction' -Default '')

@"
            <li>
              <strong>$(_EncodePortfolioReportHtml $repoName)</strong>
              <span class="focus-score">Score $(_EncodePortfolioReportHtml $score)</span>
              <div class="focus-task">$(_EncodePortfolioReportHtml $text)</div>
              <div class="focus-action">$(_EncodePortfolioReportHtml $action)</div>
            </li>
"@
    }

    if (@($recommendationMarkup).Count -eq 0) {
        $recommendationMarkup = @'
            <li class="empty-note">
              <strong>No ranked pending work in this report slice.</strong>
              <div class="focus-action">The exported repositories are currently blocked, complete, archived, or missing roadmap work.</div>
            </li>
'@
    }

    $tableRows = foreach ($entry in $sortedEntries) {
        if ($null -eq $entry) { continue }

        $repoName = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'repoName' -Default 'unknown')
        $lifecycleState = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'lifecycleState' -Default 'discovered')
        $sourceCoverage = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'sourceCoverage' -Default 'local')
        $recommendedAction = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'recommendedAction' -Default '')
        $topValueItem = _GetPortfolioReportField -InputObject $entry -PropertyName 'topValueItem' -Default $null
        $topText = [string](_GetPortfolioReportField -InputObject $topValueItem -PropertyName 'text' -Default (_GetPortfolioReportField -InputObject $entry -PropertyName 'nextPendingItemText' -Default ''))
        $topScore = [string](_GetPortfolioReportField -InputObject $topValueItem -PropertyName 'valueScore' -Default '')
        $blockingReasons = @(_GetPortfolioReportField -InputObject $entry -PropertyName 'blockingReasons' -Default @())
        $localPath = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'localPath' -Default '')
        $htmlUrl = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'htmlUrl' -Default '')
        $roadmapState = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'roadmapState' -Default '')
        $maturityLevel = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'maturityLevel' -Default '')
        $readmeScore = _FormatPortfolioReportScore (_GetPortfolioReportField -InputObject $entry -PropertyName 'readmeScore' -Default $null)
        $roadmapScore = _FormatPortfolioReportScore (_GetPortfolioReportField -InputObject $entry -PropertyName 'roadmapScore' -Default $null)
        $docHealthScore = _FormatPortfolioReportScore (_GetPortfolioReportField -InputObject $entry -PropertyName 'documentationHealthScore' -Default $null)
        $dispatchReadiness = [string](_GetPortfolioReportField -InputObject $entry -PropertyName 'dispatchReadiness' -Default '')
        $lifecycleBadgeClass = _GetPortfolioLifecycleBadgeClass -LifecycleState $lifecycleState

        $pathMarkup = if (-not [string]::IsNullOrWhiteSpace($localPath)) {
            "<div class=""repo-meta-line""><span class=""meta-label"">Path</span><code>$(_EncodePortfolioReportHtml $localPath)</code></div>"
        } else {
            '<div class="repo-meta-line"><span class="meta-label">Path</span><span class="muted">n/a</span></div>'
        }
        $remoteMarkup = if (-not [string]::IsNullOrWhiteSpace($htmlUrl)) {
            "<div class=""repo-meta-line""><span class=""meta-label"">Remote</span><a href=""$(_EncodePortfolioReportHtml $htmlUrl)"" target=""_blank"" rel=""noreferrer"">$(_EncodePortfolioReportHtml $htmlUrl)</a></div>"
        } else {
            '<div class="repo-meta-line"><span class="meta-label">Remote</span><span class="muted">n/a</span></div>'
        }

        $blockerMarkup = if (@($blockingReasons).Count -gt 0) {
            @($blockingReasons | ForEach-Object { "<li>$(_EncodePortfolioReportHtml $_)</li>" }) -join ''
        } else {
            '<li class="muted">No blocking reasons recorded.</li>'
        }

        $topWorkMarkup = if (-not [string]::IsNullOrWhiteSpace($topText)) {
@"
              <div class="top-work-title">$(_EncodePortfolioReportHtml $topText)</div>
              <div class="top-work-meta">Value score: $(_EncodePortfolioReportHtml $topScore)</div>
"@
        } else {
            '<div class="muted">No ranked pending work available.</div>'
        }

@"
          <tr>
            <td>
              <div class="repo-name">$(_EncodePortfolioReportHtml $repoName)</div>
              <div class="repo-meta">$(_EncodePortfolioReportHtml $sourceCoverage)</div>
              $pathMarkup
              $remoteMarkup
            </td>
            <td>
              <span class="badge $lifecycleBadgeClass">$(_EncodePortfolioReportHtml (_GetPortfolioLifecycleLabel -LifecycleState $lifecycleState))</span>
              <div class="top-work-meta">Roadmap: $(_EncodePortfolioReportHtml $roadmapState)</div>
              <div class="top-work-meta">Maturity: $(_EncodePortfolioReportHtml $maturityLevel)</div>
            </td>
            <td>
              <div class="action-text">$(_EncodePortfolioReportHtml $recommendedAction)</div>
              <div class="top-work-meta">Dispatch readiness: $(_EncodePortfolioReportHtml $dispatchReadiness)</div>
            </td>
            <td>
              $topWorkMarkup
            </td>
            <td>
              <ul class="blocker-list">
                $blockerMarkup
              </ul>
            </td>
            <td>
              <dl class="signal-list">
                <div><dt>README</dt><dd>$(_EncodePortfolioReportHtml $readmeScore)</dd></div>
                <div><dt>ROADMAP</dt><dd>$(_EncodePortfolioReportHtml $roadmapScore)</dd></div>
                <div><dt>Docs</dt><dd>$(_EncodePortfolioReportHtml $docHealthScore)</dd></div>
              </dl>
            </td>
          </tr>
"@
    }

    if (@($tableRows).Count -eq 0) {
        $tableRows = @'
          <tr>
            <td colspan="6" class="empty-state">No portfolio assessment entries were included in this report.</td>
          </tr>
'@
    }

    $totalRepos = [int](_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'totalRepos' -Default $entryList.Count)
    $readyCount = [int](_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'readyForWorkCount' -Default 0)
    $blockedCount = [int](_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'blockedCount' -Default 0)
    $runningCount = [int](_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'runningCount' -Default 0)
    $missingRoadmapCount = [int](_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'missingRoadmapCount' -Default 0)
    $weakRoadmapCount = [int](_GetPortfolioReportField -InputObject $summaryObject -PropertyName 'weakRoadmapCount' -Default 0)

@"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Collection Status Report - $generatedDisplay</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #08111f;
      --panel: rgba(10, 24, 45, 0.86);
      --line: rgba(142, 169, 197, 0.2);
      --text: #e7eef7;
      --muted: #94a7bf;
      --shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(56, 189, 248, 0.18), transparent 28%),
        radial-gradient(circle at top right, rgba(34, 197, 94, 0.16), transparent 30%),
        linear-gradient(180deg, #09101d 0%, #08111f 52%, #050a12 100%);
      color: var(--text);
      min-height: 100vh;
    }
    .shell {
      width: min(1440px, calc(100% - 32px));
      margin: 28px auto;
      padding: 24px;
      border: 1px solid var(--line);
      border-radius: 28px;
      background: var(--panel);
      backdrop-filter: blur(18px);
      box-shadow: var(--shadow);
    }
    .hero {
      display: grid;
      gap: 20px;
      grid-template-columns: 1.7fr 1fr;
      align-items: end;
      margin-bottom: 24px;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 12px;
      border-radius: 999px;
      background: rgba(14, 165, 233, 0.12);
      color: #bfe9ff;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    h1 {
      margin: 14px 0 10px;
      font-size: clamp(32px, 4vw, 54px);
      line-height: 1;
    }
    .lede {
      margin: 0;
      color: var(--muted);
      max-width: 72ch;
      line-height: 1.6;
    }
    .meta-card,
    .workflow-card,
    .focus-card,
    .table-shell {
      border: 1px solid var(--line);
      border-radius: 24px;
      background: rgba(4, 10, 20, 0.55);
    }
    .meta-card {
      padding: 20px;
      background: linear-gradient(180deg, rgba(13, 30, 54, 0.94), rgba(8, 17, 31, 0.94));
    }
    .meta-card strong {
      display: block;
      margin-bottom: 8px;
      font-size: 14px;
      color: #bcd0e8;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }
    .meta-card span {
      display: block;
      color: var(--text);
      line-height: 1.6;
      word-break: break-word;
    }
    .stats {
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      margin-bottom: 24px;
    }
    .stat {
      padding: 18px;
      border-radius: 20px;
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.03);
    }
    .stat .label {
      display: block;
      margin-bottom: 12px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .stat .value {
      display: block;
      font-size: clamp(24px, 3vw, 34px);
      font-weight: 700;
    }
    .workflow-card,
    .focus-card {
      padding: 20px;
      margin-bottom: 20px;
    }
    .workflow-card h2,
    .focus-card h2 {
      margin: 0 0 10px;
      font-size: 18px;
    }
    .workflow-card p,
    .focus-card p {
      margin: 0 0 14px;
      color: var(--muted);
      line-height: 1.6;
    }
    .workflow-card ol,
    .focus-card ul,
    .blocker-list {
      margin: 0;
      padding-left: 18px;
    }
    .workflow-card li,
    .focus-card li,
    .blocker-list li {
      margin: 0 0 10px;
      line-height: 1.5;
    }
    .focus-grid {
      display: grid;
      gap: 20px;
      grid-template-columns: 1.4fr 1fr;
      margin-bottom: 20px;
    }
    .focus-score {
      display: inline-flex;
      margin-left: 10px;
      padding: 3px 8px;
      border-radius: 999px;
      background: rgba(14, 165, 233, 0.14);
      color: #bfe9ff;
      font-size: 12px;
    }
    .focus-task {
      margin-top: 6px;
      color: var(--text);
    }
    .focus-action {
      margin-top: 4px;
      color: var(--muted);
      font-size: 14px;
    }
    .lifecycle-summary {
      list-style: none;
      padding-left: 0;
    }
    .lifecycle-summary li {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 10px 0;
      border-bottom: 1px solid rgba(142, 169, 197, 0.12);
    }
    .lifecycle-summary li:last-child {
      border-bottom: 0;
    }
    .table-shell {
      overflow: hidden;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    thead th {
      text-align: left;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: #a9bdd3;
      background: rgba(13, 30, 54, 0.94);
      padding: 16px 18px;
      border-bottom: 1px solid var(--line);
      position: sticky;
      top: 0;
    }
    tbody td {
      padding: 16px 18px;
      border-bottom: 1px solid rgba(142, 169, 197, 0.12);
      vertical-align: top;
    }
    tbody tr:hover {
      background: rgba(255, 255, 255, 0.03);
    }
    .repo-name {
      font-size: 16px;
      font-weight: 700;
      margin-bottom: 6px;
    }
    .repo-meta,
    .repo-meta-line,
    .signal-list div {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 10px;
      align-items: center;
    }
    .repo-meta {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .meta-label,
    .muted {
      color: var(--muted);
    }
    .meta-label {
      min-width: 56px;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 110px;
      padding: 7px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .badge.ready { background: rgba(34, 197, 94, 0.14); color: #c1f7d7; }
    .badge.ok { background: rgba(16, 185, 129, 0.14); color: #b6f4df; }
    .badge.warn { background: rgba(245, 158, 11, 0.16); color: #f9d48e; }
    .badge.accent { background: rgba(59, 130, 246, 0.16); color: #b9d5ff; }
    .badge.danger { background: rgba(251, 113, 133, 0.16); color: #fecdd3; }
    .badge.muted { background: rgba(148, 163, 184, 0.14); color: #d7e0ea; }
    .action-text {
      color: var(--text);
      line-height: 1.5;
    }
    .top-work-title {
      color: var(--text);
      font-weight: 600;
      line-height: 1.5;
    }
    .top-work-meta {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }
    .signal-list {
      margin: 0;
    }
    .signal-list dt {
      min-width: 70px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }
    .signal-list dd {
      margin: 0;
      font-weight: 600;
    }
    a { color: #9fd0ff; }
    code {
      font-family: "Cascadia Code", Consolas, monospace;
      font-size: 12px;
      background: rgba(148, 163, 184, 0.1);
      padding: 2px 6px;
      border-radius: 8px;
      word-break: break-all;
    }
    .empty-state,
    .empty-note {
      color: var(--muted);
    }
    @media (max-width: 1180px) {
      .hero,
      .focus-grid,
      .stats {
        grid-template-columns: 1fr 1fr;
      }
    }
    @media (max-width: 900px) {
      .shell {
        width: min(100% - 20px, 1440px);
        padding: 18px;
        margin: 14px auto;
      }
      .hero,
      .focus-grid,
      .stats {
        grid-template-columns: 1fr;
      }
      .table-shell {
        overflow-x: auto;
      }
      table {
        min-width: 1200px;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <div>
        <span class="eyebrow">Portfolio Mission Report</span>
        <h1>Collection Status Report</h1>
        <p class="lede">A plain-language portfolio snapshot built from the normalized assessment model. Use it to see lifecycle state, blockers, next actions, and highest-value work without opening each repository one by one.</p>
      </div>
      <aside class="meta-card">
        <strong>Report Context</strong>
        <span>Source: $(_EncodePortfolioReportHtml $SourceLabel)</span>
        <span>Generated: $(_EncodePortfolioReportHtml $generatedDisplay)</span>
        <span>Repositories: $totalRepos</span>
      </aside>
    </section>

    <section class="stats">
      <article class="stat"><span class="label">Repositories</span><span class="value">$totalRepos</span></article>
      <article class="stat"><span class="label">Ready</span><span class="value">$readyCount</span></article>
      <article class="stat"><span class="label">Blocked</span><span class="value">$blockedCount</span></article>
      <article class="stat"><span class="label">Running</span><span class="value">$runningCount</span></article>
      <article class="stat"><span class="label">Missing Roadmap</span><span class="value">$missingRoadmapCount</span></article>
      <article class="stat"><span class="label">Weak Roadmap</span><span class="value">$weakRoadmapCount</span></article>
    </section>

    <section class="workflow-card">
      <h2>North-Star Workflow</h2>
      <p>This report exists to support the operating loop the product is built around: assess the collection, fix blockers, rank work, refine the prompt, dispatch, validate, and report progress.</p>
      <ol>
        $workflowMarkup
      </ol>
    </section>

    <section class="focus-grid">
      <article class="focus-card">
        <h2>Top Recommended Work</h2>
        <p>The highest-ranked pending roadmap work in this export slice. When several repos are ready, this list shows the best next starting points first.</p>
        <ul>
          $recommendationMarkup
        </ul>
      </article>
      <article class="focus-card">
        <h2>Lifecycle Distribution</h2>
        <p>Use these counts to see whether the portfolio is ready for execution or still dominated by roadmap, README, or structure blockers.</p>
        <ul class="lifecycle-summary">
          $(($lifecycleMarkup -join "`n"))
        </ul>
      </article>
    </section>

    <section class="table-shell">
      <table>
        <thead>
          <tr>
            <th>Repository</th>
            <th>Lifecycle</th>
            <th>Recommended Action</th>
            <th>Top Work</th>
            <th>Blockers</th>
            <th>Signals</th>
          </tr>
        </thead>
        <tbody>
$(($tableRows -join "`n"))
        </tbody>
      </table>
    </section>
  </main>
</body>
</html>
"@
}

function Export-PortfolioCollectionStatusReport {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter()][string]$SourceLabel = 'Portfolio assessment export',
        [Parameter(Mandatory = $true)][string]$ReportsRoot
    )

    [System.IO.Directory]::CreateDirectory($ReportsRoot) | Out-Null

    $generatedAt = Get-Date
    $timestamp = $generatedAt.ToString('yyyyMMdd_HHmmssfff')
    $htmlFileName = "collection-status-report_$timestamp.html"
    $csvFileName = "collection-status-report_$timestamp.csv"
    $htmlPath = Join-Path $ReportsRoot $htmlFileName
    $csvPath = Join-Path $ReportsRoot $csvFileName
    $summary = _GetPortfolioCollectionReportSummary -Entries $Entries

    $htmlContent = New-PortfolioCollectionStatusHtmlContent -Entries $Entries -Summary $summary -SourceLabel $SourceLabel -GeneratedAt $generatedAt
    $csvContent = New-PortfolioCollectionStatusCsvContent -Entries $Entries

    Set-Content -LiteralPath $htmlPath -Value $htmlContent -Encoding UTF8
    Set-Content -LiteralPath $csvPath -Value $csvContent -Encoding UTF8

    # Release 3.3 milestone 4 -- decision-grade framing on the collection
    # export: the counts already exist in $summary; what was missing is what
    # a reader should conclude and do.
    if (-not (Get-Command New-DecisionGradeEnvelope -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot '..\common\DecisionGrade.ps1')
    }
    $readyForWork = [int](_GetPortfolioReportField -InputObject $summary -PropertyName 'readyForWorkCount' -Default 0)
    $missingRoadmap = [int](_GetPortfolioReportField -InputObject $summary -PropertyName 'missingRoadmapCount' -Default 0)
    $collectionEnvelope = New-DecisionGradeEnvelope -Units 'repositories' `
        -Headline $(if (@($Entries).Count -eq 0) { 'No repositories in this collection export.' } else { "$readyForWork of $(@($Entries).Count) repositories are ready for work; $missingRoadmap have no roadmap." }) `
        -NextAction $(if ($missingRoadmap -gt 0) { "Add a ROADMAP.md to the $missingRoadmap repositories without one -- no repository can be packaged for dispatch until it has one." } elseif ($readyForWork -gt 0) { 'Package the highest-value ready repository for dispatch.' } else { 'Run a portfolio assessment to refresh readiness before acting on this export.' }) `
        -WindowFrom $generatedAt.ToUniversalTime().ToString('o') -WindowTo $generatedAt.ToUniversalTime().ToString('o') `
        -AssessedCount (@($Entries).Count) -TotalCount (@($Entries).Count)

    return [pscustomobject]@{
        generatedAt = $generatedAt.ToString('o')
        repoCount = @($Entries).Count
        sourceLabel = $SourceLabel
        reportFileName = $htmlFileName
        reportPath = $htmlPath
        reportUrl = "/api/reports/$([System.Uri]::EscapeDataString($htmlFileName))"
        csvFileName = $csvFileName
        csvPath = $csvPath
        dataWindow = $collectionEnvelope.dataWindow
        units = $collectionEnvelope.units
        headline = $collectionEnvelope.headline
        nextAction = $collectionEnvelope.nextAction
        coverage = $collectionEnvelope.coverage
    }
}

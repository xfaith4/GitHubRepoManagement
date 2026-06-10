#Requires -Modules Pester
<#
.SYNOPSIS
    Pester suite for tools/Test-RoadmapStructure.ps1 — covers the original
    structural R-rules and the new roadmap-quality RQ-rules.
.DESCRIPTION
    Most cases run the validator end-to-end in a child pwsh process (so the
    script's `exit` statements cannot affect the test session), write findings
    to JSON, and assert on the parsed finding codes / exit code. A handful of
    pure-function cases dot-source the script with -LoadFunctionsOnly.

    Run with:
        Invoke-Pester ./tools/Test-RoadmapStructure.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Test-RoadmapStructure.ps1'
    if (-not (Test-Path $script:ScriptPath)) { throw "Validator not found: $script:ScriptPath" }

    # Dot-source for unit tests of helper functions.
    . $script:ScriptPath -LoadFunctionsOnly

    # Self-managed scratch dir. We avoid Pester's $TestDrive here because the
    # validator runs in a child pwsh process and writes JSON/CSV artifacts;
    # a plain temp directory is visible to both processes deterministically.
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-tests-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # A complete, valid roadmap: one active release (2.0) with every active
    # contract section, plus a matching future-release block. Uses 2.0 so the
    # "missing 1.2 when later 1.x exists" rule (R003) does not fire.
    $script:BaseValid = @'
# Test Roadmap

> **Status:** Active
> **Active release:** **Release 2.0 — Sample Active Release**

## 1. What This Document Is

Intro paragraph.

## 3. Implementation-State Vocabulary

| State | Meaning |
| ----- | ------- |
| done  | done    |

## 5. Release Roadmap

### Active release detail — 2.0 Sample Active Release

**Status:** active

**Goal:** Deliver a sample feature so the validator has a valid contract to read.

#### Product outcomes

- Operators can perform the sample workflow end to end.

#### Engineering milestones

- [ ] Implement the sample endpoint in `backend/sample.ps1`.

#### Acceptance criteria

- [ ] The sample endpoint returns a 200 response verified by `npm test`.

#### Validation plan

- [ ] Run `npm test` and `Invoke-Pester` against the sample suite.

#### Risks and blockers

- Sample fixture data may be incomplete for edge cases.

#### Dependencies

- Depends on the Release 1.9 sample groundwork.

#### Known issues / discovered during development

- None currently known.

#### Traceability

- Issue: #123
- Tests: `tests/sample.Tests.ps1`

## 6. Future Releases

### Release 2.0 — Sample Active Release

**Goal:** Deliver a sample feature so operators gain the sample workflow.

#### Product outcomes

- Operators can perform the sample workflow end to end.

#### Engineering milestones

- [ ] Implement the sample endpoint in `backend/sample.ps1`.

#### Acceptance criteria

- [ ] The sample endpoint returns a 200 response verified by integration tests.
'@

    # Run the validator end-to-end against $Content; return exit code + findings.
    function Invoke-Validator {
        param(
            [Parameter(Mandatory)][string]$Content,
            [string[]]$ExtraArgs = @(),
            [string]$CsvOut = ''
        )
        $stamp = [guid]::NewGuid().ToString('N')
        $rmPath  = Join-Path $script:WorkDir ("roadmap-$stamp.md")
        $jsonOut = Join-Path $script:WorkDir ("findings-$stamp.json")
        Set-Content -LiteralPath $rmPath -Value $Content -Encoding UTF8

        $argv = @('-NoProfile','-File', $script:ScriptPath, '-Path', $rmPath, '-JsonOut', $jsonOut)
        if ($CsvOut) { $argv += @('-CsvOut', $CsvOut) }
        $argv += $ExtraArgs

        $output = & pwsh @argv 2>&1
        $code   = $LASTEXITCODE

        $findings = @()
        if (Test-Path -LiteralPath $jsonOut) {
            $raw = Get-Content -LiteralPath $jsonOut -Raw
            if ($raw.Trim()) { $findings = @($raw | ConvertFrom-Json) }
        }
        return [pscustomobject]@{
            exit       = $code
            findings   = $findings
            codes      = @($findings | ForEach-Object { $_.code })
            output     = ($output -join "`n")
            jsonOut    = $jsonOut
            csvOut     = $CsvOut
        }
    }
}

AfterAll {
    if ($script:WorkDir -and (Test-Path -LiteralPath $script:WorkDir)) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Structural rules (regression)' {

    It 'Case 1: a valid roadmap with one active release produces no errors' {
        $r = Invoke-Validator -Content $script:BaseValid
        $r.exit | Should -Be 0
        @($r.findings | Where-Object { $_.severity -eq 'error' }).Count | Should -Be 0
    }

    It 'Case 2: detects duplicate release headings (R001)' {
        $c = $script:BaseValid + "`n`n### Release 2.0 — Duplicate Heading`n`n**Goal:** dup.`n"
        (Invoke-Validator -Content $c).codes | Should -Contain 'R001-DUP-RELEASE'
    }

    It 'Case 3: detects out-of-order releases (R002)' {
        $c = $script:BaseValid + @'


### Release 2.5 — Later First

**Goal:** later.

### Release 2.1 — Earlier Second

**Goal:** earlier.
'@
        (Invoke-Validator -Content $c).codes | Should -Contain 'R002-RELEASE-ORDER'
    }

    It 'Case 4: detects a release missing a required base section (R004)' {
        # Remove the Acceptance criteria heading from the future-release block.
        $c = $script:BaseValid -replace '(?s)#### Acceptance criteria\s*\n\s*\n- \[ \] The sample endpoint returns a 200 response verified by integration tests\.', ''
        (Invoke-Validator -Content $c).codes | Should -Contain 'R004-MISSING-SECTION'
    }

    It 'Case 5: detects a missing active-release pointer (R011)' {
        $c = $script:BaseValid -replace '(?m)^> \*\*Active release:\*\*.*$', ''
        (Invoke-Validator -Content $c).codes | Should -Contain 'R011-MISSING-ACTIVE-POINTER'
    }

    It 'Case 6: detects active pointer/detail mismatch (R011)' {
        $c = $script:BaseValid -replace 'Active release detail — 2\.0', 'Active release detail — 2.1'
        (Invoke-Validator -Content $c).codes | Should -Contain 'R011-ACTIVE-MISMATCH'
    }
}

Describe 'Roadmap-quality rules (RQ)' {

    It 'Case 7: detects an invalid status value (RQ002, error)' {
        $c = $script:BaseValid -replace '(?m)^\*\*Status:\*\* active\s*$', '**Status:** frobnicate'
        $r = Invoke-Validator -Content $c
        $r.codes | Should -Contain 'RQ002-INVALID-STATUS'
        @($r.findings | Where-Object { $_.code -eq 'RQ002-INVALID-STATUS' })[0].severity | Should -Be 'error'
    }

    It 'Case 8: detects more than one active release (RQ003)' {
        $c = $script:BaseValid + @'


### Release 2.2 — Second Active

**Status:** active

**Goal:** a second, conflicting active release.
'@
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ003-MULTIPLE-ACTIVE-RELEASES'
    }

    It 'Case 9: detects a blocked release with no blocker (RQ007)' {
        # Mark active, then add a second blocked block with empty risks.
        $c = $script:BaseValid + @'


### Release 2.3 — Blocked Work

**Status:** blocked

**Goal:** work that is stuck.

#### Risks and blockers

#### Acceptance criteria

- [ ] Something observable happens and is verified by tests.
'@
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ007-BLOCKED-WITHOUT-BLOCKER'
    }

    It 'Case 10: detects a validation release with no validation plan (RQ004-MISSING)' {
        $c = $script:BaseValid -replace '(?m)^\*\*Status:\*\* active\s*$', '**Status:** validation'
        $c = $c -replace '(?s)#### Validation plan\s*\n\s*\n- \[ \] Run `npm test` and `Invoke-Pester` against the sample suite\.', ''
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ004-MISSING-VALIDATION-PLAN'
    }

    It 'Case 11: detects a weak validation plan with no concrete signal (RQ004-WEAK)' {
        $c = $script:BaseValid -replace '(?s)- \[ \] Run `npm test` and `Invoke-Pester` against the sample suite\.', '- [ ] Make sure everything is good and ready.'
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ004-WEAK-VALIDATION-PLAN'
    }

    It 'Case 12: detects weak acceptance criteria (RQ005)' {
        $c = $script:BaseValid -replace '(?s)- \[ \] The sample endpoint returns a 200 response verified by integration tests\.', '- [ ] works'
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ005-WEAK-ACCEPTANCE-CRITERIA'
    }

    It 'Case 13: detects a done release with unchecked items (RQ008)' {
        $c = $script:BaseValid + @'


### Release 1.4 — Shipped Snapshot

**Status:** done

**Goal:** a release that claims to be done.

#### Acceptance criteria

- [x] First criterion is met and verified.
- [ ] Second criterion was never finished.
'@
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ008-DONE-WITH-UNCHECKED-CRITERIA'
    }

    It 'Case 14: detects an active release missing traceability (RQ006)' {
        $c = $script:BaseValid -replace '(?s)#### Traceability\s*\n\s*\n- Issue: #123\s*\n- Tests: `tests/sample\.Tests\.ps1`', ''
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ006-MISSING-TRACEABILITY'
    }

    It 'Case 15: detects an active release missing known-issues/pipeline feedback (RQ009)' {
        $c = $script:BaseValid -replace '(?s)#### Known issues / discovered during development\s*\n\s*\n- None currently known\.', ''
        (Invoke-Validator -Content $c).codes | Should -Contain 'RQ009-MISSING-PIPELINE-FEEDBACK'
    }
}

Describe 'Config + output + exit-code behavior' {

    It 'Case 16: config overrides required-release behavior' {
        # requiredReleases ["3.0"] -> 3.0 is missing -> R003-MISSING-RELEASE.
        $cfgPath = Join-Path $script:WorkDir 'cfg-required.json'
        '{ "requiredReleases": ["3.0"] }' | Set-Content -LiteralPath $cfgPath -Encoding UTF8
        (Invoke-Validator -Content $script:BaseValid -ExtraArgs @('-Config', $cfgPath)).codes |
            Should -Contain 'R003-MISSING-RELEASE'

        # Empty requiredReleases suppresses the default 1.2 rule even when a
        # later 1.x release exists.
        $cfgEmpty = Join-Path $script:WorkDir 'cfg-empty.json'
        '{ "requiredReleases": [] }' | Set-Content -LiteralPath $cfgEmpty -Encoding UTF8
        $c = $script:BaseValid + "`n`n### Release 1.6 — Later 1.x`n`n**Goal:** later.`n"
        $withEmpty = Invoke-Validator -Content $c -ExtraArgs @('-Config', $cfgEmpty)
        $withEmpty.codes | Should -Not -Contain 'R003-MISSING-1.2'
    }

    It 'Case 16b: a malformed explicit config raises RQ000-CONFIG-ERROR' {
        $bad = Join-Path $script:WorkDir 'cfg-bad.json'
        '{ this is not json' | Set-Content -LiteralPath $bad -Encoding UTF8
        (Invoke-Validator -Content $script:BaseValid -ExtraArgs @('-Config', $bad)).codes |
            Should -Contain 'RQ000-CONFIG-ERROR'
    }

    It 'Case 17: JSON and CSV output are written and parseable' {
        # Use a roadmap that yields at least one finding so CSV emits rows.
        $c = $script:BaseValid -replace '(?s)#### Traceability\s*\n\s*\n- Issue: #123\s*\n- Tests: `tests/sample\.Tests\.ps1`', ''
        $csv = Join-Path $script:WorkDir 'findings.csv'
        $r = Invoke-Validator -Content $c -CsvOut $csv

        Test-Path -LiteralPath $r.jsonOut | Should -BeTrue
        Test-Path -LiteralPath $csv       | Should -BeTrue
        # JSON parses back into objects with the expected fields.
        $parsed = @(Get-Content -LiteralPath $r.jsonOut -Raw | ConvertFrom-Json)
        $parsed.Count | Should -BeGreaterThan 0
        $parsed[0].PSObject.Properties.Name | Should -Contain 'recommendedAction'
        # CSV preserves the original six columns in order, then appends extras.
        $header = (Get-Content -LiteralPath $csv -TotalCount 1)
        $header | Should -BeLike '"severity","code","message","release","line","recommendedAction"*'
    }

    It 'Case 17b: a clean roadmap still writes a valid (empty) JSON array' {
        $r = Invoke-Validator -Content $script:BaseValid
        Test-Path -LiteralPath $r.jsonOut | Should -BeTrue
        (Get-Content -LiteralPath $r.jsonOut -Raw).Trim() | Should -Be '[]'
    }

    It 'Case 18: -FailOnError exits non-zero only when errors exist' {
        # Warnings only -> exit 0 even with -FailOnError.
        (Invoke-Validator -Content $script:BaseValid -ExtraArgs @('-FailOnError')).exit | Should -Be 0

        # Introduce an error (invalid status) -> exit 1 with -FailOnError.
        $c = $script:BaseValid -replace '(?m)^\*\*Status:\*\* active\s*$', '**Status:** frobnicate'
        (Invoke-Validator -Content $c -ExtraArgs @('-FailOnError')).exit | Should -Be 1
    }
}

Describe 'Helper functions (unit)' {

    It 'Get-ReleaseStatus normalizes legacy aliases' {
        (Get-ReleaseStatus -RawText '**Status:** complete.' -Cfg $script:DefaultConfig).normalized | Should -Be 'done'
        (Get-ReleaseStatus -RawText 'Status: In Progress'   -Cfg $script:DefaultConfig).normalized | Should -Be 'active'
        (Get-ReleaseStatus -RawText '**Status:** pending'    -Cfg $script:DefaultConfig).normalized | Should -Be 'planned'
    }

    It 'Get-ReleaseStatus flags unknown values as invalid' {
        $s = Get-ReleaseStatus -RawText '**Status:** frobnicate' -Cfg $script:DefaultConfig
        $s.found | Should -BeTrue
        $s.valid | Should -BeFalse
    }

    It 'Test-ValidationPlanIsConcrete recognizes concrete signals' {
        Test-ValidationPlanIsConcrete -PlanText 'Run npm test in CI'      -Cfg $script:DefaultConfig | Should -BeTrue
        Test-ValidationPlanIsConcrete -PlanText 'make sure it works well' -Cfg $script:DefaultConfig | Should -BeFalse
    }

    It 'Merge-RoadmapValidationConfig overlays file values onto defaults' {
        $override = '{ "maxActiveRoadmapLines": 1234 }' | ConvertFrom-Json
        $merged = Merge-RoadmapValidationConfig -Defaults $script:DefaultConfig -Override $override
        $merged.maxActiveRoadmapLines | Should -Be 1234
        # Untouched keys retain their defaults.
        @($merged.allowedStatuses) | Should -Contain 'validation'
    }
}

# Roadmap Validation (`Test-RoadmapStructure.ps1`)

`tools/Test-RoadmapStructure.ps1` is a **read-only** validator for this repo's
`ROADMAP.md`. It performs two layers of checks:

1. **Structural checks (`R0xx`)** — document shape: heading format, release
   ordering, required sub-sections, active-release pointer/detail agreement,
   completed-release dominance, file length, etc.
2. **Roadmap-quality checks (`RQ0xx`)** — execution-contract quality: explicit
   release status, validation plan, risks/blockers, dependencies,
   known-issues / pipeline feedback, traceability, and acceptance-criteria
   strength.

The validator never modifies `ROADMAP.md`. It prints operator-readable findings
to the console and can additionally emit machine-readable JSON and CSV.

> Roadmaps are execution contracts. This validator answers: *is the active
> release not only well-formatted, but actually usable as a contract you can
> dispatch, validate, and merge against?*

---

## Running it

```powershell
# Console report
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md

# With machine-readable output
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md `
    -JsonOut ./out/roadmap-findings.json -CsvOut ./out/roadmap-findings.csv

# CI gate — exits non-zero ONLY on error-severity findings
pwsh ./tools/Test-RoadmapStructure.ps1 -FailOnError

# With a repo-specific config
pwsh ./tools/Test-RoadmapStructure.ps1 -Config ./standards/roadmap/roadmap-validation.config.json
```

Compatible with Windows PowerShell 5.1 and PowerShell 7+. No external modules.

### In CI

The repo's `CI Smoke` workflow already runs the validator as a gate:

```yaml
- name: Validate ROADMAP.md structure
  shell: pwsh
  run: ./tools/Test-RoadmapStructure.ps1 -Path "${{ github.workspace }}/ROADMAP.md" -FailOnError
```

Because only **error**-severity findings fail the build, the new quality
checks (which are mostly warnings/info) surface roadmap weaknesses without
breaking existing pipelines. Promote a check to a hard gate by configuring it
(see `treatDoneWithUncheckedCriteriaAsError`) — never by editing the script.

---

## Exit codes

| Code | Meaning |
| ---- | ------- |
| `0`  | Validation ran. Default behavior, or `-FailOnError` with no error findings. |
| `1`  | `-FailOnError` was set and at least one **error**-severity finding exists. |
| `2`  | The roadmap file was not found at `-Path`. |

---

## Configuration

All repo-specific opinions are data, not code. Drop a config file at either:

- `standards/roadmap/roadmap-validation.config.json` (preferred), or
- `tools/roadmap-validation.config.json`

…and it is auto-discovered. Or pass `-Config <path>` explicitly. A starter
file lives at
[`standards/roadmap/roadmap-validation.config.example.json`](../../standards/roadmap/roadmap-validation.config.example.json).

Rules:

- **No config present** → built-in defaults apply (identical to the legacy
  structural linter plus the default quality rules).
- **Config present** → it is *merged over* the defaults; omitted keys keep
  their defaults; unknown keys are ignored.
- **Explicit `-Config` that is missing or malformed** → an
  `RQ000-CONFIG-ERROR` finding is raised. It only fails the build under
  `-FailOnError`.

### Keys

| Key | Default | Effect |
| --- | ------- | ------ |
| `requiredSections` | Goal, Product outcomes, Engineering milestones, Acceptance criteria | Sub-sections every release must have (`R004`). |
| `activeReleaseRequiredSections` | Validation plan, Risks and blockers, Dependencies, Known issues, Traceability | Sections expected on active/blocked/validation releases. |
| `allowedStatuses` | planned, active, blocked, validation, done, archived | Canonical statuses; anything else is `RQ002` (error). |
| `statusAliases` | pending→planned, in progress→active, complete→done, … | Legacy wording normalized before validation. |
| `requiredReleases` | `["1.2"]` | `1.2` keeps "only required when a later 1.x exists" semantics; other versions are hard-required (`R003-MISSING-RELEASE`). |
| `maxActiveRoadmapLines` | 900 | File-length warning threshold (`R010`). |
| `maxFutureReleaseLines` | 120 | Future-release size warning threshold (`R013`). |
| `allowImmediateNextFocus` | false | When true, suppresses `R006-IMMEDIATE-NEXT-FOCUS-PRESENT`. |
| `requireImplementationStateVocabulary` | false | When true, missing vocabulary section is a warning (else info, `R009`). |
| `treatDoneWithUncheckedCriteriaAsError` | false | When true, `RQ008` is an error instead of a warning. |
| `flagMissingStatusOnFutureReleases` | false | When true, future releases without a Status line emit info `RQ001`. |
| `flagFutureReleaseRecommendations` | false | When true, planned releases missing Dependencies/Non-goals emit info `RQ011`/`RQ012`. |
| `validationSignals` | npm test, Invoke-Pester, CI, … | Tokens that make a validation plan "concrete" (`RQ004-WEAK`). |
| `weakAcceptanceTerms` | works, done, polish, … | Vague acceptance-criterion terms (`RQ005`). |
| `pipelineKeywords` | bug, regression, ci, build, … | Discovered-issue keywords for the feedback rule (`RQ010`). |

---

## Finding codes

### Structural (`R0xx`) — preserved from the original linter

`R000-NO-RELEASES`, `R001-DUP-RELEASE`, `R002-RELEASE-ORDER`,
`R003-MISSING-1.2` / `R003-MISSING-RELEASE`, `R004-MISSING-SECTION`,
`R005-TITLE-GOAL-MISMATCH`, `R006-IMMEDIATE-NEXT-FOCUS-PRESENT` /
`R006-DANGLING-NEXT-FOCUS`, `R007-UNCHECKED-NO-ACCEPTANCE`,
`R008-COMPLETED-DOMINANCE`, `R009-MISSING-STATE-VOCAB`, `R010-FILE-LENGTH`,
`R011-MISSING-ACTIVE-POINTER` / `R011-MISSING-ACTIVE-DETAIL` /
`R011-ACTIVE-MISMATCH`, `R012-COMPLETED-IN-ACTIVE`, `R013-FUTURE-RELEASE-SIZE`.

### Roadmap-quality (`RQ0xx`) — new

| Code | Severity | Meaning |
| ---- | -------- | ------- |
| `RQ000-CONFIG-ERROR` | error* | An explicit `-Config` file is missing or unparseable. |
| `RQ001-MISSING-STATUS` | warning / info | Active detail block (or, opt-in, a future release) has no Status line. |
| `RQ002-INVALID-STATUS` | error | Status value is not in `allowedStatuses` (after alias normalization). |
| `RQ003-MULTIPLE-ACTIVE-RELEASES` | error | More than one release is marked `active`. |
| `RQ003-ACTIVE-POINTER-MISMATCH` | error | The top active pointer disagrees with the release marked `active`. |
| `RQ004-MISSING-VALIDATION-PLAN` | warning | Active/blocked/validation release has no validation plan. |
| `RQ004-WEAK-VALIDATION-PLAN` | warning | Validation plan exists but names no concrete validation signal. |
| `RQ005-WEAK-ACCEPTANCE-CRITERIA` | warning | Vague acceptance criteria (e.g. "works", "polish"). |
| `RQ006-MISSING-TRACEABILITY` | warning | Active/validation release has no issue/PR/test/ADR/doc/workflow link. |
| `RQ007-BLOCKED-WITHOUT-BLOCKER` | warning | A `blocked` release lists no blocker. |
| `RQ008-DONE-WITH-UNCHECKED-CRITERIA` | warning* | A `done` release still has unchecked items. |
| `RQ009-MISSING-PIPELINE-FEEDBACK` | warning | Active/blocked/validation release lacks a known-issues section. |
| `RQ010-EMPTY-KNOWN-ISSUES` | info | Known-issues section is empty, or lists trouble with no follow-up signal. |
| `RQ011-MISSING-DEPENDENCIES-SECTION` | warning / info | Dependencies section missing (active = warning; planned = opt-in info). |
| `RQ012-MISSING-NON-GOALS` | info | Planned release has no Non-goals / Out-of-scope section (opt-in). |

\* `RQ000` only fails the build under `-FailOnError`; `RQ008` severity is
configurable via `treatDoneWithUncheckedCriteriaAsError`.

---

## Output fields

Every finding carries the original six fields — `severity`, `code`,
`message`, `release`, `line`, `recommendedAction` — unchanged. Three additive
fields are appended for richer tooling: `category` (`structure` | `quality` |
`config`), `section`, and `rule`. JSON includes all nine; CSV keeps the
original six columns in order and appends the three new ones, so both
header-keyed and fixed-column consumers keep working.

See [docs/reference/roadmap-contracts.md](../reference/roadmap-contracts.md)
for the canonical release contract and good/weak release examples.

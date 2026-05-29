# Portfolio Assessment

This document describes the portfolio assessment model — the single normalized record per repository that
combines git status, documentation audit, roadmap state, roadmap maturity, repo structure audit, and
execution state into one operator-facing view.

The assessment is the data source for the Portfolio Mission panel, the Work Queue value ranking, and the
Collection Status Report export.

---

## What Is a Portfolio Assessment?

A **portfolio assessment** is one record per repository that answers: *"What is the current state of
this repo, and what should the operator do with it next?"*

The assessment combines six signal sources into a single normalized model:

| Signal | Source | Purpose |
| --- | --- | --- |
| `status` | `Get-StatusAdapterResult` | Git branch, dirty state, archived flag, GitHub URL link |
| `roadmap` | Roadmap index cache | Roadmap presence, pending count, next pending item |
| `docAudit` | DocAudit scanner | README presence, doc findings, dispatch readiness |
| `roadmapAudit` | Roadmap auditor | Maturity level (L0–L4) and score |
| `execution` | Execution ledger | Whether a Copilot task is running for the repo |
| `github` | GitHub API/CLI (opt-in) | Repos that exist on GitHub but not on disk |

Each signal source is reused from its existing TTL cache when available; the assessment route does not
re-run scans that already have warm cached results.

---

## Lifecycle State

Every assessment record carries one `lifecycleState` — the single operator-facing status for the repo.
The state is computed by deterministic precedence (first match wins):

| Order | State | Trigger | Meaning |
| --- | --- | --- | --- |
| 1 | `archived` | `isArchived = true` | Repo is archived; no action expected |
| 2 | `parse-error` | `roadmapState = parse-error` | Roadmap exists but cannot be parsed |
| 3 | `running` | `executionState = running` | A Copilot task is in flight |
| 4 | `needs-readme` | README is missing | First action: generate a README |
| 5 | `needs-roadmap` | No `ROADMAP.md` on disk | First action: run repo evaluation to draft a roadmap |
| 6 | `needs-roadmap-repair` | Maturity below L3 (and roadmap not complete) | First action: open the Roadmap Repair preview |
| 7 | `needs-structure` | Critical/warning structure findings remain *or* doc-audit blocks dispatch | First action: fix missing structural elements or doc findings |
| 8 | `ready-for-work` | Maturity ≥ L3 *and* pending items > 0 | Dispatch the next pending roadmap item |
| 9 | `completed` | `roadmapState = complete` | No pending work; consider drafting next release |
| 10 | `monitored` | No pending work and no blockers | Stable; nothing to do |
| 11 | `discovered` | Fallback when signals are inconsistent | Re-run a portfolio scan to refresh signals |

Each record also carries:

- `recommendedAction` — short, concrete next-step phrase shown in the dashboard
- `blockingReasons` — list of human-readable strings explaining why the repo is in this state

### Why `ready-for-work` trusts the roadmap audit

When maturity is L3+ and pending items > 0, the repo is classified `ready-for-work` regardless of what
`dispatchReadiness` (from doc-audit) says. This is intentional: doc-audit and roadmap-audit can drift
out of sync (see Phase 2 investigation in `ROADMAP.md`), and the roadmap audit is the authoritative
source for "is the roadmap a valid work contract?"

---

## Source Coverage

Every assessment record carries `sourceCoverage`, one of:

| Value | Meaning |
| --- | --- |
| `local` | Repo present on disk only — no linked GitHub remote detected |
| `local+github` | Repo present on disk *and* has a `htmlUrl` (or matched a GitHub inventory entry) |
| `github` | Repo present on GitHub only — no local clone in any configured `inventory.localRoots` |

GitHub-only entries appear only when `?includeGithub=true` is passed and a `gitHubOwner` is configured
in `settings.json`.

---

## Value Ranking

The assessment carries both the full scored pending-work list and the highest-value recommendation for
each repo:

- `pendingItems` — all pending roadmap items with tags, per-item score, value tier, and rationale.
- `topValueItem` — the single highest-value pending roadmap item for the repo, or `null` when the repo
  has no rankable roadmap work.

The Work Queue consumes `topValueItem` to rank ready repos by value within each readiness bucket and to
show operators *why* a repo rose to the top before they preview or dispatch work.

---

## Collection Status Report

The dashboard `Report` action now exports a **Collection Status Report** backed by portfolio assessment
entries rather than only raw repo-status rows.

The HTML and CSV artifacts answer four operator questions in one place:

1. What lifecycle state is each repo in right now?
2. What is blocking it from progress or dispatch?
3. What is the recommended next action?
4. What is the highest-value pending roadmap work when the repo is ready?

The HTML report includes:

- lifecycle counts for the exported portfolio slice
- a top recommended work list based on `topValueItem`
- the north-star operator workflow summary
- one row per repo with lifecycle, action, blockers, and documentation signals

The CSV companion file carries the same operational fields in spreadsheet-friendly form.

### Export route

- `POST /api/export` with `portfolioEntries` and `sourceLabel`
- `GET /api/reports/:reportName` to open the saved HTML or CSV artifact

If the dashboard cannot obtain portfolio assessment entries, it can still fall back to the older repo-status
export input (`repos`) so reporting never hard-fails solely because the richer portfolio model is unavailable.

---

## North-Star Workflow

The product direction is intentionally ordered. The normal operator loop is:

1. Assess the collection.
2. Classify each repo into one lifecycle state.
3. Surface blockers and recommended next actions.
4. Repair README, roadmap, or structure gaps.
5. Rank the highest-value pending roadmap work.
6. Refine the Copilot task packet.
7. Dispatch and monitor execution.
8. Re-run validation and export a Collection Status Report.

This workflow is mirrored in the Help modal and in the report itself so the UI, report output, and product
direction all describe the same operating loop.

---

## Repo Structure Audit

The structure audit (`Invoke-RepoStructureAudit`) checks each repo against the data-driven standard at
`backend/config/repo-structure-standards.json`. The standard defines:

- **Required root files** — README, ROADMAP, LICENSE, SECURITY, CONTRIBUTING, .gitignore (each with
  severity `critical`, `warning`, or `info` and an alt-name list)
- **Required root folders** — e.g. `docs/`
- **CI signals** — e.g. `.github/workflows/` containing at least one workflow file
- **Test signals** — derived per repo type (node, dotnet, python, rust, powershell, go, other)

Each missing element produces a `structureFinding` on the assessment record:

```json
{
  "kind": "missing-root-file",
  "target": "LICENSE",
  "category": "compliance",
  "severity": "warning",
  "recommendedAction": "Add a LICENSE file to make terms of use explicit."
}
```

---

## API Reference

### `GET /api/portfolio/assessment`

Returns one assessment record per repo plus a portfolio-level summary.

**Query parameters:**

| Param | Default | Effect |
| --- | --- | --- |
| `refresh` | `false` | When `true`, invalidates the assessment cache and re-runs all underlying scans |
| `includeGithub` | `false` | When `true`, enumerates GitHub-only repos via the configured `gitHubOwner` |
| `scanMode` | `full` | `full` runs normal assessment; `differential` re-assesses only repos whose tracked local/GitHub signals changed since the last persisted index snapshot |

**Response shape:**

```json
{
  "success": true,
  "data": {
    "entries": [ /* PortfolioAssessmentEntry[] */ ],
    "summary": { /* PortfolioAssessmentSummary */ },
    "signalSources": {
      "status": "cache" | "fresh-scan" | "error",
      "roadmap": "cache" | "fresh-scan" | "deferred-differential" | "differential-scan" | "differential-noop",
      "docAudit": "cache" | "fresh-scan" | "deferred-differential" | "differential-scan" | "differential-noop",
      "roadmapAudit": "cache" | "cache-filtered" | "unavailable" | "deferred-differential" | "differential-noop",
      "execution": "ledger" | "unavailable",
      "github": "api" | "not-evaluated" | "no-owner-configured" | "no-token" | "error",
      "scanMode": "differential" | "differential-fallback-full",
      "differentialChangedCount": 0,
      "differentialUnchangedCount": 0
    },
    "generatedAt": "ISO-8601",
    "count": 0,
    "cacheSource": "memory" | "fresh-scan",
    "cacheAgeSeconds": 0
  }
}
```

**Cache behavior:**

- The route holds a 180-second in-memory TTL cache (configurable via `settings.json` →
  `portfolio.assessmentCacheTtlSeconds`).
- It opportunistically reuses the existing `status`, `roadmap`, `docAudit`, and `roadmapAudit` caches
  when warm. It does *not* re-run those scans on its own when their caches are populated.
- `scanMode=differential` bypasses the route-level in-memory assessment cache to ensure the response
  reflects the requested differential mode and emits differential signal markers.
- When the route's own cache misses **and** any underlying signal cache is cold, it triggers a
  cascading fresh-scan. On a portfolio of 50+ repos this can take several minutes on first call.
  Subsequent calls within the TTL window return in well under a second.

**`signalSources` field:** every response declares where each signal came from, so an operator can tell
whether they are looking at a stale-vs-fresh view per signal type. This is especially useful when
`roadmapAudit` is `unavailable` (no warm cache; maturity-driven lifecycle decisions degrade to L0).

---

## Portfolio Summary

The `summary` block aggregates portfolio-level counts:

```json
{
  "totalRepos": 0,
  "byLifecycle": { "discovered": 0, "needs-readme": 0, /* … one per lifecycle state */ },
  "bySourceCoverage": { "local": 0, "github": 0, "local+github": 0 },
  "missingReadmeCount": 0,
  "missingRoadmapCount": 0,
  "weakRoadmapCount": 0,
  "readyForWorkCount": 0,
  "runningCount": 0,
  "blockedCount": 0
}
```

`weakRoadmapCount` is the count of repos that have a roadmap but with maturity below L3.
`blockedCount` is the count of repos in `needs-readme`, `needs-roadmap`, `needs-roadmap-repair`,
`needs-structure`, or `parse-error`.

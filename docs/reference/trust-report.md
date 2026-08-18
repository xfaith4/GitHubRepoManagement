# Trust Report — the 15 Findings, Before and After

**Release 3.5 acceptance deliverable.** The 2026-08-14 adversarial UI review
([source](2026-08-15-UI-Adversarial_Review.md),
[triage](2026-08-15-ui-review-triage.md)) numbered 15 findings. This report
records, per finding: the before value, the after state, and fixed / not-fixed
with the reason. A number that moved because it was wrong is labelled as the
fix it is — `Stale: 0 → measured` is honesty arriving, not a regression.

## Contradictions (findings 1–9)

| # | Before | After | Status |
| --- | --- | --- | --- |
| 1 | Four denominators on one screen: header `76` · Operations `75` · Doc Readiness `52` · Mission `27` | Each names its dimension: header `N scanned · M in-scope`; Mission `Assessed (of N scanned)` reads the snapshot's denominator; all share one *as of* instant (snapshot fetched with each repo-list refresh) | **Fixed** (#146, #151) |
| 2 | `Stale Repositories: 0` beside a dead 14-day threshold, repos years behind | `staleThreshold` retired (consumed nowhere; wiring days into the 300s drift tolerance would have blanked 3.1's staleness column); the stale KPI counts 3.1's measured remote drift over the in-scope set; the filter tooltip states the drift definition | **Fixed** (#145) |
| 3 | Ready-queue depth `21 / 0 / 0` across three views | Three distinct measurements named apart — *Claimable Lanes* / *dispatch-ready* / *Work-ready (L3+)* — as three snapshot metrics with sources and definitions; live CI equalities pin each endpoint to its metric | **Fixed** (#147, #151, #152; equalities completed in this PR) |
| 4 | One card: tiles `0% / 0% / 0 Ready` above trend rows `20% / 22` | History-backed reads take tiles from the latest history day — the same source as the rows; docs health (no history column) reads `—`, never a fake `0%` | **Fixed** (#145) |
| 5 | `Ready Repos … High 1592` on a 76-repo portfolio; `-81 vs start` | The day-grouped `SUM` counted every capture; both trend queries now take each repo's latest capture per day, and the store-level invariant (`ready ≤ distinct repos`) is asserted against a fixture the old SQL demonstrably fails (returns 3 over 2 repos) | **Fixed** (#145) |
| 6 | `Docs Health` = `54%`, `0%`, and per-repo values with no aggregation rule | One nullable average with `docsHealthAssessedCount` beside it; partial samples say *"of N assessed"*; the definition rides the snapshot metric | **Fixed** (#145, #147) |
| 7 | `README Score 84%` above `Missing README 37` — the average silently skipped the unscored | Null-skipping still averages the assessed (legitimate arithmetic), but the coverage travels with it: *"of N assessed"* hints, `confidence: partial`, and empty sets read `—` — a partial sample can no longer pose as the portfolio | **Fixed** (#145, #147) |
| 8 | One generation event stamped `7:54:24 AM` and `11:54:24 AM` | Payload timestamps carry an explicit basis (Z or offset), enforced by a recursive walker over live payloads in CI; artifact display stamps carry ` UTC`; the render boundary formats once via `toLocale*` | **Fixed** (this PR) |
| 9 | Group headers `35 + 15 = 50` — counting the page, presenting the portfolio | Confirmed root cause (`groupedRepos` reduces over `pagedRepos`); headers count what they show, and the KPI row above carries the portfolio numbers with their scope stated | **Fixed by framing** — group headers are page-scoped by design (they head page groups); the defect was the *missing* portfolio-scoped labels beside them, which the scoped KPI row now provides |
| — | | | |

## Silent failures (findings 10–13)

| # | Before | After | Status |
| --- | --- | --- | --- |
| 10 | Five permanent spinners, no timeout/error/retry | Zero: two panels on the full state machine (error-with-retry, stale-keeps-last-good, empty-with-timestamp); the other four fetches carry the shared 10s deadline naming their endpoint | **Fixed** (#148, #152) |
| 11 | `Runner stalled` as red text below the fold; header says `6 active` | Severity-colored runner pill beside the activity indicator on every tab; one click to the remedy command with a Copy button; the queue-age alarm escalates past-24h queued work **even with a present runner**; `6 active` → `6 agent runs`, named in its tooltip | **Fixed** (#149) |
| 12 | `4 stranded` badge above 13 rendered entries — a retry loop as a backlog | Packaged items group by `(repo, itemText)`: newest attempt as the face, earlier attempts behind an *"N earlier attempts"* expander; the list counts work and agrees with its badge | **Fixed** (#149) |
| 13 | `No cross-repo dependencies detected` — including on fetch failure (silent catch) | `error` (endpoint + message + Retry), `empty` (computed, stamped with the scanner's `scannedAt`, *Compute now*), `stale` (last good graph + failure age) are three distinct renderings; `empty` is only reachable through a success, by construction | **Fixed** (#148) |

## Scope contamination (findings 14–15)

| # | Before | After | Status |
| --- | --- | --- | --- |
| 14 | `.tmp_compare` clones, `Archive/` trees, worktree containers and vendored repos counted as portfolio — and ranked in the Doc Readiness queue | Classified at the scan producer (`excluded-path` / `archived` / `vendored`), hidden behind a default-on toggle with per-row reasons, **never deleted**; KPI math and (this PR) the assessment/doc-readiness/value-ranking intake run over the in-scope set; an empty owner set disables vendor classification | **Fixed** (#146; assessment recompute in this PR) |
| 15 | Local `Genesys.Core_AuditLogsApp` "mislabeled" with `xfaith4/Genesys.Core`'s remote | Reproduced live and found *cleaner than claimed*: a genuine second clone (same remote, same root commit `d884af1`). Identity dedupe groups by normalized remote URL, subdivided by root-commit SHA paid only inside colliding groups; both checkouts surface under one identity | **Fixed** (#146) |

## Corrections to the review, held

- **`Drift unknown` was not removed** — it varies by design (renders only when
  staleness resolved `unknown`); its ubiquity was a finding about unreachable
  remotes, not badge design. `No Builds` remains grid-visible via build-status
  grouping rather than as an invariant chip.
- **No suite was committed red** — every gate landed with its fix and was
  proven non-vacuous against the pre-fix code (the `ready=3 over 2 repos`
  fixture, the pre-route contract failures, the walker's own 315-second
  infinite-recursion discovery).
- **The `Today` view was not built** — it remains Lane 0.5's product decision,
  now standing on numbers that can support it.

## Deliberate residuals (recorded, not hidden)

- Operations panels keep last-good-on-refresh-failure only via unchanged data
  retention, not the full `stale` rendering — deferred to the Release 3.2
  `Dashboard.tsx`/`OperationsWorkspaceView` refactor.
- The markup-level "component computes its own metric" tripwire was **rejected
  as gameable**; the live cross-endpoint equalities are the behavior-derived
  enforcement, per this repo's presence-vs-behavior principle.
- Live-portal screenshots and operator sign-off ride Release 2.9's batched
  session, alongside the other operator-verified proofs.

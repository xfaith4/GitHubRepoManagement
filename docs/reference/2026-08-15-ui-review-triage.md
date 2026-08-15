# UI Adversarial Review — Merit Triage

**Source:** [`2026-08-15-UI-Adversarial_Review.md`](2026-08-15-UI-Adversarial_Review.md)
(reviewed 14 Aug 2026 against `http://127.0.0.1:7071/`)
**Triaged:** 2026-08-15, against the code rather than against the screenshots.
**Consumer:** [Release 3.5 — Trustworthy Surfaces](../../ROADMAP.md#release-35--trustworthy-surfaces-ui-quality)

---

## Why this file exists

The review asserts UI symptoms. A roadmap needs causes. Every finding below was
checked against the source before it was scheduled, and three of them turned out
to be something other than what the review said they were — one has a
single-line root cause the review could not have seen, one is already half-shipped,
and one would be made **worse** by the fix the review proposes.

Verdicts used:

| Verdict | Meaning |
| --- | --- |
| `confirmed` | Reproduced in the source; the review's description matches the mechanism. |
| `confirmed + cause` | Reproduced, and the specific defect line is identified below. |
| `narrowed` | Real, but partly closed by shipped work; only the named residue is open. |
| `reframed` | Symptom real, diagnosis wrong; fixing it as described would remove signal. |
| `unverified` | Needs live workspace data; scheduled with verification as step one. |
| `routed` | Legitimate, but a product/design decision that belongs to an existing lane. |

---

## Tier 1 — Contradictory numbers

| # | Finding | Verdict | Evidence |
| --- | --- | --- | --- |
| 1.1 | Four repo denominators (76 / 75 / 52 / 27) | `confirmed` | Four independent producers with no reconciliation: the grid's `summary.total` is `reposWithRoadmap.length` ([Dashboard.tsx:1013](../../frontend/components/Dashboard.tsx#L1013)), Operations reports index entries, Doc Readiness reports audited entries, Portfolio Mission reports assessment `totalRepos`. No component reads a shared set. |
| 1.2 | `Stale Repositories 0` against a 14-day threshold | `confirmed + cause` | Two unrelated concepts share one word. `settings.staleThreshold` is consumed **nowhere in `backend/`** (zero matches) — it is a dead setting rendered as a live control at [SettingsModal.tsx:172](../../frontend/components/SettingsModal.tsx#L172). Meanwhile `isStale` was redefined by Release 3.1 to mean *local behind remote*, a drift concept with no day threshold. The KPI also counts over `reposWithRoadmap`, not the portfolio ([Dashboard.tsx:1015](../../frontend/components/Dashboard.tsx#L1015)). |
| 1.3 | Ready-queue depth disagrees three ways | `confirmed` | Five separate computations of "ready": [InsightsView.tsx:187](../../frontend/components/InsightsView.tsx#L187), [ExecutionQueuePanel.tsx:358](../../frontend/components/ExecutionQueuePanel.tsx#L358) (`rankedQueue.length`), [portfolioTrendView.ts:215](../../frontend/lib/portfolioTrendView.ts#L215) (`summary.readyForWorkCount`), [WorkQueueView.tsx:334](../../frontend/components/WorkQueueView.tsx#L334) (`readinessCounts`), and `Portfolio.Report.ps1`. Each is right about its own source. |
| 1.4 | Analytics tiles say `0%`, its own trend rows say `20%` | `confirmed + cause` | In `Get-PortfolioTrendPayload`, `$summaryPayload` (the tiles) is built from the passed-in `$Assessments`/`$Summary`, then `$series` (the rows) is **replaced wholesale** from `app.db` history when history exists ([Portfolio.Analytics.ps1:317-333](../../backend/modules/portfolio/Portfolio.Analytics.ps1#L317-L333)). An index-only read supplies no assessments, so the tiles compute over an empty set while the rows come from the database. One card, two data paths. |
| 1.5 | `Ready Repos … High 1592` on a 76-repo portfolio | `confirmed + cause` | The highest-confidence defect in the review, and a one-line fix. `ready_repo_count` is `SUM(CASE … THEN 1 ELSE 0 END)` grouped by `captured_day` over `maturity_history` ([Portfolio.Analytics.ps1:120](../../backend/modules/portfolio/Portfolio.Analytics.ps1#L120)) — a table holding **one row per repo per capture**. Every capture in a day adds its ready repos again. The sibling column uses `AVG`, which is why Avg Maturity stayed plausible at 20% while Ready Repos went to 1592; that asymmetry is exactly what the reviewer saw. `-81 vs start` is the same defect read as a delta. |
| 1.6 | `Docs Health` has three values | `confirmed` | Same split as 1.4 for the docs series, plus per-repo scores with no stated aggregation rule anywhere in the payload or the UI. |
| 1.7 | `README Score 84%` above `Missing README 37` | `confirmed + cause` | `_GetPortfolioAnalyticsAverage` skips null entries with `continue` ([Portfolio.Analytics.ps1:61](../../backend/modules/portfolio/Portfolio.Analytics.ps1#L61)), so every average is over *scored* repos only — the headline improves as unscored repos accumulate. The same helper returns `0` for an empty set ([:69](../../backend/modules/portfolio/Portfolio.Analytics.ps1#L69)), making "not computed" indistinguishable from "zero". |
| 1.8 | One event stamped `7:54:24 AM` and `11:54:24 AM` | `confirmed` | Mixed stamping convention, verified by count: ~181 sites use `(Get-Date).ToUniversalTime().ToString('o')`, while `Portfolio.Report.ps1`, `Start-RepoManagementApiHost.ps1` (`generatedAt = Get-Date`), `Metrics.ps1` and `SessionAuth.ps1` stamp local. The frontend renders every stamp through `toLocaleTimeString()`, so any payload whose zone basis is lost renders its UTC digits as if local — a 4-hour skew at UTC-4, which is the skew observed. The exact leaking field is left for the tripwire to name rather than guessed at here. |
| 1.9 | Group headers count the page, not the portfolio | `confirmed + cause` | `groupedRepos` reduces over `pagedRepos`, not the filtered set ([RepoGrid.tsx:372](../../frontend/components/RepoGrid.tsx#L372)). `35 + 15 = 50` is the rows-per-page value, exactly as the review reasoned. |

**Root-cause hypothesis — accepted.** Four producers (live scan, portfolio index,
execution ledger, `app.db`) each render through whichever component owns them,
with no reconciliation layer and no shared "as of" instant.

---

## Tier 2 — Inventory without ranking

| Finding | Verdict | Note |
| --- | --- | --- |
| The value ranking exists but is buried three clicks deep | `routed` | Real. The `Today` landing view the review proposes is a **product decision**, and it collides with the already-open progressive-disclosure question in Lane 0.5 — which is the same decision asked a different way. Routed there, not scheduled as engineering. The review agrees on ordering: nothing ranked should be built on numbers that still contradict each other. |
| Nine equal-weight buttons per row, no primary action | `routed` | Same lane, same decision. |
| Read-only and irreversible actions share a visual weight | `confirmed` | This is the visual analogue of Release 3.1's shipped guardrail *"do not leave a control enabled that cannot succeed"*: 3.1 made a control state its **availability**, this makes it state its **consequence**. Cheap, safety-relevant, scheduled. |
| Bulk actions default to the whole portfolio | `narrowed` | Lane 0.5 shipped bulk-scope confirmation on mutating actions 2026-08-10 ([bulkScope.ts](../../frontend/lib/bulkScope.ts)), so the review's "no mitigation" framing is out of date. The open half is the review's real point: a confirm is a weak fix for wrong-by-default **scoping**. Only the default changes. |
| Seven verbs for one concept | `confirmed` | `Refresh All`, `Refresh`, `Scan All`, `Sync`, `Reload List`, `Retry`, `Evaluate` coexist with no statement of what each invalidates. |
| Three unmapped status vocabularies | `confirmed` | Grid chips, Operations lifecycle, and maturity levels have no mapping between them. The cited instance — one repo reading `Ready` on one tab and `blocked / L0-Absent` on another in the same session — is the failure mode, not a cosmetic complaint. |

---

## Tier 3 — Invisible failure states

| Finding | Verdict | Evidence |
| --- | --- | --- |
| Five permanent spinners, no timeout or error state | `confirmed` | All five located verbatim: [App.tsx:380](../../frontend/App.tsx#L380), [ExecutionQueuePanel.tsx:435](../../frontend/components/ExecutionQueuePanel.tsx#L435), [OperationsWorkspaceView.tsx:1234](../../frontend/components/OperationsWorkspaceView.tsx#L1234), [:1415](../../frontend/components/OperationsWorkspaceView.tsx#L1415), [:2037](../../frontend/components/OperationsWorkspaceView.tsx#L2037). Each is an ad-hoc boolean; there is no shared async state model. |
| `Runner stalled` buried below the fold | `narrowed` | Release 3.1 shipped the presence gate, the disabled approve controls, the stranded badge and `resolveRunnerPresence`. What it did **not** ship is delivery: no runner-health indicator in the header beside `Backend: Online`, no copy affordance for the remedy command, no above-fold placement. Only that residue is open. |
| `4 stranded` badge above 13 rendered entries | `confirmed` | Two sources: the badge reads backend `strandedCount` ([PackagedItemQueue.tsx:76](../../frontend/components/PackagedItemQueue.tsx#L76)), the list renders raw queue entries with no grouping by `(repo, task_id)`. This is the UI face of an already-recorded Release 3.1 non-blocker — *"the same item can still be queued twice while a runner is present"* — so the dedupe belongs here and the idempotency stays there. |
| Dependencies asserts a clean bill of health it did not earn | `confirmed` | `!dependencyGraph \|\| summary.length === 0` renders one message for both *not computed* and *computed, found nothing* ([Dashboard.tsx:1536](../../frontend/components/Dashboard.tsx#L1536)), and drops the `scannedAt` that `Roadmap.DependencyTracker.ps1` already emits. |
| Debug telemetry in the Portfolio Mission card | `confirmed` | Degradation values (`stale-cache`, `unavailable`) carry the same styling as ordinary fields — a warning rendered as data. |

---

## Tier 4 — Scope contamination

**Verdict: `confirmed`, and the highest leverage per unit of effort in the review.**
Every percentage in the product is computed over the contaminated set, so this is
upstream of most of Tier 1.

- `backend/config/settings.json` carries `inventory.maxDepth: 3` and **no exclusion
  policy of any kind**.
- The only ignore list in the scan path is build-artifact *directory names*
  ([Invoke-Reconciliation.ps1:75-83](../../backend/modules/reconcile/Invoke-Reconciliation.ps1#L75-L83)):
  `node_modules, vendor, dist, build, out, .vs, .idea, .vscode, bin, obj, .venv, venv, __pycache__, .next, .pytest_cache`.
  No `.tmp*`, no `Archive`, no worktrees, no remote-owner filter.
- Consequence: temp compare directories, archived folders and vendored third-party
  clones enter portfolio math and the ranked work queue as first-class repositories.
- The `Critical 2386 / 2200 / 1993` ahead-behind counts dominating the triage order
  are the same defect seen through Release 3.1's new staleness signal: upstream
  drift on a clone nobody owns is not portfolio debt.

**Identity mis-mapping — `unverified`.** The duplicate-set detector is real
([RepoGrid.tsx:680](../../frontend/components/RepoGrid.tsx#L680)), but the specific
claim that one local repo carries another's remote needs the live workspace to
confirm. Scheduled with reproduction as step one, and with the fix stated
structurally: deduplicate by `(remote_url, root_commit_sha)` rather than by folder
name.

**Constraint carried into the roadmap:** nothing is deleted. Out-of-scope repos are
reclassified and stay visible behind a toggle, because a scan that silently drops
repositories is the same class of lie as a metric that silently drops them.

---

## Tier 5 — Interaction, accessibility, copy

| Finding | Verdict | Note |
| --- | --- | --- |
| Card density; a table would fit the portfolio in two screens | `routed` | Design-dependent, and already contested space: Lane 0.5 owns the disclosure question and Release 3.2 owns grid virtualization. Duplicating it here would schedule the same decision twice. |
| Dead `Clone PLANNED` / `Archive PLANNED` in prime toolbar slots | `confirmed` | [ActionBar.tsx:156](../../frontend/components/ActionBar.tsx#L156), [InitModal.tsx:92](../../frontend/components/InitModal.tsx#L92). Both are correctly disabled and labelled — Release 3.1's audit already required that — so the residual finding is narrower than "dead controls": they occupy two of eight primary slots. That is placement, not honesty. |
| `Drift unknown` and `No Builds` on every row are chrome | `reframed` | **The proposed fix would destroy signal.** `Drift unknown` renders *only* when `staleness.state === 'unknown'` ([RepoGrid.tsx:1017](../../frontend/components/RepoGrid.tsx#L1017)) — it varies by design. Appearing on every row means staleness resolved `unknown` portfolio-wide, which is a finding about clones with no reachable remote (consistent with the Release 3.1 measurement of clones that had never fetched), not a finding about badge design. Fix: make the chip say **why** it is unknown. `No Builds` ([:552](../../frontend/components/RepoGrid.tsx#L552)) is a genuine invariant badge and can go. |
| Four unexplained header indicators; `6 active` (six what?) | `confirmed` | |
| `Auto-scan off` is a label, not a control; packaging notice describes assessment | `unverified` | The pattern is real and the copy defect is specific enough to fix, but the exact string was not located; verification is step one of the task. |
| Accessibility: unnamed `⋯` menus and checkboxes, truncated aria-label, colour-only status, silent long scans | `confirmed` | Cheap, testable, and standards-relevant for a product that audits other repositories against declared standards. |
| A 47–60s scan with no cancel | `routed` | Already an open Release 3.2 milestone (*"make a cold full scan an explicit background job with progress and a cancel"*). Not rescheduled. |
| `"with 1 active contributors"` | `confirmed` | [ChangeHistoryPanel.tsx:236](../../frontend/components/ChangeHistoryPanel.tsx#L236) — plural hardcoded. |

---

## Corrections to the review's proposed plan

Three changes were made on the way into the roadmap. They are recorded here so the
next agent does not read the review and the roadmap as disagreeing by accident.

1. **"Commit the invariant suite red" is rejected as written.** This repo's `main`
   requires `ci-smoke` green with `enforce_admins` on, so a deliberately-red suite
   on `main` breaks the merge gate every other release depends on. The intent —
   *prove the bug before fixing it* — is kept, using the habit Release 3.1
   established instead: each gate lands **with** its fix and is proven non-vacuous
   by being run against the pre-fix host and failing there. A gate is finished when
   it has been shown to fail, not when it passes.
2. **The `Today` view is not scheduled as engineering.** It is a product decision,
   it duplicates Lane 0.5's open progressive-disclosure question, and the review
   itself gates it behind the metric work. It is routed to that lane as a decision.
3. **`trust-report.md` moves off the repo root** to `docs/reference/`, and its
   evidence lands in `evidence/` per this repo's layout. The content requirement —
   before and after values for every numbered finding — is unchanged.

---

## What was deliberately not scheduled

- Card-versus-table density, the ranked landing view, and the nine-button row:
  one design decision, owned by Lane 0.5. Scheduling it three times as engineering
  would not make the decision.
- Scan cancellation and progress: an open Release 3.2 milestone already.
- Dispatch idempotency: an open Release 3.1 non-blocker already. Release 3.5
  dedupes the **display**; it does not touch the queue writer.

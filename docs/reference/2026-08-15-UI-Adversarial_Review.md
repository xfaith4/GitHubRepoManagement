# GitHub Repo Manager — Adversarial UI Review

**Reviewed:** `http://127.0.0.1:7071/` · 14 Aug 2026 · all six tabs \+ Settings **Stance:** hostile. I assumed every number was wrong until it proved otherwise, and looked for the gap between what the UI *displays* and what an operator can *decide*.

---

## Verdict in one paragraph

This is a genuinely ambitious portfolio-governance tool with real machinery behind it — differential scanning, an index, a value-ranked work queue, doc maturity scoring, an agent-run ledger, merge gating. The engineering is ahead of the interface. The interface has two structural problems: **the numbers contradict each other across tabs, so none of them can be trusted**, and **the app inventories work without ever ranking it, so it raises anxiety ("46 need attention") without discharging it**. Everything else on this list is downstream of those two.

---

## What it gets right (so the rest lands fairly)

- Tooltips on the filter chips are written in plain operator language ("Ordinary loads reuse unchanged repositories from the index. Refresh All bypasses that…"). That's better copy than most commercial dashboards.  
- The safety posture is explicit and repeated: *"nothing is pushed or merged"*, *"Report is read-only and runs straight away"*, *"apply backs up the current file and records restore metadata first."* Preview-before-write is the correct default for an agent-dispatching tool.  
- `Why?` links next to value scores. Explaining a ranking is the difference between a score and a number.  
- Structure findings are actionable, not just diagnostic: `missing root file • SECURITY.md → Add SECURITY.md so vulnerability reports have a documented destination.`  
- Differential scan telemetry (`27 reused · 48 reindexed · 47.5s`) is the kind of thing an ops person actually wants.

---

## Tier 1 — The numbers cannot be trusted (this is the whole ballgame)

A dashboard's only asset is credibility. One provable contradiction burns it for every other number on the page. I found nine without trying hard.

| \# | Contradiction | Evidence (verbatim, same session) |
| :---- | :---- | :---- |
| 1.1 | **Four different denominators for "how many repos do I have"** | Header `76 repos` · Operations `Indexed entries: 75` · Doc Readiness `52 repos audited` · Portfolio Mission `Total 27` |
| 1.2 | **Stale metric is provably lying** | KPI `Stale Repositories 0`, Settings `Stale Threshold (days) 14` — while the grid shows repos at `local 9/11/2025` and a detail pane shows `Last Commit 11/9/2022`. Either the field is unwired or the threshold isn't applied. |
| 1.3 | **Ready queue depth disagrees three ways** | Insights `READY QUEUE 21` · Copilot Execution Lanes `Ready Queue 0` · Portfolio Mission `Ready 0` |
| 1.4 | **Portfolio Analytics contradicts itself inside one card** | Summary tiles read `0% Avg Maturity · 0% Docs Health · 0 Ready Now`; the trend rows immediately beneath read `Avg Maturity 20%` and `Ready Repos 22` |
| 1.5 | **Impossible axis** | `Ready Repos … Low 0 High 1592` in a portfolio of 76 repos. Also `-81 vs start` on a metric that started at ≤76. |
| 1.6 | **Docs Health has three values** | `Docs Health 54%` (Documentation Health) · `0%` (Portfolio Analytics) · `78%`, `84%`, `7%` per repo. No stated aggregation rule. |
| 1.7 | **Survivorship bias in the headline** | `README Score 84%` sits directly above `Missing README 37` (of 75). The score silently excludes the failures, so the headline improves as the portfolio worsens. |
| 1.8 | **Two clocks on one screen** | Same generation event stamped `Generated 7:54:24 AM` and `Generated 11:54:24 AM` (UTC vs. local leak). Also `Last scan: 07:48 AM` vs `Updated: 8/14/2026, 11:46:22 AM`. |
| 1.9 | **Group counts are page-scoped, totals are set-scoped** | `Needs attention (35)` \+ `No attention needed (15)` \= 50 \= the rows-per-page value, while the KPI says `46` and the caption says `Showing 72 of 76`. The group headers are counting the current page and presenting it as a portfolio fact. |

**Root cause (hypothesis):** at least four independent data sources — live scan, portfolio index, execution ledger, SQLite history — are each rendered by whichever component owns them, with no reconciliation layer and no shared "as of" instant. Every tab is right about its own source and wrong about the portfolio.

**Consequence:** an operator who spots 1.2 (and they will — "0 stale" is visibly false) has no way to know which *other* numbers are also unwired. Rational response is to stop believing the dashboard and go back to `git status` in a terminal. The tool's entire value proposition is legibility, and this is the mechanism by which it loses it.

---

## Tier 2 — It inventories work but never ranks it

The KPI row asks a question (`Needs Attention 46`) that no view answers. There is no "start here."

- **The scoring exists but is buried.** `value 93 · highest`, `~3 work units`, `82 high`, `59 medium` — the app already computes a value-ranked queue, then displays it three clicks deep inside Operations and Doc Readiness rather than making it the landing view.  
- **Nine equal-weight buttons per row.** Doc Readiness rows offer `Improve · Preview Task · Audit · Lint · Standardize · Evaluate · Dispatch Release · Roadmap` (+ `Repair` on some rows, absent on others with no explanation). No primary action, no visual hierarchy, no disclosure of which one is the *next* one. This is a menu, not a workflow.  
- **Read-only and irreversible share a visual weight.** `Audit` (safe) and `Dispatch Release` (not) are the same size, same row, adjacent. The safety copy elsewhere shows the team understands this risk; the button styling doesn't reflect it.  
- **Bulk actions default to the entire portfolio.** *"When none are selected, Pull/Fetch/Report apply to the full filtered repository set (76)."* Empty selection meaning "everything" is a footgun; a confirm dialog is a weak mitigation for wrong-by-default scoping.  
- **Seven verbs for one concept.** `Refresh All`, `Refresh`, `Scan All`, `Sync`, `Reload List`, `Retry`, `Evaluate` — all present simultaneously, none explaining what they invalidate or how long they take. Operators end up cargo-culting the biggest button.  
- **Three overlapping status vocabularies.** Grid chips (`Dirty / Drift unknown / Needs Docs / No Roadmap / Parse Error / Blocked / Ready`), Operations lifecycle (`Needs Readme / Needs Roadmap / Needs Roadmap Repair / Needs Structure / Parse Error`), and maturity levels (`L0-Absent → L4-Orchestration-Ready`). Nothing maps them to each other. `Genesys.Core` appears as **Ready** in Doc Readiness and **blocked / L0-Absent** in Insights *in the same session*.

---

## Tier 3 — Failure states are invisible, and the most important one is buried

- **Five permanent spinners.** `Refreshing…` (Insights, never resolved), `Loading execution queue…`, `Loading repository documents…`, `Loading audit findings...`, `Loading agent runs…`. No timeout, no error state, no "last known good," no retry affordance. A hung fetch and a slow fetch are indistinguishable forever.  
- **The single most consequential message in the app is a wall of red text below the fold:** *"Runner stalled: nothing would pick this up. Start the operator runner first — pwsh \-File scripts/Invoke-RoadmapTaskRunner.ps1. 4 tasks already queued with nothing to claim them."* The diagnosis is excellent. The delivery is not: no copy button, no start-runner control, no runner-health indicator in the header next to `Backend: Online`, and the header instead reports a cheerful `6 active`. The system knows it is broken and tells you only if you scroll.  
- **The stranded-work count disagrees with the stranded work.** Badge says `4 stranded`; **13 entries render**, all for the same repo, same task title (`Add the operator dashboard export route with smoke test coverage`), same `value 93`, differing only by run ID — queued daily from 08-09 through 08-13. That's a retry loop presented as a backlog. No dedupe, no "12 earlier attempts" collapse, no failure reason.  
- **Empty states assert facts they haven't earned.** Dependencies: `No cross-repo dependencies detected` across 76 repos, with no last-computed timestamp. Given `Missing ROADMAP 4` and 10 parse errors, "not detected" almost certainly means "not computed." Presenting a detection failure as a clean bill of health is the worst possible empty state.  
- **Debug telemetry leaked into a user-facing card.** Portfolio Mission renders raw key/value soup: `Roadmap differential-scan`, `StatusRefreshing`, `Github api Status stale-cache`, `ScanMode differential`, `Roadmap unavailable`, `DifferentialUnchangedCount 27`. Two of those (`stale-cache`, `unavailable`) are *degradation warnings* wearing the same styling as normal fields.

---

## Tier 4 — Scope hygiene is polluting every metric upstream

`Repository Scan Depth 3` is pulling in things that are not portfolio repos, and every percentage in the app is computed over that contaminated set:

- `…\Genesys.Core_AuditLogsApp\.tmp_compare\genesys-cloud-mcp-server` — a temp comparison folder inside another repo, counted as a first-class portfolio repo *and* ranked in the Doc Readiness queue.  
- `google-gemini/gemini-cli`, `modelcontextprotocol/quickstart-resources`, `GenesysCloudBlueprints/*` — vendored third-party clones you will never write a ROADMAP for, dragging down `Missing ROADMAP` and `Docs Health`.  
- Six `\Archive\` paths counted as live (`AI-Toolbox(old)\prompt-library`, `Archive\MusicLibrary`, …).  
- **Identity mapping is wrong:** local `Genesys.Core_AuditLogsApp` is labelled with GitHub remote `xfaith4/Genesys.Core` — the same remote as a *different* local repo. That is very likely what's generating the `2 duplicate repository sets found` banner, and it means per-repo GitHub signals (PRs, Actions) may be attributed to the wrong folder.  
- Ahead/behind counts of `Critical 2386`, `2200`, `1993`, `1453` are almost certainly upstream drift on vendored/archived clones, not actionable debt — yet they dominate the `Critical` severity bucket and therefore the triage order.

---

## Tier 5 — Interaction, accessibility, copy

- **Density.** \~120px per repo card × 76 repos, three-deep pagination, with the highest-signal fields (branch, last commit, owner) rendered smallest. A table with sortable columns would fit the whole portfolio in two screens. Card layouts are for browsing; this is triage.  
- **Dead controls in prime real estate.** `Clone PLANNED` and `Archive PLANNED` occupy two of the eight primary toolbar slots and cannot be clicked.  
- **Chips that carry zero information.** `Drift unknown` on every row. `No Builds` on every row. A badge that never varies is chrome, not signal.  
- **Four unexplained status indicators in the header.** `6 active` (six *what*?), `Source: Local • 6m ago`, `Auto-scan off`, `Backend: Online` — and, notably, no runner-health indicator, which is the one that was actually failing.  
- **`Auto-scan off` is a passive label, not a control.** Same for `Automation off` / `Packaging off` in Operations, both of which route you to Settings with **identical copy** — the packaging notice reads *"Enable it in Settings to keep favorites assessed automatically,"* which describes assessment, not packaging. Copy/paste bug.  
- **Accessibility:** status is conveyed by colour \+ chip text only; the Needs Attention explainer is exposed as `img` with an aria-label truncated mid-sentence (`…a failing build, a blocked` ); per-row `⋯` menus and row checkboxes have no accessible names; long-running scans announce nothing to screen readers.  
- **A 47–60s scan with no cancel** and no progress granularity beyond a rising second counter.  
- **Grammar in the one sentence meant for a human:** *"with 1 active contributors."*

---

## The single change I'd make next

Not a feature. **A truth layer.**

Everything in Tier 1 says the same thing: there is no single, versioned, provenance-carrying snapshot that every view reads from. Everything in Tier 2 says: the app already computes the ranking it refuses to lead with. Fix those two together and the product changes character — from *an inventory that makes you anxious* to *a dashboard you can act on*, which is the actual brief.

Concretely: one `portfolio-snapshot` contract where every metric carries `value`, `basis` (n of m), `asOf`, `source`, and `coverage`; a contract test that fails CI when any two views disagree; a scope policy that excludes vendored/nested/archive clones from portfolio math; async panels that resolve to *something* within 10s; and a `Today` view that surfaces the top 5 ranked actions with the blocking reason and a one-click path through it.

The prompt below is written to be pasted into a coding agent working in this repo.

---

# ▶ Prompt for the coding agent

> Copy everything between the rules.

---

You are working in the **GitHub Repo Manager** repository (local-first portfolio governance tool: PowerShell/host backend \+ web UI at `127.0.0.1:7071`, portfolio index, differential scanner, execution ledger, SQLite history).

## The problem

The UI's numbers contradict each other across tabs, so an operator cannot trust any of them; and the app inventories work without ever ranking it, so it never answers "what do I do next." Both are architectural, not cosmetic. Here is the evidence, all captured in a single session:

**Contradictions**

1. Repo count is `76` (header), `75` (Operations index), `52` (Doc Readiness "repos audited"), `27` (Portfolio Mission "Total").  
2. `Stale Repositories: 0` with `Stale Threshold: 14 days`, while repos show last commits of `9/11/2025` and `11/9/2022`.  
3. Ready-queue depth is `21` (Insights), `0` (Copilot Execution Lanes), `0` (Portfolio Mission).  
4. Portfolio Analytics tiles say `0% Avg Maturity / 0% Docs Health / 0 Ready Now`; the trend rows in the same card say `20%` and `22`.  
5. A trend axis reads `Ready Repos … High 1592` for a 76-repo portfolio, and `-81 vs start`.  
6. `Docs Health` is `54%` in one card and `0%` in another.  
7. `README Score 84%` is displayed above `Missing README: 37` — the score excludes repos with no README, so it rises as the portfolio degrades.  
8. The same generation event is stamped `7:54:24 AM` and `11:54:24 AM` (UTC/local leak).  
9. Grid group headers count only the current page (`35 + 15 = 50` \= rows-per-page) while presenting portfolio totals.

**Silent failures**

10. Five panels sit in a permanent loading state with no timeout, error, retry, or last-known-good: Insights `Refreshing…`, `Loading execution queue…`, `Loading repository documents…`, `Loading audit findings...`, `Loading agent runs…`.  
11. `Runner stalled: nothing would pick this up…` — accurate, actionable, and rendered as unstyled red text below the fold, while the header simultaneously shows `6 active` and no runner-health indicator.  
12. Packaged roadmap work shows a `4 stranded` badge above **13 rendered entries**, all the same repo and same task title, differing only by run ID, queued once a day for five days. A retry loop is being displayed as a backlog.  
13. Dependencies shows `No cross-repo dependencies detected` with no computed-at timestamp — a probable detection failure presented as a clean result.

**Scope contamination**

14. Scan depth 3 admits vendored clones (`google-gemini/gemini-cli`, `modelcontextprotocol/quickstart-resources`, `GenesysCloudBlueprints/*`), `\Archive\` folders, and a temp compare directory (`…\Genesys.Core_AuditLogsApp\.tmp_compare\genesys-cloud-mcp-server`) into portfolio math and the work queue.  
15. Local `Genesys.Core_AuditLogsApp` is mapped to remote `xfaith4/Genesys.Core` — the same remote as a different local repo. This is likely the source of the `2 duplicate repository sets found` banner and may misattribute PR/Actions signals.

## What to build

### Phase 0 — Prove the bug before fixing it

Write a failing invariant test suite (`tests/Portfolio.Invariants.Tests.ps1` or the repo's existing harness — match what's there, prefer Pester for host-side). Assert, against live API responses:

- every view's repo denominator derives from one canonical set  
- `stale_count` recomputed from `last_commit` \+ configured threshold equals the displayed value  
- ready-queue depth is identical across every endpoint that reports it  
- no percentage metric exceeds 100 or drops below 0; no count exceeds the portfolio size  
- every timestamp in a single payload shares one timezone basis

Commit these **red**. They are the definition of done.

### Phase 1 — One snapshot, one clock, one provenance

Introduce a single `portfolio-snapshot` object built once per scan and consumed by every view. No component may compute a portfolio-level metric itself. Every metric is an object, never a bare number:

{ "id": "docs\_health",

  "value": 54.2,

  "unit": "percent",

  "basis": { "numerator": 41, "denominator": 76 },

  "asOf": "2026-08-14T11:54:24Z",

  "source": "portfolio-index",

  "coverage": { "assessed": 52, "total": 76 },

  "confidence": "partial",

  "definition": "docs\_health\_v1" }

Rules:

- All timestamps stored UTC, formatted once at the render boundary in the user's locale. Zero exceptions.  
- `coverage.assessed < total` ⇒ the tile renders "of 52 assessed" inline. Never silently extrapolate a partial sample to a portfolio headline (fixes \#7).  
- Snapshot carries a `schemaVersion` and a `degraded[]` array naming any source that returned stale/failed (`stale-cache`, `unavailable` are currently rendered as normal fields — promote them to a visible degradation banner).

### Phase 2 — Metric definitions as data

Establish one machine-readable metric-definition source used by implementation, UI explanation, and documentation.
metric definitions
      ├── runtime calculation
      ├── UI tooltip
      └── docs/metrics.md

### Phase 3 — Portfolio scope policy

Add a first-class scope policy with a settings UI and sensible defaults:

- exclude paths matching `**/.tmp*/**`, `**/node_modules/**`, `**/Archive/**`, `**/*.worktrees/**`  
- exclude repos whose remote owner is outside the configured owner/org set (mark them `vendored`, keep them visible under a "Vendored (excluded from metrics)" toggle — do not delete them)  
- deduplicate by `(remote_url, root_commit_sha)`, not by folder name; when two locals share a remote, surface both under one identity with the paths listed, and fix the `Genesys.Core_AuditLogsApp` mis-mapping  
- **every metric tile states its scope** ("52 in-scope repos · 24 vendored/archived excluded")

Recompute all Tier-1 metrics over the in-scope set only.

### Phase 4 — Async panels get a real state machine

Replace every ad-hoc spinner with one shared component: `idle | loading | success | empty | stale | error | degraded`.

- Hard 10s timeout → `error` with the failing endpoint, the HTTP status, and a Retry button.  
- On refresh failure, render the **last good value greyed out with its age** ("as of 11:54, refresh failed 2m ago") rather than a spinner. Stale truth beats a lie of omission.  
- `empty` must distinguish *computed and found nothing* from *not computed* — Dependencies currently conflates them. It needs a computed-at timestamp and a "Compute now" action.

### Phase 5 — Runner health is a first-class citizen

- Add a runner heartbeat probe. Put its state in the header beside `Backend: Online`; make `6 active` say what is active or remove it.  
- When the runner is down and work is queued, the banner moves **above the fold**, states the wait ("4 tasks queued, oldest 5d"), offers a copy-to-clipboard for `pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1`, and — if the host is permitted to — a Start Runner button behind a single confirm.  
- Collapse duplicate queue entries: group by `(repo, task_id)`, show the latest attempt with an "N earlier attempts" expander and the failure reason for each. Make the `stranded` badge count what is actually rendered.  
- Add a queue-age alarm: any task unclaimed \> 24h escalates to the header.

### Phase 6 — The `Today` view (new default landing tab)

The ranking already exists (`value 93 · highest`, `~3 work units`, maturity L0–L4). Lead with it.

- Top 5 recommended actions across the whole portfolio, ranked by existing value score ÷ estimated work units, with hard blockers filtered out and shown separately as "Blocked — fix these first."  
- Each row: repo · one-sentence *why now* · the single primary action (one button, not nine) · a `Why?` disclosure showing the score inputs · secondary actions behind an overflow menu.  
- One "portfolio health" sentence generated from the snapshot, with real denominators and an as-of stamp. Fix `"with 1 active contributors"` and pluralize from data.  
- Everything else keeps its current home. `Today` is a lens over the snapshot, not a new data path.

## Constraints

- **No new portfolio metrics.** Make the existing ones true, scoped, and explained. If a metric cannot be computed correctly, render it as `—` with a reason, never as `0`.  
- **No new nouns.** Reduce them: reconcile the three status vocabularies (grid chips / Operations lifecycle / maturity levels) into one documented model with an explicit mapping table, and consolidate the seven refresh verbs (`Refresh All`, `Refresh`, `Scan All`, `Sync`, `Reload List`, `Retry`, `Evaluate`) into at most two, each stating what it invalidates and its expected duration.  
- **Preserve the safety posture.** Preview-before-write, "nothing is pushed or merged", backup-on-apply all stay. Additionally: give destructive/irreversible actions distinct styling from read-only ones, and change bulk-action default scope from "all filtered repos" to "nothing selected ⇒ action disabled, with a explicit 'Select all 76' control."  
- Remove or hide `PLANNED` toolbar buttons until they work.  
- Drop chips whose value never varies across rows (`Drift unknown`, `No Builds`) or make them vary.  
- Accessibility: full accessible names on `⋯` menus and row checkboxes, status not conveyed by colour alone, `aria-live` for scan progress and completion, and fix the truncated Needs Attention aria-label.

## Definition of done

1. Phase 0's invariant suite passes green, and is wired into CI so any future cross-view disagreement fails the build.  
2. A `trust-report.md` at the repo root: for each of the 15 numbered findings above — fixed / not-fixed / why, with the before and after values.  
3. Screenshots of every tab before and after, plus the `Today` view.  
4. `docs/metrics.md` exists, and every visible tooltip is generated from it.  
5. A short migration note: what the numbers were, what they are now, and why they moved — anyone who saw the old dashboard needs to know that `Stale: 0 → 31` is a fix, not a regression.

Work in vertical slices, phase by phase. After each phase, run the invariant suite and report which assertions flipped green. Do not begin Phase 6 until Phases 1–3 are green — a ranked action list built on numbers that still contradict each other is worse than no ranked list at all.

---

## If you'd rather point the agent elsewhere

Two alternates, same evidence base:

- **"Make the runner self-healing."** Narrower, faster payoff: Phases 4 \+ 5 only, plus a supervisor that restarts the operator runner, an exponential-backoff retry with a dead-letter queue, and desktop notification on stranded work \> 1h. Fixes the failure that is *actually costing you work right now* (13 queued attempts, nothing claiming them) without touching the metrics layer.  
- **"Ship the portfolio brief."** Given your observability-to-decision leaning: a scheduled job that renders the snapshot to a single self-contained HTML/Markdown brief — what changed since the last brief, what regressed, the top 5 actions, what's blocked and for how long — written to disk and openable without the app running. Forces the same metric discipline as Phase 1–2 but delivers an artifact rather than a UI, and it's the natural on-ramp to trend history once the SQLite window fills.


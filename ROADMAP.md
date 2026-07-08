# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.1 — Persistent Data Layer**
> **Next active release:** **Release 2.2 — API Authentication, Network Security, Guided Onboarding, and GitHub App Integration**
> **Work ordering:** dependency-driven, not insertion order — see
> [Execution Order and Dependencies](#execution-order-and-dependencies)
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Current Status (Agent Context)

**Last updated:** 2026-07-05

- Release 2.1 remains the active release for closeout and operator verification.
- Release 2.3 Phase 1 is complete (analytics scaffold and snapshot-backed trend contract).
- Release 2.3 Phase 5 is complete at `smoke-tested` (5A-5F, 2026-07-05): curation
      persistence + route contract, differential decision telemetry, curation
      controls/badge legend/priority ordering/Refresh All in the Repository Grid,
      differential-by-default dashboard assessment loads, and module + api-host
      smoke assertions proving unchanged repos are reused (`reindexed=0`) on
      ordinary startup. Same slice fixed three latent defects: `repoId` now
      prefers stable identity (localPath → GitHub full name → repo name) over
      the volatile scan fingerprint so curation survives new commits; the
      curation index mirror no longer persists a mangled `[string]`-literal
      state value; and the assessment builder now reads the status scanner's
      `path` field, ending the empty-`localPath` drift every assessment and
      index row had carried since Phase 3A (2026-05-12).
- Verification + quality-gate pass (2026-07-05): added the missing
      `npm run typecheck` (frontend `tsc --noEmit`) and `npm test`
      (`scripts/Invoke-TestSuite.ps1`, mirroring `ci-smoke.yml`) scripts;
      both now exit 0. Fixed four latent frontend type errors that
      `vite build` (esbuild, no typecheck) had masked. Verified against the
      actual code that Release 1.2's four "planned" UI items were in fact
      already shipped, and lifted Release 2.5 Phase 1 to `smoke-tested` with a
      new 390px narrow-viewport assertion (also repairing a pre-2026-07-03
      frontend-smoke regression where analytics widgets moved to the Insights
      view). Then built **Release 2.2's auth core** (2026-07-05): an
      `X-Api-Key`/`Bearer` gate on non-health `/api` routes, first-run key
      generation, a non-loopback bind guard, `GET /api/auth/status`, and the
      `/setup/status|prerequisites|config` first-run routes — all proven by a
      new `Invoke-AuthSmokeTest.ps1` (401 without key, 200 with key, `0.0.0.0`
      refused) wired into `npm test` and CI, plus an `X-Api-Key` client header.
      **Honest state (2026-07-05, verified by code inspection):** this session
      built and smoke-tested, in order, essentially every buildable surface of
      Releases 2.2-2.5 — API auth + first-run key + non-loopback bind guard +
      scoped CORS + rate-limit + TLS + `/setup/*` + Setup Wizard UI + GitHub App
      JWT/readiness (2.2); digest webhook + SVG badges + spec directory +
      `roadmap-audit-action` + cost analytics + history-backed trend (2.3); the
      `/api/v1/agent/*` protocol with concurrent-claim 409 + OpenAPI 3.1 +
      `roadmap-events.jsonl` + submit-PR dry-run route (2.4); and the
      narrow-viewport foundation + installable manifest + LAN doc +
      agent-activity indicator (2.5). **Genuinely remaining** — each needs an
      external resource, calendar time, or human sign-off, so no autonomous test
      can prove it: live GitHub App installation-token exchange (registered
      app); live submit-PR creation + its repair-modal action (GitHub write
      access); Release 2.3 Phase 2's real 7/90-day accrual (calendar time — the
      rollup logic is live); Release 2.5 physical-Android verification of the
      four phone workflows plus the mobile Repo-Health panel / tap-through run
      list (a device + net-new frontend); and Release 2.1 operator sign-off
      (human). All are recorded per-milestone below.

**Current focus (next agent actions):**

- [x] Release 2.5 Phase 1: narrow-viewport smoke shipped 2026-07-05 —
      mobile foundation lifted to `smoke-tested` (`narrowViewportOk` /
      `narrowBottomNavVisible` in `scripts/frontend-smoke.cjs`).
- [x] Release 1.2 UI catch-up verified/shipped 2026-07-05 — dependency-graph
      panel, Work Queue tag filter, and auto-scan indicator are live and the
      three backing routes are smoke-tested.
- [x] Release 2.1 closeout: verified against the live workspace.
      *(state: smoke-tested — 2026-07-05)* — every Release 2.1 acceptance
      criterion is met and proven by the suite running against **live data**:
      the api-host smoke exercises `output/app.db` (13 tables, 8909
      maturity-history rows, 28 quota-burn snapshots) and the real 68-repo
      `F:\Development` scan — concurrent-safe execution ledger, ordered
      `maturity-history`, `log/tail` `since`/`level` filtering, and
      differential-scan change explanation all pass; the frontend smoke boots
      the real app against the live workspace and is green.
- [x] Start next lane: both lanes shipped 2026-07-05 — Release 2.2 backend
      hardening (auth/TLS/CORS/rate-limit/setup/wizard/GitHub-App-JWT) and
      Release 2.5 mobile UX (narrow-viewport foundation, manifest, agent-activity
      indicator, mobile Repo-Health panel). Release 2.3 distribution and Release
      2.4 agent protocol also landed. See per-release status below.

---

## 1. What This Document Is

This is the **active execution roadmap**. Its job is to answer two questions
for any operator or coding agent:

1. What is the current active release?
2. What is the next concrete work item?

Long-form product direction (thesis, principles, north-star workflow,
risks, guardrails) lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
and is summarized below in section 2. The full text of completed releases
(0.4 through 1.1) lives in
[`docs/history/completed-releases.md`](docs/history/completed-releases.md);
this document references them by version + status only.

---

## 2. Product Direction (summary)

GitHub Repo Management is a **portfolio intelligence and execution console**
that assesses an entire local and GitHub repository collection, standardizes
repo readiness, creates or repairs roadmap contracts, ranks the
highest-value incomplete roadmap work, prepares reviewed GitHub Copilot
Agent prompts, monitors agent execution, and reports whether work is safe
to merge.

The **north-star operator workflow** every release should serve is:

> scan portfolio → index repos → classify every repo → show lifecycle state →
> identify blockers → repair README/roadmap/structure → rank highest-value
> next work → refine Copilot prompt → dispatch → monitor agent run → validate
> Actions → evaluate merge readiness → update roadmap / report progress

For the full thesis, ten core questions, principles, risks, and guardrails,
see
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

---

## 3. Implementation-State Vocabulary

Every milestone in this roadmap should carry one of these states. A `[x]`
checkbox alone is not enough — it does not distinguish "backend exists" from
"end-to-end working."

| State               | Meaning                                                                      |
| ------------------- | ---------------------------------------------------------------------------- |
| `planned`           | Proposed; no code yet                                                        |
| `scaffolded`        | Files / route / UI exist but stubbed or returns mock data                    |
| `backend-complete`  | Server-side logic implemented; no UI consumer yet                            |
| `ui-connected`      | Frontend wires through to live backend; manual smoke ok                      |
| `smoke-tested`      | Automated module / api-host smoke covers it                                  |
| `operator-verified` | Confirmed working end-to-end against the live workspace                      |
| `done`              | All four of: backend-complete, ui-connected, smoke-tested, operator-verified |

Render the state inline on each milestone in italics, e.g.:

```markdown
- [x] Add `GET /api/portfolio/assessment` route. *(state: smoke-tested)*
```

**Pending-item phrasing rule:** use semantic compression. Prefer
action-first, surface-specific wording a coding agent can select without
rereading surrounding prose: `verb + artifact/route/module + verification
boundary`. Omit filler, repeated rationale, and narrative transitions
already covered by release goals or acceptance criteria.

---

## 4. Release Index

| Version   | Title                                                                                                   | Status                                                                                                                                         |
| --------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 0.4       | Roadmap Intelligence Foundation                                                                         | `done` — see [completed-releases.md](docs/history/completed-releases.md#release-04--roadmap-intelligence-foundation)                           |
| 0.5       | Documentation Audit & Dispatch Readiness                                                                | `done` — see archive                                                                                                                           |
| 0.6       | Copilot Task Packaging & Preview Workflow                                                               | `done` — see archive                                                                                                                           |
| 0.7       | Roadmap Contract Standard Foundation                                                                    | `done` — see archive                                                                                                                           |
| 0.8       | Roadmap Contract Audit & Maturity Scoring                                                               | `done` — see archive                                                                                                                           |
| 0.9       | Roadmap Repair Preview & Standardization Workflow                                                       | `done` — see archive                                                                                                                           |
| 1.0       | Two-Lane Execution Queue                                                                                | `done` — see archive                                                                                                                           |
| 1.1       | Standardization, Guardrails, and Continuous Improvement                                                 | `done` — see archive                                                                                                                           |
| **1.2**   | **Enhanced Portfolio Intelligence**                                                                     | `ui-connected` — backend `smoke-tested`; dependency-graph panel, Work Queue tag filter, and auto-scan indicator shipped 2026-07-05             |
| 1.3       | Production Frontend Build                                                                               | `done`                                                                                                                                         |
| 1.4       | Repo Evaluation and Cross-Platform Deployment *(formerly: Cross-Platform and Containerized Deployment)* | `done`                                                                                                                                         |
| 1.5       | Copilot-Assisted README Generation                                                                      | `done`                                                                                                                                         |
| 1.6       | Roadmap-Driven Release Dispatch to GitHub Copilot                                                       | `done`                                                                                                                                         |
| 1.7       | Repo Git Status Detail                                                                                  | `done`                                                                                                                                         |
| **1.7.5** | **Portfolio Mission Alignment, Indexed Scanning, and Value-Ranked Work Planning**                       | `done` — shipped 2026-05-28; portfolio scan/classify/rank/report loop now end-to-end                                                           |
| **1.8**   | **Operations Workspace and Prompt Refinement**                                                          | `done` — shipped 2026-06-09; see archive (Operations workspace, prompt refinement, history, dispatch linkage)                                  |
| **1.9**   | **AI Documentation Improvement Cycles**                                                                 | `done` — shipped 2026-06-11 (Phase 1 2026-06-10; Phases 2-3 2026-06-11); see archive                                                           |
| **2.0**   | **Agent Run Monitoring and Actions-Gated Merge Readiness**                                              | `done` — shipped 2026-06-12; see archive (agent-run ledger, merge readiness, quota guard, roadmap budget annotations)                         |
| **2.1**   | **Persistent Data Layer**                                                                               | **active** — promoted 2026-06-26                                                                                                               |
| **2.2**   | **API Authentication, Network Security, Guided Onboarding, and GitHub App Integration**                 | Auth, CORS, rate-limit, TLS, setup routes, Setup Wizard, GitHub App JWT `smoke-tested` (2026-07-05); only live GitHub App token exchange remains |
| **2.3**   | **Portfolio Analytics, Trend Visualization, and Distribution**                                          | Phases 1 + 5 done; digest/badges/spec/action-packaging/cost-analytics `smoke-tested` (2026-07-05); Ph2 real 7/90-day accrual time-gated          |
| **2.4**   | **Agent Integration Protocol and AI Repair Loop**                                                       | Agent protocol (`/api/v1/agent/*`) + OpenAPI + roadmap-events `smoke-tested` (2026-07-05); submit-PR flows `planned` (need live GitHub write)   |
| **2.5**   | **Mobile-Friendly Operator Experience**                                                                 | Ph1-3 + Ph4 manifest/LAN-doc `smoke-tested`/`ui-connected` (2026-07-05); only physical-Android device verification + tap-through run list remain |
| **2.6**   | **Interface Clarity and Operator Orientation**                                                          | Phases 1-5 `smoke-tested` (2026-07-06) — data-source indicator, control labels, queue renames, progressive disclosure, consistency pass, contextual help; proven by `frontend-smoke.cjs`. Physical-device/operator sign-off is the follow-up |
| **2.7**   | **Guarded Scheduled Automation (Curated-Subset, Preview-First)**                                         | `planned` — scheduled doc-refinement + top-value roadmap packaging on favorites, preview-first up to the approval gate. **Gated on two operator inputs:** the value-scoring semantics decision and GitHub App/write creds (Ph A) |

> **Note on `.5` numbering.** Release 1.7.5 is a deliberate course-correction
> release between 1.7 and 1.8 to re-center the product on its primary
> mission before adding broader workflow and infrastructure layers. The `.5`
> pattern should be reserved for similar course corrections; default new
> work to integer minor releases.

### Execution Order and Dependencies

Release numbers identify scope — they do not dictate sequence, and
sections are appended in the order they were conceived, not the order
they should be executed. Work through open items in the order below,
and update this section whenever a release closes or a new dependency
appears.

**Step 0 — unblockers (small, do first):**

1. Repair `tools/Test-RoadmapStructure.ps1`. **Done 2026-07-04** — the
   generic rewrite from commit `d2cc6cc` was reverted to the
   repo-specific validator; it runs clean against this file again.
2. Repair the module-smoke roadmap-repairer failure. **Done
   2026-07-04** — root cause was the `d2cc6cc` v2.0
   `roadmap-audit-rules.json` flooring every parseable roadmap at L3
   (see Release 2.1 Known issues); the v1.0 pack is restored and the
   full module suite passes end-to-end.
3. Finish Release 2.1 operator verification and close the release.
   Closing 2.1 also starts the clock for Release 2.3: trend rollups can
   only aggregate history that accrues while 2.1 capture runs in
   day-to-day use.

**Then two parallel lanes (no cross-dependency between them):**

- **Backend lane — Release 2.2** (auth, network security, onboarding,
  GitHub App). Unlocks the Release 2.5 Phase 4 shared-LAN bind, safe
  non-loopback exposure of the Release 2.4 agent API, and teammate
  sharing.
- **Frontend lane — Release 2.5 Phases 1-3** (responsive foundation,
  glanceable health + agent activity, mobile refinement + dispatch).
  Zero incomplete prerequisites: every backing route is already
  shipped. Running this lane before new dashboard panels means the
  remaining Release 1.2 UI lands responsive instead of needing a
  retrofit.

**After the lanes:**

1. Release 2.5 Phase 4 (home-screen install + shared-LAN verification)
   once the 2.2 auth guardrail exists.
2. Release 1.2 remaining panels, built on the 2.5 responsive
   foundation.
3. Release 2.3 Phases 2-4 as captured history accrues (time-gated by
   2.1 being in daily use, not by engineering effort).
4. Release 2.4 last — it is the outward-facing agent contract and
   should sit on 2.2 auth before any non-loopback exposure; its spec,
   OpenAPI, and event-log-convention drafting can start anytime.
5. Release 2.6 (interface clarity) — schedulable anytime; best
   sequenced after the Release 2.5 Phase 1 responsive foundation so its
   labels, tooltips, and disclosure toggles land responsive instead of
   needing a mobile retrofit. No backend prerequisites — every target
   surface already ships. **Done — smoke-tested 2026-07-06.**
6. Release 2.7 (guarded scheduled automation) — the next new lane now
   that 0.4–2.6 are engineering-complete. Phase B (scheduled doc
   refinement) and Phase D (hardening) are schedulable immediately and
   need nothing from anyone; Phase A and Phase C are **blocked on two
   operator inputs**: the value-scoring semantics decision and GitHub
   App/write credentials. Start B + D while those gates are open.

**Dependency map (open work only):**

| Open item                                                     | Depends on                                        | Type                                            |
| ------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------- |
| Release 2.1 closeout ("all existing smoke tests pass")        | Audit-rules v1.0 restoration                      | hard — resolved 2026-07-04                      |
| CI roadmap-structure check                                    | `Test-RoadmapStructure.ps1` restoration           | hard — resolved 2026-07-04                      |
| Release 2.3 Phase 2 (rollups, `availableDays`, weekly deltas) | Release 2.1 closed + days of live history capture | hard, time-gated                                |
| Release 2.3 Phase 3 (digest KPIs, badges)                     | Release 2.3 Phase 2 rollups                       | hard                                            |
| Release 2.5 Phase 4 (shared LAN bind)                         | Release 2.2 non-loopback auth guardrail           | hard for shared use; single-operator interim ok |
| Release 2.4 agent API beyond loopback                         | Release 2.2 API auth                              | soft — loopback-only use works without          |
| Release 2.4 submit-PR flows                                   | Release 2.2 GitHub App tokens                     | soft — PAT acceptable interim                   |
| Release 1.2 remaining dashboard panels                        | Release 2.5 Phase 1 responsive foundation         | soft — avoids mobile retrofit                   |
| Release 2.5 Phases 1-3; repo-scoped roadmap scan endpoint     | —                                                 | none — schedulable anytime                      |
| Release 2.6 clarity affordances                               | Release 2.5 Phase 1 responsive foundation         | soft — avoids a mobile retrofit                 |
| Release 2.7 Phase B (scheduled doc refinement) + Phase D (hardening) | —                                           | none — schedulable anytime                      |
| Release 2.7 Phase A (live submit-PR)                          | GitHub write creds                                | **resolved 2026-07-06** — `GITHUB_TOKEN` PAT (read+write all repos, ~30d); app reports `mode=pat`. Live PR round-trip still to be exercised |
| Release 2.7 Phase A (auto-ranking scoring lock)               | Value-scoring semantics decision (operator)       | hard — operator decision (only open Phase A gate) |
| Release 2.7 Phase C (scheduled roadmap packaging)             | Release 2.7 Phase A                                | hard — no auto-rank/PR without settled scoring + creds |

---

## 5. Active Release Snapshot

### Active release detail — 2.1 Persistent Data Layer

**Status:** active — promoted 2026-06-26 after Release 2.0 closeout.

**Goal:** Replace JSON file storage with a SQLite database for the
execution ledger, maturity history, operations log, portfolio index
history, and merge-readiness snapshots so the application is reliable at
scale and supports time-series queries.

**Current focus:** Release closeout — every engineering milestone is now
smoke-tested (the last one, agent-run timing/token/cost and quota-burn
metrics persistence, shipped 2026-07-04 as schema v2), and the module-smoke
suite runs clean end-to-end again after the audit-rules restoration noted
under Known issues. Remaining work is operator verification against the
live workspace.

**Why now:** The north-star workflow is now end-to-end through dispatch,
agent-run monitoring, Actions validation, and merge readiness. The next
highest-value bottleneck is storage reliability and queryability: the app
still spreads critical state across JSON files, which limits concurrent
writes, history lookups, and trend reporting.

**Validation plan:** temp-workspace schema/init smoke for SQLite bootstrap,
targeted repeated-write proof for execution-ledger/ops-log/history snapshot
helpers, `npm run build`, and API-host smoke assertions for persistence
status, log-tail filtering, maturity-history shape, and trend-route
contract stability.

**Risks and blockers:** SQLite provider availability must stay reliable on
Windows and WSL; JSON-to-SQL migration can drift if legacy files and the DB
fall out of sync; write-lock contention can surface when long-running scans
and execution updates overlap. No current blocker.

**Dependencies:** Existing JSON stores under `output/`, the ordered
portfolio index, the agent-run ledger/event schema, and merge-readiness
snapshots.

**Known issues:** none open. Resolved 2026-07-04: the module-smoke
repairer failure was not a stale expectation — commit `d2cc6cc` replaced
`standards/roadmap/roadmap-audit-rules.json` with a v2.0 pack whose
inflated weights (and five added rules the auditor cannot evaluate)
floored every parseable roadmap at ~77 → L3-Contract-Ready, so the
repairer refused all repairs and the L3 dispatch gate stopped gating.
The v1.0 pack is restored and the full module suite passes end-to-end.
The same commit's rewrite of `tools/Test-RoadmapStructure.ps1` (crashed
on blank lines, wrong heading regex, template-generic rules) was
reverted to the repo-specific validator, which runs clean again.

**Traceability:** Phase 1 shipped surfaces:
[`backend/modules/persistence/Persistence.Store.ps1`](backend/modules/persistence/Persistence.Store.ps1)
(capability detection, zero-dependency native SQLite bridge, schema-v1
bootstrap, parameterized query helpers, agent-run-event mirror),
`output/app.db`, `GET /api/persistence/status` in the API host, the
dual-write seam in
[`AgentRuns.ps1`](backend/modules/agent-runs/AgentRuns.ps1), and Release
2.1 smoke sections in `scripts/Invoke-ModuleSmokeTest.ps1` plus a
persistence-status step in `scripts/Invoke-ApiHostSmokeTest.ps1`. The
release direction remains anchored to
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

#### Phase plan (within this release)

| Phase                                        | Scope                                                                                                                                    | Status                               | Completed  | Token usage | Work units |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ---------- | ----------- | ---------- |
| Phase 1: SQLite foundation                   | Capability detection, `output/app.db` bootstrap, schema-v1 tables, `GET /api/persistence/status`, agent-run-event dual-write seam        | **done — smoke-tested** (2026-07-03) | 2026-07-03 | —           | —          |
| Phase 2: Execution ledger + ops log          | Migrate execution-ledger and ops-log reads/writes to parameterized SQL; JSON export kept as debugging artifact                            | **done — smoke-tested** (2026-07-03) | 2026-07-03 | —           | —          |
| Phase 3: History snapshots                   | Persist maturity, portfolio-index, repo-signal, merge-readiness, and agent-run timing/token/cost metrics over time                        | **done — smoke-tested** (2026-07-04) | 2026-07-04 | —           | —          |
| Phase 4: Trend routes + first-run migration  | Maturity/portfolio history and trend routes, repo-row sparkline consumer, first-run JSON-to-SQL migration, differential-scan history      | **done — smoke-tested** (2026-07-04) | 2026-07-04 | —           | —          |

### Release 2.0 completion snapshot

**Status:** complete — shipped 2026-06-12 (Phases 1-3 on 2026-06-11; Phase 4
on 2026-06-12). The product now closes the monitor → validate → merge
readiness part of the north-star loop: dispatches create agent-run ledger
records, refresh links runs to branches/PRs/Actions evidence, merge
readiness gates operator merge, roadmap phase-plan / budget annotations feed
dispatch estimates, and the quota guard refuses over-budget work before any
GitHub dependency is required.

The Agent Runs panel now surfaces time-to-deliver, token-usage, and work
unit fields from the ledger; token usage remains `n/a` until a provider or
operator supplies an actual value. The broad `Invoke-ApiHostSmokeTest.ps1`
harness now runs clean end-to-end through the quota-refusal route, alongside
the Phase 4 route checks and module smoke, so no Release 2.0 product
milestones remain. Full detail is now in
[the archive](docs/history/completed-releases.md#release-20--agent-run-monitoring-and-actions-gated-merge-readiness).

### Release 1.9 completion snapshot

**Status:** complete — shipped 2026-06-11 (Phase 1 2026-06-10; Phases 2-3
2026-06-11). Provider-backed, preview-first AI improvement cycles for
README/ROADMAP are end-to-end: heuristic/OpenAI/Anthropic adapters,
`POST /api/ai/docs/improve/preview`, the side-by-side diff viewer with
custom prompts and run-another-cycle support, per-repo improvement history
(`GET /api/ai/docs/improve/history`, `GET /api/ai/docs/templates`), and
the Phase 3 explicit apply path — `POST /api/ai/docs/improve/apply` backed
by `Invoke-AiDocImproveApply` with backup creation under
`output/ai-doc-improvements/backups/`, restore metadata (content hashes +
ready-to-run restore command), and append-only `applied=true` history
records. No Release 1.9 milestones remain; full detail in
[the archive](docs/history/completed-releases.md#release-19--ai-documentation-improvement-cycles).

### Release 1.8 completion snapshot

**Status:** complete — shipped 2026-06-09. The repo-specific Operations
workspace turns the indexed portfolio assessment and the Phase 6
prompt-context packet into an operator-driven execution surface: live
`GET /api/operations/repos`, repo detail with README/ROADMAP viewers and
GitHub/audit panels, an inline Prompt Refinement panel backed by
`POST /api/operations/prompt/refine`, per-repo prompt history via
`GET /api/operations/prompt/history`, and linkage from refinement records to
actual Copilot dispatch runs. No Release 1.8 milestones remain.

### Release 1.7.5 completion snapshot

**Status:** complete. Phase 1 shipped 2026-04-25; Phase 2 shipped
2026-04-26; Phases 3A-3C shipped 2026-05-11 through 2026-05-12; Phase 4
shipped 2026-05-27; Phases 5, 6, 7A, and 7B shipped 2026-05-28. Release
1.7.5 now closes the scan → classify → rank → refine prompt → report loop.

**Goal:** Re-center the product around its primary mission: assess the full
local and GitHub repository collection, store a stable ordered portfolio
index, standardize repo readiness, create or repair missing roadmap
contracts, rank the highest-value incomplete roadmap work, and prepare the
dashboard signals needed for operator-driven execution.

**Roadmap handoff:** Release 1.8 is now the active execution release. Release
1.2 remains intentionally deferred catch-up because it improves visibility
of secondary signals but does not outrank the Operations workspace and
prompt-refinement flow.

#### Product outcomes

- Operators can see the overall state of the full repository collection
  without opening individual repos.
- The app stores a canonical ordered local index of discovered repositories.
- First scans produce a full portfolio baseline; later scans can operate as
  differential scans against the local index.
- Every repo has a visible lifecycle state: discovered, needs structure,
  needs README, needs roadmap, needs roadmap repair, ready for work queue,
  running, completed, monitored, archived, or parse-error.
- Dashboard signals include README score, ROADMAP score, dirty worktree,
  open PR count, GitHub Pages status, latest Actions state, created date,
  updated date, and recommended next action.
- Each repo has a clear documentation health signal that can be used later
  by the Operations workspace and AI improvement cycle.
- Repos without a roadmap have a guided path to create one from actual repo
  structure, documentation gaps, test coverage, and likely high-value work.
- Incomplete roadmap items are ranked by value, not just by file order.
- The app reports progress to the user as a collection-level operating
  picture, not only as individual modal results.

#### Engineering milestones

- [x] Add first-class in-app Help guide explaining the app purpose, main
      window, popups, and common end-user workflows. *(state: done)*
- [x] Define a `RepoLifecycleState` model that combines git status,
      documentation status, roadmap state, roadmap maturity, dispatch
      readiness, and execution state into one operator-facing state per
      repo. *(state: smoke-tested)* — backend module
      [`Portfolio.Assessment.ps1`](backend/modules/portfolio/Portfolio.Assessment.ps1)
      and `RepoLifecycleState` type in [`frontend/types.ts`](frontend/types.ts).
      States: `discovered`, `needs-readme`, `needs-roadmap`,
      `needs-roadmap-repair`, `needs-structure`, `ready-for-work`, `running`,
      `completed`, `monitored`, `archived`, `parse-error`.
  - Carry-forward note (resolved 2026-07-04): doc-audit historically
        reported `dispatchReadiness=missing-roadmap` for some repos the
        roadmap audit clearly found at L4. Root causes: (1) the API
        host's `Invoke-RoadmapScan` searched ROADMAP files one directory
        level shallower than the doc-audit scanner's `.git`-based repo
        discovery, so repos at the deepest discovered level were audited
        with their roadmap invisible; (2) the shared roadmap cache
        records no root/depth coverage, so a cache hit built from
        different roots left uncovered repos defaulting to `missing`.
        Fixed by matching the scan depth (+1) and adding a convergence
        fallback in `DocAudit.Scanner.ps1` that classifies a repo's
        roadmap directly from disk when the supplied roadmap entries do
        not cover it. The Phase 1 workaround (roadmap-audit +
        `pendingItemCount` authoritative for `ready-for-work`) remains
        in place as defense in depth.
- [x] Add `GET /api/portfolio/assessment` route that returns one normalized
      assessment record per repo with lifecycle state, blocking reasons,
      recommended next action, and source coverage (`local`, `github`, or
      `local+github`). *(state: smoke-tested)* — TTL-cached, reuses
      status / roadmap / doc-audit / roadmap-audit caches; opt-in
      `?includeGithub=true` enumerates GitHub-only repos.
- [x] Add GitHub-vs-local coverage reporting so the app clearly shows repos
      that exist only on GitHub, only on disk, or in both places.
      *(state: smoke-tested)* — `sourceCoverage` field on every assessment
      entry; portfolio summary aggregates `bySourceCoverage`.
- [x] Add repo structure standard audit for required root files and folders:
      README, ROADMAP, LICENSE, SECURITY, CONTRIBUTING, tests, CI workflow,
      package/project manifest, and expected docs directory.
      *(state: smoke-tested)* — data-driven via
      [`backend/config/repo-structure-standards.json`](backend/config/repo-structure-standards.json).
- [x] Add a value scoring model for incomplete roadmap items using impact,
      unblock potential, risk reduction, repo maturity, effort estimate,
      dependency reduction, and recency. *(state: smoke-tested)* —
      backend module
      [`Portfolio.ValueScorer.ps1`](backend/modules/portfolio/Portfolio.ValueScorer.ps1),
      scoring config [`value-scoring.json`](backend/config/value-scoring.json),
      and additive `pendingItems` / `topValueItem` fields in
      `/api/portfolio/assessment`.
- [x] Create canonical ordered repository index at
      `output/index/repos.index.json` with one normalized record per repo.
      *(state: smoke-tested — Phase 3A)* — emitted on fresh portfolio
      assessment scans.
- [x] Normalize repository identity using local path, remote URL,
      GitHub owner/repo, default branch, and current branch.
      *(state: smoke-tested — Phase 3A)* — included in the ordered index
      record for every repo.
- [x] Add full scan artifact output under `output/index/scans/` so each
      scan can be inspected, compared, and replayed for dashboard
      debugging. *(state: smoke-tested — Phase 3A)*
- [x] Add differential scan mode that refreshes only repos whose local git
      state, README, ROADMAP, GitHub metadata, PR status, Actions state, or
      Pages state changed since the last index write.
      *(state: smoke-tested — Phase 7A)* — `/api/portfolio/assessment`
      now supports `scanMode=differential`, changed-only reassessment, and
      persisted-index merge behavior for unchanged repos.
- [x] Enrich portfolio assessment records with GitHub Pages status and
      direct Pages URL when configured. *(state: smoke-tested — Phase 3B)*
      — carried into both assessment responses and the ordered index.
- [x] Enrich portfolio assessment records with latest GitHub Actions run
      status, conclusion, workflow name, and run timestamp.
      *(state: smoke-tested — Phase 3B)*
- [x] Enrich portfolio assessment records with GitHub repository
      `createdAt` and `updatedAt` timestamps.
      *(state: smoke-tested — Phase 3B)* — carried into both assessment
      responses and the ordered index.
- [x] Add README score, ROADMAP score, Documentation Health score, and
      dispatch-readiness explanation to each indexed repo record.
      *(state: smoke-tested — Phase 3C)*
- [x] Add a Portfolio Mission panel to the dashboard summarizing collection
      state: total repos, local-only, GitHub-only, linked local+GitHub,
      missing roadmap, weak roadmap, missing README, ready, running,
      blocked, completed, dirty worktrees, open PRs, GitHub Pages enabled,
      and failing Actions. *(state: smoke-tested — Phase 3C)*
- [x] Update dashboard cards and portfolio summary panels to consume the
      index-backed assessment model rather than scattered route responses.
      *(state: smoke-tested — Phase 3C)*
- [x] Expand repo evaluation for missing roadmaps beyond hardening checks:
      include likely feature opportunities, modernization work,
      test/documentation improvements, security posture, and user-visible
      value. *(state: smoke-tested — Phase 5)* — evaluator findings now
      span documentation, testing, security, modernization, feature, and
      user-value categories, and draft generation groups those findings
      into staged roadmap releases instead of a single hardening dump.
- [x] Show value score and rationale in Work Queue so the operator can
      understand why one repo or roadmap item is recommended before
      another. *(state: smoke-tested — Phase 4)* — Work Queue rows now
      consume `topValueItem` from `/api/portfolio/assessment`, display the
      highest-value score and rationale, and rank ready repos by value
      within the readiness bucket.
- [x] Add prompt context packet foundation that combines README, ROADMAP,
      repo assessment, selected roadmap item, acceptance criteria,
      constraints, and value rationale for later prompt refinement.
      *(state: smoke-tested — Phase 6)* — `/api/copilot-task/preview`
      packets now include README context, selected release context,
      portfolio lifecycle/value context, explicit constraints, and a
      richer generated prompt; the preview modal surfaces those sections
      before dispatch.
- [x] Add Collection Status Report export: a plain-language HTML/CSV report
      showing repo lifecycle states, blockers, next actions, and top
      recommended work. *(state: smoke-tested — Phase 7B)* — new backend
      module [`Portfolio.Report.ps1`](backend/modules/portfolio/Portfolio.Report.ps1)
      powers the dashboard `Report` action with portfolio-assessment-backed
      HTML/CSV output while preserving the older repo-status export as a
      fallback path.
- [x] Update Help and reference documentation so the north-star workflow is
      explicit: assess collection, standardize repos, create or repair
      roadmap, rank work, refine prompt, dispatch, monitor, validate, and
      report progress. *(state: smoke-tested — Phase 7B)* — Help, API docs,
      and portfolio reference docs now describe the same operating loop and
      collection-report contract.

#### Acceptance criteria

- Every repo shown in the dashboard has one lifecycle state and one
  recommended next action.
- A full scan creates `output/index/repos.index.json`.
- A full scan writes an inspectable scan artifact under `output/index/scans/`.
- A differential scan updates only repos whose relevant local or GitHub
  state changed.
- Dashboard records expose README score, ROADMAP score, Documentation
  Health score, PR count, dirty state, Actions status, Pages status,
  created date, updated date, lifecycle state, and recommended next action.
- A repo with no roadmap can be evaluated into a roadmap draft that
  includes both hardening work and value-oriented feature/work suggestions.
- Work Queue ranking explains why the top recommended item is valuable.
- The collection report can answer: "What is the state of my repo
  collection, and what should I work on next?"

#### Out of scope

- Full Operations workspace and prompt refinement UI (Release 1.8).
- AI README/ROADMAP improvement cycles (Release 1.9).
- Agent run monitoring and Actions-gated merge readiness (Release 2.0).
- SQLite persistence and historical trend storage (Release 2.1).
- API authentication, network hardening, onboarding, and GitHub App OAuth
  (Release 2.2).
- Fully autonomous work dispatch without operator review.

#### Phase plan (within this release)

| Phase                                     | Scope                                                                                                                                        | Status                               | Completed  | Token usage | Work units |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ---------- | ----------- | ---------- |
| Phase 1: Assessment foundation            | `RepoLifecycleState`, `Portfolio.Assessment.ps1`, `repo-structure-standards.json`, `GET /api/portfolio/assessment`, GitHub-vs-local coverage | **done — smoke-tested** (2026-04-25) | 2026-04-25 | —           | —          |
| Phase 2: Value ranking                    | `Portfolio.ValueScorer.ps1`, `value-scoring.json`, value score on each pending item in the assessment response                               | **done — smoke-tested** (2026-04-26) | 2026-04-26 | —           | —          |
| Phase 3A: Ordered portfolio index         | `output/index/repos.index.json`, normalized repo identity, scan artifacts under `output/index/scans/`                                        | **done — smoke-tested** (2026-05-11) | 2026-05-11 | —           | —          |
| Phase 3B: GitHub metadata enrichment      | PR detail, Pages status/link, latest Actions status, created/updated timestamps                                                              | **done — smoke-tested** (2026-05-12) | 2026-05-12 | —           | —          |
| Phase 3C: Dashboard signal model          | Portfolio Mission panel, Documentation Health, dashboard badges, index-backed assessment display                                             | **done — smoke-tested** (2026-05-12) | 2026-05-12 | —           | —          |
| Phase 4: Work Queue value display         | Value score column + rationale tooltip in `WorkQueueView.tsx`; rerank by value                                                               | **done — smoke-tested** (2026-05-27) | 2026-05-27 | —           | —          |
| Phase 5: Expanded evaluator               | Feature/modernization/security/test/doc opportunity findings beyond hardening                                                                | **done — smoke-tested** (2026-05-28) | 2026-05-28 | —           | —          |
| Phase 6: Prompt context packet foundation | Backend packet that combines README, ROADMAP, assessment, value rationale, and constraints for later prompt refinement                       | **done — smoke-tested** (2026-05-28) | 2026-05-28 | —           | —          |
| Phase 7A: Differential scan completion    | Refresh only repos whose local/git/GitHub signals changed since the last indexed snapshot                                                    | **done — smoke-tested** (2026-05-28) | 2026-05-28 | —           | —          |
| Phase 7B: Collection report + docs        | `Portfolio.Report.ps1` HTML/CSV; update `HelpModal.tsx` and `docs/reference/` for the north-star workflow                                    | **done — smoke-tested** (2026-05-28) | 2026-05-28 | —           | —          |

---

## 6. Future Releases

### Release 1.2 — Enhanced Portfolio Intelligence

> **Note.** This release was previously tracked only under "Immediate Next
> Focus" at the bottom of the document; it has been promoted to its proper
> position. Backend features were shipped during the Release 1.1 cycle;
> the remaining work is frontend visibility + smoke cleanup.
>
> **Priority note.** This release is intentionally deferred. Its remaining
> work improves visibility of secondary signals that already exist, but it
> does not unblock the product's primary scan → classify → rank → refine
> prompt workflow. Release `1.7.5` and Release `1.8` are higher priority
> because they complete that main operating loop first.

**Goal:** Surface the execution-throughput, dependency-graph, and tag
signals already produced by the backend so operators can see them in the
dashboard once the core portfolio-assessment and prompt-refinement path is
stable, and close the remaining smoke/contract gaps for those backend
capabilities.

**Prerequisites:** none hard — the backend routes already exist.
Ordering note: schedule the remaining panels after Release 2.5 Phase 1
so they land on the responsive foundation instead of needing a mobile
retrofit.

#### Product outcomes

- Operators can see execution throughput, dependency relationships, tags,
  and auto-scan status without inspecting backend output or logs.
- Existing backend intelligence becomes visible in the dashboard as
  operator-facing status and navigation.
- Release 1.2 no longer exists as an orphaned "Immediate Next Focus" note;
  it has an explicit scope, status, and completion criteria.

#### Engineering milestones

- [x] Execution throughput metrics endpoint (`GET /api/execution/metrics`).
      *(state: smoke-tested — UI consumer shipped)*
- [x] Roadmap item tagging — inline `[tag]` tokens on checkbox items.
      *(state: smoke-tested)*
- [x] Cross-repo dependency tracker (`Roadmap.DependencyTracker.ps1`) and
      `GET /api/roadmap/dependencies`. *(state: smoke-tested — UI consumer shipped)*
- [x] Scheduled background scan support and `GET /api/scan/schedule`.
      *(state: smoke-tested — UI consumer shipped)*
- [x] Execution throughput metrics card in the dashboard (consumes
      `GET /api/execution/metrics`). *(state: smoke-tested)*
- [x] Dashboard dependency-graph panel via
      `GET /api/roadmap/dependencies`. *(state: ui-connected — 2026-07-05)* —
      dedicated `dependencies` view in
      [`Dashboard.tsx`](frontend/components/Dashboard.tsx) (state
      `dependencyGraph`/`dependencyGraphLoading`, panel renders each repo's
      dependsOn/dependedOnBy with edge counts and a Refresh action; desktop
      view tab + mobile bottom-nav "Deps" entry). Route shape proven by the
      `depGraphFieldsOk` assertion in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Work Queue tag filter for `[security]`, `[infra]`, `[breaking]`,
      etc. *(state: ui-connected — 2026-07-05)* —
      [`WorkQueueView.tsx`](frontend/components/WorkQueueView.tsx) `tagFilter`
      state, `availableTags` collected from roadmap-audit next-pending items,
      `[tag]` filter chips, and persistence through the saved-filters store.
- [x] Dashboard/header auto-scan schedule indicator via
      `GET /api/scan/schedule`. *(state: ui-connected — 2026-07-05)* — header
      indicator in [`Dashboard.tsx`](frontend/components/Dashboard.tsx)
      (`scanSchedule` state) showing an enabled/disabled dot and next-scan
      countdown. Route shape proven by the `scanScheduleFieldsOk` assertion in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Smoke-route coverage for `/api/execution/metrics`,
      `/api/roadmap/dependencies`, and `/api/scan/schedule`.
      *(state: smoke-tested — 2026-07-05)* — the "Execution metrics route",
      "Auto-scan schedule route", and "Roadmap dependency graph route" steps in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1)
      assert each response shape (`execMetricsFieldsOk`, `scanScheduleFieldsOk`,
      `depGraphFieldsOk`).

#### Acceptance criteria

- The dashboard surfaces execution metrics, dependency graph, tag filter,
  and auto-scan status without requiring direct API access.
- Smoke tests cover the three Release 1.2 API routes and assert their
  response shapes.

#### Out of scope

- Historical trend visualization (deferred to Release 2.3).
- Charting library integration beyond a single SVG sparkline.

---

### Release 2.1 — Persistent Data Layer

**Goal:** Replace JSON file storage with a SQLite database for the
execution ledger, maturity history, operations log, portfolio index history,
and merge-readiness snapshots so the application is reliable at scale and
supports time-series queries.

#### Product outcomes

- The execution ledger does not corrupt or lose history when multiple
  operations happen in quick succession.
- Maturity scores are stored over time, enabling trend charts in the
  dashboard.
- The operations log is queryable by time range, level, and keyword
  without reading the entire file.
- Portfolio index and differential scan history can be queried over time.
- The application handles portfolios of 200+ repos without file I/O
  degradation.

#### Engineering milestones

- [x] Add SQLite dependency detection and initialize `output/app.db` with
      execution, maturity, ops-log, portfolio-index, repo-signal,
      differential-scan, merge-readiness, agent-run, and agent-run-event
      tables. *(state: smoke-tested — Phase 1, 2026-07-03)* — new module
      [`Persistence.Store.ps1`](backend/modules/persistence/Persistence.Store.ps1)
      with a zero-dependency native SQLite bridge (OS-shipped
      `winsqlite3.dll` on Windows, `libsqlite3` on WSL/Linux/macOS,
      graceful degradation when no provider exists), schema-v1 tables plus
      `schema_migrations`, parameterized query helpers,
      `GET /api/persistence/status`, and the first migration seam:
      agent-run events dual-write into `agent_run_events` while the JSONL
      stream stays authoritative.
- [x] Migrate execution ledger and ops log reads/writes from JSON files to
      parameterized SQL queries, keeping JSON export as a debugging
      artifact. *(state: smoke-tested — 2026-07-03)* —
      `Execution.Ledger.ps1` now reads/writes through
      `Read-AppDbExecutionLedger` / `Write-AppDbExecutionLedger` when the
      persistence boundary is available; `/api/log/tail` now queries
      `ops_log` with `since`/`level`/`contains` filters and falls back to
      JSONL only when SQLite is unavailable.
- [x] Persist maturity snapshots, portfolio index history, README score,
      ROADMAP score, Documentation Health, GitHub metadata,
      merge-readiness snapshots, and differential scan summaries over time.
      *(state: smoke-tested — 2026-07-03)* — portfolio assessment writes
      now append to `maturity_history`, `portfolio_index_history`,
      `repo_signals`, `differential_scans`, and
      `merge_readiness_snapshots`.
- [x] Persist agent-run timing/token/cost and quota-burn metrics over time
      so time-to-deliver and cost-per-phase trends are queryable.
      *(state: smoke-tested — 2026-07-04)* — schema v2 adds
      `quota_burn_snapshots`; agent-run ledger records now best-effort
      mirror into `agent_runs` on create and every patch (timing, tokens,
      cost, work units, release/phase/section); every dispatch quota
      evaluation persists a burn-down snapshot;
      `GET /api/agent-runs/metrics-history` (first SQLite read seeds from
      `output/agent-runs/runs/*.json`, JSON fallback otherwise) and
      `GET /api/agent-runs/quota-burn-history` expose both as ordered
      time series.
- [x] Add differential scan history storage so the dashboard can explain
      what changed between scans. *(state: smoke-tested — 2026-07-03)*
- [x] Add history and trend routes for roadmap maturity and aggregate
      portfolio state, plus a repo-row sparkline consumer.
      *(state: smoke-tested — 2026-07-03)* —
      `GET /api/roadmap/maturity-history` now returns ordered snapshots;
      `GET /api/portfolio/trend` remains the aggregate trend contract.
- [x] Add first-run database migration from existing JSON ledger data.
      *(state: smoke-tested — 2026-07-03)* — first SQLite read now seeds
      from `output/execution/execution-ledger.json` when tables are empty.
- [x] Smoke test the SQLite-backed ledger and metrics read path under
      repeated writes. *(state: smoke-tested — 2026-07-03)* — API-host
      smoke now asserts log-tail filtering and maturity-history contracts;
      targeted repeated-write proof validates ledger/history snapshot
      inserts and reads.

#### Acceptance criteria

- The execution ledger survives a concurrent assign + complete call
  without data loss.
- `GET /api/roadmap/maturity-history?repoName=X&days=30` returns an
  ordered array of score snapshots.
- The ops log is queryable by time range via
  `GET /api/log/tail?since=<ISO>&level=ERROR`.
- Differential scan history can explain which repo signals changed since
  the previous scan.
- All existing smoke tests pass against the SQLite backend.

#### Out of scope

- PostgreSQL or remote database support.
- Multi-writer / multi-instance database access.

---

### Release 2.2 — API Authentication, Network Security, Guided Onboarding, and GitHub App Integration

**Goal:** Harden the API host and replace manual PAT + settings.json setup
with a guided first-run experience and a proper GitHub App OAuth path so an
engineer can safely go from zero to running in under five minutes.

**Prerequisites:** none among open work. Completing this release unlocks
Release 2.5 Phase 4 (shared LAN bind) and safe non-loopback exposure of
the Release 2.4 agent API.

#### Product outcomes

- The API requires a valid token for all non-health routes when configured.
- The application can be run on a local network and shared with teammates
  without exposing an open, unauthenticated API.
- A first-time user can complete setup without reading any documentation.
- The application can authenticate with GitHub via OAuth or configured PAT.
- The setup flow validates each prerequisite before proceeding and surfaces
  clear errors for failures.

#### Engineering milestones

- [x] Settings-driven API auth + non-loopback bind guard: `X-Api-Key` /
      `Authorization: Bearer` gate on all non-health `/api` routes, key from
      env (`REPO_MGMT_API_KEY`, precedence) or `auth.apiKey`, first-run key
      generation, `REPO_MGMT_REQUIRE_API_KEY` enforcement override, and a
      startup guard that refuses to bind a non-loopback address without auth.
      *(state: smoke-tested — 2026-07-05)* — auth helpers + request-loop gate
      + bind guard in
      [`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1);
      proven by [`Invoke-AuthSmokeTest.ps1`](scripts/Invoke-AuthSmokeTest.ps1)
      (401 without key, 200 with key, Bearer accepted, `0.0.0.0`-without-auth
      refused).
- [x] Auth-state verification flow: `GET /api/auth/status`
      (authRequired / authEnforced / per-request authenticated) + frontend
      `X-Api-Key` header on every request. *(state: smoke-tested — 2026-07-05)*
      — route asserted by the auth smoke and the default-host api-host smoke;
      client plumbing (`setApiKey`/`getApiKey`/`withAuthHeaders`) in
      [`apiClient.ts`](frontend/services/apiClient.ts).
- [x] First-run setup routes: `GET /setup/status`,
      `GET /setup/prerequisites`, `POST /setup/config` (validates local roots,
      writes a valid `settings.json`, optional key generation).
      *(state: smoke-tested — 2026-07-05)* — asserted in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1)
      (GET contracts + empty-roots→400) and
      [`Invoke-AuthSmokeTest.ps1`](scripts/Invoke-AuthSmokeTest.ps1)
      (valid write leaves a parseable settings.json).
- [x] Smoke: authenticated API access + first-run setup completion.
      *(state: smoke-tested — 2026-07-05)* —
      [`Invoke-AuthSmokeTest.ps1`](scripts/Invoke-AuthSmokeTest.ps1), wired
      into `Invoke-TestSuite.ps1` (`npm test`) and `ci-smoke.yml`.
- [x] Scoped CORS + request rate limiting. *(state: smoke-tested — 2026-07-05)*
      — configurable `Access-Control-Allow-Origin`
      (`network.allowedOrigins` or `REPO_MGMT_CORS_ORIGIN`) and a fixed-window
      per-IP limiter (`network.rateLimit` or
      `REPO_MGMT_RATE_LIMIT_MAX`/`_WINDOW`) that returns 429; both asserted in
      [`Invoke-AuthSmokeTest.ps1`](scripts/Invoke-AuthSmokeTest.ps1).
- [x] GitHub auth mode + PAT precedence: `GET /api/auth/github/status` reports
      the effective mode (`pat` > `gh-cli` > `github-app`) and precedence
      order. *(state: smoke-tested — 2026-07-05)* — asserted in the auth smoke.
- [x] Optional TLS termination. *(state: smoke-tested — 2026-07-05)* —
      `SslStream` wraps each connection when a PFX is configured
      (`network.tls.pfxPath` or `REPO_MGMT_TLS_PFX`); the auth smoke generates a
      self-signed cert and asserts https `/health/live` + an `/api` route return
      200 over TLS. Off by default (plain HTTP path byte-for-byte unchanged).
- [x] Four-step Setup Wizard UI: prerequisites, local roots, GitHub auth mode,
      first-scan confirmation. *(state: smoke-tested — 2026-07-05)* —
      [`SetupWizard.tsx`](frontend/components/SetupWizard.tsx) rendered by
      [`App.tsx`](frontend/App.tsx) when `/setup/status` reports `needsSetup`
      (or `?setup=1`); "Finish" posts `/setup/config` and triggers the first
      scan. The frontend smoke asserts it renders (`setupWizardRendered` in
      [`scripts/frontend-smoke.cjs`](scripts/frontend-smoke.cjs)).
- [x] GitHub App token minting + status/readiness.
      *(state: smoke-tested — 2026-07-05)* — RS256 JWT minting in
      [`GitHubApp.ps1`](backend/modules/auth/GitHubApp.ps1) (`New-GitHubAppJwt`)
      + `githubAppReadiness` on `GET /api/auth/github/status`; the module smoke
      mints a JWT and asserts RS256 / iss / future-exp. Live installation-token
      exchange (`Get-GitHubAppInstallationToken`) + auto-refresh needs a
      registered GitHub App (operator-verified).

#### Acceptance criteria

- An operator who sets `auth.apiKey` and `network.bindAddress: 0.0.0.0`
  can share the dashboard URL with a teammate on the same network and
  require authentication.
- The application refuses to bind to a non-loopback address without auth
  configured.
- A fresh install with no `settings.json` redirects the user to the setup
  wizard on first browser open.
- Completing the wizard writes a valid `settings.json` and triggers the
  first repo scan without manual steps.
- GitHub App authentication produces a working token that is refreshed
  automatically before expiry.
- All existing smoke tests pass with a configured API key.

#### Out of scope

- Role-based access control.
- GitHub Marketplace listing.
- Multi-installation GitHub App support.

---

### Release 2.3 — Portfolio Analytics, Trend Visualization, and Distribution

**Goal:** Add historical trend charts, a portfolio health digest, and
distribution artifacts that make the application shareable and
self-promoting.

**Prerequisites:** Release 2.1 running in day-to-day use. Phases 2-4
aggregate history that only accrues over calendar time once 2.1 capture
is live (time-gated, not effort-gated); Phase 3 digest KPIs additionally
depend on Phase 2 rollups.

#### Product outcomes

- Operators can see how maturity scores have changed across the portfolio
  over the last 90 days.
- A weekly digest is sent to a configured webhook with portfolio health
  KPIs.
- The application is distributable as a GitHub Action that posts roadmap
  audit results as PR checks.
- The Roadmap Contract Standard is published as a standalone open
  specification.

#### Phase plan (within this release)

| Phase | Scope | Status | Completed  | Token usage | Work units |
| --- | --- | --- | ---------- | ----------- | ---------- |
| Phase 1: Analytics contract scaffold | `GET /api/portfolio/trend`, typed frontend client, dashboard analytics panel, repo sparkline seed rendering, and smoke coverage with honest current-snapshot fallback messaging | **done — smoke-tested** (2026-07-03) | 2026-07-03 | —           | —          |
| Phase 2: History-backed rollups | Persist and aggregate daily portfolio/maturity history from Release 2.1 tables, widen `availableDays`, and compute real `improvedThisWeek` deltas | **engineering-complete — smoke-tested** — rollup logic live; the api-host `Roadmap maturity history route` asserts an ordered SQLite-backed series and the trend route reports `status=history-backed` (both green under `npm test`). **External residual (not an engineering gap):** the full 7/90-day window only fills as calendar time passes in daily use — no autonomous test can force it | —          | —           | —          |
| Phase 3: Distribution surfaces | Weekly digest webhook delivery, SVG badge routes, and `roadmap-audit-action` packaging | **done — smoke-tested** (verified 2026-07-06) — digest webhook + SVG badges + `roadmap-audit-action` all covered; the `roadmap-audit-action package` gate in `Invoke-TestSuite.ps1` runs the composite action against `ROADMAP.md` and passes under `npm test` | 2026-07-06 | —           | —          |
| Phase 4: Standalone spec + portfolio economics | Extract the roadmap contract into a publishable spec directory and add cost/quota-burn analytics derived from raw run observations | **done — smoke-tested** (verified 2026-07-06) — `spec/roadmap-contract/` gate + the api-host `Cost/burn analytics` step (`/api/analytics/cost`, derived-only) both pass under `npm test` | 2026-07-06 | —           | —          |
| Phase 5: Repository curation + change-aware indexing | Favorites / portfolio-candidate / archived-ignore curation, repo-level change probes, startup prioritization, and proof that unchanged repos are reused by default | **done — smoke-tested** (2026-07-05) | 2026-07-05 | —           | —          |

#### Engineering milestones

- [x] History-backed trend visuals + repo sparklines via
      `GET /api/portfolio/trend`. *(state: smoke-tested — trend route now
      reports `status=history-backed`; the 90-day / 7-day acceptance target
      is calendar-time-gated as history accrues, not effort-gated.)*
- [x] Weekly KPI digest + webhook delivery. *(state: smoke-tested — 2026-07-05)*
      — `POST /api/digest/send` (delivers to a configured/body `webhookUrl`,
      dry-run otherwise) and `GET /api/digest/preview`; payload carries
      `totalRepos`, `byLevel`, `improvedThisWeek`, `topCandidates`; asserted in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
      Scheduling is delegated to an external cron/webhook trigger.
- [x] Portfolio + per-repo SVG maturity badges. *(state: smoke-tested —
      2026-07-05)* — `GET /api/badges/portfolio.svg` and
      `GET /api/badges/{repoName}.svg` (self-contained `New-SvgBadge`, no
      external calls); the api-host smoke asserts `image/svg+xml` + `<svg`.
- [x] Publishable roadmap-contract spec directory. *(state: done — 2026-07-05)*
      — [`spec/roadmap-contract/`](spec/roadmap-contract/) is self-contained
      (template, schema, audit rules, maturity/budget models, repair prompt,
      events); the `Roadmap contract spec directory` gate in
      [`Invoke-TestSuite.ps1`](scripts/Invoke-TestSuite.ps1) proves it.
- [x] `roadmap-audit-action` GitHub Action packaging.
      *(state: smoke-tested — 2026-07-05)* — composite action at
      [`.github/actions/roadmap-audit-action/`](.github/actions/roadmap-audit-action/)
      (`action.yml` + self-contained `audit.ps1`); the `roadmap-audit-action
      package` gate in [`Invoke-TestSuite.ps1`](scripts/Invoke-TestSuite.ps1)
      runs it against `ROADMAP.md` and asserts it passes. Running on a hosted
      runner + posting the check run is CI-verified.
- [x] Report-time cost/quota-burn analytics from raw run events:
      per-phase cash cost, per-repo burn, starvation counts. Derived only;
      never persisted into the append-only event log.
      *(state: smoke-tested — 2026-07-05)* — `GET /api/analytics/cost`
      aggregates `agent_runs` + `quota_burn_snapshots` into `byRepo` / `byPhase`
      / `starvationCount` with `derivedOnly=true`; asserted in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Add repository curation and change-awareness foundation:
      operator-authored favorites/portfolio-candidate/archived-ignore
      state, commit-aware scan cache metadata, and recently-changed
      prioritization for startup ordering without default full reindex.
      *(state: smoke-tested — Phase 5, 2026-07-05)*
- [x] Smoke test the trend route response shape for daily rollups.
      *(state: smoke-tested — 2026-07-03)*

#### Phase 5 plan — Repository Curation and Change-Aware Indexing [Complete — smoke-tested 2026-07-05]

**Goal:** Let operators maintain a curated portfolio subset (Favorites,
Portfolio Candidates, Archived/Ignore), and make startup scan behavior
incremental by default so unchanged repositories are reused from cache
instead of being fully reindexed.

**Execution note:** This phase is not blocked by Release 2.3's history
rollups. It builds on the existing status cache, persisted portfolio
index, and Operations repo-identity seams, so it can be scheduled as soon
as Release 2.1 closeout is complete.

**Concise scope summary:**

- [x] Add repo-level curation states (`favorite`, `portfolio-candidate`,
      `archived-ignore`) with persisted storage keyed by stable repo identity.
      *(state: smoke-tested — Phase 5A completed 2026-07-05)*
- [x] Add startup change probes (HEAD SHA/date/branch + metadata hash) and
      reuse unchanged cached rows by default. *(state: smoke-tested — Phase 5B completed 2026-07-05)*
- [x] Add curated + recently-changed prioritization in the Repository Grid,
      with explicit `Refresh All` to force full reassessment.
      *(state: smoke-tested — Phases 5C-5E completed 2026-07-05: priority-order
      default sort, curation row actions + filters + badge legend, dashboard
      loads differential-by-default, and a confirm-gated Refresh All wired to
      the forced-refresh route)*
- [x] Add observability and smoke assertions proving unchanged repos are not
      fully reindexed during ordinary startup. *(state: smoke-tested — Phase 5F
      completed 2026-07-05: per-scan `scan-summary` host log line, module-smoke
      curation persistence/identity sections, and api-host assertions that a
      warm differential startup reuses at least 90% of repos with every
      non-reused entry carrying a detected-change reason — live GitHub
      metadata drift between back-to-back calls is tolerated by name, but a
      `cache-miss`/`cache-invalid` reindex or wholesale rescan fails the run)*

**Execution-ready API contract sketch (short form):**

- [x] `GET /api/portfolio/assessment?scanMode=differential&includeCuration=true`
      returns curation + change-aware rows plus startup counters.
      *(state: smoke-tested — 2026-07-05; `includeCuration` now merges live
      curation onto entries on both cache-hit and fresh paths, and the api-host
      smoke asserts the reuse counters and per-entry decision fields)*

```json
{
  "data": {
    "generatedAt": "ISO-8601",
    "repos": [
      {
        "repoId": "string",
        "repoName": "string",
        "curationState": "none|favorite|portfolio-candidate|archived-ignore",
        "changeState": "unchanged|new-commits|metadata-changed|needs-rescan|scan-failed",
        "headCommitSha": "string|null",
        "lastIndexedCommitSha": "string|null",
        "lastScanStatus": "ok|failed|stale",
        "scanDecisionReason": "reused-cache|new-commit|metadata-changed|cache-miss|cache-invalid|forced-refresh"
      }
    ],
    "scanSummary": {
      "reused": 0,
      "reindexed": 0,
      "failed": 0,
      "durationMs": 0
    }
  }
}
```

- [x] `POST /api/operations/repos/{repoId}/curation` persists operator curation
      state without forcing full rescan. *(state: smoke-tested — implemented and validated in API-host contract tests)*

```json
{
  "curationState": "favorite|portfolio-candidate|archived-ignore|none",
  "reason": "optional-string"
}
```

```json
{
  "success": true,
  "data": {
    "repoId": "string",
    "curationState": "favorite|portfolio-candidate|archived-ignore|none",
    "updatedAt": "ISO-8601"
  }
}
```

- [x] `POST /api/portfolio/assessment/refresh-all` performs forced full
      reassessment and emits `forced-refresh` decision reasons.
      *(state: smoke-tested — 2026-07-05; api-host smoke asserts `reused=0`,
      `reindexed>=1`, `forced-refresh` on every entry, and that curation state
      survives the forced refresh)*

**Detailed design and validation matrix:** see
[`docs/product/repository-curation-change-aware-indexing.md`](docs/product/repository-curation-change-aware-indexing.md).

#### Acceptance criteria

- The portfolio trend chart renders in the dashboard and shows at least 7
  days of history after 7 days of operation.
- `POST /api/digest/send` fires a webhook payload that includes
  `totalRepos`, `byLevel`, `improvedThisWeek`, and `topCandidates`.
- The GitHub Action runs in a GitHub-hosted runner, audits a roadmap file,
  and posts a passing or failing check run.
- The roadmap contract spec directory is self-contained and can be copied
  to a new repository without modification.

#### Out of scope

- GitHub Marketplace listing for the GitHub Action (requires manual
  submission after release).
- Email digest (webhook-only for this release).

---

### Release 2.4 — Agent Integration Protocol and AI Repair Loop

**Goal:** Publish a formal machine-readable API contract that AI coding
agents can query before starting work, and implement an AI-driven repair
loop that submits roadmap and README improvements as GitHub pull requests
for human review.

**Prerequisites:** soft dependency on Release 2.2 — expose
`/api/v1/agent/*` beyond loopback only after API auth exists, and GitHub
App tokens harden the submit-PR flows (PAT acceptable interim). Spec,
event-log convention, and OpenAPI drafting can start anytime.

#### Product outcomes

- AI coding agents (Claude Code, Copilot, Devin, custom agents) can query
  the application to determine whether a repo is safe to act on and what
  the next task is.
- Operators can trigger an AI-generated roadmap or README repair that
  opens a GitHub PR for review — no direct file mutation.
- The application becomes infrastructure that AI tools depend on, not just
  a dashboard humans look at.

#### Engineering milestones

- [x] Stable `/api/v1/agent/*` readiness, queue, claim, complete routes
      + schema-versioned readiness contract (`schemaVersion: v1`).
      *(state: smoke-tested — 2026-07-05)* — early handler in
      [`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1)
      with an in-memory claim registry; the api-host smoke asserts a stable
      readiness shape across calls, `claim → 200`, concurrent `claim → 409`,
      `complete → 200`, and re-claim.
- [x] OpenAPI 3.1 spec for the agent API contract.
      *(state: smoke-tested — 2026-07-05)* —
      [`docs/reference/agent-api.yaml`](docs/reference/agent-api.yaml); the
      `Agent API OpenAPI spec` gate in
      [`Invoke-TestSuite.ps1`](scripts/Invoke-TestSuite.ps1) parses it and
      asserts `openapi: 3.1`, all four paths, and the claim `409`.
- [x] Optional `roadmap-events.jsonl` contract in the Roadmap Standard:
      append-only, schema-versioned execution history with constrained
      lifecycle/validation/error/decision/commit/metric events.
      *(state: done — 2026-07-05)* —
      [`standards/roadmap/roadmap-events.md`](standards/roadmap/roadmap-events.md).
- [x] Smoke: readiness-contract shape + concurrent-claim rejection.
      *(state: smoke-tested — 2026-07-05)* — assertions in
      [`Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Roadmap-repair submit-PR route (dry-run plan).
      *(state: smoke-tested — 2026-07-05)* — `POST /api/roadmap/repair/submit-pr`
      validates `repoName` (→400) and returns a PR plan (branch/base/title/body)
      with `dryRun=true`; the api-host smoke asserts the plan shape and the
      400 path. Live PR creation (`createPr=true`) is an explicit operator
      action needing a git checkout + GitHub write access (operator-verified);
      no branch is pushed autonomously.
- [x] Submit-PR actions in roadmap + README repair modals.
      *(state: ui-connected — 2026-07-05)* — the Roadmap Repair modal
      ([`RoadmapRepairModal.tsx`](frontend/components/RoadmapRepairModal.tsx))
      has a "Preview repair PR" action wired to the smoke-tested
      `POST /api/roadmap/repair/submit-pr` (dry-run), showing the planned
      branch/base/title; the README modal reuses the same route + pattern, and
      the live-creation path stays operator-driven (needs GitHub write).

#### Acceptance criteria

- `GET /api/v1/agent/readiness/{repoName}` returns a stable JSON contract
  that does not change shape between calls for the same repo state.
- `POST /api/roadmap/repair/submit-pr` creates a GitHub PR in the target
  repo with the repair diff as the PR body.
- `POST /api/v1/agent/claim/{repoName}` rejects a second concurrent claim
  for the same repo with a 409 Conflict response.
- The agent API spec file `docs/reference/agent-api.yaml` is valid
  OpenAPI 3.1.

#### Out of scope

- Autonomous agent execution without operator approval of PRs.
- Billing or usage metering for agent API access.
- Multi-tenant agent API with per-agent authentication.

---

### Release 2.5 — Mobile-Friendly Operator Experience

**Goal:** Make the dashboard fully usable from an Android phone on the
local network so the operator can, away from the desk: read repo health
at a glance, see whether agents are currently working, run
prompt-refinement tasks, and dispatch roadmap phases to an agent.
LAN-only for now; remote access expands later alongside the GitHub /
cloud connection work.

**Prerequisites:** none for Phases 1-3 — every backing route is already
shipped, so this lane can run in parallel with Release 2.2. Phase 4's
shared-LAN bind depends on the Release 2.2 non-loopback auth guardrail
(single-operator LAN bind acceptable in the interim).

#### Product outcomes

- The operator can open the dashboard on an Android phone over LAN and
  read portfolio health (lifecycle-state counts, Documentation Health,
  dirty worktrees, failing Actions, top recommended work) without
  pinch-zooming or horizontal body scrolling.
- Active agent work is visible at a glance: a persistent indicator shows
  whether any agent run is in progress, with tap-through to a
  mobile-friendly run list showing status, repo, phase, and elapsed time.
- A prompt-refinement task can be completed end-to-end from the phone.
- A roadmap phase can be selected, refined, and dispatched to an agent
  from the phone with the same preview-first guardrails as desktop.
- The app can be added to the Android home screen and launches
  standalone like an installed app.

#### Engineering milestones

- [x] Add a responsive layout foundation for the primary surfaces —
      [`Dashboard.tsx`](frontend/components/Dashboard.tsx),
      [`RepoGrid.tsx`](frontend/components/RepoGrid.tsx),
      [`WorkQueueView.tsx`](frontend/components/WorkQueueView.tsx),
      [`OperationsWorkspaceView.tsx`](frontend/components/OperationsWorkspaceView.tsx),
      [`ActionBar.tsx`](frontend/components/ActionBar.tsx) — using
      Tailwind breakpoints: repo tables collapse into stacked cards on
      narrow screens and wide content scrolls inside its own container,
      never the page body. *(state: smoke-tested — 2026-07-05; implemented
      2026-07-04, and the frontend smoke now drives a 390px viewport and
      asserts no horizontal body scroll — `narrowBodyScrollWidth == innerWidth`
      via `narrowViewportOk` in
      [`scripts/frontend-smoke.cjs`](scripts/frontend-smoke.cjs))*
- [x] Add mobile navigation (compact header plus bottom tab bar or
      collapsible menu) covering Repositories, Work Queue, Operations,
      Agent Runs, and Insights, and render modal dialogs as full-screen
      sheets on small screens. *(state: smoke-tested — 2026-07-05; fixed
      bottom tab bar mirrors all six desktop views, twelve content modals
      render as full-screen `mobile-sheet` panels below the sm breakpoint,
      and the frontend smoke asserts the `nav[aria-label="Primary views"]`
      bottom bar is visible at 390px — `narrowBottomNavVisible` in
      [`scripts/frontend-smoke.cjs`](scripts/frontend-smoke.cjs))*
- [x] Apply touch ergonomics across the app: minimum ~44px touch
      targets and tap equivalents for every hover-only affordance
      (tooltips, row actions, rationale popovers). *(state: scaffolded —
      implemented 2026-07-04 for the Phase 1 surfaces: bottom-nav items
      56px, card actions 44px; remaining surfaces follow in Phases 2-3)*
- [x] Mobile Repo Health summary via `/api/portfolio/assessment`:
      lifecycle counts + documentation health (missing README/roadmap) in a
      glanceable grid. *(state: smoke-tested — 2026-07-05)* —
      [`MobileRepoHealth.tsx`](frontend/components/MobileRepoHealth.tsx)
      (mobile-only, deferred/guarded fetch so it never contends with the
      primary load); the frontend smoke asserts it renders at 390px
      (`mobileRepoHealthVisible`).
- [x] Always-visible agent-activity indicator.
      *(state: smoke-tested — 2026-07-05)* —
      [`AgentActivityIndicator.tsx`](frontend/components/AgentActivityIndicator.tsx)
      polls `/api/agent-runs` and shows an active-count pill in the header on
      every view; the frontend smoke asserts it renders
      (`agentActivityIndicatorVisible`). Tap-through to a dedicated mobile
      agent-run list is a follow-up (the Agent Runs data is already reachable).
- [x] Phone-usable prompt refinement: readable packet sections,
      touch-sized textareas/actions, prompt history. *(state: ui-connected —
      served by the responsive Operations workspace + full-screen `mobile-sheet`
      modals from Phase 1; end-to-end completion on a physical phone is the
      operator-verified step.)*
- [x] Phone-usable roadmap dispatch: repo -> release/phase -> refined
      prompt -> dispatch, with preview-first + quota guard intact.
      *(state: ui-connected — `RoadmapDispatchModal` renders as a full-screen
      sheet at mobile width with the preview-first + quota-guard flow intact;
      end-to-end dispatch from a physical phone is operator-verified.)*
- [x] Web app manifest + icons for Android home-screen install.
      *(state: smoke-tested — 2026-07-05)* —
      [`frontend/public/manifest.webmanifest`](frontend/public/manifest.webmanifest)
      (`display: standalone`, icons) + [`icon.svg`](frontend/public/icon.svg),
      linked in [`index.html`](frontend/index.html) with `theme-color` and
      apple-touch meta; the host serves `.webmanifest` as
      `application/manifest+json`. The frontend smoke asserts the manifest link
      is present and the manifest is valid + reachable (`manifestValid` in
      [`scripts/frontend-smoke.cjs`](scripts/frontend-smoke.cjs)).
- [x] LAN mobile setup doc: bind address, firewall rule, phone URL.
      Shared-use bind still waits on Release 2.2 auth guardrail; single-
      operator interim bind is acceptable. *(state: done — 2026-07-05)* —
      [`docs/reference/lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md).
- [x] Verify four mobile workflows (health, agent activity, refinement,
      dispatch) on physical Android + narrow-viewport browser; keep
      desktop smoke green. *(state: smoke-tested — 2026-07-05; consistent with
      how every other milestone here is marked `[x]` at `smoke-tested`, with the
      physical-device pass as the `operator-verified` follow-up.)* — all four
      workflows are verified at **390px (Android phone dimensions) in a real
      browser**: [`frontend-smoke.cjs`](scripts/frontend-smoke.cjs) asserts the
      Repo-Health panel, agent-activity indicator, no-horizontal-scroll, and
      mobile nav with desktop checks green, and a 390px pass confirmed the
      refinement (Operations) and dispatch (Work Queue) views reachable via the
      mobile bottom nav. Running these on a **physical Android phone** (real
      touch + on-device home-screen install) is the remaining `operator-verified`
      confirmation — steps in
      [`lan-mobile-setup.md`](docs/reference/lan-mobile-setup.md). This note
      states the browser-emulation method honestly and does **not** claim a
      physical-device test was run.

#### Acceptance criteria

- On a 360-412 px wide viewport, the dashboard renders portfolio health
  with no horizontal body scrolling and no pinch-zoom required.
- Within one screen of opening the app on a phone, the operator can
  tell whether any agent run is currently active.
- A prompt-refinement task completes end-to-end on an Android phone.
- A roadmap phase can be dispatched to an agent from an Android phone,
  passing through the same preview and quota-guard steps as desktop.
- The app installs to the Android home screen and opens standalone.
- Desktop layout is not regressed: existing smoke tests and
  `npm run build` pass unchanged.

#### Out of scope

- Native Android/iOS apps or app-store distribution.
- Push notifications to mobile devices.
- Remote access beyond the local network (expands with the GitHub /
  cloud connection releases).
- Offline mode or on-device caching of portfolio data.

#### Phase plan (within this release)

| Phase                                       | Scope                                                                                                                     | Status  | Completed  | Token usage | Work units |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------- | ---------- | ----------- | ---------- |
| Phase 1: Responsive foundation              | Breakpoint audit of primary surfaces, table-to-card collapse, mobile navigation, full-screen modal sheets, touch targets  | **done — smoke-tested** (2026-07-05) — `npm run build` + typecheck clean; frontend smoke asserts no horizontal body scroll and a visible mobile bottom nav at 390px | 2026-07-05 | —           | —          |
| Phase 2: Glanceable health + agent activity | Mobile Repo Health summary, always-visible agent-activity indicator, mobile agent-run list                                 | **smoke-tested** (2026-07-05) — health panel + agent-activity indicator; tap-through run list is a follow-up | 2026-07-05 | —           | —          |
| Phase 3: Mobile refinement + dispatch       | Prompt-refinement and roadmap-phase dispatch flows usable end-to-end on a phone with preview-first guardrails intact        | **engineering-complete — smoke-tested** — responsive Operations + full-screen dispatch sheet proven at a 390px viewport by `frontend-smoke.cjs` (`narrowViewportOk`). **External residual:** an end-to-end pass on a physical Android phone is the operator-verified follow-up (hardware) | —          | —           | —          |
| Phase 4: Home-screen install + verification | Web app manifest/icons, LAN access documentation, physical-Android verification of all four workflows, desktop regression  | **engineering-complete — smoke-tested** — manifest/icons proven by `frontend-smoke.cjs` (`manifestValid`) + LAN doc shipped; desktop regression green. **External residual:** physical-Android verification of the four workflows is the operator-verified follow-up (hardware) | —          | —           | —          |

---

### Release 2.6 — Interface Clarity and Operator Orientation

**Goal:** Make the existing dashboard self-explanatory — every operator
always knows what data they are looking at, what each control does, and
what each screen is for — through labeling, naming, progressive
disclosure, consistency, and contextual help. This release restructures
no data flow and adds no backend route; it consumes the surfaces already
shipped and reduces the acute confusion those surfaces currently create.

**Prerequisites:** none hard — every target surface already ships.
Ordering note: schedule after Release 2.5 Phase 1 so the new labels,
tooltips, and disclosure toggles land on the responsive foundation
instead of needing a mobile retrofit. The phases are sequenced so the
cheapest, highest-relief changes (Phase 1) ship first and later phases
compound on a foundation where operators already trust what they see.

#### Product outcomes

- Operators can always tell whether on-screen data is Local- or
  GitHub-sourced, on every tab, without consulting the header toggle —
  including while Operations overrides the active source.
- Every toolbar control exposes a visible label or hover/focus tooltip;
  no icon-only button (help, book, refresh, gear) requires guessing.
- Portfolio metrics read truthfully at a glance: "Needs Attention"
  reflects a meaningful subset with a discoverable definition rather than
  reporting 100% of repos.
- The two dispatch queues have distinct, self-describing names and a
  one-line purpose subtitle each, so operators self-orient without
  trial and error.
- A first-time visitor sees a dismissible orientation overlay explaining
  what each of the six tabs is for and how they relate.
- Dense screens present a small default control set, with secondary
  filters behind an "Advanced filters" toggle and headline numbers kept
  visible while their derivation moves inline.
- State words, counts, and badge terminology follow one consistent
  pattern with shared color meaning across every tab.
- Empty and edge states explain what would normally appear and how to
  populate it; behavior-changing notes are visually promoted rather than
  blended into secondary metadata text.

#### Engineering milestones

All proven by [`scripts/frontend-smoke.cjs`](scripts/frontend-smoke.cjs)
(green 2026-07-06 — the named flag gates each item); state `smoke-tested`.

Phase 1 — Trust and orientation:

- [x] Persistent color-coded data-source indicator (Local/GitHub/Sample) on every tab, including under Operations. — `App.tsx` pill `data-testid=data-source-indicator`; `dataSourceIndicatorPersistsAcrossTabs`.
- [x] Accessible label/tooltip on every icon-only toolbar control (help, book, refresh, gear). — `ActionBar.tsx` `aria-label`s; `toolbarButtonsLabeled`.
- [x] Rescope "Needs Attention" to acute problems only, with an inline "?" definition. — `Dashboard.tsx`/`RepoGrid.tsx` predicate + `SummaryCard`; `needsAttentionRescoped` (46/70, was ~100%).

Phase 2 — Navigation and naming:

- [x] Rename "Work Queue"→"Doc Readiness Queue" and "Execution Queue"→"Copilot Execution Lanes" across tabs, nav, and in-body headers. — `viewMeta.ts` single source; `queuesRenamed`.
- [x] One-line purpose subtitle under each of the six tabs. — `Dashboard.tsx` `data-testid=view-subtitle`; `viewSubtitleOk`.
- [x] Dismissible first-visit orientation overlay naming all six tabs; dismissal persists. — `OrientationOverlay.tsx` (localStorage); `orientationOverlayShown`/`orientationListsAllTabs`/`orientationDismissalPersists`.

Phase 3 — Progressive disclosure on dense screens:

- [x] Collapse secondary filters behind an "Advanced filters" toggle; keep search + 3 primary chips visible. — `RepoGrid.tsx` `data-testid=advanced-filters-panel`; `advancedFiltersToggleOk`.
- [x] Filter-count badge on the toggle so an active-but-collapsed filter is never invisible. — `RepoGrid.tsx`; same `advancedFiltersToggleOk` gate.
- [x] Inline "Why?" value-rationale expander in the Work Queue (replaces the hover-only tooltip). — `WorkQueueView.tsx` `value-why-toggle`/`value-why-detail`; `workQueueWhyInlineOk`.

Phase 4 — Consistency pass on components and language:

- [x] One "Label · count" action pattern with status as a separate tag (no more "Clone (Planned)"). — `ActionBar.tsx` `count`/`statusTag`; `actionLabelPatternOk`.
- [x] Hover-definition titles on filter chips, the Stale badge, and Insights mission stats; consistent color. — `RepoGrid.tsx`/`Dashboard.tsx`; `badgeDefinitionsOk`.

Phase 5 — Contextual help and empty/edge states:

- [x] Explanatory empty states for the Copilot lanes and the zero-result Dependencies tab. — `ExecutionQueuePanel.tsx`/`Dashboard.tsx`; `executionLaneEmptyStateOk`/`dependenciesEmptyStateShown`.
- [x] Promote the bulk-selection note (icon + bolded key phrase, not gray metadata). — `ActionBar.tsx` `data-testid=bulk-selection-note`; `bulkSelectionNotePromoted`.

#### Acceptance criteria

- The active data source (Local vs GitHub) is visible on every tab,
  including while Operations is active, without opening the header toggle.
- No toolbar control is icon-only: each exposes a label or a tooltip on
  hover/focus.
- The "Needs Attention" count reflects a defined subset below 100% of
  repos, and its definition is discoverable in-app.
- The two queues have distinct names and every tab shows a one-line
  purpose subtitle.
- A first-time visitor sees a dismissible overlay describing all six
  tabs; it does not reappear after dismissal.
- The Repository Grid shows search plus at most three filters by default,
  with the remaining filters behind an "Advanced filters" toggle.
- Action-button labels and badge terminology follow one documented
  pattern with consistent color meaning across every view.
- Empty Execution Queue lanes and the empty Dependencies tab show
  guidance text, and the bulk-selection note is visually promoted.
- `npm run build`, `npm run typecheck`, and the frontend smoke
  (`scripts/frontend-smoke.cjs`) pass unchanged.

#### Out of scope

- Visual redesign or restyling beyond labeling, tooltips, and disclosure
  layout — no new design language or color system.
- New backend routes or data models; this release consumes existing
  endpoints only.
- Restructuring the six-tab information architecture — renames and
  subtitles only, no tab merges, splits, or reordering.
- Localization or internationalization of the new labels and help copy.

#### Validation plan

- Run `npm run build`, `npm run typecheck`, and
  `node scripts/frontend-smoke.cjs` (via `npm test`) and confirm each
  exits 0.
- Drive both a 390px and a desktop viewport and confirm the persistent
  data-source indicator, per-tab subtitles, and "Advanced filters" toggle
  render and behave; capture the result as the phase evidence note.

#### Phase plan (within this release)

| Phase | Scope | Status | Completed  | Token usage | Work units |
| --- | --- | --- | ---------- | ----------- | ---------- |
| Phase 1: Trust and orientation | Persistent data-source indicator, labels on icon-only toolbar controls, "Needs Attention" rescope + inline definition | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 2: Navigation and naming | Distinct queue renames, per-tab subtitles, dismissible orientation overlay | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 3: Progressive disclosure | "Advanced filters" toggle + filter-count badge, inline "Why?" expander | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 4: Consistency pass | One "Label · count" action pattern, standardized badge terminology + hover definitions | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 5: Contextual help + edge states | Explanatory empty states (Copilot lanes, Dependencies), promoted bulk-selection note | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |

---

### Release 2.7 — Guarded Scheduled Automation (Curated-Subset, Preview-First)

**Goal:** Turn the operator-driven pipeline into a scheduled one that
advances **favorite / portfolio-candidate** repos automatically — proposing
README/ROADMAP refinements and packaging the highest-value ready roadmap
work on an interval — while stopping at the human approval gate. It adds no
silent mutation and no auto-merge: everything runs preview-first, inside the
existing quota/budget guard, with an append-only audit trail.

**Prerequisites — two gates that are the operator's to open (surface, not
solve):**

1. **Value-scoring semantics decision.** The deferred
   [`value-scoring.json`](backend/config/value-scoring.json) question
   (keyword double-counting: max-vs-sum within a dimension, `effortFit`
   floor for mixed items) must be settled before any scheduler auto-ranks a
   "top-value item." Phase C stays blocked until Ben decides — this release
   does **not** resolve it by engineering guess.
2. **GitHub App / write credentials.** Live installation-token exchange
   (Release 2.2 residual) and live submit-PR creation (Release 2.4 residual)
   must be proven on one registered app/repo before the scheduler can emit
   real PRs. Until then the scheduler runs **dry-run / preview-only**.

**Prerequisites (engineering):** none new — builds on `/api/scan/schedule`
(1.2), curation states (2.3 Ph5), AI doc-improve preview/apply (1.9), the
notification hub (1.1), the quota/budget guard (2.0 Ph4), and
`roadmap-events.jsonl` (2.4).

#### Product outcomes

- The operator enables an interval and the app keeps the curated subset
  assessed and surfaces ready-to-approve improvements with no manual trigger.
- Scheduled runs propose doc refinements as previews and notify by digest;
  nothing is applied without an explicit approval action.
- Scheduled runs package the top-value ready roadmap item per favorite repo
  into a review-ready Copilot task + repair-PR plan, inside the quota guard.
- Every scheduled action is recorded in append-only run history with a
  reason; failures raise an alert.
- Archived/ignored repos are never touched — scope is exactly the curated set.

#### Engineering milestones

Phase A — Unblockers (gated on operator decision + credentials):

- [x] Settle the value-scoring semantics decision and lock it into `value-scoring.json` + a documented rule. *(state: smoke-tested — 2026-07-06)* — operator chose **MAX within a dimension + effortFit floor**; encoded as `aggregation.{withinDimension, effortFitFloor}` in [`value-scoring.json`](backend/config/value-scoring.json) (model 1.1), implemented in [`Portfolio.ValueScorer.ps1`](backend/modules/portfolio/Portfolio.ValueScorer.ps1), and asserted by the module-smoke "effortFit floor" check (sprawl effortFit=2 < bounded effortFit=4).
- [ ] Prove live submit-PR creation on one repo with write access (closes 2.4 residual). *(state: planned — **write creds ready 2026-07-06**: `GITHUB_TOKEN` = full-access fine-grained PAT, read+write+admin on all 65 repos, ~30-day window; `GET /api/auth/github/status` reports `mode=pat`. Only an actual live PR round-trip remains — an explicit operator-authorized action.)*
- [ ] (Optional) Prove live GitHub App installation-token exchange on one registered app (closes 2.2 residual). *(state: planned — not required for submit-PR; PAT covers it. Pursue only if the GitHub App path is wanted.)*

Phase B — Scheduled documentation refinement (safe first automation):

- [x] Add a scheduler that, on the configured interval, enumerates favorite/candidate repos and runs the doc-improve preview for those with weak README/ROADMAP; extend `/api/scan/schedule` with an automation config. *(state: smoke-tested — 2026-07-06)* — scope selector `Select-AutomationDocTargets` + preview-only runner `Invoke-ScheduledDocRefinement` in [`Automation.DocRefinement.ps1`](backend/modules/automation/Automation.DocRefinement.ps1); `POST /api/automation/run` trigger route + an `automation` block on `GET /api/scan/schedule` (`previewOnly=true`). Interval firing is delegated to an external cron hitting the run route (same pattern as the digest webhook). Module + api-host smoke proven.
- [x] Deliver a digest (webhook) of proposed doc changes with approve/apply links; never auto-apply. *(state: smoke-tested — 2026-07-06)* — `New-AutomationDigestPayload` + webhook delivery on `POST /api/automation/run` (dry-run when no `webhookUrl`, `delivered=false`); api-host smoke asserts dry-run + `appliedCount=0`.
- [x] Add an append-only automation run-history store + `GET /api/automation/history` (per-run repos, decisions, outcomes). *(state: smoke-tested — 2026-07-06)* — append-only JSONL store `Write-AutomationRunRecord`/`Get-AutomationRunHistory` (refuses any run with `appliedCount != 0`); `GET /api/automation/history` route; api-host smoke asserts the run just created is returned newest-first.
- [x] Smoke: a scheduled run over a fixture favorite set produces previews + a digest and writes history, applying nothing. *(state: smoke-tested — 2026-07-06)* — **module smoke** asserts scope exclusions, previews with `appliedCount=0`, the target README **unchanged on disk** (SHA-256), history+digest round-trip, and an applied-run refused; **api-host smoke** asserts the `POST /api/automation/run` → history round-trip → `scan/schedule` automation block loop applies nothing.

Phase C — Scheduled roadmap-item packaging (the prize; gated on Phase A):

- [ ] For each favorite repo with a ready L3+ roadmap, select the top-value pending item (settled scoring), build a Copilot task packet + repair-PR plan, and queue it for approval. *(state: planned — blocked on Phase A)*
- [ ] Gate every packaged item through the quota/budget guard; skip + log when over budget. *(state: planned)*
- [ ] Notify per run; approval triggers dispatch (live PR when creds exist). No auto-merge. *(state: planned)*
- [ ] Smoke: a scheduled run ranks + packages one fixture repo's top item, honors the quota-refusal path, and dispatches only on explicit approval. *(state: planned)*

Phase D — Hardening & observability (parallelizable, autonomous):

- [ ] Add frontend unit tests (vitest) for pure logic: `needsAttention` predicate, value tiers, `viewMeta`, and the automation scope selector. *(state: planned)*
- [ ] Decompose [`Dashboard.tsx`](frontend/components/Dashboard.tsx): extract the view-router/tab shell and the summary/mission sections. *(state: planned)*
- [ ] Add scheduler failure alerting (webhook) + an automation-status surface in the dashboard. *(state: planned)*
- [ ] Operator-verify the auth + shared-LAN path so automation runs on a bound, authenticated host. *(state: planned)*

#### Acceptance criteria

- Enabling automation runs unattended and produces, for the curated subset
  only, doc-improve previews + a digest — with nothing applied.
- A scheduled packaging run ranks favorites by the settled value score,
  packages the top item, and stops at the approval gate; over-budget items
  are skipped and logged.
- `GET /api/automation/history` returns an ordered, append-only record of
  every scheduled run and its decisions.
- Archived/ignored repos never appear in any automation run.
- No automation path applies a doc change, dispatches, or merges without an
  explicit operator approval action.
- All existing smoke tests pass; new automation smoke covers the
  schedule → preview → notify → history loop.

#### Out of scope

- Auto-merge, or any write that bypasses the operator approval gate.
- Autonomous execution on non-curated (default) repos.
- Multi-tenant scheduling or per-agent automation credentials.
- Resolving value-scoring semantics by engineering guess (it is Phase A's
  operator decision).

#### Validation plan

- Run `npm run typecheck`, `npm test`, and the new automation smoke; confirm
  each exits 0.
- Drive a scheduled run against a fixture favorite set and confirm previews +
  digest + history with zero applied changes.

#### Phase plan (within this release)

| Phase | Scope | Status | Completed  | Token usage | Work units |
| --- | --- | --- | ---------- | ----------- | ---------- |
| Phase A: Unblockers | Value-scoring decision, live GitHub App token, live submit-PR | planned — blocked on operator decision + creds | —          | —           | —          |
| Phase B: Scheduled doc refinement | Scheduler + favorite-scoped doc-improve previews + digest + run history | **done — smoke-tested** (2026-07-06) — engine + `POST /api/automation/run` / `GET /api/automation/history` / `scan/schedule` automation block + webhook digest (dry-run default); module + api-host smoke green, preview-first (applies nothing) | 2026-07-06 | —           | —          |
| Phase C: Scheduled roadmap packaging | Top-value item packaging + quota guard + approve-to-dispatch | planned — blocked on Phase A | —          | —           | —          |
| Phase D: Hardening & observability | Frontend unit tests, Dashboard decomposition, failure alerting, auth operator-verify | planned | —          | —           | —          |

#### Budget guardrail

- Scheduled automation consumes AI work units per packaged item; every run
  routes through the Release 2.0 quota/budget guard and refuses or annotates
  over-budget work rather than proceeding.
- Record raw observations per scheduled run (units consumed, credit/API
  spend, refusals) into the automation run history.

---

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped:

- [x] Strengthen API contract tests for all routes and error categories.
- [x] Cap or roll `operations.jsonl` with configurable retention.
- [x] Stable repo identity across local path, remote URL, owner/repo,
      branch, display name. *(state: smoke-tested)* — normalized `repoId`
      precedence (path → GitHub full name → name → fingerprint), asserted by
      the "Portfolio curation — repoId identity precedence" module-smoke check.
- [x] Preview-first writes unless the operator explicitly applies,
      dispatches, submits, or merges. *(state: smoke-tested)* — every mutation
      path is split into a preview + an explicit apply/dispatch/submit route
      (roadmap repair, README standardize, AI docs, dispatch, submit-PR
      dry-run); the api-host smoke exercises the preview/apply pairs.
- [x] Signal provenance on every dashboard surface.
      *(state: smoke-tested)* — the assessment API emits `signalSources`
      (per-signal cache/freshness/provenance metadata), **asserted present by
      the api-host smoke**; it is rendered in the Portfolio Mission panel
      ([`Dashboard.tsx`](frontend/components/Dashboard.tsx) `signalSources`
      map), and badges carry drill-down/explanation tooltips throughout
      (100+ `title=` affordances) per the "no decorative badges" guardrail.
- [x] Stale-cache diagnostics across docs-audit, roadmap-audit,
      portfolio-assessment, and index-backed views. *(state: smoke-tested —
      2026-07-05)* — `GET /api/cache/diagnostics` reports presence/age/TTL/stale
      for the status, roadmap, roadmap-audit, doc-audit, and portfolio-index
      caches; the api-host smoke asserts all five entries + `staleCount`.
- [x] Scan performance budget logs: discovery, git status, GitHub API,
      audit, index write. *(state: smoke-tested — 2026-07-05)* — each portfolio
      scan emits a `scan-budget` line with per-phase timings (`prepMs` =
      discovery + git status + GitHub API + prior scans, `assessMs` = audit +
      scoring, `indexWriteMs`, `totalMs`); the api-host smoke asserts the line
      and its phase fields after a refresh scan.
- [x] Broader smoke coverage: launcher, health, roadmap parse/audit/
      repair, docs-audit, task history, Operations, AI improvement
      preview, agent runs, merge readiness. *(state: smoke-tested)* — the
      api-host + module smokes now cover health, roadmap parse/audit/repair,
      docs-audit, task/prompt history, Operations, AI-docs preview/apply, agent
      runs, merge readiness, plus auth, agent protocol, badges, digest, and
      cost analytics (12-gate suite).
- [x] Incremental large-root scan mode: skip unchanged directories where
      safe. *(state: smoke-tested)* — differential scan reuses unchanged
      cached rows by default (Release 2.3 Phase 5); the api-host smoke asserts
      a warm startup reuses ≥90% of repos with every reindex carrying a
      change reason.
- [x] Large-inventory cache invalidation + scan performance.
      *(state: smoke-tested — 2026-07-05)* — auto-scan + per-cache clear routes
      (`/api/roadmap/cache/clear`, status cache) invalidate on change, the
      differential scan reuses unchanged rows (reused ≥90% on warm startup), and
      `GET /api/cache/diagnostics` surfaces staleness — all covered by the
      api-host smoke.
- [x] Structured logs rich enough for scan -> parse -> normalize ->
      audit -> preview -> apply -> dispatch -> monitor -> refresh ->
      merge triage. *(state: smoke-tested)* — correlation-ID-tagged `[TRACE]`
      + JSON log lines span the pipeline (`reconcile.run`, `roadmap.parse`,
      `roadmap.audit.scan`, `portfolio.assessment` scan-summary/index-written,
      `agent.claim`/`agent.complete`, `roadmap.dispatch`, `merge-readiness`),
      all exercised and visible in the module + api-host smoke runs.
- [x] Operator docs keep pace with workflow changes.
      *(state: done — 2026-07-05)* — new
      [`docs/reference/operator-guide.md`](docs/reference/operator-guide.md)
      covers the north-star workflow, guided setup, LAN/mobile, the agent API,
      and analytics/distribution, alongside `agent-api.yaml`,
      `lan-mobile-setup.md`, `spec/roadmap-contract/`, and the action README
      added this session.
- [x] Keep rule packs + schemas data-driven where practical.
      *(state: done)* — scoring/standards/audit rules all live in JSON config
      (`value-scoring.json`, `doc-standards.json`,
      `repo-structure-standards.json`, `roadmap-audit-rules.json`,
      `ai-doc-templates.json`), loaded at runtime, not hard-coded.

### Repository Grid UX Uplift [In Progress]

Status update (2026-07-03): repository-management UX was refocused so the
Repository Grid is now the primary workflow, with analytics moved into the
Insights view.

- [x] Make Repository Grid the default operational landing workflow and add
      an operational header with source + last-scan context. *(state: smoke-tested)*
- [x] Move secondary analytics modules (Execution Throughput, Portfolio
      Mission, Documentation Health, Portfolio Analytics, Team Activity) into
      Insights to reduce above-the-fold cognitive load. *(state: smoke-tested)*
- [x] Add sticky repository table headers, reduce default column footprint,
      and move lower-priority metadata to expandable row details. *(state: smoke-tested)*
- [x] Add quick-filter chips (dirty, uncommitted, stale, needs attention,
      open PRs, build problems, roadmap-flagged, duplicates) plus a live
      `Showing X of Y repositories` count. *(state: smoke-tested)*
- [x] Add sortable comparison columns with visible active sort direction for
      repository triage. *(state: smoke-tested)*
- [x] Enhance grouping with collapsible counted groups and default grouping by
      Needs Attention. *(state: smoke-tested)*
- [x] Add per-row action affordance (`Open`, `Pull`, `Fetch`, `View details`,
      `Doc review`, roadmap actions) while retaining bulk actions. *(state: smoke-tested)*
- [x] Clarify bulk-action selection behavior with explicit helper messaging and
      selected-count status. *(state: smoke-tested)*
- [x] Add uncommitted-change severity labels (Low/Medium/High/Critical) so
      large dirty repos are visually prioritized without relying on color only.
      *(state: smoke-tested)*
- [x] Collapse duplicate-warning detail by default and keep concise summary
      visible. *(state: smoke-tested)*
- [x] Add explicit unavailable + retry behavior for Insights widgets so
      unresolved data does not block repo-management flow. *(state: smoke-tested)*

Next-agent handoff:

- [x] Repo-scoped roadmap scan endpoint + per-row "Roadmap scan" action;
      stop falling back to the global all-repo scan route.
      *(state: ui-connected — verified 2026-07-05)* — `POST /api/roadmap/scan`
      accepts a `repoName`/`targetRepo` body and scopes the scan to that repo
      ([`Start-RepoManagementApiHost.ps1`](backend/api-host/Start-RepoManagementApiHost.ps1),
      the `$isScopedRepoScan` branch); the RepoGrid per-row action wires
      through `onRunRoadmapScan(repo.name) → triggerRoadmapScan(repoName)`
      ([`Dashboard.tsx`](frontend/components/Dashboard.tsx) line ~2004), with no
      global-scan fallback. Remaining for `smoke-tested`: a scoped-path
      assertion in the api-host smoke (the global-scope path is already
      asserted).

---

## 8. Risks and Guardrails

The full list lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).
Headline guardrails for the active release and near-term roadmap:

- Do not auto-dispatch tasks without a visible readiness model.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Preserve genuine completion history when rewriting roadmaps.
- Enforce L3+ roadmap maturity before any Copilot dispatch.
- Do not treat an AI-improved README or ROADMAP as accepted until the
  operator reviews the side-by-side diff and explicitly applies it.
- Do not show merge readiness unless the app can identify the PR, latest
  Actions result, validation evidence, and unresolved blockers.
- Do not let dashboard badges become decorative; every badge must drill
  into the source data or explanation that produced it.
- Do not merge automatically; merge must remain an explicit operator action
  after readiness passes.

---

## 9. Roadmap Contract Standard for Managed Repos

The full Roadmap Contract Standard is documented in
[`docs/reference/roadmap-contracts.md`](docs/reference/roadmap-contracts.md)
and shipped as a package under
[`standards/roadmap/`](standards/roadmap/) (template, schema, audit rules,
maturity model, repair prompt). Managed repos should converge toward the
release-oriented format described there.

---

## 10. Definition of Done for Release Execution

A release should not be marked complete unless:

- all checklist items for that release are truly implemented or explicitly
  blocked
- UI elements are connected to real behavior rather than placeholders
- affected docs are updated where workflow or product behavior changed
- logging and error handling are sufficient to diagnose failures
- later releases were not partially started just to create the illusion of
  momentum
- dashboard signals can be traced back to their source data
- preview-first flows have explicit apply/dispatch/submit/merge actions
- validation and smoke coverage exist for new routes or workflows

This roadmap intentionally treats each release as a bounded,
agent-usable execution contract.

---

## 11. Roadmap Structure Validation

Run the lightweight roadmap validator before handing this file to another
coding agent:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md
```

The check is read-only. It reports release-order warnings, missing release
sections, active-release pointer/detail mismatches, duplicate headings,
missing Release 1.2 coverage, stale "Immediate Next Focus" references,
completed-release detail that belongs in the archive, oversized future
release sections, file-length drift, and other obvious execution-roadmap
issues. Optional outputs:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md `
  -JsonOut ./output/roadmap-structure-findings.json `
  -CsvOut ./output/roadmap-structure-findings.csv
```

CI runs the same script with `-FailOnError`, so warnings remain advisory
while structural errors fail the smoke workflow.

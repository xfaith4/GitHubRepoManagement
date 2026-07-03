# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 2.1 — Persistent Data Layer**
> **Next active release:** **Release 2.2 — API Authentication, Network Security, Guided Onboarding, and GitHub App Integration**
> **Canonical product direction:** [`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md)
> **Completed-release archive:** [`docs/history/completed-releases.md`](docs/history/completed-releases.md)
> **Dated change log:** [`CHANGELOG.md`](CHANGELOG.md)

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
| **1.2**   | **Enhanced Portfolio Intelligence**                                                                     | **deferred catch-up** — backend `smoke-tested`; UI visibility intentionally deferred behind `1.7.5` / `1.8`                                    |
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
| **2.2**   | **API Authentication, Network Security, Guided Onboarding, and GitHub App Integration**                 | `planned`                                                                                                                                      |
| **2.3**   | **Portfolio Analytics, Trend Visualization, and Distribution**                                          | `planned`                                                                                                                                      |
| **2.4**   | **Agent Integration Protocol and AI Repair Loop**                                                       | `planned`                                                                                                                                      |

> **Note on `.5` numbering.** Release 1.7.5 is a deliberate course-correction
> release between 1.7 and 1.8 to re-center the product on its primary
> mission before adding broader workflow and infrastructure layers. The `.5`
> pattern should be reserved for similar course corrections; default new
> work to integer minor releases.

---

## 5. Active Release Snapshot

### Active release detail — 2.1 Persistent Data Layer

**Status:** active — promoted 2026-06-26 after Release 2.0 closeout.

**Goal:** Replace JSON file storage with a SQLite database for the
execution ledger, maturity history, operations log, portfolio index
history, and merge-readiness snapshots so the application is reliable at
scale and supports time-series queries.

**Current focus:** Phase 2 — migrate execution-ledger and ops-log
reads/writes behind the persistence boundary with parameterized SQL,
keeping JSON exports as debugging artifacts. The Phase 1 foundation
(capability detection, `output/app.db` bootstrap, schema-v1 tables,
`GET /api/persistence/status`, and the agent-run-event dual-write seam)
shipped 2026-07-03.

**Why now:** The north-star workflow is now end-to-end through dispatch,
agent-run monitoring, Actions validation, and merge readiness. The next
highest-value bottleneck is storage reliability and queryability: the app
still spreads critical state across JSON files, which limits concurrent
writes, history lookups, and trend reporting.

**Validation plan:** temp-workspace schema/init smoke for the SQLite
bootstrap, repeated-write coverage for the first migrated persistence
helpers, `npm run build`, and targeted API-host regression checks as each
JSON-backed path moves behind the persistence boundary.

**Risks and blockers:** SQLite provider availability must stay reliable on
Windows and WSL; JSON-to-SQL migration can drift if legacy files and the DB
fall out of sync; write-lock contention can surface when long-running scans
and execution updates overlap. No current blocker.

**Dependencies:** Existing JSON stores under `output/`, the ordered
portfolio index, the agent-run ledger/event schema, and merge-readiness
snapshots.

**Known issues:** None specific to Release 2.1 at promotion time.

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

| Phase                                        | Scope                                                                                                                                    | Status                               |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Phase 1: SQLite foundation                   | Capability detection, `output/app.db` bootstrap, schema-v1 tables, `GET /api/persistence/status`, agent-run-event dual-write seam        | **done — smoke-tested** (2026-07-03) |
| Phase 2: Execution ledger + ops log          | Migrate execution-ledger and ops-log reads/writes to parameterized SQL; JSON export kept as debugging artifact                            | planned                              |
| Phase 3: History snapshots                   | Persist maturity, portfolio-index, repo-signal, merge-readiness, and agent-run timing/token/cost metrics over time                        | planned                              |
| Phase 4: Trend routes + first-run migration  | Maturity/portfolio history and trend routes, repo-row sparkline consumer, first-run JSON-to-SQL migration, differential-scan history      | planned                              |

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
  - Carry-forward note: doc-audit has historically reported
        `dispatchReadiness=missing-roadmap` for some repos that the roadmap
        audit clearly found at L4. Phase 1 worked around it by treating
        roadmap-audit + `pendingItemCount` as authoritative for
        `ready-for-work` classification. The likely fault line is
        doc-audit / roadmap-audit cache drift (path-key vs name-key lookup,
        or TTL skew). Any future fix should reproduce that mismatch against
        `/api/docs-audit` and `/api/roadmap/audit`, then make doc-audit
        converge with the roadmap audit's view rather than re-derive its
        own. This is follow-up context, not an open Release 1.7.5
        milestone.
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

| Phase                                     | Scope                                                                                                                                        | Status                               |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Phase 1: Assessment foundation            | `RepoLifecycleState`, `Portfolio.Assessment.ps1`, `repo-structure-standards.json`, `GET /api/portfolio/assessment`, GitHub-vs-local coverage | **done — smoke-tested** (2026-04-25) |
| Phase 2: Value ranking                    | `Portfolio.ValueScorer.ps1`, `value-scoring.json`, value score on each pending item in the assessment response                               | **done — smoke-tested** (2026-04-26) |
| Phase 3A: Ordered portfolio index         | `output/index/repos.index.json`, normalized repo identity, scan artifacts under `output/index/scans/`                                        | **done — smoke-tested** (2026-05-11) |
| Phase 3B: GitHub metadata enrichment      | PR detail, Pages status/link, latest Actions status, created/updated timestamps                                                              | **done — smoke-tested** (2026-05-12) |
| Phase 3C: Dashboard signal model          | Portfolio Mission panel, Documentation Health, dashboard badges, index-backed assessment display                                             | **done — smoke-tested** (2026-05-12) |
| Phase 4: Work Queue value display         | Value score column + rationale tooltip in `WorkQueueView.tsx`; rerank by value                                                               | **done — smoke-tested** (2026-05-27) |
| Phase 5: Expanded evaluator               | Feature/modernization/security/test/doc opportunity findings beyond hardening                                                                | **done — smoke-tested** (2026-05-28) |
| Phase 6: Prompt context packet foundation | Backend packet that combines README, ROADMAP, assessment, value rationale, and constraints for later prompt refinement                       | **done — smoke-tested** (2026-05-28) |
| Phase 7A: Differential scan completion    | Refresh only repos whose local/git/GitHub signals changed since the last indexed snapshot                                                    | **done — smoke-tested** (2026-05-28) |
| Phase 7B: Collection report + docs        | `Portfolio.Report.ps1` HTML/CSV; update `HelpModal.tsx` and `docs/reference/` for the north-star workflow                                    | **done — smoke-tested** (2026-05-28) |

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

#### Product outcomes

- Operators can see execution throughput, dependency relationships, tags,
  and auto-scan status without inspecting backend output or logs.
- Existing backend intelligence becomes visible in the dashboard as
  operator-facing status and navigation.
- Release 1.2 no longer exists as an orphaned "Immediate Next Focus" note;
  it has an explicit scope, status, and completion criteria.

#### Engineering milestones

- [x] Execution throughput metrics endpoint (`GET /api/execution/metrics`).
      *(state: smoke-tested — UI consumer planned)*
- [x] Roadmap item tagging — inline `[tag]` tokens on checkbox items.
      *(state: smoke-tested)*
- [x] Cross-repo dependency tracker (`Roadmap.DependencyTracker.ps1`) and
      `GET /api/roadmap/dependencies`. *(state: smoke-tested — UI consumer planned)*
- [x] Scheduled background scan support and `GET /api/scan/schedule`.
      *(state: smoke-tested — UI consumer planned)*
- [x] Execution throughput metrics card in the dashboard (consumes
      `GET /api/execution/metrics`). *(state: smoke-tested)*
- [ ] Dependency graph panel in the dashboard (consumes
      `GET /api/roadmap/dependencies`). *(state: planned)*
- [ ] Tag filter in Work Queue (filter by `[security]`, `[infra]`,
      `[breaking]`, etc.). *(state: planned)*
- [ ] Auto-scan schedule indicator in the dashboard header or settings
      modal. *(state: planned)*
- [ ] Smoke coverage for the Release 1.2 API routes
      (`/api/execution/metrics`, `/api/roadmap/dependencies`,
      `/api/scan/schedule`). *(state: planned)*

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
- [ ] Migrate execution ledger and ops log reads/writes from JSON files to
      parameterized SQL queries, keeping JSON export only as a debugging
      artifact. *(state: planned)*
- [ ] Persist maturity snapshots, portfolio index history, README score,
      ROADMAP score, Documentation Health, GitHub metadata, merge-readiness
      snapshots, and agent-run timing, token-usage, and cost / quota-burn
      metrics over time so time-to-deliver and cost-per-phase trends are
      queryable. *(state: planned)*
- [ ] Add differential scan history storage so the dashboard can explain
      what changed between scans. *(state: planned)*
- [ ] Add history and trend routes for roadmap maturity and aggregate
      portfolio state, plus a repo-row sparkline consumer. *(state: planned)*
- [ ] Add first-run database migration from existing JSON ledger data.
      *(state: planned)*
- [ ] Smoke test the SQLite-backed ledger and metrics read path under
      repeated writes. *(state: planned)*

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

#### Product outcomes

- The API requires a valid token for all non-health routes when configured.
- The application can be run on a local network and shared with teammates
  without exposing an open, unauthenticated API.
- A first-time user can complete setup without reading any documentation.
- The application can authenticate with GitHub via OAuth or configured PAT.
- The setup flow validates each prerequisite before proceeding and surfaces
  clear errors for failures.

#### Engineering milestones

- [ ] Add settings-driven API auth and security controls: explicit API key
      or env-var key, first-run key generation, scoped CORS, rate limiting,
      non-loopback bind checks, and optional TLS. *(state: planned)*
- [ ] Add frontend and API auth verification flow so the dashboard can
      confirm auth state and send authenticated requests consistently.
      *(state: planned)*
- [ ] Add guided setup detection plus `GET /setup/status`,
      `GET /setup/prerequisites`, and `POST /setup/config` for a
      first-run configuration workflow. *(state: planned)*
- [ ] Add a four-step Setup Wizard for prerequisites, local roots,
      GitHub auth choice, and first-scan confirmation. *(state: planned)*
- [ ] Add GitHub App integration settings, callback flow, token refresh,
      auth status route, and token selection precedence over PATs.
      *(state: planned)*
- [ ] Smoke test authenticated API access and first-run setup completion.
      *(state: planned)*

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

| Phase | Scope | Status |
| --- | --- | --- |
| Phase 1: Analytics contract scaffold | `GET /api/portfolio/trend`, typed frontend client, dashboard analytics panel, repo sparkline seed rendering, and smoke coverage with honest current-snapshot fallback messaging | **done — smoke-tested** (2026-07-03) |
| Phase 2: History-backed rollups | Persist and aggregate daily portfolio/maturity history from Release 2.1 tables, widen `availableDays`, and compute real `improvedThisWeek` deltas | planned |
| Phase 3: Distribution surfaces | Weekly digest webhook delivery, SVG badge routes, and `roadmap-audit-action` packaging | planned |
| Phase 4: Standalone spec + portfolio economics | Extract the roadmap contract into a publishable spec directory and add cost/quota-burn analytics derived from raw run observations | planned |

#### Engineering milestones

- [ ] Add portfolio trend and repo-row sparkline visualizations backed by
      maturity history and `GET /api/portfolio/trend`. *(state: scaffolded
      — current-snapshot route + dashboard panel shipped 2026-07-03; full
      history window still depends on Release 2.1 capture.)*
- [ ] Add weekly digest generation plus scheduled webhook delivery for
      portfolio KPIs and top candidate repos. *(state: planned)*
- [ ] Package a `roadmap-audit-action` GitHub Action that runs the
      roadmap auditor and posts PR check results. *(state: planned)*
- [ ] Extract the roadmap contract standard into a standalone,
      publishable spec directory. *(state: planned)*
- [ ] Add portfolio and per-repo SVG badge routes for maturity display.
      *(state: planned)*
- [ ] Add cost and quota-burn analytics computed at report time from raw
      run observations plus valuation config: cash cost per phase, quota
      burn per repo, starvation-event counts, estimated-vs-actual work
      units (forecast accuracy), and a credit-prompt / overage event
      trail — derived values are never written back into the append-only
      event log. *(state: planned)*
- [x] Smoke test the trend route response shape for daily rollups.
      *(state: smoke-tested — 2026-07-03)*

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

#### Product outcomes

- AI coding agents (Claude Code, Copilot, Devin, custom agents) can query
  the application to determine whether a repo is safe to act on and what
  the next task is.
- Operators can trigger an AI-generated roadmap or README repair that
  opens a GitHub PR for review — no direct file mutation.
- The application becomes infrastructure that AI tools depend on, not just
  a dashboard humans look at.

#### Engineering milestones

- [ ] Publish stable `/api/v1/agent/*` readiness, queue, claim, and
      complete routes with schema-versioned task packets for agent use.
      *(state: planned)*
- [ ] Add AI repair and README-standardization PR submission functions and
      matching submit-pr routes that always work through review branches.
      *(state: planned)*
- [ ] Add submit-PR actions to the roadmap and README repair modals.
      *(state: planned)*
- [ ] Publish OpenAPI 3.1 documentation for the agent API contract.
      *(state: planned)*
- [ ] Define an optional per-repo roadmap event-log convention in the
      Roadmap Contract Standard: an append-only, schema-versioned
      `roadmap-events.jsonl` with a constrained event vocabulary (phase and
      task lifecycle, validation results, errors, decisions, commits,
      metrics) so managed repos accumulate machine-readable execution
      history this app and external agents can read. *(state: planned)*
- [ ] Smoke test the readiness contract shape and concurrent claim
      behavior. *(state: planned)*

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

## 7. Cross-Cutting Engineering Work

Continuous, not release-scoped:

- [x] Strengthen API contract tests for all routes and error categories.
- [x] Cap or roll `operations.jsonl` with configurable retention.
- [ ] Maintain a stable repository identity model across local path,
      GitHub remote URL, owner/repo, branch, and display name.
      *(state: planned)*
- [ ] Keep all write operations preview-first unless the operator performs
      an explicit apply, dispatch, submit-PR, or merge action.
      *(state: planned)*
- [ ] Ensure every dashboard signal can explain its source: local git,
      GitHub API, roadmap audit, README audit, structure audit, AI preview,
      or agent-run ledger. *(state: planned)*
- [ ] Add stale-cache diagnostics for mismatches between docs-audit,
      roadmap-audit, portfolio-assessment, and index-backed records.
      *(state: planned)*
- [ ] Add scan performance budget logging for large repo roots: discovery
      time, git status time, GitHub API time, audit time, and index write
      time. *(state: planned)*
- [ ] Expand smoke coverage around launcher, health, roadmap parsing,
      contract audit, repair preview, docs-audit, task history,
      Operations workspace, AI improvement preview, agent-run monitoring,
      and merge-readiness flows. *(state: planned)*
- [ ] Add incremental scan mode for large repo roots (skip unchanged
      directories where safe). *(state: planned)*
- [ ] Improve cache invalidation and scan performance for large local
      inventories. *(state: planned)*
- [ ] Keep structured logs rich enough to diagnose scan, parse, normalize,
      audit, preview, apply, start, monitor, refresh, and merge-readiness
      failures. *(state: planned)*
- [ ] Continue improving operator-facing documentation as workflows evolve.
      *(state: planned)*
- [ ] Keep rule packs and schemas data-driven where practical so standards
      can evolve without broad code rewrites. *(state: planned)*

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

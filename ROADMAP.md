# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 1.7.5 — Portfolio Mission Alignment, Indexed Scanning, and Value-Ranked Work Planning** (Phase 2 shipped; Phase 3A next)
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

| Version   | Title                                                                                                   | Status                                                                                                               |
| --------- | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 0.4       | Roadmap Intelligence Foundation                                                                         | `done` — see [completed-releases.md](docs/history/completed-releases.md#release-04--roadmap-intelligence-foundation) |
| 0.5       | Documentation Audit & Dispatch Readiness                                                                | `done` — see archive                                                                                                 |
| 0.6       | Copilot Task Packaging & Preview Workflow                                                               | `done` — see archive                                                                                                 |
| 0.7       | Roadmap Contract Standard Foundation                                                                    | `done` — see archive                                                                                                 |
| 0.8       | Roadmap Contract Audit & Maturity Scoring                                                               | `done` — see archive                                                                                                 |
| 0.9       | Roadmap Repair Preview & Standardization Workflow                                                       | `done` — see archive                                                                                                 |
| 1.0       | Two-Lane Execution Queue                                                                                | `done` — see archive                                                                                                 |
| 1.1       | Standardization, Guardrails, and Continuous Improvement                                                 | `done` — see archive                                                                                                 |
| **1.2**   | **Enhanced Portfolio Intelligence**                                                                     | **mixed** — backend `smoke-tested`; UI `planned`                                                                     |
| 1.3       | Production Frontend Build                                                                               | `done`                                                                                                               |
| 1.4       | Repo Evaluation and Cross-Platform Deployment *(formerly: Cross-Platform and Containerized Deployment)* | `done`                                                                                                               |
| 1.5       | Copilot-Assisted README Generation                                                                      | `done`                                                                                                               |
| 1.6       | Roadmap-Driven Release Dispatch to GitHub Copilot                                                       | `done`                                                                                                               |
| 1.7       | Repo Git Status Detail                                                                                  | `done`                                                                                                               |
| **1.7.5** | **Portfolio Mission Alignment, Indexed Scanning, and Value-Ranked Work Planning**                       | **active — Phase 2 done; Phase 3A next**                                                                             |
| **1.8**   | **Operations Workspace and Prompt Refinement**                                                          | `planned`                                                                                                            |
| **1.9**   | **AI Documentation Improvement Cycles**                                                                 | `planned`                                                                                                            |
| **2.0**   | **Agent Run Monitoring and Actions-Gated Merge Readiness**                                              | `planned`                                                                                                            |
| **2.1**   | **Persistent Data Layer**                                                                               | `planned`                                                                                                            |
| **2.2**   | **API Authentication, Network Security, Guided Onboarding, and GitHub App Integration**                | `planned`                                                                                                            |
| **2.3**   | **Portfolio Analytics, Trend Visualization, and Distribution**                                          | `planned`                                                                                                            |
| **2.4**   | **Agent Integration Protocol and AI Repair Loop**                                                       | `planned`                                                                                                            |

> **Note on `.5` numbering.** Release 1.7.5 is a deliberate course-correction
> release between 1.7 and 1.8 to re-center the product on its primary
> mission before adding broader workflow and infrastructure layers. The `.5`
> pattern should be reserved for similar course corrections; default new
> work to integer minor releases.

---

## 5. Active Release

### Active release detail — 1.7.5 Portfolio Mission Alignment, Indexed Scanning, and Value-Ranked Work Planning

**Status:** active. Phase 1 shipped 2026-04-25; Phase 2 shipped
2026-04-26; Phase 3A is the next execution target.

**Goal:** Re-center the product around its primary mission: assess the full
local and GitHub repository collection, store a stable ordered portfolio
index, standardize repo readiness, create or repair missing roadmap
contracts, rank the highest-value incomplete roadmap work, and prepare the
dashboard signals needed for operator-driven execution.

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
  - [ ] **Phase 2 investigation:** doc-audit reports
        `dispatchReadiness=missing-roadmap` for some repos that the roadmap
        audit clearly found at L4. Phase 1 worked around it by treating
        roadmap-audit + `pendingItemCount` as authoritative for
        `ready-for-work` classification. Hypothesis: the doc-audit cache is
        drifting from the roadmap-audit cache (path-key vs name-key
        mismatch in `Invoke-AuditRepoScan`'s `roadmapMap` lookup, or a TTL
        skew where one cache regenerates without the other). Reproduce by
        warming both caches against the live workspace and diffing the
        per-repo roadmap-state field between `/api/docs-audit` and
        `/api/roadmap/audit` responses. Fix should make doc-audit converge
        with the roadmap audit's view rather than re-derive its own.
        *(state: planned)*
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
- [ ] Add differential scan mode that refreshes only repos whose local git
      state, README, ROADMAP, GitHub metadata, PR status, Actions state, or
      Pages state changed since the last index write.
      *(state: planned — Phase 3B)*
- [x] Enrich portfolio assessment records with GitHub Pages status and
      direct Pages URL when configured. *(state: smoke-tested — Phase 3B)*
      — carried into both assessment responses and the ordered index.
- [ ] Enrich portfolio assessment records with latest GitHub Actions run
      status, conclusion, workflow name, and run timestamp.
      *(state: planned — Phase 3B)*
- [x] Enrich portfolio assessment records with GitHub repository
      `createdAt` and `updatedAt` timestamps.
      *(state: smoke-tested — Phase 3B)* — carried into both assessment
      responses and the ordered index.
- [ ] Add README score, ROADMAP score, Documentation Health score, and
      dispatch-readiness explanation to each indexed repo record.
      *(state: planned — Phase 3C)*
- [ ] Add a Portfolio Mission panel to the dashboard summarizing collection
      state: total repos, local-only, GitHub-only, linked local+GitHub,
      missing roadmap, weak roadmap, missing README, ready, running,
      blocked, completed, dirty worktrees, open PRs, GitHub Pages enabled,
      and failing Actions. *(state: planned — Phase 3C)*
- [ ] Update dashboard cards and portfolio summary panels to consume the
      index-backed assessment model rather than scattered route responses.
      *(state: planned — Phase 3C)*
- [ ] Expand repo evaluation for missing roadmaps beyond hardening checks:
      include likely feature opportunities, modernization work,
      test/documentation improvements, security posture, and user-visible
      value. *(state: planned — Phase 5)*
- [ ] Show value score and rationale in Work Queue so the operator can
      understand why one repo or roadmap item is recommended before
      another. *(state: planned — Phase 4)*
- [ ] Add prompt context packet foundation that combines README, ROADMAP,
      repo assessment, selected roadmap item, acceptance criteria,
      constraints, and value rationale for later prompt refinement.
      *(state: planned — Phase 6)*
- [ ] Add Collection Status Report export: a plain-language HTML/CSV report
      showing repo lifecycle states, blockers, next actions, and top
      recommended work. *(state: planned — Phase 7)*
- [ ] Update Help and reference documentation so the north-star workflow is
      explicit: assess collection, standardize repos, create or repair
      roadmap, rank work, refine prompt, dispatch, monitor, validate, and
      report progress. *(state: planned — Phase 7)*

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

| Phase                               | Scope                                                                                                                                        | Status                               |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Phase 1: Assessment foundation            | `RepoLifecycleState`, `Portfolio.Assessment.ps1`, `repo-structure-standards.json`, `GET /api/portfolio/assessment`, GitHub-vs-local coverage | **done — smoke-tested** (2026-04-25) |
| Phase 2: Value ranking                    | `Portfolio.ValueScorer.ps1`, `value-scoring.json`, value score on each pending item in the assessment response                               | **done — smoke-tested** (2026-04-26) |
| Phase 3A: Ordered portfolio index         | `output/index/repos.index.json`, normalized repo identity, scan artifacts under `output/index/scans/`                                        | **done — smoke-tested** (2026-05-11) |
| Phase 3B: GitHub metadata enrichment      | PR detail, Pages status/link, latest Actions status, created/updated timestamps                                                              | **next active target**               |
| Phase 3C: Dashboard signal model          | Portfolio Mission panel, Documentation Health, dashboard badges, index-backed assessment display                                             | planned                              |
| Phase 4: Work Queue value display         | Value score column + rationale tooltip in `WorkQueueView.tsx`; rerank by value                                                               | planned                              |
| Phase 5: Expanded evaluator               | Feature/modernization/security/test/doc opportunity findings beyond hardening                                                                 | planned                              |
| Phase 6: Prompt context packet foundation | Backend packet that combines README, ROADMAP, assessment, value rationale, and constraints for later prompt refinement                       | planned                              |
| Phase 7: Collection report + docs         | `Portfolio.Report.ps1` HTML/CSV; update `HelpModal.tsx` and `docs/reference/` for the north-star workflow                                   | planned                              |

---

## 6. Future Releases

### Release 1.2 — Enhanced Portfolio Intelligence

> **Note.** This release was previously tracked only under "Immediate Next
> Focus" at the bottom of the document; it has been promoted to its proper
> position. Backend features were shipped during the Release 1.1 cycle;
> the remaining work is frontend + smoke coverage.

**Goal:** Surface the execution-throughput, dependency-graph, and tag
signals already produced by the backend so operators can see them in the
dashboard, and close the smoke-coverage gap for the Release 1.2 API
routes.

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
- [ ] Execution throughput metrics card in the dashboard (consumes
      `GET /api/execution/metrics`). *(state: planned)*
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

### Release 1.8 — Operations Workspace and Prompt Refinement

**Goal:** Add a repo-specific Operations workspace that turns portfolio
signals into actionable execution context. Operators can select a repo,
inspect its dashboard signals, review README and ROADMAP context, compose a
coding-agent prompt, refine it, and prepare it for dispatch.

#### Product outcomes

- Operators can move from portfolio overview to repo-specific detail
  without leaving the app.
- Every selected repo shows documentation health, roadmap maturity, dirty
  worktree state, open PRs, Actions state, GitHub Pages status, and
  recommended next action.
- Operators can generate a structured coding-agent prompt from repo
  context instead of hand-writing prompts from scratch.
- Prompt refinement remains operator-reviewed and preview-first.

#### Engineering milestones

- [ ] Add Operations tab with repo selection table for indexed portfolio
      records. *(state: planned)*
- [ ] Add repo detail workspace showing local path, GitHub URL, default branch,
      current branch, dirty state, last commit, created date, updated date,
      README score, ROADMAP score, lifecycle state, and recommended next
      action. *(state: planned)*
- [ ] Add README and ROADMAP viewers inside the repo detail workspace.
      *(state: planned)*
- [ ] Add GitHub panel showing open PRs, latest Actions status, and
      GitHub Pages status/link. *(state: planned)*
- [ ] Add audit findings panel showing README findings, ROADMAP findings,
      structure findings, and dispatch blockers. *(state: planned)*
- [ ] Add Prompt Builder panel that composes a coding-agent prompt from
      selected roadmap item, README summary, ROADMAP context, audit
      findings, repo constraints, acceptance criteria, and value rationale.
      *(state: planned)*
- [ ] Add editable prompt preview before dispatch. *(state: planned)*
- [ ] Add custom operator instruction field that appends additional
      constraints or direction to the generated prompt. *(state: planned)*
- [ ] Store prompt history per repo, including generated previews, edits,
      and dispatch records. *(state: planned)*
- [ ] Add `GET /api/operations/repos` route that returns the indexed repo
      list optimized for the Operations tab. *(state: planned)*
- [ ] Add `GET /api/operations/repos/{repoId}` route that returns full
      repo detail, documentation context, GitHub metadata, audit findings,
      and dispatch context. *(state: planned)*
- [ ] Add `POST /api/operations/prompt/preview` route that returns the
      generated prompt, source context summary, and warnings.
      *(state: planned)*

#### Acceptance criteria

- Selecting a repo in Operations opens a complete repo-specific detail
  workspace.
- The repo detail view shows the same core metrics as the main dashboard,
  but scoped to one repo.
- The prompt builder produces a complete coding-agent prompt from README,
  ROADMAP, audit findings, and selected work item.
- The operator can edit the generated prompt before dispatch.
- No prompt is sent to any agent without explicit operator action.

#### Out of scope

- AI-generated README/ROADMAP improvement cycles; handled in Release 1.9.
- Agent-run monitoring and merge readiness; handled in Release 2.0.

---

### Release 1.9 — AI Documentation Improvement Cycles

**Goal:** Add provider-backed, preview-first AI improvement cycles for
README.md and ROADMAP.md so operators can repair weak documentation,
standardize repos, and improve dispatch readiness without direct
unreviewed file mutation.

#### Product outcomes

- Operators can compare current README/ROADMAP content against a proposed
  improved version.
- The app explains what changed and why.
- Operators can run multiple improvement cycles using built-in templates or
  a custom improvement prompt.
- OpenAI and Anthropic can be supported through provider adapters.

#### Engineering milestones

- [ ] Define AI provider adapter contract for documentation improvement.
      *(state: planned)*
- [ ] Add OpenAI provider adapter using configured environment variable or
      settings path. *(state: planned)*
- [ ] Add Anthropic provider adapter using configured environment variable
      or settings path. *(state: planned)*
- [ ] Add built-in README improvement templates: product README,
      developer/operator README, open-source README, and portfolio showcase
      README. *(state: planned)*
- [ ] Add built-in ROADMAP improvement templates: release-oriented roadmap,
      roadmap contract format, agent-dispatch-ready roadmap, and
      recovery/repair roadmap. *(state: planned)*
- [ ] Add `POST /api/ai/docs/improve/preview` route that returns current
      content, proposed content, change summary, estimated score movement,
      and warnings. *(state: planned)*
- [ ] Add side-by-side diff viewer for current vs proposed README/ROADMAP.
      *(state: planned)*
- [ ] Add improvement cycle history per repo. *(state: planned)*
- [ ] Add custom improvement prompt field for additional refinement cycles.
      *(state: planned)*
- [ ] Add explicit apply action for accepted changes with backup creation
      and restore metadata. *(state: planned)*
- [ ] Add `POST /api/ai/docs/improve/apply` route that writes accepted
      changes only after explicit operator approval. *(state: planned)*
- [ ] Add `GET /api/ai/docs/improve/history` route for repo-specific
      improvement history. *(state: planned)*

#### Acceptance criteria

- A README improvement preview shows current content, proposed content,
  and change summary side by side.
- A ROADMAP improvement preview shows current content, proposed content,
  and change summary side by side.
- The operator can run an additional cycle using a custom improvement
  prompt.
- No README.md or ROADMAP.md file is modified without explicit apply.
- AI-provider failures degrade to clear operator-facing errors.

#### Out of scope

- Automatic PR creation for documentation repairs; deferred to Release 2.4.
- Autonomous documentation rewriting without human approval.

---

### Release 2.0 — Agent Run Monitoring and Actions-Gated Merge Readiness

**Goal:** Monitor coding-agent execution after dispatch, associate agent
work with branches and pull requests, track GitHub Actions, and present a
merge-readiness signal that requires successful validation before merge.

#### Product outcomes

- Operators can see whether an agent task is active, completed, failed, or
  blocked.
- Agent-created PRs are associated with the original repo, roadmap item,
  prompt, and dispatch record.
- GitHub Actions status is part of the execution workflow.
- The app blocks merge-readiness when validation evidence is missing.

#### Engineering milestones

- [ ] Add agent-run ledger model with runId, repoId, promptId, selected
      roadmap item, provider/tool, branch, PR URL, status, createdAt,
      updatedAt, and outcome. *(state: planned)*
- [ ] Add `GET /api/agent-runs` route for active, completed, failed, and
      blocked runs. *(state: planned)*
- [ ] Add `GET /api/agent-runs/{runId}` route with full run detail.
      *(state: planned)*
- [ ] Add `POST /api/agent-runs/{runId}/refresh` route that refreshes
      branch, PR, and Actions state. *(state: planned)*
- [ ] Add operator-visible Actions refresh control in the Operations
      workspace and run detail views. *(state: planned)*
- [ ] Associate Copilot/agent-created branches and PRs with dispatch
      records using branch naming, PR metadata, or stored task fingerprints.
      *(state: planned)*
- [ ] Add merge-readiness evaluator. *(state: planned)*
- [ ] Block merge readiness when the repo has a dirty worktree, no PR,
      failing or pending Actions, merge conflicts, missing validation
      evidence, or unresolved audit blockers. *(state: planned)*
- [ ] Add Actions-gated status panel to Operations tab. *(state: planned)*
- [ ] Add operator-controlled merge action only after merge readiness is
      satisfied. *(state: planned)*
- [ ] Add `GET /api/merge-readiness/{repoId}` route. *(state: planned)*
- [ ] Add `POST /api/merge-readiness/{repoId}/evaluate` route.
      *(state: planned)*

#### Acceptance criteria

- The app shows active, completed, failed, and blocked agent runs.
- A dispatched task can be traced to its prompt, repo, branch, PR, and
  Actions result.
- Merge readiness is false while Actions are failing or pending.
- Merge readiness is false when the PR has conflicts or no validation
  evidence.
- The app never auto-merges without explicit operator action.

#### Out of scope

- Fully autonomous agent execution.
- Multi-agent scheduling and distributed work claiming; deferred to 2.4.

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

- [ ] Add SQLite dependency detection and initialize `output/app.db` with
      execution, maturity, ops-log, portfolio-index, repo-signal,
      differential-scan, and merge-readiness tables. *(state: planned)*
- [ ] Migrate execution ledger and ops log reads/writes from JSON files to
      parameterized SQL queries, keeping JSON export only as a debugging
      artifact. *(state: planned)*
- [ ] Persist maturity snapshots, portfolio index history, README score,
      ROADMAP score, Documentation Health, GitHub metadata, and
      merge-readiness snapshots over time. *(state: planned)*
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

#### Engineering milestones

- [ ] Add portfolio trend and repo-row sparkline visualizations backed by
      maturity history and `GET /api/portfolio/trend`. *(state: planned)*
- [ ] Add weekly digest generation plus scheduled webhook delivery for
      portfolio KPIs and top candidate repos. *(state: planned)*
- [ ] Package a `roadmap-audit-action` GitHub Action that runs the
      roadmap auditor and posts PR check results. *(state: planned)*
- [ ] Extract the roadmap contract standard into a standalone,
      publishable spec directory. *(state: planned)*
- [ ] Add portfolio and per-repo SVG badge routes for maturity display.
      *(state: planned)*
- [ ] Smoke test the trend route response shape for daily rollups.
      *(state: planned)*

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

# GitHub Repo Management — Active Execution Roadmap

> **Status:** Active
> **Active release:** **Release 1.7.5 — Portfolio Mission Alignment and Value-Ranked Work Planning** (Phase 2 shipped; Phase 3 next)
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
highest-value incomplete roadmap work, and prepares reviewed GitHub Copilot
Agent prompts.

The **north-star operator workflow** every release should serve is:

> scan portfolio → classify every repo → show lifecycle state → identify
> blockers → repair README/roadmap/structure → rank highest-value next
> work → refine Copilot prompt → dispatch → validate result → update
> roadmap / report progress

For the full thesis, ten core questions, principles, risks, and guardrails,
see
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).

---

## 3. Implementation-State Vocabulary

Every milestone in this roadmap should carry one of these states. A `[x]`
checkbox alone is not enough — it does not distinguish "backend exists" from
"end-to-end working."

| State | Meaning |
|---|---|
| `planned` | Proposed; no code yet |
| `scaffolded` | Files / route / UI exist but stubbed or returns mock data |
| `backend-complete` | Server-side logic implemented; no UI consumer yet |
| `ui-connected` | Frontend wires through to live backend; manual smoke ok |
| `smoke-tested` | Automated module / api-host smoke covers it |
| `operator-verified` | Confirmed working end-to-end against the live workspace |
| `done` | All four of: backend-complete, ui-connected, smoke-tested, operator-verified |

Render the state inline on each milestone in italics, e.g.:

```markdown
- [x] Add `GET /api/portfolio/assessment` route. *(state: smoke-tested)*
```

---

## 4. Release Index

| Version | Title | Status |
|---|---|---|
| 0.4 | Roadmap Intelligence Foundation | `done` — see [completed-releases.md](docs/history/completed-releases.md#release-04--roadmap-intelligence-foundation) |
| 0.5 | Documentation Audit & Dispatch Readiness | `done` — see archive |
| 0.6 | Copilot Task Packaging & Preview Workflow | `done` — see archive |
| 0.7 | Roadmap Contract Standard Foundation | `done` — see archive |
| 0.8 | Roadmap Contract Audit & Maturity Scoring | `done` — see archive |
| 0.9 | Roadmap Repair Preview & Standardization Workflow | `done` — see archive |
| 1.0 | Two-Lane Execution Queue | `done` — see archive |
| 1.1 | Standardization, Guardrails, and Continuous Improvement | `done` — see archive |
| **1.2** | **Enhanced Portfolio Intelligence** | **mixed** — backend `smoke-tested`; UI `planned` |
| 1.3 | Production Frontend Build | `done` |
| 1.4 | Repo Evaluation and Cross-Platform Deployment *(formerly: Cross-Platform and Containerized Deployment)* | `done` |
| 1.5 | Copilot-Assisted README Generation | `done` |
| 1.6 | Roadmap-Driven Release Dispatch to GitHub Copilot | `done` |
| 1.7 | Repo Git Status Detail | `done` |
| **1.7.5** | **Portfolio Mission Alignment and Value-Ranked Work Planning** | **active — Phase 2 done; Phase 3 next** |
| 1.8 | API Authentication and Network Security | `planned` |
| 1.9 | Persistent Data Layer | `planned` |
| 2.0 | Complete the Doc Review Pipeline | `planned` |
| 2.1 | Guided Onboarding and GitHub App Integration | `planned` |
| 2.2 | Portfolio Analytics, Trend Visualization, and Distribution | `planned` |
| 2.3 | Agent Integration Protocol and AI Repair Loop | `planned` |

> **Note on `.5` numbering.** Release 1.7.5 is a deliberate course-correction
> release between 1.7 and 1.8 to re-center the product on its primary
> mission before adding network/security or persistence work. The `.5`
> pattern should be reserved for similar course corrections; default new
> work to integer minor releases.

---

## 5. Active Release

### Release 1.7.5 — Portfolio Mission Alignment and Value-Ranked Work Planning

**Status:** active. Phase 1 shipped 2026-04-25; Phase 2 shipped
2026-04-26; Phase 3 is the next execution target.

**Goal:** Re-center the product around its primary mission: assess the full
local and GitHub repository collection, standardize repo readiness, create
or repair missing roadmap contracts, rank the highest-value incomplete
roadmap work, and prepare clear Copilot Agent prompts while reporting
collection status in plain language.

#### Product outcomes

- Operators can see the overall state of the full repository collection
  without opening individual repos.
- Every repo has a visible lifecycle state: discovered, needs structure,
  needs README, needs roadmap, needs roadmap repair, ready for work queue,
  running, completed, or monitored.
- Repos without a roadmap have a guided path to create one from actual repo
  structure, documentation gaps, test coverage, and likely high-value work.
- Incomplete roadmap items are ranked by value, not just by file order.
- A Copilot Agent prompt can be reviewed and refined with clear context,
  constraints, value rationale, and acceptance criteria before dispatch.
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
- [ ] Add a Portfolio Mission panel to the dashboard summarizing collection
      state: total repos, local-only, GitHub-only, linked local+GitHub,
      missing roadmap, weak roadmap, missing README, ready, running,
      blocked, and completed. *(state: planned — Phase 3)*
- [ ] Expand repo evaluation for missing roadmaps beyond hardening checks:
      include likely feature opportunities, modernization work,
      test/documentation improvements, security posture, and user-visible
      value. *(state: planned — Phase 5)*
- [x] Add a value scoring model for incomplete roadmap items using impact,
      unblock potential, risk reduction, repo maturity, effort estimate,
      dependency reduction, and recency. *(state: smoke-tested)* —
      backend module
      [`Portfolio.ValueScorer.ps1`](backend/modules/portfolio/Portfolio.ValueScorer.ps1),
      scoring config [`value-scoring.json`](backend/config/value-scoring.json),
      and additive `pendingItems` / `topValueItem` fields in
      `/api/portfolio/assessment`.
- [ ] Show value score and rationale in Work Queue so the operator can
      understand why one repo or roadmap item is recommended before
      another. *(state: planned — Phase 4)*
- [ ] Add a Prompt Refinement view that composes the Copilot Agent prompt
      from repo assessment, selected roadmap item, acceptance criteria,
      constraints, relevant docs, and value rationale; allow final operator
      edits before dispatch. *(state: planned — Phase 6)*
- [ ] Add Collection Status Report export: a plain-language HTML/CSV report
      showing repo lifecycle states, blockers, next actions, and top
      recommended work. *(state: planned — Phase 7)*
- [ ] Update Help and reference documentation so the north-star workflow is
      explicit: assess collection, standardize repos, create or repair
      roadmap, rank work, refine prompt, dispatch, report progress.
      *(state: planned — Phase 7)*

#### Acceptance criteria

- Every repo shown in the dashboard has one lifecycle state and one
  recommended next action.
- A repo with no roadmap can be evaluated into a roadmap draft that
  includes both hardening work and value-oriented feature/work suggestions.
- Work Queue ranking explains why the top recommended item is valuable.
- The prompt refinement screen shows the selected work item, repo context,
  constraints, acceptance criteria, and value rationale before dispatch.
- The collection report can answer: "What is the state of my repo
  collection, and what should I work on next?"

#### Out of scope

- API authentication and network hardening (Release 1.8).
- SQLite persistence and historical trend storage (Release 1.9).
- GitHub App OAuth setup (Release 2.1).
- Fully autonomous work dispatch without operator review.

#### Phase plan (within this release)

| Phase | Scope | Status |
|---|---|---|
| 1. Assessment foundation | `RepoLifecycleState`, `Portfolio.Assessment.ps1`, `repo-structure-standards.json`, `GET /api/portfolio/assessment`, GitHub-vs-local coverage | **done — smoke-tested** (2026-04-25) |
| 2. Value ranking | `Portfolio.ValueScorer.ps1`, `value-scoring.json`, value score on each pending item in the assessment response | **done — smoke-tested** (2026-04-26) |
| 3. Portfolio Mission panel | New `PortfolioMissionPanel.tsx` consuming `/api/portfolio/assessment` | **next active target** |
| 4. Work Queue value display | Value score column + rationale tooltip in `WorkQueueView.tsx`; rerank by value | planned |
| 5. Expanded evaluator | Feature/modernization/security/test/doc opportunity findings beyond hardening | planned |
| 6. Prompt refinement | Extend `RoadmapDispatchModal.tsx` with Value Rationale + Assessment Context | planned |
| 7. Collection report + docs | `Portfolio.Report.ps1` HTML/CSV; update `HelpModal.tsx` and `docs/reference/` for the north-star workflow | planned |

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

- Historical trend visualization (deferred to Release 2.2).
- Charting library integration beyond a single SVG sparkline.

---

### Release 1.8 — API Authentication and Network Security

**Goal:** Harden the API host so it can be safely exposed beyond
`127.0.0.1` without risk of unauthenticated access or information
disclosure.

#### Product outcomes

- The API requires a valid token for all non-health routes.
- The application can be run on a local network and shared with teammates
  without exposing an open, unauthenticated API.
- Security-conscious operators can configure HTTPS for local or network
  deployment.

#### Engineering milestones

- [ ] Add `auth.apiKey` field to `settings.json` schema; on startup, if
      set, all routes except `/health/live` and `/health/ready` require
      `Authorization: Bearer <key>` or `X-Api-Key: <key>`; return 401 on
      mismatch. *(state: planned)*
- [ ] Add `auth.apiKeyEnvVar` alternative so the key can be injected via
      environment variable without storing it in `settings.json`.
      *(state: planned)*
- [ ] Generate a random API key on first startup if `auth.apiKey` and
      `auth.apiKeyEnvVar` are both unset; write the generated key to
      `backend/modules/output/runtime/api-key.txt` with a startup log
      message pointing to it. *(state: planned)*
- [ ] Add CORS configuration to `settings.json`: `cors.allowedOrigins`
      array (default `["http://localhost:7000", "http://127.0.0.1:7000"]`);
      replace the current `Access-Control-Allow-Origin: *` with the
      configured origins. *(state: planned)*
- [ ] Implement per-IP request rate limiting: track request counts in a
      script-scoped hashtable; return 429 with `Retry-After` header when
      any single IP exceeds `security.maxRequestsPerMinute` (default 300).
      *(state: planned)*
- [ ] Add `network.bindAddress` to `settings.json` (default `127.0.0.1`);
      validate that non-loopback bind requires `auth.apiKey` or
      `auth.apiKeyEnvVar` to be set, and refuse to start without it.
      *(state: planned)*
- [ ] Implement TLS option: if `tls.certPath` and `tls.keyPath` are set in
      `settings.json`, wrap the `TcpListener` with `SslStream` using the
      provided certificate; serve HTTPS on the configured port.
      *(state: planned)*
- [ ] Add `GET /api/auth/verify` route that returns 200 `{ valid: true }`
      for authenticated requests; used by frontend to confirm auth state on
      load. *(state: planned)*
- [ ] Frontend: read `VITE_API_KEY` from build env or prompt on first load
      if `/api/auth/verify` returns 401; store in `sessionStorage`; include
      in all API requests as `X-Api-Key` header. *(state: planned)*
- [ ] Smoke test: unauthenticated `GET /api/status` returns 401 when
      `auth.apiKey` is configured; authenticated request returns 200.
      *(state: planned)*

#### Acceptance criteria

- An operator who sets `auth.apiKey` and `network.bindAddress: 0.0.0.0`
  can share the dashboard URL with a teammate on the same network and
  require authentication.
- The application refuses to bind to a non-loopback address without auth
  configured.
- All existing smoke tests pass with a configured API key.

#### Out of scope

- OAuth / GitHub App authentication (deferred to Release 2.1).
- Role-based access control.

---

### Release 1.9 — Persistent Data Layer

**Goal:** Replace JSON file storage with a SQLite database for the
execution ledger, maturity history, and operations log so the application
is reliable at scale and supports time-series queries.

#### Product outcomes

- The execution ledger does not corrupt or lose history when multiple
  operations happen in quick succession.
- Maturity scores are stored over time, enabling trend charts in the
  dashboard.
- The operations log is queryable by time range, level, and keyword
  without reading the entire file.
- The application handles portfolios of 200+ repos without file I/O
  degradation.

#### Engineering milestones

- [ ] Add `System.Data.SQLite` via the `PSSQLite` PowerShell module or
      direct .NET assembly; add dependency check to startup with a clear
      error message if unavailable. *(state: planned)*
- [ ] Create `Initialize-AppDatabase` function that creates `output/app.db`
      with schema: `execution_entries` table, `execution_history` table,
      `maturity_snapshots` table (repoName, score, level, capturedAt),
      `ops_log` table (ts, level, msg). *(state: planned)*
- [ ] Migrate `Execution.Ledger.ps1` to read/write `execution_entries` and
      `execution_history` via parameterized SQL queries; remove
      `execution-ledger.json` write path. *(state: planned)*
- [ ] Add daily maturity snapshot write: after every roadmap audit scan,
      insert a row into `maturity_snapshots` for each repo with its
      current score and level. *(state: planned)*
- [ ] Migrate `Write-HostLog` JSONL append to an INSERT into `ops_log`;
      keep `Invoke-TrimOpsLog` as a fallback for non-database mode;
      `GET /api/log/tail` queries `ops_log` with `ORDER BY ts DESC LIMIT ?`.
      *(state: planned)*
- [ ] Add `GET /api/roadmap/maturity-history` route: accepts
      `?repoName=&days=30` query params; queries `maturity_snapshots`;
      returns array of `{ capturedAt, score, level }` for charting.
      *(state: planned)*
- [ ] Add maturity trend sparkline to the repository grid row: fetch last
      14 days of snapshots and render a 14-point SVG sparkline.
      *(state: planned)*
- [ ] Add `GET /api/portfolio/trend` route: returns aggregate portfolio
      stats by day — count of repos at each maturity level — for the last
      90 days. *(state: planned)*
- [ ] Write `Invoke-DatabaseMigration.ps1` that detects the existing JSON
      ledger file and imports its entries into the SQLite database on
      first run; skips if DB already populated. *(state: planned)*
- [ ] Keep JSON file output as an optional export: `POST /api/export`
      still writes JSON/CSV artifacts; the source of truth is SQLite.
      *(state: planned)*
- [ ] Smoke test: write 100 execution history records via the ledger API,
      read them back via `GET /api/execution/metrics`; assert counts are
      correct. *(state: planned)*

#### Acceptance criteria

- The execution ledger survives a concurrent assign + complete call
  without data loss.
- `GET /api/roadmap/maturity-history?repoName=X&days=30` returns an
  ordered array of score snapshots.
- The ops log is queryable by time range via
  `GET /api/log/tail?since=<ISO>&level=ERROR`.
- All existing smoke tests pass against the SQLite backend.

#### Out of scope

- PostgreSQL or remote database support.
- Multi-writer / multi-instance database access.

---

### Release 2.0 — Complete the Doc Review Pipeline

**Goal:** Deliver the Validate and Complete modes of the documentation
review pipeline that are currently scaffolded but not implemented, and
implement the Clone and Archive UI actions.

#### Product outcomes

- Operators can validate whether a documentation improvement was actually
  applied correctly.
- Operators can mark a documentation review cycle as complete and record
  the outcome.
- Repositories can be cloned from GitHub into a configured local workspace
  from the UI.
- Stale or archived repositories can be marked as inactive so they exit
  the work queue.

#### Engineering milestones

- [ ] Implement `Validate` mode in `Invoke-DocReviewExecution.ps1`: re-run
      the doc standards audit against the repo after a Copilot task has
      run; compare findings before and after; return a structured diff of
      resolved vs remaining findings. *(state: scaffolded)*
- [ ] Implement `Complete` mode in `Invoke-DocReviewExecution.ps1`: accept
      a `--Outcome` parameter (`improved`, `skipped`, `deferred`); write a
      completion record to `output/docreview/history.jsonl` with repoName,
      outcome, completedAt, and finding summary. *(state: scaffolded)*
- [ ] Add `POST /api/docreview/validate` route that calls Validate mode
      for a given repo and returns before/after finding comparison.
      *(state: planned)*
- [ ] Add `POST /api/docreview/complete` route that calls Complete mode
      and returns the written history record. *(state: planned)*
- [ ] Add `GET /api/docreview/history` route that reads
      `output/docreview/history.jsonl` and returns the last 100 completion
      records. *(state: planned)*
- [ ] Implement Clone action: `POST /api/clone` accepts
      `{ repoFullName, targetRoot }`, validates `targetRoot` is in
      `inventory.localRoots`, runs `gh repo clone {repoFullName}
      {targetPath}`, returns the local path; enable Clone button in
      `ActionBar.tsx` and set `cloneImplemented = true`.
      *(state: scaffolded)*
- [ ] Implement Archive action: `POST /api/archive` accepts
      `{ repoName }`, writes an `archived: true` flag to the repo's
      status cache entry, excludes it from the work queue and dispatch
      queue; enable Archive button in `ActionBar.tsx` and set
      `archiveImplemented = true`. *(state: scaffolded)*
- [ ] Add `GET /api/status?includeArchived=true` filter support so
      archived repos remain visible in a dedicated "Archived" view but
      are excluded from default scans. *(state: planned)*
- [ ] Add DocReview history tab to `DocReviewModal` showing completion
      records from `GET /api/docreview/history`. *(state: planned)*
- [ ] Smoke test: call Validate mode on a repo that has had a doc
      standardization applied; assert the before/after diff contains at
      least one resolved finding. *(state: planned)*

#### Acceptance criteria

- Validate mode returns a structured before/after finding comparison with
  `resolvedCount` and `remainingCount`.
- Complete mode writes a history record that is retrievable via
  `GET /api/docreview/history`.
- Clone button clones a repo and triggers a status cache refresh.
- Archive button removes the repo from the active work queue without
  deleting it from disk.

#### Out of scope

- Bulk archive of multiple repos in one action.
- Restoring archived repos from the UI (use `settings.json` edit for now).

---

### Release 2.1 — Guided Onboarding and GitHub App Integration

**Goal:** Replace the manual PAT + settings.json setup with a guided
first-run experience and a proper GitHub App OAuth flow so any engineer
can go from zero to running in under five minutes.

#### Product outcomes

- A first-time user can complete setup without reading any documentation.
- The application authenticates with GitHub via OAuth rather than a
  Personal Access Token.
- The setup flow validates each prerequisite before proceeding and
  surfaces a clear error for any failure.

#### Engineering milestones

- [ ] Add startup detection: if `backend/config/settings.json` is missing
      or has `schemaVersion` absent, redirect all non-health API routes to
      `GET /setup/status` which returns the list of incomplete setup
      steps. *(state: planned)*
- [ ] Implement `GET /setup/status` route: checks prerequisites in order —
      `pwsh` version ≥ 7.0, Node.js version ≥ 18, `gh` CLI present,
      `GITHUB_TOKEN` or GitHub App token set, at least one
      `inventory.localRoots` path exists and is readable; returns array of
      `{ step, status, message }`. *(state: planned)*
- [ ] Implement `POST /setup/config` route: accepts partial settings
      object, merges with defaults, validates, and writes
      `backend/config/settings.json`; returns validation errors for each
      invalid field. *(state: planned)*
- [ ] Build `SetupWizard` React component: four-step flow —
      (1) prerequisites check with per-item status badges,
      (2) local repo roots picker with directory browser,
      (3) GitHub authentication method selection,
      (4) first scan confirmation; shown when `GET /setup/status` reports
      incomplete steps. *(state: planned)*
- [ ] Implement `GET /setup/prerequisites` route: returns per-tool version
      check results for `pwsh`, `node`, `npm`, `git`, `gh`; includes
      download URL for each missing tool. *(state: planned)*
- [ ] Register a GitHub App (owner: application developer); add
      `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY_PATH`, and
      `GITHUB_APP_INSTALLATION_ID` to `settings.json` schema as
      alternatives to `secrets.gitHubTokenEnvVar`. *(state: planned)*
- [ ] Add `GET /auth/github/callback` route: receives OAuth code from
      GitHub, exchanges for installation token via GitHub App API, stores
      token in `backend/modules/output/runtime/github-token.json` with
      expiry; refresh automatically when expired. *(state: planned)*
- [ ] Add `GET /auth/status` route: returns
      `{ method: "pat" | "app" | "none", authenticated: bool, scopes: [],
      rateLimitRemaining: int }`. *(state: planned)*
- [ ] Update all GitHub API calls in the API host to read the token from
      the App token file first, falling back to the PAT env var, then to
      unauthenticated. *(state: planned)*
- [ ] Smoke test: run `GET /setup/status` against a fresh
      `settings.json`-less environment; assert all steps return
      `incomplete`; post a valid config; assert all steps return
      `complete`. *(state: planned)*

#### Acceptance criteria

- A fresh install with no `settings.json` redirects the user to the setup
  wizard on first browser open.
- Completing the wizard writes a valid `settings.json` and triggers the
  first repo scan without manual steps.
- GitHub App authentication produces a working token that is refreshed
  automatically before expiry.

#### Out of scope

- GitHub Marketplace listing (deferred to Release 2.2).
- Multi-installation GitHub App support (one installation per running
  instance).

---

### Release 2.2 — Portfolio Analytics, Trend Visualization, and Distribution

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

- [ ] Add `PortfolioTrendChart` React component that fetches
      `GET /api/portfolio/trend` and renders a stacked area chart (L0–L4
      counts per day for last 90 days) using a lightweight charting
      library (e.g., Recharts). *(state: planned)*
- [ ] Add `MaturitySparkline` component in the repo grid row: fetches
      `GET /api/roadmap/maturity-history?repoName=X&days=14` and renders a
      14-point SVG path showing score trend. *(state: planned)*
- [ ] Add `POST /api/digest/send` route: computes portfolio KPIs (total
      repos, count per maturity level, repos that improved this week,
      repos that regressed, top 3 dispatch-ready repos) and fires
      `Send-NotificationEvent` with `event: digest.weekly` and the
      computed payload. *(state: planned)*
- [ ] Add `scanning.weeklyDigestWebhook` to `settings.json` schema; when
      set, `Register-ScheduledTasks.Template.ps1` registers a weekly Task
      Scheduler job that calls `POST /api/digest/send`. *(state: planned)*
- [ ] Write `action.yml` for a GitHub Action named
      `roadmap-audit-action`: accepts inputs `roadmap-path`,
      `min-maturity-level`; calls the roadmap contract auditor PowerShell
      module; outputs `maturity-score`, `maturity-level`,
      `findings-count`; posts a check run to the PR with the audit
      result. *(state: planned)*
- [ ] Extract `standards/roadmap/` into a standalone
      `roadmap-contract-spec` directory with its own `README.md`,
      `SPEC.md`, version file (`spec-version: 1.0`), and MIT license;
      structure it so it can be published as a separate GitHub
      repository. *(state: planned)*
- [ ] Add `GET /api/portfolio/badge` route: returns an SVG badge showing
      the portfolio's average maturity score (e.g.,
      `roadmap maturity | L2.8`) suitable for embedding in a README.
      *(state: planned)*
- [ ] Add `GET /api/roadmap/badge/{repoName}` route: returns per-repo SVG
      badge showing current maturity level and score. *(state: planned)*
- [ ] Smoke test: `GET /api/portfolio/trend?days=7` returns an array of 7
      daily entries each with `{ date, l0, l1, l2, l3, l4 }`.
      *(state: planned)*

#### Acceptance criteria

- The portfolio trend chart renders in the dashboard and shows at least 7
  days of history after 7 days of operation.
- `POST /api/digest/send` fires a webhook payload that includes
  `totalRepos`, `byLevel`, `improvedThisWeek`, and `topCandidates`.
- The GitHub Action runs in a GitHub-hosted runner, audits a roadmap
  file, and posts a passing or failing check run.
- The roadmap contract spec directory is self-contained and can be
  copied to a new repository without modification.

#### Out of scope

- GitHub Marketplace listing for the GitHub Action (requires manual
  submission after release).
- Email digest (webhook-only for this release).

---

### Release 2.3 — Agent Integration Protocol and AI Repair Loop

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
- The application becomes infrastructure that AI tools depend on, not
  just a dashboard humans look at.

#### Engineering milestones

- [ ] Define and publish `GET /api/v1/agent/readiness/{repoName}` route
      with stable contract: returns
      `{ schemaVersion: "1.0", repoName, dispatchSafe: bool, maturityLevel,
      maturityScore, selectedTask: { text, section, tags }, constraints:
      [], auditFindings: [], nextSteps: [] }`; version the contract with a
      `schemaVersion` field; treat as a stable public API.
      *(state: planned)*
- [ ] Add `GET /api/v1/agent/queue` route: returns the top 5
      dispatch-ready repos as an ordered list with per-repo readiness
      packets; designed for agents that self-assign rather than being
      told which repo to work on. *(state: planned)*
- [ ] Add `POST /api/v1/agent/claim/{repoName}` route: atomically marks a
      repo as `running` in the execution ledger and returns the full task
      packet; rejects if already claimed. *(state: planned)*
- [ ] Add `POST /api/v1/agent/complete/{repoName}` route: accepts
      `{ runId, outcome, summary }`; marks the task complete; triggers a
      completion-preview diff for the roadmap. *(state: planned)*
- [ ] Implement `Invoke-AiRepairSubmission` function: takes a roadmap
      repair preview, creates a feature branch in the repo via `gh`,
      commits the proposed content, and opens a PR with the diff and
      audit finding context as the PR body; never pushes to the default
      branch directly. *(state: planned)*
- [ ] Add `POST /api/roadmap/repair/submit-pr` route: calls
      `Invoke-AiRepairSubmission` with the current repair preview for the
      given repo; returns the PR URL. *(state: planned)*
- [ ] Implement `Invoke-AiReadmeSubmission` function: equivalent to
      `Invoke-AiRepairSubmission` but for README standardization
      previews. *(state: planned)*
- [ ] Add `POST /api/readme/standardize/submit-pr` route: calls
      `Invoke-AiReadmeSubmission`; returns the PR URL. *(state: planned)*
- [ ] Add `SubmitPR` button to `RoadmapRepairModal` and
      `ReadmeStandardizationModal` that calls the respective submit-pr
      routes. *(state: planned)*
- [ ] Publish OpenAPI 3.1 spec for all `/api/v1/agent/*` routes as
      `docs/reference/agent-api.yaml`. *(state: planned)*
- [ ] Smoke test: call `GET /api/v1/agent/readiness/{repoName}` for a
      repo with a known maturity level; assert `schemaVersion`,
      `dispatchSafe`, `maturityLevel`, and `selectedTask.text` are all
      present. *(state: planned)*

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
- [ ] Expand smoke coverage around launcher, health, roadmap parsing,
      contract audit, repair preview, docs-audit, and task history flows.
      *(state: planned)*
- [ ] Add incremental scan mode for large repo roots (skip unchanged
      directories where safe). *(state: planned)*
- [ ] Improve cache invalidation and scan performance for large local
      inventories. *(state: planned)*
- [ ] Keep structured logs rich enough to diagnose scan, parse, normalize,
      audit, preview, apply, and start failures. *(state: planned)*
- [ ] Continue improving operator-facing documentation as workflows
      evolve. *(state: planned)*
- [ ] Keep rule packs and schemas data-driven where practical so standards
      can evolve without broad code rewrites. *(state: planned)*

---

## 8. Risks and Guardrails

The full list lives in
[`docs/product/portfolio-execution-console.md`](docs/product/portfolio-execution-console.md).
Headline guardrails for the active release:

- Do not auto-dispatch tasks without a visible readiness model.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Preserve genuine completion history when rewriting roadmaps.
- Enforce L3+ roadmap maturity before any Copilot dispatch.

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

- all checklist items for that release are truly implemented or
  explicitly blocked
- UI elements are connected to real behavior rather than placeholders
- affected docs are updated where workflow or product behavior changed
- logging and error handling are sufficient to diagnose failures
- later releases were not partially started just to create the illusion
  of momentum

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
sections, duplicate headings, missing Release 1.2 coverage, stale
"Immediate Next Focus" references, completed-history dominance, and other
obvious execution-roadmap issues. Optional outputs:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md `
  -JsonOut ./output/roadmap-structure-findings.json `
  -CsvOut ./output/roadmap-structure-findings.csv
```

CI runs the same script with `-FailOnError`, so warnings remain advisory
while structural errors fail the smoke workflow.

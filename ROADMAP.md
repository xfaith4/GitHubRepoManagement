# GitHub Repo Management — Product & Engineering Roadmap

> Status: Active
>
> Product direction: evolve from a general repo utility into a **roadmap-driven work queue, roadmap contract auditor, and Copilot dispatch console** for multi-repo momentum.

## 1. Product Intent

GitHub Repo Management is being reshaped into a clean, operator-friendly tool that helps answer seven questions across a portfolio of repositories:

1. Which repos have a roadmap at all?
2. Which repos have a roadmap that is **contract-quality** rather than informal markdown?
3. Which repos have a clearly actionable next release or next pending work item?
4. Which repos are blocked by missing or weak documentation?
5. Which repos are currently safe to dispatch to GitHub Copilot?
6. Which repos require roadmap repair, augmentation, or standardization before orchestration?
7. How do we keep limited Copilot capacity continuously focused on the best next work without duplicate effort or drift?

The long-term goal is not generic repository browsing. The goal is a **portfolio execution console** that continuously audits roadmap quality, surfaces the next best roadmap work, packages clean context, and launches or tracks Copilot tasks across repositories without duplicate effort or hidden ambiguity.

---

## 2. Product Principles

- **Roadmap-first workflow** — roadmap files are a primary source of truth for next work.
- **Roadmap as contract** — a roadmap is not merely documentation; it is a machine-readable work contract for execution and orchestration.
- **Explainable automation** — every audit, readiness score, and dispatch decision should be inspectable and grounded in visible repo state.
- **Human review before irreversible action** — preview repair, preview task packaging, and preview write-back before mutation.
- **Portfolio visibility over repo trivia** — make missing roadmaps, weak roadmaps, completed roadmaps, pending work, and blocked repos obvious.
- **Operational continuity** — preserve current launcher, logging, API host, and dashboard foundations rather than rebuilding from scratch.
- **Continuous improvement of roadmap quality** — roadmap format itself should improve over time to support better parsing and safer automation.

---

## 3. Current State Summary

The project already has the foundational pieces needed for a roadmap-aware execution tool:

- dashboard shell and API host
- local repo scanning and status inventory
- roadmap file discovery, caching, and viewing
- operation log plumbing
- Copilot task preview/start/history plumbing for roadmap-driven execution

The next stage is to convert these foundations into a coherent work queue product **and** a formal roadmap contract system.

---

## 4. Recently Completed

The following progress is preserved from prior execution history and remains foundational:

- [x] Unified API host and adapter layer (status, reconcile, doc-review, git ops).
- [x] Dual GitHub inventory adapter (`gh` CLI + direct REST API fallback).
- [x] Structured logging, metrics endpoint, health/dependency checks, retention tooling.
- [x] ROADMAP file scanner — indexes ROADMAP*.md across all local repos; viewer in dashboard.
- [x] Roadmap index cached (TTL 300 s); `/api/roadmap/index`, `/api/roadmap/content`, `/api/roadmap/scan` routes.
- [x] Dashboard ROADMAP badges per repo row; `RoadmapViewerModal` with Scan All and Refresh.
- [x] Single-entrypoint launcher (`Start-App.ps1`, `start-silent.bat`) — hidden background processes, PID tracking.
- [x] Structured operations log (JSONL); `GET /api/log/tail` polled by dashboard Operation Log panel.
- [x] Backend connectivity indicator (`useHealthPing`) shown in dashboard header.
- [x] CI smoke workflow covering module, adapter, and API host smoke tests.
- [x] Roadmap task automation scripts: `Start-RoadmapCopilotTask.ps1` + `Start-GitHubCopilotTask.ps1` with preview mode.
- [x] Persistent roadmap task history and API call logging (`output/roadmap-task-history/*.json*`).
- [x] New roadmap agent API routes: `/api/roadmap-agent/preview`, `/api/roadmap-agent/start`, `/api/roadmap-agent/history`.
- [x] Dashboard ROADMAP modal upgraded to preview/start roadmap Copilot tasks and view recent task history.
- [x] Local status scan now populates `lastCommitMessage`, `lastCommitAuthor`, `commitsLastWeek`, `commitsLastMonth`.
- [x] GitHub insights now aggregate real open PR counts (removed hardcoded zeros in API/gh paths).
- [x] Documentation audit scanner (`DocAudit.Scanner.ps1`) computes per-repo `DispatchReadiness` from roadmap state + doc findings.
- [x] Machine-readable documentation standards (`backend/config/doc-standards.json`) for README presence, length, sections, and required files.
- [x] New docs-audit API routes: `GET /api/docs-audit` and `POST /api/docs-audit/scan` with TTL cache.
- [x] Work Queue primary view in the dashboard — filters repos by dispatch readiness; shows findings with severity and recommended actions.
- [x] Dispatch readiness badges and readiness filter dropdown added to the Repository Grid view.
- [x] CI smoke extended with doc-standards.json integrity check and `/api/docs-audit` route coverage.
- [x] Release-oriented roadmap format adopted for this repository to improve agent execution boundaries.
- [x] Initial Roadmap Contract Standard package drafted: canonical template, schema, audit rules, maturity model, and repair prompt.
- [x] Roadmap Contract Standard package delivered under `standards/roadmap/`: ROADMAP_TEMPLATE.md, roadmap-contract.schema.json, roadmap-audit-rules.json (10 weighted rules), ROADMAP_MATURITY_MODEL.md (L0–L4), roadmap-repair-prompt.md.
- [x] Backend loader (`GET /api/roadmap/standard`) reads audit rules from `standards/roadmap/roadmap-audit-rules.json` at runtime without code changes.
- [x] App documentation added: `docs/reference/roadmap-contracts.md` covering contract model, scoring, authoring guidance, and API reference.
- [x] CI smoke and module smoke extended with roadmap standard asset integrity checks.
- [x] Roadmap contract normalization layer (`Invoke-NormalizeRoadmapContract`) maps parsed markdown into the stable internal model from `roadmap-contract.schema.json`.
- [x] Rule-based roadmap auditor (`Invoke-AuditRoadmapContract`) applies the JSON rule pack and computes a 0–100 maturity score per repo.
- [x] Roadmap maturity level (L0-Absent through L4-Orchestration-Ready) assigned and exposed in API responses (`GET /api/roadmap/audit`, `POST /api/roadmap/audit/scan`).
- [x] Per-rule audit findings with severity, message, recommended action, and score impact returned in every contract audit result.
- [x] Roadmap contract audit modal (`RoadmapAuditModal`) added to the dashboard — shows maturity level badge, score bar, structural flags, and expandable findings.
- [x] Maturity-level filter and maturity mini-badges added to the Work Queue view.
- [x] Module smoke and API host smoke extended with roadmap auditor coverage (Release 0.8).
- [x] Roadmap repair planner (`Invoke-PlanRoadmapRepair`) maps audit findings to concrete repair actions with `previewState` assignment.
- [x] Repair preview generator (`Invoke-GenerateRepairPreview`) produces proposed normalized roadmap markdown preserving completed history.
- [x] Repair API routes: `POST /api/roadmap/repair/preview`, `POST /api/roadmap/repair/apply`, `GET /api/roadmap/repair/history`.
- [x] Repair history persistence (JSONL append-log) and original roadmap backup-before-write-back.
- [x] `RoadmapRepairModal` dashboard component — Repair Plan, Diff Preview, and History tabs with explicit two-step apply workflow.
- [x] "Repair" button in Work Queue for L0–L2 repos; cache invalidated after successful apply.
- [x] Module smoke and API host smoke extended with roadmap repair coverage (Release 0.9).
- [x] Persistent execution state ledger (`Execution.Ledger.ps1`) — tracks repo assignments, two-lane slots, execution states, history.
- [x] Explicit execution states: `idle`, `ready`, `running`, `blocked`, `complete` with duplicate-dispatch guards.
- [x] Execution API routes: `GET /api/execution/queue`, `POST /api/execution/sync`, `POST /api/execution/assign`, `POST /api/execution/complete`, `POST /api/execution/cancel`, `POST /api/execution/requeue`.
- [x] Two-lane Execution Queue panel (`ExecutionQueuePanel`) in dashboard — Active Lanes board, ranked Ready Queue, and execution history tabs.
- [x] Repos ranked by priority score (maturity score + readiness bonus) to surface best candidates.
- [x] Requeue and retry semantics: blocked repos requeueable with force; retries tracked; max retry threshold transitions to blocked.
- [x] Module smoke and API host smoke extended with execution ledger coverage (Release 1.0).
- [x] Roadmap linter (`Invoke-LintRoadmapContent`) — 7 policy checks for release headings, checkbox format, required sections, version gaps, and vague items.
- [x] README standardization preview workflow (`Invoke-PreviewReadmeStandardization`, `Invoke-ApplyReadmeStandardization`) — proposes missing sections, backs up originals, logs history.
- [x] Roadmap lint API routes: `GET /api/roadmap/lint`, `POST /api/roadmap/lint/scan`.
- [x] README standardization API routes: `POST /api/readme/standardize/preview`, `POST /api/readme/standardize/apply`, `GET /api/readme/standardize/history`.
- [x] Maturity drift monitor (`Set-MaturityBaseline`, `Get-MaturityDrift`, `Confirm-MaturityDriftAcknowledged`) — per-repo baseline tracking and drift severity alerts.
- [x] Contract drift API routes: `GET /api/roadmap/drift`, `POST /api/roadmap/drift/baseline`, `POST /api/roadmap/drift/acknowledge`.
- [x] Notification hub (`Register-NotificationWebhook`, `Send-NotificationEvent`) — webhook registration and event firing for scan/repair/execution/drift events.
- [x] Notification webhook API routes: `GET/POST /api/notifications/webhooks`, `POST /api/notifications/webhooks/remove`.
- [x] Roadmap completion update preview (`POST /api/roadmap/completion-preview`) — after task execution, generates proposed roadmap with completed items marked.
- [x] `RoadmapLintModal` and `ReadmeStandardizationModal` dashboard components — Lint findings panel and three-tab standardization modal with diff preview and apply workflow.
- [x] Saved operator filters in Work Queue — named filter presets persisted to localStorage; loadable in one click.
- [x] Module smoke and API host smoke extended with Release 1.1 coverage (linter, drift monitor, doc standardization, notification hub).
- [x] Operations log (`operations.jsonl`) capped with configurable `retention.maxOpsLogLines` setting (default 5 000); trimmed on startup and every 250 writes.
- [x] Scheduled background scan support (`scanning.autoScanIntervalMinutes` setting); background runspace invalidates all caches on interval; `GET /api/scan/schedule` exposes status.
- [x] Execution throughput metrics (`GET /api/execution/metrics`) — completed today/week, average run time, error rate, and state counts from the execution ledger.
- [x] Roadmap item tagging — inline `[tag]` tokens (e.g. `[security]`, `[infra]`, `[breaking]`) extracted from checkbox items; `allTags` and per-item `tags` added to parse result; tags stripped from display text.
- [x] Cross-repo dependency tracker (`Roadmap.DependencyTracker.ps1`) — detects GitHub URL, hash-ref, and keyword-based references between portfolio repos; `GET /api/roadmap/dependencies` returns full graph and summary.
- [x] Copilot task prompt enriched with execution history, roadmap audit quality context, and cross-cutting tag context (Steps 6b–6d in `Build-CopilotTaskPacket`).

---

## 5. Release Roadmap

## Release 0.4 — Roadmap Intelligence Foundation

**Goal:** turn roadmap files from passive documents into structured, portfolio-usable work signals.

### Product outcomes

- Repos can be classified as: missing roadmap, roadmap complete, roadmap has pending items, parse error.
- The next actionable roadmap item becomes visible from the main UI.
- Operators can quickly separate repos with work from repos with no actionable next step.

### Engineering milestones

- [x] Build structured roadmap parser for checkbox items, section grouping, and ordered pending-item extraction.
- [x] Add normalized roadmap state model to backend responses.
- [x] Add roadmap completion status and pending count to repo records.
- [x] Surface `nextPendingRoadmapItem` in the main dashboard grid.
- [x] Distinguish `missing`, `complete`, `pending`, and `parse-error` roadmap states in UI badges.
- [x] Add smoke/API contract coverage for roadmap API routes.
- [x] Add smoke/API contract coverage for roadmap-agent routes.
- [x] Add roadmap parse diagnostics to the operations log.

### Acceptance criteria

- Every scanned repo is assigned exactly one roadmap state.
- Main UI shows the next pending item, or an explicit non-ready reason.
- Parse failures are visible and actionable rather than silent.

---

## Release 0.5 — Documentation Audit & Dispatch Readiness

**Goal:** determine whether a repo is truly ready to hand to Copilot.

### Product outcomes

- The app can identify repos that have roadmap work but are not yet safe to dispatch.
- README and supporting docs are evaluated against a standard rather than vague intuition.
- Operators can filter repos by readiness instead of manually inspecting markdown files.

### Engineering milestones

- [x] Introduce a `Documentation Audit` or `Work Queue` primary view in the UI.
- [x] Add machine-readable documentation standards for README and required repo-root documents.
- [x] Implement combined docs-audit backend route family (inventory + README findings + roadmap findings + readiness status).
- [x] Compute per-repo `DispatchReadiness` state:
  - `missing-roadmap`
  - `roadmap-complete`
  - `needs-doc-standardization`
  - `ready`
  - `blocked`
- [x] Show missing docs, README quality findings, and roadmap readiness in a single repo details panel.
- [x] Add filters for missing roadmap, roadmap complete, pending work, docs non-compliant, ready for dispatch, and blocked.
- [x] Add severity/recommended-action summaries to each repo row.
- [x] Add CI checks for documentation integrity and broken internal links where practical.

### Acceptance criteria

- A repo can be declared `ready` only when roadmap and documentation conditions are met.
- Operators can sort and filter by readiness without opening individual files.
- README/roadmap problems are visible in one place with a recommended next action.

---

## Release 0.6 — Copilot Task Packaging & Preview Workflow

**Goal:** create a clean bridge between a roadmap item and a trustworthy Copilot task.

### Product outcomes

- Starting a Copilot task becomes a deliberate, inspectable act.
- The app generates a structured work packet instead of sending a thin prompt with weak context.
- Operators can preview exactly what Copilot will be asked to do and why.

### Engineering milestones

- [x] Define a normalized task packet model containing repo context, selected roadmap item, local documentation findings, acceptance criteria, and constraints.
- [x] Add `Preview Copilot Task` as a first-class action from the Work Queue.
- [x] Include neighboring roadmap context (previous item, section, next item) in the task packet.
- [x] Include documentation findings and repo standards in preview payload.
- [x] Add repo-level guardrails in generated prompts:
  - no placeholder stub-outs
  - update affected docs when workflow changes
  - preserve existing launcher/logging behavior unless intentionally changed
  - keep changes aligned to the selected roadmap item
- [x] Persist preview/start metadata with stable task identifiers.
- [x] Improve recent task history views with repo, roadmap item, started time, and outcome.

### Acceptance criteria

- Every launched task is tied to a visible roadmap item.
- Operators can preview the exact task package before launch.
- Task history can answer who launched what, for which repo, against which roadmap item.

---

## Release 0.7 — Roadmap Contract Standard Foundation

**Goal:** define the canonical standard that turns roadmap markdown into a normalized contract model suitable for audit, repair, and orchestration.

### Product outcomes

- The app has an official roadmap contract standard instead of ad hoc roadmap interpretation.
- Managed repos can be measured against a clear roadmap quality target.
- Roadmap repair and Copilot dispatch can be grounded in the same contract model.

### Engineering milestones

- [x] Add `standards/roadmap/ROADMAP_TEMPLATE.md` as the canonical authoring template.
- [x] Add `standards/roadmap/roadmap-contract.schema.json` for normalized contract validation.
- [x] Add `standards/roadmap/roadmap-audit-rules.json` with weighted scoring, severities, and repair guidance.
- [x] Add `standards/roadmap/ROADMAP_MATURITY_MODEL.md` defining levels from absent to orchestration-ready.
- [x] Add `standards/roadmap/roadmap-repair-prompt.md` for preview-based roadmap rewrite workflows.
- [x] Add app documentation explaining roadmap contracts, contract audit goals, and how release-scoped work should be authored.
- [x] Add backend loader for roadmap standard assets so audit logic reads rules from data instead of hardcoded assumptions.

### Acceptance criteria

- The repo contains a complete Roadmap Contract Standard package under source control.
- The standard is documented clearly enough for both humans and coding agents to follow.
- Audit logic can load the standard package without code edits for rule changes.

### Out of scope

- Full portfolio-wide roadmap repair write-back.
- Autonomous task dispatch.

---

## Release 0.8 — Roadmap Contract Audit & Maturity Scoring

**Goal:** formally audit whether each roadmap is a valid machine-readable work contract.

### Product outcomes

- The app can grade roadmap quality instead of merely detecting file presence.
- Each repo receives a roadmap score, maturity level, and actionable findings.
- Operators can identify which repos are orchestration-ready and which need roadmap repair first.

### Engineering milestones

- [x] Implement roadmap contract normalization layer that maps parsed markdown into a stable internal model.
- [x] Implement rule-based roadmap auditor using the JSON rule pack.
- [x] Compute weighted roadmap audit score and grade per repo.
- [x] Assign roadmap maturity level per repo:
  - `L0 Absent`
  - `L1 Informal`
  - `L2 Structured`
  - `L3 Contract-Ready`
  - `L4 Orchestration-Ready`
- [x] Add audit findings with severity, code, message, and recommended fix.
- [x] Add roadmap audit summary card and details panel to the UI.
- [x] Add filters for roadmap missing, repairable, compliant, and orchestration-ready.
- [x] Add operations-log traces for parse, normalize, score, and audit-rule failures.

### Acceptance criteria

- Every repo with a roadmap receives a score or an explicit parse/audit failure.
- The UI can explain why a roadmap is weak, not just that it is weak.
- The app can distinguish `has roadmap` from `has valid work contract`.

---

## Release 0.9 — Roadmap Repair Preview & Standardization Workflow

**Goal:** let operators preview a corrected, augmented roadmap before applying any write-back.

### Product outcomes

- Weak roadmaps can be repaired into the standard without manual reinvention.
- Completed history is preserved while future work is normalized into release-scoped contracts.
- Operators can diff current vs proposed roadmap before approving changes.

### Engineering milestones

- [x] Implement roadmap repair planner that maps audit findings to repair actions.
- [x] Generate proposed normalized roadmap markdown using the canonical template.
- [x] Preserve completion history while restructuring future work into releases with per-release checklists.
- [x] Add roadmap diff preview in UI with current vs proposed content.
- [x] Add explicit preview states: `repair-preview-ready`, `repair-blocked`, `rewrite-not-recommended`.
- [x] Support augmentation of missing contract sections such as acceptance criteria, out-of-scope, and release status.
- [x] Add apply workflow with explicit user approval and operation logging.
- [x] Persist rewrite history metadata for traceability.

### Acceptance criteria

- A non-compliant roadmap can be preview-rewritten into the contract format without losing true completed history.
- Operators can review structural changes before write-back.
- Rewrite activity is logged and traceable.

### Out of scope

- Unreviewed automatic mutation of roadmaps across the portfolio.
- Autonomous completion marking.

---

## Release 1.0 — Two-Lane Execution Queue

**Goal:** keep up to two Copilot agents productively occupied across separate repos without collisions.

### Product outcomes

- The app behaves like a portfolio momentum console.
- Ready repos can be prioritized and dispatched without duplicate assignment.
- Active work across two Copilot lanes is visible at a glance.

### Engineering milestones

- [x] Introduce persistent execution state ledger for repo assignments and task outcomes.
- [x] Prevent duplicate dispatch of the same repo while a task is active.
- [x] Prevent duplicate dispatch of the same roadmap item.
- [x] Add explicit execution states: `idle`, `ready`, `running`, `blocked`, `complete`.
- [x] Add two-lane execution board or lane panel to the dashboard.
- [x] Rank ready repos by priority/readiness score to surface the best next candidates.
- [x] Requeue repos automatically after refresh when more pending work remains.
- [x] Add cancellation/failure handling and clear retry semantics.

### Acceptance criteria

- No repo can occupy both lanes simultaneously.
- Operators can see which two tasks are active and what remains next in queue.
- Completed or failed tasks are reflected back into repo readiness on refresh.

### Out of scope

- Unlimited parallel orchestration.
- Fully autonomous agent fleet behavior.

---

## Release 1.1 — Standardization, Guardrails, and Continuous Improvement

**Goal:** reduce ambiguity in roadmap-driven automation and make the system safer and more deterministic over time.

### Product outcomes

- Roadmap formatting becomes consistent enough to support reliable parsing across repos.
- Documentation quality and roadmap quality improve together.
- The product can gradually move from assisted workflow toward more autonomous but still reviewable execution.

### Engineering milestones

- [x] Publish recommended `ROADMAP.md` structure standard for managed repos.
- [x] Add roadmap linting or policy checks for release headings, checkbox formatting, required sections, and parseability.
- [x] Add README standardization preview workflow.
- [x] Add proposed roadmap completion/update preview after successful task execution.
- [x] Add saved operator filters/views for common triage patterns.
- [x] Add notification hooks for scheduled scans and execution failures.
- [x] Add policy-as-code checks for repository standards enforcement.
- [x] Add contract drift alerts when a roadmap falls below a target maturity level.

### Acceptance criteria

- The app can identify roadmap formatting drift before it breaks downstream automation.
- Standardization tasks can be previewed before modification.
- Repo management becomes progressively more deterministic over time.

### Out of scope

- Silent autonomous mutation of docs and roadmaps.
- Removing the operator from review loops.

---

---

## Release 1.3 — Production Frontend Build

**Goal:** Eliminate the Vite development server from the runtime path so the application can run as a single deployable unit without Node.js present after build time.

### Product outcomes

- The frontend is a compiled static bundle served directly by the PowerShell API host.
- No `npm run dev` process is required at runtime.
- The application starts faster, consumes fewer resources, and is safe to expose on a local network.
- A single launcher command produces a production-grade running application.

### Engineering milestones

- [x] Add `npm run build` step to `Start-App.ps1` that compiles the Vite frontend to `frontend/dist/` when `dist/` is absent or `--rebuild` is passed.
- [x] Implement `Send-StaticFile` in `Start-RepoManagementApiHost.ps1` that reads files from `frontend/dist/`, sets correct `Content-Type` by extension, and adds `Cache-Control` headers for assets (1 year for hashed filenames, no-cache for `index.html`).
- [x] Add catch-all route `GET /*` that serves `frontend/dist/index.html` for any path not matched by an API route (client-side routing support).
- [x] Add `GET /` route that redirects to the SPA entry point.
- [x] Compress files larger than 1 KB with gzip when the request `Accept-Encoding` header includes `gzip`; serve with `Content-Encoding: gzip`.
- [x] Update `Start-App.ps1` to skip the Vite dev server process entirely in silent mode when `frontend/dist/index.html` exists.
- [x] Add `--dev` flag to `Start-App.ps1` that retains the Vite dev server for active frontend development.
- [x] Update `start.bat` and `start-live.bat` to pass `--rebuild` on first launch or when `frontend/dist/` is missing.
- [x] Remove `VITE_USE_MOCK_API` environment variable from all launchers; mock mode becomes a build-time flag only.
- [x] Smoke test: `GET /` returns 200 with `text/html`; `GET /assets/*.js` returns 200 with correct MIME type and `Cache-Control`.

### Acceptance criteria

- Running `.\Start-App.ps1` on a machine with Node.js builds the frontend once and never starts a Vite process again unless `--dev` is passed.
- The application is fully functional through the compiled bundle.
- Removing Node.js from PATH after the initial build does not prevent the app from running.

### Out of scope

- CDN deployment or static hosting.
- Server-side rendering.

---

## Release 1.4 — Cross-Platform and Containerized Deployment

**Goal:** Enhance this application with the ability to implement the necessary changes to Roadmaps that are determined weak.  For repos that do not have a roadmap, this application should give the option to evalutate the repo in order to determine logical action items to added to a roadmap.

### Product outcomes

- Fully functional option in UI to Update a single repo roadmap with suggested hardening changes.
- Fully functional option in UI to evaluate a repo in order to create a logical roadmap with code hardening changes and\or reasonable features with great value.


### Engineering milestones

- [x] Add cross-platform startup script parity: align `Start-App.ps1` and `start.sh` flags/config handling with consistent defaults and error reporting.
- [x] Implement repo evaluation pipeline that inspects repo structure and produces suggested roadmap items (hardening + high-value features).
- [x] Add UI workflow to run evaluation, review suggested items, and create a roadmap when none exists.
- [x] Add UI workflow to update a single repo roadmap with suggested hardening changes and allow user approval before applying.
- [x] Add containerization support: `Dockerfile` + `docker-compose.yml` with health endpoint wiring and documented ports/volumes.

---

## Release 1.5 — API Authentication and Network Security

**Goal:** Harden the API host so it can be safely exposed beyond `127.0.0.1` without risk of unauthenticated access or information disclosure.

### Product outcomes

- The API requires a valid token for all non-health routes.
- The application can be run on a local network and shared with teammates without exposing an open, unauthenticated API.
- Security-conscious operators can configure HTTPS for local or network deployment.

### Engineering milestones

- [ ] Add `auth.apiKey` field to `settings.json` schema; on startup, if set, all routes except `/health/live` and `/health/ready` require `Authorization: Bearer <key>` or `X-Api-Key: <key>`; return 401 on mismatch.
- [ ] Add `auth.apiKeyEnvVar` alternative so the key can be injected via environment variable without storing it in `settings.json`.
- [ ] Generate a random API key on first startup if `auth.apiKey` and `auth.apiKeyEnvVar` are both unset; write the generated key to `backend/modules/output/runtime/api-key.txt` with a startup log message pointing to it.
- [ ] Add CORS configuration to `settings.json`: `cors.allowedOrigins` array (default `["http://localhost:7000", "http://127.0.0.1:7000"]`); replace the current `Access-Control-Allow-Origin: *` with the configured origins.
- [ ] Implement per-IP request rate limiting: track request counts in a script-scoped hashtable; return 429 with `Retry-After` header when any single IP exceeds `security.maxRequestsPerMinute` (default 300).
- [ ] Add `network.bindAddress` to `settings.json` (default `127.0.0.1`); validate that non-loopback bind requires `auth.apiKey` or `auth.apiKeyEnvVar` to be set, and refuse to start without it.
- [ ] Implement TLS option: if `tls.certPath` and `tls.keyPath` are set in `settings.json`, wrap the `TcpListener` with `SslStream` using the provided certificate; serve HTTPS on the configured port.
- [ ] Add `GET /api/auth/verify` route that returns 200 `{ valid: true }` for authenticated requests; used by frontend to confirm auth state on load.
- [ ] Frontend: read `VITE_API_KEY` from build env or prompt on first load if `/api/auth/verify` returns 401; store in `sessionStorage`; include in all API requests as `X-Api-Key` header.
- [ ] Smoke test: unauthenticated `GET /api/status` returns 401 when `auth.apiKey` is configured; authenticated request returns 200.

### Acceptance criteria

- An operator who sets `auth.apiKey` and `network.bindAddress: 0.0.0.0` can share the dashboard URL with a teammate on the same network and require authentication.
- The application refuses to bind to a non-loopback address without auth configured.
- All existing smoke tests pass with a configured API key.

### Out of scope

- OAuth / GitHub App authentication (deferred to Release 1.8).
- Role-based access control.

---

## Release 1.6 — Persistent Data Layer

**Goal:** Replace JSON file storage with a SQLite database for the execution ledger, maturity history, and operations log so the application is reliable at scale and supports time-series queries.

### Product outcomes

- The execution ledger does not corrupt or lose history when multiple operations happen in quick succession.
- Maturity scores are stored over time, enabling trend charts in the dashboard.
- The operations log is queryable by time range, level, and keyword without reading the entire file.
- The application handles portfolios of 200+ repos without file I/O degradation.

### Engineering milestones

- [ ] Add `System.Data.SQLite` via the `PSSQLite` PowerShell module or direct .NET assembly; add dependency check to startup with a clear error message if unavailable.
- [ ] Create `Initialize-AppDatabase` function that creates `output/app.db` with schema: `execution_entries` table, `execution_history` table, `maturity_snapshots` table (repoName, score, level, capturedAt), `ops_log` table (ts, level, msg).
- [ ] Migrate `Execution.Ledger.ps1` to read/write `execution_entries` and `execution_history` via parameterized SQL queries; remove `execution-ledger.json` write path.
- [ ] Add daily maturity snapshot write: after every roadmap audit scan, insert a row into `maturity_snapshots` for each repo with its current score and level.
- [ ] Migrate `Write-HostLog` JSONL append to an INSERT into `ops_log`; keep `Invoke-TrimOpsLog` as a fallback for non-database mode; `GET /api/log/tail` queries `ops_log` with `ORDER BY ts DESC LIMIT ?`.
- [ ] Add `GET /api/roadmap/maturity-history` route: accepts `?repoName=&days=30` query params; queries `maturity_snapshots`; returns array of `{ capturedAt, score, level }` for charting.
- [ ] Add maturity trend sparkline to the repository grid row: fetch last 14 days of snapshots and render a 14-point SVG sparkline in the repo row.
- [ ] Add `GET /api/portfolio/trend` route: returns aggregate portfolio stats by day — count of repos at each maturity level — for the last 90 days.
- [ ] Write `Invoke-DatabaseMigration.ps1` that detects the existing JSON ledger file and imports its entries into the SQLite database on first run; skips if DB already populated.
- [ ] Keep JSON file output as an optional export: `POST /api/export` still writes JSON/CSV artifacts; the source of truth is SQLite.
- [ ] Smoke test: write 100 execution history records via the ledger API, read them back via `GET /api/execution/metrics`; assert counts are correct.

### Acceptance criteria

- The execution ledger survives a concurrent assign + complete call without data loss.
- `GET /api/roadmap/maturity-history?repoName=X&days=30` returns an ordered array of score snapshots.
- The ops log is queryable by time range via `GET /api/log/tail?since=<ISO>&level=ERROR`.
- All existing smoke tests pass against the SQLite backend.

### Out of scope

- PostgreSQL or remote database support.
- Multi-writer / multi-instance database access.

---

## Release 1.7 — Complete the Doc Review Pipeline

**Goal:** Deliver the Validate and Complete modes of the documentation review pipeline that are currently scaffolded but not implemented, and implement the Clone and Archive UI actions.

### Product outcomes

- Operators can validate whether a documentation improvement was actually applied correctly.
- Operators can mark a documentation review cycle as complete and record the outcome.
- Repositories can be cloned from GitHub into a configured local workspace from the UI.
- Stale or archived repositories can be marked as inactive so they exit the work queue.

### Engineering milestones

- [ ] Implement `Validate` mode in `Invoke-DocReviewExecution.ps1`: re-run the doc standards audit against the repo after a Copilot task has run; compare findings before and after; return a structured diff of resolved vs remaining findings.
- [ ] Implement `Complete` mode in `Invoke-DocReviewExecution.ps1`: accept a `--Outcome` parameter (`improved`, `skipped`, `deferred`); write a completion record to `output/docreview/history.jsonl` with repoName, outcome, completedAt, and finding summary.
- [ ] Add `POST /api/docreview/validate` route that calls Validate mode for a given repo and returns before/after finding comparison.
- [ ] Add `POST /api/docreview/complete` route that calls Complete mode and returns the written history record.
- [ ] Add `GET /api/docreview/history` route that reads `output/docreview/history.jsonl` and returns the last 100 completion records.
- [ ] Implement Clone action: `POST /api/clone` accepts `{ repoFullName, targetRoot }`, validates `targetRoot` is in `inventory.localRoots`, runs `gh repo clone {repoFullName} {targetPath}`, returns the local path; enable Clone button in `ActionBar.tsx` and set `cloneImplemented = true`.
- [ ] Implement Archive action: `POST /api/archive` accepts `{ repoName }`, writes an `archived: true` flag to the repo's status cache entry, excludes it from the work queue and dispatch queue; enable Archive button in `ActionBar.tsx` and set `archiveImplemented = true`.
- [ ] Add `GET /api/status?includeArchived=true` filter support so archived repos remain visible in a dedicated "Archived" view but are excluded from default scans.
- [ ] Add DocReview history tab to `DocReviewModal` showing completion records from `GET /api/docreview/history`.
- [ ] Smoke test: call Validate mode on a repo that has had a doc standardization applied; assert the before/after diff contains at least one resolved finding.

### Acceptance criteria

- Validate mode returns a structured before/after finding comparison with `resolvedCount` and `remainingCount`.
- Complete mode writes a history record that is retrievable via `GET /api/docreview/history`.
- Clone button clones a repo and triggers a status cache refresh.
- Archive button removes the repo from the active work queue without deleting it from disk.

### Out of scope

- Bulk archive of multiple repos in one action.
- Restoring archived repos from the UI (use `settings.json` edit for now).

---

## Release 1.8 — Guided Onboarding and GitHub App Integration

**Goal:** Replace the manual PAT + settings.json setup with a guided first-run experience and a proper GitHub App OAuth flow so any engineer can go from zero to running in under five minutes.

### Product outcomes

- A first-time user can complete setup without reading any documentation.
- The application authenticates with GitHub via OAuth rather than a Personal Access Token.
- The setup flow validates each prerequisite before proceeding and surfaces a clear error for any failure.

### Engineering milestones

- [ ] Add startup detection: if `backend/config/settings.json` is missing or has `schemaVersion` absent, redirect all non-health API routes to `GET /setup/status` which returns the list of incomplete setup steps.
- [ ] Implement `GET /setup/status` route: checks prerequisites in order — `pwsh` version ≥ 7.0, Node.js version ≥ 18, `gh` CLI present, `GITHUB_TOKEN` or GitHub App token set, at least one `inventory.localRoots` path exists and is readable; returns array of `{ step, status, message }`.
- [ ] Implement `POST /setup/config` route: accepts partial settings object, merges with defaults, validates, and writes `backend/config/settings.json`; returns validation errors for each invalid field.
- [ ] Build `SetupWizard` React component: four-step flow — (1) prerequisites check with per-item status badges, (2) local repo roots picker with directory browser, (3) GitHub authentication method selection, (4) first scan confirmation; shown when `GET /setup/status` reports incomplete steps.
- [ ] Implement `GET /setup/prerequisites` route: returns per-tool version check results for `pwsh`, `node`, `npm`, `git`, `gh`; includes download URL for each missing tool.
- [ ] Register a GitHub App (owner: application developer); add `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY_PATH`, and `GITHUB_APP_INSTALLATION_ID` to `settings.json` schema as alternatives to `secrets.gitHubTokenEnvVar`.
- [ ] Add `GET /auth/github/callback` route: receives OAuth code from GitHub, exchanges for installation token via GitHub App API, stores token in `backend/modules/output/runtime/github-token.json` with expiry; refresh automatically when expired.
- [ ] Add `GET /auth/status` route: returns `{ method: "pat" | "app" | "none", authenticated: bool, scopes: [], rateLimitRemaining: int }`.
- [ ] Update all GitHub API calls in the API host to read the token from the App token file first, falling back to the PAT env var, then to unauthenticated.
- [ ] Smoke test: run `GET /setup/status` against a fresh `settings.json`-less environment; assert all steps return `incomplete`; post a valid config; assert all steps return `complete`.

### Acceptance criteria

- A fresh install with no `settings.json` redirects the user to the setup wizard on first browser open.
- Completing the wizard writes a valid `settings.json` and triggers the first repo scan without manual steps.
- GitHub App authentication produces a working token that is refreshed automatically before expiry.

### Out of scope

- GitHub Marketplace listing (deferred to Release 1.9).
- Multi-installation GitHub App support (one installation per running instance).

---

## Release 1.9 — Portfolio Analytics, Trend Visualization, and Distribution

**Goal:** Add historical trend charts, a portfolio health digest, and distribution artifacts that make the application shareable and self-promoting.

### Product outcomes

- Operators can see how maturity scores have changed across the portfolio over the last 90 days.
- A weekly digest is sent to a configured webhook with portfolio health KPIs.
- The application is distributable as a GitHub Action that posts roadmap audit results as PR checks.
- The Roadmap Contract Standard is published as a standalone open specification.

### Engineering milestones

- [ ] Add `PortfolioTrendChart` React component that fetches `GET /api/portfolio/trend` and renders a stacked area chart (L0–L4 counts per day for last 90 days) using a lightweight charting library (e.g., Recharts).
- [ ] Add `MaturitySparkline` component in the repo grid row: fetches `GET /api/roadmap/maturity-history?repoName=X&days=14` and renders a 14-point SVG path showing score trend.
- [ ] Add `POST /api/digest/send` route: computes portfolio KPIs (total repos, count per maturity level, repos that improved this week, repos that regressed, top 3 dispatch-ready repos) and fires `Send-NotificationEvent` with `event: digest.weekly` and the computed payload.
- [ ] Add `scanning.weeklyDigestWebhook` to `settings.json` schema; when set, `Register-ScheduledTasks.Template.ps1` registers a weekly Task Scheduler job that calls `POST /api/digest/send`.
- [ ] Write `action.yml` for a GitHub Action named `roadmap-audit-action`: accepts inputs `roadmap-path`, `min-maturity-level`; calls the roadmap contract auditor PowerShell module; outputs `maturity-score`, `maturity-level`, `findings-count`; posts a check run to the PR with the audit result.
- [ ] Extract `standards/roadmap/` into a standalone `roadmap-contract-spec` directory with its own `README.md`, `SPEC.md`, version file (`spec-version: 1.0`), and MIT license; structure it so it can be published as a separate GitHub repository.
- [ ] Add `GET /api/portfolio/badge` route: returns an SVG badge showing the portfolio's average maturity score (e.g., `roadmap maturity | L2.8`) suitable for embedding in a README.
- [ ] Add `GET /api/roadmap/badge/{repoName}` route: returns per-repo SVG badge showing current maturity level and score.
- [ ] Smoke test: `GET /api/portfolio/trend?days=7` returns an array of 7 daily entries each with `{ date, l0, l1, l2, l3, l4 }`.

### Acceptance criteria

- The portfolio trend chart renders in the dashboard and shows at least 7 days of history after 7 days of operation.
- `POST /api/digest/send` fires a webhook payload that includes `totalRepos`, `byLevel`, `improvedThisWeek`, and `topCandidates`.
- The GitHub Action runs in a GitHub-hosted runner, audits a roadmap file, and posts a passing or failing check run.
- The roadmap contract spec directory is self-contained and can be copied to a new repository without modification.

### Out of scope

- GitHub Marketplace listing for the GitHub Action (requires manual submission after release).
- Email digest (webhook-only for this release).

---

## Release 2.0 — Agent Integration Protocol and AI Repair Loop

**Goal:** Publish a formal machine-readable API contract that AI coding agents can query before starting work, and implement an AI-driven repair loop that submits roadmap and README improvements as GitHub pull requests for human review.

### Product outcomes

- AI coding agents (Claude Code, Copilot, Devin, custom agents) can query the application to determine whether a repo is safe to act on and what the next task is.
- Operators can trigger an AI-generated roadmap or README repair that opens a GitHub PR for review — no direct file mutation.
- The application becomes infrastructure that AI tools depend on, not just a dashboard humans look at.

### Engineering milestones

- [ ] Define and publish `GET /api/v1/agent/readiness/{repoName}` route with stable contract: returns `{ schemaVersion: "1.0", repoName, dispatchSafe: bool, maturityLevel, maturityScore, selectedTask: { text, section, tags }, constraints: [], auditFindings: [], nextSteps: [] }`; version the contract with a `schemaVersion` field; treat as a stable public API.
- [ ] Add `GET /api/v1/agent/queue` route: returns the top 5 dispatch-ready repos as an ordered list with per-repo readiness packets; designed for agents that self-assign rather than being told which repo to work on.
- [ ] Add `POST /api/v1/agent/claim/{repoName}` route: atomically marks a repo as `running` in the execution ledger and returns the full task packet; rejects if already claimed; designed for agent self-registration.
- [ ] Add `POST /api/v1/agent/complete/{repoName}` route: accepts `{ runId, outcome, summary }`; marks the task complete; triggers a completion-preview diff for the roadmap; designed for agents reporting back autonomously.
- [ ] Implement `Invoke-AiRepairSubmission` function: takes a roadmap repair preview, creates a feature branch in the repo via `gh`, commits the proposed content, and opens a PR with the diff and audit finding context as the PR body; never pushes to the default branch directly.
- [ ] Add `POST /api/roadmap/repair/submit-pr` route: calls `Invoke-AiRepairSubmission` with the current repair preview for the given repo; returns the PR URL.
- [ ] Implement `Invoke-AiReadmeSubmission` function: equivalent to `Invoke-AiRepairSubmission` but for README standardization previews; creates a branch, commits the proposed README, and opens a PR.
- [ ] Add `POST /api/readme/standardize/submit-pr` route: calls `Invoke-AiReadmeSubmission`; returns the PR URL.
- [ ] Add `SubmitPR` button to `RoadmapRepairModal` and `ReadmeStandardizationModal` that calls the respective submit-pr routes; shows the returned PR URL as a clickable link.
- [ ] Publish OpenAPI 3.1 spec for all `/api/v1/agent/*` routes as `docs/reference/agent-api.yaml`; generate from route definitions.
- [ ] Smoke test: call `GET /api/v1/agent/readiness/{repoName}` for a repo with a known maturity level; assert `schemaVersion`, `dispatchSafe`, `maturityLevel`, and `selectedTask.text` are all present.

### Acceptance criteria

- `GET /api/v1/agent/readiness/{repoName}` returns a stable JSON contract that does not change shape between calls for the same repo state.
- `POST /api/roadmap/repair/submit-pr` creates a GitHub PR in the target repo with the repair diff as the PR body.
- `POST /api/v1/agent/claim/{repoName}` rejects a second concurrent claim for the same repo with a 409 Conflict response.
- The agent API spec file `docs/reference/agent-api.yaml` is valid OpenAPI 3.1.

### Out of scope

- Autonomous agent execution without operator approval of PRs.
- Billing or usage metering for agent API access.
- Multi-tenant agent API with per-agent authentication.

---

## 6. Cross-Cutting Engineering Work

These items support all releases and should be advanced continuously:

- [x] Strengthen API contract tests for all routes and error categories.
- [x] Cap or roll `operations.jsonl` with configurable retention.
- [ ] Expand smoke coverage around launcher, health, roadmap parsing, contract audit, repair preview, docs-audit, and task history flows.
- [ ] Add incremental scan mode for large repo roots (skip unchanged directories where safe).
- [ ] Improve cache invalidation and scan performance for large local inventories.
- [ ] Keep structured logs rich enough to diagnose scan, parse, normalize, audit, preview, apply, and start failures.
- [ ] Continue improving operator-facing documentation as workflows evolve.
- [ ] Keep rule packs and schemas data-driven where practical so standards can evolve without broad code rewrites.

---

## 7. Risks and Design Guardrails

### Risks

- Roadmap markdown may be too inconsistent across repos for safe automation.
- README quality may be insufficient for meaningful Copilot context.
- Queue automation can create duplicate or low-value work if readiness is weak.
- Hidden background execution can obscure failures if logs and history are not clear.
- Repair flows can accidentally erase real completed history if not handled carefully.

### Guardrails

- Do not auto-dispatch tasks without a visible readiness model.
- Do not treat all roadmap files as equal; parse confidence matters.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Keep the product operator-readable; this is a control console, not a magic box.
- Preserve genuine completion history when rewriting roadmaps.
- Treat roadmap audit failures as first-class findings, not hidden parser trivia.

---

## 8. Roadmap Contract Standard for Managed Repos

Managed repos should converge toward a release-oriented roadmap format that is both human-readable and machine-parseable.

### Minimum contract expectations

- Clear roadmap title
- Product intent or scope
- Preserved completion history where relevant
- Release-oriented future plan
- Per-release checklist
- Acceptance criteria per release
- Out-of-scope boundaries for larger releases
- Stable release identifiers
- Explicit status markers where practical

### Recommended release structure

```md
## Release 0.4 — Example Release Title

**Goal:** Describe the functioning version this release should deliver.

### Product outcomes
- Outcome visible to operators or users

### Engineering milestones
- [ ] Concrete, testable implementation step
- [ ] Another concrete, testable implementation step

### Acceptance criteria
- The release can be judged complete in observable terms

### Out of scope
- Explicitly deferred work
```

### Formatting guidance

- Prefer release-scoped checklists instead of one giant top-level checklist.
- Treat each release as a bounded work package for coding agents.
- Keep checklist items concrete, implementation-testable, and aligned to a functioning version.
- Avoid vague placeholders such as `improve app`, `refactor stuff`, or `finish later`.
- Preserve completed history rather than rewriting the past into fiction.

---

## 9. Definition of Done for Release Execution

A release should not be marked complete unless:

- all checklist items for that release are truly implemented or explicitly blocked
- UI elements are connected to real behavior rather than placeholders
- affected docs are updated where workflow or product behavior changed
- logging and error handling are sufficient to diagnose failures
- later releases were not partially started just to create the illusion of momentum

This roadmap intentionally treats each release as a bounded, agent-usable execution contract.

---

## 10. Definition of Useful Product Progress

The product is moving in the right direction when:

- missing or weak roadmaps become obvious immediately
- next pending work is visible without opening files
- repos can be filtered by dispatch readiness
- roadmap quality can be scored and explained, not merely guessed
- Copilot tasks are launched from structured context, not wishful prompting
- two active Copilot lanes can stay busy on separate repos without confusion
- progress history remains preserved while future work becomes increasingly formal and deterministic

---

## 11. Immediate Next Focus

Release 1.2 backend features are complete. The recommended next execution target is:

### **Release 1.2 — Enhanced Portfolio Intelligence (frontend + smoke coverage)**

Backend features delivered. Remaining work:

- [ ] Execution throughput metrics card in the dashboard (consumes `GET /api/execution/metrics`)
- [ ] Dependency graph panel in the dashboard (consumes `GET /api/roadmap/dependencies`)
- [ ] Tag filter in Work Queue (filter by `[security]`, `[infra]`, `[breaking]`, etc.)
- [ ] Auto-scan schedule indicator in the dashboard header or settings modal
- [ ] Smoke coverage for the new Release 1.2 API routes (`/api/execution/metrics`, `/api/roadmap/dependencies`, `/api/scan/schedule`)

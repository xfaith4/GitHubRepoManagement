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

### Out of scope

- Automatic roadmap rewrite application.
- Two-lane scheduling.

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

## 6. Cross-Cutting Engineering Work

These items support all releases and should be advanced continuously:

- [ ] Strengthen API contract tests for all routes and error categories.
- [ ] Expand smoke coverage around launcher, health, roadmap parsing, contract audit, repair preview, docs-audit, and task history flows.
- [ ] Add incremental scan mode for large repo roots (skip unchanged directories where safe).
- [ ] Improve cache invalidation and scan performance for large local inventories.
- [ ] Cap or roll `operations.jsonl` with configurable retention.
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

The recommended immediate execution target is:

### **Release 1.2 — Enhanced Portfolio Intelligence**

The next logical evolution is to deepen portfolio-level intelligence and improve operator workflows:

- add scheduled background scan support (configurable interval for automatic re-auditing)
- add cross-repo dependency tracking (identify repos that reference each other in roadmap items)
- add execution throughput metrics and trend visualization in the dashboard
- add roadmap item tagging for cross-cutting concerns (security, infrastructure, breaking changes)
- improve the Copilot task prompt quality based on execution history and audit outcomes

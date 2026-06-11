# Completed Releases — Historical Archive

> **What this file is.** This is the full text of every completed release of
> GitHub Repo Management, preserved verbatim from `ROADMAP.md`. The active
> roadmap was reorganized in 2026-04 to focus on current and future
> execution; completed releases were relocated here so nothing is lost while
> keeping `ROADMAP.md` scannable.
>
> For a chronological developer-facing change log (security fixes,
> reliability hardening, individual file changes), see
> [`CHANGELOG.md`](../../CHANGELOG.md). The two are complementary: this file
> tracks **what was shipped per release**; `CHANGELOG.md` tracks **dated
> code-level changes**.
>
> For the active roadmap, see [`ROADMAP.md`](../../ROADMAP.md).
> For the product direction, see
> [`docs/product/portfolio-execution-console.md`](../product/portfolio-execution-console.md).

---

## Foundational Capabilities (pre-release)

The following progress is preserved from prior execution history and remains
foundational to the product:

- Unified API host and adapter layer (status, reconcile, doc-review, git ops).
- Dual GitHub inventory adapter (`gh` CLI + direct REST API fallback).
- Structured logging, metrics endpoint, health/dependency checks, retention tooling.
- ROADMAP file scanner — indexes `ROADMAP*.md` across all local repos; viewer in dashboard.
- Roadmap index cached (TTL 300 s); `/api/roadmap/index`, `/api/roadmap/content`, `/api/roadmap/scan` routes.
- Dashboard ROADMAP badges per repo row; `RoadmapViewerModal` with Scan All and Refresh.
- Single-entrypoint launcher (`Start-App.ps1`, `start-silent.bat`) — hidden background processes, PID tracking.
- Structured operations log (JSONL); `GET /api/log/tail` polled by dashboard Operation Log panel.
- Backend connectivity indicator (`useHealthPing`) shown in dashboard header.
- CI smoke workflow covering module, adapter, and API host smoke tests.
- Roadmap task automation scripts: `Start-RoadmapCopilotTask.ps1` + `Start-GitHubCopilotTask.ps1` with preview mode.
- Persistent roadmap task history and API call logging (`output/roadmap-task-history/*.json*`).
- New roadmap agent API routes: `/api/roadmap-agent/preview`, `/api/roadmap-agent/start`, `/api/roadmap-agent/history`.
- Dashboard ROADMAP modal upgraded to preview/start roadmap Copilot tasks and view recent task history.
- Local status scan now populates `lastCommitMessage`, `lastCommitAuthor`, `commitsLastWeek`, `commitsLastMonth`.
- GitHub insights now aggregate real open PR counts (removed hardcoded zeros in API/gh paths).
- Documentation audit scanner (`DocAudit.Scanner.ps1`) computes per-repo `DispatchReadiness` from roadmap state + doc findings.
- Machine-readable documentation standards (`backend/config/doc-standards.json`).
- New docs-audit API routes: `GET /api/docs-audit` and `POST /api/docs-audit/scan` with TTL cache.
- Work Queue primary view in the dashboard — filters repos by dispatch readiness; shows findings with severity and recommended actions.
- Dispatch readiness badges and readiness filter dropdown added to the Repository Grid view.
- CI smoke extended with doc-standards.json integrity check and `/api/docs-audit` route coverage.
- Release-oriented roadmap format adopted for this repository to improve agent execution boundaries.
- Initial Roadmap Contract Standard package drafted: canonical template, schema, audit rules, maturity model, and repair prompt.
- Roadmap Contract Standard package delivered under `standards/roadmap/`: ROADMAP_TEMPLATE.md, roadmap-contract.schema.json, roadmap-audit-rules.json (10 weighted rules), ROADMAP_MATURITY_MODEL.md (L0–L4), roadmap-repair-prompt.md.
- Backend loader (`GET /api/roadmap/standard`) reads audit rules from `standards/roadmap/roadmap-audit-rules.json` at runtime without code changes.
- App documentation added: `docs/reference/roadmap-contracts.md` covering contract model, scoring, authoring guidance, and API reference.
- CI smoke and module smoke extended with roadmap standard asset integrity checks.
- Roadmap contract normalization layer (`Invoke-NormalizeRoadmapContract`) maps parsed markdown into the stable internal model.
- Rule-based roadmap auditor (`Invoke-AuditRoadmapContract`) applies the JSON rule pack and computes a 0–100 maturity score per repo.
- Roadmap maturity level (L0-Absent through L4-Orchestration-Ready) assigned and exposed in API responses.
- Per-rule audit findings with severity, code, message, recommended action, and score impact returned in every contract audit result.
- Roadmap contract audit modal (`RoadmapAuditModal`) added to the dashboard.
- Maturity-level filter and maturity mini-badges added to the Work Queue view.
- Roadmap repair planner (`Invoke-PlanRoadmapRepair`) maps audit findings to concrete repair actions with `previewState` assignment.
- Repair preview generator (`Invoke-GenerateRepairPreview`) produces proposed normalized roadmap markdown preserving completed history.
- Repair API routes: `POST /api/roadmap/repair/preview`, `POST /api/roadmap/repair/apply`, `GET /api/roadmap/repair/history`.
- Repair history persistence (JSONL append-log) and original roadmap backup-before-write-back.
- `RoadmapRepairModal` dashboard component — Repair Plan, Diff Preview, and History tabs with explicit two-step apply workflow.
- "Repair" button in Work Queue for L0–L2 repos; cache invalidated after successful apply.
- Persistent execution state ledger (`Execution.Ledger.ps1`) — tracks repo assignments, two-lane slots, execution states, history.
- Explicit execution states: `idle`, `ready`, `running`, `blocked`, `complete` with duplicate-dispatch guards.
- Execution API routes: `GET /api/execution/queue`, `POST /api/execution/sync`, `POST /api/execution/assign`, `POST /api/execution/complete`, `POST /api/execution/cancel`, `POST /api/execution/requeue`.
- Two-lane Execution Queue panel in dashboard.
- Repos ranked by priority score (maturity score + readiness bonus).
- Requeue and retry semantics: blocked repos requeueable with force; retries tracked; max retry threshold transitions to blocked.
- Roadmap linter (`Invoke-LintRoadmapContent`) — 7 policy checks for release headings, checkbox format, required sections, version gaps, and vague items.
- README standardization preview workflow.
- Roadmap lint API routes and README standardization API routes.
- Maturity drift monitor with per-repo baseline tracking and drift severity alerts.
- Notification hub (`Register-NotificationWebhook`, `Send-NotificationEvent`) and webhook API routes.
- Roadmap completion update preview after task execution.
- `RoadmapLintModal` and `ReadmeStandardizationModal` dashboard components.
- Saved operator filters in Work Queue.
- Operations log capped with configurable retention; trimmed on startup and every 250 writes.
- Scheduled background scan support; `GET /api/scan/schedule` exposes status.
- Execution throughput metrics (`GET /api/execution/metrics`).
- Roadmap item tagging — inline `[tag]` tokens (`[security]`, `[infra]`, `[breaking]`, etc.).
- Cross-repo dependency tracker (`Roadmap.DependencyTracker.ps1`) and `GET /api/roadmap/dependencies`.
- Copilot task prompt enriched with execution history, roadmap audit quality context, and cross-cutting tag context.
- Release-level Copilot dispatch (`Roadmap.Dispatcher.ps1`); maturity gate enforces L3+ before dispatch; `RoadmapDispatchModal` with 8-phase state machine; "Dispatch Release" button in Work Queue.
- Repo git status detail — `Git.StatusDetail.ps1`; `RepoGitStatusModal`; clickable Dirty/Ahead/Behind/Diverged badges in repo grid.

---

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
- [x] Compute per-repo `DispatchReadiness` state: `missing-roadmap`, `roadmap-complete`, `needs-doc-standardization`, `ready`, `blocked`.
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
- [x] Add repo-level guardrails in generated prompts (no placeholder stub-outs; update affected docs when workflow changes; preserve existing launcher/logging behavior unless intentionally changed; keep changes aligned to the selected roadmap item).
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
- [x] Assign roadmap maturity level per repo: `L0 Absent`, `L1 Informal`, `L2 Structured`, `L3 Contract-Ready`, `L4 Orchestration-Ready`.
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

## Release 1.8 — Operations Workspace and Prompt Refinement

**Goal:** Add a repo-specific Operations workspace that turns the indexed
portfolio assessment and the Phase 6 prompt-context packet into an
operator-driven execution surface. Operators can select a repo, inspect its
state, review README and ROADMAP context, refine a generated task packet
into a dispatch-ready prompt, and prepare it for execution without rebuilding
the packet foundation from scratch.

### Product outcomes

- Operators can move from portfolio overview to repo-specific detail
  without leaving the app.
- Every selected repo shows documentation health, roadmap maturity, dirty
  worktree state, open PRs, Actions state, GitHub Pages status, and
  recommended next action.
- Operators can start from the generated packet/context assembled in Release
  `1.7.5` Phase 6 instead of hand-writing prompts from scratch.
- Prompt refinement remains operator-reviewed and preview-first.
- Operators can trace a dispatched refined prompt back to the refinement
  run that launched it.

### Engineering milestones

- [x] Add Operations tab with repo selection table for indexed portfolio
      records. *(state: ui-connected)* — the existing
      [`OperationsWorkspaceView.tsx`](frontend/components/OperationsWorkspaceView.tsx)
      is now fed by a live `/api/operations/repos` contract instead of a
      missing backend route.
- [x] Add repo detail workspace showing local path, GitHub URL, default branch,
      current branch, dirty state, last commit, created date, updated date,
      README score, ROADMAP score, lifecycle state, and recommended next
      action. *(state: ui-connected)* — the right-hand Operations detail pane
      now opens against live indexed repo records served by the host.
- [x] Add README and ROADMAP viewers inside the repo detail workspace.
      *(state: ui-connected)* — Operations repo detail now renders inline
      README/ROADMAP content panes backed by
      `/api/readme/content` and `/api/roadmap/content`.
- [x] Add GitHub panel showing open PRs, latest Actions status, and
      GitHub Pages status/link. *(state: ui-connected)* — the Operations
      workspace now renders those live fields from the indexed repo payload.
- [x] Add audit findings panel showing README findings, ROADMAP findings,
      structure findings, and dispatch blockers. *(state: ui-connected)*
- [x] Add Prompt Refinement panel that starts from the existing
      `/api/copilot-task/preview` packet, lets the operator adjust selected
      work item, constraints, and emphasis, and produces a dispatch-ready
      coding-agent prompt without duplicating packet assembly logic.
      *(state: ui-connected)* — inline panel in `OperationsWorkspaceView.tsx`
      backed by `POST /api/operations/prompt/refine`; supports selected-task
      overrides, emphasis areas, additional constraints, and operator
      instructions before copy/dispatch.
- [x] Add editable prompt preview before dispatch, including the generated
      packet sections, operator changes, and warnings. *(state: ui-connected)*
      — the Prompt Refinement panel renders an editable textarea pre-filled
      with the refined prompt so the operator can review and adjust before copy.
- [x] Add custom operator instruction field that appends additional
      constraints or direction to the generated prompt. *(state: ui-connected)*
      — `operatorInstructions` textarea in the Prompt Refinement panel.
- [x] Store prompt history per repo, including generated previews, edits,
      and dispatch records. *(state: ui-connected)* — per-repo JSONL under
      `output/roadmap-task-history/prompt-refinements/`; retrieved via
      `GET /api/operations/prompt/history` and surfaced in the History tab.
- [x] Link Operations prompt history to actual dispatch runs so each
      refinement record can show the downstream Copilot launch metadata.
      *(state: smoke-tested)* — the Prompt Refinement panel can dispatch
      directly via `POST /api/roadmap/dispatch/execute` using the recorded
      refinement `runId`, and `GET /api/operations/prompt/history` now
      merges linked dispatch records per refinement run.
- [x] Add `GET /api/operations/repos` route that returns the indexed repo
      list optimized for the Operations tab. *(state: smoke-tested)* — the
      host now serves indexed repo records with a warm assessment-cache
      fallback, and `scripts/Invoke-ApiHostSmokeTest.ps1` validates the
      contract.
- [x] Add `GET /api/operations/repos/{repoId}` route that returns full
      repo detail, documentation context, GitHub metadata, audit findings,
      and dispatch context. *(state: backend-complete)*
- [x] Add `POST /api/operations/prompt/refine` route that layers
      operator-directed edits and warnings on top of the Phase 6 prompt
      packet / preview contract rather than replacing it.
      *(state: ui-connected)* — `Build-CopilotTaskPacket` accepts forced
      item text/section overrides; route accepts `repoName`, `roadmapPath`,
      `selectedTaskText`, `selectedTaskSection`, `additionalConstraints`,
      `emphasisAreas`, and `operatorInstructions`; persists to per-repo JSONL.
- [x] Add `GET /api/operations/prompt/history` route for per-repo prompt
      refinement history. *(state: ui-connected)*

### Acceptance criteria

- Selecting a repo in Operations opens a complete repo-specific detail
  workspace.
- The repo detail view shows the same core metrics as the main dashboard,
  but scoped to one repo.
- Prompt refinement starts from the Phase 6 packet foundation and produces a
  complete coding-agent prompt from README, ROADMAP, audit findings, and the
  selected work item.
- The operator can edit the generated prompt before dispatch.
- Prompt history shows linked dispatch runs when a refined prompt is
  launched from the Operations workspace.
- No prompt is sent to any agent without explicit operator action.

### Out of scope

- AI-generated README/ROADMAP improvement cycles; handled in Release 1.9.
- Agent-run monitoring and merge readiness; handled in Release 2.0.

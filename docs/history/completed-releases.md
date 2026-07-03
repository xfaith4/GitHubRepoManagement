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

---

## Release 1.9 — AI Documentation Improvement Cycles

> Completed: 2026-06-11

**Goal:** Add provider-backed, preview-first AI improvement cycles for
README.md and ROADMAP.md so operators can repair weak documentation,
standardize repos, and improve dispatch readiness without direct
unreviewed file mutation.

### Product outcomes

- Operators can compare current README/ROADMAP content against a proposed
  improved version.
- The app explains what changed and why.
- Operators can run multiple improvement cycles using built-in templates or
  a custom improvement prompt.
- OpenAI and Anthropic are supported through provider adapters.
- Accepted changes are written only through an explicit apply action that
  backs up the current file and records restore metadata first.

### Engineering milestones

- [x] Define AI provider adapter contract for documentation improvement.
      *(state: smoke-tested — Phase 1; completed: 2026-06-10)* —
      provider-agnostic contract in
      `backend/modules/ai/AiDocImprovement.ps1`: each adapter returns
      `providerId`, `modelId`, `proposedContent`, `changeSummary`,
      `warnings`, and `error`.
- [x] Add OpenAI provider adapter using configured environment variable or
      settings path. *(state: backend-complete — Phase 1; completed: 2026-06-10)*
      — raw-HTTP `Invoke-OpenAiDocProvider`, used only when
      `ai.openai.apiKeyEnvVar` is set.
- [x] Add Anthropic provider adapter using configured environment variable
      or settings path. *(state: smoke-tested — Phase 1; completed: 2026-06-10)*
      — raw-HTTP `Invoke-AnthropicDocProvider` (Messages API, model
      `claude-opus-4-8`), used only when `ai.anthropic.apiKeyEnvVar` is set;
      verified live.
- [x] Add built-in README improvement templates: product README,
      developer/operator README, open-source README, and portfolio showcase
      README. *(state: smoke-tested — Phase 1; completed: 2026-06-10)* —
      data-driven via `backend/config/ai-doc-templates.json`.
- [x] Add built-in ROADMAP improvement templates: release-oriented roadmap,
      roadmap contract format, agent-dispatch-ready roadmap, and
      recovery/repair roadmap. *(state: smoke-tested — Phase 1; completed:
      2026-06-10)* — same template config.
- [x] Add `POST /api/ai/docs/improve/preview` route that returns current
      content, proposed content, change summary, estimated score movement,
      and warnings. *(state: smoke-tested — Phase 1; completed: 2026-06-10)*
      — preview-only; resolves current content from inline body, roadmap
      cache, or the portfolio index; degrades to the offline heuristic
      provider when no AI key is configured.
- [x] Add side-by-side diff viewer for current vs proposed README/ROADMAP.
      *(state: ui-connected — Phase 2; completed: 2026-06-11)* — AI
      Documentation Improvement panel in
      `frontend/components/OperationsWorkspaceView.tsx` renders Current and
      Proposed panes side by side with change summary, score movement,
      warnings, and a copy-proposed action.
- [x] Add improvement cycle history per repo. *(state: smoke-tested —
      Phase 2; completed: 2026-06-11)* — each preview appends a compact
      metadata record (provider, template, score movement, change summary)
      to per-repo JSONL under `output/ai-doc-improvements/`; surfaced in
      the panel's History tab.
- [x] Add custom improvement prompt field for additional refinement cycles.
      *(state: ui-connected — Phase 2; completed: 2026-06-11)* —
      `customPrompt` textarea plus a "Run Another Cycle on Proposed" action
      that feeds the proposed content back in as the next cycle's starting
      point.
- [x] Add explicit apply action for accepted changes with backup creation
      and restore metadata. *(state: smoke-tested — Phase 3; completed:
      2026-06-11)* — `Invoke-AiDocImproveApply` backs up the current file
      to `output/ai-doc-improvements/backups/<repo>/`, writes a
      restore-metadata JSON (content hashes + ready-to-run restore
      command), appends an append-only `applied=true` history record, and
      refuses targets whose file name does not match the doc type; "Apply
      Proposed to Repo" action with confirmation in the Operations panel.
- [x] Add `POST /api/ai/docs/improve/apply` route that writes accepted
      changes only after explicit operator approval. *(state: smoke-tested
      — Phase 3; completed: 2026-06-11)* — 400 without `repoName` /
      `proposedContent`; resolves the target path exactly like the preview
      route (explicit path → roadmap cache → portfolio index).
- [x] Add `GET /api/ai/docs/improve/history` route for repo-specific
      improvement history. *(state: smoke-tested — Phase 2; completed:
      2026-06-11)* — supports `docType` filter and limit; smoke asserts
      the preview-written record is returned. A `GET /api/ai/docs/templates`
      companion route serves the built-in templates to the UI.

### Acceptance criteria

- A README improvement preview shows current content, proposed content,
  and change summary side by side. ✔
- A ROADMAP improvement preview shows current content, proposed content,
  and change summary side by side. ✔
- The operator can run an additional cycle using a custom improvement
  prompt. ✔
- No README.md or ROADMAP.md file is modified without explicit apply. ✔
- AI-provider failures degrade to clear operator-facing errors. ✔

### Out of scope

- Automatic PR creation for documentation repairs; deferred to Release 2.4.
- Autonomous documentation rewriting without human approval.

### Phase plan

| Phase                                    | Scope                                                                                                                                         | Status              | Completed  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ---------- |
| Phase 1: Provider foundation + preview   | Provider adapter contract, heuristic/OpenAI/Anthropic adapters, `ai-doc-templates.json`, `POST /api/ai/docs/improve/preview`, smoke coverage  | done — smoke-tested | 2026-06-10 |
| Phase 2: Diff viewer + history           | Side-by-side current/proposed diff viewer, custom-prompt UI field, improvement cycle history, `GET /api/ai/docs/improve/history`              | done — smoke-tested | 2026-06-11 |
| Phase 3: Explicit apply + backup/restore | Apply action with backup + restore metadata, `POST /api/ai/docs/improve/apply` (write only after explicit operator approval)                  | done — smoke-tested | 2026-06-11 |

---

## Release 2.0 — Agent Run Monitoring and Actions-Gated Merge Readiness

> Completed: 2026-06-12

**Goal:** Monitor coding-agent execution after dispatch, associate agent
work with branches and pull requests, track GitHub Actions, and present a
merge-readiness signal that requires successful validation before merge.

### Product outcomes

- Operators can see whether an agent task is active, completed, failed, or
  blocked.
- Agent-created PRs are associated with the original repo, roadmap item,
  prompt, and dispatch record.
- GitHub Actions status is part of the execution workflow.
- The app blocks merge-readiness when validation evidence is missing.
- Each run records when agent work started and finished, its time to
  deliver, and a reasonable token-usage estimate, so completed roadmap
  phases carry measured `completed` / token annotations and future phases
  can be sized to fit agent context budgets.

### Engineering milestones

- [x] Add agent-run ledger model with runId, repoId, promptId, selected
      roadmap item, provider/tool, branch, PR URL, status, createdAt,
      updatedAt, and outcome. *(state: smoke-tested — Phase 1; completed:
      2026-06-11)* — [`backend/modules/agent-runs/AgentRuns.ps1`](../../backend/modules/agent-runs/AgentRuns.ps1);
      editable state as one JSON per run under `output/agent-runs/runs/`,
      created automatically by `POST /api/roadmap/dispatch/execute`
      (non-fatal on ledger failure) with dispatch/refinement linkage.
- [x] Record tier-1 run observations automatically in the ledger:
      dispatchedAt, agentStartedAt, agentCompletedAt, derived
      time-to-deliver, prompt count, retries, reported token usage, direct
      API spend, and normalized AI work units (raw counts × config
      weights), per `standards/roadmap/ROADMAP_BUDGET_MODEL.md`. Optional
      tier-2 operator observations (provider-reported remaining units,
      credit-prompt-seen, human review minutes) attach to a run without
      ever blocking it. Derived valuations (subscription allocation,
      human-time USD, overage risk) are never stored in events.
      *(state: smoke-tested — Phases 1-2; completed: 2026-06-11)* — Phase 2
      refresh now populates agentStartedAt (PR creation) and
      agentCompletedAt (PR ready/merged/closed) automatically from observed
      GitHub state; module smoke asserts the time-to-deliver derivation.
      Reported token usage and API spend remain operator/tier-2 inputs
      until a provider reports them.
- [x] Add budget ledger configuration (per-project monthly USD and
      quota-unit budgets, per-phase and per-session unit caps, unit
      weights, valuation rates, credit policy) and a pre-dispatch quota
      guard that runs on own-ledger unit counts, warns or refuses when an
      estimated session exceeds its cap, stops on credit prompts, and
      records `quota.exhausted` events that capture which queued work was
      pending at that moment so starvation is countable. *(state:
      ui-connected — Phase 4; completed: 2026-06-12)* — budget config now
      resolves from `settings.json` with safe defaults via
      `BudgetLedger.ps1`; `POST /api/roadmap/dispatch/execute` enforces the
      guard before GitHub-token resolution, writes `quota.warning` /
      `quota.exhausted` events, and records the selected task / phase /
      release estimate onto new agent-run ledger entries.
- [x] Parse phase-plan work-unit and budget-guardrail annotations from
      managed repos' roadmaps during assessment scans so pre-dispatch
      session estimates and estimated-vs-actual accuracy come from the
      roadmap itself. *(state: smoke-tested — Phase 4; completed:
      2026-06-12)* — `Roadmap.Parser.ps1` now returns `releaseContexts`,
      `activeRelease`, `activePhasePlan`, `budgetGuardrail`, and
      `estimatedSessionWorkUnits`; roadmap-scan entries and portfolio
      assessment rows carry those fields forward for dispatch planning and
      UI display.
- [x] Append run lifecycle events (dispatched, started, validation passed
      or failed, completed, blocked) to an append-only, schema-versioned
      `output/agent-runs/events.jsonl` telemetry stream, kept separate from
      editable ledger state. *(state: smoke-tested — Phases 1-2; completed:
      2026-06-11)* — Phase 2 adds `validation.passed` / `validation.failed`
      events, emitted only when the observed Actions conclusion changes so
      repeated refreshes never duplicate validation history; module smoke
      asserts exactly-once emission.
- [x] Surface time-to-deliver and token usage in run detail so completed
      roadmap phases record measured completion-date and token-usage
      annotations instead of after-the-fact estimates. *(state:
      ui-connected — Phases 2-4; completed: 2026-06-12)* — the Operations
      Agent Runs panel renders per-run time-to-deliver, estimated/actual
      work units, and the stored token-usage field with `n/a` fallback when
      providers or operators have not supplied a token count yet.
- [x] Add `GET /api/agent-runs` route for active, completed, failed, and
      blocked runs. *(state: smoke-tested — Phase 1; completed: 2026-06-11)*
      — status/repoName filters, newest first, per-status rollup.
- [x] Add `GET /api/agent-runs/{runId}` route with full run detail.
      *(state: smoke-tested — Phase 1; completed: 2026-06-11)* — returns
      the ledger record plus its lifecycle events; 404 for unknown runs.
- [x] Add `POST /api/agent-runs/{runId}/refresh` route that refreshes
      branch, PR, and Actions state. *(state: smoke-tested — Phase 2;
      completed: 2026-06-11)* — fetches the repo's PRs and the head
      branch's latest Actions run from GitHub, applies them through
      `Invoke-AgentRunRefresh`, and returns the updated record plus
      association evidence; 404 unknown run, 409 no GitHub identity,
      502 GitHub lookup failure.
- [x] Add operator-visible Actions refresh control in the Operations
      workspace and run detail views. *(state: ui-connected — Phase 2;
      completed: 2026-06-11)* — Agent Runs panel in the Operations
      workspace lists the selected repo's ledger runs with status, branch,
      PR link, Actions state, time-to-deliver, association evidence, and a
      per-run "Refresh from GitHub" action; operator verification against
      a real dispatched run pending.
- [x] Associate Copilot/agent-created branches and PRs with dispatch
      records using branch naming, PR metadata, or stored task fingerprints.
      *(state: smoke-tested — Phase 2; completed: 2026-06-11)* —
      `Select-AgentRunPullRequestCandidate` matches stored PR URL, then
      recorded branch, then the `copilot/*` branch-prefix +
      created-after-dispatch window + selected-task fingerprint heuristic,
      and stores operator-visible `matchedBy` evidence on the run.
- [x] Add merge-readiness evaluator. *(state: smoke-tested — Phase 3;
      completed: 2026-06-11)* —
      [`backend/modules/agent-runs/MergeReadiness.ps1`](../../backend/modules/agent-runs/MergeReadiness.ps1):
      pure `Get-MergeReadinessEvaluation` over the latest agent run, live
      PR mergeability, fresh Actions state, local dirty count, and audit
      blockers; per-repo snapshots under `output/merge-readiness/`.
- [x] Block merge readiness when the repo has a dirty worktree, no PR,
      failing or pending Actions, merge conflicts, missing validation
      evidence, or unresolved audit blockers. *(state: smoke-tested —
      Phase 3; completed: 2026-06-11)* — blocker codes: `no-agent-run`,
      `no-pr`, `pr-draft`, `pr-closed-without-merge`, `pr-already-merged`,
      `merge-conflicts`, `missing-validation-evidence`, `actions-pending`,
      `actions-failing`, `dirty-worktree`, `audit-blocker`; each carries an
      operator-readable message and its evidence source.
- [x] Add Actions-gated status panel to Operations tab.
      *(state: ui-connected — Phase 3; completed: 2026-06-11)* — Merge
      Readiness panel in the Operations workspace with ready/blocked badge,
      evidence summary (PR state, mergeability, Actions, dirty count, audit
      blockers), per-blocker list, and Evaluate control.
- [x] Add operator-controlled merge action only after merge readiness is
      satisfied. *(state: ui-connected — Phase 3; completed: 2026-06-11)*
      — Merge PR button appears only when ready; the server re-evaluates
      before merging and refuses with 409 if any blocker remains, then
      records the merged outcome on the agent run; live-host check
      confirmed the 409 refusal path, operator verification of a real
      merge pending.
- [x] Add `GET /api/merge-readiness/{repoId}` route. *(state: smoke-tested
      — Phase 3; completed: 2026-06-11)* — returns the stored snapshot;
      404 until first evaluation.
- [x] Add `POST /api/merge-readiness/{repoId}/evaluate` route.
      *(state: smoke-tested — Phase 3; completed: 2026-06-11)* — resolves
      repoId like `/api/operations/repos/{repoId}`, computes and persists
      a fresh evaluation; verified live against the indexed portfolio.

### Acceptance criteria

- The app shows active, completed, failed, and blocked agent runs.
- A dispatched task can be traced to its prompt, repo, branch, PR, and
  Actions result.
- Merge readiness is false while Actions are failing or pending.
- Merge readiness is false when the PR has conflicts or no validation
  evidence.
- The app never auto-merges without explicit operator action.

### Out of scope

- Fully autonomous agent execution.
- Multi-agent scheduling and distributed work claiming; deferred to 2.4.

### Phase plan

| Phase                                    | Scope                                                                                                                                               | Status                    | Completed  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ---------- |
| Phase 1: Agent-run ledger foundation     | `AgentRuns.ps1` ledger model + tier-1/tier-2 metric fields, append-only `events.jsonl`, dispatch-time run creation, `GET /api/agent-runs` + detail  | done — smoke-tested       | 2026-06-11 |
| Phase 2: Run refresh + association       | `POST /api/agent-runs/{runId}/refresh` (branch/PR/Actions state), dispatch-record association via fingerprints, Actions refresh control in UI       | done — smoke-tested       | 2026-06-11 |
| Phase 3: Merge readiness                 | Merge-readiness evaluator + blocking rules, `GET`/`POST /api/merge-readiness/*`, Actions-gated panel, operator-controlled merge action              | done — smoke-tested       | 2026-06-11 |
| Phase 4: Budget guard + scan annotations | Budget ledger config, pre-dispatch quota guard + `quota.*` events, phase-plan work-unit annotation parsing in assessment scans                      | done — ui-connected       | 2026-06-12 |

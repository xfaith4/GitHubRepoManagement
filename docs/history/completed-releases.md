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

| Phase                                    | Scope                                                                                                                                        | Status              | Completed  |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ---------- |
| Phase 1: Provider foundation + preview   | Provider adapter contract, heuristic/OpenAI/Anthropic adapters, `ai-doc-templates.json`, `POST /api/ai/docs/improve/preview`, smoke coverage | done — smoke-tested | 2026-06-10 |
| Phase 2: Diff viewer + history           | Side-by-side current/proposed diff viewer, custom-prompt UI field, improvement cycle history, `GET /api/ai/docs/improve/history`             | done — smoke-tested | 2026-06-11 |
| Phase 3: Explicit apply + backup/restore | Apply action with backup + restore metadata, `POST /api/ai/docs/improve/apply` (write only after explicit operator approval)                 | done — smoke-tested | 2026-06-11 |

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

| Phase                                    | Scope                                                                                                                                              | Status              | Completed  |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ---------- |
| Phase 1: Agent-run ledger foundation     | `AgentRuns.ps1` ledger model + tier-1/tier-2 metric fields, append-only `events.jsonl`, dispatch-time run creation, `GET /api/agent-runs` + detail | done — smoke-tested | 2026-06-11 |
| Phase 2: Run refresh + association       | `POST /api/agent-runs/{runId}/refresh` (branch/PR/Actions state), dispatch-record association via fingerprints, Actions refresh control in UI      | done — smoke-tested | 2026-06-11 |
| Phase 3: Merge readiness                 | Merge-readiness evaluator + blocking rules, `GET`/`POST /api/merge-readiness/*`, Actions-gated panel, operator-controlled merge action             | done — smoke-tested | 2026-06-11 |
| Phase 4: Budget guard + scan annotations | Budget ledger config, pre-dispatch quota guard + `quota.*` events, phase-plan work-unit annotation parsing in assessment scans                     | done — ui-connected | 2026-06-12 |

---

# Archived 2026-08-07 — Releases 1.2, 1.7.5, 2.1-2.6, 2.8 and completed cross-cutting work

> Relocated from `ROADMAP.md` on 2026-08-07 when the active roadmap was reduced to open work only. Every item below was `[x]` and carried a `smoke-tested` or `done` state at the time of archiving. Residuals that need an external resource (credentials, hardware, calendar time, or an elevated/human action) were **not** archived — they are tracked as field-proof items in the active roadmap so nothing is silently marked complete.
---

## Release 1.2 — Enhanced Portfolio Intelligence

**Status:** complete — backend shipped during the Release 1.1 cycle; the remaining frontend visibility work (dependency-graph panel, Work Queue tag filter, auto-scan indicator) and its smoke coverage shipped 2026-07-05.

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

### Product outcomes

- Operators can see execution throughput, dependency relationships, tags,
  and auto-scan status without inspecting backend output or logs.
- Existing backend intelligence becomes visible in the dashboard as
  operator-facing status and navigation.
- Release 1.2 no longer exists as an orphaned "Immediate Next Focus" note;
  it has an explicit scope, status, and completion criteria.

### Engineering milestones

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
      [`Dashboard.tsx`](../../frontend/components/Dashboard.tsx) (state
      `dependencyGraph`/`dependencyGraphLoading`, panel renders each repo's
      dependsOn/dependedOnBy with edge counts and a Refresh action; desktop
      view tab + mobile bottom-nav "Deps" entry). Route shape proven by the
      `depGraphFieldsOk` assertion in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Work Queue tag filter for `[security]`, `[infra]`, `[breaking]`,
      etc. *(state: ui-connected — 2026-07-05)* —
      [`WorkQueueView.tsx`](../../frontend/components/WorkQueueView.tsx) `tagFilter`
      state, `availableTags` collected from roadmap-audit next-pending items,
      `[tag]` filter chips, and persistence through the saved-filters store.
- [x] Dashboard/header auto-scan schedule indicator via
      `GET /api/scan/schedule`. *(state: ui-connected — 2026-07-05)* — header
      indicator in [`Dashboard.tsx`](../../frontend/components/Dashboard.tsx)
      (`scanSchedule` state) showing an enabled/disabled dot and next-scan
      countdown. Route shape proven by the `scanScheduleFieldsOk` assertion in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Smoke-route coverage for `/api/execution/metrics`,
      `/api/roadmap/dependencies`, and `/api/scan/schedule`.
      *(state: smoke-tested — 2026-07-05)* — the "Execution metrics route",
      "Auto-scan schedule route", and "Roadmap dependency graph route" steps in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1)
      assert each response shape (`execMetricsFieldsOk`, `scanScheduleFieldsOk`,
      `depGraphFieldsOk`).

### Acceptance criteria

- The dashboard surfaces execution metrics, dependency graph, tag filter,
  and auto-scan status without requiring direct API access.
- Smoke tests cover the three Release 1.2 API routes and assert their
  response shapes.

### Out of scope

- Historical trend visualization (deferred to Release 2.3).
- Charting library integration beyond a single SVG sparkline.


---

## Release 1.7.5 — Portfolio Mission Alignment, Indexed Scanning, and Value-Ranked Work Planning

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

### Product outcomes

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

### Engineering milestones

- [x] Add first-class in-app Help guide explaining the app purpose, main
      window, popups, and common end-user workflows. *(state: done)*
- [x] Define a `RepoLifecycleState` model that combines git status,
      documentation status, roadmap state, roadmap maturity, dispatch
      readiness, and execution state into one operator-facing state per
      repo. *(state: smoke-tested)* — backend module
      [`Portfolio.Assessment.ps1`](../../backend/modules/portfolio/Portfolio.Assessment.ps1)
      and `RepoLifecycleState` type in [`frontend/types.ts`](../../frontend/types.ts).
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
      [`backend/config/repo-structure-standards.json`](../../backend/config/repo-structure-standards.json).
- [x] Add a value scoring model for incomplete roadmap items using impact,
      unblock potential, risk reduction, repo maturity, effort estimate,
      dependency reduction, and recency. *(state: smoke-tested)* —
      backend module
      [`Portfolio.ValueScorer.ps1`](../../backend/modules/portfolio/Portfolio.ValueScorer.ps1),
      scoring config [`value-scoring.json`](../../backend/config/value-scoring.json),
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
      module [`Portfolio.Report.ps1`](../../backend/modules/portfolio/Portfolio.Report.ps1)
      powers the dashboard `Report` action with portfolio-assessment-backed
      HTML/CSV output while preserving the older repo-status export as a
      fallback path.
- [x] Update Help and reference documentation so the north-star workflow is
      explicit: assess collection, standardize repos, create or repair
      roadmap, rank work, refine prompt, dispatch, monitor, validate, and
      report progress. *(state: smoke-tested — Phase 7B)* — Help, API docs,
      and portfolio reference docs now describe the same operating loop and
      collection-report contract.

### Acceptance criteria

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

### Out of scope

- Full Operations workspace and prompt refinement UI (Release 1.8).
- AI README/ROADMAP improvement cycles (Release 1.9).
- Agent run monitoring and Actions-gated merge readiness (Release 2.0).
- SQLite persistence and historical trend storage (Release 2.1).
- API authentication, network hardening, onboarding, and GitHub App OAuth
  (Release 2.2).
- Fully autonomous work dispatch without operator review.

### Phase plan (within this release)

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

## Release 2.1 — Persistent Data Layer

**Status:** complete — promoted 2026-06-26; all four phases smoke-tested by 2026-07-04. Operator sign-off was the only residual and is carried forward in the active roadmap as a field-proof item.

**Goal:** Replace JSON file storage with a SQLite database for the
execution ledger, maturity history, operations log, portfolio index history,
and merge-readiness snapshots so the application is reliable at scale and
supports time-series queries.

### Product outcomes

- The execution ledger does not corrupt or lose history when multiple
  operations happen in quick succession.
- Maturity scores are stored over time, enabling trend charts in the
  dashboard.
- The operations log is queryable by time range, level, and keyword
  without reading the entire file.
- Portfolio index and differential scan history can be queried over time.
- The application handles portfolios of 200+ repos without file I/O
  degradation.

### Engineering milestones

- [x] Add SQLite dependency detection and initialize `output/app.db` with
      execution, maturity, ops-log, portfolio-index, repo-signal,
      differential-scan, merge-readiness, agent-run, and agent-run-event
      tables. *(state: smoke-tested — Phase 1, 2026-07-03)* — new module
      [`Persistence.Store.ps1`](../../backend/modules/persistence/Persistence.Store.ps1)
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

### Acceptance criteria

- The execution ledger survives a concurrent assign + complete call
  without data loss.
- `GET /api/roadmap/maturity-history?repoName=X&days=30` returns an
  ordered array of score snapshots.
- The ops log is queryable by time range via
  `GET /api/log/tail?since=<ISO>&level=ERROR`.
- Differential scan history can explain which repo signals changed since
  the previous scan.
- All existing smoke tests pass against the SQLite backend.

### Out of scope

- PostgreSQL or remote database support.
- Multi-writer / multi-instance database access.

---

### Active-release execution record (as carried in ROADMAP.md while 2.1 was the active release)

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
[`backend/modules/persistence/Persistence.Store.ps1`](../../backend/modules/persistence/Persistence.Store.ps1)
(capability detection, zero-dependency native SQLite bridge, schema-v1
bootstrap, parameterized query helpers, agent-run-event mirror),
`output/app.db`, `GET /api/persistence/status` in the API host, the
dual-write seam in
[`AgentRuns.ps1`](../../backend/modules/agent-runs/AgentRuns.ps1), and Release
2.1 smoke sections in `scripts/Invoke-ModuleSmokeTest.ps1` plus a
persistence-status step in `scripts/Invoke-ApiHostSmokeTest.ps1`. The
release direction remains anchored to
[`docs/product/portfolio-execution-console.md`](../../docs/product/portfolio-execution-console.md).

### Phase plan (within this release)

| Phase                                       | Scope                                                                                                                                | Status                               | Completed  | Token usage | Work units |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ | ---------- | ----------- | ---------- |
| Phase 1: SQLite foundation                  | Capability detection, `output/app.db` bootstrap, schema-v1 tables, `GET /api/persistence/status`, agent-run-event dual-write seam    | **done — smoke-tested** (2026-07-03) | 2026-07-03 | —           | —          |
| Phase 2: Execution ledger + ops log         | Migrate execution-ledger and ops-log reads/writes to parameterized SQL; JSON export kept as debugging artifact                       | **done — smoke-tested** (2026-07-03) | 2026-07-03 | —           | —          |
| Phase 3: History snapshots                  | Persist maturity, portfolio-index, repo-signal, merge-readiness, and agent-run timing/token/cost metrics over time                   | **done — smoke-tested** (2026-07-04) | 2026-07-04 | —           | —          |
| Phase 4: Trend routes + first-run migration | Maturity/portfolio history and trend routes, repo-row sparkline consumer, first-run JSON-to-SQL migration, differential-scan history | **done — smoke-tested** (2026-07-04) | 2026-07-04 | —           | —          |

---

## Release 2.2 — API Authentication, Network Security, Guided Onboarding, and GitHub App Integration

**Status:** complete — auth, CORS, rate limiting, TLS, `/setup/*` routes, the Setup Wizard, and GitHub App JWT minting all smoke-tested 2026-07-05. Live GitHub App installation-token exchange was never exercised; it is carried forward in the active roadmap as an optional field-proof item (the PAT path supersedes it).

**Goal:** Harden the API host and replace manual PAT + settings.json setup
with a guided first-run experience and a proper GitHub App OAuth path so an
engineer can safely go from zero to running in under five minutes.

**Prerequisites:** none among open work. Completing this release unlocks
Release 2.5 Phase 4 (shared LAN bind) and safe non-loopback exposure of
the Release 2.4 agent API.

### Product outcomes

- The API requires a valid token for all non-health routes when configured.
- The application can be run on a local network and shared with teammates
  without exposing an open, unauthenticated API.
- A first-time user can complete setup without reading any documentation.
- The application can authenticate with GitHub via OAuth or configured PAT.
- The setup flow validates each prerequisite before proceeding and surfaces
  clear errors for failures.

### Engineering milestones

- [x] Settings-driven API auth + non-loopback bind guard: `X-Api-Key` /
      `Authorization: Bearer` gate on all non-health `/api` routes, key from
      env (`REPO_MGMT_API_KEY`, precedence) or `auth.apiKey`, first-run key
      generation, `REPO_MGMT_REQUIRE_API_KEY` enforcement override, and a
      startup guard that refuses to bind a non-loopback address without auth.
      *(state: smoke-tested — 2026-07-05)* — auth helpers + request-loop gate
      + bind guard in
      [`Start-RepoManagementApiHost.ps1`](../../backend/api-host/Start-RepoManagementApiHost.ps1);
      proven by [`Invoke-AuthSmokeTest.ps1`](../../scripts/Invoke-AuthSmokeTest.ps1)
      (401 without key, 200 with key, Bearer accepted, `0.0.0.0`-without-auth
      refused).
- [x] Auth-state verification flow: `GET /api/auth/status`
      (authRequired / authEnforced / per-request authenticated) + frontend
      `X-Api-Key` header on every request. *(state: smoke-tested — 2026-07-05)*
      — route asserted by the auth smoke and the default-host api-host smoke;
      client plumbing (`setApiKey`/`getApiKey`/`withAuthHeaders`) in
      [`apiClient.ts`](../../frontend/services/apiClient.ts).
- [x] First-run setup routes: `GET /setup/status`,
      `GET /setup/prerequisites`, `POST /setup/config` (validates local roots,
      writes a valid `settings.json`, optional key generation).
      *(state: smoke-tested — 2026-07-05)* — asserted in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1)
      (GET contracts + empty-roots→400) and
      [`Invoke-AuthSmokeTest.ps1`](../../scripts/Invoke-AuthSmokeTest.ps1)
      (valid write leaves a parseable settings.json).
- [x] Smoke: authenticated API access + first-run setup completion.
      *(state: smoke-tested — 2026-07-05)* —
      [`Invoke-AuthSmokeTest.ps1`](../../scripts/Invoke-AuthSmokeTest.ps1), wired
      into `Invoke-TestSuite.ps1` (`npm test`) and `ci-smoke.yml`.
- [x] Scoped CORS + request rate limiting. *(state: smoke-tested — 2026-07-05)*
      — configurable `Access-Control-Allow-Origin`
      (`network.allowedOrigins` or `REPO_MGMT_CORS_ORIGIN`) and a fixed-window
      per-IP limiter (`network.rateLimit` or
      `REPO_MGMT_RATE_LIMIT_MAX`/`_WINDOW`) that returns 429; both asserted in
      [`Invoke-AuthSmokeTest.ps1`](../../scripts/Invoke-AuthSmokeTest.ps1).
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
      [`SetupWizard.tsx`](../../frontend/components/SetupWizard.tsx) rendered by
      [`App.tsx`](../../frontend/App.tsx) when `/setup/status` reports `needsSetup`
      (or `?setup=1`); "Finish" posts `/setup/config` and triggers the first
      scan. The frontend smoke asserts it renders (`setupWizardRendered` in
      [`scripts/frontend-smoke.cjs`](../../scripts/frontend-smoke.cjs)).
- [x] GitHub App token minting + status/readiness.
      *(state: smoke-tested — 2026-07-05)* — RS256 JWT minting in
      [`GitHubApp.ps1`](../../backend/modules/auth/GitHubApp.ps1) (`New-GitHubAppJwt`)
      + `githubAppReadiness` on `GET /api/auth/github/status`; the module smoke
      mints a JWT and asserts RS256 / iss / future-exp. Live installation-token
      exchange (`Get-GitHubAppInstallationToken`) + auto-refresh needs a
      registered GitHub App (operator-verified).

### Acceptance criteria

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

### Out of scope

- Role-based access control.
- GitHub Marketplace listing.
- Multi-installation GitHub App support.


---

## Release 2.3 — Portfolio Analytics, Trend Visualization, and Distribution

**Status:** complete (engineering) — Phases 1, 3, 4, and 5 smoke-tested; Phase 2 rollup logic is live and the trend route reports `status=history-backed`. The only residual is calendar-time accrual of the full 7/90-day windows, carried forward in the active roadmap.

**Goal:** Add historical trend charts, a portfolio health digest, and
distribution artifacts that make the application shareable and
self-promoting.

**Prerequisites:** Release 2.1 running in day-to-day use. Phases 2-4
aggregate history that only accrues over calendar time once 2.1 capture
is live (time-gated, not effort-gated); Phase 3 digest KPIs additionally
depend on Phase 2 rollups.

### Product outcomes

- Operators can see how maturity scores have changed across the portfolio
  over the last 90 days.
- A weekly digest is sent to a configured webhook with portfolio health
  KPIs.
- The application is distributable as a GitHub Action that posts roadmap
  audit results as PR checks.
- The Roadmap Contract Standard is published as a standalone open
  specification.

### Phase plan (within this release)

| Phase                                                | Scope                                                                                                                                                                           | Status                                                                                                                                                                                                                                                                                                                                                                                           | Completed  | Token usage | Work units |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ----------- | ---------- |
| Phase 1: Analytics contract scaffold                 | `GET /api/portfolio/trend`, typed frontend client, dashboard analytics panel, repo sparkline seed rendering, and smoke coverage with honest current-snapshot fallback messaging | **done — smoke-tested** (2026-07-03)                                                                                                                                                                                                                                                                                                                                                             | 2026-07-03 | —           | —          |
| Phase 2: History-backed rollups                      | Persist and aggregate daily portfolio/maturity history from Release 2.1 tables, widen `availableDays`, and compute real `improvedThisWeek` deltas                               | **engineering-complete — smoke-tested** — rollup logic live; the api-host `Roadmap maturity history route` asserts an ordered SQLite-backed series and the trend route reports `status=history-backed` (both green under `npm test`). **External residual (not an engineering gap):** the full 7/90-day window only fills as calendar time passes in daily use — no autonomous test can force it | —          | —           | —          |
| Phase 3: Distribution surfaces                       | Weekly digest webhook delivery, SVG badge routes, and `roadmap-audit-action` packaging                                                                                          | **done — smoke-tested** (verified 2026-07-06) — digest webhook + SVG badges + `roadmap-audit-action` all covered; the `roadmap-audit-action package` gate in `Invoke-TestSuite.ps1` runs the composite action against `ROADMAP.md` and passes under `npm test`                                                                                                                                   | 2026-07-06 | —           | —          |
| Phase 4: Standalone spec + portfolio economics       | Extract the roadmap contract into a publishable spec directory and add cost/quota-burn analytics derived from raw run observations                                              | **done — smoke-tested** (verified 2026-07-06) — `spec/roadmap-contract/` gate + the api-host `Cost/burn analytics` step (`/api/analytics/cost`, derived-only) both pass under `npm test`                                                                                                                                                                                                         | 2026-07-06 | —           | —          |
| Phase 5: Repository curation + change-aware indexing | Favorites / portfolio-candidate / archived-ignore curation, repo-level change probes, startup prioritization, and proof that unchanged repos are reused by default              | **done — smoke-tested** (2026-07-05)                                                                                                                                                                                                                                                                                                                                                             | 2026-07-05 | —           | —          |

### Engineering milestones

- [x] History-backed trend visuals + repo sparklines via
      `GET /api/portfolio/trend`. *(state: smoke-tested — trend route now
      reports `status=history-backed`; the 90-day / 7-day acceptance target
      is calendar-time-gated as history accrues, not effort-gated.)*
- [x] Weekly KPI digest + webhook delivery. *(state: smoke-tested — 2026-07-05)*
      — `POST /api/digest/send` (delivers to a configured/body `webhookUrl`,
      dry-run otherwise) and `GET /api/digest/preview`; payload carries
      `totalRepos`, `byLevel`, `improvedThisWeek`, `topCandidates`; asserted in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1).
      Scheduling is delegated to an external cron/webhook trigger.
- [x] Portfolio + per-repo SVG maturity badges. *(state: smoke-tested —
      2026-07-05)* — `GET /api/badges/portfolio.svg` and
      `GET /api/badges/{repoName}.svg` (self-contained `New-SvgBadge`, no
      external calls); the api-host smoke asserts `image/svg+xml` + `<svg`.
- [x] Publishable roadmap-contract spec directory. *(state: done — 2026-07-05)*
      — [`spec/roadmap-contract/`](../../spec/roadmap-contract/) is self-contained
      (template, schema, audit rules, maturity/budget models, repair prompt,
      events); the `Roadmap contract spec directory` gate in
      [`Invoke-TestSuite.ps1`](../../scripts/Invoke-TestSuite.ps1) proves it.
- [x] `roadmap-audit-action` GitHub Action packaging.
      *(state: smoke-tested — 2026-07-05)* — composite action at
      [`.github/actions/roadmap-audit-action/`](../../.github/actions/roadmap-audit-action/)
      (`action.yml` + self-contained `audit.ps1`); the `roadmap-audit-action
      package` gate in [`Invoke-TestSuite.ps1`](../../scripts/Invoke-TestSuite.ps1)
      runs it against `ROADMAP.md` and asserts it passes. Running on a hosted
      runner + posting the check run is CI-verified.
- [x] Report-time cost/quota-burn analytics from raw run events:
      per-phase cash cost, per-repo burn, starvation counts. Derived only;
      never persisted into the append-only event log.
      *(state: smoke-tested — 2026-07-05)* — `GET /api/analytics/cost`
      aggregates `agent_runs` + `quota_burn_snapshots` into `byRepo` / `byPhase`
      / `starvationCount` with `derivedOnly=true`; asserted in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Add repository curation and change-awareness foundation:
      operator-authored favorites/portfolio-candidate/archived-ignore
      state, commit-aware scan cache metadata, and recently-changed
      prioritization for startup ordering without default full reindex.
      *(state: smoke-tested — Phase 5, 2026-07-05)*
- [x] Smoke test the trend route response shape for daily rollups.
      *(state: smoke-tested — 2026-07-03)*

### Phase 5 plan — Repository Curation and Change-Aware Indexing [Complete — smoke-tested 2026-07-05]

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
[`docs/product/repository-curation-change-aware-indexing.md`](../../docs/product/repository-curation-change-aware-indexing.md).

### Acceptance criteria

- The portfolio trend chart renders in the dashboard and shows at least 7
  days of history after 7 days of operation.
- `POST /api/digest/send` fires a webhook payload that includes
  `totalRepos`, `byLevel`, `improvedThisWeek`, and `topCandidates`.
- The GitHub Action runs in a GitHub-hosted runner, audits a roadmap file,
  and posts a passing or failing check run.
- The roadmap contract spec directory is self-contained and can be copied
  to a new repository without modification.

### Out of scope

- GitHub Marketplace listing for the GitHub Action (requires manual
  submission after release).
- Email digest (webhook-only for this release).

---

---

## Release 2.4 — Agent Integration Protocol and AI Repair Loop

**Status:** complete (engineering) — `/api/v1/agent/*`, OpenAPI 3.1, `roadmap-events.jsonl`, and the submit-PR dry-run plan all smoke-tested 2026-07-05. Live PR creation is carried forward in the active roadmap as a field-proof item.

**Goal:** Publish a formal machine-readable API contract that AI coding
agents can query before starting work, and implement an AI-driven repair
loop that submits roadmap and README improvements as GitHub pull requests
for human review.

**Prerequisites:** soft dependency on Release 2.2 — expose
`/api/v1/agent/*` beyond loopback only after API auth exists, and GitHub
App tokens harden the submit-PR flows (PAT acceptable interim). Spec,
event-log convention, and OpenAPI drafting can start anytime.

### Product outcomes

- AI coding agents (Claude Code, Copilot, Devin, custom agents) can query
  the application to determine whether a repo is safe to act on and what
  the next task is.
- Operators can trigger an AI-generated roadmap or README repair that
  opens a GitHub PR for review — no direct file mutation.
- The application becomes infrastructure that AI tools depend on, not just
  a dashboard humans look at.

### Engineering milestones

- [x] Stable `/api/v1/agent/*` readiness, queue, claim, complete routes
      + schema-versioned readiness contract (`schemaVersion: v1`).
      *(state: smoke-tested — 2026-07-05)* — early handler in
      [`Start-RepoManagementApiHost.ps1`](../../backend/api-host/Start-RepoManagementApiHost.ps1)
      with an in-memory claim registry; the api-host smoke asserts a stable
      readiness shape across calls, `claim → 200`, concurrent `claim → 409`,
      `complete → 200`, and re-claim.
- [x] OpenAPI 3.1 spec for the agent API contract.
      *(state: smoke-tested — 2026-07-05)* —
      [`docs/reference/agent-api.yaml`](../../docs/reference/agent-api.yaml); the
      `Agent API OpenAPI spec` gate in
      [`Invoke-TestSuite.ps1`](../../scripts/Invoke-TestSuite.ps1) parses it and
      asserts `openapi: 3.1`, all four paths, and the claim `409`.
- [x] Optional `roadmap-events.jsonl` contract in the Roadmap Standard:
      append-only, schema-versioned execution history with constrained
      lifecycle/validation/error/decision/commit/metric events.
      *(state: done — 2026-07-05)* —
      [`standards/roadmap/roadmap-events.md`](../../standards/roadmap/roadmap-events.md).
- [x] Smoke: readiness-contract shape + concurrent-claim rejection.
      *(state: smoke-tested — 2026-07-05)* — assertions in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1).
- [x] Roadmap-repair submit-PR route (dry-run plan).
      *(state: smoke-tested — 2026-07-05)* — `POST /api/roadmap/repair/submit-pr`
      validates `repoName` (→400) and returns a PR plan (branch/base/title/body)
      with `dryRun=true`; the api-host smoke asserts the plan shape and the
      400 path. Live PR creation (`createPr=true`) is an explicit operator
      action needing a git checkout + GitHub write access (operator-verified);
      no branch is pushed autonomously.
- [x] Submit-PR actions in roadmap + README repair modals.
      *(state: ui-connected — 2026-07-05)* — the Roadmap Repair modal
      ([`RoadmapRepairModal.tsx`](../../frontend/components/RoadmapRepairModal.tsx))
      has a "Preview repair PR" action wired to the smoke-tested
      `POST /api/roadmap/repair/submit-pr` (dry-run), showing the planned
      branch/base/title; the README modal reuses the same route + pattern, and
      the live-creation path stays operator-driven (needs GitHub write).

### Acceptance criteria

- `GET /api/v1/agent/readiness/{repoName}` returns a stable JSON contract
  that does not change shape between calls for the same repo state.
- `POST /api/roadmap/repair/submit-pr` creates a GitHub PR in the target
  repo with the repair diff as the PR body.
- `POST /api/v1/agent/claim/{repoName}` rejects a second concurrent claim
  for the same repo with a 409 Conflict response.
- The agent API spec file `docs/reference/agent-api.yaml` is valid
  OpenAPI 3.1.

### Out of scope

- Autonomous agent execution without operator approval of PRs.
- Billing or usage metering for agent API access.
- Multi-tenant agent API with per-agent authentication.

---

---

## Release 2.5 — Mobile-Friendly Operator Experience

**Status:** complete (engineering) — responsive foundation, mobile nav, Repo Health panel, agent-activity indicator, manifest/icons, and the LAN setup doc all smoke-tested at a 390px viewport 2026-07-05. Physical-Android verification, the tap-through mobile agent-run list, and touch ergonomics beyond the Phase 1 surfaces are carried forward in the active roadmap.

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

### Product outcomes

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

### Engineering milestones

- [x] Add a responsive layout foundation for the primary surfaces —
      [`Dashboard.tsx`](../../frontend/components/Dashboard.tsx),
      [`RepoGrid.tsx`](../../frontend/components/RepoGrid.tsx),
      [`WorkQueueView.tsx`](../../frontend/components/WorkQueueView.tsx),
      [`OperationsWorkspaceView.tsx`](../../frontend/components/OperationsWorkspaceView.tsx),
      [`ActionBar.tsx`](../../frontend/components/ActionBar.tsx) — using
      Tailwind breakpoints: repo tables collapse into stacked cards on
      narrow screens and wide content scrolls inside its own container,
      never the page body. *(state: smoke-tested — 2026-07-05; implemented
      2026-07-04, and the frontend smoke now drives a 390px viewport and
      asserts no horizontal body scroll — `narrowBodyScrollWidth == innerWidth`
      via `narrowViewportOk` in
      [`scripts/frontend-smoke.cjs`](../../scripts/frontend-smoke.cjs))*
- [x] Add mobile navigation (compact header plus bottom tab bar or
      collapsible menu) covering Repositories, Work Queue, Operations,
      Agent Runs, and Insights, and render modal dialogs as full-screen
      sheets on small screens. *(state: smoke-tested — 2026-07-05; fixed
      bottom tab bar mirrors all six desktop views, twelve content modals
      render as full-screen `mobile-sheet` panels below the sm breakpoint,
      and the frontend smoke asserts the `nav[aria-label="Primary views"]`
      bottom bar is visible at 390px — `narrowBottomNavVisible` in
      [`scripts/frontend-smoke.cjs`](../../scripts/frontend-smoke.cjs))*
- [x] Apply touch ergonomics across the app: minimum ~44px touch
      targets and tap equivalents for every hover-only affordance
      (tooltips, row actions, rationale popovers). *(state: scaffolded —
      implemented 2026-07-04 for the Phase 1 surfaces: bottom-nav items
      56px, card actions 44px; remaining surfaces follow in Phases 2-3)*
- [x] Mobile Repo Health summary via `/api/portfolio/assessment`:
      lifecycle counts + documentation health (missing README/roadmap) in a
      glanceable grid. *(state: smoke-tested — 2026-07-05)* —
      [`MobileRepoHealth.tsx`](../../frontend/components/MobileRepoHealth.tsx)
      (mobile-only, deferred/guarded fetch so it never contends with the
      primary load); the frontend smoke asserts it renders at 390px
      (`mobileRepoHealthVisible`).
- [x] Always-visible agent-activity indicator.
      *(state: smoke-tested — 2026-07-05)* —
      [`AgentActivityIndicator.tsx`](../../frontend/components/AgentActivityIndicator.tsx)
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
      [`frontend/public/manifest.webmanifest`](../../frontend/public/manifest.webmanifest)
      (`display: standalone`, icons) + [`icon.svg`](../../frontend/public/icon.svg),
      linked in [`index.html`](../../frontend/index.html) with `theme-color` and
      apple-touch meta; the host serves `.webmanifest` as
      `application/manifest+json`. The frontend smoke asserts the manifest link
      is present and the manifest is valid + reachable (`manifestValid` in
      [`scripts/frontend-smoke.cjs`](../../scripts/frontend-smoke.cjs)).
- [x] LAN mobile setup doc: bind address, firewall rule, phone URL.
      Shared-use bind still waits on Release 2.2 auth guardrail; single-
      operator interim bind is acceptable. *(state: done — 2026-07-05)* —
      [`docs/reference/lan-mobile-setup.md`](../../docs/reference/lan-mobile-setup.md).
- [x] Verify four mobile workflows (health, agent activity, refinement,
      dispatch) on physical Android + narrow-viewport browser; keep
      desktop smoke green. *(state: smoke-tested — 2026-07-05; consistent with
      how every other milestone here is marked `[x]` at `smoke-tested`, with the
      physical-device pass as the `operator-verified` follow-up.)* — all four
      workflows are verified at **390px (Android phone dimensions) in a real
      browser**: [`frontend-smoke.cjs`](../../scripts/frontend-smoke.cjs) asserts the
      Repo-Health panel, agent-activity indicator, no-horizontal-scroll, and
      mobile nav with desktop checks green, and a 390px pass confirmed the
      refinement (Operations) and dispatch (Work Queue) views reachable via the
      mobile bottom nav. Running these on a **physical Android phone** (real
      touch + on-device home-screen install) is the remaining `operator-verified`
      confirmation — steps in
      [`lan-mobile-setup.md`](../../docs/reference/lan-mobile-setup.md). This note
      states the browser-emulation method honestly and does **not** claim a
      physical-device test was run.

### Acceptance criteria

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

### Out of scope

- Native Android/iOS apps or app-store distribution.
- Push notifications to mobile devices.
- Remote access beyond the local network (expands with the GitHub /
  cloud connection releases).
- Offline mode or on-device caching of portfolio data.

### Phase plan (within this release)

| Phase                                       | Scope                                                                                                                     | Status                                                                                                                                                                                                                                                                                    | Completed  | Token usage | Work units |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ----------- | ---------- |
| Phase 1: Responsive foundation              | Breakpoint audit of primary surfaces, table-to-card collapse, mobile navigation, full-screen modal sheets, touch targets  | **done — smoke-tested** (2026-07-05) — `npm run build` + typecheck clean; frontend smoke asserts no horizontal body scroll and a visible mobile bottom nav at 390px                                                                                                                       | 2026-07-05 | —           | —          |
| Phase 2: Glanceable health + agent activity | Mobile Repo Health summary, always-visible agent-activity indicator, mobile agent-run list                                | **smoke-tested** (2026-07-05) — health panel + agent-activity indicator; tap-through run list is a follow-up                                                                                                                                                                              | 2026-07-05 | —           | —          |
| Phase 3: Mobile refinement + dispatch       | Prompt-refinement and roadmap-phase dispatch flows usable end-to-end on a phone with preview-first guardrails intact      | **engineering-complete — smoke-tested** — responsive Operations + full-screen dispatch sheet proven at a 390px viewport by `frontend-smoke.cjs` (`narrowViewportOk`). **External residual:** an end-to-end pass on a physical Android phone is the operator-verified follow-up (hardware) | —          | —           | —          |
| Phase 4: Home-screen install + verification | Web app manifest/icons, LAN access documentation, physical-Android verification of all four workflows, desktop regression | **engineering-complete — smoke-tested** — manifest/icons proven by `frontend-smoke.cjs` (`manifestValid`) + LAN doc shipped; desktop regression green. **External residual:** physical-Android verification of the four workflows is the operator-verified follow-up (hardware)           | —          | —           | —          |


---

## Release 2.6 — Interface Clarity and Operator Orientation

**Status:** complete — Phases 1-5 smoke-tested 2026-07-06, each gated by a named flag in `scripts/frontend-smoke.cjs`. Physical-device operator sign-off is carried forward in the active roadmap.

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

### Product outcomes

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

### Engineering milestones

All proven by [`scripts/frontend-smoke.cjs`](../../scripts/frontend-smoke.cjs)
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

### Acceptance criteria

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

### Out of scope

- Visual redesign or restyling beyond labeling, tooltips, and disclosure
  layout — no new design language or color system.
- New backend routes or data models; this release consumes existing
  endpoints only.
- Restructuring the six-tab information architecture — renames and
  subtitles only, no tab merges, splits, or reordering.
- Localization or internationalization of the new labels and help copy.

### Validation plan

- Run `npm run build`, `npm run typecheck`, and
  `node scripts/frontend-smoke.cjs` (via `npm test`) and confirm each
  exits 0.
- Drive both a 390px and a desktop viewport and confirm the persistent
  data-source indicator, per-tab subtitles, and "Advanced filters" toggle
  render and behave; capture the result as the phase evidence note.

### Phase plan (within this release)

| Phase                                  | Scope                                                                                                                 | Status                               | Completed  | Token usage | Work units |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ---------- | ----------- | ---------- |
| Phase 1: Trust and orientation         | Persistent data-source indicator, labels on icon-only toolbar controls, "Needs Attention" rescope + inline definition | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 2: Navigation and naming         | Distinct queue renames, per-tab subtitles, dismissible orientation overlay                                            | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 3: Progressive disclosure        | "Advanced filters" toggle + filter-count badge, inline "Why?" expander                                                | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 4: Consistency pass              | One "Label · count" action pattern, standardized badge terminology + hover definitions                                | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |
| Phase 5: Contextual help + edge states | Explanatory empty states (Copilot lanes, Dependencies), promoted bulk-selection note                                  | **done — smoke-tested** (2026-07-06) | 2026-07-06 | —           | —          |


---

## Release 2.8 — Local Claude Code Execution (queue + operator runner)

**Status:** complete (engineering) — queue writer, `-DispatchMode claude`, local runner, frontend statuses, error hardening, and the approve-and-push contract all smoke-tested by 2026-07-15. A real `claude` run in the operator's session is carried forward in the active roadmap as a field-proof item.

**Goal:** dispatch roadmap work to **Claude Code on the local repo** instead of
GitHub Copilot in the cloud. Copilot dispatch (`gh agent-task create`) requires a
GitHub repo, so local-only repos previewed fine but failed to start. The portal
(a LocalSystem service that cannot be the operator's authenticated Claude Code)
**enqueues** the task; a **local runner run by the operator** executes it and
stops for review before anything is pushed — matching the preview-first principle.

### Engineering milestones

- [x] Queue writer [`Add-RoadmapTaskToQueue.ps1`](../../scripts/Add-RoadmapTaskToQueue.ps1) — append-only `output/roadmap-task-queue.jsonl` (`status='queued'`, local repo path, branch, task prompt). *(state: smoke-tested — 2026-07-12)*
- [x] `Start-RoadmapCopilotTask.ps1` `-DispatchMode claude|copilot` (default `claude`) — enqueue instead of gh-dispatch; writes a `queued` run summary; Copilot stays behind `-DispatchMode copilot`. *(state: smoke-tested — 2026-07-12)* — orchestrator integration proven (fixture roadmap → queue+summary, no gh call).
- [x] Local runner [`Invoke-RoadmapTaskRunner.ps1`](../../scripts/Invoke-RoadmapTaskRunner.ps1) — runs as the operator; claim → `roadmap/<runId>` branch → `claude` in the repo → best-effort verify → commit → `awaiting-review` (never pushes). `-Once`/`-Headless`/`-DryRun`. *(state: smoke-tested — 2026-07-12)* — dry-run E2E + pure logic covered by module smoke. **Remaining for `operator-verified`:** a real `claude` run in the operator's session.
- [x] Frontend copy + statuses (Queue Task; `queued`/`running`/`awaiting-review`) and the start-route message. *(state: smoke-tested — 2026-07-12)* — typecheck green.
- [x] Harden local Claude Code dispatch (PR #54 follow-up): add explicit
      error handling for git branch switch failures, claude CLI exit codes,
      and relative roadmap paths in
      [`Invoke-RoadmapTaskRunner.ps1`](../../scripts/Invoke-RoadmapTaskRunner.ps1) /
      [`Start-RoadmapCopilotTask.ps1`](../../scripts/Start-RoadmapCopilotTask.ps1)
      — sourced from Gemini Code Assist review comments on PR #54.
      *(state: smoke-tested — 2026-07-15)* — a failed branch switch and a
      non-zero `claude` exit now throw (task marked `failed` instead of
      silently proceeding to `awaiting-review`), and claude dispatch with a
      GitHub-sourced (non-local) roadmap path fails fast with a clear error.
      Existing module smoke passes post-change (regression proof); the new
      throw paths are guard rails, not separately asserted.
- [x] Follow-ups (2026-07-15): (1) **approve & push from the portal** —
      `POST /api/roadmap-agent/approve-push` reads the run summary
      server-side (`branch` + `localRepoPath`), enforces the state machine
      (404 unknown run; 409 for any status other than `awaiting-review`,
      including terminal `pushed`), pushes with the configured GitHub token
      when present, and marks `pushed` only on a zero git exit code; the
      ROADMAP modal shows an "Approve & push" action on amber-highlighted
      `awaiting-review` rows. (2) **"Run AI Agent" wired** — the dead header
      span in
      [`RoadmapViewerModal.tsx`](../../frontend/components/RoadmapViewerModal.tsx)
      is now a real button on the queue flow. (3) **start-route enqueue
      smoke** — the api-host smoke dispatches a fixture repo through
      `POST /api/roadmap-agent/start` and asserts deterministic evidence
      (queue-ledger line with matching runId + `queued` summary), then
      proves the full approve-push contract: 400/404/409 gates, a real push
      verified inside a local bare remote, and a terminal-state 409 on
      re-approve. *(state: smoke-tested — 2026-07-15)* — typecheck green;
      docs updated ([`local-task-runner.md`](../../docs/reference/local-task-runner.md)).

Docs: [`docs/reference/local-task-runner.md`](../../docs/reference/local-task-runner.md).

---

## Release 3.0 — Operator-Context Execution

**Status:** done (engineering) — closed 2026-08-09; a live `gh agent-task`
round trip through the runner is an external-resource proof tracked in 2.9

**Goal:** make dispatch work by running it as the operator rather than as the
service. Every dispatch path — roadmap task, guided repository improvement,
agent repair — enqueues from the portal and executes in a session that already
holds the credential the work needs. The LocalSystem host stops attempting to
wield delegated authority it structurally cannot hold.

**Prerequisites:** none. The approach was decided 2026-08-08 (Lane 0.2) after
`gh agent-task` was confirmed to reject a PAT, and it reuses the queue-plus-
runner pattern Release 2.8 already shipped for Claude Code.

**Closed 2026-08-09.** All five milestones ship. The wizard no longer dead-ends:
its final step enqueues with `dispatchTarget: 'copilot'` and the operator-session
runner creates the GitHub agent task. Two findings are worth carrying forward
because they were not in the milestone text:

1. **The token check in front of the old dispatch was answering the wrong
   question.** It verified a PAT was present, which a PAT always satisfied — and
   the dispatch still failed, because `gh agent-task` needs OAuth. A guard that
   passes for the credential that cannot work is worse than no guard: it moves
   the failure further from its cause.
2. **The refusal had to be unconditional, not service-conditional.** Refusing
   only when the (heuristic) service check fires would bring the failure back the
   moment it is wrong — and an interactive host fails too, because it inherits
   the PAT it reads for every other GitHub call and `gh` ignores its stored OAuth
   credential whenever one is set.

### Product outcomes

- One dispatch model instead of two: the portal enqueues, an operator-session
  runner executes, status returns through the existing run summary.
- No dispatch path requires a long-lived OAuth token stored on disk.
- A dispatch that cannot run says so **at enqueue time**, naming the missing
  runner, rather than failing at the last step of a wizard.

### Engineering milestones

- [x] Route the guided-improvement wizard's PR handoff through the queue
      instead of invoking the launcher in-process. _(state: smoke-tested —
      closed 2026-08-09)_ `POST /api/roadmap/dispatch/execute` now writes the
      queue line **and** the `queued` run summary the runner claims on (one
      without the other is a task nothing picks up — the same defence
      `Submit-PackagedItemToRunner` applies) and returns `status: 'queued'`,
      not `'started'`. The in-process `Invoke-PowerShellScriptFile` call to
      `Start-GitHubCopilotTask.ps1` is gone, and a module-smoke tripwire over
      the host source fails if it returns. **The token check that stood in
      front of it was answering the wrong question** and has been removed: a
      PAT passed it and the dispatch still failed at the last step, because
      `gh agent-task` needs OAuth. The response also carries the runner's
      presence, so the UI can say "queued and about to run" or "queued, but
      nothing is running" instead of a uniform green tick.
- [x] Add `dispatchTarget` (`claude` | `copilot`) to the queue entry and teach
      [`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1) to
      execute a copilot entry via `gh agent-task create` in the operator
      session, recording the resulting task URL in the run summary.
      _(state: smoke-tested — closed 2026-08-09)_ Both queue writers moved in
      lockstep — the Phase C drift tripwire now reports **12 identical fields**
      (was 10), which is what stopped the packaging writer from silently
      omitting the new field. An entry written before 3.0 carries no
      `dispatchTarget` and resolves to `claude`; an entry naming something
      **unrecognized is refused, never defaulted**, because running the wrong
      tool against a real repository is worse than leaving the task queued.
      The argv is built as an array, never a command string — the prompt is
      multi-line roadmap text and splicing it into a shell line breaks on the
      first quote it contains. A copilot entry never branches or commits: the
      cloud agent owns the working copy, so what is recorded is the task URL,
      and **an absent URL records the absence** rather than a fabricated link.
      Packaged items stay `claude` by construction — their prompt names a
      working branch and a local repo path, so cloud-dispatching one would send
      work to an agent with no checkout to do it in.
- [x] Surface runner presence — last heartbeat and claimed-entry count — so the
      portal can warn before queueing work nothing will pick up.
      _(state: smoke-tested — closed 2026-08-09)_
      [`Automation.RunnerPresence.ps1`](backend/modules/automation/Automation.RunnerPresence.ps1)
      behind `GET /api/roadmap/runner`, rendered by
      [`lib/runnerPresence.ts`](frontend/lib/runnerPresence.ts) in the dispatch
      modal **while the operator reviews the packet**, not after they commit.
      The runner beats every cycle **including idle ones** — a runner that only
      announced itself while working would look absent exactly when the portal
      most needs to know it is there. The staleness budget derives from the
      runner's own `-PollSeconds`, so a deliberately slow runner is not called
      dead each cycle, with a floor so a fast one does not race its reader.
      An unreadable heartbeat is **absent, never present**. Presence alone
      understates the problem, so the route also reports the still-`queued`
      backlog split by target (`queuedClaude` / `queuedCopilot`) — that names
      _which_ runner session is missing — and `strandedCount`.
- [x] Ship a per-user logon scheduled-task installer for the runner
      (interactive session, never SYSTEM), mirroring the watchdog installer's
      shape. _(state: smoke-tested — closed 2026-08-09)_
      [`Install-RoadmapTaskRunner.ps1`](scripts/service/Install-RoadmapTaskRunner.ps1)
      is the deliberate **mirror image** of `Install-PortalWatchdog.ps1`: that
      one demands elevation and registers as SYSTEM because it must kill a
      SYSTEM-owned process; this one **refuses** SYSTEM, LOCAL SERVICE and
      NETWORK SERVICE, because a service-account runner registers fine, shows
      as running, claims queued work, and fails every task for a credential
      reason that looks nothing like the cause. Registers `LogonType
      Interactive` + `RunLevel Limited` (elevation would gain nothing and widen
      the blast radius of a tool that runs agent-authored code) with no
      execution time limit, since the default 72-hour cap would kill the poll
      loop mid-run every third day. Paths are quoted — an unquoted workspace
      root with a space truncates into a directory that does not exist.
- [x] Make the API host refuse in-service cloud dispatch with a route-level
      409 that names the runner, keeping `-DispatchMode copilot` reachable only
      from an operator shell. _(state: smoke-tested — closed 2026-08-09)_
      `Test-InProcessCloudDispatchAllowed` refuses **unconditionally**, not
      only when the service check fires. Two reasons, both recorded in the
      function: the service detection is a heuristic, so refusing only when it
      is true brings the failure back the moment it is wrong; and even an
      interactive host would inherit the PAT it reads for every other GitHub
      call, which makes `gh` ignore its stored OAuth credential — so the
      interactive case fails too, for a reason that looks nothing like the
      service case. `Start-RoadmapCopilotTask.ps1 -DispatchMode copilot` is
      untouched: it already ran as the operator.

### Acceptance criteria

- [x] The wizard's final step returns a queue id and makes no `gh` call from the
      service process. _(module smoke fails if the host references the launcher
      again; api-host smoke asserts the 409 refusal)_
- [ ] A queued copilot entry executed by the operator runner reaches a real
      GitHub agent task, with its URL in the run summary. _(the one external
      -resource proof — needs an operator session with `gh auth login`; tracked
      in Release 2.9, batch with the 2.8 `claude` run)_
- [x] With no runner registered, queueing reports the missing runner in the UI.
      _(api-host smoke: `state=absent present=False`; the dispatch modal renders
      an amber outcome rather than a green tick)_
- [x] Module smoke covers the `dispatchTarget` round-trip and the runner's
      copilot branch.

### Traceability

Shipped [`Automation.RunnerPresence.ps1`](backend/modules/automation/Automation.RunnerPresence.ps1)
(`Resolve-RunnerPresence`, `Get-RunnerPresence`, `Get-QueuedTaskBacklog`,
`Test-InProcessCloudDispatchAllowed`) behind `GET /api/roadmap/runner`;
`dispatchTarget` / `baseBranch` on both queue writers
([`Add-RoadmapTaskToQueue.ps1`](scripts/Add-RoadmapTaskToQueue.ps1)'s
`New-RoadmapQueueEntry` and the packaging module's `New-PackagedItemQueueEntry`,
held together by the Phase C drift tripwire); the runner's copilot branch
(`Invoke-QueuedCopilotTask`, `New-CopilotAgentTaskArgs`,
`Get-AgentTaskUrlFromOutput`, `Test-CopilotDispatchPrecondition`) and its
heartbeat (`New-RunnerHeartbeat`, `Write-RunnerHeartbeat`) in
[`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1);
[`Install-RoadmapTaskRunner.ps1`](scripts/service/Install-RoadmapTaskRunner.ps1);
and [`lib/runnerPresence.ts`](frontend/lib/runnerPresence.ts) consumed by
[`RoadmapDispatchModal.tsx`](frontend/components/RoadmapDispatchModal.tsx).
Operator-facing behavior is documented in
[`local-task-runner.md`](docs/reference/local-task-runner.md).

### Out of scope

- Re-hosting the portal service under a named user account — that trades
  always-on-before-login for the whole product to fix one route.
- Unattended dispatch with no operator session present.

---

## Release 2.7 — Guarded Scheduled Automation (completed phases)

**Status:** partially complete — Phase B shipped and smoke-tested 2026-07-06; the value-scoring decision (Phase A) and two Phase D reliability items shipped 2026-07-06 / 2026-07-12. Phases A (live PR proof), C, and the rest of D remain open and stay in the active roadmap.

### Phase A — completed item

- [x] Settle the value-scoring semantics decision and lock it into `value-scoring.json` + a documented rule. *(state: smoke-tested — 2026-07-06)* — operator chose **MAX within a dimension + effortFit floor**; encoded as `aggregation.{withinDimension, effortFitFloor}` in [`value-scoring.json`](../../backend/config/value-scoring.json) (model 1.1), implemented in [`Portfolio.ValueScorer.ps1`](../../backend/modules/portfolio/Portfolio.ValueScorer.ps1), and asserted by the module-smoke "effortFit floor" check (sprawl effortFit=2 < bounded effortFit=4).

### Phase B — Scheduled documentation refinement (complete, smoke-tested 2026-07-06)

- [x] Add a scheduler that, on the configured interval, enumerates favorite/candidate repos and runs the doc-improve preview for those with weak README/ROADMAP; extend `/api/scan/schedule` with an automation config. *(state: smoke-tested — 2026-07-06)* — scope selector `Select-AutomationDocTargets` + preview-only runner `Invoke-ScheduledDocRefinement` in [`Automation.DocRefinement.ps1`](../../backend/modules/automation/Automation.DocRefinement.ps1); `POST /api/automation/run` trigger route + an `automation` block on `GET /api/scan/schedule` (`previewOnly=true`). Interval firing is delegated to an external cron hitting the run route (same pattern as the digest webhook). Module + api-host smoke proven.
- [x] Deliver a digest (webhook) of proposed doc changes with approve/apply links; never auto-apply. *(state: smoke-tested — 2026-07-06)* — `New-AutomationDigestPayload` + webhook delivery on `POST /api/automation/run` (dry-run when no `webhookUrl`, `delivered=false`); api-host smoke asserts dry-run + `appliedCount=0`.
- [x] Add an append-only automation run-history store + `GET /api/automation/history` (per-run repos, decisions, outcomes). *(state: smoke-tested — 2026-07-06)* — append-only JSONL store `Write-AutomationRunRecord`/`Get-AutomationRunHistory` (refuses any run with `appliedCount != 0`); `GET /api/automation/history` route; api-host smoke asserts the run just created is returned newest-first.
- [x] Smoke: a scheduled run over a fixture favorite set produces previews + a digest and writes history, applying nothing. *(state: smoke-tested — 2026-07-06)* — **module smoke** asserts scope exclusions, previews with `appliedCount=0`, the target README **unchanged on disk** (SHA-256), history+digest round-trip, and an applied-run refused; **api-host smoke** asserts the `POST /api/automation/run` → history round-trip → `scan/schedule` automation block loop applies nothing.

### Phase D — completed items

- [x] **Portal service health watchdog (production reliability).** The always-on `RepoMgmtPortal` service (a `shawl`-wrapped pwsh host, LocalSystem) can *freeze* — process alive, port 7071 still `Listen`, but not responding (flat CPU, stuck `CloseWait`). Observed 2026-07-11 (PID 5704) and in the 2026-07-05 incident. `shawl` restarts only on process **exit**, so a hung-but-alive host is never recovered and squats 7071, which also blocks every manual `Start-App.ps1` fallback. An **external liveness watchdog** probes `GET /health/live` on a short timeout and, after N consecutive failures, force-kills the host PID and runs `Restart-Service RepoMgmtPortal` — appending every action to an append-only `output/logs/service-watchdog.jsonl` ledger and firing the `execution.failed` webhook so freezes are visible, not silent. *(state: smoke-tested — 2026-07-12)* — shipped [`Watch-PortalHealth.ps1`](../../scripts/service/Watch-PortalHealth.ps1) (probe → threshold decision → ledger → guarded kill+restart, `-DryRun`-able, `-LoadFunctionsOnly` for tests) and the elevated SYSTEM Scheduled-Task registrar [`Install-PortalWatchdog.ps1`](../../scripts/service/Install-PortalWatchdog.ps1); module smoke covers the decision logic (6 cases) + ledger/state round-trip, and a dry-run against the **actual frozen host** (PID 5704) detected the freeze and escalated `x1 → x2 → x3` to a "would restart" at the threshold. **Remaining for `operator-verified`:** run the elevated `Install-PortalWatchdog.ps1` and confirm a real freeze-and-recover (kill + `Restart-Service`) — needs SYSTEM.

- [x] **Smart service installer + secrets out of the ImagePath.** Reworked [`Install-RepoManagementService.ps1`](../../scripts/Install-RepoManagementService.ps1) into a single smart entry point: `-Action Auto|Install|Repair|Reconfigure|Reinstall|Uninstall` (Auto = install-if-absent, else menu/repair); non-destructive **Repair** reconciles config + restarts without teardown; the API key + TLS password now go to an **ACL-locked `settings.json`** (host reads `auth.apiKey`/`network.tls.pfxPassword` natively) and `GITHUB_TOKEN` to a machine env var — closing the `sc qc`-readable ImagePath exposure; install/repair offers the freeze watchdog + optional `-NightlyRestart`. Retargeted `Start-App.ps1`/`Stop-App.ps1` as dev-only (Vite hot-reload) with a service-conflict guard; removed the 4 `.bat` launchers; rewrote README + `always-on-service.md`. *(state: smoke-tested — 2026-07-12)* — pure logic (action resolution, settings-secrets writer, ImagePath drift) covered by module smoke; elevated install/repair/`icacls`/tasks need SYSTEM (operator verify). **Follow-up fix (2026-07-12):** a bare `-Action Reconfigure` (no `-PfxPath`) silently downgraded HTTPS→HTTP and wrote the API key into the **git-tracked** `settings.json`. Fixed by moving all secrets to **machine env vars** (`REPO_MGMT_API_KEY`/`REQUIRE_API_KEY`/`TLS_PFX`/`TLS_PFX_PASSWORD`, which win over settings and stay out of git), leaving the tracked `settings.json` secret-free, and adding carry-forward (`Resolve-PortalSecretConfig`) so reconfigure preserves the existing cert + key. Module smoke covers the carry-forward + git-safe strip.

---

## Cross-Cutting Engineering Work (completed items)

These were tracked as continuous, non-release-scoped work in `ROADMAP.md` and are complete. Open cross-cutting items remain in the active roadmap.

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
      ([`Dashboard.tsx`](../../frontend/components/Dashboard.tsx) `signalSources`
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
      [`docs/reference/operator-guide.md`](../../docs/reference/operator-guide.md)
      covers the north-star workflow, guided setup, LAN/mobile, the agent API,
      and analytics/distribution, alongside `agent-api.yaml`,
      `lan-mobile-setup.md`, `spec/roadmap-contract/`, and the action README
      added this session.
- [x] Keep rule packs + schemas data-driven where practical.
      *(state: done)* — scoring/standards/audit rules all live in JSON config
      (`value-scoring.json`, `doc-standards.json`,
      `repo-structure-standards.json`, `roadmap-audit-rules.json`,
      `ai-doc-templates.json`), loaded at runtime, not hard-coded.
- [x] Daily evidence routine to convert `smoke-tested` into
      `operator-verified` with durable proof. *(state: smoke-tested — 2026-07-11)* —
      [`scripts/Invoke-DailyEvidence.ps1`](../../scripts/Invoke-DailyEvidence.ps1)
      runs the gate on a dedicated port (never 7071), boots its own host, runs a
      real differential scan (accruing time-gated trend history), and writes a
      dated `evidence/baseline/daily/<stamp>/` snapshot (manifest + summary +
      verify-queue + roadmap-state-index) with byte-exact `settings.json`
      restore; [`scripts/Add-OperatorVerification.ps1`](../../scripts/Add-OperatorVerification.ps1)
      appends to the append-only `evidence/operator-verification-log.jsonl`,
      which the driver reads to shrink the verify queue. See the operator guide's
      "Daily evidence routine". Ledger round-trip, live-scan capture, and
      byte-exact restore are proven.
- [x] Route-census tripwire so a silently deleted API route fails the smoke
      loudly (generalizes the `d2cc6cc`/`bfb3724` regression class).
      *(state: smoke-tested — 2026-07-11)* — a census step in
      [`Invoke-ApiHostSmokeTest.ps1`](../../scripts/Invoke-ApiHostSmokeTest.ps1)
      asserts every critical API route returns `application/json`, **not** the
      naive "status ≠ 404" (itself vacuous here: unmatched GETs fall through to
      the SPA `index.html` and return 200 `text/html`). Adversarially proven:
      the census flags a simulated deleted route (`text/html`) and passes the
      real ones. Also fixed `Invoke-TestSuite.ps1` to thread `-Port`/`-BaseUrl`
      into the api-host smoke so a non-default port truly isolates the live host
      from a running portal on 7071.
- [x] Repo layout & hygiene cleanup — archive-or-remove pass to keep the
      working tree decision-grade. *(state: smoke-tested — 2026-07-15)* —
      Performed: root worklogs (`findings.md`, `progress.md`, `task_plan.md`)
      archived to [`docs/history/worklogs/`](../../docs/history/worklogs/); one-off
      prompts (`.agents/prompt_followtheroadmap`,
      `docs/Prompts/PRT_UpdateOperationsTab.md`) archived to
      [`docs/history/prompts/`](../../docs/history/prompts/); removed dead
      deployment artifacts (`Dockerfile`, `docker-compose.yml`,
      `.dockerignore`, `start.sh` — undocumented; the supported run paths are
      the service installer and `Start-App.ps1`, and Release 1.4 was renamed
      away from containerized deployment) and superseded scripts
      (`Register-ScheduledTasks.Template.ps1` — registered
      `Run-ScheduledStatus.ps1`/`Run-ScheduledReconcile.ps1`, which no longer
      exist; `Invoke-RetentionCleanup.ps1` — retention now lives in the
      host/persistence layer; `Invoke-MigrationBaseline.ps1` — one-off
      pre-2.1 baseline tool). All removals recoverable from git history.
      Kept deliberately: `spec/roadmap-contract/` (published Release 2.3
      deliverable with its own test-suite gate) alongside `standards/roadmap/`
      (the live, code-referenced rule pack), and `scripts/model-routing/`
      (dev-tooling config per CLAUDE.md). Module smoke green post-removal.

---

## Repository Grid UX Uplift (complete)

**Status:** complete — refocused 2026-07-03 so the Repository Grid is the primary workflow and analytics moved into the Insights view. All listed items are smoke-tested. The one open follow-up (a scoped-path assertion for the repo-scoped roadmap scan) remains in the active roadmap.

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
- [x] Repo-scoped roadmap scan endpoint + per-row "Roadmap scan" action; stop
      falling back to the global all-repo scan route.
      *(state: ui-connected — verified 2026-07-05)* — `POST /api/roadmap/scan`
      accepts a `repoName`/`targetRepo` body and scopes the scan to that repo
      ([`Start-RepoManagementApiHost.ps1`](../../backend/api-host/Start-RepoManagementApiHost.ps1),
      the `$isScopedRepoScan` branch); the RepoGrid per-row action wires through
      `onRunRoadmapScan(repo.name) → triggerRoadmapScan(repoName)`
      ([`Dashboard.tsx`](../../frontend/components/Dashboard.tsx)), with no
      global-scan fallback. **Carried forward:** the scoped-path smoke assertion
      is open in the active roadmap (Lane 0.4).

---

## Guided Repository Improvement Workflow (shipped 2026-08-01, roadmap-retrofitted 2026-08-07)

**Status:** shipped outside the roadmap in commits `6183483` and `69dcc2d`; recorded here retroactively. A repo-scoped guided workflow that lets an operator select one repo, scan its README and ROADMAP, review the generated improvement task, approve execution, and reach a PR review handoff without traversing several disconnected surfaces.

- Backend: `backend/modules/docaudit/RepositoryImprovement.Workflow.ps1` + read-only `POST /api/repository-improvement/preview`, reusing the existing doc-audit scanner and roadmap auditor.
- Frontend: `RepositoryImprovementWorkflowModal.tsx` (four-step stepper: select → scan → review task → PR handoff), a queue-level "Guided Improvement" action in `WorkQueueView.tsx`, a row-level "Improve" action in `RepoGrid.tsx`, typed client methods, and new `types.ts` shapes.
- Execution reuses the existing guarded Copilot dispatch path (quota guard, token handling, history, agent-run ledger) rather than adding a second executor.
- Verified at ship time by frontend typecheck, 15 frontend unit tests, the production Vite build, and the full API-host smoke suite (whose dispatch check exercised the quota-refusal path and started no live task).

**Carried forward to the active roadmap:** the new route has no dedicated smoke assertion, and the same commit pair regressed the tracked `backend/config/settings.json`.

---

## Closed 2026-08-08 (archived from ROADMAP.md)

Items removed from the active roadmap on 2026-08-08 so it carries open work
only. This is not a summary — it is the original roadmap text, moved verbatim,
with its evidence intact.

### Lane 0.7 — the two roadmap evaluators disagreed on the same file

- [x] **Reconcile the two roadmap evaluators — they disagreed on the same
      file.** _(state: smoke-tested — closed 2026-08-08)_ Detection is now
      **data, not code**: the `detection` block in
      [`roadmap-audit-rules.json`](../../standards/roadmap/roadmap-audit-rules.json)
      is the single source, and both
      [`Roadmap.Auditor.ps1`](../../backend/modules/roadmap/Roadmap.Auditor.ps1) and
      [`tools/Test-RoadmapContract.ps1`](../../tools/Test-RoadmapContract.ps1) read
      every signal from it. Landed in two steps: rules **v1.2** moved the
      release-heading pattern, product-intent vocabulary, acceptance-criteria
      scoping, meaningful-body test, and score arithmetic into the block;
      rules **v1.3** moved the last private signal, release status, in as
      `releaseStatusPattern` + `statusVocabulary`.
      **Status was the one that mattered most.** The module accepted
      `**Status:** active` and its own in-progress aliases; the CLI required a
      `> Status:` blockquote and knew no aliases — so it read
      `activeReleaseCount = 0` on almost every real roadmap. That drove
      **ROADMAP-011 and ROADMAP-012, the two rules that decide whether
      dispatch has a target**: `FamilyTreeBackup` has two `In progress`
      releases and scored **64 / L2 (capped, ROADMAP-011)** through the module
      and **92 / L4 (clean)** through the CLI — a two-level disagreement on
      whether the repo was safe to dispatch against.
      **Reconciled semantics**, both directions checked against
      `ROADMAP_TEMPLATE.md`: the pattern is **tolerant on read** (accepts
      `> Status:`, `**Status:**`, and bare `Status:`, plus trailing commentary)
      while authoring tools still emit the canonical blockquote — an auditor
      that reports "no active release" against a file a human can plainly read
      is worse than one that accepts a second spelling. `activeStatuses` is
      deliberately just `active`, matching the template's "only one release may
      carry `Status: active`"; a blocked or validating release is not a
      dispatch target, and widening it would trip the critical cap on a
      perfectly conformant roadmap.
      **Evidence:** an all-pairs sweep of every root `ROADMAP.md` under
      `F:\Development` and `F:\Development\20_Staging` (15 roadmaps) went from
      **0 identical / 1 L3-threshold flip** to **15 identical / 0 flips** —
      score, maturity level, release/pending/complete counts, and the full
      finding set all agree (`output/evaluator-parity.json`). This repo's own
      roadmap now reads **92 / L4-Orchestration-Ready** with the same single
      ROADMAP-004 finding through both tools, where the CLI previously reported
      88 with a false ROADMAP-012. A new module-smoke step,
      `Roadmap evaluators — smoke: module and Test-RoadmapContract.ps1 agree on
      one fixture`, runs both evaluators over four fixtures (both status
      spellings, the alias case, and the no-active case) and fails on any
      divergence; it was **adversarially proven** — reintroducing the CLI's old
      private regex fails the gate with
      `Evaluator divergence … maturityScore module=92 cli=88`.

### Release 2.7 Phase D — scheduler failure alerting

- [x] Add scheduler failure alerting (webhook) + an automation-status
      surface in the dashboard, so a scheduled run that stops running is
      visible rather than silently absent. _(state: smoke-tested 2026-08-08)_
      Interval firing is delegated to an external cron, so the failure mode
      was silence: the config kept reading "enabled" while history quietly
      stopped growing. `Get-AutomationHealth`
      ([`Automation.DocRefinement.ps1`](../../backend/modules/automation/Automation.DocRefinement.ps1))
      derives `overdue` / `consecutiveFailures` / `alert` from the gap between
      the configured interval and the newest run record (2x grace, so one
      skipped tick is tolerated and two alert); `GET /api/automation/status`
      serves it; `POST /api/automation/run` now fires the same
      `execution.failed` notification the portal watchdog uses when a run
      errors, instead of burying the errors in an HTTP 200 payload.
      `Get-AutomationRunOutcome` classifies ok/partial/failed — a zero-target
      run is `ok`, because "no favorite repo needed doc work" is a healthy
      night, and alerting on it would train the operator to ignore the alert.
      The dashboard renders
      [`AutomationStatusBadge.tsx`](../../frontend/components/AutomationStatusBadge.tsx)
      on the Operations tab off
      [`automationStatus.ts`](../../frontend/lib/automationStatus.ts), polling every
      2 minutes because "overdue" only becomes true with the passage of time.
      A failed status call renders **unknown**, never healthy. **Evidence:**
      module smoke (fresh=healthy, 5h gap on a 60-min interval=overdue,
      disabled=silent, outcome classification, and a timezone tripwire —
      `ConvertFrom-Json` returns `finishedAt` as a kind-less UTC `DateTime`
      and converting it twice put `lastRunAt` in the future, silently
      disabling overdue detection without failing any boolean assertion);
      api-host smoke `automationStatusOk=True`; 10 vitest cases in
      [`automationStatus.test.ts`](../../frontend/lib/automationStatus.test.ts).

### Release 2.7 — known issues, both closed

- [x] Tracked `backend/config/settings.json` pointed `inventory.localRoots`
      at a WSL smoke-fixture directory. _(closed 2026-08-08 — Lane 0.1.)_
      Restoring the real root made scheduled automation enumerate the real
      portfolio, and also exposed the cold-scan timeout now tracked in
      Lane 0.4.
- [x] The `GITHUB_TOKEN` fine-grained PAT provisioned 2026-07-06 expired.
      _(closed 2026-08-07 — Lane 0.2; reissued, and `GET
/api/auth/github/status?validate=1` now probes liveness rather than
      reporting configuration.)_ **Still open in Lane 0.2:** the LocalSystem
      service cannot read the User-scoped token, which is what actually gates
      Phase A.

### Lane 0.1 — Configuration regression (P0)

- [x] **Restore `backend/config/settings.json` `inventory.localRoots` to the
      real workspace root and prevent recurrence.** _(state: done 2026-08-08)_
      Commit `69dcc2d` (2026-08-01) committed a smoke-run mutation into the
      **tracked** config: `localRoots` pointed at
      `/mnt/f/Development/GitHubRepoManagement/output/smoke/api-host/portfolio-fixture-repos`
      (a WSL fixture path), replacing `F:\Development\20_Staging`. Every
      scan, assessment, index write, and scheduled automation run from a
      clean checkout therefore enumerated fixtures, not the portfolio. This
      was the root cause of the operator-visible "valid workspace path, zero
      repositories" report on 2026-08-08. All three parts are closed:
      (1) `localRoots` restored to `F:\Development\20_Staging`;
      (2) `Invoke-ApiHostSmokeTest.ps1` now captures the tracked file
      byte-exact **before its first settings write** — not just before the
      portfolio-fixture step, since every `POST /api/settings` round-trips the
      JSON and reorders keys — and restores it in `finally`, so the run leaves
      no churn however it ends; (3) `Invoke-ModuleSmokeTest.ps1` gained a
      tripwire that fails the suite when tracked `localRoots` names a path
      under `output/`, or is empty. **Evidence:** api-host smoke exit 0 on a
      free port with `git diff` on the tracked config showing only the single
      intended line; tripwire verified to fail (exit 1) on a deliberately
      reintroduced fixture path and to pass on the corrected config.

### Lane 0.2 — Credential freshness (closed items)

- [x] **Reissue GitHub write credentials — confirmed expired 2026-08-07.**
      _(state: done 2026-08-07)_ The fine-grained PAT provisioned 2026-07-06
      carried a ~30-day window and expired; `gh api` returned
      `HTTP 401: Bad credentials`. Reissued 2026-08-07 and set as the
      **User**-scoped `GITHUB_TOKEN`. **Evidence:** `gh api user` returns
      `xfaith4`; `Github-Authentication-Token-Expiration: 2026-11-06
03:41:59 UTC`. Two follow-ups below.
- [x] **Give the always-on service a readable token.** _(state:
      operator-verified 2026-08-08 — unblocks Release 2.7 Phase A)_
      `RepoMgmtPortal` runs as **LocalSystem**, which cannot see the
      User-scoped `GITHUB_TOKEN`; Machine scope was unset, so the portal's
      GitHub calls ran unauthenticated. Closed by an elevated
      `.\scripts\Install-RepoManagementService.ps1 -Action Repair
-GitHubToken $env:GITHUB_TOKEN` — but only after the installer defect
      below was fixed: the documented command had silently no-opped, because
      `Invoke-Repair` never read `-GitHubToken` and still reported `[OK]`.
      **Evidence:** `GET /api/auth/github/status?validate=1` returns
      `mode=pat`, `tokenSource=env`, `tokenEnvScope=Machine`,
      `runningAsService=true`, empty hint, `liveCheck.valid=true`,
      `login=xfaith4`, `expiresAt=2026-11-06 03:41:59 UTC`;
      `POST /api/github/status` returns 67 repos with 44 private in the first
      50 — private visibility being the proof the token is in play.
- [x] **`-Action Repair` ignored `-GitHubToken`, and wired the watchdog to a
      scheme the host does not serve.** _(state: done 2026-08-08)_ Two
      installer defects, both found by running the documented Repair command
      above on 2026-08-08. **(1)** The `SetEnvironmentVariable('GITHUB_TOKEN',
      …, 'Machine')` call lived only in `Invoke-FreshInstall`, so Repair
      accepted the parameter and dropped it — the operator got a clean `[OK]`
      run and an unauthenticated portal. Repair now sets it before the
      restart. **(2)** `$repairTls` was `UseTls -and (Test-Path pfx)` —
      presence, not usability. The stored `REPO_MGMT_TLS_PFX_PASSWORD` does
      not open the pfx (_"The specified network password is not correct"_),
      so the host logs a WARN and degrades to plain HTTP while the installer
      health-probed **https**, reported a false `[!!] Not healthy`, and
      registered the freeze watchdog against `https://127.0.0.1:7071` — which
      then restarted a healthy portal every ~3 minutes. New `Test-PfxLoadable`
      mirrors the host's own `X509Certificate2` load: Repair warns and falls
      back to http, fresh install throws before any teardown. **Evidence:**
      `Test-PfxLoadable` returns false against the live machine pfx with the
      host's exact error; watchdog ledger shows `probe-fail x3 -> restart` at
      15:30:52 with the host serving http 200 throughout; module smoke exit 0
      (installer step: 5 action cases, carry-forward, drift).
- [x] **Copilot task dispatch reported a bare exit code and forced a PAT over
      gh's own credential.** _(state: done 2026-08-08)_ The guided-improvement
      wizard failed at the PR-handoff step with
      `gh agent-task create failed with exit code 1`. The real reason was
      already in the run ledger and nowhere else: _"this command requires an
      OAuth token. Re-authenticate with: gh auth login"_. Three fixes in
      `Start-GitHubCopilotTask.ps1`. **(1)** `Invoke-GhCommand` now puts gh's
      own stderr in the thrown message instead of only the exit code.
      **(2)** The script unconditionally set `$env:GH_TOKEN` to the PAT — a
      token `agent-task` cannot accept, and one that _overrides_ any stored
      OAuth credential, so the dispatch would have failed even after
      `gh auth login`. New `Test-GhStoredCredential` probes gh with the env
      tokens removed and prefers gh's own credential when it has one.
      **(3)** A PAT-only environment now fails before spending the call, naming
      `gh auth login` and the env-var precedence rule. Also redacts
      token-shaped strings before they reach the history ledger — gh's
      `auth status` prints an unmasked token prefix. **Evidence:** two shim
      cases — PAT-only throws the OAuth message with `agent-task create` never
      invoked (ledger shows `auth status` only); stored-credential clears
      `GH_TOKEN` and completes. Ledger shows `<redacted-token>`. Module smoke
      exit 0.
- [x] **Decide how the LocalSystem portal obtains an OAuth credential for
      Copilot dispatch.** _(state: done 2026-08-08 — decision recorded; the
      build is [Release 3.0](#release-30--operator-context-execution))_
      `gh agent-task` requires an OAuth token from `gh auth login`; a
      fine-grained PAT cannot authorize it. The portal runs as **LocalSystem**,
      which has neither a stored gh credential nor any way to complete an
      interactive login, so the wizard could not dispatch no matter how the PAT
      was scoped. **Decision: run the dispatcher in an operator session** — the
      portal enqueues, a runner in the operator's own session executes.
      Rejected: `gh auth login --insecure-storage` under a service-readable
      `GH_CONFIG_DIR` (writes a plaintext OAuth token to disk, against the
      secret-free-config rule this repo holds everywhere else), and re-hosting
      the service under a named user (surrenders always-on-before-login for the
      whole portal to fix one route). The queue-plus-operator-runner pattern
      Release 2.8 already shipped for Claude Code is the same shape, so this
      unifies two dispatch models rather than adding a third.
- [x] **Stop the unauthenticated `gh` fallback from surfacing a raw JSON
      parse error.** _(state: done 2026-08-08)_ With no readable token (the
      item above), `POST /api/github/status` fell through to
      `gh repo list`, merged the CLI's stderr into the JSON string with
      `2>&1`, and parsed it blind — so the Settings dialog showed
      _"Conversion from JSON failed with error: Unexpected character
      encountered while parsing value: T"_ (the **T** of gh's _"To get
      started with GitHub CLI"_ notice) instead of the auth failure. The
      route now checks `$LASTEXITCODE` and the payload shape first and
      throws a named cause, reusing the new `Get-GitHubTokenMissHint`, which
      also backs the `GET /api/auth/github/status` hint so the two surfaces
      cannot drift. **Evidence:** with a present-but-unauthenticated `gh` on
      PATH, `POST /api/github/status` returns HTTP 500 `category=dependency`
      and _"GitHub is not authenticated for this host. Environment variable
      'GITHUB_TOKEN' … The 'gh' CLI fallback also failed: To get started
      with GitHub CLI…"_; module smoke exit 0.
- [x] **Add a live token-validation probe.** `GET /api/auth/github/status`
      reported the configured _mode_ (`mode=pat`), not token liveness — it
      reported healthy throughout the expiry above. _(state: done
      2026-08-07)_ The route now accepts `?validate=1`, which probes an
      authenticated `GET /user` and returns `liveCheck.{valid, login,
expiresAt}`; Settings surfaces it behind a **Test connection** button.
      The same route also reports `tokenSource`, `tokenEnvScope`, and
      `runningAsService` so an unreadable variable is distinguishable from an
      unset one. **Evidence:** `scripts/Invoke-ApiHostSmokeTest.ps1` step
      _"GitHub auth — env-var-name indirection"_ asserts the probe fields and
      the 400 rejections; run 2026-08-07 exit 0, summary
      `githubAuthProbeOk=True githubTokenSource=env`.
- [x] **Remove the last stored-secret path: `readme.copilotApiKey`.**
      _(state: done 2026-08-07)_ `Readme.Generator.ps1` `_ResolveApiKey`
      accepted a literal Copilot key stored in `settings.json` (priority 1)
      ahead of the `readme.copilotApiKeyEnvVar` name — the same leak shape
      the `secrets.githubToken` removal closed. The literal path is gone;
      resolution starts at the env-var name. The startup stripper is now
      `Remove-StoredSecretsFromSettings` and clears **both** legacy slots.
      **Evidence:** module smoke exit 0; API-host smoke exit 0 with
      `githubAuthProbeOk=True`; `grep copilotApiKey` shows no remaining read
      of the literal key.

### Lane 0.4 — Smoke coverage gaps (closed items)

- [x] Add a scoped-path assertion for the repo-scoped roadmap scan
      (`POST /api/roadmap/scan` with a `repoName`/`targetRepo` body) to the
      api-host smoke. _(state: done 2026-08-08 — `smoke-tested`)_ Asserts the
      scoped call returns exactly the target repo, echoes
      `scopedRepo`, and — the load-bearing property — does **not** rewrite the
      portfolio-wide roadmap cache, so one RepoGrid row action cannot silently
      shrink the cached portfolio to a single repo. A companion unscoped scan
      over the same two-repo fixture asserts it sees both, so the
      single-result assertion cannot pass vacuously against an empty fixture.
      **Evidence:** api-host smoke `scopedRoadmapScanOk=True`.
- [x] Add an api-host smoke assertion for
      `POST /api/repository-improvement/preview` (the Guided Repository
      Improvement Workflow shipped 2026-08-01). _(state: done 2026-08-08 —
      `smoke-tested`)_ Runs the preview against a deliberately thin fixture
      repo (one-line README, no ROADMAP) and asserts `findingCount >= 1`, so a
      preview that runs but evaluates nothing fails; also asserts a request
      with no `repoPath` is refused rather than inferred. **Evidence:**
      api-host smoke `improvementPreviewOk=True`.
**Fixed 2026-08-08 while closing the two gaps above** — three defects in the
api-host smoke harness itself, all of the "the gate passed without testing
anything" class:

- **`-Port` did not move `-BaseUrl`.** `-Port 7093` booted the host under test
  on 7093 while `BaseUrl` stayed pinned to `http://127.0.0.1:7071`, so the run
  silently exercised whatever host was already listening there — typically the
  operator's live portal — and reported its behavior as the result. Every
  assertion still ran; none tested the host under test. `BaseUrl` is now
  derived from `Port` unless the caller sets both, and the run logs its target.
- **The `finally` block masked every early failure.**
  `$script:TrackedSettingsBackup` was assigned inside `try`, well after the
  first steps, so under `Set-StrictMode` any failure before that point made
  teardown throw _"variable has not been set"_ and replace the real error.
  Both variables are now declared before the `try`.
- **The auth assertion tested the wrong input.** It inferred expected
  enforcement from `REPO_MGMT_API_KEY` alone, but the host gates on
  `Test-ApiAuthRequired` (`auth.requireApiKey` / `REPO_MGMT_REQUIRE_API_KEY`)
  **and** a non-empty key. It passed only while the tracked `settings.json`
  carried leftover smoke pollution; the Lane 0.1 cleanup exposed the wrong
  premise. The assertion now mirrors the host's own rule and names all three
  inputs when it fails.

### Lane 0.6 — Workspace-path failure was silent (closed)

- [x] **Reject a workspace path that is not on disk, and report one that is
      already saved.** _(state: done 2026-08-08)_ An operator set a workspace
      path and got zero repositories with no error: `Backend: Online`, a green
      `Source: Local` badge, and a "successful" 0.1s scan. Two independent
      causes. First, the tracked config pointed at a fixture path (Lane 0.1).
      Second, `POST /api/settings` wrote `inventory.localRoots` with **no
      existence check**, while `POST /api/setup` had always rejected a missing
      root — so the Setup Wizard was guarded and the Settings dialog was the
      unvalidated way in. `Get-LocalFolderInventory` then logged
      _"Skipping invalid root"_ to the host log and returned an empty
      inventory, which the adapter reported as a successful scan. Fixes:
      `POST /api/settings` returns HTTP 400 naming the path and persists
      nothing; the status adapter and `GET /api/status` both report
      `meta.missingRoots`, recomputed at the route so a cache hit cannot replay
      stale on-disk state; the portal renders a top-of-page alert naming the
      exact path with a **Fix in Settings** action. The Settings dialog also
      surfaced save failures for the first time — `handleSave` previously
      swallowed the error with a `console.error` and a "you would show a toast"
      comment, so the new 400 would have been invisible. **Evidence:**
      api-host smoke `workspaceValidationOk=True`,
      `missingRootsReportedOk=True` (rejects a bogus `basePath` with 400, leaves
      `localRoots` untouched, and reports `meta.missingRoots` from
      `/api/status`); direct adapter run over the restored root returned
      **75 repositories** with `missingRoots` empty, and over the mistyped path
      returned `success=True`, `repoCount=0`, `missingRoots` populated.

### Lane 0.5 — Portal UX follow-ups (closed items)

- [x] **Reconcile the live-scan vs. persisted-index contradiction.**
      _(state: done 2026-08-08)_ The header read the live scan (`repos`)
      while the Queue buckets, "68% Avg Maturity", and "15 Ready Repos" read
      the persisted indexes in `output/index/`, so a 0-repo scan rendered
      populated figures beside a `0 repos` count and read as a broken tool.
      Both figures were always real; only the provenance was missing. Added
      [`frontend/lib/dataProvenance.ts`](../../frontend/lib/dataProvenance.ts)
      (`resolveProvenance` → `live` / `stale-only` / `empty`) plus
      [`ProvenanceNotice.tsx`](../../frontend/components/ProvenanceNotice.tsx),
      mounted at the top of the Insights tab (covering Portfolio Mission,
      Documentation Health, and Portfolio Analytics in one notice) and above
      the Doc Readiness Queue; the scan label now reads "No repos in this
      scan". Badges have no room for a sentence, so the **Operations** and
      **Doc Readiness Queue** counts — in both the desktop tab strip and the
      mobile bottom nav — render amber with a `ring` and an explanatory
      tooltip via `isCarriedOverCount` instead of as plain current-looking
      numbers. **Evidence:** `frontend/lib/dataProvenance.test.ts` (24 cases,
      incl. the unknown-live-count guards against a false banner and against
      disabling by omission); `npx vitest run` 37/37; `tsc --noEmit` clean;
      `vite build` clean with every new marker present in `dist`; module
      smoke exit 0.
- [x] **Disable repo-acting buttons when nothing is in scope.**
      _(state: done 2026-08-08)_ Pull, Fetch, Report, Doc Review, and Roadmap
      Scan stayed clickable at 0 repos, letting the operator click into a
      no-op instead of being pointed at the blocker. `ActionBar` now takes a
      `repoCount` prop and gates those five on
      `canRunRepoActions(repoCount, isActionRunning)`, replacing the
      implicit-bulk-scope callout with the actual blocker ("Scan a workspace
      first…"). Refresh, Settings, Help, and API docs stay enabled — they are
      the way out of the empty state. The Doc Readiness Queue's own actions
      needed the same treatment for a subtler reason: its rows come from the
      persisted index, so they outlive the scan and every row can target a
      repo the app cannot currently see. **Guided Improvement** and the six
      mutating row actions (Improve, Repair, Standardize, Generate README,
      Evaluate, Dispatch Release) are gated on `isKnownEmptyScope`;
      read-only actions (Audit, Lint, Roadmap, Preview Task) stay enabled,
      because inspecting the carried-over data is how an operator diagnoses
      _why_ the scan came back empty. `isKnownEmptyScope` returns false for an
      unknown count, so a view that never receives `liveRepoCount` is never
      disabled by omission. **Evidence:** as above;
      `scripts/frontend-smoke.cjs` `bulkSelectionNotePromoted` made
      state-aware so it asserts the correct variant rather than breaking on
      the empty-workspace path.


### Lane 0.7 — Roadmap-standard fidelity (closed items)

- [x] **Stop the repairer asserting "(No completed items recorded yet)" on a
      repo that archived its history.** _(state: smoke-tested 2026-08-08)_
      The repairer emitted that literal placeholder whenever no inline `[x]`
      items existed, so repairing a correctly-split roadmap wrote a false
      claim into it — against the section 8 guardrail "preserve genuine
      completion history when rewriting roadmaps." It carried a second defect:
      the placeholder was a `- [x]` checkbox, which the parser counts as a
      completed item, so each repair pass inflated `completedCount` with work
      that never happened. New `Get-RoadmapHistoryPointer`
      ([`Roadmap.Repairer.ps1`](../../backend/modules/roadmap/Roadmap.Repairer.ps1))
      detects the archive link, and the empty state now either names the
      archive or scopes the claim to "this file" — as a plain line, never a
      checkbox. The two duplicate builders were collapsed into one so the
      wording cannot drift. **Evidence:** module smoke step _"split-archive
      layout is preserved, never contradicted"_ asserts pointer detection,
      pointer preservation in the proposed content, `completedItemCount=0`,
      and that the output reparses to zero completed items; assertions are
      unconditional (the preview state is asserted, not used as a guard).
      Tripwire confirmed by reintroducing the old placeholder — smoke fails
      exit 1 naming the assertion — then restoring byte-exact.

---

## Release 3.1 — Closed-Loop Delivery

**Status:** `done` (engineering) — closed 2026-08-10. The one open item is the
live full-loop proof, which needs the same operator `claude` session Release 2.9
already batches.

**Goal:** close the north-star loop end to end, repeatedly, with explicit
operator gates at apply, dispatch, and merge. Today the console can rank work
and prepare a prompt, and it can read merge readiness, but no single work item
has ever travelled the whole chain — so the loop's real failure modes are
unknown.

**Prerequisites:** all but one are met. Release 2.7 Phase A (the live submit-PR
proof) and Release 3.0 (a dispatch that runs) both closed 2026-08-09. Only the
PAT's `Checks: Read` grant (Lane 0.2) is outstanding, and it affects per-check
merge detail rather than the loop — `mergeStateStatus` already answers the
merge-readiness question this release gates on.

### Product outcomes

- One roadmap item is carried from "ranked highest value" to "merged, with the
  managed repo's roadmap updated" without a human stitching the steps.
- Every stage transition is inspectable after the fact from one trace, rather
  than reconstructed from four ledgers.
- Roadmap write-back is preview-first: the console proposes the completion
  edit and the operator applies it.

### Engineering milestones

- [x] Add a per-work-item trace view joining rank → prompt → dispatch → agent
      run → Actions result → merge readiness → write-back, keyed by `runId`.
      _(state: smoke-tested — closed 2026-08-10)_ Every stage already wrote its
      own ledger and nothing joined them, so "what happened to this item?" meant
      opening four files by hand and matching ids across them.
      [`Execution.Trace.ps1`](../../backend/modules/execution/Execution.Trace.ps1) is
      that join, behind `GET /api/trace/{runId}`. **Any of the four ids the loop
      mints resolves the same trace** — packet id, packaging run id, dispatch
      run id, agent run id — because a trace view you can only open with the id
      you don't have is not a trace view; `Join-WorkItemTrace` is pure so every
      stage combination is testable without a workspace. Two decisions carry it:
      **absence is a finding** (all seven stages are always reported, and an
      absent one names the action that would advance it, so a stalled loop
      cannot read as a finished one), and **a hole in the middle stays visible**
      — the furthest stage reached is a different question from "is every
      earlier stage done", so a green merge-readiness over an unobserved Actions
      run is reported as a gap at `actions`, not hidden behind the later
      success. `Invoke-AgentRunRefresh` now keeps `prMergedAt` and
      `prMergeCommitSha` on the run record instead of folding the merge time
      into `agentCompletedAt`, which other paths also set — reading merge proof
      out of a timing metric would accept a merge claim from something that
      never merged. **Evidence:** module smoke — 7 stages always reported with a
      next action on each absent one, a mid-loop hole reported as a gap while
      `currentStage` still reports the furthest stage, and disk resolution from
      all four ids against a fixture workspace that also contains a **decoy run
      for a different dispatch** (selection must be by id, not "the only file in
      the directory").
- [x] Generate the managed repo's roadmap completion edit from merge evidence
      and present it as a reviewed diff. _(state: smoke-tested — closed
      2026-08-10)_
      [`Roadmap.WriteBack.ps1`](../../backend/modules/roadmap/Roadmap.WriteBack.ps1)
      produces the proposal and its unified diff; it writes nothing, and the
      operator applies through the existing `POST /api/roadmap/repair/submit-pr`
      where review already lives. The generator is deliberately conservative and
      **verifies its own output**: exactly one `- [ ]` may match (ambiguity
      refuses rather than guessing which item completed, since marking the wrong
      one silently corrupts the history this loop exists to keep honest), an
      already-`[x]` item is a no-op, and if the proposal differs from the
      original anywhere other than the flipped checkbox and the one inserted
      line it refuses as `unexpected-edit` rather than handing a reviewer a diff
      that quietly rewrote the file. The inserted line is an **evidence note
      naming the merged PR and the validation run**, because this repo's own
      contract is that nothing is marked complete without naming the artifact
      that proves it — and it lands after the item's continuation prose, not
      spliced into the middle of a sentence. **Evidence:** module smoke — one
      line flipped plus one note appended, sibling items and pre-existing `[x]`
      untouched, note placement asserted against the lines on either side.
- [x] Gate write-back on merge evidence: refuse to mark an item complete from
      code churn or a green run alone. _(state: smoke-tested — closed
      2026-08-10)_ `Test-RoadmapWriteBackEvidence` is the single definition of
      "proven complete", and **churn and a green run are refused by their own
      names** rather than folded into a generic failure — `churn-only` and
      `pr-not-merged` are the two halves of the section 8 guardrail, quoted back
      to the caller. A merge claimed with neither a merge timestamp nor a merge
      commit is refused as `merge-unverified`: an unverifiable claim is not
      evidence. **The item as written named one route; the hazard was the
      pattern.** `POST /api/roadmap/completion-preview` already existed and
      flipped any checkbox it was handed with no evidence of any kind — the
      exact behaviour the guardrail forbids, sitting behind an HTTP POST — so it
      now runs the same gate, and its multi-item shape survives while the free
      pass does not. Refusals are 409 (the request is well-formed; the answer is
      that the evidence does not justify it), carry **no `proposedContent`** so
      there is nothing for a UI to click past, and are appended to
      `output/roadmap-writeback.jsonl` as durably as proposals — a guardrail
      whose refusals leave no trace is indistinguishable from one that never
      ran. **Evidence:** module smoke — 8 refusals each named, plus a **tripwire
      that derives write-back surfaces from the api host's own AST** (any route
      body that generates a completed checkbox must reach the gate) rather than
      a hand-maintained list, since a hand-maintained list is what drifted here
      before: `0 ungated checkbox generators in 137 route bodies`.
      **Adversarially proven** — the detector was run against the pre-fix route
      shape and found exactly 1 violation, `completion-preview`, and the pre-fix
      regex was run against the fixture roadmap to confirm it marks the item on
      churn alone that the gate now refuses.
- [ ] Record a full-loop proof for one real item in `evidence/`, naming each
      stage's artifact. _(state: blocked on an operator session — the only
      remaining 3.1 item)_ Every stage is built and gated; the proof needs one
      real item to travel `rank → … → write-back`, and the agent-run stage runs
      `claude` in an authenticated operator session. **Batch it with Release
      2.9's operator session**, which already carries the 2.8 `claude` run and
      the 3.0 `gh agent-task` round trip — the same prerequisite, one sitting.

### Acceptance criteria

- A single `runId` resolves to every stage artifact through one route.
  **Met 2026-08-10** — and so do the packet, packaging-run, and agent-run ids.
  api-host smoke asserts `/api/trace/{runId}` answers as **JSON** (an unmatched
  GET falls through to the SPA index at HTTP 200, so status alone would pass on
  a route that does not exist) with 404 and all seven stages for an unknown id.
- A write-back attempt with no merge evidence is refused and says why.
  **Met 2026-08-10** — 409 `write-back-refused:<reason>` on both surfaces, with
  no `proposedContent` in the refusal. The **admitted** path is asserted too:
  merged + green returns 200 with one changed line, a reviewable diff, and the
  fixture roadmap **byte-identical on disk** — preview-first stated as an
  assertion rather than a promise.
- The loop proof exists in `evidence/` with the PR, the Actions result, and
  the applied roadmap diff. **Open** — needs the operator session above.

### Out of scope

- Automatic merge — merge stays an explicit operator action after readiness
  passes.
- Multi-repo parallel dispatch; one item end to end first.

---

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


## Closed 2026-08-11 (archived from ROADMAP.md)

Moved out of the active roadmap on 2026-08-11 under the section 8 split
rule, after `tools/Test-RoadmapStructure.ps1` reported `R010-FILE-LENGTH`
(2,020 lines) and `R013-FUTURE-RELEASE-SIZE` on Release 3.1. Every item below
shipped and is **verbatim** as it stood in `ROADMAP.md` — the evidence prose
is the reason later agents stop re-litigating settled decisions, so it is
preserved rather than summarized (section 8: "preserve genuine completion
history when rewriting roadmaps").


### Release 2.7 — Guarded Scheduled Automation (Curated-Subset, Preview-First)

- [x] Prove a live submit-PR round trip on one write-enabled repo: branch
      push, PR creation, PR visible in the target repo, run recorded.
      Closes the Release 2.4 residual and opens Phase C.
      _(state: **done** — proven live 2026-08-09 against this repo,
      [PR #96](https://github.com/xfaith4/GitHubRepoManagement/pull/96):
      6 additions / 0 deletions, 1 file, `MERGEABLE`, left open for review.
      **Phase C is now unblocked.**)_
      **Evidence, each verified independently rather than inferred from a
      success message:** the route returned `created=true` with a `prUrl`;
      a separate GitHub API read confirmed `state=open head=roadmap-repair/…
      base=main changed_files=1`; the append-only repair history carries a
      matching `submit-pr` record with the PR number and branch; and the
      checkout was left back on `main` and clean, proving the `finally`
      restore works on the success path and not only on failure.
      **This item was mis-scoped, and the correction matters.** It read as a
      credentials gate — "the dry-run plan path is smoke-tested; only the live
      round trip is missing", and the 2026-08-08 status note said Phase A was
      "now unblocked" because the service could read a token. In fact
      `POST /api/roadmap/repair/submit-pr` **had no live path at all**: even
      with `createPr=true` it returned `created=false` / `prUrl=null` and a
      note saying no branch was pushed. There was no checkout, commit, push,
      or PR creation anywhere in the route. The credentials were never what
      was blocking it. Half the machinery did exist —
      `POST /api/roadmap-agent/approve-push` performs a real token-authenticated
      push — but it stops at the push ("Open the PR from GitHub when ready").
      **Built 2026-08-09:**
      [`Roadmap.PrSubmitter.ps1`](backend/modules/roadmap/Roadmap.PrSubmitter.ps1)
      does branch → write → commit → push → `POST /repos/{o}/{r}/pulls`, with
      the pure parts (branch naming, remote-slug parsing, the refusal matrix)
      split out so they are testable without a checkout or a token. Safety
      properties, each asserted: never force-pushes, never commits onto the
      base branch, always returns to the starting branch via `finally`,
      refuses a dirty working tree rather than sweeping unrelated edits into
      an automated PR, refuses a no-op diff rather than opening an empty PR,
      and keeps the token out of the git argv (base64 `http.extraheader`, the
      same approach `approve-push` uses). A refusal returns **409 with a named
      reason and category**, never `200` with `created=false` — the caller
      must not be able to read "no PR" as success, which is exactly how the
      stub behaved. The run is recorded as a `submit-pr` event in the existing
      append-only repair history, carrying `prUrl`/`prNumber`/`branch`/`repoSlug`.
      **Evidence so far:** module smoke exit 0 — `submit-PR ok: 4 remote forms
      parsed, 4 non-GitHub refused, 8 refusal categories named, token not in
      cleartext`.

- [x] For each favorite repo with a ready L3+ roadmap, select the top-value
      pending item using the settled scoring semantics (MAX within a
      dimension + `effortFit` floor), build a task packet + repair-PR plan,
      and queue it for approval. _(state: smoke-tested — closed 2026-08-09)_
      Scope is resolved by `Resolve-AutomationPackagingScope`, which returns a
      decision per repo and **names every refusal** rather than shrinking the
      list silently: `archived-ignore`, `not-curated`, `roadmap-not-ready`
      (below L3), `no-pending-work`, `no-scored-item`, `missing-local-path`.
      Scope opts **in** — an unrecognized curation state is excluded, the same
      contract `curationScope.ts` pins on the frontend. Ranking reuses the
      assessment's already-scored items (`Select-TopValueRoadmapItem`: highest
      `valueScore`, earlier `roadmapOrder` breaks the tie, exactly as
      `_SelectTopValueItem` does) so a packet and the dashboard can never
      disagree about "the top item", and an **unscored** item is never
      packaged. The packet carries the item, its score/tier/rationale, a
      namespaced `roadmap-item/<slug>-<id>` branch, an item-scoped prompt that
      forbids widening the scope, and a repair-PR plan naming the Phase A
      write path (`POST /api/roadmap/repair/submit-pr`) with `submitted=false`.

- [x] Gate every packaged item through the quota/budget guard; skip and log
      when over budget. _(state: smoke-tested — closed 2026-08-09)_
      `Test-PackagingQuota` delegates to the Release 2.0
      `Test-AgentDispatchQuota`, prices each item from the roadmap's own
      annotated phase estimate (falling back to a configured default), and a
      refusal is recorded as a skip carrying **the guard's own `blockedCode`
      and message**. The guard is **fail-closed**: if `BudgetLedger.ps1` is not
      loaded the item is refused with `quota-guard-unavailable` rather than
      admitted — a guard that cannot be evaluated is not a pass. The quota is
      re-checked at approval time, because budget can be consumed between
      packaging and approval.

- [x] Notify per run; approval triggers dispatch (live PR once Phase A
      passes). No auto-merge. _(state: smoke-tested — closed 2026-08-09)_
      Each run emits a digest (webhook when configured, dry-run otherwise)
      listing what was packaged and what was skipped with its reason, and a
      degraded run fires the same `execution.failed` event Phase D wired.
      **A scheduled run never dispatches** — `dispatchedCount` is an invariant
      and `Write-PackagingRunRecord` refuses to persist a run claiming
      otherwise, the same defense-in-depth Phase B applies to `appliedCount`.
      Dispatch happens only through the explicit approval action, which
      enqueues to the Release 2.8 operator-runner queue (queue line **and** the
      `queued` run summary the runner claims on — one without the other is a
      task nothing picks up). `Test-PackagedItemTransition` is the single
      definition of what may follow what; a refusal is a **409 with a named
      category**, never a 200 that reads like success, and a dispatched packet
      is terminal so it cannot be dispatched twice.

- [x] Smoke: a scheduled run ranks + packages one fixture repo's top item,
      honors the quota-refusal path, and dispatches only on explicit
      approval. _(state: smoke-tested — closed 2026-08-09)_
      **Module smoke** (exit 0): `packaging scope ok: 2 selected, 7 refusals
      each named`; `packaging rank ok: max score, earlier roadmap order breaks
      the tie, unscored selects nothing`; `packaging quota ok: over-budget
      skipped+logged with the guard code, nothing queued, missing guard fails
      closed` (the fail-closed branch is proven in a fresh runspace where
      `BudgetLedger.ps1` was never loaded); `packaging run ok: 2 packet(s)
      queued for approval, dispatched=0 applied=0, dispatch queue absent,
      invariant-violating runs refused`; `packaging approval ok: 8 transitions
      enforced, queue+summary written on dispatch, fold keeps 3-step history,
      sibling packet untouched`; and a **drift tripwire** — `queue contract ok:
      10 fields identical to the canonical writer` — that fails if
      `Add-RoadmapTaskToQueue.ps1`'s entry shape ever changes without this
      writer following, which would otherwise strand approved work in the queue
      as entries the runner silently mishandles.
      **Api-host smoke** (exit 0, `packagingOk=True`) against a live host:
      `packaged 'Add the operator dashboard export route with smoke test
      coverage' (score 93, order 2) not the first item, over-budget twin
      skipped at stage=quota, dispatch only on approval (run
      20260809-105754-0c048a3f), re-approval 409`. Two fixture repos are used
      because the pre-existing fixture's roadmap is deliberately below L3; the
      over-budget twin differs **only** by a phase-plan estimate above the
      per-session cap, so the refusal is caused by the budget and nothing else,
      and the packaged item is asserted to be neither the first pending item nor
      merely whatever the route returned.

- [x] The approval queue now has an operator UI on the Operations tab.
      _(state: smoke-tested — closed 2026-08-09)_ Approving was an API call
      (`POST /api/automation/packages/approve`); the loop worked but a packaged
      item was less discoverable than a doc-improve preview in the AI Docs
      panel. [`PackagedItemQueue.tsx`](frontend/components/PackagedItemQueue.tsx)
      renders the queue over a pure
      [`lib/packagedItems.ts`](frontend/lib/packagedItems.ts) that **mirrors
      `Test-PackagedItemTransition`'s matrix rather than reinventing it**, so the
      UI can never offer an action the backend answers with a 409 (nor hide one
      it would allow) — `dispatched` and `rejected` are terminal in both places.
      A rejection prompts for a reason and it is written to the append-only
      audit trail. **`dispatched` is deliberately not labelled "done"**: approval
      enqueues to the operator runner, which stops at a reviewed branch, so a
      "Complete" badge here would be exactly the decorative badge section 8
      forbids — a unit test asserts the label never reads done/complete/merged.
      **Evidence:** `npm run test:unit` 112 passing across 8 files (23 new
      assertions in `packagedItems.test.ts`), `npm run typecheck` and
      `npm run build` exit 0.

- [x] Packaging now has an overdue alert of its own.
      _(state: smoke-tested — closed 2026-08-09)_ `Get-AutomationHealth`
      deliberately reads only the doc-refinement history (interleaving kinds
      would let a live packaging cron mask a dead doc cron), so a packaging cron
      that stopped was invisible. The fix is the second reader the item
      specified — `Get-PackagingHealth` / `Get-PackagingRunOutcome` over
      `packaging-runs.jsonl`, **never a merged file** — surfaced as a
      `packaging` block on `GET /api/automation/status` beside the unchanged
      doc-refinement fields, and rendered as a second badge on the Operations
      tab. Alert codes are packaging-specific (`packaging-never-ran`,
      `packaging-overdue`, `packaging-run-failed`, `packaging-run-partial`)
      because `automation-overdue` on both would leave a webhook unable to say
      which scheduler stopped. A **skip is not a failure** — an over-budget repo
      is the guard working, so a run that only skipped classifies `ok`.
      Interval falls back to `automation.intervalMinutes` when no
      `automation.packaging.intervalMinutes` is set, so a single cron hitting
      both routes is not reported as "never ran" for want of a second setting.
      **Evidence:** module smoke — `packaging health ok: never-ran/overdue/
      partial named packaging-specifically, skips are not failures, doc runs
      cannot mask it` (that last assertion is the independence proof: a
      workspace holding only a fresh doc-refinement run still reports
      `packaging-never-ran`); api-host smoke asserts both blocks are present and
      self-identify (`kind=doc-refinement` / `kind=roadmap-packaging`) so the
      route can never return the doc verdict twice.

- [x] Complete the frontend unit-test set (vitest). _(state: smoke-tested —
      4 of 4 named units covered, closed 2026-08-09)_ `needsAttention` and
      `viewMeta` were already covered
      ([`needsAttention.test.ts`](frontend/lib/needsAttention.test.ts),
      [`viewMeta.test.ts`](frontend/viewMeta.test.ts)). The two gaps closed
      by extracting the logic out of the components that held it, so the
      tests cover the code that actually ships rather than a copy:
      **value tiers** → [`lib/valueTier.ts`](frontend/lib/valueTier.ts) +
      [`valueTier.test.ts`](frontend/lib/valueTier.test.ts), consumed by
      `WorkQueueView`; **automation scope selector** (operator curation) →
      [`lib/curationScope.ts`](frontend/lib/curationScope.ts) +
      [`curationScope.test.ts`](frontend/lib/curationScope.test.ts),
      consumed by `RepoGrid`. The scope suite pins the Release 2.7 contract
      the backend also enforces: `archived-ignore` is never in automation
      scope, and neither is an uncurated repo — scope opts in, it never opts
      out, so an unrecognized curation state is excluded rather than
      admitted. **Evidence:** `npm run test:unit` 79 passing across 6 files,
      `npm run typecheck` exit 0; the never-touch assertion was
      adversarially proven — widening `isInAutomationScope` to
      `state !== 'none'` fails
      [`curationScope.test.ts:72`](frontend/lib/curationScope.test.ts#L72).

- [x] Decompose [`Dashboard.tsx`](frontend/components/Dashboard.tsx):
      extract the view-router/tab shell and the summary/mission sections.
      _(state: smoke-tested — both named extractions landed 2026-08-09)_
      The tab shell became
      [`DashboardViewTabs.tsx`](frontend/components/DashboardViewTabs.tsx)
      over a pure [`lib/viewTabs.ts`](frontend/lib/viewTabs.ts); the summary
      and mission blocks became
      [`PortfolioSummarySection.tsx`](frontend/components/PortfolioSummarySection.tsx)
      and
      [`PortfolioMissionSection.tsx`](frontend/components/PortfolioMissionSection.tsx).
      The extraction also closed two latent drift hazards it exposed: four of
      the six tabs hardcoded their label instead of reading `VIEW_META` (the
      exact drift [`viewMeta.ts`](frontend/viewMeta.ts) exists to prevent), and
      the badge-visibility rule was written three different ways inline. Both
      are now single definitions. **Evidence:** `npm run test:unit` 91 passing
      across 7 files (12 new `viewTabs` assertions), `npm run typecheck` and
      `npm run build` exit 0; tab labels and order are unchanged because
      `VIEW_META` already carried the same six labels in the same order.


### Release 3.1 — Closed-Loop Delivery

- [x] Add a per-work-item trace view joining rank → prompt → dispatch → agent
      run → Actions result → merge readiness → write-back, keyed by `runId`.
      _(state: smoke-tested — closed 2026-08-10)_ The join is explicit and pure:
      [`Execution.Trace.ps1`](backend/modules/execution/Execution.Trace.ps1)'s
      `Join-WorkItemTrace` takes the already-read stage records and returns the
      seven-stage chain, so the whole decision table is testable offline;
      `Get-WorkItemTrace` is the thin reader behind `GET /api/trace/{id}`.
      **Any id the chain mints resolves to the same trace** — packetId,
      packaging runId, dispatch runId or agent-run id — because an operator
      holding one of them should not have to know which ledger minted it. The
      PR stage joins on **branch**: the submit-PR history shares no run id with
      the dispatch chain, and repo name alone would attribute another item's PR
      to this one. **The load-bearing distinction is `pending` vs `missing`:**
      `pending` means the chain has not reached a stage, `missing` means it
      demonstrably has and the artifact that should exist does not. Only
      `missing` becomes a gap, and gaps displace the progress narrative in both
      the API roll-up and the UI — "6 of 7 done" would otherwise hide a stage
      nothing ever recorded. **Evidence:** module smoke — 18 stage cases across
      the loop's shapes, 4 ids resolving to one trace, 7/7 stages joined from
      real ledger files on disk, plus a **tripwire that every stage must be
      able to report a gap** (a stage that could only ever read `pending` would
      make a broken chain look merely young; an eighth stage without gap
      detection fails the gate). api-host smoke traces the item its own
      packaging run just dispatched, checks `packetId` and `dispatchRunId`
      resolve to the same `traceId`, and asserts an unknown id 404s **as JSON**
      — status alone would pass against the SPA fallback. Frontend: 16 pure
      view tests + 5 DOM tests asserting a gap renders differently from
      unreached work.

- [x] Generate the managed repo's roadmap completion edit from merge evidence
      and present it as a reviewed diff. _(state: smoke-tested — closed
      2026-08-10)_ `POST /api/roadmap/write-back/preview` resolves the work
      item from any trace id, re-reads its pull request **live** (a stored
      merge-readiness snapshot never carries a merge commit, so a snapshot
      alone can only ever say "unverified"), and returns a **line-level** diff
      rather than a whole-file dump — the roadmaps this edits are thousands of
      lines, so a full body is not a review surface. Matching is exact on the
      trimmed item text: a fuzzy match would eventually tick the wrong line in
      someone else's roadmap. Re-running is a no-op reported as
      `alreadyComplete`, never a second claim, and a miss is named rather than
      returned as a silent zero-line edit.

- [x] Gate write-back on merge evidence: refuse to mark an item complete from
      code churn or a green run alone. _(state: smoke-tested — closed
      2026-08-10)_ `Test-RoadmapWriteBackEvidence`
      ([`Roadmap.WriteBack.ps1`](backend/modules/roadmap/Roadmap.WriteBack.ps1))
      is pure and **fails closed** — no evidence at all is a refusal, not a
      pass. Nine shapes are refused, each with a code, a sentence and the
      remedy that would satisfy it: churn-only (`no-pull-request`, which names
      the changed-file count and the passing local verify so the operator is
      told those are not the thing), a green check on an open PR
      (`pr-not-merged`), closed-without-merging, merged-with-no-Actions,
      merged-mid-validation, merged past a red check (`validation-failed`),
      merged with no merge commit, merged per a stored snapshot only
      (`merge-unverified` — nobody asked GitHub), and no item text. **Apply
      re-runs the gate from scratch** rather than inheriting the preview's
      verdict, refuses a preview whose file moved underneath it
      (`stale-preview`), and the ledger itself throws on an applied record with
      no allowed gate. Every refusal is a **409**, never a 200 carrying
      `changed=false` a caller could read as success.
      **The pattern, not the instance:** the Release 1.1 completion-preview
      route carried its own inline `- [ ]` → `- [x]` rewrite, so there were
      about to be two generators and only one of them gated. It now delegates,
      and a tripwire asserts there is **exactly one** generator in `backend/`
      — a file that both matches an open checkbox and emits a complete one.
      **Evidence:** module smoke — the 9 refusal shapes, the allowed case,
      edit exactness/indentation/idempotence, the ledger round trip, and the
      applied record reaching the trace's final stage (two modules name that
      file through two constants; the assertion is behavioral so drift fails
      rather than silently showing `writeBack=missing` forever). Two tripwires,
      both **adversarially proven**: the one-generator detector reports the
      pre-fix host as a generator and none of the four legitimate near-misses
      (parser and dispatcher match open items; linter and repairer emit `- [x]`
      into history sections), and the gate detector fires when `gate.allowed`
      is removed from the apply route. api-host smoke: preview **and** apply
      both refuse a real ranked-approved-dispatched item 409 because nothing
      merged, the fixture roadmap is verified untouched, and an unknown id 404s
      as JSON. Frontend: 8 DOM/view tests, including that apply confirms first
      (it writes to a file in a **different** repository) and that a refusal
      appearing only at apply time is surfaced rather than a stale success.


### Release 3.2 — Portfolio Scale and Responsiveness

- [x] Declare and enforce a performance budget for the portfolio read path,
      with the measured figure reported next to it. _(state: smoke-tested —
      closed 2026-08-11)_ Before this, the only number bounding a portfolio
      read was the Lane 0.4 request deadline, and that enforces by calling
      `Environment.FailFast` — **a target whose only enforcement is destroying
      the host is a crash guard, not a budget.** It cannot report that a 400ms
      cache read became 4 seconds, which is the regression an operator feels
      first. [`PerformanceBudget.ps1`](backend/api-host/PerformanceBudget.ps1)
      declares a budget per read class and is pure, so the whole contract is
      testable without starting the listener. **The budget keys off the same
      `cacheSource` literal the routes already serve**, so there is no second
      classifier to drift out of step with the first, and the api-host smoke
      asserts `readClass === cacheSource` on both routes — this repo's
      recurring "two figures, one truth" failure cannot recur here silently.
      **An undeclared class fails closed** (`declared=false` forces
      `withinBudget=false`): an unbudgeted read path is unmeasured, not fast,
      and scoring it as passing is exactly how a new slow route stays
      invisible — the same contract `Test-PackagingQuota` and
      `Test-RoadmapWriteBackEvidence` apply. The cold-scan budget is **300s,
      deliberately far below the 900s scan-tier deadline**, and a module-smoke
      assertion derives that ceiling from `Get-RequestDeadlineSecondsForPath`
      rather than copying the number: budgeting a scan at the crash guard would
      mean the first thing to notice a regression is the guard killing the
      host, which is the outage Lane 0.9 records three times. The measured
      figure ships **in the response payload beside its budget**
      (`data.performance`) and as a greppable `portfolio.read-budget` TRACE
      line in the shape `Invoke-DailyEvidence.ps1` already parses.
      **Evidence:** module smoke — `read-path budget ok: 4 class(es) declared,
      undeclared fails closed, cold-scan budget 300000ms < deadline 900000ms,
      2 route(s) evaluate it`. Two tripwires, both **adversarially proven**:
      the drift detector derives the emitted classes from the host source (a
      hand-maintained list is what drifted in Lane 0.9) and fired on
      `cacheSource 'portfolio-index'` when its budget was deleted; the wiring
      detector fired with `Route 'GET /api/operations/repos' … never evaluates
      the read-path budget` when the call was renamed away. Api-host smoke
      asserts the block round-trips on both routes, that the class judged is
      the class served, and that a breach **fails the gate** rather than
      logging quietly.


### Lane 0.2 — Credential freshness

- [x] **Populate `rateLimit` on the GitHub insights path.** _(state:
      smoke-tested — closed 2026-08-09)_ `Get-GitHubReposViaApi` returned a
      hardcoded `rateLimit = $null`, so `insightsMeta.rateLimit` was always null
      and the readout stayed blank even though every call already receives
      `X-RateLimit-Limit` / `-Remaining` / `-Reset`. The parser and the
      last-observation snapshot live in a dot-sourced
      [`GitHubRateLimit.ps1`](backend/api-host/GitHubRateLimit.ps1) — the shape
      `RequestDeadline.ps1` uses — because a helper defined inside the host
      script cannot be loaded without starting the listener, and a parser only
      reachable through a live HTTP request is a parser nothing tests.
      Three calls switched from `Invoke-RestMethod` to `Invoke-WebRequest`
      (`Invoke-RestMethod` discards headers on Windows PowerShell); the snapshot
      is cleared per request and takes the **newest** observation, because the
      limit is consumed by every call in the sweep, not just the first.
      **The item named one call site and there were two.** A source tripwire
      over the whole file — not the named line — caught
      `POST /api/github/status`'s **`gh` CLI fallback** returning its own
      hardcoded null. That path has no response object to read, so it resolves
      from `GET /rate_limit` (which does not itself consume quota) through
      `ConvertFrom-GitHubRateLimitPayload`, which **reuses the header parser**
      so the two paths cannot emit differently-shaped readouts.
      **Absent or unparseable headers still yield `$null`, never a zeroed
      object** — a fabricated "0/5000" would read as an exhausted quota and look
      like a real measurement. **Evidence:** module smoke —
      `both header shapes parsed, /rate_limit payload shares the shape, newest
      observation wins, absent headers stay null` (PS 5.1's
      `Dictionary[string,string]` and PS 7's `Dictionary[string,string[]]` are
      both asserted; a parser handling one silently reads blank on the other).


### Lane 0.3 — Layout follow-ups from the 2026-07-15 cleanup

- [x] Normalize hardcoded `G:\Development\GitHubRepoManagement`
      `-WorkspaceRoot` defaults to `$PSScriptRoot`-derived paths so the
      suite runs unmodified from any clone location. _(state: smoke-tested —
      confirmed 2026-08-07 still present in `backend/adapters/Adapters.ps1`,
      `backend/api-host/Start-RepoManagementApiHost.ps1`,
      `backend/modules/docreview/Invoke-DocReviewInventory.ps1`, and both
      reconcile modules — a wider blast radius than the original note
      recorded)_ **Partly closed 2026-08-08:**
      [`scripts/Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1)
      now defaults to `(Split-Path -Parent $PSScriptRoot)`. This one mattered
      more than the note implied: the required pre-commit gate failed on its
      first step for anyone invoking it without `-WorkspaceRoot`, which is
      exactly how `CLAUDE.md` documents running it. **Evidence:** gate re-run
      with no arguments, exit 0.
      [`scripts/Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1)
      was fixed the same way, so **both** required gates now run unmodified from
      any clone location. **Closed 2026-08-09**, and the file list above was
      wrong in both directions — worth recording, because the same mistake
      produced the 2026-08-07 "wider blast radius than the original note"
      correction:
      **(a) Three of the five named `backend/` files were not `-WorkspaceRoot`
      defaults at all.** `Adapters.ps1`, `Invoke-DocReviewInventory.ps1`, and
      the reconcile modules hardcoded `$LocalRoots` / `$RootPath` — **scan
      targets**, i.e. where the operator's repos live, not where the tool
      lives. `$PSScriptRoot` derivation is meaningless for those. Every caller
      already passed them explicitly, so the defaults were dead code whose only
      possible effect was to scan a nonexistent drive and return "no repos"
      instead of "misconfigured". They now default to empty and throw a named
      error. Removing them exposed a hidden coupling:
      `Invoke-Reconciliation.ps1`'s empty-roots check ran even under
      `-LoadFunctionsOnly`, and had been passing only because the dead
      `G:\Development` default made the array non-empty — so `Adapters.ps1`
      broke the moment the default was honest. The check is now correctly
      skipped when only loading functions.
      **(b) Seven files were missing from the list**, including
      `Invoke-AuthSmokeTest.ps1` and `Invoke-PhaseProtocolTest.ps1`, which
      hardcode **`F:\`** — the current machine's drive, so they work here and
      break on every other clone. A `G:\` grep could never have found them.
      **The instances are fixed and the pattern is now enforced:**
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) fails
      if any tracked `backend/`, `scripts/`, or `tools/` script declares a
      `[string]$Param = 'X:\...'` default (`*.Tests.ps1` exempt — those use
      absolute paths as synthetic fixtures). **Evidence:** the tripwire was
      written before the last two fixes and caught them, which is how they were
      found; module smoke and adapter smoke both exit 0, the latter run with no
      `-WorkspaceRoot` argument at all; each of the three adapter guards was
      confirmed to raise its named error when the root is omitted.

- [x] Implement the documented maturity **caps** that the auditor did not
      apply: `ROADMAP_MATURITY_MODEL.md` states "any critical finding caps
      maturity at L1" and "any warning finding caps maturity at L3", but
      `Invoke-AuditRoadmapContract` only did weighted-score arithmetic, so a
      roadmap could carry a critical finding and still score
      orchestration-ready. _(state: smoke-tested — closed 2026-08-09)_
      **The model contradicted itself, and Ben chose the resolution
      2026-08-09.** `ROADMAP-011` (>1 active release) carried a named L2 cap
      _and_ `critical` severity; applying the blanket critical cap literally
      would have forced it to L1 and made its own documented L2 cap
      unreachable. Rather than add a precedence rule, **the severity was the
      bug**: `ROADMAP-011` is now `warning` (rules **v1.5**), so it takes the
      L3 blanket cap plus its named L2 cap and lands at L2 exactly as
      documented — and "any critical finding caps at L1" became literally
      true. Ambiguous dispatch is still a hard gate, because L2 is below the
      L3 contract-ready bar. Caps now **compose**: the effective ceiling is
      the lowest that applies. **Both rule-pack mirrors and both
      `ROADMAP_MATURITY_MODEL.md` copies moved in lockstep**, and the model
      now records why the severity must not be re-promoted.
      **The parity tripwire earned its keep:** implementing the caps in the
      backend auditor alone broke it immediately
      (`maturityScore module=84 cli=92`), because
      [`Test-RoadmapContract.ps1`](tools/Test-RoadmapContract.ps1) carries its
      own cap block — exactly the "two figures, one truth" divergence this
      product exists to catch. Both evaluators now implement the same
      composed caps. **Evidence:** module smoke exit 0 —
      `maturity caps ok: critical -> L1-Informal (<= 39); 1 warning finding(s)
      -> L3-Contract-Ready (<= 84)`, `2 active -> ROADMAP-011 (warning) +
      capped at L2-Structured`, and `evaluator parity ok: 4 fixtures agree`.
      A new assertion fails the gate if `ROADMAP-011` is ever re-promoted to
      `critical`.

- [x] Repair `CLAUDE.md`'s dangling `@_base.md` and
      `@.claude/modes/implementer.md` imports — neither file exists.
      _(state: done — closed 2026-08-09)_ The note said to "fix at the tool
      level" because `ccmode.ps1` manages the mode line, but **`ccmode.ps1`
      does not exist either** — not in this repo and not under any `.claude`
      directory on this machine — so there was no tool level to fix at. Ben
      chose removal 2026-08-09: both imports are gone, replaced by a comment
      recording what they were and that `ccmode.ps1` can re-add its own line
      if it is ever restored. Nothing was fabricated to satisfy them.

- [x] Tune `tools/Test-RoadmapStructure.ps1` for the template's own layout:
      `ROADMAP_TEMPLATE.md` puts the full execution contract inside the
      `## Release X — Title` block, so R013's 120-line cap fired on any
      conformant active release, and RQ001 wanted a `Status` line on the
      "Active release detail" pointer that must not restate it (declaring it
      twice is an RQ003 error). _(state: smoke-tested — closed 2026-08-09;
      this file is now 0 errors / 1 warning, and the one left is the true
      R010 file-length signal)_ R013 now skips the active release; RQ001 now
      skips a pointer block whose release declares a valid status, and its
      message names both places when neither does. **Two pre-existing crashes
      surfaced while testing the relaxations**, both in the
      "linter dies on exactly the file it should diagnose" shape: a roadmap
      with no status lines anywhere hit `Cannot bind argument ... empty array`
      before RQ001 could report it (six rule parameters were missing the
      `[AllowEmptyCollection()]` that a seventh already had), and a file with
      no release headings hit a StrictMode `$null.Count` before
      `R000-NO-RELEASES` could fire — `ROADMAP_TEMPLATE.md` itself is such a
      file, so the linter could not lint its own template. Both fixed.
      **The linter had no smoke coverage at all**, which is how it drifted
      into contradicting the template it lints;
      [`Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1) now
      pins both relaxations _and_ proves each rule still fires when genuinely
      violated. **Evidence:** module smoke exit 0; adversarially proven —
      reverting either relaxation fails the gate at the matching assertion.
      The first version of that coverage captured only `2>&1`, so every
      "must fire" assertion passed vacuously while the finding scrolled past
      on the console; it captures `*>&1` now, which is what the linter's
      `Write-Host` findings actually use.


### Lane 0.4 — Smoke coverage gaps

- [x] **The cold-scan request deadline — decided and shipped 2026-08-09.**
      _(state: smoke-tested)_ `POST /api/automation/run` calls
      `Get-OperationsReposPayload`, which does a **cold full-portfolio
      assessment**. That step was fast only while the tracked `settings.json`
      pointed at a fixture directory; with the real root restored (Lane 0.1)
      it exceeded the smoke's default `-RequestTimeoutSec 180` on the real
      75-repo workspace. Worse, the **Phase D request deadline also defaulted
      to 180s and terminates the host on expiry** — so a legitimate cold scan
      tripped the freeze guard, and Shawl/SCM recovery restarted the host
      straight back into the same scan. The guard was manufacturing the
      outage it exists to prevent.
      **Decision: an extended tier, not an exemption.** Exempting the scan
      routes outright would restore the unbounded wedge the Phase D guard was
      built to stop, and bounding the cold scan itself is a Release 3.2
      performance problem, not a reliability fix — so the deadline now
      classifies routes instead. `Get-LongRunningScanRoutePattern` in
      [`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1) names the
      routes that reach a full-portfolio assessment
      (`/api/portfolio/assessment`, `/api/operations/repos`,
      `/api/automation/run`, `/api/digest/*`, `/api/reconcile`,
      `/api/docreview/run`, `/api/badges/*`, `/api/v1/agent/*`); those get
      **900 seconds** (`REPO_MGMT_SCAN_REQUEST_TIMEOUT_SECONDS`, same 30-3600
      clamp, never below the default tier), everything else keeps 180. The
      deadline is now recorded per request, so an incident record reports the
      tier that actually fired rather than the startup default.
      `Invoke-ApiHostSmokeTest.ps1` dot-sources the same classifier for its
      client timeout, so client and server cannot drift apart.
      **Evidence:** module smoke asserts the classification both ways (five
      scan paths in, five ordinary paths plus the empty path out), the
      trailing-slash form, the 900/180 selection, and that the extended tier
      can neither drop below the default tier nor exceed the 3600 ceiling;
      the assertion was adversarially proven to throw with the pattern list
      emptied. `./scripts/Invoke-ApiHostSmokeTest.ps1 -Port 7099` passes with
      **no `-RequestTimeoutSec 900` and no
      `REPO_MGMT_REQUEST_TIMEOUT_SECONDS` override** — the two workarounds
      this item existed to remove.
      **This decision is the input Release 3.2 was waiting on** (see the
      dependency map): 3.2 inherits a bounded 900-second scan budget as the
      number its responsiveness work has to beat, not an unbounded route.

- [x] Archive the root worklogs `findings.md`, `progress.md`, and
      `task_plan.md` to [`docs/history/worklogs/`](docs/history/worklogs/),
      matching the 2026-07-15 cleanup convention they were re-created against.
      _(state: smoke-tested — closed 2026-08-09)_ They went to
      `docs/history/worklogs/2026-08-08-guided-improvement/` rather than the
      directory root: the three files already archived there are a **different**
      set from the pre-2026-07-15 layout, and overwriting real history to
      satisfy a filename would have destroyed it. **The convention is now
      enforced rather than restated** — the note explaining it lived only inside
      a completed release, which is why the files came back within three weeks.
      All three fixes ship together: a `.gitignore` rule stops new ones
      appearing, [`docs/history/worklogs/README.md`](docs/history/worklogs/README.md)
      states the convention where worklogs are actually written, and a
      module-smoke tripwire fails the required pre-commit gate if a worklog is
      tracked at the root again (gitignore alone cannot stop an already-tracked
      file, or a `git add -f`). **Evidence:** module smoke —
      `no worklogs tracked at the repository root; the convention is
      documented`.


### Lane 0.9 — Portal restart loop: the watchdog was killing healthy scans (P0, 2026-08-10)

- [x] **Teach the watchdog to tell "busy" from "frozen" via a progress
      heartbeat.** _(state: smoke-tested — closed 2026-08-10)_ The host now
      publishes what it is doing and when it last moved
      ([`OperationHeartbeat.ps1`](backend/api-host/OperationHeartbeat.ps1),
      dot-sourced so it is testable without starting the listener); the scan
      path marks itself active, ticks progress per directory through a new
      `-OnProgress` callback threaded into `Get-LocalFolderInventory`, and
      clears in a `finally` so a thrown scan cannot leave a marker behind.
      `Resolve-WatchdogAction` takes the progress state as an **explicit
      input** and stays pure. **Progress, not CPU, is the contract** — a
      healthy scan can block for minutes on GitHub, `git`/`gh`, or the
      filesystem while accruing no CPU, and a runaway can burn CPU while
      achieving nothing; `cpuAdvanced` is carried to the ledger as
      corroboration only and is never consulted by the decision. Suppression
      is gated on the **age** of the last progress record, so an orphaned
      marker ages out by itself and restarts resume with no cleanup; failures
      keep counting while suppressed, so staleness restarts immediately rather
      than three probes later. A configuration invariant
      (`Test-WatchdogToleranceInvariant`) refuses a no-progress tolerance
      shorter than the cadence the **host itself declares** in the heartbeat
      file, clamping up — and the tolerance is a no-progress budget (120s),
      deliberately **not** raised to the 900s request deadline, so a scan that
      keeps reporting is never restarted however long it runs while a host
      that stops moving is still caught in ~2 minutes. **Evidence:** module
      smoke — 10 decision cases (fresh progress suppresses at threshold; fresh
      progress + flat CPU still suppresses; stale progress restarts; no
      operation keeps the old policy both below and at threshold; healthy
      resets mid-operation; completed operation returns to ordinary policy;
      orphaned 24h marker restarts; tolerance boundary fresh/stale) plus 6
      progress-age shapes (null/inactive/unparseable/missing all yield "no
      suppression", and a `Kind=Unspecified` stamp is read as UTC).
      **Adversarially proven** against both rejected designs: the pre-fix
      counter restarts the healthy scan the new logic protects; a CPU-based
      guard would kill a scan blocked on I/O _and_ never restart a
      CPU-burning runaway.
      **Live production proof (2026-08-10, service restarted onto this code),
      both halves observed unprompted in the watchdog ledger:** with a scan
      active and progress fresh, three consecutive failed probes at 04:03:33 /
      04:04:34 / 04:05:36 (ages 3s / 11s / 71s) recorded `suppressed=true` and
      **no restart** — the exact sequence that force-restarted the host at
      03:19, 03:22 and 03:25 before the fix; then with **no** operation
      active, failed probes at 04:07:33 / 04:08:33 / 04:09:33 restarted the
      service normally. The guard discriminates rather than merely tolerating.
      The 71s reading also gives the first real measurement of scan tick
      spacing against the 120s tolerance — previously unmeasurable.

- [x] **The first fix instrumented one route; the long routes stayed bare.**
      _(state: smoke-tested — closed 2026-08-10, second pass)_ Reported as
      "Insights page does not load": Portfolio Mission showed `Failed to
      fetch`, Documentation Health and Portfolio Analytics stayed unavailable.
      Cause: the heartbeat was added **per route**, to `/api/status` only —
      which is not even on the extended-deadline list — while
      `Get-LongRunningScanRoutePattern` already enumerated the routes that
      genuinely run for minutes. `/api/portfolio/assessment` therefore had no
      heartbeat and was restarted mid-scan exactly as before: ledger shows
      `04:24:33 suppressed=True age=76` then `04:25:33 decision=restart` while
      the host log shows `04:25:22 portfolio.assessment start` →
      `04:25:35 host started`. **This repo's third instance of fixing the
      named instance instead of the pattern.** The heartbeat lifecycle now
      hangs off the **same classifier the request deadline uses**
      (`Test-LongRunningScanRoute`) in the request loop, completing in the
      same `finally` as `Clear-RequestDeadline`, so a route added to that list
      is covered automatically. An ambient tick
      (`Update-ActivePortalOperationProgress` /
      `Get-ActivePortalOperationTick`) lets deep scan code publish progress
      without threading a callback through every layer, and no-ops outside an
      operation. **Evidence:** module smoke — `heartbeat coverage ok: request
      loop keyed off Test-LongRunningScanRoute, 3 scan-engine call site(s) all
      publish progress, ambient tick no-ops when idle`; the tripwire fails if
      the request loop stops keying off the classifier, if it stops completing
      in `finally`, or if **any** `Get-StatusAdapterResult` call site omits
      `-OnProgress` — a marked-active operation with no ticks goes stale and is
      restarted anyway, so the marker alone is not protection.

- [x] **Route coverage was right; the work inside the route still ran dark.**
      _(state: smoke-tested + live-proven — closed 2026-08-10, third pass)_
      With the classifier fix deployed, the assessment was **still** killed at
      215s. The watchdog was not at fault: it suppressed correctly while
      progress was fresh (ages 3s / 39s / 99s) and restarted only once progress
      had been stale for 159s > the 120s tolerance. Progress had genuinely
      stopped — between the local inventory ending (~04:52:55) and
      `cold-roadmap-scan` (04:55:09) sat a **134-second unpublished GitHub
      phase**. `Get-GitHubReposViaApi` makes sequential per-repo network calls
      (`Get-LatestGitHubWorkflowRunViaApi`, plus the Pages lookup inside
      `ConvertTo-GitHubRepoMetadata`) — ~150 round-trips across the portfolio,
      publishing nothing. Both broken routes reach it through the same
      `Add-GitHubMetadataToStatusResult`, so one fix covers both. Now ticks per
      repo inside the loop, and per owner (a dead owner returns zero repos, so
      the per-repo tick never runs). **The second-pass tripwire asserted the
      wrong invariant** — "every `Get-StatusAdapterResult` call site passes
      `-OnProgress`" is call-site wiring, and it passed while a third of the
      assessment ran dark. The replacement enforces the actual property via the
      AST: a loop containing per-item network calls must publish **from inside
      that loop** (a tick outside does not bound the silent window).
      **Evidence:** `network-loop progress ok: 2 per-item GitHub loop(s) all
      tick from inside the loop`; adversarially proven by running the detector
      against the pre-fix file — **2 violations, exactly the two loops that
      caused the outage**. An earlier draft of the detector produced a false
      positive (`Invoke-MergeReadinessForRepo`, which has a loop and a network
      call but not one inside the other) and was tightened to true lexical
      containment. **Live production proof:** assessment completed **HTTP 200
      in 235s** (previously dead at 215s), watchdog progress age never above
      12s across four probes (was 3→39→99→159→kill), **zero restarts**.

- [x] **`/api/status` ran a full-portfolio scan on the 180s tier and the
      deadline guard killed the host.** _(state: smoke-tested — closed
      2026-08-10, third pass)_ Reported as an endless spinner on the roadmap
      modal. The request deadline does not fail the request on expiry — it
      calls `Environment.FailFast`, terminating the process. `GET /api/status`
      — the route the browser polls — runs `Get-StatusAdapterResult` over the
      workspace plus ~150 GitHub calls, but was on the **default** tier:
      `Process terminated. API request deadline exceeded for GET /api/status
      (timeoutSeconds=180)`, started 05:09:10 and dead at 05:12:10, exactly
      180s. Three occurrences on 2026-08-10 (04:06:25, 04:58:50, 05:12:14),
      predating the heartbeat work — a distinct, pre-existing defect, not a
      regression. This is the failure the tier's own comment says it exists to
      prevent: "the guard becoming the outage it exists to prevent". The smoke
      test had explicitly asserted `/api/status` was an ordinary route; that
      classification was the bug, and it was corrected **on production
      evidence**, not to make a change pass. **Evidence:** `scan-route deadline
      tier ok: 7 full-portfolio route(s) all on the extended tier` — the
      tripwire derives tier membership from what each handler actually calls
      (`Get-StatusAdapterResult` / `Invoke-PortfolioAssessment` /
      `Get-OperationsReposPayload`) rather than a hand-maintained list, since a
      hand-maintained list is exactly what drifted; verified against the
      pre-fix tier list — **1 violation, `GET /api/status`**.
      **Live production proof (2026-08-10 17:22, service running the fixed
      code since 05:59:40):** a forced cold scan
      `GET /api/status?refresh=true` returned **HTTP 200 in 194s** — past the
      180s deadline that previously terminated the process — with the service
      PID unchanged across the request and **no new `FailFast`** (the last
      remains 05:45:52, before the fix loaded). The reported symptom is gone:
      the roadmap modal's endpoints answer immediately
      (`/api/roadmap-agent/history` 200 in 0s, `/api/roadmap/content` 200 in
      4s) where both previously hung behind a scan about to kill the host.
      **[non-blocker]** `FailFast` as deadline policy means one slow request
      destroys every in-flight request; the blast radius is a design question
      left open.


### Lane 0.6 — Workspace-path failure was silent (P0, 2026-08-08)

- [x] Point the zero-scope action hint at the specific cause when a root is
      missing. _(state: smoke-tested — closed 2026-08-09)_ The ActionBar hint
      read the generic "Scan a workspace first — set the workspace path in
      Settings, then Refresh" while the red alert directly above it named the
      actual missing path. `repoActionsBlockedReason` now takes the same
      `missingRoots` the alert reads and, when one is present, names the path
      and the thing to check ("reconnect the drive or correct the path"), since
      telling an operator to scan a workspace they have already configured is
      redundancy, not guidance. The generic remedy survives for the genuine
      nothing-configured case, where it is the correct next step. **Blank
      entries fall back rather than manufacturing a claim about nothing.**
      **Evidence:** `npm run test:unit` — five new `dataProvenance` assertions
      covering single root, multi-root summarisation, blank-root fallback, and
      that a populated scope stays unblocked even with a missing root.


### Lane 0.5 — Portal UX follow-ups (empty-state audit 2026-08-08)

- [x] **A render error in any component no longer white-screens the portal.**
      _(state: smoke-tested — closed 2026-08-10)_ No error boundary existed
      anywhere: one render-time throw in any of ~38 components killed the
      entire UI with no message and no recovery.
      [`ErrorBoundary.tsx`](frontend/components/ErrorBoundary.tsx) now mounts
      twice — `index.tsx` wraps `<App />` as the last resort, and Dashboard
      wraps the active tab panel with `key={activeView}`, so a crashed view
      degrades to a card naming the view and the error while the header, tab
      strip, and the other five views keep working; switching tabs resets the
      boundary. **Evidence:** four DOM tests — untouched happy path, named
      card with `role="alert"`, Try-again genuinely re-renders after the
      cause is gone, and a still-broken child re-shows the card.

Surfaced by a walkthrough of the Repository Grid, Insights, Operations, and
Doc Readiness Queue tabs against a workspace that scanned 0 repos. The two
data-integrity findings from that audit were fixed the same day and are in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd);
these two are design-dependent and deliberately deferred.

- [x] **Add a confirmation step to implicit bulk-scope actions.** _(state:
      smoke-tested — closed 2026-08-10)_ With no rows selected, Pull/Fetch/Report
      applied to the **entire filtered set** (75 repos on the real workspace)
      behind nothing but an amber banner. **Ben settled the deferred product
      call 2026-08-10: mutating actions always confirm; read-only ones keep
      their single click.** So Pull and Fetch gate on a `window.confirm` naming
      the command and the count; `Report` (and Doc Review, and Roadmap Scan) are
      read-only and reversible, and spending the dialog there would train the
      operator to dismiss the one that matters. The rule is **"mutating +
      implicit", not "mutating + big"** — no threshold, because two working
      trees the operator did not name is still two they did not name. An
      explicit selection never re-asks: that selection _is_ the operator naming
      the scope. Encoded in [`lib/bulkScope.ts`](frontend/lib/bulkScope.ts),
      which lists the mutating actions **by name** so a new bulk action is a
      deliberate decision on both sides of the line rather than silently
      defaulting to no confirmation. **Evidence:** 11 new `bulkScope`
      assertions.

- [x] **Progressive disclosure for the six-tab dashboard — the navigation
      defect underneath it.** _(state: smoke-tested — closed 2026-08-10)_
      Investigating the density complaint found a concrete cause rather than a
      taste question: **the Insights tab rendered its content above the tab
      bar.** 558 lines and six widgets sat in a container preceding
      `<DashboardViewTabs>`, while the Insights tab panel held one sentence —
      "Insights widgets are shown above this section." Clicking Insights
      inserted ~560 lines above the control the operator had just clicked,
      pushing the tab bar off-screen; the panel then pointed back upward. The
      tab metaphor was inverted for one of six tabs.
      Fixed by extracting
      [`InsightsView.tsx`](frontend/components/InsightsView.tsx) over a pure
      [`lib/portfolioTrendView.ts`](frontend/lib/portfolioTrendView.ts) and
      mounting it **inside** the panel. **Enforced, not just fixed:** a
      module-smoke tripwire fails if `<InsightsView>` ever precedes
      `<DashboardViewTabs>` in source, if any `activeView === '…'` render gate
      sits above the tab strip (so a _future_ tab cannot repeat it), or if the
      "shown above this section" apology copy returns. Adversarially proven —
      re-injecting the old layout fires both assertions.
      **This also took `Dashboard.tsx` from 2,308 to 1,752 lines**, closing the
      larger half of the Phase D decomposition non-blocker below.
      **Evidence:** `npm run test:unit` 149 passing across 11 files (22 new
      `portfolioTrendView` assertions covering the sparkline edge cases —
      empty series, flat series, single point — that previously rendered as
      `NaN` path data, i.e. a silently blank chart); `npm run typecheck` and
      `npm run build` exit 0; module smoke exit 0.


### Lane 0.7 — Roadmap-standard fidelity: split-history awareness (2026-08-08)

- [x] **Fold `tools/Test-RoadmapStructure.ps1` into the shared detection
      contract — it was the third private copy.** _(state: done 2026-08-08)_
      The linter now reads `detection.releaseStatusPattern` and
      `detection.statusVocabulary` from the rule pack at load
      (`Import-RoadmapStatusContract`); the literals it keeps are a declared
      mirror for standalone use in a repo that does not vendor the standards
      tree, byte-identical to the JSON and guarded by a test that diffs them
      against it. Its private map was **not** a subset of the pack's — it knew
      `pending` and `released`, which were merged into `statusVocabulary` when
      this was found, and it was missing twelve the pack had (`deferred`,
      `on hold`, `in review`, `paused`, …), so the same word could read as a
      status in one tool and as unknown in the other. Folding it in also
      forced a **rule-pack 1.4** correction: the linter's regex tolerated
      `Status: done. Shipped 2026-05.` and `Status: active, pending review`,
      which the 1.3 pattern matched **not at all**, so adopting 1.3 unchanged
      would have converted readable statuses into `RQ001-MISSING-STATUS`
      warnings. Sentence punctuation (`.`, `,`, `;`) is now a status
      terminator in the shared pattern; tolerance still applies to reading
      only. That widening immediately exposed a second defect the linter's
      stricter copy did not have: 1.3 made the **colon optional**, so any
      prose line opening with the word "status" parsed as a declaration — this
      lane's own write-up tripped `RQ002-INVALID-STATUS` on a sentence. The
      colon is mandatory in 1.4, which makes the shared pattern strictly more
      precise than 1.3 rather than only more tolerant. Evidence: `Test-RoadmapStructure.Tests.ps1` 27/27 (3 new cases —
      punctuation tolerance, full alias vocabulary, and a pack-vs-mirror
      equality guard), linter output on this `ROADMAP.md` byte-identical
      before and after, `Invoke-ModuleSmokeTest.ps1` exit 0, and
      `Invoke-TestSuite.ps1 -SkipApiHost` 11/11 gates green. `Test-RoadmapStructure.Tests.ps1`
      28/28 (4 new cases — punctuation tolerance, mandatory colon, full alias
      vocabulary, and a pack-vs-mirror equality guard).

- [x] **"Product Direction" accepted into the product-intent vocabulary.**
      _(state: done 2026-08-08 — decided in the standard, not in this repo's
      file)_ `productIntentHeadingPattern` recognized `product intent`,
      `product scope`, `overview`, `about`, `purpose`, `background`, and
      `what this does/is`, but not **`Product Direction`** — the heading
      section 2 actually uses, and a plain synonym of the already-accepted
      `product intent` rather than a missing section. Renaming this repo's
      heading would have left the same false negative in place estate-wide for
      any repo using the synonym, so the vocabulary was widened in rule pack
      1.4 instead. `productIntentNote` now records that synonyms are added on
      evidence, not speculatively. Evidence: this repo's contract score
      **92 → 100** (`L4-Orchestration-Ready` both before and after) with
      ROADMAP-004 the only rule that changed state.


### Lane 0.8 — Verification gate integrity (CI audit 2026-08-10)

- [x] **Make the gate honest, then delete `ci.yml`.** _(state: smoke-tested —
      closed 2026-08-10)_ Implemented in a **stronger form than planned**:
      instead of mirroring the gate list into `ci-smoke.yml` and policing the
      two copies, CI now **invokes `Invoke-TestSuite.ps1` itself** (checkout →
      setup-node → `npm ci --include=optional` → the suite), so local
      `npm test` and CI are one list **by construction** — mirroring would
      also have preserved the reverse gap, since the local suite already
      covered three gates CI never ran (OpenAPI spec, spec dir,
      roadmap-audit-action). The suite gained the three frontend gates
      (`typecheck`, `test:unit`, `build`) via `Invoke-NpmGate`, which **fails
      with a named cause** when npm or `node_modules` is missing rather than
      skipping — a suite that silently passes without Node is the vacuous
      green this item exists to kill. `ci.yml` and `reusable-ci.yml` are
      deleted (no external caller per `gh search code`). Folded-in hardening:
      the suite's default port moved **7071 → 7171** — `Clear-ListenerPort`
      kills whatever listens on the target port, so a bare `npm test`
      previously terminated the operator's live portal. **Evidence:** full
      suite exit 0 with the three frontend gates in the summary; the landing
      PR's own CI Smoke run is the first honest CI pass — that green is the
      live proof, not a prior claim.

- [x] **Tripwire: CI must cover the local suite.** _(state: smoke-tested —
      closed 2026-08-10)_ Module smoke now fails if `ci-smoke.yml` stops
      invoking the suite, smuggles in `-SkipApiHost`, adds a `paths` filter
      (filtered PRs merge on no evidence), drops the `pull_request` trigger,
      skips `npm ci`, or if either vacuous workflow file returns; and it
      fails if the suite itself is hollowed (≥7 script gates asserted, and
      `typecheck`/`test:unit`/`build` by name). Comment lines are stripped
      before matching, per the Lane 0.5 precedent. **Evidence:** module
      smoke — `ci-smoke.yml runs the full suite (7 script gates, 3 npm
      gates)`; adversarially proven with seven scratch mutations (baseline
      passes, six hollowings each fire the specific assertion).

- [x] **Close the render gap.** _(state: smoke-tested — closed 2026-08-10)_
      jsdom + `@testing-library/react`; `*.test.tsx` files run under jsdom via
      a per-file pragma so the pure-logic tests keep the cheaper node
      environment. Fifteen DOM tests across three components, each asserting
      the half its pure-logic twin cannot see: **ActionBar** — the component
      actually consults `requiresBulkConfirmation`, Cancel really stops the
      action, explicit selection skips the dialog, read-only Report never
      shows it, and the zero-scope hint names the missing root;
      **DashboardViewTabs** — every `VIEW_META` view is reachable, selection
      fires, the subtitle tracks the active view; **InsightsView** — the
      panel body renders (the DOM half of the Lane 0.5 contract), an idle
      ledger stays visible with an explanation while never-loaded metrics
      show the distinct unavailable state, a failed refresh labels the stale
      snapshot, and the analytics Retry is wired to the trend loader.
      **`playwright` removed** from root devDependencies — unused; its only
      codebase reference was a keyword string in the roadmap linter.
      Folded-in hardening: `npm audit fix` cleared 4 advisories (3 high,
      incl. the vite Windows UNC-path fs.deny bypass) → **0 vulnerabilities**.
      **Evidence:** `npm run test:unit` 164 passing across 14 files (15 new
      DOM assertions); typecheck, build, module smoke all exit 0.

- [x] **Linting — failing gates from day one, with the debt ratcheted.**
      _(state: smoke-tested — closed 2026-08-10)_ Landed stronger than the
      report-only plan: both linters are **failing suite gates immediately**,
      with pre-existing debt held by ratchets that only tighten. **ESLint**
      (flat config, typescript-eslint + react-hooks): initial wall was 185;
      real defects fixed at adoption — `RepoGrid`'s
      `declare global JSX IntrinsicElements: any` escape hatch **deleted**
      (it disabled element-name typechecking app-wide; typecheck stayed clean,
      so nothing hid behind it), `RoadmapViewerModal` use-before-declaration
      reordered, `ChangeHistoryPanel` impure `Date.now()` render moved to a
      lazy initializer, `apiClient` dead assignments removed and the scan
      timeout now carries its `cause`, ~20 dead imports/vars deleted. Debt
      rules (`no-explicit-any` 123, `set-state-in-effect` 31) downgraded to
      warn under `--max-warnings 161`. **PSScriptAnalyzer**
      ([`Invoke-LintGate.ps1`](scripts/Invoke-LintGate.ps1) +
      `PSScriptAnalyzerSettings.psd1` + `scripts/pssa-baseline.json`): the
      one Error-severity finding **fixed** (`New-AdapterResponse`'s `$Error`
      parameter shadowed the automatic variable; JSON key unchanged), Errors
      hard-zero forever, 598 warnings baselined per-rule (17 rules), any
      growth or new rule fails, `-UpdateBaseline` locks improvements in.
      `PSAvoidUsingWriteHost` (723) excluded as **policy** — gate scripts'
      operator UI — not counted as debt. **Evidence:** ratchet adversarially
      proven (+1 `Invoke-Expression` → FAIL naming rule/delta/site; removed →
      PASS); suite now 17 gates; typecheck, lint, 164 unit tests, build,
      module smoke all exit 0.


### Current Status narrative (dated milestone notes, archived from ROADMAP.md section "Current Status")

These are the running milestone notes that accumulated at the top of the
active roadmap between 2026-08-08 and 2026-08-10. They are history, not open
work, and were crowding the one section whose job is to answer "what is the
next concrete work item?" — so they moved here on 2026-08-11 and the active
file kept a compact status in their place.

**MILESTONE 2026-08-10 — verification is structurally enforced (Lane 0.8
closed same-day, PRs #102–#107).** Before today the merge signal was half
convention: the frontend's tests/typecheck/build gated nothing, one of the two
green checks executed nothing, no linter ran, and `main` was unprotected. Now
`ci-smoke.yml` **invokes `Invoke-TestSuite.ps1` itself** (17 gates — one list
for CI and local, tripwired against hollowing), both linters fail the build
(ESLint 0-errors + 161-warning ratchet; PSSA Errors hard-zero + 598-warning
per-rule ratchet), error boundaries stop render-throw white-screens, and
`main` **requires** the `smoke` check with `enforce_admins` on. **The
enforcement was demonstrated, not just configured:** PR #107 sat `BLOCKED`
while its required check ran and merged only after `completed/success` →
`CLEAN` — a blocked-then-clean merge is the required check working in anger.
The two lint baselines are **controlled technical debt**: counts may only
shrink, reductions land as the small planned batches at the end of Lane 0.8,
and `set-state-in-effect` is deliberately excluded from mechanical cleanup.

**Closed 2026-08-10 — Lane 0.5, and a navigation defect hiding under it.** The
"six-tab dashboard is dense" complaint had a concrete cause: **the Insights tab
rendered its content above the tab bar.** Clicking Insights inserted ~560 lines
above the control just clicked, pushing the tab strip off-screen, while the panel
underneath held only "Insights widgets are shown above this section." Fixed by
extracting `InsightsView.tsx` and mounting it inside the panel — which also took
`Dashboard.tsx` from 2,308 to 1,752 lines. Bulk-scope confirmation shipped
alongside it on the rule Ben settled: mutating actions always confirm, read-only
ones keep their single click. The wider progressive-disclosure question stays
open and is now a smaller one.

**Closed 2026-08-09 (third pass) — Release 3.0, the dispatch that could never
run.** All five milestones ship: the guided-improvement wizard enqueues with
`dispatchTarget: 'copilot'` instead of calling the launcher in-process, the
operator-session runner executes it with `gh agent-task create` and records the
task URL, runner presence is readable before work is queued, a logon-task
installer registers the runner as an interactive user (and refuses SYSTEM), and
in-host cloud dispatch is a 409 that names the runner. **Release 3.0 is
engineering-complete and archived** (its full text moved to
[the archive](docs/history/completed-releases.md#release-30--operator-context-execution)
the same day, per the split rule in section 8); the one live `gh agent-task`
round trip belongs to 2.9's
operator session, batched with the 2.8 `claude` run it shares a prerequisite
with. Two corrections worth carrying: the token check in front of the old
dispatch was answering the wrong question (a PAT passed it and the dispatch still
failed), and the refusal had to be unconditional rather than service-conditional.

**Closed 2026-08-09 (second pass) — every recorded non-blocker that did not need
an operator decision.** Phase C's two: the approval queue now has an operator UI
on the Operations tab (mirroring the backend's transition matrix so it cannot
offer an action that 409s), and packaging has its own overdue alert from a
second health reader over its own history file. Plus Lane 0.2's null rate-limit
readout, Lane 0.4's root worklogs (archived, gitignored, documented, and now
tripwired), and Lane 0.6's zero-scope action hint. Two of these were larger than
their notes implied: the rate-limit item named one call site and a source
tripwire found a second, and the worklog item asked for a move that would have
overwritten genuine earlier history.

**Closed 2026-08-09 — Release 2.7 Phase C, the largest remaining product
increment.** Scheduled roadmap-item packaging is built and smoke-tested end to
end: a scheduled run ranks each curated L3+ repo's pending work, packages the
top-value item into a task packet + repair-PR plan, prices it through the
quota guard (skipping over-budget repos with the guard's own code), notifies,
and stops at the approval gate. Dispatch happens only through an explicit
approval, which enqueues to the Release 2.8 operator-runner queue. **Release
2.7 is now engineering-complete** — every remaining item in it is either an
external-resource proof (Phase D's elevated service install) or a recorded
non-blocker. Detail and evidence are on the Phase C milestones below.

**Closed 2026-08-09:** Lane 0.4's cold-scan request deadline — the freeze guard
now classifies routes into a 180-second default tier and a 900-second
full-portfolio-scan tier, so a legitimate cold scan no longer trips the guard
into a restart loop, and neither smoke gate needs a timeout override any more.
Also **both remaining Phase D frontend items**: the unit-test set reached 4 of 4
named units by extracting the value-tier and curation-scope logic into pure
`frontend/lib` modules the components now consume, and the `Dashboard.tsx`
decomposition landed its two named extractions (tab shell, summary/mission).
**Release 2.7 Phase D is now engineering-complete** except for the live service
deployment its freeze-prevention item has always been waiting on (an elevated
Windows install). The only open 2.7 work is Phase A and the Phase C it gates.
Also Lane 0.3's hardcoded workspace defaults, where the fix is now enforced by a
module-smoke tripwire rather than just applied — the tripwire found two `F:\`
offenders that the item's own `G:\` file list could never have named.

**Closed 2026-08-08 and archived out of this file:** the settings.json
regression (Lane 0.1, which closed entirely), the silent workspace-path
failure, Lane 0.5's two data-integrity findings, the credential reissue and
live-validation probe, the service's readable token, the two smoke gaps,
scheduler failure alerting, two installer defects that had made the documented
credential fix a silent no-op, and the Copilot-dispatch OAuth diagnosis that
produced Release 3.0. Full text with evidence is in
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).
**This file now carries open work only** — every remaining checkbox is
something still to do.

### Release 2.7 — risks, dependencies, known issues and traceability (as carried in ROADMAP.md)

Archived 2026-08-11. Retained verbatim because the traceability catalogue is
the map from Phase B/C/D milestones to the functions, routes and docs they
shipped — the thing an agent needs when it has to change one of them and
wants to know what else moves. The risk list is kept for the same reason the
roadmap keeps cleared risks: the record of WHY a risk was retired is what
stops it being re-raised.

**Risks and blockers:**

- **Cleared 2026-08-09:** Phase A's credential/write-path blocker and the
  Phase C dependency it gated. The sequence held — packaging shipped only
  after one live PR round trip proved the write path.
- **Risk — auto-ranking on unproven writes.** Retired: packaging now sits
  behind a write path proven live (PR #96), so a packet's repair-PR plan
  names a route that demonstrably opens a PR.
- **Risk — the portal freezes under load.** Observed twice (2026-07-05,
  2026-07-11): process alive, port listening, not responding. The watchdog
  safety net is shipped but unproven at SYSTEM; the root-cause prevention
  work is still open in Phase D.
- **Risk — `app.db` growth.** ~138 MB in daily use. **Mitigated 2026-08-08:**
  scheduled prune + VACUUM ships in Phase D and runs daily from
  `Invoke-DailyEvidence.ps1`; per-table retention floors keep the trend
  windows Release 2.9 is waiting on intact.
- **Risk — the freeze guard kills the host during a legitimate cold scan.**
  The Phase D request deadline defaults to 180s and terminates the host on
  expiry, but a cold full-portfolio assessment over the real 75-repo
  workspace exceeds that. Tracked as the top open item in Lane 0.4.

**Dependencies:** `/api/scan/schedule` (1.2), repo curation states (2.3
Ph5), AI doc-improve preview/apply (1.9), the notification hub (1.1), the
quota/budget guard (2.0 Ph4), `roadmap-events.jsonl` (2.4), and valid
GitHub write credentials for Phase A onward.

**Known issues:**

- [ ] The freeze guard can kill the host during a legitimate cold scan. The
      Phase D request deadline defaults to 180s and terminates the host on
      expiry, but a cold full-portfolio assessment over the real 75-repo
      workspace exceeds that — so the guard that exists to protect the portal
      is the thing that stops it. Tracked as the top open item in Lane 0.4;
      Release 3.2 implements whichever way that decision lands.
- [ ] Phase C dispatches to the **operator runner**, not to the cloud. `gh
      agent-task` requires an OAuth token the LocalSystem service structurally
      cannot hold, so approval enqueues to the Release 2.8 queue
      (`output/roadmap-task-queue.jsonl` + a `queued` run summary) and
      `Invoke-RoadmapTaskRunner.ps1` executes it in the operator's session.
      That is the one dispatch path that works from a service today, and it is
      proven in both smokes. Cloud (Copilot) dispatch for packaged items still
      needs Release 3.0. An approved packet therefore reaches a **branch with
      committed work awaiting review**, not an open PR — the PR is opened
      through Phase A's submit-PR route, which the packet's repair-PR plan
      names, as a further operator action. Nothing auto-merges.

Both known issues that stood here on 2026-08-07 — the tracked `settings.json`
fixture path and the expired PAT — closed 2026-08-08; see
[the archive](docs/history/completed-releases.md#closed-2026-08-08-archived-from-roadmapmd).

**Traceability:** Phase C shipped
[`Automation.RoadmapPackaging.ps1`](backend/modules/automation/Automation.RoadmapPackaging.ps1)
(`Resolve-AutomationPackagingScope`, `Select-TopValueRoadmapItem`,
`New-RoadmapItemTaskPacket`, `Test-PackagingQuota`,
`Invoke-ScheduledRoadmapPackaging`, `Write-PackagingRunRecord` /
`Get-PackagingRunHistory`, `Get-PackagedItemQueue`,
`Test-PackagedItemTransition`, `Submit-PackagedItemToRunner`), the routes
`POST /api/automation/package-run`, `GET /api/automation/packages`, and
`POST /api/automation/packages/approve` / `/reject`, a `kind` filter plus
both-kind merge on `GET /api/automation/history`, and
`/api/automation/package-run` added to the extended request-deadline tier in
[`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1) (it reaches the
same full-portfolio scan `/api/automation/run` does). Operator-facing behavior
is documented in
[`local-task-runner.md`](docs/reference/local-task-runner.md). Phase B shipped
[`Automation.DocRefinement.ps1`](backend/modules/automation/Automation.DocRefinement.ps1)
(`Select-AutomationDocTargets`, `Invoke-ScheduledDocRefinement`,
`New-AutomationDigestPayload`, `Write-AutomationRunRecord` /
`Get-AutomationRunHistory`), `POST /api/automation/run`, `GET
/api/automation/history`, and the `automation` block on `GET
/api/scan/schedule`, with module + api-host smoke coverage. Phase D's
shipped half is [`Watch-PortalHealth.ps1`](scripts/service/Watch-PortalHealth.ps1),
[`Install-PortalWatchdog.ps1`](scripts/service/Install-PortalWatchdog.ps1),
the reworked
[`Install-RepoManagementService.ps1`](scripts/Install-RepoManagementService.ps1),
[`RequestDeadline.ps1`](backend/api-host/RequestDeadline.ps1) with the
cache-off regression guards, `Invoke-AppDbMaintenance` /
`Get-AppDbMaintenanceRetentionDays` in
[`Persistence.Store.ps1`](backend/modules/persistence/Persistence.Store.ps1)
behind `GET`/`POST /api/maintenance/database`, and `Get-AutomationHealth` /
`Get-AutomationRunOutcome` in
[`Automation.DocRefinement.ps1`](backend/modules/automation/Automation.DocRefinement.ps1)
behind `GET /api/automation/status`, surfaced by
[`AutomationStatusBadge.tsx`](frontend/components/AutomationStatusBadge.tsx).
Verification runs through `scripts/Invoke-TestSuite.ps1` (`npm test`), mirrored
in [`.github/workflows/ci-smoke.yml`](.github/workflows/ci-smoke.yml); the
Phase D frontend units live beside
[`frontend/lib/needsAttention.test.ts`](frontend/lib/needsAttention.test.ts).
Operator-facing behavior is documented in
[`docs/reference/operator-guide.md`](docs/reference/operator-guide.md).

## Release 2.7 — Guarded Scheduled Automation (closed 2026-08-11)

**Closed as a release on 2026-08-11.** Every phase is engineering-complete:
A (live submit-PR proof), B (scheduled doc refinement), C (scheduled
roadmap-item packaging), D (hardening and observability). What was still
open under it was never 2.7 engineering — it was one **elevated Windows
install** and one recorded non-blocker, so both were re-homed rather than
held open under a finished release:

- The **freeze-prevention live deployment** moved to Release 2.9, which
  exists to batch exactly this kind of elevated/hardware/human proof. All
  three of its engineering parts shipped and are smoke-tested; only the
  service install remains, and it shares an elevated session with the
  watchdog and service-installer proofs already sitting in 2.9.
- The **`Dashboard.tsx` decomposition non-blocker** moved to Release 3.2,
  where it pairs with the repo-grid virtualization milestone that already
  named it.

This also settled the governance question 2.7 had been carrying: it was
still marked the active release while holding no dispatchable engineering,
which is precisely the "everything is done" reading the roadmap vocabulary
exists to prevent. Release 3.2 is now active. Full section as it stood:

### Release 2.7 — Guarded Scheduled Automation (Curated-Subset, Preview-First)

**Status:** active

**Goal:** turn the operator-driven pipeline into a scheduled one that
advances **favorite / portfolio-candidate** repos automatically — proposing
README/ROADMAP refinements and packaging the highest-value ready roadmap work
on an interval — while stopping at the human approval gate. No silent
mutation, no auto-merge: everything runs preview-first, inside the existing
quota/budget guard, with an append-only audit trail.

**Prerequisites:** all met. Phase A's credential gate closed 2026-08-08 and the
live proof landed 2026-08-09; Phase C followed it the same day. Phase D's
remaining step needs an elevated (SYSTEM) Windows session.

#### Product outcomes

- The operator enables an interval and the app keeps the curated subset
  assessed and surfaces ready-to-approve improvements with no manual trigger.
- Scheduled runs package the top-value ready roadmap item per favorite repo
  into a review-ready task packet + repair-PR plan, inside the quota guard.
- Every scheduled action is recorded in append-only run history with a
  reason; failures raise an alert instead of failing silently.
- Archived/ignored repos are never touched — scope is exactly the curated set.
- The always-on portal does not freeze under ordinary daily load, and if it
  does, it recovers without operator intervention.

#### Engineering milestones

**Phases A and C are complete and archived** (2026-08-09). Phase A proved the
live submit-PR round trip that gated everything after it
([PR #96](https://github.com/xfaith4/GitHubRepoManagement/pull/96)); Phase C
shipped scheduled top-value roadmap-item packaging behind it, in
[`Automation.RoadmapPackaging.ps1`](backend/modules/automation/Automation.RoadmapPackaging.ps1)
and `POST /api/automation/package-run` / `GET /api/automation/packages` /
`POST /api/automation/packages/approve` / `/reject`. Full text and evidence:
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd).

Phase D — Hardening & observability. **Four of six items shipped and are
archived** (frontend unit-test set, `Dashboard.tsx` tab-shell and
summary/mission extractions, plus the two closed earlier). What remains:

- [ ] **Freeze prevention (root cause), paired with the shipped watchdog.**
      Guarantee `/api/status` + assessment caching cannot regress off (a
      gutted cache caused the 2026-07-05 blocking-scan pile-up); add a
      per-request work timeout so one blocked native call — e.g. the SQLite
      bridge — cannot wedge the single-threaded accept loop; schedule
      `app.db` maintenance (VACUUM + snapshot retention; ~138 MB and
      growing). _(state: in progress — all three engineering parts are now
      built and smoke-tested; only live service deployment (elevated Windows
      install) remains.)_ Cache-off regression guards and the 180-second host
      request deadline landed 2026-08-08; the deadline records the
      route/correlation ID and exits a wedged host so Shawl/SCM recovery
      restarts it. **Scheduled `app.db` maintenance landed 2026-08-08:**
      `Invoke-AppDbMaintenance` prunes the seven snapshot/history tables and
      runs `VACUUM`, exposed as report-only `GET /api/maintenance/database`
      and mutating `POST /api/maintenance/database`, and driven daily from
      [`Invoke-DailyEvidence.ps1`](scripts/Invoke-DailyEvidence.ps1) through
      the host's own route (the host holds the SQLite connections, so an
      out-of-process VACUUM would contend for the write lock). Retention
      windows are clamped **up** to a per-table floor — 180 days for every
      table with a history reader — because `GET /api/portfolio/trend` answers
      up to `days=180` and Release 2.9 is waiting on 7/90-day accrual; a low
      configured window must never delete the history that milestone needs.
      Append-only operational records (`execution_ledger`,
      `execution_history`, `agent_runs`, `repo_curation`) are never touched.
      **Evidence:** module smoke asserts report-only counts without deleting,
      the 180-day floor protecting 100-day-old rows against a 30-day request,
      VACUUM running, and `ops_log` untouched; api-host smoke
      `dbMaintenanceOk=True` asserts the floor survives the HTTP round trip.
- [ ] **[non-blocker]** `Dashboard.tsx` is **1,752 lines** (2,519 → 2,308 after
      the Phase D extractions → 1,752 on 2026-08-10). The ~600-line Insights
      block this item named is out: it became
      [`InsightsView.tsx`](frontend/components/InsightsView.tsx) over a pure
      [`lib/portfolioTrendView.ts`](frontend/lib/portfolioTrendView.ts) as a
      side effect of fixing the Lane 0.5 tab-inversion defect. What remains is
      ~1,000 lines of hooks and handlers above the return — a different shape of
      problem from the JSX blocks, and one with no user-visible symptom driving
      it. _(state: planned — worth doing, not worth blocking on.)_

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
- One live PR exists in a real repo, created through the submit-PR route.
- A blocked native call no longer wedges the accept loop, and `app.db`
  maintenance runs on a schedule.
- `npm run typecheck` and `npm test` pass; new automation smoke covers the
  schedule → preview → notify → history loop.

#### Out of scope

- Auto-merge, or any write that bypasses the operator approval gate.
- Autonomous execution on non-curated (default) repos.
- Multi-tenant scheduling or per-agent automation credentials.

**Validation plan:** run `npm run typecheck`, `npm test`
(`scripts/Invoke-TestSuite.ps1`, mirroring `ci-smoke.yml`), and the
automation smoke; confirm each exits 0. Drive a scheduled run against a
fixture favorite set and confirm previews + digest + history with **zero**
applied changes. For Phase C, additionally assert the quota-refusal path and
that dispatch fires only on an explicit approval action.

**Risks and blockers:**

- **Risk — the portal freezes under load.** Observed twice (2026-07-05,
  2026-07-11): process alive, port listening, not responding. The watchdog
  safety net is shipped but **unproven at SYSTEM**; the root-cause prevention
  work is the one open engineering item left in Phase D.
- **Cleared, and kept here because the reasons matter.** Phase A's
  credential/write-path blocker and the Phase C dependency it gated (the
  sequence held — packaging shipped only after one live PR proved the write
  path); auto-ranking on unproven writes; `app.db` growth (~138 MB, mitigated
  by the scheduled prune + VACUUM); and the freeze guard killing a legitimate
  cold scan, which Lane 0.4 settled as an extended 900s tier rather than an
  exemption. Detail in
  [the archive](docs/history/completed-releases.md#release-27--risks-dependencies-known-issues-and-traceability-as-carried-in-roadmapmd).

**Dependencies:** `/api/scan/schedule` (1.2), repo curation states (2.3
Ph5), AI doc-improve preview/apply (1.9), the notification hub (1.1), the
quota/budget guard (2.0 Ph4), `roadmap-events.jsonl` (2.4), and valid
GitHub write credentials for Phase A onward.

**Known issues:** none open. The two that stood here on 2026-08-07 closed
2026-08-08, and the cold-scan freeze-guard issue closed 2026-08-09 via Lane
0.4's tier decision. That Phase C dispatches to the **operator runner** rather
than the cloud is shipped, documented behavior, not a defect — `gh agent-task`
needs an OAuth token a LocalSystem service structurally cannot hold, so an
approved packet reaches a branch with committed work awaiting review and the PR
is opened through Phase A's submit-PR route as a further operator action.
Nothing auto-merges.

**Traceability:** the full map from Phase B/C/D milestones to the functions,
routes and docs they shipped is in
[the archive](docs/history/completed-releases.md#release-27--risks-dependencies-known-issues-and-traceability-as-carried-in-roadmapmd).
Verification runs through `scripts/Invoke-TestSuite.ps1` (`npm test`), mirrored
in [`.github/workflows/ci-smoke.yml`](.github/workflows/ci-smoke.yml).
Operator-facing behavior is documented in
[`docs/reference/operator-guide.md`](docs/reference/operator-guide.md) and
[`local-task-runner.md`](docs/reference/local-task-runner.md).

#### Phase plan (within this release)

| Phase                                | Scope                                                                                                   | Status                                                   | Completed  | Token usage | Work units |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ---------- | ----------- | ---------- |
| Phase A: Unblockers                  | Live submit-PR proof on one write-enabled repo                                                          | **done — proven live** (PR #96)                          | 2026-08-09 | —           | —          |
| Phase B: Scheduled doc refinement    | Scheduler + favorite-scoped doc-improve previews + digest + run history                                 | **done — smoke-tested** (2026-07-06) — see archive       | 2026-07-06 | —           | —          |
| Phase C: Scheduled roadmap packaging | Top-value item packaging + quota guard + approve-to-dispatch + approval UI + packaging health           | **done — smoke-tested**; both non-blockers closed        | 2026-08-09 | —           | —          |
| Phase D: Hardening & observability   | Frontend unit tests, Dashboard decomposition, failure alerting, freeze prevention, auth operator-verify | **in progress — 4 of 6 shipped; 2 open (frontend)**      | —          | —           | —          |

#### Budget guardrail

- Scheduled automation consumes AI work units per packaged item; every run
  routes through the Release 2.0 quota/budget guard and refuses or annotates
  over-budget work rather than proceeding.
- Record raw observations per scheduled run (units consumed, credit/API
  spend, refusals) into the automation run history.

---


## Closed 2026-08-15 (archived from ROADMAP.md)

Moved out of the active roadmap on 2026-08-15 under the archive rule, after
Release 3.4 reached its `R013-FUTURE-RELEASE-SIZE` cap of 120 lines. Both items
below shipped and are **verbatim** as they stood in `ROADMAP.md`.

Worth preserving alongside them: these two milestones were **recorded as
`planned` for a full day after they shipped** ([PR #134](https://github.com/xfaith4/GitHubRepoManagement/pull/134)
shipped the code and updated no milestone state), and the next agent to read the
roadmap was one step away from reimplementing a tested 306-line module. The
correction landed in [PR #136](https://github.com/xfaith4/GitHubRepoManagement/pull/136).
That is the origin of the section 8 guardrail requiring milestone state and
delivery documentation to move in the same pull request as the capability.

### Release 3.4 — The Delivery Loop Closes (first two milestones)

- [x] **Syncing `main` is a capability, not just a refusal.** **Operation shipped
      2026-08-14** ([PR #134](https://github.com/xfaith4/GitHubRepoManagement/pull/134));
      **step 10 and the operator surface shipped 2026-08-15.**
      [`Git.DefaultBranchSync.ps1`](../../backend/modules/git/Git.DefaultBranchSync.ps1)
      is the road behind 3.1's stop sign: fetch and fast-forward are separate
      explicit commands, never `git pull`, so a repo-local `pull.rebase` cannot
      turn a sync into a history rewrite, and `--ff-only` — the one git operation
      incapable of authoring a commit — is the only merge. Only `behind`
      fast-forwards; `ahead` refuses as `default-branch-ahead`, `diverged`
      refuses because a fast-forward is impossible, and dirty tree, detached
      HEAD, an unverifiable reading and an unapproved transition each refuse by
      name.

      **The residue was a door, not an operation.** For a day the module was
      reachable only from the task runner, because the api-host **never
      dot-sourced it** — so no control an operator could click could reach a
      capability that was already built, already tested, and already shipped.
      `POST /api/git/sync-default-branch` is that door, and it adds no policy of
      its own: refusals are the module's own category, reason and remedy
      forwarded verbatim as a 409, the same shape `runner-absent` and
      `stale-base` already use. Approval remains an **input** to the operation,
      so an omitted flag refuses as `approval-required` rather than meaning yes.
      The control lives in the per-repo git status modal rather than on every
      grid row — the 2026-08-14 UI review found nine equal-weight buttons per row
      already, and Release 3.5 is scheduled to reduce that, not add to it.
      _(state: smoke-tested — the decision matrix and the operation itself
      against real fixture clones (module smoke), the route's refusal, 404 and
      validation contracts over a live host
      ([`ApiHost.Contract.Tests.ps1`](../../backend/api-host/ApiHost.Contract.Tests.ps1)),
      and the control's refusal rendering
      ([`DefaultBranchSyncButton.test.tsx`](../../frontend/components/DefaultBranchSyncButton.test.tsx)).
      All four route assertions were **run against the pre-route host and failed
      there** — the refusal case is the load-bearing one, because it is the only
      assertion that distinguishes "the route exists" from "the route exists AND
      the module is loaded in this host", which was the entire defect.)_

- [x] **Ahead and behind are both real, and divergence is named.** **Shipped
      2026-08-14** (PR #134). [`Git.BaseFreshness.ps1`](../../backend/modules/git/Git.BaseFreshness.ps1)
      computed `HEAD..remote` and never the reverse, so a clone 5 behind _and_
      carrying local commits reported "behind 5" and said nothing about the local
      side — the exact state where a fast-forward refuses. Both directions now
      come from one `rev-list --left-right --count` walk, and `diverged` is its
      own state with its own remedy. _(state: smoke-tested)_

---

### Release 3.4 — The Delivery Loop Closes (milestones 3 and 4, closed 2026-08-15)

- [x] **A pushed branch does not end at "open the PR from GitHub when ready."**
      **Shipped 2026-08-15.**
      [`Roadmap.PrSubmitter.ps1`](../../backend/modules/roadmap/Roadmap.PrSubmitter.ps1)
      already opened pull requests with ten named refusals, proven live in 2.7
      Phase A — but only for roadmap repairs, because branch-and-PR logic was
      entangled with commit-the-roadmap-file logic in one function.
      `Open-RepoBranchPullRequest` is the separation: push (never force, never
      the base branch) and PR-open for ANY committed branch, behind its own
      eight-refusal matrix (`Test-RepoBranchPrPreconditions`), with a PR that
      already exists returned as `alreadyExisted` rather than surfaced as a raw
      422 — approving twice is idempotent, not an error. The repair submission
      now routes through it, so the two callers cannot drift; and
      `POST /api/roadmap-agent/approve-push` opens the run's PR after its
      proven push. A PR refusal after a successful push is reported as a
      partial success with the refusal named — an operator without a token
      still gets the push, plus the reason no PR appeared.
      _(state: smoke-tested — the matrix's eight categories asserted
      individually; the impure entry point proven to RETURN refusals rather
      than throw, against a real fixture repo, for the tokenless and
      missing-branch cases, both firing before anything could reach the
      network.)_

- [x] **Roadmap completion travels through the pull request, never after it.**
      **Shipped 2026-08-15.** `POST /api/roadmap/write-back/apply` was gated on
      merge evidence and then wrote the checkbox with a bare `Set-Content` on
      whatever branch was checked out — `main`, at that point in the loop.
      `Add-RoadmapCompletionCommit`
      ([`Roadmap.WriteBack.ps1`](../../backend/modules/roadmap/Roadmap.WriteBack.ps1))
      now commits the completion edit on the feature branch during the run —
      refusing BY NAME on a default branch, which is the acceptance criterion
      made executable — and the runner records the outcome
      (`committed` / `already-complete` / `item-not-found` / refusal) in the
      run summary rather than dying on it. The apply route inverted: a
      checkbox already `[x]` after the merge is the SUCCESS (the PR carried
      it; recorded as `action: verified-merged` in the append-only ledger,
      still behind the gate), and one still open refuses as
      `completion-not-merged`. The route writes no file content at all.
      The base-freshness reading travels ON the completion record rather than
      gating it: the runner already refused a stale base before the branch
      existed, and after that the PR merge is the arbiter — what the
      2026-08-11 triage lacked was evidence, not another refusal.
      _(state: smoke-tested — reproduced in a fixture: the default-branch
      refusal proven with the file untouched, the feature-branch commit proven
      by HEAD moving with only its own checkbox flipped and a clean tree,
      idempotency proven, unknown item named. The 3.1-era tripwire that
      REQUIRED a gated write site in the host was inverted and **failed red
      against the new host before it was rewritten** — the proof the behavior
      change is real. Its replacement asserts the host writes no completion
      edit anywhere and that the `verified-merged` record stays inside the
      merge-evidence gate.)_

---

### Release 3.4 — The Delivery Loop Closes (milestones 5 and 6, closed 2026-08-15)

- [x] **A merged branch is cleaned up, and cleanup proves it is the branch that
      merged.** **Shipped 2026-08-15.** No deletion of any kind existed, so every
      completed item left two branches behind.
      [`Git.BranchCleanup.ps1`](../../backend/modules/git/Git.BranchCleanup.ps1)
      requires **both** a merged pull request's head SHA **and** the branch tip
      still equalling it — deliberately stricter than `git branch -d`, whose
      merged check proves neither *which* merge nor squash merges at all.
      `tip-advanced` refuses because commits past the merged head are not in the
      default branch and deleting the branch would destroy them; `checked-out`
      refuses for the current checkout and linked worktrees alike, before git
      has to; `default-branch` refuses always; `no-merge-evidence` refuses when
      no SHA is presented, because deletion is not tidiness — it is the last
      step of a proven merge, and the proof travels as the SHA. Remote deletion
      is optional, never forced, and a remote failure does not undo the proven
      local deletion — it reports as its own outcome.
      `POST /api/git/cleanup-branch` is the operator door, adding no policy.
      _(state: smoke-tested — every refusal reproduced against real
      repositories: a bare origin, a clone, a linked worktree; the happy path
      proven by the local ref disappearing AND `ls-remote` showing the remote
      ref gone. The route's refusal/404/validation contracts verified
      non-vacuous against the pre-route host: all three failed there.)_

- [x] **The default-branch invariant is enforced, not stated.** **Shipped
      2026-08-15**, deliberately last, so the derived tripwire validates the
      finished surface rather than being revised around each new write path.
      The module-smoke invariant sweep widened from push-only to the full rule:
      every repo-targeted `git commit` must sit in a scope that creates a
      feature branch (`switch -c` / `checkout -b`) or refuses a default one by
      name; every `git push` is checked for literal default-branch targets and
      force flags; every `git merge` must carry `--ff-only` — the one merge
      that cannot author a commit. Floors fail closed: fewer than the known 3
      commit, 3 push and 1 merge sites means the walker lost its scope, not
      that the tree got cleaner. **The checker proves itself against a
      deliberately violating fixture before it is trusted on the real tree** —
      a fixture that pushes to `main --force`, merges bare, and commits with no
      branch discipline must produce all four violation classes, or the sweep
      throws. Three gates in this repo's history passed vacuously on their
      first attempt; this one carries its own refutation.
      _(state: smoke-tested — self-proof plus the clean sweep: 4 push, 3
      commit, 1 merge site, none reaching a default branch.)_

---

## Release 3.4 — The Delivery Loop Closes (closed 2026-08-15, archived from ROADMAP.md)

Moved out of the active roadmap on 2026-08-15 under the archive rule when the
release closed — six engineering milestones plus the live full-loop proof, all
in one day. Verbatim as it stood:

### Release 3.4 — The Delivery Loop Closes

**Status:** done — all six engineering milestones shipped and archived
2026-08-14 / 2026-08-15, and the live full-loop proof recorded 2026-08-15
(manual trigger, operator-verified):
[`evidence/verified/full-loop-proof-2026-08-15.md`](evidence/verified/full-loop-proof-2026-08-15.md).

**Goal:** the agent executes the full delivery loop end to end — sync, branch,
implement, test, commit, push, PR, CI, merge, sync, clean up, mark complete —
without the operator leaving the product to finish a step by hand.

**Prerequisites:** met. Release 3.1 closed the honesty gaps this depends on:
nothing queues into an empty room, every dispatch surface is gated, staleness is
computed rather than asserted, and no write path branches from a clone it has
not verified. This release adds the _actions_ those guards can currently only
refuse on.

The target workflow, the layer model, and the evidence per step live in
[`docs/product/delivery-loop.md`](docs/product/delivery-loop.md). Measured
2026-08-14 at eight of twelve steps built; **all twelve are built as of
2026-08-15**, each landing with the tripwire that keeps it honest. The loop is
a circle in code; what no one has yet done is drive one real item around it.

#### Product outcomes

- A roadmap item travels the whole loop with the operator approving each
  transition rather than performing it.
- Local `main` is returned to the remote tip by the product, not by hand.
- Completion is recorded through the same pull request as the work it describes.
- No branch is left behind on either side once an item is done.

#### Governing invariant

**Agents may commit freely to feature branches. They may never merge or push to
a default branch. Changes reach `main` only through a passing pull request.**
This is already how every write path behaves; this release encodes it as a gate
rather than a statement, and no milestone below relaxes it. `pull --ff-only` is
not an exception — fast-forward-only refuses outright when a merge would be
required, so it moves a pointer and cannot author a commit.

#### Engineering milestones

**All six engineering milestones shipped and are archived:** the default-branch
sync operation plus its step-10 route and operator control (2026-08-14 /
2026-08-15); both-direction ahead/behind with `diverged` named (2026-08-14); the
branch-PR separation, so approve-push opens the run's pull request through the
same refusal matrix as the roadmap repair (2026-08-15); completion travelling
through the pull request — committed on the feature branch, verified rather than
written by the gate (2026-08-15); branch cleanup that requires the merged PR's
head SHA and refuses `tip-advanced`, `checked-out`, `default-branch` and
`no-merge-evidence` by name (2026-08-15); and the default-branch invariant as a
derived tripwire that proves itself against a violating fixture before sweeping
the real tree (2026-08-15). Full text and evidence:
[the archive](docs/history/completed-releases.md#closed-2026-08-15-archived-from-roadmapmd).

- [x] **Drive one real roadmap item around the full circle** — **done
      2026-08-15, manual trigger.** Run `20260815-060711-b3853924` (Lane 0.7's
      external-archive documentation item): sync `current`, branch, implement,
      verify passed, completion committed on the branch by
      `Add-RoadmapCompletionCommit`, **PR #142 opened by approve-push**, CI
      green, merged `CLEAN`, **sync route fast-forwarded `main` from behind**,
      **cleanup route deleted both branches at the merged head** `312ec823`,
      and the item reads `[x]` on `main` through the merge. Each step's
      artifact:
      [`evidence/verified/full-loop-proof-2026-08-15.md`](evidence/verified/full-loop-proof-2026-08-15.md),
      including run 1 (PR #140), whose overeager nested agent proved the
      on-default-branch completion guard live, and the two same-day fixes the
      drive produced (PR #141; the stale-queue triage).
      _(state: operator-verified — manual trigger. The scheduled-trigger half
      belongs to Release 3.1's proof item and stays open there.)_


**Automated conflict resolution is deliberately deferred** — the manual loop has
to run smoothly first; constraints and the engine decision are in the same doc.

#### Acceptance criteria

- A roadmap item travels all twelve steps with the operator **approving** each
  transition, never **performing** it.
- Sync classifies `current`, `behind`, `ahead` and `diverged`; **only `behind`
  fast-forwards**, `ahead` refuses as `default-branch-ahead`, every refusal names
  its remedy, and a smoke assertion proves the **refusals**, not the happy path.
- Roadmap completion appears in the feature branch's commit; no path writes a
  completion edit to a default branch.
- No command in `backend/` or `scripts/` can commit onto or push to a default
  branch. The assertion derives its scope from the commands themselves and fails
  closed when it finds fewer sites than exist.
- Branch deletion refuses a tip advanced past the merged head, and a branch
  checked out in another worktree. A completed item leaves no branch behind.
- Every state above is **reproduced in a fixture**, not asserted from a
  description.

---

## Release 3.1 — Closed-Loop Delivery (closed 2026-08-15, archived from ROADMAP.md)

Closed under the external-resource rule: every engineering milestone shipped,
the manual full-loop proof is operator-verified
(`evidence/verified/full-loop-proof-2026-08-15.md`), and the remaining live
proofs (empty-room gate, engine attribution, the scheduled-trigger loop half)
are re-homed to Release 2.9's authenticated operator session. The
`.gitattributes` and writer-coverage non-blockers re-homed to Lane 0.8;
queue idempotency and the override durable record are carried in Release 3.5's
known issues. Verbatim as it stood:

### Release 3.1 — Closed-Loop Delivery

**Status:** validation — engineering complete; moved out of `active` 2026-08-15
when Release 3.5 was promoted. The manual full-loop proof is
operator-verified ([evidence](evidence/verified/full-loop-proof-2026-08-15.md));
what remains is the scheduled-trigger half, batched with 2.9's operator
session. Originally promoted 2026-08-11, displacing 3.2. 3 of 8 milestones
shipped 2026-08-10 and are archived (the work-item trace, the completion-edit
generator, and the merge-evidence gate). Two more — the empty-room gate and
engine attribution — are engineering-complete and smoke-tested as of
2026-08-13, and stay `[ ]` here because their live proof is outstanding, per the
checkbox rule.

**Widened again 2026-08-14** with the stale-clone guard, deliberately and for
the second time. The test applied: this release's goal names explicit operator
gates at **apply**, dispatch, and merge, and the apply gate turned out to have
no staleness precondition at all. Shipping "the loop closes end to end" while
its first write path can generate a proposal from a months-old copy would make
this release's own completion claim false, so it belongs here rather than in a
later release. The cost is honest — 3.1 now carries three open engineering
milestones instead of two, and closes later. The release was first widened on
promotion day by the priority reset
in section "Current Status": closing the loop is not enough if the operator
cannot tell that it closed, which engine acted, or what it cost.

**Goal:** close the north-star loop end to end, repeatedly, with explicit
operator gates at apply, dispatch, and merge — and make each step legible while
it happens. Today the console can rank work, prepare a prompt and read merge
readiness, but no single work item has travelled the whole chain, and the
surfaces that start the chain do not say whether they can finish it.

**Prerequisites:** met for all engineering. Only the operator-session proof
waits on a human. Every input the widened milestones need is already computed —
runner presence (`Get-RunnerPresence`), provider identity (`providerId` on the
AI preview), and the agent-run metric fields. The gap is data computed and then
not used, or used on only one of two surfaces.

#### Product outcomes

- One roadmap item is carried from "ranked highest value" to "merged, with the
  managed repo's roadmap updated" without a human stitching the steps.
- No enabled control leads to a dead end: if a workflow cannot complete, the
  operator learns that _before_ investing review effort, not after.
- An operator can always tell a deterministic rule from a model's proposal, and
  no cost figure in this product is a number a human typed.

#### Engineering milestones

**Three shipped 2026-08-10 and are archived:** the per-work-item trace
(`GET /api/trace/{id}`, joining all seven stages from any id the chain minted),
the completion-edit generator behind `POST /api/roadmap/write-back/preview`, and
the merge-evidence gate that refuses nine shapes which are not completion. Full
text and evidence:
[the archive](docs/history/completed-releases.md#closed-2026-08-11-archived-from-roadmapmd).

- [ ] **Nothing may be queued into an empty room.** The route now refuses with
      409 `runner-absent` **before** any write, naming the unmet precondition and
      the remedy command, and carrying `strandedCount` so "no runner" reads
      differently at 0 queued than at 6. `acknowledgeNoRunner` keeps a deliberate
      queue-then-start-a-runner possible — the capability is explained, not
      removed. The approve controls in the dispatch wizard and the packaged-item
      queue disable on absent presence with the precondition rendered above them,
      and the queue header shows a stranded badge. The six stranded entries were
      triaged and cancelled, recorded in
      [`evidence/verified/stranded-dispatch-triage-2026-08-11.md`](evidence/verified/stranded-dispatch-triage-2026-08-11.md).
      **Coverage completed 2026-08-13.** The first pass gated two surfaces and
      missed two, including the one this release is named after — the guided
      wizard's "Approve and create PR task". A tripwire now derives its scope
      from the call sites: every component invoking `executeRoadmapDispatch`
      must consult `resolveDispatchGate`, so a fifth surface cannot be added
      ungated. All three call sites pass.
      _(state: smoke-tested — module smoke asserts, through the AST and scoped to
      this route, that the refusal precedes the queue write and reports
      `strandedCount`; verified non-vacuous against the pre-gate host, and the
      coverage tripwire verified non-vacuous by failing on the two ungated
      surfaces before they were fixed. Needs `operator-verified` against the
      live portal, batched with 2.9's session.)_
- [ ] **Every surface names its engine.** The guided-improvement preview now
      carries an `engine` block — `kind: deterministic-rules`, the rule sources,
      what it applies to, and `handoffEngine` naming what acts _after_ approval —
      and the modal renders it above the findings, with the prompt section
      stating that Copilot is the first model to see any of it. `providerId` and
      `modelId` are null for rule engines and populated for model ones, so a
      consumer branches on the payload rather than on which screen it is.
      _(state: smoke-tested — asserted from the payload per the acceptance
      criterion, plus an AST check that the preview reaches no provider, so the
      label cannot quietly become false. Remaining: the same treatment for
      surfaces beyond this wizard and the Operations workspace, which the
      "enabled means available" audit below should enumerate rather than this
      milestone guessing at.)_
- [x] **Token and cost are measured, not declared.** **Shipped 2026-08-14.**
      `tokenUsage` and `apiSpendUsd` existed on the agent-run record, flowed
      through `tokens_reported` in `app.db` and out to analytics — and were
      **never written by production code**. The Anthropic and OpenAI adapters in
      [`AiDocImprovement.ps1`](backend/modules/ai/AiDocImprovement.ps1) sent
      `max_tokens` and discarded the `usage` block the API returned; the only
      real value in the repo was a smoke fixture.

      Both adapters now read usage off the response into one normalized record.
      Every count is nullable, and `source` separates the three cases that look
      identical from outside: `provider-usage` (real counts), `absent` (the
      model answered and reported nothing — a defect), `call-failed` (the call
      errored), `not-applicable` (the offline heuristic called no model).
      `tokenUsage`/`apiSpendUsd` on the improvement-history record deliberately
      reuse the agent-run metric names so the two series join untranslated.

      **Cost is priced only from operator-supplied rates** under
      `ai.pricing.<modelId>`, and this repo ships none: published prices change,
      and a stale rate produces a confidently wrong number, which is worse than
      an honest blank. Unpriced, `costUsd` stays null, `costBasis` says
      `no-price-configured`, and the UI renders _unmeasured_ — never `$0.00`.
      _(state: smoke-tested — both adapters driven over a mocked response;
      a successful model call recording null usage fails the gate, and an
      AST check derives its scope from **which functions make an HTTP call**,
      so a third adapter is covered without editing the assertion. The client
      hop is asserted not to coerce any usage field with `?? 0`.)_
- [ ] **Staleness is a visible property of every repo, not a hidden one.**
      **Shipped 2026-08-14 for the free tier.** `isStale`, `localAhead` and
      `remoteAhead` were hardcoded `$false`/`0`/`0` in both GitHub scan paths and
      computed nowhere, while the dashboard had shipped a Stale column, a
      stale-only quick filter, a group-by-stale control and an ahead/behind badge
      bound to them for several releases. The column read "No" for all 80+
      repositories — not because they were current, but because nothing looked.
      The scan already collected both facts and threw the comparison away: the
      local side records `git log -1 --format=%cI`, the GitHub side records
      `pushed_at`, and they meet on the same object in
      `Add-GitHubMetadataToStatusResult`.
      [`Git.Staleness.ps1`](backend/modules/git/Git.Staleness.ps1) is that
      comparison, pure and unit-tested, classifying behind / ahead-or-unpushed /
      current / unknown with the basis named and the magnitude carried. The grid
      shows the drift and the remote push date beside the local commit date.
      _(state: smoke-tested — the matrix is asserted directly and a tripwire
      fails if any scan path reverts to a literal. `localAhead`/`remoteAhead`
      remain unwritten rather than zeroed: two dates cannot yield a commit count,
      and `exactCountsAvailable` says so in the payload.)_

      Remaining, and deliberately not free — both need data the scan does not
      collect today, so they are scoped separately rather than bundled into a
      comparison that cost nothing:

      - **Exact ahead/behind counts** need a real ref comparison. `git ls-remote`
        is the cheaper option (one round trip, no object download) against a
        fetch per repo; at 80+ repos either is a real charge on Release 3.2's
        300s cold-scan budget and should be measured before it is adopted.
      - **Last merged PR** needs a per-repo pulls query (`state=closed` filtered
        to merged); the scan currently fetches only open-PR counts.
      - **Most recently modified uncommitted file** needs working-tree stat calls
        per repo; the scan counts `git status --short` lines but never reads
        their timestamps.
- [x] **No write path may act on a stale clone.** **Shipped 2026-08-14.** Every
      write this product made to a managed repo branched from whatever the local
      working copy happened to be, and **`git fetch` appeared nowhere in
      `backend/` or `scripts/`**. The submit-PR path
      ([`Roadmap.PrSubmitter.ps1`](backend/modules/roadmap/Roadmap.PrSubmitter.ps1))
      evaluated nine refusals — not a git repo, dirty tree, no token,
      unrecognizable remote, byte-identical no-op, and five more — and staleness
      was not among them; the task runner
      ([`Invoke-RoadmapTaskRunner.ps1`](scripts/Invoke-RoadmapTaskRunner.ps1))
      branched the same way.

      [`Git.BaseFreshness.ps1`](backend/modules/git/Git.BaseFreshness.ps1) asks
      the remote directly with `git ls-remote` — one round trip, no object
      download, no working-tree mutation. Both write paths now refuse with a
      named `stale-base` category that says how far behind the clone is and what
      to run, and both accept a deliberate override (`acknowledgeStaleBase` on
      the route, `-AcknowledgeStaleBase` on the runner) exactly as
      `acknowledgeNoRunner` works for dispatch. The count is **exact when the
      objects are already local** and `null` when only a fetch could name it —
      never a guess, the same rule this release applies to unmeasured cost.

      **A clone that cannot be verified is not treated as stale.** No remote, no
      network, detached HEAD all read `unknown`, are reported, and are allowed
      through — the rule `Resolve-RunnerPresence` applies to an unreadable
      heartbeat, kept consistent so an offline operator is not locked out of
      their own repositories.

      **The damage is not the obvious one.** `git add -- $RoadmapPath` stages a
      single file, so unrelated upstream work cannot be reverted, and GitHub's
      three-way merge turns a genuinely conflicting roadmap edit into a visible
      `DIRTY` state. What nothing catches is that the **proposal itself was
      computed from stale content** — an improvement generated against an
      outdated document, re-adding what upstream already fixed or missing
      context added since. That merges cleanly and reads as correct in review.
      A silent wrong artifact on the primary write path costs more than the
      stranded queue did, because the stranded queue announced itself.

      **Measured 2026-08-14 across the 60 local clones under
      `F:\Development\20_Staging`:** 49 have upstream tracking branches and
      **11 report being behind** — 154, 60, 18, 17, 15, 8, 8, 5, 4, 3, 1
      commits. Every one of those counts is measured against a remote-tracking
      ref that is itself stale: those same clones last fetched 93, 195, 285, 93,
      26, 0, 63, 104, 53, 120 and 16 days ago, and one has never fetched. The
      true figures cannot be known without fetching and can only be larger.
      The detector the product already has is as stale as the thing it detects:
      [`Git.StatusDetail.ps1`](backend/modules/git/Git.StatusDetail.ps1) computes
      `unpulledCommits` from `git log HEAD..@{u}`, which reports **zero** on a
      clone whose upstream ref predates the divergence — exactly what a
      PromptPilot clone did while sitting 8 commits behind.
      _(state: smoke-tested — the defect is **reproduced**, not asserted from a
      description: the smoke builds a bare origin, clones it, moves the origin
      three commits, and proves `git log HEAD..@{u}` reports **0** on that clone
      while `ls-remote` reports behind — then fetches without merging and proves
      the exact count becomes 3. Coverage derives from the commands that branch
      or commit in a managed repo, as this entry asked: 4 base-deriving sites
      across 2 files, all gated, with 7 publish/working-tree sites reported as
      deliberately out of scope rather than silently skipped.)_
- [x] **Enabled means available.** **Shipped 2026-08-14.** The audit ran as a
      gate rather than as a written list, and the enumeration is the deliverable:
      **82 disabled controls across 22 PC components** — 30 disabled by an
      operation already in flight (the label and spinner already say why) and
      **52 by a precondition**, every one of which now names it.

      **The first pass undercounted by more than half, and that is the finding.**
      A lazy `<button.*?>` regex stops at the `>` inside `onClick={() => …}`,
      so every control whose first prop is an arrow handler read as ungated: it
      reported 30 disabled controls and scored `RepoGrid.tsx` as 31 ungated
      buttons when it holds 6 gated ones. Walking the tag with brace/quote depth
      instead found 18 unexplained controls where the regex had found 7, in
      files nobody had reported — pagination, curation state, the two dispatch
      overrides, the discard-changes control, and a permanently dead
      `disabled={true}` labelled only "Not Available".

      Lane 0.9's three instances closed here: Insights now offers the
      assessment run its own text tells the operator to perform (its analytics
      panel had a button named just `Retry` that re-fetched the trend, not the
      assessment the sentence beside it named); the bare `Failed to fetch`
      screen is replaced by a classified state that distinguishes an unreachable
      backend from an unconfigured portal and offers both a retry and Settings;
      the dispatch wizard closed under M1.
      _(state: smoke-tested — the classifier derives its scope from the markup,
      so a control added later is audited without anyone remembering to add it.
      It fails closed if it finds fewer than 20 controls, so a broken scanner
      cannot pass vacuously, and it reports every violation at once rather than
      the first.)_
- [ ] Record a full-loop proof for one real item in `evidence/`, naming each
      stage's artifact, **manually and once on a schedule**. _(state: the
      **manual half is operator-verified 2026-08-15** — PR #142, all twelve
      steps, recorded in
      [`evidence/verified/full-loop-proof-2026-08-15.md`](evidence/verified/full-loop-proof-2026-08-15.md).
      What remains is the scheduled trigger: a scheduled packaging run whose
      packet an operator approves through to the same recorded outcome.)_ The
      scheduled path deliberately stops at `pending-approval` (Release 2.7
      Phase C), so this

#### Acceptance criteria

- A single `runId` resolves to every stage artifact through one route.
- The approve control cannot be clicked when no runner can claim the result,
  and a smoke assertion proves the **disabled** state, not the happy path.
- Every surface displaying a generated document or finding names its engine,
  asserted from the payload rather than by inspection; a model call that
  records `null` usage fails a gate.
- No write path branches from a clone it has not verified is current, and the
  refusal names how far behind it is. A smoke assertion proves the **refusal**
  against a deliberately-stale fixture clone, not the current-clone happy path.
- The loop proof exists in `evidence/` with the PR, the Actions result, and
  the applied roadmap diff, for both the manual and the scheduled trigger.

#### Out of scope

- Automatic merge — merge stays an explicit operator action after readiness
  passes.
- Removing the human approval gate on scheduled work.
- Multi-repo parallel dispatch; one item end to end first.

**Validation plan:** `npm test` (`scripts/Invoke-TestSuite.ps1`, the same
17-gate list `ci-smoke.yml` invokes), exit 0. Each milestone lands its own gate:
a disabled-state assertion, an engine-attribution assertion over the payload, a
usage-not-null assertion on a stubbed provider call, and a recorded evidence
entry per trigger. The dispatch success-path assertion added 2026-08-11
([PR #119](https://github.com/xfaith4/GitHubRepoManagement/pull/119)) is the
pattern: a contract proven only by its refusals is not proven.

**Risks and blockers:**

- **Risk — disabling controls hides capability instead of explaining it.** A
  greyed button with no reason is worse than a failing one: the operator cannot
  tell broken from not-yet-applicable. Every disabled state carries its unmet
  precondition in text.
- **Risk — a measured token figure gets treated as a budget before it is
  trustworthy.** Report measured usage separately from the declared work units
  the quota guard enforces; do not wire the new figure into refusals here.
- **Risk — the end-to-end proof needs the same scarce operator session** 2.9
  waits on. Batch them or this milestone stalls alone.

**Dependencies:** `Get-RunnerPresence`
([`Automation.RunnerPresence.ps1`](backend/modules/automation/Automation.RunnerPresence.ps1)),
the AI provider adapters
([`AiDocImprovement.ps1`](backend/modules/ai/AiDocImprovement.ps1)), the
agent-run ledger ([`AgentRuns.ps1`](backend/modules/agent-runs/AgentRuns.ps1)),
and the work-item trace shipped earlier in this release.

**Known issues:**

- [ ] **[non-blocker]** **No `.gitattributes`, with `core.autocrlf=true`.**
      Whether a tracked file holds CRLF or LF in the working tree depends on
      which git operation last materialised it, so any byte-level comparison
      between two tracked copies is non-deterministic locally while passing in
      CI's fresh checkout. This surfaced 2026-08-13 when the standards/spec sync
      gate reported drift between two files with identical content (245 CRLF vs
      245 LF, same 16,280 characters). That gate now normalises before
      comparing, but it was the only one audited — the general fix is a
      `.gitattributes` declaring `text eol=lf`, and the risk until then is a
      gate that reports drift that is not there, or hides drift that is.
      _(state: planned — recorded 2026-08-13)_
- [ ] **[non-blocker]** The same item can still be queued twice while a runner
      _is_ present. The triage found the six stranded entries were **three items,
      each queued twice** — two pairs seconds apart (double-submit) and one three
      minutes apart (a retry after nothing appeared to happen). The presence gate
      removes the cause for the absent-runner case only; nothing makes dispatch
      idempotent. _(state: planned — recorded 2026-08-13 from
      [the triage](evidence/verified/stranded-dispatch-triage-2026-08-11.md);
      pairs with the "enabled means available" milestone, since both are about a
      control that gives no feedback that it worked.)_
- [ ] The scheduled and operator paths reach dispatch through different writers
      (`Automation.RoadmapPackaging.ps1` and the dispatch route). The
      queue-contract tripwire keeps their _shape_ identical; nothing yet keeps
      their _behaviour_ identical, and only one has an end-to-end test.
      **Narrowed 2026-08-13:** the divergence that mattered is closed. There
      were **three** roads to the queue, not two, and only one was gated:
      `POST /api/roadmap/dispatch/execute` wrote it directly and was gated;
      `POST /api/automation/packages/approve` reached it through
      `Submit-PackagedItemToRunner` and was not; `POST /api/roadmap-agent/start`
      reached it through `Start-RoadmapCopilotTask.ps1` →
      `Add-RoadmapTaskToQueue.ps1` and was not.
      The third is the instructive one: it never names the queue file, so a
      tripwire scoped to that filename could not see it — the first version of
      this check reported full coverage while a road stood open. The check now
      derives the writer scripts and then the routes that invoke them, so an
      indirect road counts as a road. `POST /api/roadmap-agent/preview` is
      exempt because it passes `-PreviewOnly` and returns before the write, and
      that ordering is itself asserted rather than trusted.

      The frontend check was rebuilt for the same reason, having failed the same
      way twice: scoped to `executeRoadmapDispatch` it passed while two surfaces
      sat ungated, and after those were fixed it still passed while
      `RoadmapViewerModal` queued through `startRoadmapTask` — a different client
      function, to a different route, to the same queue. It now derives its scope
      from the backend in two hops: routes that refuse on presence → the
      `apiClient` functions posting to them → every component calling one. Five
      surfaces, all gated. A container that forwards presence to the child
      rendering the control counts as gated; requiring a redundant
      `resolveDispatchGate` in `Dashboard` would add a call nothing reads.

      What remains of this issue is the original end-to-end coverage asymmetry,
      not a behavioural difference.
- [ ] **[non-blocker]** **A deliberate override leaves no durable record.**
      `acknowledgeNoRunner` lets an operator queue into an empty room on
      purpose, and `queuedWithoutRunner` reports it — but only in the HTTP
      response. Neither the queue entry nor the run summary records it, so the
      next person triaging a stranded pile cannot tell a deliberate override
      from a gate that failed. That is precisely the ambiguity the 2026-08-11
      triage had to reconstruct from timestamps. The queue entry shape is
      locked by the queue-contract tripwire, so the run summary is the right
      home for it. _(state: planned — recorded 2026-08-13)_

---

### Release 3.5 — Trustworthy Surfaces (milestone 4, closed 2026-08-15)

- [x] **Fix the four measured metric defects, each reproduced before it is
      fixed.** **Shipped 2026-08-15.**
      **(a)** `maturity_history` holds one row per repo PER CAPTURE, and the
      day-grouped `SUM` counted a thrice-captured ready repo three times —
      `Ready Repos … High 1592` on a 76-repo portfolio — while the sibling
      `AVG` weighted it threefold, merely hiding the same defect. Both queries
      (portfolio series and per-repo sparkline) now take each repo's latest
      capture per day, so no day's ready count can exceed the distinct-repo
      count — which is asserted directly against the store as the release's
      first cross-view invariant.
      **(b)** `Get-PortfolioTrendPayload` built its tiles from the passed-in
      assessments and replaced its series from `app.db`, so an index-only read
      rendered `0% / 0 Ready` above rows reading 20% and 22 in the same card.
      History-backed reads with no live assessments now take the tiles from
      the latest history day — the same source as the rows beneath them.
      **(c)** `_GetPortfolioAnalyticsAverage` returned `0` for an empty set
      and silently skipped nulls. It now returns `null` for "not computed"
      (rendered as an em dash, never `0%`), and `maturityAssessedCount` /
      `docsHealthAssessedCount` travel beside the averages so a partial sample
      says "of N assessed" instead of posing as the portfolio. The client
      mapper preserves null rather than laundering it with `?? 0`.
      **(d)** `settings.staleThreshold` was consumed nowhere in `backend/`
      while Release 3.1 redefined `isStale` as remote drift — two concepts
      sharing one word, one of them a dead control. **Retired**: wiring
      days into the 300-second drift tolerance would have blanked 3.1's
      staleness column, so the Settings input, the type field, the client
      defaults and every stale-threshold help text are gone, and the grid's
      stale-filter tooltip now states the drift definition.
      _(state: smoke-tested — a three-capture-day fixture in a real SQLite
      `app.db` proves ready<=distinct-repos (the pre-fix SQL returns 3 over 2
      repos against the same fixture, verified red), latest-capture averages,
      sparkline latest-not-average, null-for-empty, and history-backed tiles
      equal to their own rows; four frontend unit tests cover the em-dash,
      coverage-hint, and measured-zero renderings.)_

---

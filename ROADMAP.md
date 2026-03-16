# GitHub Repo Management — Product & Engineering Roadmap

> Status: Active
>
> Product direction: evolve from a general repo utility into a **roadmap-driven work queue and Copilot dispatch console** for multi-repo momentum.

## 1. Product Intent

GitHub Repo Management is being reshaped into a clean, operator-friendly tool that helps answer five questions across a portfolio of repositories:

1. Which repos have a usable roadmap?
2. Which repos have a clearly actionable next item?
3. Which repos are blocked by missing or weak documentation?
4. Which repos are currently safe to dispatch to GitHub Copilot?
5. How do we keep limited Copilot capacity continuously focused on the best next work?

The long-term goal is not generic repository browsing. The goal is a **portfolio execution console** that continuously surfaces the next best roadmap work, packages clean context, and launches or tracks Copilot tasks across repositories without duplicate effort or drift.

---

## 2. Product Principles

- **Roadmap-first workflow** — roadmap files are a primary source of truth for next work.
- **Explainable automation** — every dispatch decision should be inspectable and grounded in visible repo state.
- **Human review before irreversible action** — preview task packaging before launch; avoid silent magical behavior.
- **Portfolio visibility over repo trivia** — make missing roadmaps, completed roadmaps, pending work, and blocked repos obvious.
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

The next stage is to convert these foundations into a coherent work queue product.

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

## Release 0.7 — Two-Lane Execution Queue
**Goal:** keep up to two Copilot agents productively occupied across separate repos without collisions.

### Product outcomes

- The app behaves like a portfolio momentum console.
- Ready repos can be prioritized and dispatched without duplicate assignment.
- Active work across two Copilot lanes is visible at a glance.

### Engineering milestones

- [ ] Introduce persistent execution state ledger for repo assignments and task outcomes.
- [ ] Prevent duplicate dispatch of the same repo while a task is active.
- [ ] Prevent duplicate dispatch of the same roadmap item.
- [ ] Add explicit execution states: `idle`, `ready`, `running`, `blocked`, `complete`.
- [ ] Add two-lane execution board or lane panel to the dashboard.
- [ ] Rank ready repos by priority/readiness score to surface the best next candidates.
- [ ] Requeue repos automatically after refresh when more pending work remains.
- [ ] Add cancellation/failure handling and clear retry semantics.

### Acceptance criteria

- No repo can occupy both lanes simultaneously.
- Operators can see which two tasks are active and what remains next in queue.
- Completed or failed tasks are reflected back into repo readiness on refresh.

---

## Release 0.8 — Standardization, Guardrails, and Continuous Improvement

**Goal:** reduce ambiguity in roadmap-driven automation and make the system safer over time.

### Product outcomes

- Roadmap formatting becomes consistent enough to support reliable parsing across repos.
- Documentation quality and roadmap quality improve together.
- The product can gradually move from assisted workflow toward more autonomous but still reviewable execution.

### Engineering milestones

- [ ] Publish recommended `ROADMAP.md` structure standard for managed repos.
- [ ] Add roadmap linting or policy checks for section names, checkbox formatting, and parseability.
- [ ] Add README standardization preview workflow.
- [ ] Add proposed roadmap completion/update preview after successful task execution.
- [ ] Add saved operator filters/views for common triage patterns.
- [ ] Add notification hooks for scheduled scans and execution failures.
- [ ] Add policy-as-code checks for repository standards enforcement.

### Acceptance criteria

- The app can identify roadmap formatting drift before it breaks downstream automation.
- Standardization tasks can be previewed before modification.
- Repo management becomes progressively more deterministic over time.

---

## 6. Cross-Cutting Engineering Work

These items support all releases and should be advanced continuously:

- [ ] Strengthen API contract tests for all routes and error categories.
- [ ] Expand smoke coverage around launcher, health, roadmap parsing, and task history flows.
- [ ] Add incremental scan mode for large repo roots (skip unchanged directories where safe).
- [ ] Improve cache invalidation and scan performance for large local inventories.
- [ ] Cap or roll `operations.jsonl` with configurable retention.
- [ ] Keep structured logs rich enough to diagnose scan, parse, preview, and start failures.
- [ ] Continue improving operator-facing documentation as workflows evolve.

---

## 7. Risks and Design Guardrails

### Risks

- Roadmap markdown may be too inconsistent across repos for safe automation.
- README quality may be insufficient for meaningful Copilot context.
- Queue automation can create duplicate or low-value work if readiness is weak.
- Hidden background execution can obscure failures if logs and history are not clear.

### Guardrails

- Do not auto-dispatch tasks without a visible readiness model.
- Do not treat all roadmap files as equal; parse confidence matters.
- Do not silently mark roadmap items complete based only on code churn.
- Prefer preview-first workflows before write-back or autonomous mutation.
- Keep the product operator-readable; this is a control console, not a magic box.

---

## 8. Suggested Roadmap File Standard for Managed Repos

To support safe parsing across repos, the recommended roadmap format should converge toward:

```md
# ROADMAP

## Now
- [ ] Highest-priority actionable work item
- [ ] Another clearly scoped item

## Next
- [ ] Follow-on work that depends on Now or is lower priority

## Later
- [ ] Useful but non-immediate future work
```

Formatting guidance:

- Prefer checkbox items for actionable work.
- Keep each item concrete and implementation-testable.
- Avoid mixing completed history into future sections except where explicitly archived.
- Keep section names stable where possible.
- Avoid vague placeholders like `misc cleanup` or `improve app`.

---

## 9. Definition of Useful Product Progress

The product is moving in the right direction when:

- missing or weak roadmaps become obvious immediately
- next pending work is visible without opening files
- repos can be filtered by dispatch readiness
- Copilot tasks are launched from structured context, not wishful prompting
- two active Copilot lanes can stay busy on separate repos without confusion
- progress history remains preserved while future work becomes increasingly formal and deterministic

---

## 10. Immediate Next Focus

The recommended immediate execution target is:

### **Release 0.7 — Two-Lane Execution Queue**

Specifically:

- persistent execution state ledger for repo assignments and task outcomes
- duplicate dispatch prevention (same repo or same roadmap item)
- two-lane execution board in the dashboard showing active tasks and the ready queue
- priority ranking of ready repos to surface the best next candidate

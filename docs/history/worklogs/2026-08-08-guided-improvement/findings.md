# Guided Repository Improvement Workflow Findings

## 2026-08-08 roadmap-priority pass

- `HEAD` already contains the Lane 0.1 workspace-root correctness fix (`c7f75cd`), despite stale earlier wording in the active-release known-issues section.
- The next autonomous, high-impact item explicitly called out by the roadmap is Release 2.7 Phase D freeze prevention: preserve caching, bound per-request work, and maintain the growing SQLite store.
- The checkout has extensive unrelated modifications. All implementation and validation must be scoped to selected reliability files and existing edits must be preserved.
- The API host accepts and handles one TCP client at a time. Stream read/write timeouts do not bound route work, so a stuck synchronous/native call blocks `/health/live` and all later requests.
- The persistence bridge already uses SQLite WAL mode and a 5-second busy timeout. The larger gap is bounding the route as a whole.
- The service installer already configures Shawl `--restart` plus three SCM recovery restarts. A host deadline can therefore fail fast on a wedged request and recover without requiring a service architecture change.
- `Get-StatusCacheTtlSeconds` and `Get-PortfolioAssessmentCacheTtlSeconds` accepted zero, disabling the caches implicated in the prior pile-up. Positive-only overrides retain explicit `refresh=true` while preventing global cache-off regression.
- Live deployment is not currently present: Windows has no `RepoMgmtPortal` service, `127.0.0.1:7071` refuses connections, the current Windows identity is not Administrator, and `shawl` is unavailable. Production installation therefore requires an elevated Windows PowerShell session plus Shawl; isolated validation must not be described as live deployment.

## User intent

- Select one repository.
- Scan README and ROADMAP readiness.
- Create an improvement task only when findings require work.
- Preview the exact task/prompt before execution.
- Execute through an agent workflow that ends in a pull request for review.

## Initial observed UX gap

- Doc Readiness Queue exposes independent Audit, Lint, Standardize, Evaluate, Preview Task, Dispatch Release, and Roadmap actions.
- The task-packet preview only offers prompt copying; single-task local execution is hidden in the separate Roadmap modal and requires an operator-session runner.
- Release dispatch is a separate GitHub Copilot flow and is broader than a single documentation-improvement task.

## Current contract map

- `POST /api/docs-audit/scan` only accepts roots/depth and returns a portfolio-sized index; there is no explicit `repoName`/`repoPath` scoped contract in the frontend client.
- A doc audit entry already combines README structural findings with ROADMAP state and the next pending roadmap item.
- `POST /api/copilot-task/preview` builds a rich single-task packet, but its modal only reviews/copies the prompt.
- `POST /api/roadmap-agent/start` queues the next roadmap task for the operator-session Claude runner; it does not accept the reviewed task-packet prompt.
- `POST /api/roadmap/dispatch/execute` accepts an explicit reviewed prompt and dispatches it to GitHub Copilot, which is the existing execution path that promises a branch and PR.
- README standardization and AI doc-improvement APIs can preview/apply content directly, but direct apply is not the requested agent-plus-PR workflow.
- Roadmap repair has a PR-planning endpoint, but the current modal calls its dry-run default rather than creating a live PR.

## Emerging implementation boundary

- The guided workflow should scan one selected local repository, synthesize one improvement task from README/ROADMAP findings, show the exact prompt, and reuse the existing guarded Copilot dispatch endpoint for execution/PR rather than writing docs directly.
- The workflow must distinguish "no improvement needed" from "task ready" and must not dispatch until the operator explicitly approves the prompt.

## Reusable implementation seams

- `Invoke-DocAuditScan -LocalRoots <roots> -MaxDepth <n>` is the shared README/ROADMAP readiness scanner; a selected repository can be audited through this seam without refreshing all 73 repositories.
- `Build-CopilotTaskPacket` is roadmap-item oriented and refuses repositories without a pending roadmap. It cannot truthfully represent a docs-only improvement task for a missing/complete roadmap.
- `Start-GitHubCopilotTask.ps1` executes `gh agent-task create <prompt> --repo <owner/repo>`; the existing dispatch endpoint already supplies auth checks, quota enforcement, history, and agent-run monitoring.
- A dedicated improvement-task preview builder is needed so README/ROADMAP findings—not an unrelated pending product task—become the task objective and acceptance criteria.
- The desktop workflow can reuse the queue's existing `DocAuditEntry.repoPath` as the stable local selection input and the dispatch route's git-remote resolution for GitHub identity.

## Integration points

- `WorkQueueView` already owns the repository list and row actions; it is the correct place for both a top-level "Guided Improvement" entry point and a row-scoped launch action.
- `Dashboard` centralizes all workflow-modal state and already refreshes docs, roadmap, and execution metrics after related actions.
- The doc scanner exports a single-repository function, `Invoke-AuditRepoDocumentation`, so a new workflow module can avoid a portfolio scan while reusing the established readiness vocabulary.
- The guided modal can call the new scan/task-preview contract, allow prompt editing, then call the existing `executeRoadmapDispatch(repoName, prompt, { localPath })` client for the explicit execution gate.
- Responsive behavior should use a horizontal step summary on desktop and stacked step labels/content on smaller screens; the task prompt remains editable before dispatch.

## Implemented contract

- `POST /api/repository-improvement/preview` validates a selected Git repository root, scans only its README and ROADMAP, and returns normalized findings plus an optional task.
- Missing, malformed, complete, or structurally weak roadmaps are represented through the existing roadmap audit rules; unrelated LICENSE, CONTRIBUTING, and CHANGELOG findings are excluded from this focused workflow.
- A zero-finding result returns `needsImprovement=false` and no task, so execution is not offered.
- The UI sends the operator-reviewed prompt and local path to the existing `/api/roadmap/dispatch/execute` contract. That route tolerates a missing roadmap and retains quota, token, repository identity, history, and agent-run ledger safeguards.
- Dispatch starts the remote Copilot task; it does not merge the resulting PR.

# Guided Repository Improvement Workflow Findings

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

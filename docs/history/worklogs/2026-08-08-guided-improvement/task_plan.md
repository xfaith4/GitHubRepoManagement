# Guided Repository Improvement Workflow

## Goal

Create a repository-scoped guided workflow that lets an operator select one repo, scan its README and ROADMAP, review any improvement task, execute the approved work, and reach a pull-request review handoff without navigating several disconnected surfaces.

## Scope guardrails

- Reuse existing scan, preview, dispatch, runner, history, and PR contracts where they are truthful.
- Keep explicit operator approval before writes, agent execution, or PR publication.
- Do not replace the existing queue, roadmap, or dispatch screens; provide one coherent orchestration path over them.
- Preserve unrelated dirty-worktree changes.

## Phases

| Phase | Status | Outcome |
|---|---|---|
| 1. Contract and UX audit | completed | Mapped current repo selection, README/ROADMAP scan, task preview, execution, and PR capabilities and gaps. |
| 2. Workflow design | completed | Defined a four-step state machine with local retry and explicit execution approval. |
| 3. Backend/API implementation | completed | Added a read-only repo-scoped preview contract that reuses the scanner and roadmap auditor. |
| 4. Frontend implementation | completed | Added queue and row entry points plus the guided selection, scan, task-review, and PR-handoff modal. |
| 5. Verification and production bundle | completed | Passed focused PowerShell validation, typecheck, 15 unit tests, production build, and the API-host smoke suite. |

---

# 2026-08-08 Roadmap Priority Execution — Portal Freeze Prevention

## Goal

Implement the highest-impact autonomous roadmap item still open: prevent a blocked or slow backend operation from making the always-on portal unresponsive, with a deployment path that preserves the current Windows service and watchdog model.

## Scope guardrails

- Treat the shared dirty worktree as user-owned and preserve unrelated edits.
- Prefer a bounded, testable reliability slice over broad API-host restructuring.
- Keep the existing watchdog as recovery defense; add prevention inside the API host.
- Do not restart or reconfigure the production service without confirming the implementation and deployment prerequisites.

## Phases

| Phase | Status | Outcome |
|---|---|---|
| 1. Priority and failure-path audit | completed | Confirmed the serial request loop, positive cache defaults but disable-able overrides, bounded SQLite lock wait, and existing Shawl/SCM restart guarantees. |
| 2. Reliability design and deployment choice | completed | Chose a host deadline + intentional fail-fast recovery, backed by Shawl/SCM, instead of a high-risk concurrent rewrite of the route dispatcher. |
| 3. Implementation | completed | Added the request-deadline controller, positive cache-TTL enforcement, module-smoke tripwires, and operator documentation. |
| 4. Verification | completed | PowerShell parse, deadline lifecycle, module smoke, 20 Pester API contracts, and full isolated-port API-host smoke all passed. |
| 5. Deployment evaluation and handoff | completed | Confirmed no live service/listener exists and this Windows identity lacks elevation/Shawl; documented the elevated service-install path and post-deploy proof boundary. |

## Frontend direction

- Visual thesis: a calm, full-width operational stepper that turns scattered tools into one visible progression.
- Content plan: select repository, scan documents, review findings/task, choose execution path, monitor PR handoff.
- Interaction thesis: completed steps compact into summaries; the active step owns the primary action; failures remain local and retryable without losing earlier results.

## Errors encountered

| Error | Attempt | Resolution |
|---|---|---|
| Bash expanded PowerShell variables and produced an empty pipe element. | Focused preview-builder validation. | Re-ran the same command with literal single-quoted PowerShell source; validation passed. |
| Linux PowerShell could not resolve the supplied Windows `F:` workspace path. | First API-host smoke invocation. | Re-ran with the native `/mnt/f/Development/GitHubRepoManagement` path; the full smoke suite passed. |
| An ambiguous cache-TTL patch matched the roadmap cache instead of the portfolio-assessment cache. | First scoped implementation diff. | Reverted that hunk and applied the positive-only guard to the intended portfolio helper before validation. |
| `git diff --check` reports every CRLF line as trailing whitespace because these shared files already differ from HEAD by line endings. | Scoped diff hygiene check. | Used `--ignore-space-at-eol` semantic diffs and preserved the shared worktree's existing line endings rather than normalizing unrelated content. |

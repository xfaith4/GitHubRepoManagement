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

## Frontend direction

- Visual thesis: a calm, full-width operational stepper that turns scattered tools into one visible progression.
- Content plan: select repository, scan documents, review findings/task, choose execution path, monitor PR handoff.
- Interaction thesis: completed steps compact into summaries; the active step owns the primary action; failures remain local and retryable without losing earlier results.

## Errors encountered

| Error | Attempt | Resolution |
|---|---|---|
| Bash expanded PowerShell variables and produced an empty pipe element. | Focused preview-builder validation. | Re-ran the same command with literal single-quoted PowerShell source; validation passed. |
| Linux PowerShell could not resolve the supplied Windows `F:` workspace path. | First API-host smoke invocation. | Re-ran with the native `/mnt/f/Development/GitHubRepoManagement` path; the full smoke suite passed. |

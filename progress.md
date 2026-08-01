# Guided Repository Improvement Workflow Progress

## 2026-08-01

- Started the repository-grounded workflow implementation.
- Loaded the planning and frontend UI skills.
- Created persistent task, findings, and progress artifacts.
- Began Phase 1 by tracing the current Doc Readiness Queue, task preview, local runner, and GitHub Copilot release-dispatch paths.
- Mapped the current doc-audit, task-packet, local queue, AI-doc preview/apply, roadmap-repair PR, and Copilot dispatch contracts.
- Identified the missing seams: repository-scoped doc scan and a reviewed documentation-improvement prompt that can flow directly into the existing PR-producing dispatch route.
- Confirmed the existing remote executor is `gh agent-task create`, already wrapped by quota, token, history, and agent-run ledger handling.
- Confirmed the current task packet cannot cover docs-only improvement when ROADMAP is missing or complete, so the guided flow needs a dedicated improvement-task preview contract.
- Located the minimal UI integration in `WorkQueueView` and modal orchestration in `Dashboard`.
- Chose to reuse the existing guarded Copilot dispatch for execution/PR and add only a repository-scoped scan plus documentation-improvement task-preview contract.

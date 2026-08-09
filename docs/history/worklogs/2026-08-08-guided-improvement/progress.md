# Guided Repository Improvement Workflow Progress

## 2026-08-08 — roadmap priority execution

- Reconciled the active roadmap with current `HEAD`; Lane 0.1 is already fixed and merged at `c7f75cd`.
- Selected Release 2.7 Phase D portal freeze prevention as the highest-impact unblocked engineering item.
- Began tracing API-host caching, listener/request execution, native-call boundaries, and SQLite maintenance before choosing a deployment design.
- Added `backend/api-host/RequestDeadline.ps1`: every accepted request receives a bounded deadline; expiry appends a correlation-rich incident record and terminates the wedged host so Shawl/SCM can restart it.
- Wired the deadline into the API host with a 180-second default and a clamped `REPO_MGMT_REQUEST_TIMEOUT_SECONDS` override (30-3600 seconds).
- Prevented status and portfolio-assessment cache TTL overrides from disabling caching with zero/negative values.
- Added module-smoke coverage for deadline resolution and cache-on source tripwires.
- Passed PowerShell parsing, an arm/clear/stop lifecycle check, the full module smoke, 20/20 API contract tests, and the full API-host smoke on isolated port 7091 (including 22/22 route census).
- Updated the active roadmap and always-on-service/API-host documentation; the broader Phase D checkbox remains open only for scheduled SQLite VACUUM + snapshot retention.
- Deployment audit: no Windows `RepoMgmtPortal` service or port-7071 listener exists; current identity `THESHIRE\xfaith` is non-admin and Shawl is not installed. Live deployment was not attempted because the required elevation/runtime prerequisite is absent.
- Roadmap structural validation passed with 0 errors (2 pre-existing advisory warnings).

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
- Added `RepositoryImprovement.Workflow.ps1` and the repo-scoped preview API route.
- Added typed frontend API support and the four-step `RepositoryImprovementWorkflowModal`.
- Added a queue-level Guided Improvement action and a row-level Improve action.
- Verified the preview builder against this repository: it returned one roadmap finding and a generated prompt.
- Passed frontend typecheck, all 15 unit tests, and the production Vite build.
- Passed the full API-host smoke suite; its dispatch check exercised the quota refusal path and did not start a live task.
- Observed the shared branch advance to commit `6183483` containing the implementation while verification was running; preserved that shared state.

# GitHub Repo Management

Windows-first repository standardization and operations toolkit with a unified local API, PowerShell modules, and operational automation scripts.

## Current Features

- Local inventory scan of repository roots with git metadata.
- Local-vs-GitHub reconciliation with duplicate candidate detection.
- Documentation review pipeline:
  - Stage 1 inventory (`manifest + csv + report`)
  - Stage 2 queue planning
  - Stage 2 batch planning (target repo)
- React/Vite operator dashboard absorbed from `GitHubRepoManagerDashboard` and integrated in `frontend/`.
- Unified API host for operational routes.
- Structured logging, metrics snapshot endpoint, health/dependency checks.
- Artifact listing endpoint for generated outputs.
- Operational scripts for smoke tests, retention cleanup, and scheduled task templates.

See [Features](docs/reference/features.md) and [Contracts](docs/reference/contracts.md) for detailed definitions.

## API Surface

From `backend/api-host/Start-RepoManagementApiHost.ps1`:

- `GET /health/live`
- `GET /health/ready`
- `GET /health/dependencies`
- `GET /metrics`
- `GET /api/status`
- `POST /api/reconcile`
- `POST /api/docreview/run`
- `GET /api/report/artifacts`
- `GET /api/artifacts/:repoName`
- `GET /api/settings`
- `POST /api/settings`
- `POST /api/init` (accepted placeholder)
- `POST /api/update`
- `POST /api/sync`
- `POST /api/export`
- `GET /api/reports/:reportName`
- `POST /api/archive` (accepted placeholder)
- `POST /api/github/status`
- `GET /api/status/cache`
- `POST /api/status/cache/clear`
- `GET /api/roadmap/index`
- `GET /api/roadmap/content`
- `POST /api/roadmap/scan`
- `GET /api/roadmap/cache`
- `POST /api/roadmap/cache/clear`
- `GET /api/log/tail`
- `POST /api/roadmap-agent/preview`
- `POST /api/roadmap-agent/start`
- `GET /api/roadmap-agent/history`

## Requirements

- Windows
- PowerShell 7+
- `git` available in `PATH`
- Node.js 20+ and npm (for dashboard frontend)
- Optional: `gh` (GitHub CLI) for GitHub inventory

## Setup

```powershell
git clone <repo-url> G:\Development\GitHubRepoManagement
Set-Location G:\Development\GitHubRepoManagement
npm run install:frontend
```

## Configuration

Primary configuration is [settings.json](backend/config/settings.json).

Key sections:

- `inventory`: `localRoots`, `maxDepth`, `includeNonGitFolders`
- `reconcile`: `ownerType`, `gitHubOwner`, retry policy
- `docReview`: depth and generation toggles
- `retention`: cleanup retention days
- `secrets`: environment variable key for token (`GITHUB_TOKEN`) and optional fallback token

Generated dashboard reports are saved under [reports](reports).

UI location:

- `Settings` dialog -> `Workspace Path` sets local repo root.
- `Settings` dialog -> `GitHub User/Org (default)` is reused by the dashboard GitHub API view on load and refresh.
- `Settings` dialog -> `GitHub Token (fallback)` stores token fallback used only when `GITHUB_TOKEN` is not set.

Example secret setup:

```powershell
$env:GITHUB_TOKEN = '<token>'
```

GitHub auth precedence for dashboard scans:

- Token entered in the `GitHub API` dialog for the current browser session
- Environment variable `GITHUB_TOKEN`
- Saved `Settings` fallback token

If a default GitHub user/org is saved in Settings, the dashboard can refresh GitHub repository data without re-entering a token in the UI when one of the sources above is available.

## Frontend build note

Recent npm versions sometimes skip Rollup's platform-native optional package on Windows. The frontend `dev`, `build`, and `preview` scripts now detect that condition and install the matching `@rollup/rollup-*` package automatically before running Vite.

If your frontend dependencies are missing entirely, run:

```powershell
npm run install:frontend
```

## Run

### Normal use — single launcher, no visible terminals

```bat
start-silent.bat
```

Both the API host and the Vite frontend start as hidden background processes.
The browser opens automatically. All output is captured to
`backend/modules/output/logs/`. Runtime telemetry (startup, scan progress,
operation results) streams into the dashboard Operation Log panel via
`GET /api/log/tail`.

To stop:

```bat
stop.bat
```

### Debug / developer mode — visible terminals

```bat
start-live.bat
```

Opens the API host in a separate terminal window and runs the Vite dev server
in the current window. Hot-module reload is active. Use this when you need
to watch raw process output or interact with the PowerShell host directly.

PowerShell shorthand for both modes:

```powershell
.\Start-App.ps1              # silent (default)
.\Start-App.ps1 -Mode debug  # two visible terminals
.\Stop-App.ps1               # stop silent-mode processes
```

### Frontend mock mode (no backend required)

```bat
start.bat
```

### Log files (silent mode)

| File | Contents |
| ---- | -------- |
| `backend/modules/output/logs/backend.log` | API host stdout |
| `backend/modules/output/logs/backend-err.log` | API host stderr |
| `backend/modules/output/logs/frontend.log` | Vite dev server output |
| `backend/modules/output/logs/operations.jsonl` | Structured JSONL event log (polled by dashboard) |

### Dashboard Operation Log

The dashboard polls `GET /api/log/tail` every 2.5 s during active operations
and displays backend log events in the slide-out Operation Log panel. A
**Backend: Online / Offline** badge in the header reflects connectivity state
(polled via `GET /health/live` every 15 s).

Start API host directly:

```powershell
.\backend\api-host\Start-RepoManagementApiHost.ps1 -BindAddress '127.0.0.1' -Port 7071
```

Smoke validation:

```powershell
.\scripts\Invoke-ModuleSmokeTest.ps1
.\scripts\Invoke-AdapterSmokeTest.ps1
.\scripts\Invoke-ApiHostSmokeTest.ps1
.\scripts\Invoke-RegressionSmokeTest.ps1
```

Operations:

```powershell
.\scripts\Register-ScheduledTasks.Template.ps1 -WorkspaceRoot 'G:\Development\GitHubRepoManagement' -TaskPrefix 'RepoMgmt'
.\scripts\Invoke-RetentionCleanup.ps1 -WorkspaceRoot 'G:\Development\GitHubRepoManagement' -RetentionDays 30
.\scripts\Start-GitHubCopilotTask.ps1 -Repository 'owner/repo' -BaseBranch 'main' -Follow
.\scripts\Start-RoadmapCopilotTask.ps1 -Repository 'owner/repo' -BaseBranch 'main' -Follow
.\scripts\Start-RoadmapCopilotTask.ps1 -Repository 'owner/repo' -PreviewOnly
```

Copilot roadmap task helper:

- Uses `gh agent-task create` to start a roadmap-driven task in a target repo.
- Defaults the task description to continue roadmap progress (verify completed items, find next uncompleted task, implement safely).
- Requires one of these environment variables: `GitHub_Token` or `GITHUB_TOKEN`.

Roadmap auto-selection helper:

- Finds a roadmap file in the target repo (`ROADMAP.md` first, then common fallback paths).
- Selects the next unchecked `- [ ]` roadmap item with section-aware priority (`Active / Next`, then near/mid/long-term).
- Builds a structured Copilot task description and delegates task creation to `scripts/Start-GitHubCopilotTask.ps1`.
- Supports `-PreviewOnly` to print the selected roadmap task and generated prompt without creating a Copilot task.

Roadmap task history and logging:

- All roadmap task preview/start runs write JSON history under `output/roadmap-task-history/`.
- Global timeline: `output/roadmap-task-history/history.jsonl`.
- Per-run files: `output/roadmap-task-history/runs/<runId>.events.jsonl` and `<runId>.summary.json`.
- API routes for UI integration: `POST /api/roadmap-agent/preview`, `POST /api/roadmap-agent/start`, `GET /api/roadmap-agent/history`.

## Repository Layout

```text
backend/
  adapters/
  api-host/
  config/
  modules/
frontend/
scripts/
docs/
.github/
standards/
```

## Documentation

- [Docs Index](docs/index.md)
- [Architecture](docs/architecture/architecture.md)
- [ADRs](docs/architecture/adr.md)
- [Roadmap](docs/planning/roadmap.md)
- [Contracts](docs/reference/contracts.md)

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
- `POST /api/export` (accepted placeholder)
- `POST /api/archive` (accepted placeholder)
- `POST /api/github/status`

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
```

## Configuration

Primary configuration is [settings.json](backend/config/settings.json).

Key sections:

- `inventory`: `localRoots`, `maxDepth`, `includeNonGitFolders`
- `reconcile`: `ownerType`, `gitHubOwner`, retry policy
- `docReview`: depth and generation toggles
- `retention`: cleanup retention days
- `secrets`: environment variable key for token (`GITHUB_TOKEN`) and optional fallback token

UI location:

- `Settings` dialog -> `Workspace Path` sets local repo root.
- `Settings` dialog -> `GitHub Token (fallback)` stores token fallback used only when `GITHUB_TOKEN` is not set.

Example secret setup:

```powershell
$env:GITHUB_TOKEN = '<token>'
```

## Run

Start API host:

```powershell
.\backend\api-host\Start-RepoManagementApiHost.ps1 -BindAddress '127.0.0.1' -Port 7071
```

Start dashboard (frontend + API host):

```powershell
.\start-live.bat
```

Start dashboard frontend only (mock mode):

```powershell
.\start.bat
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
```

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


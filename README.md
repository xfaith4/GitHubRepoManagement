# GitHub Repo Management

A portfolio-level execution console for managing multiple GitHub repositories. Unifies repository discovery, documentation auditing, roadmap contract validation, and AI-assisted task dispatch into a single operator dashboard — running entirely on PowerShell + React with no external web framework.

---

## What It Does

Answers seven core questions across a portfolio of repositories:

1. Which repos have a roadmap?
2. Which roadmaps are contract-quality (machine-readable)?
3. Which repos have clearly actionable next work?
4. Which repos are blocked by weak documentation?
5. Which repos are safe for Copilot dispatch?
6. Which repos need roadmap repair or standardization?
7. How do we keep Copilot capacity focused on best-next work without duplicate effort?

---

## Features

### Repository Inventory

- Local repo discovery under configured root paths with real-time git status
- Branch, dirty state, commit frequency, last author and message per repo
- Open PR counts sourced from GitHub API
- Staleness detection, archive tracking, and batch git operations (pull, fetch, sync)

### Roadmap Contracts (L0–L4 Maturity Model)

- ROADMAP.md discovery and inline viewer across all repos
- Contract validation against a formal schema and 10 weighted audit rules (ROADMAP-001–010)
- Maturity scoring on a 0–100 point scale mapped to levels L0 (absent) through L4 (dispatch-ready)
- Lint scanning with 7 policy checks: format, checkbox syntax, required sections, vague items
- Repair preview — automated suggestions for normalizing roadmap structure, shown as inline diff before apply
- Completion preview — mark roadmap items done and see the resulting markdown before writing

### Documentation Standardization

- README.md validation against a machine-readable doc standards schema
- Three-tab preview workflow: Plan → Diff → History before any changes are written
- Auto-backup and apply with full standardization history

### Work Queue & Dispatch Readiness

- Unified work queue filtered by dispatch readiness: `ready` / `blocked` / `review`
- Readiness badges per repo showing documentation and roadmap health at a glance
- Saved filter presets (stored in localStorage) for operator workflows
- Maturity drift detection — track repos against baseline targets
- Acknowledged drift to silence alerts without losing audit trail

### Copilot Task Automation

- Preview AI-generated task prompts from any roadmap before launching
- Direct task dispatch to GitHub Copilot via `gh agent-task create`
- Task history with per-run audit trails, summaries, and event logs
- Duplicate task prevention (case-insensitive, whitespace-normalized)
- Section-aware task priority: Active/Next → near-term → mid-term → long-term → tech debt

### Notifications & Observability

- Webhook registration and dispatch for events: `scan.completed`, `repair.applied`, `execution.failed`, `drift.detected`
- Structured JSONL operation log streamed to a live log panel in the UI
- Prometheus-style metrics endpoint at `/metrics`
- Health/readiness probes at `/health/live` and `/health/ready`

---

## Requirements

| Dependency | Version | Notes |
| --- | --- | --- |
| PowerShell | 5.1+ or 7+ | Backend API host |
| Git | Any recent | Local repo scanning |
| GitHub CLI (`gh`) | Latest | Auth, PR counts, Copilot dispatch |
| Node.js | v18+ | Frontend dev server |
| npm | v9+ | Frontend dependencies |
| GitHub PAT | — | Set as `GITHUB_TOKEN` env var |

> **OS:** Windows 10/11 (primary). Linux/macOS are untested.

---

## Setup

### 1. Clone the repo

```powershell
git clone <repo-url>
cd GitHubRepoManagement
```

### 2. Configure

Create `backend/config/settings.json` (or edit the existing file):

```json
{
  "schemaVersion": "1",
  "inventory": {
    "localRoots": ["C:\\Development\\MyRepos"]
  },
  "reconcile": {
    "gitHubOwner": "your-github-org-or-username"
  },
  "secrets": {
    "gitHubTokenEnvVar": "GITHUB_TOKEN"
  },
  "retention": {
    "days": 30
  }
}
```

### 3. Set your GitHub token

```powershell
$env:GITHUB_TOKEN = "ghp_your_personal_access_token"
```

The token needs read access to your org repos. Copilot task dispatch additionally requires the `copilot` scope.

### 4. (Optional) Configure GitHub CLI path

If `gh` is installed but not on your PATH, set `GH_CLI_PATH` to the executable:

```powershell
$env:GH_CLI_PATH = "C:\Program Files\GitHub CLI\gh.exe"
```

Or add it permanently via Claude Code settings (`~/.claude/settings.json`):

```json
{
  "env": {
    "GH_CLI_PATH": "C:\\Program Files\\GitHub CLI\\gh.exe"
  }
}
```

---

## Launch

```powershell
.\Start-App.ps1
```

This will:

1. Install frontend dependencies (`npm install`) if needed
2. Start the PowerShell API host bound to `0.0.0.0:7071`
3. Serve the built app on the LAN at `http://<localhostIP>:7071/`
4. In `-Dev` mode, start the Vite frontend dev server on `http://<localhostIP>:7000/`
5. Open your browser automatically

### Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-Mode` | `silent` | `silent` = background windows, `debug` = visible terminals |
| `-ApiPort` | `7071` | Port for the PowerShell API host |
| `-FrontendPort` | `7000` | Port for the Vite dev server |
| `-ApiHost` | `0.0.0.0` | Bind address for the API host |
| `-AppHost` | `<localhostIP>` | Hostname or IP that browsers should use to reach the app |
| `-NoBrowser` | off | Pass to suppress automatic browser launch |

### Examples

```powershell
# Normal use
.\Start-App.ps1

# Visible terminal output for debugging
.\Start-App.ps1 -Mode debug

# Custom LAN host
.\Start-App.ps1 -AppHost <localhostIP>

# Custom ports and host
.\Start-App.ps1 -ApiPort 8080 -FrontendPort 5173 -AppHost <localhostIP>

# Headless (no browser)
.\Start-App.ps1 -NoBrowser
```

### Windows batch shortcuts

```batch
start.bat          # Silent mode
start-live.bat     # Debug mode (visible windows)
stop.bat           # Shutdown
```

### Stop

```powershell
.\Stop-App.ps1
```

---

## Architecture

```text
GitHubRepoManagement/
├── Start-App.ps1                    # Single-entry launcher
├── Stop-App.ps1                     # Graceful shutdown
├── frontend/                        # React 19 + Vite + Tailwind
│   └── src/
│       ├── components/              # Modals, panels, grid, action bar
│       └── services/apiClient.ts    # Fetch-based API client
├── backend/
│   ├── api-host/
│   │   └── Start-RepoManagementApiHost.ps1  # PowerShell HTTP server
│   ├── modules/
│   │   ├── common/                  # Logging, metrics, validation, retry, webhooks
│   │   ├── roadmap/                 # Parser, linter, repairer, maturity drift
│   │   ├── docaudit/                # Documentation scanning
│   │   ├── docstandardization/      # README standardization
│   │   ├── execution/               # Task ledger, duplicate detection
│   │   ├── reconcile/               # Local vs GitHub reconciliation
│   │   └── docreview/               # Doc review planning pipeline
│   └── config/
│       └── settings.json            # Runtime configuration (gitignored)
├── scripts/                         # Smoke tests, Copilot task scripts, cleanup
├── standards/roadmap/               # Contract schema, audit rules, maturity model
├── docs/                            # Architecture docs, ADRs, feature reference
└── output/                          # Generated reports and logs (gitignored)
```

**Backend:** PowerShell API host on raw `TcpListener` — no external web framework. All HTTP parsing, routing, and JSON handling is implemented in-house.

**Frontend:** React 19 + TypeScript, built with Vite. State via React hooks; no Redux or external state library.

**Caching:** In-memory TTL caches per resource type — status (120s), roadmap index (300s), doc audit (300s), roadmap audit (300s).

---

## API Surface

The API host exposes ~55 routes. Key groups:

| Group | Example Routes |
| --- | --- |
| Health | `GET /health/live`, `GET /health/ready`, `GET /metrics` |
| Repos | `GET /api/status`, `POST /api/sync`, `POST /api/update` |
| Roadmap | `GET /api/roadmap/index`, `POST /api/roadmap/lint/scan`, `POST /api/roadmap/repair/preview` |
| Docs | `GET /api/docs-audit`, `POST /api/readme/standardize/preview`, `POST /api/readme/standardize/apply` |
| Drift | `GET /api/roadmap/drift`, `POST /api/roadmap/drift/baseline`, `POST /api/roadmap/drift/acknowledge` |
| Copilot | `POST /api/roadmap-agent/preview`, `POST /api/roadmap-agent/start`, `GET /api/roadmap-agent/history` |
| Notifications | `GET /api/notifications/webhooks`, `POST /api/notifications/webhooks` |
| Logs | `GET /api/log/tail`, `GET /api/settings`, `POST /api/export` |

Full interactive API reference available in-app via the **API Docs** button.

---

## Smoke Tests

```powershell
# Test backend modules
.\scripts\Invoke-ModuleSmokeTest.ps1

# Test adapter contracts
.\scripts\Invoke-AdapterSmokeTest.ps1

# Test all API routes against a running host
.\scripts\Invoke-ApiHostSmokeTest.ps1

# Full regression suite
.\scripts\Invoke-RegressionSmokeTest.ps1
```

---

## Security Notes

- API host binds to `127.0.0.1` by default — not exposed on network interfaces
- Webhook URLs are validated against an allow-scheme list (prevents SSRF)
- HTTP request bodies capped at 10 MB
- Roadmap linter content truncated at 5,000 lines / 512 KB before processing
- All roadmap repair and README standardization changes are **preview-first** — nothing is written without an explicit apply step

---

## Known Limitations

- `Validate` and `Complete` modes in the doc review pipeline are scaffolded but not yet implemented (Phase 3B/3C)
- Clone and Archive buttons in the UI are present but marked as planned features
- Operations log (`operations.jsonl`) has no rolling/size cap — monitor disk usage in long-running environments
- GitHub PR aggregation returns counts only (no aging or review-state breakdown)

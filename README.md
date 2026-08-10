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
| Node.js | v18+ | Frontend dev server + the frontend gates in `npm test` |
| npm | v9+ | Frontend dependencies |
| GitHub PAT | — | Held in an env var; the app stores only that variable's **name** |

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

The app **never stores your token**. `settings.json` holds only the *name* of the
environment variable to read (`secrets.gitHubTokenEnvVar`); the host reads that
variable at runtime. Point it at any name you like, then set that variable:

```powershell
# The name configured above — use your own if you changed it.
$env:GITHUB_TOKEN = "github_pat_..."
```

Required fine-grained PAT permissions:

| Permission | Access | Needed for |
| --- | --- | --- |
| Metadata | Read | Repository listing and insights |
| Contents | Read and write | README generation, branch pushes |
| Pull requests | Read and write | PR creation and merge readiness |
| Actions | Read | Workflow run state |
| Checks | Read | Per-check merge detail (`gh pr checks`) |

Copilot task dispatch additionally requires a token with Copilot access.

> **Restart after changing it.** The host reads the variable at launch; a
> variable set afterwards is not picked up until restart. If you run the
> always-on service, the variable must be **Machine-scoped** — a LocalSystem
> service cannot see User-scoped variables. See
> [docs/always-on-service.md](docs/always-on-service.md).

Settings → *GitHub Token — Environment Variable Name* shows whether the name you
configured actually resolved in the host's process, and **Test connection**
validates the token against GitHub and reports its expiry.

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

## Run it

The portal runs two ways: as an **always-on Windows service** (production) or via
a **developer launcher** (frontend dev with Vite hot-reload). Both serve the same
app on the same port — run one at a time.

### Production — the always-on service (recommended)

Install (or repair/reconfigure) the `RepoMgmtPortal` service from an **elevated**
PowerShell. It starts at boot, unattended, restarts on crash, and serves the API
plus the built dashboard from a single process — no Node/Vite at runtime:

```powershell
.\scripts\Install-RepoManagementService.ps1                     # local, HTTP
.\scripts\Install-RepoManagementService.ps1 `
  -PfxPath .\backend\config\tls\portal.pfx -PfxPassword $pw      # LAN + HTTPS
```

Re-running detects the existing service and offers **Repair / Reconfigure /
Reinstall / Uninstall** (or pass `-Action Repair` non-interactively). Secrets
(API key, TLS password) are written to an ACL-locked `settings.json`, never the
service command line. Full guide: [`docs/always-on-service.md`](docs/always-on-service.md).

```powershell
Get-Service RepoMgmtPortal                                       # status
Restart-Service RepoMgmtPortal                                   # (elevated)
Invoke-RestMethod https://127.0.0.1:7071/health/live -SkipCertificateCheck
.\scripts\Install-RepoManagementService.ps1 -Action Uninstall    # remove
```

**Reliability:** `shawl` restarts the host if it exits; the installer also offers
a **freeze watchdog** ([`scripts/service/`](scripts/service/)) that restarts the
service if the host *hangs* (alive but unresponsive — which `shawl` alone can't
catch), plus an optional `-NightlyRestart`.

### Development — `Start-App.ps1` (Vite hot-reload)

For frontend work the launcher runs the Vite dev server so edits hot-reload.
**Stop the service first** (it owns the port), or use a dev port:

```powershell
Stop-Service RepoMgmtPortal          # elevated, if the service is running
.\Start-App.ps1 -Dev                 # API + Vite hot-reload, opens the browser
.\Start-App.ps1 -Dev -ApiPort 7072 -FrontendPort 7001   # alongside the service
.\Stop-App.ps1                       # stop the dev processes (not the service)
```

| Parameter | Default | Description |
| --- | --- | --- |
| `-Dev` | off | Run the Vite dev server (hot-reload) instead of the built bundle |
| `-Mode` | `silent` | `silent` = background, `debug` = visible terminals |
| `-ApiPort` | `7071` | API host port (use another to run alongside the service) |
| `-FrontendPort` | `7000` | Vite dev-server port |
| `-NoBrowser` | off | Suppress automatic browser launch |
| `-Force` | off | Start even if the service is running (skips the conflict guard) |

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

## Verification

One command runs the canonical gate list — the same list CI runs on every PR
(`ci-smoke.yml` invokes this script, so local and CI cannot drift apart):

```powershell
npm test          # Invoke-TestSuite.ps1: all 17 gates, ~10 min (live API-host smoke included)
npm run test:fast # same suite minus the API-host smoke, ~2 min
```

The 17 gates: module smoke (incl. source tripwires), adapter contracts,
frontend typecheck / ESLint / 168 unit+DOM tests (vitest + jsdom) / production
build, PowerShell lint (PSScriptAnalyzer with a per-rule ratchet baseline —
Error severity is a hard zero; warning counts may only shrink), live API-host
smoke, API contract (Pester), auth smoke, repository-structure audit, config
and spec integrity checks, and the roadmap structure linter.

Targeted runs when iterating on one layer:

```powershell
.\scripts\Invoke-ModuleSmokeTest.ps1     # backend modules + tripwires
.\scripts\Invoke-ApiHostSmokeTest.ps1    # boots a live host on a dedicated port
.\scripts\Invoke-LintGate.ps1            # PSSA ratchet (-UpdateBaseline after cleanup)
npm run lint                             # ESLint (flat config, --max-warnings ratchet)
```

`main` is branch-protected: the `smoke` check (the full suite on
`windows-latest`) is required, admins included — a PR merges only on green.

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

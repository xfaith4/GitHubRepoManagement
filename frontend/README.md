# Frontend Dashboard

React + Vite dashboard absorbed from the predecessor `GitHubRepoManagerDashboard` and adapted to this repository API host.

## Run (with backend API host)

From repo root:

```powershell
.\start-live.bat
```

## Run (frontend only, mock mode)

From repo root:

```powershell
.\start.bat
```

## Manual run

```powershell
Set-Location .\frontend
npm install
$env:VITE_USE_MOCK_API = 'false'
$env:VITE_API_PROXY_TARGET = 'http://localhost:7071'
npm run dev
```

## GitHub API auth

The dashboard GitHub inventory view uses this token precedence:

- Token entered in the `GitHub API` dialog for the current session
- Environment variable `GITHUB_TOKEN`
- Saved fallback token from the backend `Settings` dialog

If `Settings` already contains a default GitHub user/org, the dashboard can refresh GitHub data without typing a token into the modal when one of those token sources is available.

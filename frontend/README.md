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
npm install --include=optional
$env:VITE_USE_MOCK_API = 'false'
$env:VITE_API_PROXY_TARGET = 'http://localhost:7071'
npm run dev
```

## Rolldown native package recovery

Vite 8 bundles with Rolldown, whose platform-native binding is an optional npm
dependency (`@rolldown/binding-<platform>-<arch>`). npm intermittently drops
optional native packages on a cold install, which breaks `vite build`. `npm run
dev`, `npm run build`, and `npm run preview` therefore run
`scripts/ensure-rolldown-native.mjs` first: it reads the binding name and
version from Rolldown's own `package.json`, and installs the missing one with
`npm install --no-save` beside the hoisted `rolldown` package. When the binding
is already present it exits silently.
## GitHub API auth

The dashboard GitHub inventory view uses this token precedence:

- Token entered in the `GitHub API` dialog for the current session
- Environment variable `GITHUB_TOKEN`
- Saved fallback token from the backend `Settings` dialog

If `Settings` already contains a default GitHub user/org, the dashboard can refresh GitHub data without typing a token into the modal when one of those token sources is available.

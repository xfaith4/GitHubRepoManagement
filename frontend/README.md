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

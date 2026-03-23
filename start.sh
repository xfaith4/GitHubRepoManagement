#!/usr/bin/env bash
# GitHub Repo Management — cross-platform launcher (macOS / Linux)
# Starts the application in silent mode (no visible terminal windows).
# The browser opens automatically when both services are ready.
#
# Usage:
#   ./start.sh           — normal start (builds frontend if dist/ is missing)
#   ./start.sh --dev     — force Vite dev server (hot-reload)
#   ./start.sh --rebuild — force a fresh npm run build before starting
#   ./stop.sh            — stop a previously started silent-mode session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_INDEX="$SCRIPT_DIR/frontend/dist/index.html"

# Require PowerShell 7+
if ! command -v pwsh &>/dev/null; then
  echo "ERROR: PowerShell 7 (pwsh) is required but was not found on PATH."
  echo "Install from https://aka.ms/pscore6 and retry."
  exit 1
fi

# Build the argument list for Start-App.ps1
ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/Start-App.ps1" -Mode silent)

# Check flags
DEV_MODE=0
REBUILD_MODE=0
for arg in "$@"; do
  case "$arg" in
    --dev)     DEV_MODE=1 ;;
    --rebuild) REBUILD_MODE=1 ;;
  esac
done

if [ "$DEV_MODE" -eq 1 ]; then
  ARGS+=(-Dev)
elif [ "$REBUILD_MODE" -eq 1 ]; then
  ARGS+=(-Rebuild)
elif [ ! -f "$DIST_INDEX" ]; then
  # First launch or dist/ was cleaned — rebuild automatically
  ARGS+=(-Rebuild)
fi

exec pwsh "${ARGS[@]}"

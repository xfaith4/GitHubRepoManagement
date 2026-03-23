# GitHub Repo Management — container image
#
# Build:  docker build -t github-repo-mgmt .
# Run:    docker run -p 7071:7071 -v $(pwd)/output:/app/output github-repo-mgmt
#
# The frontend is compiled at image build time (npm run build).
# At runtime only pwsh is required — Node.js is not needed.

# ── Stage 1: build frontend ──────────────────────────────────────────────────
FROM node:20-alpine AS frontend-builder

WORKDIR /build/frontend

COPY frontend/package*.json ./
RUN npm ci --silent

COPY frontend/ ./
RUN npm run build

# ── Stage 2: runtime image ───────────────────────────────────────────────────
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

LABEL org.opencontainers.image.title="GitHub Repo Management" \
      org.opencontainers.image.description="Portfolio roadmap and repo health dashboard" \
      org.opencontainers.image.source="https://github.com/xfaith4/GitHubRepoManagement"

WORKDIR /app

# Copy application source
COPY backend/  ./backend/
COPY scripts/  ./scripts/

# Copy compiled frontend bundle from build stage
COPY --from=frontend-builder /build/frontend/dist ./frontend/dist

# Create runtime output directories
RUN mkdir -p \
    backend/modules/output/logs \
    backend/modules/output/runtime \
    output/roadmap-repair-history \
    output/repo-evaluations \
    output/smoke \
    backend/config

# Default config — operators can bind-mount settings.json over this
COPY backend/config/ ./backend/config/ 2>/dev/null || true

EXPOSE 7071

ENV POSH_GIT_ENABLED=0

# Health check — polls the liveness endpoint
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD pwsh -NoProfile -Command \
        "try { \$null = Invoke-RestMethod -Uri 'http://localhost:7071/health/live' -TimeoutSec 4; exit 0 } catch { exit 1 }"

ENTRYPOINT ["pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", \
            "-File", "/app/backend/api-host/Start-RepoManagementApiHost.ps1", \
            "-BindAddress", "0.0.0.0", \
            "-Port", "7071", \
            "-WorkspaceRoot", "/app"]

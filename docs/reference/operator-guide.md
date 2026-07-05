# Operator Guide

A task-oriented guide to running GitHub Repo Management. For the product
thesis see [`docs/product/portfolio-execution-console.md`](../product/portfolio-execution-console.md);
for the release plan see [`ROADMAP.md`](../../ROADMAP.md).

## North-star workflow

> scan portfolio → index repos → classify every repo → show lifecycle state →
> identify blockers → repair README/roadmap/structure → rank highest-value
> next work → refine Copilot prompt → dispatch → monitor agent run → validate
> Actions → evaluate merge readiness → update roadmap / report progress

## First run (guided setup)

On a fresh install (no `settings.json`), the app opens the **Setup Wizard**
(4 steps: prerequisites → local roots → GitHub auth → first scan). It writes a
valid `settings.json` and triggers the first scan. Preview it any time with
`?setup=1`. Backing routes: `GET /setup/status|prerequisites`, `POST /setup/config`.

## Running & sharing on a LAN

`./Start-App.ps1` (defaults to bind `0.0.0.0`). Before sharing with teammates,
enable API auth — see [`lan-mobile-setup.md`](lan-mobile-setup.md). Key points:

- The host **refuses a non-loopback bind without auth** unless you acknowledge
  the risk (`network.allowInsecureBind` / `REPO_MGMT_ALLOW_INSECURE_BIND`).
- `auth.requireApiKey` + `REPO_MGMT_API_KEY` gate all non-health `/api` routes
  (`X-Api-Key` or `Authorization: Bearer`).
- Optional: scoped CORS (`network.allowedOrigins`), rate limiting
  (`network.rateLimit`), TLS (`network.tls.pfxPath`).
- Add the site to an Android home screen — the web app manifest launches it
  standalone.

## Mobile

Below the `md` breakpoint the app shows a bottom tab bar, full-screen modal
sheets, a glanceable **Repo-Health** panel, and an always-visible
**agent-activity** indicator. Prompt refinement and roadmap dispatch use the
same preview-first + quota-guard flow as desktop.

## Agent integration (`/api/v1/agent/*`)

AI agents query readiness, claim work exclusively (second concurrent claim →
`409`), and report completion. Contract: [`agent-api.yaml`](agent-api.yaml).
Optional execution history: `roadmap-events.jsonl`
([standard](../../standards/roadmap/roadmap-events.md)).

## Analytics & distribution

- Trend: `GET /api/portfolio/trend` (history accrues over calendar time).
- Digest webhook: `POST /api/digest/send` (`totalRepos` / `byLevel` /
  `improvedThisWeek` / `topCandidates`).
- Badges: `GET /api/badges/portfolio.svg`, `GET /api/badges/{repo}.svg`.
- Cost/burn: `GET /api/analytics/cost` (derived-only).
- Cache freshness: `GET /api/cache/diagnostics`.
- Publishable roadmap spec: [`spec/roadmap-contract/`](../../spec/roadmap-contract/).
- CI roadmap audit: [`.github/actions/roadmap-audit-action/`](../../.github/actions/roadmap-audit-action/).

## Verify before commit

`npm run typecheck && npm test` (12-gate suite: module/adapter/API-host/contract/
auth/repo-structure/config/OpenAPI/spec-dir/action/roadmap-lint). Frontend UI:
`npm run smoke:frontend`.

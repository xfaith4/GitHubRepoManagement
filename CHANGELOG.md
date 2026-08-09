# Changelog

All notable changes to this project are documented here.

## 2026-08-09 — Frontend unit-test set completed: value tiers and the automation scope selector

### Changes

- **What it closes:** Release 2.7 Phase D's frontend unit-test milestone, which stood at 2 of 4 named units. The two uncovered ones — **value tiers** and the **automation scope selector** — were both logic embedded inside components, so they were untestable without mounting the component. Extracted rather than duplicated, so the tests cover the code that actually ships.
- **`frontend/lib/valueTier.ts`** (new) — `VALUE_TIER_CONFIG` moved out of `WorkQueueView.tsx`, plus `getValueTierPresentation` (degrades null/undefined/unknown to `unscored` instead of returning undefined), `getValueTierRank` / `VALUE_TIER_ORDER` (ranking that does not depend on object declaration order), and `formatValueScoreLabel` (keeps the tooltip's tier label from drifting from the chip's). `WorkQueueView.tsx` consumes all three.
- **`frontend/lib/curationScope.ts`** (new) — `getCurationBadgeConfig`, `getCurationRank`, and `matchesCurationFilters` moved out of `RepoGrid.tsx`, plus `isInAutomationScope`, which states the Release 2.7 scope contract in one place: favorites and portfolio candidates only. `RepoGrid.tsx` consumes them, and its three inline curation filter predicates collapse to one call.
- **`frontend/lib/valueTier.test.ts`, `frontend/lib/curationScope.test.ts`** (new) — the scope suite pins the contract the backend also enforces: `archived-ignore` is never in automation scope, an uncurated repo is not either, and an unrecognized curation state is excluded rather than admitted (scope opts in; it never opts out). `getCurationRank` is pinned to put uncurated ahead of archived, so a parked repo never outranks an untriaged one.

### Testing

- `npm run test:unit` — 79 passing across 6 files; `npm run typecheck` exit 0.
- Adversarially proven: widening `isInAutomationScope` to `state !== 'none'` fails the never-touch assertion at `curationScope.test.ts:72`.
- Not covered: component rendering — these are pure-logic units, consistent with the existing `needsAttention` / `viewMeta` suites. No renderer is configured in this project.

## 2026-08-09 — Request deadline gains a scan tier, so the freeze guard stops causing restart loops

### Changes

- **What it fixes:** the Phase D request deadline bounded *every* route at 180 seconds and terminates the host on expiry so Shawl/SCM recovery can replace a wedged process. But a cold full-portfolio assessment of the real 75-repo workspace legitimately exceeds 180 seconds, so `POST /api/automation/run` and its siblings tripped the guard — and recovery restarted the host straight back into the same scan. The guard was manufacturing the outage it exists to prevent. `REPO_MGMT_REQUEST_TIMEOUT_SECONDS=900` plus `-RequestTimeoutSec 900` were the standing workarounds (ROADMAP Lane 0.4).
- **Decision — an extended tier, not an exemption.** Exempting the scan routes would restore the unbounded wedge Phase D was built to stop; bounding the cold scan itself is Release 3.2 performance work, not a reliability fix. So the deadline classifies routes instead, and both tiers stay bounded.
- **`backend/api-host/RequestDeadline.ps1`** — new `Get-LongRunningScanRoutePattern` names the routes that reach `Get-OperationsReposPayload` / `Invoke-PortfolioAssessment` (`/api/portfolio/assessment`, `/api/operations/repos`, `/api/automation/run`, `/api/digest/*`, `/api/reconcile`, `/api/docreview/run`, `/api/badges/*`, `/api/v1/agent/*`); `Test-LongRunningScanRoute` normalizes the path the same way the dispatcher does before matching; `Get-EffectiveScanRequestTimeoutSeconds` clamps the extended tier to the same 30-3600 range and raises it to at least the default tier, so an extended tier can never be shorter than the tier it extends; `Get-RequestDeadlineSecondsForPath` selects between them. The watchdog now reads the timeout from the synchronized per-request state rather than the value captured at construction, so an incident record and its `FailFast` message report the tier that actually fired.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — new `-ScanRequestTimeoutSeconds` parameter (default 900) and `REPO_MGMT_SCAN_REQUEST_TIMEOUT_SECONDS` override; the dispatcher arms each request with the tier its path selects, and startup logs both tiers.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — dot-sources the host's own classifier so the client timeout and the server deadline cannot drift apart, and gains `-ScanRequestTimeoutSec` (default 900) applied to exactly the routes the host puts on the extended tier. Ordinary routes keep the tighter 180-second client timeout, so a real hang still surfaces fast.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — asserts the classification both ways, the trailing-slash form, the 900/180 selection, and both clamp behaviors.
- **Docs** — `backend/api-host/README.md` and `docs/always-on-service.md` document the two tiers and why the split exists.

### Testing

- Parser check clean on all three modified PowerShell files.
- Module smoke exit 0 — `scan routes get the extended (still bounded) deadline tier; ordinary routes do not`. Adversarially proven: with `Get-LongRunningScanRoutePattern` stubbed to `@()`, the scan-route assertion throws.
- API-host smoke exit 0 on port 7099 with **no `-RequestTimeoutSec` override and no `REPO_MGMT_REQUEST_TIMEOUT_SECONDS`** — the two workarounds this change removes.
- Not covered: the terminate path itself under the extended tier (it ends the process, so it stays out of the automated gate); the existing `Resolve-RequestDeadlineAction` state assertions cover the decision logic.

## 2026-08-07 — GitHub auth is env-var-name indirection only (no stored or transmitted tokens)

### Changes

- **What it fixes:** the host had three ways to obtain a GitHub token, two of which handled the secret directly — a literal token persisted to the **git-tracked** `backend/config/settings.json` under `secrets.githubToken`, and a token typed into the browser and POSTed per request. The `secrets.gitHubTokenEnvVar` indirection already existed but was never exposed in the UI and was bypassed by three call sites that hardcoded `$env:GITHUB_TOKEN`, so renaming the variable silently broke them. Separately, a LocalSystem service cannot read a User-scoped variable, and nothing reported that — an operator saw only unexplained anonymous rate limits.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — new `Get-GitHubTokenEnvVarName` and `Get-GitHubTokenResolution` resolve the token from the **named** variable first, then the `gh` CLI, returning the source and environment scope alongside the token. This drops the `secrets.githubToken` fallback, and removes the prior implementation's transient process-wide `SetEnvironmentVariable($name, $null)` — a race in a threaded HTTP host — that also put `gh` ahead of the env var, contradicting the documented order. `Get-ConfiguredGitHubToken` is now a thin wrapper and no longer takes `-RequestToken`. New `Remove-StoredGitHubTokenFromSettings` strips a surviving stored token at startup and warns to revoke it (it may exist in git history). Startup logs which variable resolved and from which scope. `PATCH /api/settings` rejects `githubToken` with `400`, validates `gitHubTokenEnvVar` against `^[A-Za-z_][A-Za-z0-9_]*$`, and rejects values that look like a token rather than a name. `POST /api/github/status` rejects a body token with `400` instead of silently ignoring it. Three hardcoded `$env:GITHUB_TOKEN` reads (agent-run branch push, roadmap dispatch, setup prerequisites) now go through the resolver.
- **`GET /api/auth/github/status`** — doubles as the resolve probe: reports `tokenEnvVar`, `tokenSource`, `tokenEnvScope`, `runningAsService`, and a `hint` naming the actual cause of a miss (User-scoped variable invisible to a service; variable set after launch). `?validate=1` spends one GitHub call to confirm the token is live and report its expiry.
- **`backend/modules/readme/Readme.Generator.ps1`** — hardening, same leak shape: `_ResolveApiKey` no longer reads a literal `readme.copilotApiKey` from the git-tracked config, so resolution starts at the `readme.copilotApiKeyEnvVar` name. Its GitHub-token fallback also reads the configured variable name instead of hardcoding `GITHUB_TOKEN`. The startup stripper is generalized to `Remove-StoredSecretsFromSettings` and clears both legacy slots (`secrets.githubToken`, `readme.copilotApiKey`), warning to revoke what it removed.
- **Frontend** — Settings replaces the token password field with a **variable name** input carrying the required PAT permissions and the Machine-scope warning, plus a live resolution panel and a **Test connection** button. Token inputs removed from the Data Source and Init modals; `AppSettings.githubToken` replaced by `gitHubTokenEnvVar`; new `GitHubAuthStatus` type and `getGitHubAuthStatus()` client.

- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new step *"GitHub auth — env-var-name indirection"* asserts the three refusals (stored token, body token, token pasted into the name field) return `400`, that `settings.json` never gains a `githubToken` key, and that the resolve probe returns `tokenEnvVar`/`tokenSource`/`tokenEnvScope`/`runningAsService`/`hint`.

### Testing

- Parser check clean on both modified PowerShell files; `npm run typecheck --prefix frontend` exit 0.
- Module smoke exit 0 (`-WorkspaceRoot F:\Development\GitHubRepoManagement`).
- API-host smoke exit 0 on port 7392; new summary fields `githubAuthProbeOk=True githubTokenSource=env`, step output `github auth ok: envVar=GITHUB_TOKEN source=env scope='User' service=False; stored/wire/pasted tokens all rejected 400`. `routeCensusMissing=0`.
- Not covered: the LocalSystem service path (`runningAsService=true` branch and the Machine-scope hint) — the smoke host runs interactively. Verify on the next service repair.

## 2026-07-12 — Installer fix: Reconfigure preserves HTTPS + secrets move to machine env vars (out of git)

### Changes

- **Root cause it fixes:** `-Action Reconfigure` (run to rebuild `dist` / re-register) re-entered the fresh-install path, which only enabled TLS when `-PfxPath` was passed *that run*. Omitting it **silently downgraded the portal from HTTPS to plain HTTP** (host logged `started on http://…`), so `https://<host>:7071` failed with "SSL connection could not be established." The same run wrote a freshly-generated `auth.apiKey` in cleartext into the **git-tracked** `backend/config/settings.json` — a secret one `git add` from being committed.
- **`scripts/Install-RepoManagementService.ps1`** — secrets now live in **machine environment variables** (`REPO_MGMT_API_KEY`, `REPO_MGMT_REQUIRE_API_KEY`, `REPO_MGMT_TLS_PFX`, `REPO_MGMT_TLS_PFX_PASSWORD`) which the host reads natively and which win over `settings.json` — the same pattern `GITHUB_TOKEN` already used. The tracked `settings.json` is left **secret-free** (any secret a prior installer parked there is stripped, and its ACL lock reset). New pure `Resolve-PortalSecretConfig` **carries forward** existing auth/TLS config (env first, then a legacy settings copy) so a reconfigure that omits `-PfxPath`/`-ApiKey` keeps HTTPS on and reuses the key instead of downgrading / regenerating. New pure `Remove-SettingsSecretKeys` strips the secret keys and prunes empty containers. `Repair` now migrates secrets out of `settings.json` too, and both `Repair` and the fresh-install probe/watchdog use the **effective** scheme (so an HTTPS host is probed over HTTPS). `Set-PortalSecretsInSettings` / `Lock-SettingsFile` removed.
- **`docs/always-on-service.md`** — documents env-var secret storage, the secret-free tracked `settings.json`, and reconfigure carry-forward.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — the installer section now covers `Resolve-PortalSecretConfig` (env/settings/param/generate carry-forward) and `Remove-SettingsSecretKeys` (git-safe strip + non-secret-sibling preservation).

### Testing

- Parser check clean; module smoke green — `service installer ok: 5 action cases, secrets carry-forward (env/settings/param/generate), settings-strip git-safe, drift flagged 4 missing`.
- Elevated paths (env-var write, service re-register/restart, `icacls` reset) can't run from a non-elevated shell — verified by logic review + the pure-function smoke. **Operator verify (elevated):** `-Action Reconfigure -PfxPath .\backend\config\tls\portal.pfx -PfxPassword '<pw>'` → `sc qc` shows no secrets, `settings.json` has no `auth.apiKey`, and `https://<host>:7071` serves; a later bare `-Action Reconfigure` keeps HTTPS.

## 2026-07-12 — Pivot dispatch from GitHub Copilot to local Claude Code (queue + operator runner)

### Changes

- **Root cause it fixes:** "Start Task" dispatched to GitHub Copilot cloud (`gh agent-task create`), which requires the repo to exist on GitHub. Local-only repos (e.g. `F:\Development\20_Staging\AdministatorTools`, no remote) previewed fine but failed to start ("Failed to fetch"). The product pivoted to Claude Code working the **local** repo, with a review gate before anything is pushed.
- **`scripts/Add-RoadmapTaskToQueue.ps1`** (new) — queue writer. Appends one append-only line to `output/roadmap-task-queue.jsonl` (`status='queued'`, local repo path, roadmap path, branch, full task prompt). Pure `New-RoadmapQueueEntry`/`Add-RoadmapQueueEntry` + `-LoadFunctionsOnly`.
- **`scripts/Invoke-RoadmapTaskRunner.ps1`** (new) — the operator-run local runner (runs **as you**, with your `claude` + auth; never the SYSTEM service). Watches the queue and per task: claim (`running`) → `git switch -c roadmap/<runId>` → launch `claude` in the target repo with the prompt → best-effort verify → commit changes on the branch → **`awaiting-review`** (never pushes). `-Once`, `-Headless`, `-PermissionMode`, `-DryRun`; pure decision helpers + `-LoadFunctionsOnly`.
- **`scripts/Start-RoadmapCopilotTask.ps1`** — new `-DispatchMode claude|copilot` (default `claude`). In `claude` mode it computes the local repo dir (`Split-Path -Parent $RoadmapPath`) and enqueues via the writer instead of calling the gh dispatcher, writing a `status='queued'` run summary. Copilot dispatch stays behind `-DispatchMode copilot`. The existing history store + `Get-RoadmapTaskHistory` + preview flow are unchanged.
- **`Start-RepoManagementApiHost.ps1`** — `POST /api/roadmap-agent/start` success message now reads "Task queued for the local Claude Code runner…".
- **`frontend/components/RoadmapViewerModal.tsx`** — reworded: "Roadmap Task (local Claude Code)", the button is now **Queue Task**, and the description explains the enqueue → runner → review flow. New `queued`/`running`/`awaiting-review` statuses render as non-errors (the `isTaskError` regex already excludes them).
- **Docs**: `docs/reference/local-task-runner.md` (the full flow + how to run the runner + review/push), operator-guide pointer, ROADMAP item.

### Testing

- Parser checks clean on all touched scripts; `npm run typecheck` exit 0.
- Module smoke green, incl. `claude dispatch ok: queue round-trip (2 entries), status transitions, commit-msg truncation, verify detection`.
- Orchestrator integration: `Start-RoadmapCopilotTask.ps1 -DispatchMode claude` against a fixture roadmap enqueued the pending task (queue `0 → 1`, run summary `status=queued` with branch + local repo path) — no gh call.
- Runner `-Once -DryRun` against a fixture queue found the queued task and logged the full plan (claim → branch → claude → verify → commit → awaiting-review), mutating nothing.
- End-to-end with real `claude` needs the operator's session/auth (I can't) — operator verify: Queue Task for `AdministatorTools` → run the runner → work lands on `roadmap/<runId>`, status → `awaiting-review`.

## 2026-07-12 — Smart portal-service installer: repair flow, secrets out of the ImagePath, dev/prod split

### Changes

- **`scripts/Install-RepoManagementService.ps1`** — reworked into a smart entry point. New `-Action` (`Auto`/`Install`/`Repair`/`Reconfigure`/`Reinstall`/`Uninstall`): `Auto` fresh-installs when the service is absent, else shows a menu (interactive) or `Repair` (non-interactive). **Repair** is non-destructive — validates the registered `ImagePath` paths, re-applies boot-start + SCM recovery, migrates secrets, restarts, and health-checks, with no teardown. **Secrets no longer go in the `ImagePath`:** the API key and TLS password are written to `settings.json` (`auth.apiKey` / `network.tls.pfxPassword`, which the host reads natively) and the file is ACL-locked (SYSTEM:R, Administrators:F, owner:M); `GITHUB_TOKEN` is set as a machine env var. Closes the `sc qc`-readable exposure. After install/repair the installer offers the **freeze watchdog** (decline with `-NoWatchdog`) and can register an optional `-NightlyRestart`. Pure logic (`Resolve-InstallAction`, `Set-PortalSecretsInSettings`, `Get-ImagePathDrift`) is factored and dot-sourceable via `-LoadFunctionsOnly`; the elevation gate moved from `#Requires -RunAsAdministrator` to a runtime check so the functions are testable non-elevated.
- **`scripts/Uninstall-RepoManagementService.ps1`** — also removes the watchdog + nightly-restart scheduled tasks (`-KeepWatchdog` to leave them).
- **`Start-App.ps1` / `Stop-App.ps1`** — re-scoped as **developer** tools (Vite hot-reload / debugging). `Start-App.ps1` gained a non-destructive service-conflict guard: it refuses to start when `RepoMgmtPortal` is running (they collide on the port) and prints the options (stop the service, use a dev `-ApiPort`, or `-Force`). It never touches the service.
- **Removed** `start.bat`, `start-silent.bat`, `start-live.bat`, `stop.bat` — those encoded the obsolete "run the portal via the launcher" model, replaced by the service.
- **`README.md`** — rewrote the run section: production = the service (installer), development = `Start-App.ps1 -Dev`; removed `.bat` references; HTTPS access URLs; a reliability note. **`docs/always-on-service.md`** — documents the smart actions, secrets-in-settings, and the watchdog. `ROADMAP.md` 2.7 Phase D updated.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new section covering the installer's pure logic: action resolution (5 cases), the settings-secrets writer (writes `auth.apiKey`/`tls.pfxPassword`, preserves `schemaVersion` + existing keys), and `ImagePath` drift detection.

### Testing

- Parser checks clean on all touched scripts.
- Module smoke green, incl. `service installer ok: 5 action cases, settings-secrets round-trip …, drift flagged N missing`.
- The elevated paths (service register/restart, `icacls`, scheduled tasks) can't be exercised from a non-elevated shell — verified by logic review + parser; the operator runs the elevated verify (fresh install, `-Action Repair`, `sc qc` shows no secrets, watchdog recovers a simulated freeze).

## 2026-07-12 — Fix: portal watchdog must probe HTTPS (the service serves TLS)

### Changes

- **`scripts/service/Watch-PortalHealth.ps1`** — the `RepoMgmtPortal` service runs with `REPO_MGMT_TLS_PFX` set, so the host wraps every accepted connection in an `SslStream` and serves **HTTPS** on 7071. The watchdog's default probe was `http://…`, which fails the TLS handshake against a *healthy* host — it would have marked a good service unhealthy and restarted it every N cycles (a false-positive restart loop). Default `-BaseUrl` is now `https://127.0.0.1:7071`, and `Test-PortalHealth` skips certificate validation for https (self-signed, loopback liveness probe): `-SkipCertificateCheck` on pwsh 6+, the `ServicePointManager` callback on Windows PowerShell 5.1. `Install-PortalWatchdog.ps1` default and the operator-guide health-check command were updated to https + cert-skip.

### Testing

- Verified against a real healthy TLS host (throwaway self-signed cert on port 7098): the fixed **https** probe returns `Healthy=True, 200`; the old **http** probe returns `Healthy=False` — proving the original default would have false-restarted a healthy service. Module smoke still green (6 decision cases + ledger/state round-trip).

## 2026-07-12 — Portal service health watchdog (freeze recovery) — Release 2.7 Phase D

### Changes

- **`scripts/service/Watch-PortalHealth.ps1`** (new) — external liveness watchdog for the always-on `RepoMgmtPortal` service. The `shawl`-wrapped pwsh host can freeze (process alive, port 7071 `Listen`, not responding — flat CPU, stuck `CloseWait`), and `shawl` only restarts on process **exit**, so a hung host is never recovered and squats the port (also blocking `Start-App.ps1`). The watchdog probes `GET /health/live` on a short timeout and, after N consecutive failures, force-kills the listener PID and runs `Restart-Service RepoMgmtPortal`. Structured for testability: `Resolve-WatchdogAction` is a pure decision function, consecutive-failure count persists in a state file across scheduled invocations, every decision is appended to an append-only `output/logs/service-watchdog.jsonl` ledger, and a restart fires the `execution.failed` webhook. `-DryRun` decides + logs without killing/restarting; `-LoadFunctionsOnly` exposes the functions to the smoke. PowerShell 5.1-compatible (try/catch around `Invoke-WebRequest`, not `-SkipHttpErrorCheck`).
- **`scripts/service/Install-PortalWatchdog.ps1`** (new) — elevated registrar that installs the watchdog as a SYSTEM Scheduled Task (`NT AUTHORITY\SYSTEM`, RunLevel Highest, every `-IntervalMinutes`, plus an `AtStartup` re-arm). Gated on an Administrator check; idempotent (`-Force`); `-Uninstall` removes it. This is the one part that needs elevation to install/verify.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new Release 2.7 Phase D section covering the watchdog decision logic (6 cases: healthy resets, failures accumulate, threshold triggers restart-then-reset) and the ledger/state round-trip on disk.
- **`ROADMAP.md`** — the 2.7 Phase D watchdog item lifted to `smoke-tested`; live install + freeze-and-recover remains for `operator-verified` (needs SYSTEM).

### Testing

- Parser checks clean for both new scripts and the modified smoke.
- Module smoke green end-to-end, incl. `watchdog ok: 6 decision cases, state round-trip, 2 append-only ledger records`.
- **Dry-run against the actual frozen host** (PID 5704 on 7071): three cycles detected the freeze (probe timeout → unhealthy) and escalated `x1 → x2 → x3`, logging `[DRYRUN] would force-kill port 7071 and Restart-Service RepoMgmtPortal` at the threshold; the append-only ledger recorded `probe-fail ×3 → restart-triggered`. Nothing killed or restarted (dry-run). State persisted across the separate invocations.

## 2026-07-11 — Daily evidence routine: driver, operator-verification log, and a non-vacuous route census

### Changes

- **`scripts/Invoke-DailyEvidence.ps1`** (new) — the daily evidence driver. One command that runs the full gate on a **dedicated port (7099, never 7071)** so it cannot kill the operator's running portal, then boots its own host, runs one real differential portfolio scan (which also accrues the time-gated Release 2.3 trend history), and captures the live signals the host already emits: the `scan-summary` (reused/reindexed/failed) and `scan-budget` TRACE lines parsed from a fresh per-run host log, `/api/persistence/status` (capability/enabled/tables/agentRunEventCount), and the three health probes. Writes a dated snapshot under `evidence/baseline/daily/<stamp>/` — `manifest.json` (git SHA, per-gate exit codes, scan metrics, verdict), `summary.md`, `verify-queue.md`, and `roadmap-state-index.json`. Restores `settings.json` **byte-exact** via `File.ReadAllText`/`WriteAllText` (only when changed) so the driver introduces no diff of its own, and tears the host down via the shutdown-signal-file contract. `-SkipGate` / `-SkipScan` / `-SkipApiHost` isolate phases.
- **`scripts/Add-OperatorVerification.ps1`** (new) — appends one record to the append-only `evidence/operator-verification-log.jsonl` (timestamp, surfaceId, release, surface text, evidence, verifiedBy, gitSha). The `SurfaceId` is a stable hash of `release || surface-text` shown in the driver's `verify-queue.md`; the script recomputes ROADMAP ids and **refuses an unknown id** so a typo can't log a verification against nothing. `-List` prints current `smoke-tested` surfaces. The driver reads this log to drop already-verified surfaces from tomorrow's queue.
- **ROADMAP state parser (in both scripts)** — accumulates a milestone's text across wrapped continuation lines (the `*(state: ...)*` marker usually sits on a later line than the `- [ ]`), skips fenced code blocks (so the section-3 vocabulary example is not counted), and attributes each surface to its `##`/`###` heading (a `####` subheading like "Engineering milestones" no longer overwrites the parent release). Current portfolio: 117 stated surfaces — 93 `smoke-tested`, 7 `ui-connected`, 6 `done`, 1 `scaffolded`, 10 `planned`.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new **route-census** step generalizing the reconcile-route regression (`d2cc6cc`/`bfb3724`), plus its summary-projection fields. **Key correction:** the naive check "status must not be 404" is *itself vacuous* on this host — unmatched GET paths fall through to the **SPA `index.html` fallback and return HTTP 200 `text/html`**, not 404. The census therefore asserts each critical API route returns **`application/json`** (the real discriminator: every live API route including `/metrics` and `/health` returns JSON, the fallback returns HTML). A silently-deleted route now trips the census instead of being shadowed by the catch-all.

### Testing

- **Parser checks** — clean for all three scripts (`[Parser]::ParseFile`).
- **ROADMAP parse** — 117 surfaces with correct release attribution (2.7/2.6/… not "Engineering milestones"); the verify queue leads with active/recent releases.
- **Live scan path** — driver booted a host on 7099, captured `mode=differential reused=68 reindexed=2 failed=0`, persistence `13 tables / 47 agent-run events`, health `200/200/200`; clean teardown (no lingering 7099 listener); `settings.json` **clean after run** (byte-exact restore proven — an earlier `Set-Content` restore had been accumulating trailing blank lines each run).
- **Ledger round-trip** — recording a 2.7 surface dropped the queue 93 → 92 and removed that id from `verify-queue.md`.
- **Adversarial census proof** — against a live host, all real API routes returned `application/json` and a simulated deleted route returned `text/html` and was caught; the census flags exactly the deleted route and passes the real ones (assertion is non-vacuous).

## 2026-07-05 — Release 2.3 Phase 5D-5F: curation UI, Refresh All, and proof that unchanged repos are reused

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — four changes. (1) New `POST /api/portfolio/assessment/refresh-all` route: the request is mapped onto the existing assessment handler with forced refresh semantics, so every repository is fully reindexed and every entry reports `scanDecisionReason=forced-refresh` — the explicit operator escape hatch from differential reuse. (2) `includeCuration=true` on `GET /api/portfolio/assessment` now does what the docs claimed: a new `Add-PortfolioCurationToAssessments` helper merges live curation state (plus a stable `repoId`) onto entries on both the cache-hit and fresh paths, so curation toggles are visible without a rescan. (3) New Phase 5F observability line — every assessment logs `[TRACE] portfolio.assessment scan-summary mode=<differential|full|forced-full|forced-refresh-all> reused=N reindexed=M failed=K durationMs=D`. (4) **Defect fix:** the curation index-mirror call passed `-CurationState [string]$writeResult.data.curationState` in argument mode, which PowerShell treats as a literal string with partial interpolation, not a cast — the persisted index could carry a mangled curation value; the cast is now parenthesized.
- **`backend/modules/portfolio/Portfolio.Assessment.ps1`** + host `Get-OperationsRepoId` — **defect fix (identity stability):** `repoId` previously preferred the scan fingerprint, which hashes volatile signals (head commit SHA, dirty counts, README/ROADMAP mtimes, PR counts), so any repo change re-keyed its identity and orphaned operator curation stored under the old id. Both derivations now prefer stable keys — normalized local path, then GitHub full name, then repo name — with the fingerprint as last resort. Existing curation entries keyed by fingerprint ids orphan once at upgrade (feature shipped yesterday; acceptable).
- **`backend/modules/portfolio/Portfolio.Assessment.ps1`** — **defect fix (empty localPath since Phase 3A):** the assessment builder read the repo directory from a `localPath` field, but status-scan repos expose it as `path` — so every real assessment entry and every persisted index row since 2026-05-12 carried an empty `localPath` (confirmed against the oldest scan artifact: 0 of 55 rows had one). Downstream, path-keyed joins silently degraded to name matching and repoIds derived as `gh:`/`repo:` keys instead of `path:`. The builder now accepts `localPath` first (fixtures, index conversions) and falls back to `path` (live status scans). Scan fingerprints are unchanged (they always read the path from the status repo directly), so this does not trigger a mass reindex; index rows self-heal on the next scan, and the curation-merge helper additionally derives `gh:owner/repo` from `htmlUrl` so GitHub-only entries key identically to index rows.
- **`frontend/components/RepoGrid.tsx`** — Phase 5D/5E surface: per-repo curation actions (★ Favorite / ◆ Candidate / ⊘ Ignore / Clear) in the row Details panel with pending/error states; curation badges in both the card list and desktop table; three new quick filters (Favorites, Candidates, Hide ignored — hide-ignored active by default); a collapsible badge legend explaining curation, index/change-state, and severity badges; a visible Scan Decision detail block (tap-friendly equivalent of the hover tooltip); a `Last scan: N reused · M reindexed · Xs` status line; priority-order default sort (favorites → candidates → recently changed → unchanged, archived-ignored last) with a chip to restore it after clicking a column sort; and a confirm-gated **Refresh All** button (inline two-step confirmation, no browser dialog) wired to the forced-refresh route.
- **`frontend/components/Dashboard.tsx`** — ordinary portfolio-assessment loads now request `scanMode=differential&includeCuration=true` so unchanged repos are served from the persisted index by default (Phase 5E startup behavior); `refresh=true` callers keep the full-signal rebuild. New `handleRefreshAllAssessment` / `handleSetRepoCuration` handlers with optimistic entry updates; curation fields merged into grid rows.
- **`frontend/services/apiClient.ts` / `frontend/types.ts`** — `refreshAllPortfolioAssessment()`, `scanMode`/`includeCuration` options on `getPortfolioAssessment`, shared `RepoCurationState` type, `repoId`/`curationState`/`curationUpdatedAt` on `PortfolioAssessmentEntry` and `RepoStatus`, and a shared assessment-result normalizer. Fixed the mock `OperationsRepoEntry` factory missing the required `curationState`.
- **`frontend/components/ApiDocsModal.tsx` / `HelpModal.tsx`** — documented the refresh-all route, the curation POST route (including repo-name/path fallback resolution and error codes), the new assessment entry fields, and added operator guidance for curation, change-aware scanning, the badge legend, and when to use Refresh All.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new Release 2.3 Phase 5 sections: repoId identity precedence (path > github > name > fingerprint), curation state vocabulary validation, and a temp-workspace persistence round-trip that re-reads from disk to model a process restart (write, reject-invalid, merge onto entries, clear).
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new Phase 5F steps: curation POST contract (invalid state → 400, favorite write → 200 with `updatedAt`, `/api/operations/repos` read-back); the core reuse proof — on a warm differential call, `reused+reindexed` must reconcile to `count`, every non-reused entry must carry a *detected-change* reason (`new-commit`/`metadata-changed` — a `cache-miss`/`cache-invalid` means the reuse machinery broke), and at least 90% of repos must be reused (GitHub Actions timestamps / `updatedAt` are fetched live per request, so a couple of repos legitimately drift between back-to-back calls; the smoke prints tolerated drift by name); refresh-all contract (`reused=0`, `reindexed>=1`, `forced-refresh` on all entries, curation surviving the forced refresh); and cleanup resetting curation to `none` so the smoke leaves no operator-visible state behind.

### Testing

- **`npm run build`** — passed. **`npx tsc --noEmit`** — only the pre-existing `OperationsWorkspaceView.tsx` / `RepoGitStatusModal.tsx` errors remain (untouched files).
- **PowerShell parser checks** — clean for the host, both portfolio modules, and both smoke scripts.
- **`pwsh -NoProfile -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end including the three new curation sections; rerun clean after the `localPath` fix.
- **`pwsh -NoProfile -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)" -Port 7099 -BaseUrl http://127.0.0.1:7099`** — exit 0 on an alternate port (the operator's own pre-change dev host holds 7071 and was left untouched). The first run failed exactly where it should: the refresh-all curation-survival assertion caught the fresh-assessment vs index repoId mismatch rooted in the empty-`localPath` defect. Final run passes with the curation round-trip actually exercised, and the smoke resets curation to `none` afterward. Live-workspace proof from the host log: `mode=differential reused=68 reindexed=0 failed=0` (~5s) versus `mode=forced-refresh-all reused=0 reindexed=68` (~71s).
- **`pwsh -NoProfile -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors after the roadmap status updates.

## 2026-07-05 — Fix: restore GET /api/status caching gutted by bfb3724 (browser ERR_CONNECTION_RESET storm)

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — restored the pre-`bfb3724` `GET /api/status` route body. The `bfb3724` "refactor" had silently reduced it to a bare full-scan handler, dropping the entire cache layer: `stale`/`refresh` query handling, `Get-StatusCacheKey`/`Get-StatusFromCache`/`Save-StatusCache`, cache metadata, GitHub metadata enrichment, and the `meta.workspacePath`/`meta.configuredGithubUser` fields the frontend consumes. All five helper functions had survived as dead code; only the route body was gutted. Consequence: every status call — including the frontend's two-per-page-load stale-while-revalidate pair — ran a ~45-second blocking scan on the single-threaded host, so any concurrent request (roadmap index, execution metrics, scan schedule) piled into the TCP backlog and surfaced in the browser as `ERR_CONNECTION_RESET`. This is the third confirmed silent regression from the 2026-07-03 commits, after the `d2cc6cc` standards/tools overwrites and the `bfb3724` reconcile-route deletion.

### Testing

- Parser check clean. After host restart: `GET /api/status?stale=true` returns 200 in **115 ms** from disk cache (was 45 s); `?refresh=true` full scan completes in 49.2 s and rewrites `status-cache.json`; subsequent warm call answers in **26 ms** from memory; `meta` again carries `statusCache` and `configuredGithubUser`; `GET /` serves the current bundle; `/api/roadmap/index`, `/api/execution/metrics`, `/api/scan/schedule` all 200.
- **Incident note (2026-07-05 ~00:23–00:25):** the operator's host instance froze hard after the uncached-scan pile-up — flat CPU, listener accepting but never responding, last handled route `execution.metrics` (its `start`-without-`done` log pattern is normal; the freeze evidence is total log silence plus flat CPU). Not reproduced after restart, including 15 rapid sequential metrics calls (11–54 ms each). If it recurs now that status caching is restored, suspect a blocked native call (SQLite bridge) under request pile-up — capture a thread dump before killing the process.



## 2026-07-04 — Release 2.5 Phase 1: Mobile responsive foundation

### Changes

- **`frontend/components/Dashboard.tsx`** — new fixed bottom tab bar below the md breakpoint mirroring all six desktop view tabs (Repos, Insights, Ops, Queue, Exec, Deps) with 56px touch targets, active-view indicator, ready-count badges, and safe-area inset padding; the desktop tab row is now `hidden md:flex`; the dashboard root reserves bottom padding on phones so the nav never covers content.
- **`frontend/components/RepoGrid.tsx`** — below md the repository table collapses into stacked touch-friendly cards: same grouping/selection/quick-filter model, per-card status/stale/changes-severity/build/PR/roadmap/readiness badges, branch + last-commit meta, 44px Pull / Fetch / Details actions, an overflow menu (Open, Doc review, Roadmap, Roadmap scan, Git status), and inline expandable detail blocks. The expanded-row detail grid was extracted into `renderRepoDetailBlocks` shared by the table and cards. Also fixed a union-narrowing type error on `dataSource.configuredGithubUser` present in the original table code and inherited by the card copy.
- **`frontend/App.tsx`** — header wraps on narrow screens (`min-h-16` instead of fixed height), the verbose data-source chip is hidden below lg, and the GitHub API button collapses to icon-only below sm.
- **`frontend/styles.css`** — new `mobile-sheet` utility: below 640px an element takes over the full viewport (fixed inset-0, 100dvh, no radius/margin), unlayered so it wins over Tailwind utilities; plus an html/body `overflow-x: hidden` guard below md so wide content can only scroll inside its own container.
- **Twelve content modals** (Help, RoadmapViewer, RoadmapRepair, RoadmapLint, RoadmapDispatch, RoadmapAudit, RepoGitStatus, ApiDocs, RepoEvaluation, CopilotTaskPreview, ReadmeGenerate, ReadmeStandardization) — panel now carries `mobile-sheet`, rendering as a full-screen sheet on phones. The five small form dialogs (Settings, Init, Artifacts, DataSource, DocReview) stay centered; their edge-to-edge overlays gained `p-4` breathing room.

### Testing

- **`npm run build`** — passed (fresh `dist/` bundle).
- **`npx tsc -p frontend/tsconfig.json --noEmit`** — zero errors in every touched file (`RepoGrid.tsx`, `Dashboard.tsx`, `App.tsx`, modal files). Two pre-existing errors remain out of scope: `OperationsWorkspaceView.tsx:1473` (possibly-undefined `selectionSource`) and `RepoGitStatusModal.tsx` `global.JSX.Element` namespace declarations — neither gates the vite build.
- **Narrow-viewport browser verification** — attempted via Chrome automation at 390×844 but blocked: the Claude-in-Chrome extension has no site permission for `127.0.0.1`, so navigation/screenshots were denied. Tracked as the remaining step before the Phase 1 milestones move past `scaffolded`.



## 2026-07-04 — Cleanup cycle: d2cc6cc tool repairs, doc-audit readiness-drift fix, reconcile route restoration

### Changes

- **`tools/Test-RoadmapContract.ps1`** — three defect classes fixed in the `d2cc6cc`-added maturity validator: (1) mandatory string/string[] parameters now carry `[AllowEmptyString()]` so blank roadmap lines no longer abort the run; (2) `New-Object`-created `List[object]` collections wrapped with `@()` crashed with "Argument types do not match" on pwsh 7.6.3 — replaced with `::new()` + `.ToArray()` at four sites; (3) rule evaluation assumed every audit rule carries a structured `condition` object (v2.0-only) — rules without one now fall back to `Test-KnownRuleFailure`, a switch mirroring `Roadmap.Auditor.ps1`'s hardcoded ROADMAP-001..010 evaluation, so the tool works against the restored v1.0 rule pack and agrees with the product auditor. The tool now runs end-to-end: this repo scores 60 → L2-Structured with 44 pending / 49 complete matching `/api/roadmap/scan`.
- **`tools/Invoke-RoadmapValidation.ps1`** — same List[object] `@()` crash in the combined-findings merge; the wrapper now runs both validators and writes the merged findings file (verified: 5 contract + 3 structure findings).
- **`standards/roadmap/roadmap-validation.config.example.json`** — restored from `8eac9e0`: the `d2cc6cc` version documented config keys for the deleted generic validator; the restored example matches the restored `Test-RoadmapStructure.ps1` key-for-key and loads cleanly via `-Config`.
- **Remaining `d2cc6cc` files audited, accepted as-is** — `roadmap-contract.schema.json` (self-consistent with the contract tool; zero schema findings), `ROADMAP_TEMPLATE.md` (canonical `## Release X.Y — Title` layout), `ROADMAP_MATURITY_MODEL.md` (documents the v1.0 `100 − sum(weights)` scoring), `roadmap-repair-prompt.md`, `standards/README.md`, `standards/MANIFEST.md` (its recommended first-run command now actually works).
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — two fixes. (1) `Invoke-RoadmapScan` now searches ROADMAP files at `-Depth ($MaxDepth + 1)`: roadmap files sit one level below the repo directory exactly like the `.git` folder the doc-audit scanner uses for repo discovery, so the old `$MaxDepth` search left repos at the deepest discovered level doc-audited with an invisible roadmap — one of two root causes of the Release 1.7.5 carry-forward drift (`dispatchReadiness=missing-roadmap` for repos the roadmap audit scored L4). (2) Restored the `POST /api/reconcile` route: commit `bfb3724` deleted it silently and undocumented; `Invoke-ReconcileAdapter` had survived, `ApiDocsModal` still documented the route, and the smoke step passed vacuously against the unmatched-route 404 envelope.
- **`backend/modules/docaudit/DocAudit.Scanner.ps1`** — convergence fallback for the second drift root cause (the shared roadmap cache records no root/depth coverage, so a cache hit built from different roots left uncovered repos defaulting to `missing`): when the supplied roadmap entries do not cover a discovered repo but a roadmap file exists on disk, the scanner classifies it directly — full parse via `Invoke-ParseRoadmapContent` when the parser module is loaded (host runtime), checkbox heuristic otherwise — instead of reporting `missing-roadmap`. Repos genuinely lacking a roadmap still report `missing-roadmap`.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — (1) the end-of-run summary projection now evaluates each entry independently, so a missing property degrades to a labelled `(unavailable: ...)` value instead of discarding the whole summary — the old all-or-nothing block died on `$reconcile.success` and printed "[WARN] Smoke summary projection skipped", which is exactly how the deleted reconcile route stayed hidden; the hardened projection named the culprit on its first run. (2) The reconcile step now throws on a 404 or a missing `success` envelope, so a silent route removal can never pass again.
- **`ROADMAP.md`** — the Release 1.7.5 carry-forward note now records the confirmed root causes and the fix (resolved 2026-07-04).

### Testing

- **`pwsh -NoProfile -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end.
- **`pwsh -NoProfile -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — `[PASS]` exit 0; summary projection fully resolved with no `(unavailable)` entries. `reconcileSuccess=False` is the adapter's GitHub-token-less result in the smoke environment, tolerated as before — the new assertions pin the route contract, not the adapter outcome.
- **`pwsh -NoProfile -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors (2 pre-existing advisory warnings); also verified the restored example config loads via `-Config`.
- **`pwsh -NoProfile -File tools/Test-RoadmapContract.ps1 -Path ./ROADMAP.md`** — exit 0, zero schema findings; **`tools/Invoke-RoadmapValidation.ps1`** — exit 0 at `-MinimumMaturity L2-Structured` with merged findings file written.
- **Doc-audit drift repro (targeted, 3 cases)** — a deep repo with a pending roadmap audited against empty roadmap entries now classifies `pending` via both the checkbox-heuristic and parser paths (parser path also surfaces the next pending item); a repo with no roadmap still reports `missing-roadmap`.
- **PowerShell parser checks** — clean for all five edited scripts/modules. `npm run build` not run: no frontend files changed this cycle.

## 2026-07-04 — Fix: restore roadmap validator and audit-rule pack broken by the d2cc6cc refactor; plan Release 2.5

### Changes

- **`tools/Test-RoadmapStructure.ps1`** — reverted to the repo-specific validator from `8eac9e0`. Commit `d2cc6cc` ("Refactor code structure for improved readability and maintainability", 2026-07-03) had replaced it with a generic template validator that (a) crashed with "Cannot bind argument to parameter 'Line'" on the first blank line (mandatory string parameter without `[AllowEmptyString()]`), and (b) validated a layout this repo does not use (`## Release X.Y` headings only, template sections like "Product Intent"), losing the documented repo-specific rules (Release 1.2 coverage, active-release pointer/detail match, state vocabulary, file-length drift). CI runs this script with `-FailOnError`, so the crash failed the smoke workflow on every push.
- **`standards/roadmap/roadmap-audit-rules.json`** — reverted to the v1.0 pack from `2fed134`. The same `d2cc6cc` commit shipped a v2.0 pack that broke maturity scoring: critical-rule weights were inflated to 160 of a 235-point denominator, and five added rules (ROADMAP-011..015) are never evaluated by `Roadmap.Auditor.ps1` (its evaluation switch handles 001-010 and treats unknown rules as passing), so their 20 points were dead weight. Net effect: every parseable pending roadmap scored at least ~77 → L3-Contract-Ready regardless of quality, which (a) made `Invoke-PlanRoadmapRepair` refuse all repairs with `rewrite-not-recommended` ("already at L3"), (b) flattened the L3+ Copilot-dispatch maturity gate, and (c) aborted the module smoke at the "plan repair for L1 informal roadmap" step — the failure previously suspected to be a stale smoke expectation. The v1.0 pack's weights sum to 100 (true deduction scoring); maturity thresholds are identical in both versions, and the v2.0-only `scoring` block was referenced nowhere in code.
- **`ROADMAP.md`** — added planned Release 2.5 (Mobile-Friendly Operator Experience: responsive foundation, glanceable health + agent activity, mobile prompt-refinement and roadmap-phase dispatch, home-screen install, LAN-access dependency on Release 2.2) and a dependency-driven "Execution Order and Dependencies" section under the Release Index (step-0 unblockers, parallel backend/frontend lanes, dependency map); added per-release Prerequisites lines; replaced the Release 2.1 known-issues note with the confirmed root cause and marked both step-0 unblockers done.
- **`progress.md`** — new dated entry for the diagnosis and restoration.

### Testing

- **`pwsh -NoProfile -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 2 advisory warnings (file length; completed Release 2.1 detail still in the active roadmap), all 6 releases detected including 2.5. The broken validator was confirmed to fail identically against the unmodified HEAD roadmap before the revert.
- **Standalone repairer repro** (parser → auditor → repairer on the smoke's L1 informal fixture) — before: score 78 → L3-Contract-Ready → `rewrite-not-recommended`, 0 actions; after: score 45 → L2-Structured → `repair-preview-ready`, 6 actions (matches pre-`d2cc6cc` behavior).
- **`pwsh -NoProfile -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end for the first time since `d2cc6cc`, through all repairer steps and the Release 2.1 Phase 1/3 persistence sections.
- **`pwsh -NoProfile -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — `[PASS]` end to end (exit 0); `/api/roadmap/standard` now reports `ruleCount=10` with the canonical five maturity levels. (First attempt hit a transient connection reset at the roadmap-content step after the harness terminated a stale pwsh holding port 7071; the rerun against a cleanly started host passed in full.)
- **Residual risk note** — `d2cc6cc` touched 11 standards/tools files in total; only the two with confirmed regressions were reverted. The other nine (including `roadmap-contract.schema.json`, `ROADMAP_TEMPLATE.md`, `ROADMAP_MATURITY_MODEL.md`, and the new `Test-RoadmapContract.ps1` / `Invoke-RoadmapValidation.ps1`) pass both smoke suites but have not been individually audited against their pre-refactor behavior.

## 2026-07-04 — Release 2.1 Phase 3: Agent-Run Metrics and Quota-Burn Persistence

### Changes

- **`backend/modules/persistence/Persistence.Store.ps1`** — schema v2: new `quota_burn_snapshots` table (one row per dispatch quota evaluation) with a repo/time index; migration row recorded alongside v1 and DDL stays idempotent. New Phase 3 stores: `Write-AppDbAgentRun` upserts (INSERT OR REPLACE) the full agent-run ledger record — status, dispatched/started/completed timestamps, derived time-to-deliver, prompt/retry counts, tokens, direct cost, work units, release/phase/section, and the raw record JSON — into the previously writer-less `agent_runs` table; `Write-AppDbQuotaBurnSnapshot` captures each `Test-AgentDispatchQuota` evaluation; `Get-AppDbAgentRunMetricsHistory` returns runs as an oldest-first time series and seeds `agent_runs` from `output/agent-runs/runs/*.json` on the first SQLite read (mirroring the execution-ledger first-run migration); `Get-AppDbQuotaBurnHistory` returns the ordered burn-down series. Timestamp/number normalizers keep string-vs-`[datetime]` JSON round-trips lexicographically sortable.
- **`backend/modules/agent-runs/AgentRuns.ps1`** — `New-AgentRunRecord` and `Update-AgentRunRecord` now best-effort mirror the run record into `agent_runs` after every authoritative JSON write (same guarded pattern as the Phase 1 event mirror); a mirror failure never breaks the run it describes.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — the dispatch route persists a quota-burn snapshot after every quota evaluation (allowed, warned, or blocked). New routes `GET /api/agent-runs/metrics-history` (SQLite-backed with seeding; truthful JSON-runs fallback with `source=agent-runs-json`) and `GET /api/agent-runs/quota-burn-history` (SQLite only; empty with `source=none` when no provider), both following the maturity-history contract (`success`/`data`/`count`/`source`, `repoName`/`days` params). The `GET /api/agent-runs/*` `{runId}` prefix matcher now excludes the two literal paths it would otherwise have swallowed as run IDs.
- **`frontend/components/ApiDocsModal.tsx`** — documented both new routes in the Agent Run Monitoring group.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — Release 2.1 Phase 3 sections: `quota_burn_snapshots` in the expected bootstrap tables, schema-version-2 assertion, run-mirror upsert proof under repeated writes (create + two patches → one row), metrics-history shape checks (derived time-to-deliver, token/cost round-trip), and ordered quota burn-down with allowed/blocked round-trip.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — contract assertions for both new routes and `quota_burn_snapshots` added to the expected persistence-status tables.
- **`ROADMAP.md` / `task_plan.md`** — final Release 2.1 milestone marked `smoke-tested`, Phases 3-4 marked done, current focus repointed at release closeout, and a known-issues note added for the pre-existing module-smoke repairer failure.

### Testing

- **PowerShell parser checks** — clean for all five edited scripts/modules.
- **Targeted Phase 3 persistence proof** (standalone run of the new module-smoke assertions on the real `winsqlite3.dll` provider) — passed: schema v2 bootstrap + idempotent re-init, single upserted row after repeated patches, `timeToDeliverSeconds=600` derived from start/complete patches, first-read seeding from the JSON runs directory, ordered two-snapshot burn-down, disabled-boundary no-op contract. Run standalone because the full module suite currently aborts earlier at a pre-existing roadmap-repairer step unrelated to this change (tracked as follow-up).
- **`pwsh -NoProfile -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — `[PASS]` end to end: persistence status reports 12 tables, `/api/agent-runs/metrics-history -> source=sqlite`, `/api/agent-runs/quota-burn-history -> source=sqlite count=1` (a real quota evaluation captured through the new seam during the run itself).
- **`npm run build`** — passed.
- **Known pre-existing breakage (not from this slice)** — `tools/Test-RoadmapStructure.ps1` fails with a parameter-binding error even against the unmodified HEAD `ROADMAP.md`, so the roadmap edit was reviewed manually instead; repairing the validator and the module-smoke repairer expectation are follow-up items.

## 2026-07-03 — Fix: api-host smoke harness runs clean end-to-end

### Changes

- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — three reliability fixes for the carried-forward "harness does not return past the quota-refusal route" defect. Forensics on the previous hung run showed the quota-refusal route itself was innocent (it returned its HTTP 409 and the run had moved on into the merge-readiness checks, which print under the same `[STEP]` banner); the harness was being killed by fragile connects plus hang-amplifying teardown. (1) Default `BaseUrl` is now `http://127.0.0.1:7071` instead of `http://localhost:7071`: the host binds IPv4 loopback only and the local firewall silently drops `[::1]:7071`, so every request paid a ~2 s dual-stack fallback (measured 2,050 ms vs 2 ms) and each connect depended on firewall timing. (2) The host job is launched with `-ShutdownSignalPath`, so its accept loop polls `Pending()` instead of parking forever inside a blocking `AcceptTcpClient()` call and exits cleanly when signaled. (3) Teardown is re-ordered to signal-file → bounded `Wait-Job` → force-kill of any process still listening on the port → `Stop-Job`/`Remove-Job` last — `Stop-Job` against a job blocked in native socket code could hang indefinitely, which is how the harness used to freeze after its last visible step and leave an orphaned host holding port 7071. All existing assertions, including the Release 2.0 quota-refusal checks, are unchanged. Side effect: full-harness host-side run time dropped from ~6.5 minutes to 102 seconds.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — `Send-StaticFile` now recognizes Vite hashes containing `-` (base64url alphabet), scoped to files in an `assets/` directory: the current bundle's `index-BbNsaX-S.js` previously fell back to `no-cache` instead of `public, max-age=31536000, immutable`, deterministically failing the smoke's Release 1.3 assertion late in every full run. Also restored a missing line-continuation backtick after `-BaseBranch $baseBranch` in the dispatch route's `New-AgentRunRecord` call — the orphaned `-WorkUnitsEstimated …` line threw a silent `CommandNotFoundException` on every successful dispatch, dropping work-unit estimate metadata and `agentRunId` capture.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — ran start-to-finish, printed `[PASS] API host smoke completed`, and exited 0. Quota refusal returned HTTP 409 (`reason=session-cap-exceeded est=8`); `GET /assets/index-BbNsaX-S.js` served `Cache-Control: public, max-age=31536000, immutable`; the host log ends with `Repo Management API host stopped` (graceful signal shutdown) and no listener or job process remained.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 0 warnings.

## 2026-07-03 — Release 2.1 Phase 1: SQLite Persistence Foundation

### Changes

- **`backend/modules/persistence/Persistence.Store.ps1`** (new) — SQLite persistence foundation. `Get-SqliteCapability` detects a provider with zero external dependencies via a compiled native bridge that probes the OS-shipped SQLite library (`winsqlite3.dll` on Windows; `libsqlite3` on WSL/Linux/macOS) and degrades gracefully — no provider means a truthful capability report, never an exception. `Initialize-AppDatabase` bootstraps `output/app.db` (WAL mode, 5s busy timeout) with the schema-v1 tables named in the Release 2.1 milestone: `execution_ledger`, `execution_history`, `maturity_history`, `ops_log`, `portfolio_index_history`, `repo_signals`, `differential_scans`, `merge_readiness_snapshots`, `agent_runs`, `agent_run_events`, plus `schema_migrations`; re-init is idempotent. `Invoke-AppDbQuery` / `Invoke-AppDbNonQuery` expose parameterized-SQL-only helpers (typed round-trip for INTEGER/REAL/TEXT/NULL, UTF-8 safe). `Write-AppDbAgentRunEvent` is the first migration seam.
- **`backend/modules/agent-runs/AgentRuns.ps1`** — `Write-AgentRunEvent` now best-effort mirrors each lifecycle event into the `agent_run_events` table after its authoritative JSONL append (dual-write seam, `INSERT OR IGNORE` on `event_id` for idempotent replays). The mirror only activates when the persistence module is loaded and the database is initialized; failures are non-fatal and reported via a `dbMirrored` flag.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — dot-sources the persistence module, initializes `output/app.db` at startup (non-fatal, logged), and adds `GET /api/persistence/status` reporting capability detection, database state, schema tables, and the mirrored agent-run-event count.
- **`backend/modules/docaudit/DocAudit.Scanner.ps1`** (fix) — the doc-standards `schemaVersion: v1` config (commit `db62f0b`, 2026-06-26) removed `readmeStandards.recommendedSections` in favor of section contracts in `ai-doc-templates.json`, and the scanner's strict property access then threw `The property 'recommendedSections' cannot be found`, breaking every doc audit and the module smoke chain. The scanner now resolves the property StrictMode-safely: old-style configs keep their section checks; v1 configs skip them until audit-time resolution of the canonical template sections is wired up as its own work item.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new Release 2.1 Phase 1 sections: capability detection, temp-workspace `app.db` bootstrap with expected-table assertions, idempotent re-init, 25 repeated writes, unicode/quote/NULL parameter-binding round-trip, and the agent-run-event dual-write seam (JSONL authoritative + mirror row present). Also fixed the portfolio-assessment section to accept the `schemaVersion` key that replaced `version` in `repo-structure-standards.json` (same `db62f0b` schema change).
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new persistence-status step asserting the `GET /api/persistence/status` contract, the full expected table set when a provider is available, and the degraded contract when not.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the new Persistence route group and rollout contract (JSON/JSONL stores remain authoritative during Release 2.1).
- **`ROADMAP.md`** — marked the Release 2.1 schema-bootstrap milestone smoke-tested, added the Release 2.1 phase plan (Phases 1-4), and pointed the active-release current focus at Phase 2 (execution ledger + ops log migration).

### Testing

- **PowerShell parser checks** — clean for the persistence module, `AgentRuns.ps1`, the API host, and both smoke scripts.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end including all pre-existing sections and the new Release 2.1 Phase 1 steps.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed end-to-end including the new persistence-status step (`provider=winsqlite3.dll`, 11 tables).
- **Targeted scratch-port host check** — `GET /api/persistence/status` returned `success=true`, `capability.available=true`, `database.enabled=true`, and all 11 schema tables; host startup logged `Persistence: app database ready`.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — passed.

## 2026-06-27 — Fix: api-host smoke harness quota-refusal route

### Changes

- **`backend/modules/agent-runs/AgentRuns.ps1`** — made `Write-AgentRunEvent -RunId` optional (`[Parameter()][string]$RunId = ''`) instead of mandatory. Pre-dispatch telemetry (`quota.exhausted` / `quota.warning`) is emitted before any run exists, so it passes an empty `RunId`; the mandatory binding rejected the empty string and threw, which turned the quota-refusal route's intended HTTP 409 into a caught HTTP 500. This was the carried-forward defect that stopped `Invoke-ApiHostSmokeTest.ps1` from getting past the Release 2.0 quota-refusal step. Backward compatible — all existing callers pass a real `RunId`.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added a `-RequestTimeoutSec` parameter (default 180) and used it for every request, so legitimately slow cold-cache routes (e.g. the `/api/portfolio/assessment` full-workspace scan, ~42s) no longer trip a false 30s timeout before later steps run. Hardened teardown to force-stop any process still listening on the host port after `Stop-Job`/`Remove-Job`, guaranteeing a clean exit and preventing a stopped job from leaving the listener holding the port (the "host did not exit after `[PASS]`" symptom). All existing smoke assertions, including the quota-refusal checks, are unchanged.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — ran start-to-finish, reached the quota-refusal route (`reason=session-cap-exceeded est=8`, HTTP 409), printed `[PASS] API host smoke completed`, and exited 0 with no lingering listener or background job.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 0 warnings.

## 2026-06-26 — Release 2.0 Closeout and Release 2.1 Promotion

### Changes

- **`ROADMAP.md`** — closed Release 2.0, added a completion snapshot, corrected the stale Agent Runs time/token milestone to match the live Operations UI, promoted Release 2.1 to the active release, and set its current focus to Phase 1 SQLite/bootstrap work.
- **`docs/history/completed-releases.md`** — archived the full Release 2.0 detail with completion dates and the settled milestone/phase-plan status.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — passed with 0 errors.
- **`git diff --check -- ROADMAP.md docs/history/completed-releases.md CHANGELOG.md task_plan.md progress.md findings.md`** — passed.

## 2026-06-12 — Release 2.0 Phase 4: Budget Guard + Scan Annotations

### Changes

- **`backend/modules/agent-runs/BudgetLedger.ps1`** (new) — added the Release 2.0 budget-ledger helper module: settings-backed quota configuration with safe defaults, per-repo monthly budget resolution, current-period usage snapshots from the agent-run ledger, and `Test-AgentDispatchQuota` evaluation (credit-prompt stop, per-session cap, per-phase cap, monthly budget exhaustion, soft/hard remaining-unit thresholds).
- **`backend/modules/roadmap/Roadmap.Parser.ps1`** — roadmap parsing now returns structured release contexts, active phase-plan rows, budget-guardrail annotations, and `estimatedSessionWorkUnits`. Fixed a real Phase 4 parser defect where ASCII `-` placeholder cells in the phase-plan table were being misread as completion markers, which incorrectly erased the active phase.
- **`backend/modules/portfolio/Portfolio.Assessment.ps1`** and **`backend/modules/agent-runs/AgentRuns.ps1`** — portfolio assessment rows now carry active-release/phase/budget metadata through to the indexed model, and new agent-run records persist selected task section, planned release/phase, and estimate source instead of always hardcoding the default 3-unit estimate.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — `POST /api/roadmap/dispatch/execute` now resolves roadmap planning context before dispatch, enforces quota checks before any GitHub dependency is required, records `quota.warning` / `quota.exhausted` events, and returns a structured quota payload (`estimatedWorkUnits`, estimate source, remaining budget, planned release/phase). `POST /api/roadmap/scan` and the dispatch packet path now surface the new roadmap annotation fields.
- **`frontend/types.ts`**, **`frontend/components/OperationsWorkspaceView.tsx`**, **`frontend/components/ApiDocsModal.tsx`**, and **`backend/api-host/README.md`** — typed and documented the new roadmap-annotation / quota contracts; the Operations workspace now shows dispatch estimate metadata and richer agent-run planning details (section, phase, release, work-unit estimate, token count).
- **`scripts/Invoke-ModuleSmokeTest.ps1`** and **`scripts/Invoke-ApiHostSmokeTest.ps1`** — module smoke now covers annotated roadmap parsing and budget-ledger quota behavior; api-host smoke now checks roadmap-scan annotation fields and exercises the quota-refusal contract against an isolated temp repo fixture.

### Testing

- **PowerShell parser checks** — passed for `backend/modules/roadmap/Roadmap.Parser.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot \"$(pwd)\"`** — passed, including the new annotated-roadmap and budget-ledger steps.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md`** — 0 errors, 3 advisory warnings.
- **Targeted host checks on a scratch port** — roadmap-scan fixture returned `activePhasePlan='Phase 2: Quota guard'`, `estimatedSessionWorkUnits=8`, and `budgetGuardrail.maxUnitsPerPhase=10`; `POST /api/roadmap/dispatch/execute` returned HTTP 409 with `error.code=quota-exhausted` and `reasonCode=session-cap-exceeded` before any GitHub dependency was required.
- **Full `Invoke-ApiHostSmokeTest.ps1`** — the run now reaches the new Phase 4 roadmap-scan annotation step and enters the quota-refusal step, but in this session the broad end-to-end harness still did not return past that route; the isolated scratch-port route checks above passed.

## 2026-06-11 — Release 2.0 Phase 1: Agent-Run Ledger Foundation

### Changes

- **`backend/modules/agent-runs/AgentRuns.ps1`** (new) — agent-run ledger and append-only run-event telemetry. Editable current state lives as one JSON per run under `output/agent-runs/runs/`; lifecycle history is the schema-versioned, append-only `output/agent-runs/events.jsonl` stream (`run.dispatched` / `run.started` / `run.completed` / `run.failed` / `run.blocked` / `run.updated`). Run records carry the tier-1 metric fields from `standards/roadmap/ROADMAP_BUDGET_MODEL.md` (dispatch/start/completion timestamps, derived time-to-deliver, prompt count, retries, token usage, API spend, normalized work units) plus optional tier-2 operator observations; derived valuations are never stored. Functions: `New-AgentRunRecord`, `Get-AgentRuns`, `Get-AgentRunDetail`, `Update-AgentRunRecord` (validates status transitions, derives `timeToDeliverSeconds`), `Write-AgentRunEvent`.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — dot-sources the new module; `POST /api/roadmap/dispatch/execute` now records every dispatch in the agent-run ledger (non-fatal on ledger failure) and returns `agentRunId` alongside the existing `runId`; added `GET /api/agent-runs` (status/repoName filters, newest first, per-status rollup) and `GET /api/agent-runs/{runId}` (run + lifecycle events; 404 for unknown runs).
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — new agent-run ledger step against an isolated temp workspace: create → list (with status-filter negative check) → update (status transition, branch/PR association, time-to-deliver derivation) → detail (both lifecycle events present) → unknown-run null → invalid-status rejection; cleans up in `finally`.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — new step asserting the `GET /api/agent-runs` payload shape (`items`/`count`/`byStatus`) and the 404 contract for unknown run IDs.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the new Agent Run Monitoring routes and storage model.
- **`ROADMAP.md`** — marked the Phase 1 milestones complete with completion dates, annotated the partially-delivered tier-1-metrics and event-stream milestones with what remains (Phase 2 refresh path), added the Release 2.0 phase plan (Phases 1-4), and updated the active-release current focus and traceability to the shipped surfaces.

### Testing

- **PowerShell parser checks** — passed for the new module, API host, and both smoke scripts.
- **`npm run build`** — passed.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — full run passed, including the new agent-run ledger step (time-to-deliver derived correctly; both lifecycle events present; invalid status rejected).
- **Live host checks** — `GET /api/agent-runs` empty contract → `count=0`; after creating a run: filtered list returns it with `byStatus.dispatched=1`; `GET /api/agent-runs/{runId}` returns the record (status `dispatched`, `workUnitsEstimated=3`) plus its `run.dispatched` event; unknown runId → HTTP 404. Test ledger data removed afterward.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors.

## 2026-06-11 — Release 1.9 Phase 3: AI Documentation Improvement — Explicit Apply with Backup & Restore (Release 1.9 closed; Release 2.0 active)

### Changes

- **`backend/modules/ai/AiDocImprovement.ps1`** — added `Invoke-AiDocImproveApply`, the only function in the module that mutates a managed document. It refuses targets whose file name does not match the doc type (README.md / ROADMAP.md), backs up the current file to `output/ai-doc-improvements/backups/<repo>/` with a timestamped name, writes a restore-metadata JSON beside the backup (SHA-256 hashes of original and applied content plus a ready-to-run restore command), writes the operator-approved content, and appends an append-only `recordType=apply` / `applied=true` record to the per-repo improvement-history JSONL.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — added `POST /api/ai/docs/improve/apply`: 400 without `repoName` or `proposedContent`; resolves the target path exactly like the preview route (explicit `path` → roadmap cache → portfolio index) and 404s when unresolvable; apply failures return 400 with the reason.
- **`frontend/components/OperationsWorkspaceView.tsx`** — "Apply Proposed to Repo" action in the AI Documentation Improvement panel with an explicit confirmation dialog, success banner showing target/backup/restore-metadata paths, error surface, viewer-pane refresh after apply, and an "Applied" badge plus apply-record rendering in the History tab.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — `AiDocImproveApplyRequest` / `AiDocImproveApplyResult` contracts, `applyAiDocImprovement` client, and `recordType` / `backupPath` on history items.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the apply route.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added a Release 1.9 Phase 3 smoke step: missing-`proposedContent` → 400, then a real apply against an isolated temp target asserting the written content, backup content, restore metadata (applyId match + restoreCommand), and the `applied=true` history record; cleans up all artifacts in a `finally` block so the smoke never mutates a real repo document.
- **`ROADMAP.md`** — Release 1.9 closed out and datetime-stamped (Phase 1 2026-06-10; Phases 2-3 2026-06-11); full release detail moved to the archive with per-milestone completion dates; Release 2.0 promoted to active with a full execution contract (current focus: agent-run ledger foundation with tier-1 budget-model metrics).
- **`docs/history/completed-releases.md`** — archived Release 1.9 with completion dates on every milestone and a dated phase plan, per the new roadmap-standard timeline convention.

### Testing

- **PowerShell parser checks** — passed for the AI module, API host, and smoke script.
- **`npm run build`** — passed.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors.
- **Live host checks** of `POST /api/ai/docs/improve/apply` — missing `proposedContent` → HTTP 400; real apply against a temp README target → HTTP 200 with the proposed content written, backup containing the original content, restore-metadata JSON with matching `applyId`, hashes, and working restore command; history returns the `applied=true` record with `backupPath`; docType/file-name mismatch guard (roadmap docType against a README.md path) → HTTP 400. (The full `Invoke-ApiHostSmokeTest.ps1` run still times out at the pre-existing 30s copilot-task/portfolio warmup cap on this large local inventory — before the AI steps are reached; tracked separately.)

## 2026-06-11 — Release 1.9 Phase 2: AI Documentation Improvement — Diff Viewer & History

### Changes

- **`backend/modules/ai/AiDocImprovement.ps1`** — added per-repo improvement-cycle history: `Write-AiDocImprovementHistory` appends a compact metadata record (provider, template, score movement, change summary — not full document bodies) to `output/ai-doc-improvements/<repo>.improvements.jsonl` on every preview, and `Get-AiDocImprovementHistory` reads it newest-first with an optional `docType` filter. Fixed a same-second ordering bug by sorting on the raw `[datetime]` value instead of a locale string cast.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — the preview route now persists a history record per cycle; added `GET /api/ai/docs/improve/history` (per-repo, `docType` filter, limit) and `GET /api/ai/docs/templates` (serves the data-driven built-in templates to the UI).
- **`frontend/components/OperationsWorkspaceView.tsx`** — new AI Documentation Improvement panel in the Operations repo detail: README/ROADMAP selector, template and provider selects, custom improvement prompt field, side-by-side Current vs Proposed comparison with change summary / score movement / warnings, copy-proposed action, "Run Another Cycle on Proposed" (feeds the proposal back in as the next cycle's input), and a History tab.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — typed contracts and client functions for AI doc improvement preview, history, and templates.
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the three AI documentation routes.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — extended the AI smoke step: templates route returns non-empty README/ROADMAP template lists; history route 400s without `repoName` and returns the record written by the preceding preview call (matched by `previewId`).
- **`ROADMAP.md`** — marked the Release 1.9 Phase 2 milestones complete and updated the active-release execution contract; Phase 3 (explicit apply with backup/restore) is the remaining slice.

### Testing

- **PowerShell parser checks** — passed for the AI module, API host, and smoke script.
- **`npm run build`** — passed.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors (2 pre-existing advisory warnings).
- **Live host checks** — `GET /api/ai/docs/templates` → 4 README + 4 ROADMAP templates; preview → history round trip returns the matching `previewId`; two-cycle flow (proposed content fed back in) works and is idempotent at full section coverage; history missing-`repoName` → 400; `docType` filter excludes non-matching records; same-second ordering regression verified at module level.

## 2026-06-10 — Release 1.9 Phase 1: AI Documentation Improvement — Provider Foundation & Preview

### Changes

- **`backend/modules/ai/AiDocImprovement.ps1`** (new) — provider-agnostic AI documentation-improvement adapter contract plus three adapters: a deterministic offline **heuristic** provider (always available; scaffolds missing template sections and normalizes the title), an **OpenAI** raw-HTTP adapter (Chat Completions), and an **Anthropic** raw-HTTP adapter (Messages API, model `claude-opus-4-8`). `Invoke-AiDocImprovePreview` resolves a template, selects an available provider (explicit → settings → heuristic fallback), computes estimated section-coverage score movement, and returns a preview-only record. No file is written.
- **`backend/config/ai-doc-templates.json`** (new) — data-driven built-in README templates (product, developer/operator, open-source, portfolio) and ROADMAP templates (release-oriented, contract, agent-dispatch-ready, recovery/repair), each with improvement guidance and expected sections.
- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — dot-sources the new AI module and adds `POST /api/ai/docs/improve/preview`. The route resolves current README/ROADMAP content from an inline body, the roadmap cache, or the portfolio index, then returns current vs proposed content, a change summary, estimated score movement, and warnings. Preview-only — no README/ROADMAP mutation.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added an AI-preview smoke step (missing-`repoName` 400 path plus a heuristic-provider contract check with inline content) that stays offline, deterministic, and free.
- **`ROADMAP.md`** — promoted Release 1.9 to the active release (Release 1.8 → `done`), marked the Phase 1 milestones complete, added a Release 1.9 phase plan, and gave the active-release detail a full execution contract (validation plan, risks, dependencies, known issues, traceability). Moved the completed Release 1.8 detail to the archive.
- **`docs/history/completed-releases.md`** — archived the full Release 1.8 detail.

### Testing

- **PowerShell parser checks** — passed for `backend/modules/ai/AiDocImprovement.ps1`, `backend/api-host/Start-RepoManagementApiHost.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — passed.
- **`tools/Test-RoadmapStructure.ps1`** — 0 errors (2 pre-existing advisory warnings).
- **Live host check** of `POST /api/ai/docs/improve/preview` — missing-`repoName` → HTTP 400; heuristic README → HTTP 200 with full preview contract (score delta, change summary); ROADMAP docType → HTTP 200 with auto-selected template. The Anthropic adapter was additionally exercised against the live Messages API. (The full `Invoke-ApiHostSmokeTest.ps1` run still times out earlier at the pre-existing 30s docs-audit/portfolio warmup cap on this large local inventory; the AI step passes when reached.)

## 2026-06-09 — Release 1.8: Operations Prompt Dispatch Tracking

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — added per-refinement dispatch-record persistence for Operations prompt history, merged those records into `GET /api/operations/prompt/history`, and taught `POST /api/roadmap/dispatch/execute` to accept an optional refinement run ID so Operations dispatches can be linked back to their originating prompt.
- **`frontend/components/OperationsWorkspaceView.tsx`** — added direct dispatch from the Prompt Refinement panel, surfaced dispatch success/error state inline, and expanded the History tab to show linked dispatch runs per refinement entry.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — extended the Operations prompt history contract with dispatch metadata and allowed dispatch execution requests to carry an originating refinement run ID.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added a regression check that synthesizes a linked dispatch record for a fresh refinement run and verifies `GET /api/operations/prompt/history` returns the merged dispatch metadata.
- **`frontend/components/ApiDocsModal.tsx`**, **`backend/api-host/README.md`**, and **`ROADMAP.md`** — documented the linked dispatch-history contract and marked the Release 1.8 closeout slice truthfully.

### Testing

- **`npm run build`** — passed.
- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed, including the new Operations prompt-history dispatch-link regression.

## 2026-06-07 — Release 1.8: Prompt Refinement Panel

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — finalized `POST /api/operations/prompt/refine` around the existing packet flow, including operator-selected task overrides, emphasis areas, additional constraints, operator instructions, and per-repo refinement history persisted under `output/roadmap-task-history/prompt-refinements/`. Added `GET /api/operations/prompt/history` for history retrieval.
- **`frontend/components/OperationsWorkspaceView.tsx`** — extended the inline Prompt Refinement panel with editable selected-task controls, operator refinement inputs, editable refined-prompt review, copy action, and a History tab for prior refinements.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — unified the prompt refinement request/response contracts, added history-item types, and added client helpers for both refine and history routes.
- **`frontend/components/ApiDocsModal.tsx`** — documented the final `POST /api/operations/prompt/refine` contract and `GET /api/operations/prompt/history`.
- **`ROADMAP.md`** — marked the Release 1.8 prompt-refinement milestones complete with the merged route and UI behavior.

### Testing

- **`npm run build`** — passed.
- **PowerShell parser diagnostics** — `Start-RepoManagementApiHost.ps1` passed with no parse errors.

## 2026-06-02 — Release 1.8: Operations Prompt Refinement Foundation

### Changes

- **`backend/api-host/Start-RepoManagementApiHost.ps1`** — added `POST /api/operations/prompt/refine`, which reuses the existing packet assembly path, applies operator-directed task/constraint/emphasis instructions, and returns a refined prompt with warning metadata.
- **`frontend/types.ts`** and **`frontend/services/apiClient.ts`** — added typed request/response contracts and client integration for Operations prompt refinement.
- **`frontend/components/OperationsWorkspaceView.tsx`** — added an in-panel Prompt Refinement workflow with selected-task overrides, emphasis and constraint inputs, custom operator instruction field, warning display, refined prompt preview, and copy action.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added route coverage for `/api/operations/prompt/refine` (missing-body validation and success-payload field checks).
- **`frontend/components/ApiDocsModal.tsx`** and **`backend/api-host/README.md`** — documented the new Operations prompt refinement endpoint and contract.
- **`ROADMAP.md`** — marked the corresponding Release 1.8 prompt-refinement milestones as completed (`ui-connected` for panel/preview/operator field, `backend-complete` for refine API route).

### Testing

- **`npm run build`** — passed.
- **Targeted API validation** — `POST /api/operations/prompt/refine` verified with long-timeout requests against a live host: expected missing-repo validation failure path plus successful response contract path.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — this run timed out during portfolio warmup under the script's existing 30-second request cap before reaching final summary.

## 2026-05-29 — Release 1.8: Operations Audit Findings Panel

### Changes

- **`OperationsWorkspaceView.tsx`** — added a new audit findings panel in Operations that shows README findings, ROADMAP findings, structure findings, and dispatch blockers for the selected repo.
- **`Dashboard.tsx`** — Operations view now primes docs-audit and roadmap-audit data on first open and passes those models into the Operations workspace.
- **`ROADMAP.md`** — marked the Release 1.8 audit findings panel milestone complete as `ui-connected`.

### Testing

- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed.

## 2026-05-28 — Roadmap Viewer Task-Source Mismatch Fix

### Changes

- **`RoadmapViewerModal.tsx`** — Preview Task and Start Task now pass the already-loaded local roadmap path to the roadmap-agent flow instead of forcing a second repo-only lookup.
- **`Start-RoadmapCopilotTask.ps1`** — explicit local `-RoadmapPath` values are now resolved from disk before any GitHub contents lookup, removing the contradiction where a local roadmap was visible in the modal but unreachable to task preview.
- **`Invoke-ApiHostSmokeTest.ps1`** — added regression coverage for `/api/roadmap-agent/preview` with a local roadmap path.

### Testing

- **PowerShell parser checks** — passed for `scripts/Start-RoadmapCopilotTask.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **Direct preview validation** — `Start-RoadmapCopilotTask.ps1 -PreviewOnly -RoadmapPath "$(pwd)/ROADMAP.md"` returned a preview payload and resolved the local roadmap path without requiring a GitHub content lookup.
- **`npm run build`** — passed.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated the new local-roadmap preview route behavior.

## 2026-05-28 — Release 1.8 Phase 1: Operations Workspace Foundation

### Changes

- **`Start-RepoManagementApiHost.ps1`** — added `GET /api/operations/repos`, serving repo-specific indexed portfolio records for the Operations tab with a warm portfolio-assessment-cache fallback and stable `repoId` values.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — expanded API host smoke coverage to validate the Operations repo-index contract after warming `/api/portfolio/assessment`.
- **`HelpModal.tsx`**, **`ApiDocsModal.tsx`**, and **`backend/api-host/README.md`** — documented the Operations workspace as a first-class app surface and added the new backend route to the API reference.
- **`ROADMAP.md`** — promoted Release 1.8 to the active release and marked the shipped foundation milestones truthfully: Operations tab, repo detail workspace, GitHub panel, and `GET /api/operations/repos`.

### Testing

- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — verified the frontend compiles with the updated Help and API docs copy.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated `/api/operations/repos` alongside the existing portfolio, report, and static-host routes.
- **`git diff --check`** — passed for the touched Operations foundation files and the roadmap/progress artifact updates.

## 2026-05-28 — Release 1.7.5 Phase 7B: Collection Report and Workflow Documentation

### Phase 7B Changes

- **`Portfolio.Report.ps1`** — added a new portfolio reporting module that generates timestamped HTML and CSV Collection Status Reports from portfolio assessment entries, including lifecycle counts, blockers, recommended actions, and top-ranked work.
- **`Start-RepoManagementApiHost.ps1`** — `/api/export` now accepts `portfolioEntries` and emits the collection-status report path while preserving the older repo-status export path as a compatibility fallback.
- **`Dashboard.tsx`** and **`apiClient.ts`** — the Report action now prefers portfolio assessment data for local collection exports, falling back to legacy repo-status export only when the richer model is unavailable.
- **`HelpModal.tsx`**, **`ApiDocsModal.tsx`**, **`backend/api-host/README.md`**, and **`docs/reference/portfolio-assessment.md`** — updated end-user and reference documentation so the scan → classify → rank → refine prompt → dispatch → report workflow is explicit and the report contract is documented.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — export smoke coverage now exercises the collection-report payload and asserts the saved HTML report serves Collection Status Report content.

### Phase 7B Testing

- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Report.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`npm run build`** — verified the frontend compiles with the updated export flow, Help modal copy, and API docs.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated `/api/export`, `/api/reports/:reportName`, `/api/portfolio/assessment`, and the static frontend bundle against the new collection-report path.

## 2026-05-28 — Release 1.7.5 Phase 7A: Differential Scan Completion

### Phase 7A Changes

- **`Start-RepoManagementApiHost.ps1`** — `/api/portfolio/assessment` now supports `scanMode=differential` and re-assesses only changed repos by comparing current signal fingerprints against the persisted index snapshot.
- **`Start-RepoManagementApiHost.ps1`** — differential mode now merges unchanged repos from the prior index payload and recalculates summary metrics on the combined result.
- **`Start-RepoManagementApiHost.ps1`** — fixed cache behavior so `scanMode=differential` requests bypass the route-level memory cache and surface differential signal metadata (`signalSources.scanMode`, changed/unchanged counters) correctly.
- **`Portfolio.Assessment.ps1`** — added scan fingerprint helpers, persisted fingerprint fields in index payload records, and index-to-assessment conversion helpers used by differential merge logic.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — added differential-route contract checks for `GET /api/portfolio/assessment?scanMode=differential`, including scan mode marker validation.

### Phase 7A Testing

- **PowerShell parser checks** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1`, `backend/modules/portfolio/Portfolio.Assessment.ps1`, and `scripts/Invoke-ApiHostSmokeTest.ps1`.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and confirmed `GET /api/portfolio/assessment?scanMode=differential` returns `success=true` with `signalSources.scanMode=differential-fallback-full`.

## 2026-05-28 — Release 1.7.5 Phase 6: Prompt Context Packet Foundation

### Changed

- **`Start-RepoManagementApiHost.ps1`** — enriched `/api/copilot-task/preview` packets with README context, selected-release roadmap context, portfolio lifecycle and score context, explicit constraints, and value rationale for the selected task.
- **`Start-RepoManagementApiHost.ps1`** — when portfolio assessment context is available, task preview now prefers the assessment-ranked top-value roadmap item instead of always defaulting to raw roadmap order.
- **`frontend/types.ts`** and **`CopilotTaskPreviewModal.tsx`** — extended the task-packet contract and preview UI so operators can review README summary, release goal/out-of-scope, lifecycle context, value rationale, and constraints before copying the prompt.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — warmed portfolio assessment ahead of task preview and expanded the route contract check for the new prompt-context packet fields.

### Testing

- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ApiHostSmokeTest.ps1 -WorkspaceRoot "$(pwd)"`** — passed and validated the enriched `/api/copilot-task/preview` contract.
- **`npm run build`** — verified the frontend compiles with the prompt-context packet UI changes.
- **PowerShell parser check** — passed for `backend/api-host/Start-RepoManagementApiHost.ps1` and `scripts/Invoke-ApiHostSmokeTest.ps1`.

## 2026-05-28 — Release 1.7.5 Phase 5: Expanded Evaluator

### Changed

- **`Roadmap.Evaluator.ps1`** — expanded repo evaluation beyond hardening-only checks so missing-roadmap repos now emit broader opportunity findings across documentation, testing, security, modernization, feature surface, and user-value gaps.
- **`Roadmap.Evaluator.ps1`** — roadmap draft generation now groups findings into staged release suggestions instead of collapsing everything into one foundational hardening release.
- **`RepoEvaluationModal.tsx`**, **`WorkQueueView.tsx`**, **`HelpModal.tsx`**, and **`frontend/types.ts`** — frontend copy and category handling now reflect the broader evaluator contract, including new finding categories and summary chips in the repo-evaluation modal.
- **`scripts/Invoke-ModuleSmokeTest.ps1`** — added direct repo-evaluator smoke coverage that asserts the expanded finding categories and the staged roadmap-draft structure.

### Testing

- **Targeted `Invoke-RepoEvaluation` verification** — passed on a temporary repo and confirmed `documentation`, `testing`, `security`, `modernization`, `feature`, and `user-value` findings plus staged draft-release output.
- **`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-ModuleSmokeTest.ps1 -WorkspaceRoot \"$(pwd)\"`** — reached and passed the new repo-evaluator smoke step, then later failed in an unrelated pre-existing portfolio-assessment smoke path with `The term 'if' is not recognized...`.
- **`npm run build`** — verified the frontend compiles with the expanded evaluator UI/category changes.

## 2026-05-27 — Release 1.7.5 Phase 4: Work Queue Value Display

### Changed

- **`WorkQueueView.tsx`** — ready repos now surface the highest-value pending roadmap item from `topValueItem`, show a value score card with rationale tooltip, and rerank within readiness buckets by value score before falling back to pending-count and name ordering.
- **`Dashboard.tsx`** — Work Queue now receives the live portfolio assessment model, and docs-audit refresh/scan flows also refresh portfolio assessment data so value ranking does not lag behind refreshed readiness data.
- **`docs/reference/portfolio-assessment.md`** — documented the `pendingItems` and `topValueItem` contract fields and how Work Queue ranking consumes them.

### Testing

- **`npm run install:frontend`** — repaired missing Rollup optional dependencies required by the repo's Vite build on this machine.
- **`npm run build`** — verified the frontend compiles with the new Work Queue value-ranking UI.

## 2026-04-26 — Release 1.7.5 Phase 2: Value-Ranked Work Planning

### Added

- **`Portfolio.ValueScorer.ps1`** — new deterministic portfolio value scorer for pending roadmap items. It scores impact, unblock potential, risk reduction, repo maturity, effort fit, dependency reduction, and recency.
- **`backend/config/value-scoring.json`** — data-driven weights and keyword rules for the value scoring model.
- **`/api/portfolio/assessment`** — assessment entries now include scored `pendingItems` and `topValueItem` fields while preserving existing lifecycle and roadmap fields.
- **Frontend portfolio types** — added `PortfolioPendingItemValue` and `PortfolioValueTier` for the new assessment response fields.

### Testing

- **`scripts/Invoke-ModuleSmokeTest.ps1`** — added value scorer smoke coverage and assertion that ready repo assessment includes scored pending items and selects the highest-value item.
- **`scripts/Invoke-ApiHostSmokeTest.ps1`** — expanded portfolio assessment contract checks for `pendingItems` and `topValueItem`.

---

## 2026-03-18 — Production Hardening Audit

### Security

- **`NotificationHub.ps1`** — `Register-NotificationWebhook` now validates the webhook URL scheme before registration. Only `http://` and `https://` URLs are accepted; `file://`, `ftp://`, and other schemes throw immediately, preventing SSRF-class abuse.
- **`NotificationHub.ps1`** — `Register-NotificationWebhook` now validates that every supplied event name is in the declared `$script:SupportedEvents` list before writing to disk. Unknown event names throw with a descriptive message.
- **`Start-RepoManagementApiHost.ps1`** — `Read-HttpRequest` now caps `Content-Length` to 10 MB. Requests advertising a body larger than this are rejected (returning `null`) to prevent memory exhaustion from large or malicious payloads.
- **`Start-RepoManagementApiHost.ps1`** — `Get-JsonObjectFromText` now explicitly checks `$end -lt 0` in addition to `$end -le $start`, preventing an out-of-range substring on output that contains `{` but no `}`.

### Reliability

- **`Execution.Ledger.ps1`** — duplicate-task guard in `Invoke-AssignLane` now normalizes task text with `.Trim().ToLowerInvariant()` before comparison, preventing the same task from running in two lanes when its text differs only in case or leading/trailing whitespace.
- **`Execution.Ledger.ps1`** — `Read-ExecutionLedger` now emits a `Write-Warning` before returning the empty fallback when the ledger file cannot be parsed, making corruption visible to operators rather than silently resetting state.
- **`MaturityDrift.Monitor.ps1`** — `Get-MaturityDrift` now uses `[double]::TryParse()` with `InvariantCulture` instead of a bare `[double]` cast when extracting the current score from audit entries. Malformed or non-numeric score values no longer throw; they default to `0`.
- **`NotificationHub.ps1`** — `Send-NotificationEvent` now guards against `null` or non-array `events` properties on webhook objects using an explicit array type check before filtering, preventing a potential null-reference during dispatch.
- **`NotificationHub.ps1`** — The previously silent `catch {}` blocks when persisting webhook registration and metadata updates now emit `Write-Warning` so operators are informed that the in-memory state could not be flushed to disk.

### Performance / Robustness

- **`Roadmap.Linter.ps1`** — `Invoke-LintRoadmapContent` now enforces a 5 000-line and 512 KB budget on roadmap content before running per-line rules. Content that exceeds either limit is silently trimmed to the budget and a new `LINT-SIZE` (warning) finding is added to inform the operator. This prevents runaway processing on pathological or accidentally concatenated roadmap files.
- **`Roadmap.Parser.ps1`** — `Invoke-ParseRoadmapContent` now enforces the same 5 000-line limit before iterating content. Lines beyond the limit are silently ignored, keeping parse time bounded for large inputs.

### Maintenance

- **`backend/config/settings2.json`** — Removed. This file was byte-for-byte identical to `settings.json` and was not referenced by any code or script. It was a source of potential configuration drift.

### Testing

- **`scripts/Invoke-ModuleSmokeTest.ps1`** — Added three new smoke steps that directly exercise the new hardening:
  - _Notification hub URL validation guard_ — verifies that `Register-NotificationWebhook` throws for `file://` URLs.
  - _Notification hub unknown event type guard_ — verifies that `Register-NotificationWebhook` throws for unrecognized event names.
  - _Execution ledger case-insensitive duplicate task guard_ — assigns one repo with task text `"Implement feature X"` then confirms the second repo is rejected when using the same text in a different case (`"Implement Feature X"`).
  - _Roadmap linter oversized content truncation guard_ — lints a 6 000-line roadmap and confirms the `LINT-SIZE` warning finding is present.

---

## 2026-03-16 — Release 1.1: Standardization, Guardrails, and Continuous Improvement

### Added

- **`Roadmap.Linter.ps1`** — new backend module with exported function `Invoke-LintRoadmapContent`. Runs 7 policy checks against raw ROADMAP.md content:
  - LINT-001 (error): Release headings must match `## Release X.Y — Title` format.
  - LINT-002 (error): Checkbox items must use `- [ ]` or `- [x]` format (detects malformed checkboxes).
  - LINT-003 (warning): Product Intent section must be present.
  - LINT-004 (warning): Completed-work section (Recently Completed or similar) must be present.
  - LINT-005 (warning): Each release section must contain at least one checklist item.
  - LINT-006 (info): Vague checklist item text detected (improve, fix, refactor, todo, misc, etc.).
  - LINT-007 (info): Version gaps detected across release headings.
- **`MaturityDrift.Monitor.ps1`** — new backend module with three exported functions:
  - `Set-MaturityBaseline` — stores per-repo target maturity level in `output/maturity-baselines.json`. Upserts existing entries.
  - `Get-MaturityDrift` — compares current audit results against baselines; emits `driftSeverity` (`warning` = 1 level below, `critical` = 2+ levels below) per drifted repo.
  - `Confirm-MaturityDriftAcknowledged` — stamps `lastAcknowledgedAt` on a baseline entry to silence alerts.
- **`DocStandardization.Previewer.ps1`** — new backend module (`backend/modules/docstandardization/`) with:
  - `Invoke-PreviewReadmeStandardization` — analyzes README.md against standard expectations (title, required sections: Installation, Usage, Contributing, License; minimum length). Returns `previewState`: `standardization-preview-ready`, `standardization-blocked`, or `already-standard`, with proposed content and per-action severity list.
  - `Invoke-ApplyReadmeStandardization` — backs up original README, writes proposed content, appends JSONL history entry.
- **`NotificationHub.ps1`** — new common module with:
  - `Register-NotificationWebhook` — registers a webhook URL subscribed to named events (`scan.completed`, `repair.applied`, `execution.failed`, `drift.detected`). Stored in `output/notification-webhooks.json`.
  - `Get-NotificationWebhooks` — returns all registered webhooks.
  - `Remove-NotificationWebhook` — removes a webhook by id.
  - `Send-NotificationEvent` — fires HTTP POST to all webhooks subscribed to the event; failures are caught and reported without crashing callers.
- **`GET /api/roadmap/lint`** — returns lint result for a named repo (requires `repoName` query parameter).
- **`POST /api/roadmap/lint/scan`** — runs lint checks across all repos in the roadmap index; returns per-repo results.
- **`POST /api/readme/standardize/preview`** — builds a full README standardization preview for a named repo.
- **`POST /api/readme/standardize/apply`** — applies an operator-approved README standardization (backs up original, writes proposed content, logs to history).
- **`GET /api/readme/standardize/history`** — returns README standardization history (preview and apply events) with `limit` query parameter.
- **`GET /api/roadmap/drift`** — returns contract drift alerts for all repos with active maturity baselines.
- **`POST /api/roadmap/drift/baseline`** — sets or updates the target maturity level baseline for a named repo.
- **`POST /api/roadmap/drift/acknowledge`** — acknowledges drift for a repo, stamping `lastAcknowledgedAt`.
- **`GET /api/notifications/webhooks`** — lists all registered notification webhooks.
- **`POST /api/notifications/webhooks`** — registers a new notification webhook.
- **`POST /api/notifications/webhooks/remove`** — removes a webhook by id.
- **`POST /api/roadmap/completion-preview`** — after task execution, generates a proposed roadmap update with completed items marked (`- [ ]` → `- [x]`). Returns `previewId`, `currentContent`, `proposedContent`, and `markedCount`.
- **`RoadmapLintModal` component** — per-repo lint findings modal showing pass/fail status, error/warning/info counts, and expandable findings with recommended actions.
- **`ReadmeStandardizationModal` component** — three-tab modal (Standardization Plan / Diff Preview / History) with editable proposed content textarea and explicit two-step apply workflow.
- **Saved operator filters** in `WorkQueueView` — filter presets persisted to `localStorage`; operators can name and save current readiness/maturity/search combinations and load them with one click.
- **"Lint" button in `WorkQueueView`** — appears for repos with a roadmap; opens `RoadmapLintModal`.
- **"Standardize" button in `WorkQueueView`** — opens `ReadmeStandardizationModal` for any repo.
- **`onLintRoadmap` and `onStandardizeReadme` props on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`OperationType` extended** with `'roadmap-lint-scan'`, `'readme-standardize-preview'`, `'readme-standardize-apply'`.
- **New frontend types** in `frontend/types.ts`: `RoadmapLintFinding`, `RoadmapLintResult`, `ReadmeStandardizationPreviewState`, `ReadmeStandardizationAction`, `ReadmeStandardizationPreview`, `ReadmeStandardizationHistoryItem`, `MaturityDriftAlert`, `MaturityDriftResult`, `NotificationWebhook`, `RoadmapCompletionPreview`.
- **New API client functions** in `frontend/services/apiClient.ts`: `getRoadmapLint()`, `triggerRoadmapLintScan()`, `previewReadmeStandardization()`, `applyReadmeStandardization()`, `getReadmeStandardizationHistory()`, `getMaturityDrift()`, `setMaturityBaseline()`, `acknowledgeMaturityDrift()`, `getNotificationWebhooks()`, `registerNotificationWebhook()`, `removeNotificationWebhook()`, `previewRoadmapCompletion()`.
- **Module smoke test** — new steps cover loading all four new modules, linting well-formed and malformed roadmaps, setting maturity baselines and detecting drift, previewing README standardization for missing and partial READMEs, and the full notification webhook lifecycle.
- **API smoke test** — new Release 1.1 steps cover `GET /api/roadmap/lint` and `POST /api/roadmap/lint/scan`, `POST /api/readme/standardize/preview` and `GET /api/readme/standardize/history`, `GET /api/roadmap/drift`, `GET/POST /api/notifications/webhooks`, and `POST /api/roadmap/completion-preview`, with contract field validation where applicable.

### Changed

- ROADMAP.md: Release 1.1 milestones marked complete; "Immediate Next Focus" updated to next release.

## 2026-03-16 — Release 0.9: Roadmap Repair Preview & Standardization Workflow

### Added

- **`Roadmap.Repairer.ps1`** — new backend module with two exported functions:
  - `Invoke-PlanRoadmapRepair` — maps a normalized, audited `RoadmapContract` (from `Invoke-AuditRoadmapContract`) to a list of concrete repair actions. Returns a repair plan with `previewState`: `repair-preview-ready`, `repair-blocked`, or `rewrite-not-recommended`. Blocks repair when roadmap is missing or unparseable; recommends against rewrite when roadmap is already complete or at L3/L4.
  - `Invoke-GenerateRepairPreview` — applies the repair plan to generate a proposed normalized roadmap markdown string. Preserves all checked items (`- [x]`), restructures pending work into release-scoped sections with goal statements, acceptance criteria, and out-of-scope boundaries. Returns `previewId`, current content, proposed content, repair action list, and item counts.
- **`POST /api/roadmap/repair/preview`** — builds a full repair preview for a named repository. Reads the roadmap, runs the audit, plans the repair, and generates proposed normalized content. Returns the preview object including `previewState`, `repairActions`, `currentContent`, `proposedContent`, `originalMaturityLevel`, and `auditFindings`.
- **`POST /api/roadmap/repair/apply`** — applies an operator-approved repair preview to the actual roadmap file. Requires `repoName`, `previewId`, and `proposedContent`. Backs up the original file, writes the proposed content, invalidates roadmap and audit caches, and persists the apply event to repair history.
- **`GET /api/roadmap/repair/history`** — returns rewrite history metadata (preview and apply events) for all repos, with `limit` query parameter.
- **Repair history persistence** (`output/roadmap-repair-history/repair-history.jsonl`) — JSONL append-only log of repair events with `previewId`, `repoName`, `roadmapPath`, `previewState`, `originalMaturityLevel`, `event` (`preview` or `apply`), and `timestamp`.
- **Roadmap backup on apply** — original roadmap file is backed up to `output/roadmap-repair-history/backups/` before any write-back.
- **Operations-log traces** for roadmap repair — `[TRACE]` entries for read, plan, preview, write, and apply events; cache invalidation after a successful apply.
- **`RoadmapRepairPreviewState` type** — `'repair-preview-ready' | 'repair-blocked' | 'rewrite-not-recommended'` in `frontend/types.ts`.
- **`RoadmapRepairAction` type** — per-action repair step with `actionId`, `description`, `affectsSection`, and `severity`.
- **`RoadmapRepairPreview` type** — full preview shape with `previewId`, `previewState`, `blockReason`, `repoName`, `roadmapPath`, `originalMaturityLevel`, `originalMaturityScore`, `currentContent`, `proposedContent`, `repairActions`, `auditFindings`, `completedItemCount`, `pendingItemCount`, and `generatedAt`.
- **`RoadmapRepairHistoryItem` type** — history record shape with `previewId`, `repoName`, `roadmapPath`, `previewState`, `originalMaturityLevel`, `event`, `timestamp`, and `appliedAt`.
- **`previewRoadmapRepair()`, `applyRoadmapRepair()`, `getRoadmapRepairHistory()`** in `frontend/services/apiClient.ts`.
- **`RoadmapRepairModal` component** — three-tab modal (Repair Plan / Diff Preview / History) opened from the Work Queue. Shows current maturity badge, repair action list with severity, side-by-side current vs proposed diff preview with syntax highlighting, an editable proposed content textarea, and an explicit two-step apply workflow (Apply button → Confirm Apply). Backs up and logs the apply event.
- **"Repair" button in `WorkQueueView`** — appears for repos at roadmap maturity L0–L2; opens `RoadmapRepairModal`.
- **`onRepairRoadmap` prop on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`OperationType` extended** with `'roadmap-repair-preview'` and `'roadmap-repair-apply'`.
- **Module smoke test** (`Invoke-ModuleSmokeTest.ps1`) — new steps cover loading `Roadmap.Repairer.ps1`, planning repair for missing/complete/informal roadmaps, verifying `previewState` assignments, generating a preview with content validation, and confirming that completed items are preserved in proposed output.
- **API smoke test** (`Invoke-ApiHostSmokeTest.ps1`) — new "Roadmap repair routes (Release 0.9)" step covers `POST /api/roadmap/repair/preview` and `GET /api/roadmap/repair/history`, with contract field validation on the preview response.

### Changed

- ROADMAP.md: Release 0.9 milestones marked complete; "Immediate Next Focus" updated to Release 1.0.

## 2026-03-16 — Release 0.8: Roadmap Contract Audit & Maturity Scoring

### Added

- **`Roadmap.Auditor.ps1`** — new backend module with two exported functions:
  - `Invoke-NormalizeRoadmapContract` — maps a parsed roadmap result (from `Invoke-ParseRoadmapContent`) plus raw content and repo metadata into the stable `RoadmapContract` internal model defined by `roadmap-contract.schema.json`. Detects `hasProductIntent`, `hasReleaseSections`, `hasAcceptanceCriteria`, `hasOutOfScope`, and `releaseCount` from raw markdown.
  - `Invoke-AuditRoadmapContract` — applies the weighted rule pack from `roadmap-audit-rules.json` to a normalized contract, computing a 0–100 maturity score, assigning maturity level (L0-Absent through L4-Orchestration-Ready), and emitting per-rule findings with severity, message, recommended action, and score impact.
- **`GET /api/roadmap/audit`** — returns per-repo normalized contract audit results with TTL cache (300 s). Each entry includes `roadmapState`, `maturityLevel`, `maturityScore`, `pendingCount`, `completedCount`, structural flags, and `auditFindings`.
- **`POST /api/roadmap/audit/scan`** — triggers a fresh roadmap contract audit across all configured local roots; reads raw content, parses, normalizes, and scores each repo.
- **Roadmap audit cache** (`roadmap-audit-cache.json`) — TTL-backed memory + disk cache for roadmap contract audit results, following the same pattern as the doc-audit cache.
- **Operations-log traces** for roadmap audit — `[TRACE]` entries for parse, normalize, score, and audit-rule failures; `[WARN]` logged when audit rules file is missing or a per-repo failure occurs.
- **`RoadmapMaturityLevel` type** — `'L0-Absent' | 'L1-Informal' | 'L2-Structured' | 'L3-Contract-Ready' | 'L4-Orchestration-Ready'` in `frontend/types.ts`.
- **`RoadmapMaturityFilter` type** — `RoadmapMaturityLevel | 'all'` for UI filter state.
- **`RoadmapAuditFinding` type** — per-rule finding shape with `ruleId`, `severity`, `message`, `recommendedAction`, and `scoreImpact`.
- **`RoadmapAuditEntry` type** — normalized contract with audit score, matching `roadmap-contract.schema.json`.
- **`RoadmapAuditIndex` type** — response shape for `/api/roadmap/audit` and `/api/roadmap/audit/scan`.
- **`getRoadmapAudit()` and `triggerRoadmapAuditScan()`** in `frontend/services/apiClient.ts`.
- **`RoadmapAuditModal` component** — per-repo contract audit detail panel showing maturity level badge, 0–100 score bar, structural flags checklist, and expandable per-rule findings with recommended actions.
- **Roadmap maturity mini-badge in `WorkQueueView`** — each repo row now shows a compact L0–L4 maturity badge (from roadmap contract audit) alongside the dispatch readiness badge.
- **Maturity-level filter in `WorkQueueView`** — new filter row lets operators narrow the work queue to repos at a specific roadmap maturity level (L0–L4).
- **"Audit" button in `WorkQueueView`** — opens `RoadmapAuditModal` for any repo with audit data.
- **`onViewRoadmapAudit` prop on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`roadmapAuditIndex` prop on `WorkQueueView`** — roadmap audit data passed in from Dashboard.
- **`OperationType` extended** with `'roadmap-audit-scan'`.
- **Module smoke test** (`Invoke-ModuleSmokeTest.ps1`) — new steps cover loading `Roadmap.Auditor.ps1`, normalizing missing and pending roadmaps, scoring with the rule pack, verifying score range and maturity level assignment, and validating that a well-formed roadmap has no critical findings.
- **API smoke test** (`Invoke-ApiHostSmokeTest.ps1`) — new "Roadmap audit routes (Release 0.8)" step covers `GET /api/roadmap/audit` and `POST /api/roadmap/audit/scan`, with contract field validation on returned entries.

### Changed

- ROADMAP.md: Release 0.8 milestones marked complete; "Immediate Next Focus" updated to Release 0.9.

## 2026-03-16 — Release 0.6: Copilot Task Packaging & Preview Workflow

### Added

- **`Build-CopilotTaskPacket` function** in the API host — constructs a normalized `CopilotTaskPacket` from local roadmap content, doc audit findings, and parsed neighboring context (previous item, section, follow-up candidates).
- **`POST /api/copilot-task/preview`** — new backend route that builds and returns a full `CopilotTaskPacket` for a named repository. Reads the local roadmap file, parses section order, merges in doc audit findings from the cache, generates acceptance criteria, guardrails, and a structured Copilot-ready prompt. Returns a stable `runId` for tracking.
- **`GET /api/copilot-task/history`** — new backend route returning enriched task history with `repoName`, `roadmapItem`, `startedAt`, `completedAt`, and `status` fields per entry.
- **`CopilotTaskPacket` type** — normalized model in `frontend/types.ts` containing: `repoContext`, `selectedRoadmapItem` (with `previousItem`/`nextItem` neighbors), `followUpCandidates`, `docFindings`, `acceptanceCriteria`, `guardrails`, `generatedPrompt`, stable `runId`, and history paths.
- **`CopilotTaskHistoryItem` type** — enriched history shape with `repoName` and `roadmapItem` fields.
- **`CopilotTaskPacketContext`, `CopilotTaskPacketRoadmapItem`, `CopilotTaskPacketGuardrail` types** in `frontend/types.ts`.
- **`previewCopilotTaskPacket(repoName, roadmapPath?)`** in `frontend/services/apiClient.ts`.
- **`getCopilotTaskHistory(limit?)`** in `frontend/services/apiClient.ts`.
- **`CopilotTaskPreviewModal` component** — three-tab modal (Task Packet / Generated Prompt / History) opened from the Work Queue. Shows repo context, selected roadmap item with neighbors, doc findings, acceptance criteria, guardrails, and the full generated prompt with a copy-to-clipboard button.
- **"Preview Task" button in `WorkQueueView`** — appears for `ready`-state repos; opens `CopilotTaskPreviewModal` for the selected repo.
- **`onPreviewTask` prop on `WorkQueueView`** — wired up in `Dashboard.tsx`.
- **`OperationType` extended** with `copilot-task-preview`.
- **Module smoke test** (`Invoke-ModuleSmokeTest.ps1`) — new step validates section-order neighboring context extraction from the roadmap parser.
- **API smoke test** (`Invoke-ApiHostSmokeTest.ps1`) — new "Copilot task packet routes" step covers `POST /api/copilot-task/preview` (with and without `repoName`) and `GET /api/copilot-task/history`, with packet field validation when the route succeeds.

### Changed

- ROADMAP.md: Release 0.6 milestones marked complete; "Immediate Next Focus" updated to Release 0.7.

## 2026-03-16 — Release 0.5: Documentation Audit & Dispatch Readiness

### Added

- **`backend/config/doc-standards.json`** — machine-readable documentation standards defining required root files (README.md, LICENSE, CONTRIBUTING.md, CHANGELOG.md), README minimum length (300 chars), and recommended README sections (Installation, Usage, Contributing).
- **`backend/modules/docaudit/DocAudit.Scanner.ps1`** — new module with `Invoke-AuditRepoDocumentation` and `Invoke-AuditRepoScan` functions. Scans repos against doc standards, checks README quality, and computes a `DispatchReadiness` state per repo.
- **`DispatchReadiness` type** — six states: `ready`, `needs-doc-standardization`, `missing-roadmap`, `roadmap-complete`, `parse-error`, `blocked`.
- **`GET /api/docs-audit`** — returns per-repo dispatch readiness audit results with TTL cache (300 s).
- **`POST /api/docs-audit/scan`** — triggers a fresh documentation audit scan across all configured local roots.
- **`WorkQueueView` component** — new "Work Queue" primary tab in the dashboard. Shows all repos ranked by readiness priority, with readiness badges, per-finding severity labels (`critical`/`warning`/`info`), expandable findings panels with recommended actions, and filter buttons for each readiness state.
- **Dispatch readiness badge in Repository Grid** — each repo row now displays a `DispatchReadiness` badge when docs-audit data is available.
- **Readiness filter in Repository Grid** — new "Readiness" dropdown filters the grid by dispatch readiness state.
- **`DocAuditEntry`, `DocAuditIndex`, `DocFinding` types** in `frontend/types.ts`.
- **`getDocsAudit()` and `triggerDocsAuditScan()`** in `frontend/services/apiClient.ts`.
- **CI: doc-standards.json integrity check** — new CI step validates `doc-standards.json` structure on every PR/push.
- **Smoke tests for doc audit scanner** — `Invoke-ModuleSmokeTest.ps1` covers `ready`, `blocked`, `needs-doc-standardization`, `missing-roadmap` classifications.
- **API smoke tests for docs-audit routes** — `Invoke-ApiHostSmokeTest.ps1` covers `GET /api/docs-audit` and `POST /api/docs-audit/scan`.

### Changed

- Dashboard adds a **tab bar** (`Repository Grid` | `Work Queue`) at the top of the main panel; Work Queue tab shows a badge with the count of ready-for-dispatch repos.
- `reposWithRoadmap` enrichment in `Dashboard.tsx` now also merges `dispatchReadiness` from the docs-audit index into each repo record.
- `OperationType` extended with `docs-audit-scan`.
- ROADMAP.md: Release 0.5 milestones marked complete; "Immediate Next Focus" updated to Release 0.6.

## 2026-03-07

- Reorganized docs into architecture/planning/reference/operations/archive.
- Added `.github` governance scaffolding (templates, CODEOWNERS, CI).
- Added repository policy files (`CONTRIBUTING`, `SECURITY`, `SUPPORT`, `CODE_OF_CONDUCT`).

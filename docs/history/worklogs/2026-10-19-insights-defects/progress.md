# Insights defects: registry and fixes — 2026-10-19

Handoff for the next session. Read `AGENTS.md` first; this log is evidence,
not authority. Revalidate every state claim below against GitHub before acting.

## Goal

Preserve the seven defects the 2026-10-19 Insights investigation confirmed
(previously only in gitignored `output/insights-defects-20261019/findings.md`),
give the repository a durable defect registry, and fix what a defect pass can
fix without changing the live runner or Release 4.1 order.

## State at handoff

| Item | State |
| --- | --- |
| Defect registry | Merged. PR #345 (`b7de0e2`): `AGENTS.md` "Defects" section, Copilot mirror, bug-report and PR templates, deferred-work back-links. Labels `bug` plus `triage:active-release`, `triage:deferred` or `needs-triage` |
| Issues #338–#343 | Fixed on branch `fix/insights-defects`, PR #346, head `85b4971` at handoff plus this worklog commit. CI green on `85b4971` (smoke 9m15s, claude-review no issues). Open, awaiting the operator's merge; `Fixes #N` closes them on merge |
| Issue #344 | Open, `triage:deferred`. Not fixable as a defect: the runner writes no phase field. Findings are in the issue comment |
| PR #330 | Closed unmerged by the operator's decision. Its only unique commit, `82370d1`, deleted 18 governance and evidence files and renamed `standards/roadmap/` to `spec/roadmap/`. Branch `proof/delivery-loop` is kept on the remote |
| Main checkout | `F:\Development\GitHubRepoManagement` is on `main` at `416fe88`, behind `origin/main`, with the operator's own uncommitted `backend/config/settings.json` and `scripts/Invoke-ApiContractTest.ps1`. That checkout is the live service: updating it is a deploy, so leave it to the operator (OQ-16) |
| Worktrees | `F:\Development\GitHubRepoManagement-fixes` (branch `fix/insights-defects`; `node_modules` is a junction to the main checkout's). Remove it after #346 merges: `git worktree remove ../GitHubRepoManagement-fixes` |

## What #346 changes

- **#339:** `Sync-AgentRunFromRunnerOutcome` and `Get-AgentRunRunnerPatch` in `backend/modules/agent-runs/AgentRuns.ps1`. `Invoke-AgentRunAutoClose` calls the sync first, locally.
- **#340:** `Get-RunnerRunOutcomeSummary` in `backend/modules/execution/Execution.Ledger.ps1`. `GET /api/execution/metrics` gains `runnerRuns` and `basis`; `errorRatePct` is `null` with no sample.
- **#341, #340 (UI):** `frontend/components/InsightsView.tsx` "Runner Failures (14d)" and Avg Active Run "—"; nullable fields in `frontend/types.ts` and `frontend/services/apiClient.ts`.
- **#338:** `frontend/components/AgentRunSheet.tsx` portals to `<body>`, closes on a backdrop click, and shows `outcomeDetail`.
- **#342:** `backend/api-host/Start-RepoManagementApiHost.ps1`, `Get-PortfolioTrendSeedPayload`: removed the outer `@()`.
- **#343:** `frontend/components/ChangeHistoryPanel.tsx` is now "Commit Activity", with no contributor count and a separate count of commits the product made.
- New gate: `tests/Test-InsightsTruth.ps1`, registered in `scripts/Invoke-TestSuite.ps1`.

## Validation performed

- `pwsh ./tests/Test-InsightsTruth.ps1 -FailOnError`: 31 passed, 0 failed.
- `npm run test:unit -- components/InsightsView.test.tsx components/AgentRunSheet.test.tsx components/ChangeHistoryPanel.test.tsx` (run from the repository root; the script runs inside `frontend/`, so paths are relative to it): 25 passed.
- `npx tsc --noEmit -p .` in `frontend/`: clean. ESLint on the changed files: 118 warnings, the same as `main`.
- `pwsh ./scripts/Invoke-LintGate.ps1`: PASS, 418 findings against baseline 419. `pwsh ./tests/Test-FixtureIsolation.ps1 -FailOnError`: PASS.
- New functions run against a temporary copy of the live `output/` (live data untouched): runner 14d total 5, failed 4, 80%. Stuck records: SystemDashboard `20261018-122835-b3aca44d` → `failed`; FreshStartFamily `20261017-181025-83010e21` → `failed`; FreshStartFamily `20261017-200105-36f5bb14` → `blocked` (awaiting review of `b19eae4`). Trend seed 62 → 62.
- Module smoke and API-host smoke were not run locally (module smoke fails in a worktree); CI ran both green on `85b4971`.

## Decisions

- GitHub Issues is the defect registry; `deferred-work.md` stays the roadmap's deferral list. A triage label adds no roadmap scope.
- #343: product commits are counted as runner runs that recorded a `commitSha`. The portfolio index cannot attribute individual commits.
- #344: not patched by inference. Honest progress needs the live runner to write `phase` and `phaseEnteredAt`; that belongs to the deferred lane-tile item and needs its own reviewed change.

## Next agent task list

Take these in order and skip any already done. Check first: `git fetch origin`, `gh pr list --state open`, then `gh issue list --label bug --state open --json number,title,labels`.

1. **If #346 has merged:** confirm issues #338–#343 closed with the PR linked. Remove the fixes worktree. Do not restart the service or update the main checkout; that is OQ-16.
2. **If #346 is still open:** stop. Merging is the operator's call. Do not open a second review PR beyond the cap of two in `AGENTS.md` and memory.
3. **After OQ-16 is recorded:** verify on the live host that `GET /api/agent-runs` lists no 2026-10-19 run as `dispatched`, and that `GET /api/execution/metrics` returns `data.runnerRuns` with `basis`. Record the result on #339 and #340. Loopback callers use https, `-SkipCertificateCheck` and `X-Api-Key`.
4. **Release 4.1 Current focus** (`ROADMAP.md`): take the first open item that is agent-executable and not in flight. At handoff the first three are `built`. The candidates are Lane 0.22 slice 2 (board, controls, dispatch refusal) and "Record the outcome of every decision (loop step 7)". Check open PRs and the `feat/roadmap-pilot-automation` worktree for in-flight work before choosing.
5. **Constraint for the weekly delivery report item:** compute agent-run failures from runner summaries (`Get-RunnerRunOutcomeSummary`), never from the lane ledger alone (#340).
6. **Leave alone unless the operator asks:** #344 (deferred); the remote branch `proof/delivery-loop`; `output/insights-defects-20261019/findings.md`, now redundant with the issues.

## Continuation prompt

Continue from `docs/history/worklogs/2026-10-19-insights-defects/progress.md`. Re-read `AGENTS.md`, fetch origin, and check the state of PR #346 and issues #338–#344 before acting. Then work the "Next agent task list" in order, recording exact check results on the issues or PRs they verify.

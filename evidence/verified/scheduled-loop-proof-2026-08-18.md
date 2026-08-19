# Scheduled-Trigger Loop Proof — 2026-08-18

**Closes:** the scheduled-trigger half of Release 3.1's full-loop proof (the
manual half: [full-loop-proof-2026-08-15.md](full-loop-proof-2026-08-15.md))
and the Release 2.8 claude-run residual (now proven three times: two manual
runs 2026-08-15, one scheduled run today).

**Operator:** benfu, authenticated session. **Host:** operator-run api-host on
`127.0.0.1:7099` (current `main`).

## The chain, every step through the product

| Step | Actor | Artifact |
| --- | --- | --- |
| Package | `POST /api/automation/package-run` (Invoke-ScheduledRoadmapPackaging) | run `pkgrun-20260818-221739-9a5e240b` → 1 packaged, 57 skipped; stopped at `pending-approval` by design |
| Curate | Operator, through the product | `INcendiary` favorited with reason (clean current clone, bounded top item); the first subject un-favorited with the guards' refusal recorded |
| Approve + dispatch | `POST /api/automation/packages/approve {dispatch:true}` | packet `pkt-20260818-222015-a98b294a` → run `20260818-222029-43de6f1f`, runner-presence gate satisfied by a live heartbeat |
| Claim → implement | Runner (poll mode) → headless `claude` on INcendiary | a five-state-tested schema validator; the repo's own gates (`export_public_data`, `validate_public_data`, `validate_source_of_truth`) run clean |
| Completion | On the feature branch | agent flipped the checkbox in its commit; the runner's completion pass read `already-complete` — the M4 idempotent case, live |
| PR | Agent-opened; **`approve-push` then live-fired its idempotent path** | `prAlreadyExisted: true`, `prUrl` recorded in the run summary — [xfaith4/INcendiary#7](https://github.com/xfaith4/INcendiary/pull/7) |
| CI | GitHub Actions on INcendiary | `success`; PR `OPEN CLEAN` |
| Merge | **Deliberately human** — awaiting the operator | the approval boundary the scheduled path exists to preserve |

## The refusal that came first, and belongs in the record

The initial subject (`2026MiddleEastWar`, value 90) was refused twice in one
claim: `-SyncMain` declined to move `main` under the operator's uncommitted
local changes (`working-tree-dirty`), and the runner refused to branch from a
clone provably behind its remote (`stale-base`, remedy named). Run
`20260818-221840-9bfa0189` records both. On 2026-08-11 this path stranded six
dispatches into an empty room; today it met unsafe ground and said no, by
name. That contrast is the point of everything built since.

## Also verified in this batch (same session)

- **Release 2.1** signed off against the live store: 20,147 maturity rows /
  20 captured days / schema v2 / native P/Invoke, queried directly.
- **Release 2.3 Phase 2, 7-day window** closed by accrual (`availableDays: 20`).
- The 3.5 scope filter observed live: 58 in-scope of ~75 scanned in the full
  assessment this proof ran on.

## Remaining in the batch (operator-only)

- Merge of INcendiary PR #7 — the operator's explicit action.
- The elevated (UAC) service batch — staged script, declined once, relaunchable.
- The copilot live run — blocked on `gh auth login` (keyring OAuth expired).
- Visual sign-offs and screenshots.

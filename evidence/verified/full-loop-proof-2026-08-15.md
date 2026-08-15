# Full-Loop Proof — 2026-08-15

**Closes:** Release 3.4's proof milestone (manual trigger) and the manual half of
Release 3.1's full-loop proof. The scheduled-trigger half of 3.1's proof remains
open — the scheduled path deliberately stops at `pending-approval`, and no
scheduled packaging ran today.

**Operator:** benfu, authenticated session (local `claude` + `gh` keyring).
**Host:** operator-run api-host instance on `127.0.0.1:7099` (today's code; the
7071 service runs an older build and was not touched).

Two runs. Run 1 closed the loop but the nested agent performed steps 8–12 with
its own `git`/`gh` (this repo's CLAUDE.md authorizes any Claude session to run
the merge loop, and the agent read it); run 2 pinned the agent with a
stop-after-commit contract, so steps 8–12 ran through the product's routes.
Both are recorded because each proved different things, and because run 1's
overreach is itself a finding.

---

## Run 2 — the route-driven circle (run `20260815-060711-b3853924`)

The item: Lane 0.7, *"Sanction the external-archive pattern in the standard"* —
documentation across `standards/roadmap/ROADMAP_TEMPLATE.md`, its
`spec/roadmap-contract/` twin, and `docs/reference/roadmap-contracts.md`.

| # | Step | Performed by | Artifact |
| --- | --- | --- | --- |
| 1 | Select item | Operator queued via `Add-RoadmapTaskToQueue.ps1` | queue line + summary `20260815-060711-b3853924` |
| 2 | Sync main | Runner `-SyncMain` | runner log: `'main' is already at the remote tip` (`current`, allowed no-op) |
| 3 | Branch | Runner | `roadmap/20260815-060711-b3853924` |
| 4 | Implement | Nested `claude` (headless), in scope | 3 files, both template copies kept byte-identical |
| 5 | Verify | Runner | `verifyResult: passed` |
| 6 | **Completion commit** | **`Add-RoadmapCompletionCommit` (M4)** | **`312ec82 docs(roadmap): record completion — …` on the feature branch** |
| 7 | Work commit | Runner | `4a04dfb` |
| 8 | Push | **`POST /api/roadmap-agent/approve-push`** | `pushed: true` |
| 9 | **Open PR** | **same call (M3)** | *"Branch pushed to origin **and PR #142 opened**"* — `prUrl` recorded in the run summary |
| 10 | CI / merge | CI `success`; PR `CLEAN`; operator merged (the designed explicit action) | [PR #142](https://github.com/xfaith4/GitHubRepoManagement/pull/142), merged 2026-08-15T10:29:50Z |
| 11 | **Sync main** | **`POST /api/git/sync-default-branch`** | `state: behind; synced: true` — `dc55b62` → `a82a494`, a real fast-forward |
| 12 | **Cleanup** | **`POST /api/git/cleanup-branch` (M5)** | `deleted: true; remoteDeleted: true` at merged head `312ec823`; `ls-remote` confirms the remote ref gone |

**Completion through the PR, verified on `main`:** the item reads `[x]` at
`ROADMAP.md` after the sync — the checkbox flip merged as part of #142, written
by the product on the branch, never on a default branch.

## Run 1 — the loop closes, and the agent out-drives the product (run `20260815-051219-0ca3949d`)

The item: Lane 0.8's *"P1 — PSSA correctness micro-batch (12 findings, low
risk)"*. Steps 1–7 identical in kind to run 2 (sync `current`, branch, implement,
verify passed). Then the nested agent — reading this repo's CLAUDE.md, which
durably authorizes the monitor-to-green-then-merge loop — pushed, opened
[PR #140](https://github.com/xfaith4/GitHubRepoManagement/pull/140), watched CI,
merged on `CLEAN`, synced `main`, and deleted both branches itself.

Two guards proved themselves live during this run:

- **The completion-commit guard (M4) fired in production.** The runner, resuming
  after the agent had already merged and switched the checkout back to `main`,
  refused the completion edit: `on-default-branch — completion travels through a
  pull request, never directly onto a default branch`. Recorded verbatim in the
  run summary.
- **The stale-queue backlog nearly executed itself.** The first runner launch
  claimed a task queued 2026-08-13 against PhotoToolboxv2 — the head of the
  retry-loop backlog the 2026-08-14 UI review documented. Stopped before the
  nested agent launched; PhotoToolboxv2 restored (branch deleted, `main`
  checked out); all four stale summaries cancelled with a triage note. Release
  3.5's queue-dedupe milestone now has live evidence.

## Findings the drive produced (fixed same-day)

1. **The trace never read the run summary's `prUrl`** — so even a route-driven
   queue-runner item refused write-back as `no-pull-request`, its evidence one
   file away. Fixed in [PR #141](https://github.com/xfaith4/GitHubRepoManagement/pull/141)
   (merged): the summary joined as a fourth `prUrl` source, reproduced in smoke,
   assertion shown to fail pre-fix.
2. **`POST /api/roadmap/dispatch/execute` hardcodes `dispatchTarget: 'copilot'`.**
   The wizard's local-claude enqueue has no one-call route; the queue-writer
   script is the operator surface. The runner's gh-token guard correctly blocked
   the unintended copilot dispatch (run `20260815-050740-5e127a98`, `blocked`).

## Named residues (open, not blockers)

- **Write-back's merge-evidence gate refuses `no-validation-evidence` for both
  runs.** Correctly: no artifact recorded the Actions result, because the
  merge-readiness evaluation (`/api/merge-readiness/{repoId}/evaluate`) resolves
  through the operations index and this repo is deliberately outside the
  portfolio root. For indexed repos the intended chain — evaluate → snapshot →
  write-back — is available; proving it end-to-end belongs to a drive on an
  indexed managed repo.
- **The scheduled-trigger half of 3.1's proof** — the scheduled path stops at
  `pending-approval` by design; a scheduled packaging run followed by an
  operator approval is still to be recorded.
- The operator performed the merge (`gh pr merge`, the designed explicit
  action) and the switch back to `main` before the sync route; everything else
  was product-performed with approval as an input.

# Proof of value — 2026-10-16 to 2026-11-15

Owner decision, 2026-10-16: until 2026-11-15 the single objective is to prove
the product delivers merged improvements to OTHER repositories for less
operator time than doing them by hand. Targets: at least five meaningful,
externally verified merged PRs initiated through the product; at least ten
repositories legitimately ready for automated work; average total operator
effort at or below 20 minutes per merged improvement, rejected proposals
included; an auditable history including failures and rejections. Targets are
not incentives: a manufactured PR or a readiness rule loosened to move a count
is a failure of this trial, not progress on it.

**Status of this file.** The baseline below was reconciled by an agent from the
product's own ledgers and GitHub on 2026-10-16. It is not operator-verified.
Per-decision records live in the delivery ledger
(`output\delivery\delivery-ledger.jsonl`, read through
`GET /api/delivery/summary`); this file holds the baseline and the judgements
made about them.

## Baseline — what the product has delivered so far

Scope: 658 pull requests created 2026-03-01 to 2026-10-16 on xfaith4
repositories other than this one.

| Class | Created | Merged |
| --- | --- | --- |
| Verified product-originated | 11 | 10 |
| Probable (marker only, no record) | 1 | 1 |
| Manual or unattributed | 646 | 572 |

A PR is **verified** only when a product record names it (a runner `prUrl` or
`agentTaskUrl`) or its head branch is a product branch (`roadmap/<runId>`,
`roadmap-repair/*`). All 11 were created in August (4) and September (7); none
since 2026-09-07. Nine are roadmap-document changes. Four merged with failing
checks; one (SystemDashboard #127) is still open with failing checks.

Corrections to earlier claims: the runner history names 11 PRs, not 3 — eight
dispatched Copilot runs carry the PR in `agentTaskUrl`, not `prUrl`. The
`agent-runs` path is not a separate delivery road; every non-smoke record there
points back at a runner run.

### Why runs failed

80 non-smoke runner runs; 51 failed, blocked or refused and 10 were cancelled.

| Cause | Runs | Latest |
| --- | --- | --- |
| No roadmap file found | 17 | 2026-05-29 |
| `gh agent-task create` failed with no detail, or `gh` missing | 12 | 2026-08-08 |
| GitHub auth or token conflict | 10 | 2026-09-06 |
| Runner restarted mid-run (orphaned) | 6 | 2026-10-15 |
| No actionable roadmap item | 4 | 2026-08-11 |
| Clone behind its base | 2 | 2026-09-19 |

### Operator involvement

Operator time has never been recorded: `operatorMinutes` is null on every
Release 3.7 trial record. The verification log's last entry is 2026-08-19.

### Readiness

Ready-for-work: 1 of 62 (PhotoToolboxv2). Ready requires a sufficient execution
contract, read from one release block (`## Release N - Title` with a goal, out
of scope, acceptance criteria and a validation plan). 27 of 35 roadmaps with
pending work have no such block. Three L4 repositories pass the contract and are
held only by structure findings (LICENSE, CI, tests). The execution queue's own
"ready" (28) is a different measure that ignores the contract.

The legitimate road to ten is adding a real release block to GitHub-backed
repositories that already have tests or CI. Loosening the contract, accepting
generator stubs, or downgrading the structure findings would move the count
without the product being able to do safe useful work, and is ruled out.

### Blockers seen on 2026-10-16

- A lane reads "running" on a run the runner abandoned on 2026-10-15; nothing
  releases it.
- The execution ledger records "success" for a CryptoAdvisor run the runner
  marked failed and for which GitHub has no PR.
- Every runner restart orphans the run in flight.

## First controlled candidate — 300PixelLED_2812B (2026-10-16)

**Step 2 failed on the product's own next action.** The deterministic roadmap
repair preview (`20261016-030747-e78c281e`) proposed replacing a 466-line,
hand-maintained roadmap with 111 lines: all 53 checklist items kept, but the
from-scratch rebuild guide, every Track and Phase section and the Track D spec
dropped, and the product intent replaced with template text ("provides tooling
and workflows for managing repositories"). Opening that as a PR would harm the
repository. The recommendation is **reject**; the decision is the owner's to
record in the console.

The same improvement, done properly, needs authored content, so it was
dispatched to an agent instead: the product's guided-improvement prompt,
tightened to forbid deleting existing content, dispatched to Claude through
`POST /api/roadmap/dispatch/execute` as run `20261016-031015-cc34298c`. The
dispatch approval was given by the implementing agent under the owner's
written instruction naming this repository as the controlled candidate, so it
carries no operator time.

## Defects fixed on the way (branch `proof/delivery-loop`)

- The service runs as LocalSystem with no git identity, so a console-opened
  repair PR could never have committed. Commits now use the checkout's own
  identity or the token owner's GitHub noreply address.
- A failed commit left the target clone with the rewritten roadmap staged. The
  commit step now restores the file, removes its empty branch and returns to
  the start branch.
- The repair modal never sent the proposal, so its PR button could only build a
  dry-run plan. It now opens the PR with the operator-edited text.
- Preview and submit found a repository only through a roadmap cache younger
  than its TTL; past it, a repository with a ROADMAP.md previewed as "No roadmap
  file found". Paths now resolve from the cache at any age, then the portfolio
  index.
- The modal's History tab requested a path without the API prefix and was
  always empty.

## 2026-10-17 — second day: what the loop actually did

**The 300PixelLED_2812B dispatch did not deliver.** Run
`20261016-031015-cc34298c` was closed as `orphaned` at 2026-10-17T05:17Z when
the runner was restarted; the interactive Claude session it had opened was
never attended. The runner had left the clone checked out on
`roadmap/20261016-031015-cc34298c`, so the owner's next commit there (a
12-file playlist feature, 2026-10-17 01:23) landed on the product's branch
and was pushed to it. FowlingScorecard, CryptoAdvisor and INcendiary were
found on stale `roadmap/<runId>` branches for the same reason. Remedy for
the owner: `git -C F:\Development\20_Staging\300PixelLED_2812B switch main`
and merge or cherry-pick `7a98410` there; the runner now returns every clone
to its start branch (see fixes below).

**The working tree is the live product.** PR #330 (owner commit `82370d1`)
moved `standards/` to `spec/` and deleted the release-3.7 fixtures. With that
branch checked out, the live service read PhotoToolboxv2 as `L0-Absent`,
score 0 (`POST /api/roadmap/dispatch/check`, 18:03), and the CI run for
PR #330 failed six gates on the missing paths. A branch from `origin/main`
checked out at 18:04 restored the verdict to `L3-Contract-Ready`, score 84.
Six files reference the old path; the restructure needs them updated or
dropped before PR #330 can merge.

**GitHub access (least privilege check, no token shown).** The product and
`gh` both use the Machine-scope `GITHUB_TOKEN`, a fine-grained PAT expiring
2026-12-06. It resolves to `xfaith4` with `push: true` and `admin: true` on
every repository probed (PhotoToolboxv2, FreshStartFamily, 300PixelLED_2812B,
GenesysAudits, SystemDashboard, this one). Deficiency: it is an admin token
where push plus pull-request would do; the keyring OAuth token (`repo`,
`workflow`) is the one `gh agent-task` needs and is shadowed by the
environment variable.

**Readiness, investigated (index of 2026-10-15, 62 repositories).**

| Lifecycle state | Repositories | What holds them |
| --- | --- | --- |
| needs-roadmap-repair | 28 | 25: no release block (goal, pending milestone, out of scope); 2: no runnable check named; 1: no sized phase |
| needs-roadmap | 16 | no ROADMAP.md at all |
| no-checklist | 8 | prose roadmap, no `- [ ]` items |
| needs-structure | 6 | contract fine; held by LICENSE / CI / tests warnings (3 are L4, 2 of those not on GitHub) |
| ready-for-work | 1 | PhotoToolboxv2 |
| running | 1 | FowlingScorecard, on a run the runner abandoned 2026-10-15 |
| curated-out / needs-readme | 2 | by owner curation; no README |

Two findings change what "ten ready" means. First, the one ready repository
is not safely workable: its roadmap items are truncated mid-sentence in the
file itself (owner commits of 2026-10-14) and it has no `tests/` directory,
so the product's own verification (`pytest`) collects nothing. Second, the
structure gate holds repositories on `LICENSE:warning`, which says nothing
about whether an agent can work safely there; dropping LICENSE, SECURITY and
CONTRIBUTING to advisory would move the six `needs-structure` repositories
without loosening anything that protects the work. That rule change is the
owner's call (steering §6) and is proposed, not made. The honest road to ten
remains a real release block in GitHub-backed repositories that already have
CI and tests: CupHandleDetectionv2, SystemDashboard, UnifiedAIToolbox,
MusicLibrary_v2, FreshStartFamily, Genesys.Core, Genesys.Core_AuditLogsApp,
GenesysAudits, GenesysCloud-API-Explorer_v3, incendiary-web.

**First dispatch through the product: FreshStartFamily, run
`20261017-181025-83010e21`.** Chosen because its clone was clean, its CI
and tests are real, and its top-value item is a precise bug with a named
check: inferred birth citations borrow another person's birthplace
(`buildFallbackFactInferences`, ROADMAP §5.4). The clone was moved to
`staging` (the repository's integration branch; feature work may not target
`main`) and the item was queued with `POST /api/roadmap/dispatch/execute` at
18:10:25; the runner claimed it ten seconds later and opened a Claude session
on `roadmap/20261017-181025-83010e21`. The session worked for ninety seconds
(36 turns) and then stalled on a `PowerShell` tool call: the permission
envelope allowed `Bash` only, and on Windows the agent reaches for PowerShell
first. At the time of writing the session is still waiting in the runner's
terminal. Operator time so far: 0 minutes (every step was the agent's, under
the owner's written instruction of 2026-10-16).

**Fixes (branch `proof/first-delivery`, from `origin/main` plus `b4b923d`).**

- The permission envelope writes every shell rule for Bash and PowerShell
  (`ConvertTo-ClaudePermissionSetting`); a packet without shell denies both.
- The runner records the branch the clone was on and returns to it when the
  run ends, success or failure, leaving the work branch intact; a dirty tree
  is never switched (`Restore-RunnerStartBranch`).
- `POST /api/execution/sync` releases a lane whose run summary says
  `failed`, `refused` or `cancelled` (`Sync-LedgerFromRunHistory`): retry
  counted, join keys cleared, one `released` history record; a missing or
  still-running summary changes nothing.
- All three are asserted in `tests/Test-DeliveryLoop.ps1` (100 assertions).
  The running runner and the service pick them up only after a restart.

**What the owner must do to reach the first PR.** Either answer the pending
PowerShell prompt in the `claude` window (once per shell call until the
restart), or close that session, restart the runner task so it loads the
fixed envelope, and queue the same item again; then approve the push from
the console (`POST /api/roadmap-agent/approve-push`), and change the PR's
base to `staging`, which the product does not yet know how to choose.

## 2026-10-17 evening — owner decisions applied, first run closed

**Owner decisions (2026-10-17).** Headless execution is authorized for this
controlled trial once credential isolation and workspace safety are verified;
operator approval stays on PR publication and merge. The product must stop
switching branches in the owner's working clones (run-owned workspaces are a
prerequisite for broader unattended execution), must keep GitHub write
credentials out of the agent's environment, must take the PR base from
explicit repository policy, and may treat LICENSE/SECURITY/CONTRIBUTING as
advisory without calling a repository ready on that alone. Operator time is
to be recorded from here on.

**The stalled run was closed, not approved.** PR #331 merged at 23:39Z. The
Claude session for run `20261017-181025-83010e21` was closed at 23:43Z with
its transcript preserved beside the run summary
(`output/roadmap-task-history/runs/20261017-181025-83010e21.claude-transcript.jsonl`);
it had changed no files. The runner recorded the run `failed` ("exit code
-1"), the FreshStartFamily clone was returned to `staging` by hand (the old
runner code was still loaded), and the empty run branch was kept. The
dispatch is recorded in the delivery ledger (`output/delivery/delivery-ledger.jsonl`,
first record) with operator seconds unmeasured and the reason why.

**Fixes (branch `proof/second-delivery`, from `main` after #331).**

- Run-owned workspaces: the runner creates a git worktree of the clone under
  `output/agent-workspaces/<runId>` on the run branch and the agent works
  there. The clone's checkout, index and uncommitted files are never touched;
  absolute clone paths in the prompt and the completion edit are remapped
  into the workspace; a clean workspace is removed when the run ends and a
  dirty one is kept at a recorded path. The clone is never switched as a
  fallback (`New-RunWorkspace`, `Remove-RunWorkspace`).
- Credential boundary: the runner refuses to launch an agent while
  `GITHUB_TOKEN` or `GH_TOKEN` is in its own environment, records the verdict
  on the run and in the heartbeat (names only), and `autoPush` is off for
  every provider, so the push and the PR happen only through the host's
  approve-push path with the host's token (`Test-RunnerCredentialIsolation`).
- PR base from policy: `backend/config/repo-policies.json` names
  FreshStartFamily → `staging`; `Resolve-RepoPullRequestBase` uses that, else
  the clone's `origin/HEAD`, validates the branch exists on origin, and
  refuses publication otherwise. Both PR-opening paths pass it.
- Ownership on restart: the orphan sweep leaves a run alone while its
  recorded runner process is alive; only a dead runner's run is closed.
- 42 new assertions in `tests/Test-DeliveryLoop.ps1` (131 total).

**Credential findings.** The runner task passes `-ClearInheritedGitHubToken`,
so the agent's shell sees no `GITHUB_TOKEN`; the heartbeat now says so. What
the agent can still reach, running as the owner: the keyring OAuth `gh`
credential (`repo`, `workflow`), held back only by `Bash(gh:*)` /
`PowerShell(gh:*)` deny rules, and the owner's git credential helper for
`git push`, held back by the same kind of rule. Full separation needs the
agent in a different Windows account or a sandbox; that is the residual
risk of this trial and is not closed by these changes. Minimum credentials
per operation: agent run, none; push and PR open, Contents and Pull requests
write on the target repository (the host's token, today an admin-scoped PAT);
merge, the owner; Copilot dispatch, the keyring OAuth token with `repo`.

**300PixelLED_2812B recovery (owner's clone, not touched by the product).**
The clone is on `roadmap/20261016-031015-cc34298c`, which holds commit
`7a98410` (12 files, playlist feature) on top of `main`, pushed to origin.
Safe steps: `git switch main`, then `git merge --ff-only roadmap/20261016-031015-cc34298c`
(it is one commit ahead, so this fast-forwards), then `git push origin main`
and delete the run branch locally and on origin. Nothing is lost at any step;
the run branch can stay until the merge is confirmed.

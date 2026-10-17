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

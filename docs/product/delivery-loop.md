# The delivery loop

Supporting detail for **Release 3.4 — The Delivery Loop Closes**. The roadmap
carries the milestones and acceptance criteria; this document carries the target
workflow, the layer model the milestones are organised by, and the evidence
behind the four gaps.

## The target workflow

```text
ROADMAP ITEM
     |
sync main                     <- step 2   (built, runner opt-in)
     |
create feature branch
     |
implement
     |
test locally
     |
commit  (including the roadmap completion edit)
     |
push branch
     |
open PR                       <- step 7   (missing)
     |
CI / verification
     |
merge PR on GitHub
     |
pull main locally             <- step 10  (missing)
     |
delete branch                 <- step 11  (missing)
     |
record completion as verified
     |
NEXT ITEM
```

Locally and on GitHub, the same loop:

```text
LOCAL                                    GITHUB

main
  |
  +-- feature/phase-12 --push-->  feature/phase-12
                                        |
                                        | Pull Request
                                        v
                                      main
                                        |
                            CI ok / review ok / protection ok
                                        |
                                        v
                                     MERGE
                                        |
                                        v
local main  <----------- pull -------- remote main
```

## What is built, and what is missing

Measured 2026-08-14 against the twelve steps, re-measured 2026-08-15 after
[PR #134](https://github.com/xfaith4/GitHubRepoManagement/pull/134) shipped the
sync operation. Nine are built; three are missing, and **every missing one still
sits at a boundary**.

| # | Step | State |
| --- | --- | --- |
| 1 | Agent receives roadmap task | built — queue, dispatch, prompt refinement, approval state machine |
| 2 | Sync local `main` | built — `Sync-RepoDefaultBranch`, opt-in via `-SyncMain` on the runner, ahead of the freshness gate |
| 3 | Create feature branch | built — `git switch -c` in the runner, `checkout -b` in the PR submitter |
| 4 | Implement, test, document | built — runner launches Claude; `Resolve-VerifyCommand` runs the repo's own suite |
| 5 | Commit locally | built |
| 6 | Push feature branch | built, operator-gated |
| 7 | **Open the pull request** | **missing** for agent runs |
| 8 | CI / verification | built — `MergeReadiness.ps1`, including a `merge-conflicts` blocker |
| 9 | Merge on GitHub | built, explicit operator action |
| 10 | **Sync local `main`** | **missing** — the operation exists; nothing calls it here, and no route exposes it |
| 11 | **Delete the feature branch** | **missing** |
| 12 | Record completion | built, but **ordered wrongly** — see below |

Steps 2 and 10 are the two points where the loop touches local `main`. Step 2 now
syncs, but **only from the runner and only when an operator passes `-SyncMain`** —
there is no route, so the portal cannot ask for a sync. Step 7 is the handoff from
push to pull request: `POST /api/roadmap-agent/{id}/approve` pushes the branch and
returns the message _"Open the PR from GitHub when ready"_, at which point the
operator leaves the product. Step 11 has no implementation of any kind.

**The loop is therefore still an arc rather than a circle, and that is why the
stale-clone defect stayed invisible for so long.** Nothing returns local `main` to
the remote tip after a merge, so "behind" remains the resting state rather than an
anomaly worth reporting — closing step 2 narrowed the window without closing the
circle.

## Layered architecture

Every milestone fits one layer, and the layers are the review surface:

```text
State discovery      ahead / behind / dirty / diverged; PR, checks, merge state
        |
Refusal layer        named unsafe conditions, each carrying a remedy
        |
Operator approval    required today; designed to become skippable per-transition
        |
Transition layer     sync / branch / push / PR / merge / cleanup
        |
Verification         fixture + smoke + CI
```

**Approval is a layer, not a hard-coded step.** It is required for every
transition in Release 3.4, but the transition layer must not assume a human is
present: each transition takes its approval as an input, so a later release can
mark individual transitions trusted and skip the prompt without reopening the
transition itself. Designing it any other way makes automation a rewrite.

## Why completion has to travel through the pull request

`POST /api/roadmap/write-back/apply` is gated on merge evidence, so it runs
_after_ the merge — and its write is a bare `Set-Content` to the roadmap file on
whatever branch happens to be checked out, which at that point in the loop is
`main`. There is no branch, no commit and no pull request anywhere in that path,
so recording completion either leaves an uncommitted edit on `main` or gets
committed straight to it. Either outcome violates the governing invariant.

Moving the completion edit into the feature branch's own commit **changes what
the merge-evidence gate means, deliberately**. It no longer gates _writing the
checkbox_ — that now happens before the merge, like every other change. It gates
**recording the completion as verified** in the write-back ledger, which is the
claim that actually requires proof of a merged pull request. Both intents
survive; only the ordering changes.

## Deferred: automated conflict resolution

When a pull request reports `mergeable: false`, dispatch GitHub Copilot to
resolve it, poll the resulting draft pull request, verify no agent session is
still active, then approve and merge — falling back to **Needs Attention** after
a single recorded attempt.

Every input already exists:

- `MergeReadiness.ps1` emits a `merge-conflicts` blocker from GitHub's own answer
- `frontend/lib/needsAttention.ts` is the surface
- `gh agent-task create` is the dispatch
- the automation scheduler supplies the timer

It is deferred on purpose. **The manual loop has to run smoothly before any of
it is automated**, and two constraints have to be designed for rather than
discovered:

1. `gh agent-task create` needs an OAuth credential the service account
   structurally cannot hold, so dispatch must route through the operator runner
   — the same empty-room problem Release 3.1 gated.
2. The retry counter must be **persisted**. Held in memory, a portal restart
   mid-loop resets it and the loop retries forever.

A further note on shape: `gh agent-task` always creates its own branch and pull
request, so conflict resolution produces a pull request that resolves a pull
request. Merge B into A, then A into `main` — two steps, but each one
reviewable.

## Which engine, and why

Two provider vocabularies already exist and are not interchangeable:

| Axis | Values | Runs where |
| --- | --- | --- |
| Content generation | `auto` / `heuristic` / `anthropic` / `openai` | direct API call from the host |
| Task dispatch | `claude` / `copilot` / `operator-runner` | local runner, or GitHub-side agent |

Decide by **where the work physically has to happen**, not by preference:

- **Local working-tree conflicts go to Claude Code via the local runner.** A
  conflicted merge exists only in the working directory; a GitHub-side agent
  cannot see it.
- **Pull-request-level conflicts go to Copilot**, which operates on a pushed
  branch.
- **Content generation with no working tree** stays on the direct API adapters.

This split is defensible on capability rather than taste, and it matches the
engine-attribution rule from Release 3.1: every surface names the engine that
acted.

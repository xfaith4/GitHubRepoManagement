# Local task runner (Claude Code, Codex and Copilot)

**Release 3.0 — one dispatch model.** The portal enqueues; this runner executes
in your session. That is now true for *both* targets: local Claude Code work and
cloud GitHub Copilot agent tasks. The portal never runs either itself, because a
LocalSystem service holds neither your Claude Code login nor the OAuth credential
`gh agent-task` requires.

Because the portal runs as a LocalSystem service, dispatch is split in two:

1. **Portal enqueues** — "Queue Task" in the ROADMAP modal writes the task to
   `output/roadmap-task-queue.jsonl` (status `queued`).
2. **You run the runner** — `scripts/Invoke-RoadmapTaskRunner.ps1`, in your own
   session (your `claude` + auth), picks up queued tasks and executes them.

With `autoPush` on (the default for local providers) the runner pushes the
branch after a successful result and verification; the PR is opened by the
portal's reconcile tick. With `autoPush` off, the runner stops at
`awaiting-review` as before — review the branch first, then push either
yourself from the shell, or with the ROADMAP modal's **Approve & push** action
(`POST /api/roadmap-agent/approve-push`), which pushes the run's branch to
`origin` and marks the run `pushed`. That path is also where a run lands when a
push is rejected by the remote, so nothing is stranded by a failed push.

## Flow

```text
Portal (SYSTEM service)                You (operator session)
─────────────────────                  ──────────────────────
Preview Task  -> pick next roadmap item
Queue Task    -> output/roadmap-task-queue.jsonl  (status=queued)
                                       Invoke-RoadmapTaskRunner.ps1
                                         claim        (status=running)
                                         git switch -c roadmap/<runId>
                                         claude  (task prompt, in the repo)
                                         result  (<runId>.result.json; missing or invalid => status=failed)
                                         verify  (best-effort: npm test / Invoke-TestSuite)
                                         git commit   (only if there are changes)
                                         status=awaiting-review   <-- STOPS here
                                       you review the branch
                                         -> push yourself, or
                                         -> Approve & push (portal)  (status=pushed)
```

Status flows back to the portal via the existing run summary
(`Get-RoadmapTaskHistory`), so the ROADMAP modal's history shows
`queued → running → awaiting-review → pushed` (or `failed`).

## Running the runner

Run it **as yourself** (not elevated, not the service) — it needs your `claude`
on PATH and your Claude auth:

```powershell
# one pass over the queue, then exit:
pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Once

# keep watching the queue:
pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1

# preview the plan without doing anything (safe):
pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Once -DryRun
```

Options:

- `-Headless` — run `claude -p "<prompt>"` non-interactively instead of an
  interactive session. Tasks that run shell commands may stall on a permission
  prompt headless mode can't answer; pair with `-PermissionMode bypassPermissions`.
- `-PermissionMode <mode>` — Claude Code permission mode (default `acceptEdits`).
- `-PollSeconds <n>` — poll interval for the watch loop (default 15).

## Reviewing and pushing

Each finished task leaves a `roadmap/<runId>` branch with the work committed. The
runner never pushes. When you're satisfied, the quickest path is the ROADMAP
modal: rows in `awaiting-review` show an **Approve & push** button that pushes
the branch to `origin` (using the configured GitHub token when the portal runs
as a service) and moves the run to `pushed`. Only `awaiting-review` runs can be
pushed — anything else is refused with a 409. Or do it yourself from the shell:

```powershell
cd <the target repo>
git switch roadmap/<runId>
# review the diff, run whatever else you want, then:
git push -u origin roadmap/<runId>   # if the repo has a GitHub remote
gh pr create                          # or open a PR
```

For a local-only repo, publish it first (`gh repo create <owner>/<name> --private
--source . --remote origin --push`) before pushing the branch.

## Scheduled packaging feeds the same queue

Release 2.7 Phase C adds a second producer for this queue. `POST /api/automation/package-run`
ranks each favorite / portfolio-candidate repo with a contract-ready (L3+) roadmap,
packages its **top-value** pending item into a task packet, prices it through the
quota guard, and queues it for approval — it never enqueues anything itself.
`POST /api/automation/packages/approve` is the only path from a packet to this
queue: it writes both the `roadmap-task-queue.jsonl` line and the `queued` run
summary the runner claims on, so an approved packet is picked up by exactly the
same runner loop described above.

```text
package-run  -> packet (pending-approval)   [nothing queued]
approve      -> roadmap-task-queue.jsonl + <runId>.summary.json (status=queued)
runner       -> claim -> branch -> claude -> result -> verify -> commit -> awaiting-review
```

Release 3.8 M1 adds the `result` step: the runner reads
`<runId>.result.json`, the structured `ExecutionResult` the agent's adapter
writes, and a headless run whose result is **missing or invalid is recorded as
`failed` by name** rather than committed and marked ready. The CLI's exit code
is recorded but no longer decides the outcome, because an agent that printed
prose and exited 0 used to reach `awaiting-review` with nothing behind it. An
interactive run records its own result, since a person watched the session.

## The work packet and the result (Release 3.8 M1)

Each run now has two structured files instead of one prose prompt:

| File | Written by | Holds |
| --- | --- | --- |
| `output/work-packets/<runId>.workpacket.json` | the dispatch route, or the packaging approval path | objective, scope paths, acceptance criteria, verification commands, permission envelope. Names **no provider** |
| `output/roadmap-task-history/runs/<runId>.result.json` | the provider's adapter | status, changed files, verification outcome, provider session id, usage in the provider's own units |

The packet is gitignored on purpose: an agent editing its own repository must
not be able to commit, and so rewrite, the instructions it was given. The
prompt is **rendered from** the packet, with acceptance criteria copied
verbatim, so the two cannot drift.

A headless run with no result, or an unreadable one, is `failed` with
`no-structured-result` and **nothing is committed**. A queue entry with no
`workPacketPath` — anything queued before Release 3.8 — still runs from its
`prompt` field exactly as before. The runner logs which source it used.

The provider's raw output is kept at `<runId>.claude.stream.jsonl` for
diagnosis. Copying one into `tests/fixtures/providers/` is also how a real
transcript reaches the test suite, which is why no gate needs a recorded one.

Inspect the approval queue with `GET /api/automation/packages?status=pending-approval`.
A packet may be approved only from `pending-approval`, and a dispatched packet is
terminal — re-approving is refused with a 409 rather than dispatched twice.

## Capacity and cooldown (Release 3.8 M2)

One record per provider lives at `output/provider-capacity/<provider>.json`,
holding named windows in **that provider's own unit** — never converted to
tokens — plus a confidence rank and any cooldown. A window with no
`remainingRatio` is valid and reads `confidence: none`: for a subscription whose
allowance is not published, *unknown* is the truth.

When a provider reports a usage limit, the run is **not** failed. Its summary
reads `status: queued` with a `capacityWait` block naming the provider, the
reset time, and whether that time was the provider's or assumed (now + 60
minutes when it gave none). Branch, attempt and provider session id survive
untouched and **nothing is committed**, so the task resumes on the same session
when the window reopens.

The runner then **declines to claim** while a cooldown is live or the single
local execution slot is busy, leaving the entry `queued` and writing no summary
at all. Each refusal is logged with a code — `provider-cooling-down`,
`local-slot-occupied`, `unknown-dispatch-target` — and the heartbeat carries
`providerCooldowns` and `localSlotsInUse`, so a runner that is alive and
deliberately idle never looks stuck. `GET /api/providers` reports each
provider's record, verdict and reason.

Capacity verdicts are **recorded but not enforced**: the reserves are decided
(15% short window, 20% weekly) but the per-task cost estimate is still a guess,
so a verdict can look wrong without blocking work.

## Which provider runs a task (Release 3.8 M3)

A queue entry carries one of four tokens: `claude`, `codex`, `copilot` or
`auto`. The first three name a provider; `auto` is an instruction to choose.

`auto` resolves **at claim time by the runner**, not when the task is queued:
the portal runs as a LocalSystem service holding no provider credential, so
only the operator session can see what is authenticated and what capacity
remains — and capacity moves in between anyway.

Eligibility first, then ranking. Each Stage 1 condition is kept per candidate
whether it passed or failed, so a provider that is never chosen is explainable
without reading a log. The runner writes `selectedProvider` and
`selectionReason` onto the run summary; with nothing eligible the entry stays
`queued` rather than failing.

A provider is selectable only where its CLI is installed, which is detected on
each machine and shown in Settings — never configured in the repository,
because a committed answer about one laptop is wrong for every other install.

## Cloud (Copilot) dispatch runs here too — Release 3.0

The guided-improvement wizard's final step used to call
`Start-GitHubCopilotTask.ps1` inside the API host. That could never succeed from
the service: `gh agent-task create` requires an **OAuth** credential, `gh`
ignores its stored credential whenever `GH_TOKEN`/`GITHUB_TOKEN` is set (the host
sets one for its own GitHub calls), and LocalSystem has no interactive login to
obtain one. The wizard therefore dead-ended after the operator had already spent
the refinement work.

`POST /api/roadmap/dispatch/execute` now enqueues instead, with
`dispatchTarget: "copilot"` on the queue entry, and this runner creates the agent
task in your session:

```text
Portal            -> roadmap-task-queue.jsonl (dispatchTarget=copilot, status=queued)
Invoke-RoadmapTaskRunner.ps1
                     gh agent-task create <prompt> --repo <owner/repo> [--base <branch>]
                     status=dispatched + agentTaskUrl recorded
```

The runner **never branches or commits** for a copilot entry — the cloud agent
owns the working copy. What it records is the task URL, which is the only durable
handle on the run.

Two things block cloud dispatch, and both are refused with a named reason rather
than left to fail at the call:

| Reason | What it means | Fix |
| --- | --- | --- |
| `gh-not-found` | The GitHub CLI is not on PATH. | Install it, or set `GH_CLI_PATH`. |
| `env-token-overrides-oauth` | This shell carries `GH_TOKEN`/`GITHUB_TOKEN`. | `$env:GH_TOKEN=$null; $env:GITHUB_TOKEN=$null`, then re-run. |

A blocked entry is **not** claimed — it stays `queued` so it can run once the
session is fixed, instead of being burned on a session that cannot execute it.

Asking the host to run cloud dispatch in-process (`inProcess: true`) is refused
with a **409 `operator-runner-required`** naming this runner, in both service and
interactive mode. The service check is a heuristic; refusing only when it fires
would bring the failure back the moment it is wrong.

## Is a runner actually running?

The portal enqueues work it cannot execute, so queueing into an empty room used
to look exactly like queueing into a running one. The runner writes a heartbeat
every poll cycle — including idle ones, so it is visible *before* work is queued
— and `GET /api/roadmap/runner` reports it:

```powershell
Invoke-RestMethod http://127.0.0.1:7071/api/roadmap/runner
```

| Field | Meaning |
| --- | --- |
| `state` | `present`, `stale`, or `absent`. Never `present` on an unreadable heartbeat. |
| `secondsSinceBeat` / `staleAfterSeconds` | Age, and the budget derived from the runner's own `-PollSeconds` (so a slow runner is not called dead). |
| `queuedClaude` / `queuedCopilot` | Still-`queued` backlog, split by target — this names *which* runner session is missing. |
| `strandedCount` | Queued work with nothing to pick it up. Zero when a runner is present. |

The roadmap dispatch modal reads this while you review the packet and warns
before you commit to queueing.

### Start it automatically at logon

```powershell
# from YOUR normal (non-elevated) PowerShell:
pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1
pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1 -Uninstall
```

This registers an **interactive, unelevated** logon task — the mirror image of
`Install-PortalWatchdog.ps1`, which demands elevation and registers as SYSTEM.
The installer **refuses** SYSTEM, LOCAL SERVICE and NETWORK SERVICE outright: a
runner registered as a service account installs fine, shows as running, claims
queued work, and fails every task for a credential reason that looks nothing like
the cause.

## Notes

- Copilot dispatch is also reachable directly from an operator shell with
  `Start-RoadmapCopilotTask.ps1 -DispatchMode copilot`, which bypasses the queue.
  That path is unchanged; it already ran as the operator.
- `verify` is best-effort across arbitrary repos (record-only, non-blocking) —
  the `awaiting-review` gate + your review are the real quality check.

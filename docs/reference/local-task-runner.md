# Local task runner (Claude Code and Copilot)

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

Nothing is pushed to GitHub by the runner. It stops at `awaiting-review` so you
review the branch first — then push either yourself from the shell, or with the
ROADMAP modal's **Approve & push** action (`POST /api/roadmap-agent/approve-push`),
which pushes the run's branch to `origin` and marks the run `pushed`.

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

Inspect the approval queue with `GET /api/automation/packages?status=pending-approval`.
A packet may be approved only from `pending-approval`, and a dispatched packet is
terminal — re-approving is refused with a 409 rather than dispatched twice.

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

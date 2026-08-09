# Local task runner (Claude Code)

The portal dispatches roadmap work to **Claude Code on the local repo**, not to
GitHub Copilot in the cloud. Because the portal runs as a LocalSystem service (it
can't be your authenticated Claude Code), dispatch is split in two:

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
runner       -> claim -> branch -> claude -> verify -> commit -> awaiting-review
```

Inspect the approval queue with `GET /api/automation/packages?status=pending-approval`.
A packet may be approved only from `pending-approval`, and a dispatched packet is
terminal — re-approving is refused with a 409 rather than dispatched twice.

## Notes

- Copilot dispatch is still available for repos that live on GitHub, behind
  `Start-RoadmapCopilotTask.ps1 -DispatchMode copilot`, but it is no longer the
  default.
- `verify` is best-effort across arbitrary repos (record-only, non-blocking) —
  the `awaiting-review` gate + your review are the real quality check.

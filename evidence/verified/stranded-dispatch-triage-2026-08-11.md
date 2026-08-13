# Stranded dispatch triage — the six entries behind Release 3.1 milestone 1

**Window:** queued 2026-08-01 02:19 → 2026-08-08 16:07 (local). Cancelled
2026-08-11 19:22:59 (local), all six in one action.
**Source of truth:** `output/roadmap-task-queue.jsonl` (append-only) joined to
`output/roadmap-task-history/runs/<runId>.summary.json`.
**Verified:** 2026-08-13, before shipping the presence gate.

## What was stranded

Six queue entries sat at `status: queued` with no operator runner ever having
reported in. `POST /api/roadmap/dispatch/execute` returned 200 for every one of
them: it read `Get-RunnerPresence` **after** writing the queue line, so the
response described the problem the operator had just created.

| runId | Repository | Item | Queued |
| --- | --- | --- | --- |
| `20260801-021933-da96ac69` | xfaith4/prompt-library | Add `CHANGELOG.md`, Keep a Changelog format | 2026-08-01 02:19:33 |
| `20260801-021941-c56ede1a` | xfaith4/prompt-library | *(same item)* | 2026-08-01 02:19:41 |
| `20260808-032019-b1480401` | xfaith4/300PixelLED_2812B | Approximate `nblendPaletteTowardPalette` | 2026-08-08 03:20:19 |
| `20260808-032023-789c9e48` | xfaith4/300PixelLED_2812B | *(same item)* | 2026-08-08 03:20:24 |
| `20260808-160411-e22a2f35` | xfaith4/AdministatorTools | `Compress-AdminToolsSnapshot -Path <session folder>` | 2026-08-08 16:04:11 |
| `20260808-160711-838aec7e` | xfaith4/AdministatorTools | *(same item)* | 2026-08-08 16:07:11 |

## What happened to each

All six carry a `cancelledReason` on their run summary, recorded at cancellation
rather than reconstructed here:

> Stranded: queued 2026-08-01..2026-08-08 and never claimed, because no operator
> runner has ever reported in. Cancelled during triage 2026-08-11; the roadmap
> item is unchanged and can be re-queued once runner-presence gating lands.

No roadmap file was edited, no branch was created, and no GitHub agent task was
opened for any of them — the entries never left `queued`, so nothing downstream
ran. Re-queueing any of the three items is a fresh dispatch, not a resume.

## The finding the count hides

**Six entries are three items, each queued twice.** Every pair is the same repo
and the same selected task:

- prompt-library — 8 seconds apart
- 300PixelLED_2812B — 4 seconds apart
- AdministatorTools — 3 minutes apart

Two seconds-apart pairs read as double-submits; the three-minute pair reads as a
deliberate retry after nothing appeared to happen. Both have the same cause: the
wizard reported success, nothing visibly changed, and the operator tried again.
The presence gate shipped in Release 3.1 milestone 1 removes the cause for the
absent-runner case — the second attempt is now refused with the precondition
named. It does **not** add an idempotency guard, so the same item can still be
queued twice while a runner *is* present. Recorded in `ROADMAP.md` as a
non-blocker rather than fixed here.

## Current state

`Get-QueuedTaskBacklog` reports `queuedTotal=0` as of 2026-08-13: no entry in
the queue file resolves to a summary still at `queued`. The stranded pile is
empty, the record of why it existed is intact, and the route that created it now
refuses to create another.

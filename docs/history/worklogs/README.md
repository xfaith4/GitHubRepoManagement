# Worklogs — where agent scratch files live

> **These are history, never a handoff.** The current handoff is the one open
> GitHub issue labelled `handoff`, which `tools/Get-SessionBriefing.ps1` prints
> first. A worklog here that calls itself a handoff, such as
> `2026-10-19-insights-defects/progress.md`, was superseded the day it landed.

Agent working notes (`findings.md`, `progress.md`, `task_plan.md` and their
relatives) belong **here**, never in the repository root.

## Why this file exists

The 2026-07-15 layout cleanup archived a set of root worklogs into this
directory. They came back: by 2026-08-08 the root carried a fresh
`findings.md` / `progress.md` / `task_plan.md` from the guided-improvement
workflow, and the convention had no enforcement behind it — only a note inside
a completed release, which nothing reads at authoring time.

So the convention is now stated here, ignored in `.gitignore`, and enforced by
a `scripts/Invoke-ModuleSmokeTest.ps1` tripwire that fails the required
pre-commit gate if a worklog is tracked at the repository root again.

## The convention

| Where | What goes there |
| --- | --- |
| Repository root | Nothing. Root worklogs are gitignored and rejected by the smoke gate. |
| `docs/history/worklogs/` | Long-lived worklogs kept from the pre-2026-07-15 layout. |
| `docs/history/worklogs/<YYYY-MM-DD>-<topic>/` | One directory per work session worth keeping. |

A worklog only worth keeping for the length of one session does not need to be
committed at all — write it under the session scratch directory instead.

## Contents

- `findings.md`, `progress.md`, `task_plan.md` — the pre-2026-07-15 worklogs,
  archived by [PR #61](https://github.com/xfaith4/GitHubRepoManagement/pull/61).
- `2026-08-08-guided-improvement/` — the guided repository-improvement workflow
  session that produced the Release 2.7 Phase D freeze-prevention work.

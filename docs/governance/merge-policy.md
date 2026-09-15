# Merge policy — a green check is the merge

Decided by Ben, 2026-09-15 (D-023). This file is the rule. `CLAUDE.md` and
`AGENTS.md` point here; where they disagree with this file, they are wrong.
The rule is enforced by
[`tools/Test-MergeTripwire.ps1`](../../tools/Test-MergeTripwire.ps1), which
runs in the canonical suite on every pull request, and proved by
[`tests/Test-MergeTripwire.ps1`](../../tests/Test-MergeTripwire.ps1).

## The rule

**A pull request with a green check merges.** The agent that opened it polls
`mergeStateStatus`, merges on `CLEAN`, deletes the branch, and names the merge
in its handoff. That includes changes under `backend/config/`,
`docs/governance/`, a test or a gate, and what a verdict says about a
repository — the four classes D-019 (2026-09-14) held for review.

**The tripwire decides what the light cannot see.** It reads the diff between
the branch and its base and reports one of three outcomes.

| Outcome | What it means | What happens |
| --- | --- | --- |
| `PASS` | Nothing the check cannot see. | Merge on green. |
| `HELD` | Something only the owner may approve. | The check stays red until Ben adds the `operator-approved` label and the next run passes. |
| `FAIL` | Something no approval clears. | Fix it. A label does not help. |

## What is held for Ben

- A protected path changed: this file, the tripwire and its proof test,
  `.github/workflows/**` (D-012), `.github/CODEOWNERS`.
- Section 2 of `steering.md` — the contracts — changed.
- A gate removed from `scripts/Invoke-TestSuite.ps1`, or `-FailOnError`
  dropped from a gate that had it. A commented-out gate counts as removed.
- A test or check file deleted (`tests/Test-*.ps1`, `tools/Test-*.ps1`,
  `scripts/Invoke-*Test*.ps1`, frontend `*.test.ts`/`*.test.tsx`). A rename
  is not a deletion.

**How Ben approves.** Add the `operator-approved` label on GitHub, then close
and reopen the pull request (or ask for a push). The check reads labels from
the event that started it, so a label on its own does not re-run anything. An
agent never applies that label; GitHub's audit log shows who did.

**At most two held pull requests wait at once.** The next held item is built
and verified on its branch, and its pull request is opened when a slot frees.

## What fails outright

- A secret shape on an added line: a GitHub token or fine-grained PAT, a model
  provider key, an AWS access key, a private-key block, a Slack token, a
  connection string with a password, or a credential assigned in the clear.
  A placeholder, example or environment-substituted value is not a secret.
- The permission envelope floor loosened in `agent-providers.json`: `network`
  or `githubWrite` true, or `.github/workflows/**` no longer forbidden
  (D-012).
- A versioned rules file under `backend/config/` changed without its
  `modelVersion` moving (steering contract 6).
- A debt ratchet loosened: the eslint `--max-warnings` cap raised, a
  PSScriptAnalyzer baseline count raised or a rule added to it, a UI ratchet
  count raised.

## What the tripwire does not see

This is the review Ben gave up for momentum. Each item is named so nobody
mistakes the gate for a reviewer.

- **A gate hollowed from inside.** Gate names and their `-FailOnError` are
  compared; gate bodies are not.
- **A decision recorded that Ben did not make.** `open-decisions.md` is the
  durable record and merges on green; a wrong entry is reverted, not caught.
- **A verdict that changed for a reason the evidence does not justify.**
  Steering §5 asks for the observed repository and a `modelVersion` bump; the
  bump is enforced, the observation is not.
- **A label applied by an agent.** The rule forbids it and the audit log shows
  it; nothing stops it.

**The remedy is a revert.** `git revert <sha>` (add `-m 1` for a merge commit)
undoes any merge in one pull request that itself merges on green.

**How Ben audits.** Everything that landed on `main` in the classes that used
to wait, newest first:

```powershell
git log --first-parent --since='2 weeks ago' --format='%h %ad %s' --date=short main -- backend/config docs/governance scripts/Invoke-TestSuite.ps1 tools tests
```

**The kill switch.** To put a class back behind review, add its path pattern
to `$script:ProtectedPathPatterns` in the tripwire. That edit is itself held,
so the rule tightens only by Ben's hand and loosens only by his merge of a
held pull request.

## Why

D-019 (2026-09-14) held four classes of change for review because an agent
that merges a change to its own gates on green is reviewing its own work. One
day later two review pull requests were waiting and a third was being built on
a branch. Ben, 2026-09-15: for the portfolio to gain momentum there has to be
a safe way to trust the automation. The safe way is to name what a human eye
was catching and make each item a check. The trust rule, the guards and
secrets stay with a person. Everything else is a diff a revert can undo.

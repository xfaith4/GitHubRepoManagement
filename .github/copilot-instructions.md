<!-- GENERATED MIRROR — DO NOT EDIT.
     Source of truth: AGENTS.md at the repository root.
     Everything below this comment is a byte-for-byte copy of that file, held
     identical by the "Agent contract mirror" gate in
     scripts/Invoke-ModuleSmokeTest.ps1. Edit AGENTS.md and re-run the gate;
     editing this file directly will fail CI. -->

# GITHUBREPOMANAGEMENT — agent contract

**This file is the canonical operating contract for any agent or tool working
this repository — Claude, Copilot, a GPT-based assistant, or a human reading
it as onboarding.** `CLAUDE.md` and `.github/copilot-instructions.md` point at
or mirror this file; none of them holds rules of its own. If guidance appears
in only one tool's file, it is invisible to every other tool, which is how a
convention silently stops applying.

## What this is

A repository portfolio management system: it scores, audits, and documents a
portfolio of 80+ repositories against declared standards. The backend API host
consumes JSON config from `backend/config/` and writes append-only state to
`output/`. Everything this project emits should be decision-grade — a report
or exported file must show what happened, why it matters, and what to do next.

## Read the roadmap before you build

`ROADMAP.md` is an execution contract, not a wish list, and it is the most
common way an agent wastes a day. Two rules make it safe to act on:

1. **A `- [ ]` checkbox means "not finished". It does NOT mean "nothing
   exists."** An item carries a state clause — `_(state: planned |
   scaffolded | backend-complete | ui-connected | smoke-tested |
   operator-verified)_`. Anything past `planned` asserts that code, gates, or
   evidence already exist. **Verify before you build.** This is enforced:
   `RQ014-OPEN-ITEM-NO-ARTIFACT` in
   [`tools/Test-RoadmapStructure.ps1`](tools/Test-RoadmapStructure.ps1) fails
   any open item past `planned` that does not name a linked path, a backticked
   file, or a command — so the artifact is always there to check.

2. **A completed item may not be in `ROADMAP.md` at all.** On release closure
   the section moves verbatim to
   [`docs/history/completed-releases.md`](docs/history/completed-releases.md).
   A grep that finds nothing in `ROADMAP.md` means "moved" as often as it
   means "missing" — check the archive before concluding anything is absent.

The same applies to any deferred instruction (a queued task, a handoff note, a
scheduled prompt): **verify its premise still holds before acting on it, and
before dismissing it.** Skipping real work fails silently; redoing finished
work at least leaves a visible empty diff.

## Layout — where things live and why

- `backend/config/` — **application config** the API host consumes
  (`repo-structure-standards.json`, `doc-standards.json`, `value-scoring.json`,
  `ai-doc-templates.json`, `settings.json`). The schema key is
  `"schemaVersion": "v1"` on all files — never `"version"`.
- `scripts/model-routing/` — **development-tooling config**. Application config
  and dev-tooling config are separate concerns. Never move files between these
  two directories or reference one from the other.
- `output/` — run evidence (`app.db`, `index/`, JSONL ledgers). Gitignored, so
  **these directories do not exist in a fresh clone** — a test fixture written
  there must create its own parent directory.
- `evidence/baseline/<date>/` — permanent snapshots. Copy into it; never edit
  in place, and never let retention or cleanup reach it.

## Config authority rules (do not re-derive these)

1. `ai-doc-templates.json` → `readmeContract` is the **single canonical
   authority** for README required sections. `doc-standards.json` references it
   and must never redefine section lists. `repo-structure-standards.json` is
   presence-only.
2. Severity policy: a missing universal section is `warning`; a missing
   profile-specific section is `info`. Universal set: Overview, Installation,
   Usage, License.
3. Any change to one config file requires checking the other four for contract
   drift before commit. The three-way README conflict happened once; the check
   exists so it does not happen twice.

## How this repo enforces things

**Gates, not documents.** If a rule matters here it is a script that fails, not
a paragraph someone is trusted to remember. Documents inform; only gates bind,
and only gates survive a change of model or tool. Two consequences:

- **Derive scope; never maintain a list.** A hand-maintained list of files or
  screens drifts the moment someone adds one. Gates in this repo find their own
  targets and fail on anything undeclared — that is how an unbounded ledger and
  a bare `git` call were both caught by gates written for other reasons.
- **A gate is not finished when it passes; it is finished when it has been
  shown to fail.** Prove a new check red against a real violating fixture
  before trusting a green run. A gate that has never failed may be asserting
  nothing — a check that examined zero items and reported success is the
  failure mode this rule exists to prevent.

## Verify before commit

- Run [`scripts/Invoke-ModuleSmokeTest.ps1`](scripts/Invoke-ModuleSmokeTest.ps1)
  and, if the API host is touched,
  [`scripts/Invoke-ApiHostSmokeTest.ps1`](scripts/Invoke-ApiHostSmokeTest.ps1).
  Exit 0 or the work is not done.
- The full suite is [`scripts/Invoke-TestSuite.ps1`](scripts/Invoke-TestSuite.ps1);
  CI runs it and is the arbiter for anything environment-sensitive.
- Config edits: validate the JSON parses and `schemaVersion` is present.
- **Never mark a roadmap item complete without evidence naming the test or
  artifact that proves it.** A release-claiming commit that ships
  `backend/` or `scripts/` code without advancing a milestone is rejected by
  [`tools/Test-RoadmapCapabilityRecord.ps1`](tools/Test-RoadmapCapabilityRecord.ps1).
- Linters here report on the information stream: capture with `*>&1`, not
  `2>&1`, or every assertion passes vacuously.

## PR and deployment workflow

This product's job is Actions-gated merge readiness, so the repo runs on that
pattern itself:

1. **Branch off `main`** — never commit feature work straight to `main`.
2. **Monitor checks to completion.** `gh pr view <n> --json mergeStateStatus`:
   `CLEAN` means mergeable. `BLOCKED` in this repo usually means a required
   check is still running, not that it failed — poll rather than concluding.
3. **Merge only on `CLEAN`**, squash, delete the branch, then
   `git switch main && git pull --ff-only`.

## Conventions

- PowerShell 5.1-compatible unless a file's `#Requires` says otherwise. That
  rules out `ForEach-Object -Parallel`, `Start-ThreadJob`, and `??`; use
  runspace pools for concurrency.
- Gates that read repo files must tolerate **CRLF** — the working tree is LF
  and a CI checkout is CRLF, so use `\r?\n` and never require a bare newline.
- Commit prefixes: `feat(release-N.M):`, `fix(validation):`, `chore(config):`.
- Non-blockers: name it, record it as a ROADMAP entry, and move on — do not
  stall the current step.
- **A question that is the operator's to answer goes in
  [`docs/governance/open-decisions.md`](docs/governance/open-decisions.md),
  not only in the reply.** If it turns on preference, product direction, risk
  appetite, or anything outside this repository, add an entry naming the
  default you proceeded under, then carry on with the parts that do not depend
  on it. Raising it in conversation alone is how a decision gets made by
  default, by whichever agent next touches the code.
- Never hide an error. Name it, record it, judge whether it blocks, and decide.
  `SilentlyContinue` must never be used to make a failure disappear.

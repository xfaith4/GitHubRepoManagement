# GITHUBREPOMANAGEMENT — repo context

@_base.md
@.claude/modes/implementer.md   <!-- swapped by ccmode.ps1 — do not edit this line by hand -->

## What this is

Repository portfolio management system: scores, audits, and documents a portfolio
of 80+ repos against declared standards. The backend API host consumes JSON config
from `backend/config/` and writes append-only state to `output/`. Everything this
project emits should be decision-grade: a report or exported file must show what
happened, why it matters, and what to do next.

## Layout — where things live and why

- `backend/config/` — **application config** the API host consumes
  (`repo-structure-standards.json`, `doc-standards.json`, `value-scoring.json`,
  `ai-doc-templates.json`, `settings.json`). Schema key is `"schemaVersion": "v1"`
  on all files — never `"version"`.
- `scripts/model-routing/` — **development-tooling config** (routing table, phase
  prompts, `Invoke-PhaseRun.ps1`). Application config and dev-tooling config are
  separate concerns. Never move files between these two directories or reference
  one from the other.
- `.claude/settings.json` — versioned repo contract (hooks, permissions).
  `settings.local.json` is per-machine and gitignored; policy never goes there.
- `output/` — run evidence (`app.db`, `index/`, `model-routing-ledger.jsonl`).
  Gitignored. Ledgers are append-only JSONL; never rewrite or truncate them.
- `evidence/baseline/<date>/` — permanent snapshots of run evidence worth keeping.
  Copy into it; never edit in place.

## Config authority rules (do not re-derive these)

1. `ai-doc-templates.json` → `readmeContract` is the **single canonical authority**
   for README required sections. `doc-standards.json` references it and must never
   redefine section lists. `repo-structure-standards.json` is presence-only.
2. Severity policy: missing universal section = `warning`; missing profile-specific
   section = `info`. Universal set: Overview, Installation, Usage, License.
3. Any change to one config file requires checking the other four for contract
   drift before commit. The three-way README conflict happened once; the check
   exists so it doesn't happen twice.

## Open decisions — surface, don't solve

- `value-scoring.json` keyword double-counting (max-vs-sum within a dimension,
  `effortFit` floor for mixed items) is **deferred pending Ben's decision on
  scoring semantics**. If work touches scoring, flag the interaction and stop.
  Do not fix it as a drive-by.

## Verify before commit

- Run `./scripts/Invoke-ModuleSmokeTest.ps1` and, if the API host is touched,
  `./scripts/Invoke-ApiHostSmokeTest.ps1`. Exit 0 or the work isn't done.
- Config edits: validate JSON parses and `schemaVersion` is present before commit.
- Never mark a ROADMAP phase complete without an evidence note naming the test
  or artifact that proves it.

## Conventions

- PowerShell 5.1-compatible unless a file's `#Requires` says otherwise.
- Commit prefixes: `feat(phaseN):`, `fix(validation):`, `chore(config):`.
- Non-blockers: name it, record it as a ROADMAP phase entry, and move on —
  don't stall the current step.

<!-- Guardrails (.claude/rules/) and mode behavior load automatically.
     Do not duplicate their content here. -->

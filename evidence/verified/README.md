# Curated proof — tracked, reviewed, permanent

Everything else under `evidence/` is generated run output: regenerable, large,
and gitignored. This directory is the exception, and the difference is
load-bearing.

`ROADMAP.md` makes evidence the boundary between a claim and a fact:

> Every milestone above carries an entry in
> `evidence/operator-verification-log.jsonl` — an unrecorded proof is
> indistinguishable from one that never happened.

Until 2026-08-13 every path under `evidence/` was ignored and the repository
structure audit failed on any tracked file there, so the only tracked entry was
a `.gitkeep`. A milestone whose acceptance criterion was an evidence entry could
not ship that entry in the pull request that earned it, and the proof lived only
on the machine that produced it.

## What belongs here

| Belongs | Does not belong |
| --- | --- |
| Hand-written triage and verification notes a human curated | Daily snapshots (`evidence/baseline/daily/`) |
| The operator verification log, once it has entries | Raw scan, ledger, or log captures |
| Anything a reviewer must read to accept a milestone | Anything a script regenerates on demand |

The test is whether losing the file would cost knowledge nobody can recompute.
A baseline snapshot can be retaken; a note explaining why six dispatches were
cancelled and what happened to each cannot.

## Conventions

- One file per proof, named `<topic>-<date>.md`.
- Open with the data window, the source of truth, and the verification date —
  the same decision-grade framing every export in this product owes its reader.
- State what was checked, what was found, and what remains. A proof that omits
  its own gaps is a summary.
- Never edit a proof in place to reflect later events. Add a new one and link
  back; this directory is a record, not a status page.

## Enforcement

`scripts/Invoke-RepositoryStructureAudit.ps1` still fails the suite for any
tracked file under `evidence/` **outside** this directory, so the carve-out
cannot widen by accident.

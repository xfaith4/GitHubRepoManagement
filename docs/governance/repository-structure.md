# Repository Structure Policy

This repository is intended to model a disciplined evaluation-tool layout rather than a long-lived working directory snapshot.

## Source Layout

- `backend/`: PowerShell modules, adapters, API host, and configuration.
- `frontend/`: React/Vite operator UI.
- `scripts/`: operator-facing automation, smoke tests, and maintenance tasks.
- `docs/`: canonical documentation only.
- `standards/`: reusable standards and schemas applied to target repositories.
- `tests/fixtures/`: small, curated, checked-in fixtures used by regression coverage.

## Generated Material

Generated material is not repository source and must stay out of tracked paths.

- `output/`: smoke runs, queue history, workitems, temporary execution state.
- `reports/`: exported HTML/CSV reports.
- `backend/modules/output/`: local runtime state used by the current host implementation.

Rules:

- Do not commit generated files from these paths.
- Keep only directory sentinels such as `.gitkeep` when a folder must exist in git.
- When regression coverage needs stable sample data, create a minimal fixture under `tests/fixtures/` instead of promoting a full runtime artifact tree into source control.

## Evidence Policy

`evidence/` holds two different things, and the difference decides whether a
path is tracked. It is enforced by
[`scripts/Invoke-RepositoryStructureAudit.ps1`](../../scripts/Invoke-RepositoryStructureAudit.ps1)
and mirrored in `.gitignore`; changing one without the other silently disables it.

| Path | Tracked | Why |
| --- | --- | --- |
| `evidence/verified/` | yes | Curated proof a person wrote and reviewed. The roadmap requires a durable evidence entry per operator-verified milestone, so a blanket ban made its own acceptance criteria impossible to satisfy in a PR. |
| `evidence/trials/` | yes | Curated trial records: selection reasons written by hand, and results recorded against a named index SHA. Release 3.7's acceptance criteria require results "recorded per repository in `evidence/`", and its body links these files directly. |
| `evidence/baseline/` | no | Run spill — regenerable, large, and produced by a command rather than a judgement. |
| anything else under `evidence/` | no | Defaults to untracked; add a carve-out deliberately or not at all. |

The line the rule defends is **regenerable output must not enter source
control** — not "nothing under `evidence/`". A new carve-out is justified only
when the content is a judgement someone made, a release's acceptance criteria
depend on it being reviewable in the PR, and re-running a command would not
reproduce it.

## Root Policy

The repository root should contain only:

- repository metadata and community files,
- the main README and roadmap,
- minimal launcher/compatibility entrypoints,
- package metadata required for local orchestration.

Implementation-specific scripts belong under `scripts/`.

## Documentation Policy

- Documentation links must be repository-relative, not site-root absolute.
- Architecture, planning, governance, operations, reference, and archive material stay under their matching `docs/` sections.
- Generated PDFs/HTML exports are not canonical docs and should not be committed.

## Enforcement

The CI structure audit validates these rules and should fail when:

- generated/runtime artifacts are tracked,
- docs index links use repository-breaking absolute paths,
- required governance/fixture structure is missing.

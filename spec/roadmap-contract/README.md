# Roadmap Contract Standard — Publishable Spec

> **Release 2.3 Phase 4.** A self-contained copy of the Roadmap Contract
> Standard. This directory can be copied into any repository without
> modification — it has no relative links out of this folder.

The Roadmap Contract Standard defines a release-oriented `ROADMAP.md` format
that both humans and AI agents can parse, audit, repair, and execute against.

## Contents

| File                             | Purpose                                                        |
| -------------------------------- | ------------------------------------------------------------- |
| `ROADMAP_TEMPLATE.md`            | Starting template for a compliant `ROADMAP.md`.               |
| `roadmap-contract.schema.json`   | JSON Schema for the normalized roadmap contract.              |
| `roadmap-audit-rules.json`       | Audit rules + maturity thresholds (L0–L4).                    |
| `ROADMAP_MATURITY_MODEL.md`      | The five maturity levels and what each requires.              |
| `ROADMAP_BUDGET_MODEL.md`        | Phase-plan / work-unit budget annotations.                    |
| `roadmap-repair-prompt.md`       | Prompt for AI-assisted roadmap repair.                        |
| `roadmap-events.md`              | Optional append-only `roadmap-events.jsonl` execution log.    |

## How to adopt

1. Copy this `roadmap-contract/` directory into your repository.
2. Copy `ROADMAP_TEMPLATE.md` to `ROADMAP.md` and fill it in.
3. Aim for maturity **L3-Contract-Ready** or higher (see the maturity model)
   before dispatching automated work.

## Versioning

The audit rules and schema carry their own version fields; treat this spec as
a snapshot. The canonical, actively-maintained source lives under
`standards/roadmap/` in the GitHub Repo Management project.

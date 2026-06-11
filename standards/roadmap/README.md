# Roadmap Contract Standard

This folder holds the data-driven assets that define what a good roadmap looks
like for this portfolio. Editing these files changes behavior without code
changes.

| File | Purpose |
| ---- | ------- |
| `ROADMAP_TEMPLATE.md` | Canonical authoring template for new roadmaps. |
| `ROADMAP_MATURITY_MODEL.md` | Human-readable maturity level (L0–L4) definitions. |
| `roadmap-contract.schema.json` | JSON Schema for the normalized contract model (backend audit). |
| `roadmap-audit-rules.json` | Weighted scoring rules + maturity thresholds (backend audit). |
| `roadmap-repair-prompt.md` | Prompt template for preview-based roadmap repair. |
| `ROADMAP_BUDGET_MODEL.md` | Cost/quota accounting model for agent-driven phases (cash, quota, opportunity). |
| `roadmap-validation.config.example.json` | Example config for the structure/quality validator. |

## Two related systems

1. **Backend roadmap audit** (`backend/modules/roadmap/`, `GET /api/roadmap/*`)
   scores *managed* repositories' roadmaps for dispatch readiness using
   `roadmap-audit-rules.json` and `roadmap-contract.schema.json`.

2. **This repo's own roadmap validator** —
   [`tools/Test-RoadmapStructure.ps1`](../../tools/Test-RoadmapStructure.ps1) —
   validates *this* repository's `ROADMAP.md` structure and execution-contract
   quality, and runs as a CI gate. It is configured by an optional
   `roadmap-validation.config.json` (copy from the `.example.json` here).

To activate a config for the validator, copy the example:

```powershell
Copy-Item ./standards/roadmap/roadmap-validation.config.example.json `
          ./standards/roadmap/roadmap-validation.config.json
```

See:
- [docs/operations/roadmap-validation.md](../../docs/operations/roadmap-validation.md) — running the validator, codes, config.
- [docs/reference/roadmap-contracts.md](../../docs/reference/roadmap-contracts.md) — the canonical release contract and examples.

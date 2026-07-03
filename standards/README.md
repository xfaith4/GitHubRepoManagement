# Roadmap Contract Standard

This folder contains the canonical, data-backed roadmap standard used by the portfolio tooling.
It intentionally separates three concerns:

| Layer | File(s) | Purpose |
| --- | --- | --- |
| Human authoring contract | `ROADMAP_TEMPLATE.md` | Defines the readable roadmap layout operators and agents should maintain. |
| Machine maturity contract | `roadmap-contract.schema.json`, `roadmap-audit-rules.json`, `Test-RoadmapContract.ps1` | Parses `ROADMAP.md` into a normalized object, validates the object shape, scores it, and assigns L0–L4 maturity. |
| Execution hygiene linting | `roadmap-validation.config.example.json`, `Test-RoadmapStructure.ps1` | CI-oriented checks for active-release quality, traceability, validation plans, status hygiene, and overgrown roadmaps. |

## Recommended validation flow

From a repository root:

```powershell
pwsh ./tools/Invoke-RoadmapValidation.ps1 `
  -Path ./ROADMAP.md `
  -ContractOut ./out/roadmap-contract.json `
  -FindingsOut ./out/roadmap-findings.json `
  -FailOnError
```

For contract-only validation:

```powershell
pwsh ./tools/Test-RoadmapContract.ps1 `
  -Path ./ROADMAP.md `
  -StandardsPath ./standards/roadmap `
  -ContractOut ./out/roadmap-contract.json `
  -JsonOut ./out/roadmap-contract-findings.json `
  -MinimumMaturity L3-Contract-Ready
```

For structure-only CI linting:

```powershell
pwsh ./tools/Test-RoadmapStructure.ps1 `
  -Path ./ROADMAP.md `
  -Config ./standards/roadmap/roadmap-validation.config.json `
  -JsonOut ./out/roadmap-structure-findings.json `
  -FailOnError
```

## File purpose

| File | Purpose |
| --- | --- |
| `ROADMAP_TEMPLATE.md` | Canonical authoring template. No conflicting “Immediate Next Focus” section; active work is represented by the single active release. |
| `ROADMAP_MATURITY_MODEL.md` | Human-readable L0–L4 model aligned to the audit rules and maturity gates. |
| `roadmap-contract.schema.json` | Normalized contract schema produced from `ROADMAP.md`. |
| `roadmap-audit-rules.json` | Data-driven weighted rules and maturity gates. |
| `roadmap-repair-prompt.md` | Prompt for preview-based roadmap repair without destroying completion history. |
| `ROADMAP_BUDGET_MODEL.md` | AI-agent budget, quota, and cost accounting model. |
| `roadmap-validation.config.example.json` | Example config for `Test-RoadmapStructure.ps1`. Copy to `roadmap-validation.config.json` to activate repo-specific overrides. |

## CI recommendation

Use both validators:

1. `Test-RoadmapContract.ps1` answers: “Is this roadmap mature enough for dispatch?”
2. `Test-RoadmapStructure.ps1` answers: “Is the active roadmap clean enough for CI and operator use?”

Do not merge those responsibilities back into one script. The contract validator should remain JSON-backed and maturity-focused. The structure validator should remain repo-hygiene-focused.

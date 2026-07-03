# Roadmap Standard Replacement Package

## Contents

```text
standards/roadmap/README.md
standards/roadmap/ROADMAP_BUDGET_MODEL.md
standards/roadmap/ROADMAP_MATURITY_MODEL.md
standards/roadmap/ROADMAP_TEMPLATE.md
standards/roadmap/roadmap-audit-rules.json
standards/roadmap/roadmap-contract.schema.json
standards/roadmap/roadmap-repair-prompt.md
standards/roadmap/roadmap-validation.config.example.json
tools/Invoke-RoadmapValidation.ps1
tools/Test-RoadmapContract.ps1
tools/Test-RoadmapStructure.ps1
```

## Installation

Copy the `standards/roadmap` folder over your existing roadmap standards and copy the `tools/*.ps1` scripts into your repo's `tools` folder.

Recommended first run:

```powershell
New-Item -ItemType Directory -Path ./out -Force | Out-Null
pwsh ./tools/Invoke-RoadmapValidation.ps1 `
  -Path ./ROADMAP.md `
  -StandardsPath ./standards/roadmap `
  -ContractOut ./out/roadmap-contract.json `
  -FindingsOut ./out/roadmap-findings.json `
  -FailOnError
```

## Design intent

- `Test-RoadmapContract.ps1` is the JSON-backed maturity validator.
- `Test-RoadmapStructure.ps1` is the CI execution-hygiene linter.
- `Invoke-RoadmapValidation.ps1` runs both and can produce a combined findings file.

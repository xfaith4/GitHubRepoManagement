# Contributing

## Workflow

1. Create a focused branch per change.
2. Keep changes small and linked to roadmap items.
3. Run smoke tests before submitting:
   - `.\scripts\Invoke-ModuleSmokeTest.ps1`
   - `.\scripts\Invoke-AdapterSmokeTest.ps1`
   - `.\scripts\Invoke-ApiHostSmokeTest.ps1`

## Standards for This Repo

- Preserve canonical contracts in `/docs/reference/contracts.md`.
- Keep operational scripts in `/scripts`.
- Update docs for every behavior or contract change.
- Avoid hardcoding secrets; use environment variables.

## Pull Requests

- Include purpose, scope, and validation evidence.
- Mention impacted docs and scripts.
- Include breaking-change notes when applicable.

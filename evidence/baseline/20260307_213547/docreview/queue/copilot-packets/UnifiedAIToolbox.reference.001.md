# Queue Item: UnifiedAIToolbox.reference.001

## Repo
- Name: UnifiedAIToolbox
- Path: G:\Development\20_Staging\UnifiedAIToolbox
- Repo Priority: High (80)

## Git State
- Branch: unknown
- Last Commit: unknown
- Uncommitted Changes: 0

## Batch
- Type: reference
- Chunk: 1
- Complexity: high
- Recommended Cooldown Seconds: 300
- Queue Score: 106
- Prompt Flavor: reference-doc-normalization

## Files in Scope
- docs\archive\cli\QUICK_REFERENCE.md
- docs\archive\cli\UNIFIED_CLI.md
- docs\archive\cli\wsl-env-passthrough.md
- docs\archive\engine-status-schema.md
- docs\archive\help\api-reference.md

## Objectives
- Normalize structure and terminology across reference docs
- Improve scanability with disciplined headings and tables where useful
- Reduce ambiguity while preserving technical precision
- Keep formatting consistent and easy to navigate

## Warnings / Review Notes
- Batch contains many files; keep changes bounded and reviewable
- Many markdown files fall into general or unclear categories
- Multiple README.md files detected across the repo
- Multiple setup-oriented docs may indicate overlap or duplication

## Constraints
- Preserve technical accuracy
- Do not invent implementation details, APIs, commands, or architecture facts
- Prefer structural improvements over cosmetic rewrites
- Keep changes concise, professional, and reviewable
- Use tree diagrams only where they materially improve understanding

## Suggested Copilot Prompt

```text
You are performing a reference documentation normalization pass.

Priorities:
- improve consistency and scanability
- normalize terminology, headings, and formatting
- use tables where appropriate for options, parameters, and comparisons
- reduce ambiguity while preserving technical precision
- use tree diagrams only when a nested structure is genuinely hard to explain in prose

Rules:
- do not invent APIs, commands, schemas, or configuration facts
- keep formatting disciplined and predictable
- prefer concise, high-signal writing
```


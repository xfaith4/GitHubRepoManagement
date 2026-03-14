# Queue Item: UnifiedAIToolbox.reference.001

## Repo
- Name: UnifiedAIToolbox
- Path: G:\Development\20_Staging\UnifiedAIToolbox
- Repo Priority: High (70)

## Git State
- Branch: main
- Last Commit: 2026-03-13 03:31:48 -0400
- Uncommitted Changes: 5

## Batch
- Type: reference
- Chunk: 1
- Complexity: medium
- Recommended Cooldown Seconds: 180
- Queue Score: 93
- Prompt Flavor: reference-doc-normalization

## Files in Scope
- docs\archive\engine-status-schema.md
- docs\archive\PROMPT_CHAIN_QUICK_REFERENCE.md
- docs\run-events.schema.md

## Objectives
- Normalize structure and terminology across reference docs
- Improve scanability with disciplined headings and tables where useful
- Reduce ambiguity while preserving technical precision
- Keep formatting consistent and easy to navigate

## Warnings / Review Notes
- Many markdown files fall into general or unclear categories
- Multiple README.md files detected across the repo
- Repo has 5 uncommitted change(s) - may be mid-surgery; verify before reviewing

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


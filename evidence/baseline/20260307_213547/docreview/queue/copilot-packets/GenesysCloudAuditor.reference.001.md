# Queue Item: GenesysCloudAuditor.reference.001

## Repo
- Name: GenesysCloudAuditor
- Path: G:\Development\20_Staging\GenesysCloudAuditor
- Repo Priority: High (55)

## Git State
- Branch: unknown
- Last Commit: unknown
- Uncommitted Changes: 0

## Batch
- Type: reference
- Chunk: 1
- Complexity: medium
- Recommended Cooldown Seconds: 180
- Queue Score: 78
- Prompt Flavor: reference-doc-normalization

## Files in Scope
- docs\credentials_config_IncludeInactive_toggle_run_audit_progress_results_tabs_export.md
- docs\OAuth_client_credentials_vs_auth_code_token_refresh_required_scopes_ra_6283b987.md
- docs\trim_case_leading_zeros_policy_non-digit_filtering_as_configured.md
- docs\WPF_.NET_8_MVVM_DI_HttpClientFactory_background_tasks_progress_reporti_91de446c.md

## Objectives
- Normalize structure and terminology across reference docs
- Improve scanability with disciplined headings and tables where useful
- Reduce ambiguity while preserving technical precision
- Keep formatting consistent and easy to navigate

## Warnings / Review Notes
- docs folder exists without docs/index.md
- Many markdown files fall into general or unclear categories

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


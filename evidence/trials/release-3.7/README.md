# Release 3.7 trial preparation

Status: **selection complete (2026-09-13); measured execution still gated.** Nine
named repositories, and `externally-managed-project` recorded as unrepresented.
No measured execution or verified improvement is claimed.

D-006's ruling (2026-09-06) released this selection and named its own default —
nine candidates plus one category recorded as unrepresented — but these files
still carried the 2026-09-05 state, where the tenth slot read
`operator-input-required`. The artifact was asking for a decision that had
already been made, so the selection milestone sat blocked for a week on nothing.

**Selection is not owner intent.** D-006 keeps the intent *labels* open, so
`abandoned-project` and `externally-managed-project` carry
`ownerIntentConfirmed: false` in `cohort.json`. Assigning a repository to a
category is not a claim about what its owner intended, and collapsing the two
would launder a pending judgement into a recorded fact.

| Required kind | Candidate | Selection evidence |
| --- | --- | --- |
| mature-active-application | ActiveFamilyArchive | Established family application with authentication, administration and extensive completed roadmap work; README and ROADMAP inspected. |
| weak-active-application | FowlingScorecard | ROADMAP Current Situation explicitly describes useful working parts but no single finished product. |
| small-utility | DevPortConsole | README describes a self-contained single-script utility; roadmap says all six phases complete. Tests the appropriate-as-is conclusion. |
| experiment | 2026-06-13_Orchestration | README describes a phase-0.1 bootstrap; roadmap prioritizes reaching a successful run. Experimental classification is provisional, not inferred from conformance. |
| abandoned-project | Genesys-Telecom-Powershell | Existing archived-ignore curation supplies intent evidence; operator may correct abandoned versus intentionally archived. |
| repository-without-roadmap | AI_PromptRefiner_GUI | Active tool README exists; root ROADMAP.md is absent. Accepted alternate locations must be checked by the product before recommending creation. |
| library | genesys-contract-client | README describes a reusable deterministic API wrapper; roadmap explicitly names library plus MCP server. |
| externally-managed-project | **Unrepresented** | No cohort member. External management is owner intent and may not be inferred from age, activity, remote ownership or documentation maturity (D-006). An empty category is a valid trial outcome, not a gap to fill with a substitute chosen for conformance. |
| nearly-finished-repository | 300PixelLED_2812B | ROADMAP contains 46 checked items and 7 open items, including simulator and diagram finishing work; counts select a category, not proof of completion. |
| messy-repository | Genesys.Core | README describes a Genesys API collection engine while ROADMAP names SereneHarmony Site Starter and website performance work. Directly observed provenance mismatch. |

## Entry gate

- Deploy and live-check the Lane 0.15 truth fixes; verify Today, outcome card and Insights with the operator.
- Required module/API smoke checks must exit 0. Automated UI checks do not establish live operator verification.
- ~~Confirm all ten categories, then freeze this cohort before recording results.~~ **Done 2026-09-13** — nine selected, one recorded unrepresented under D-006. Owner-intent *labels* remain open and are tracked per record, not here; they gate how a result is described, not whether the cohort is settled.
- Refresh each repository through the product; freeze its source, scope, timestamps, head commit and before-state evidence. Cached outcomes in cohort.json are diagnostic context only.

## Evidence per repository

Use `cohort.json` records for conclusions, why the repository matters, limiting foundation, next action and preview. Record the explicit operator approval, agent-run id, operator minutes measured by the operator, first-pass result, before/after artifacts and independent criterion-level checks against the resulting branch/commit. A check names its criterion, command or observation, result and evidence path. A merge alone is not an acceptance check. Failed or unparseable validation is not a pass.

Keep appropriate-as-is, archive and insufficiently-understood outcomes in the ten-repository conclusion tally. Count toward the five improvements only when an approved action through the product has independently evidenced material benefit. Do not infer minutes or savings from timestamps. Unavailable cost or effort stays unavailable.

Record release-level operator verification with `scripts/Add-OperatorVerification.ps1 -List` and the resolved SurfaceId plus observed evidence. Per-repository results live here and reference the existing agent-run ledgers; the script does not invent trial surface IDs.

## Exit gate

Ten recorded conclusions, at least five independently validated material improvements, recorded operator minutes/first-pass/outcome quality, corrected false positives and a numeric rollout go/no-go. Until those exist, rollout is no-go. Carryover, cumulative sequence caps and dependency ordering remain deferred Lane 0.18 work.

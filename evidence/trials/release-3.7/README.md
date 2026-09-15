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

Keep appropriate-as-is, archive and insufficiently-understood outcomes in the nine-repository conclusion tally. Count toward the five improvements only when an approved action through the product has independently evidenced material benefit. Do not infer minutes or savings from timestamps. Unavailable cost or effort stays unavailable.

Record release-level operator verification with `scripts/Add-OperatorVerification.ps1 -List` and the resolved SurfaceId plus observed evidence. Per-repository results live here and reference the existing agent-run ledgers; the script does not invent trial surface IDs.

## Exit gate

Nine recorded conclusions, at least five independently validated material improvements, recorded operator minutes/first-pass/outcome quality, corrected false positives and a numeric rollout go/no-go. Until those exist, rollout is no-go. Carryover, cumulative sequence caps and dependency ordering remain deferred Lane 0.18 work.

## Conclusions (2026-09-13)

Engine output from `Get-RepositoryFoundationConclusion` (foundation-conclusions v1) over the index generated 2026-09-13T21:07:51Z, which scanned all nine that morning. Zero conclusion-contract violations. **Not operator-verified** — the entry gate still wants eyes on the live Today, outcome-card and Insights surfaces, so these are what the product concluded, not confirmed findings. No improvement is claimed and nothing here counts toward the five.

| Repository | Detected kind | Conclusion | Limiting foundation | Product can act |
| --- | --- | --- | --- | --- |
| ActiveFamilyArchive | `unknown` | **strengthen** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |
| FowlingScorecard | `unknown` | **strengthen** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |
| DevPortConsole | `unknown` | **strengthen** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |
| 2026-06-13_Orchestration | `unknown` | **strengthen** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |
| Genesys-Telecom-Powershell | `archived` | **appropriate-as-is** | nothing limiting | no action to take |
| AI_PromptRefiner_GUI | `unknown` | **strengthen** | `planning` missing | yes — `/api/roadmap/repair/preview` |
| genesys-contract-client | `unknown` | **insufficiently-understood** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |
| 300PixelLED_2812B | `unknown` | **strengthen** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |
| Genesys.Core | `unknown` | **strengthen** | `planning` weak, `structure` weak | yes — `/api/roadmap/repair/preview` |

### What the first pass exposes

The trial exists to find false positives and bad recommendations on nine
repositories before they are found on eighty. Three surfaced on the first pass.
None is an engineering failure; all three are the model not yet discriminating,
which is the thing measured execution would otherwise have hidden.

**F-01 — kind detection resolves only `archived`.** Eight of nine conclusions
were drawn with the basis *"no kind signal in the index; every scored domain
applies"*. The cohort was selected BY KIND, and the product cannot tell those
kinds apart, so per-kind applicability never engaged: a library is judged
against the same yardstick as a mature application. The roadmap already records
this as a known gap under Release 3.6 out-of-scope; what is new is evidence that
it undercuts the trial's own premise rather than being cosmetic.

**F-02 — seven of nine share one limiting pair.** `planning` weak plus
`structure` weak is the answer for seven repositories, including a finished LED
firmware project, an API client library and an orchestration experiment. A
ranking that returns the same answer for most of the portfolio cannot say what
to do *first*, which is the product's stated job.

**F-03 — every actionable repository gets the same next action.** All eight
resolve to `POST /api/roadmap/repair/preview`. That is a defensible default when
planning is the weakest foundation, but as the universal recommendation it means
the conclusion model is currently a planning detector rather than a portfolio
advisor. This is the clearest thing for milestone 4 to fix.

These are recorded, not acted on. Fixing them is milestone 4's job ("adjust and
decide"), and doing it now — before the improvements are executed and measured —
would change the model mid-measurement.

## What the product could not see

Recorded 2026-09-14 against the conclusions above (foundation-conclusions v1,
index generated 2026-09-13T21:07:51Z), as steering Rung 2A requires of every
trial. Each line is a limit of the product, not a finding about the repository.

- **What each repository is.** v1 carried no kind signal, so eight of nine were
  judged against every domain. Kind detection (M4a, #295) reads manifests,
  entry points and the README purpose line; the live index carries those
  signals only after the portal's next service restart (OQ-12), so the
  conclusions above were drawn without them.
- **A workspace root.** 2026-06-13_Orchestration is an npm workspace whose
  purpose line names its packages rather than what they are for, and whose
  dependencies live one level down. The scanner reads the root only; the
  repository resolves `unknown`, and since the M4a follow-through that
  `unknown` names the one hint it saw (`monorepo`) so the next rule is a data
  change. The v2 signals for all nine are recorded in `kind-baseline-v2.json`
  as hints and a SHA-256 of each purpose line - never the text, because this
  repository is public.
- **A purpose line that is an instruction.** FowlingScorecard's first README
  sentence tells an operator what to do, not what the repository is. The
  product reads the first prose line; it cannot tell a purpose statement from
  a quick-start line.
- **Disagreement between manifest and README.** FowlingScorecard carries a
  PowerShell module manifest and a served page; 300PixelLED_2812B carries
  Arduino sketches and a web app. The product picks one kind by rule order and
  does not surface the disagreement (steering extension 2).
- **Owner intent.** `abandoned-project` and `externally-managed-project` are
  cohort categories, not findings; both records carry
  `ownerIntentConfirmed: false`, and the product concludes neither (D-006,
  contract 7).
- **Whether its recommendations are accepted.** No accept/reject ledger exists;
  the leverage panel reports that figure as not captured. Every approval or
  rejection in this trial is recorded by hand in `cohort.json` until the
  ledger ships (steering extension 1).
- **Whether the live surfaces show what the payload says.** Engine output is
  what is recorded here; the entry gate's eyes-on check is OQ-1.

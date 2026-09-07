# Release 3.9 — Roadmap Contract v2: work packets

> Companion to [`HAIKU-WORK-PACKETS-3.8.md`](HAIKU-WORK-PACKETS-3.8.md) and it
> follows the same operating rules — read `## 0` there first. This file adopts
> `roadmap-audit-rules` **v2.0**, which reframes the audit around
> execution-contract quality instead of one prescribed roadmap layout.

## 0. What this file is, and what it found

The v2.0 rule pack was authored outside this repository and handed over as
`roadmap-audit-rules-v2.0.json`. It is **not a configuration bump**. Evaluating
it against the code that consumes v1.5 turned up four facts that shape every
packet below.

### 0.1 All twelve rule IDs were kept and all twelve were repurposed

This is the single largest hazard in the change, and it is invisible in a diff
that only looks at the JSON.

| ID | v1.5 meaning | v2.0 meaning |
| --- | --- | --- |
| ROADMAP-003 | `roadmap-has-pending-work` | `non-root-roadmap-linked-from-readme` |
| ROADMAP-008 | `sufficient-pending-item-count` | `work-items-are-concrete` |
| ROADMAP-009 | `has-multiple-releases` | `current-target-designated-when-work-pending` |
| ROADMAP-010 | `no-vague-checklist-items` | `single-current-target` |
| ROADMAP-011 | `single-active-release` | `current-target-has-recognized-status` |
| ROADMAP-012 | `has-designated-active-release` | `status-and-work-are-consistent` |

ROADMAP-001, -002, -004, -005, -006 and -007 keep their *intent* but change
their `failCondition`, weight, applicability or all three.

[`Roadmap.Repairer.ps1`](../../backend/modules/roadmap/Roadmap.Repairer.ps1)
maps **nine of these IDs to repair prose written against the v1.5 meaning**.
Adopt v2.0 without touching it and a repository failing "your work items are
vague" is told to *"add more concrete pending checklist items (currently fewer
than 3)"*, while one with two current targets is told to *"rewrite N vague
checklist items"*. Wrong advice delivered confidently is worse than no advice,
and nothing in CI would catch it, because the ID still resolves.

The same reuse silently reinterprets every stored finding:
`backend/modules/output/cache/roadmap-audit-cache.json` and
`output/evaluator-parity.json` both record findings by ID.

### 0.2 There are two evaluators, and a parity gate between them

- [`Roadmap.Auditor.ps1`](../../backend/modules/roadmap/Roadmap.Auditor.ps1) — the module evaluator
- [`Test-RoadmapContract.ps1`](../../tools/Test-RoadmapContract.ps1) — the CLI evaluator

Each carries its **own private mirror** of the detection defaults, kept
byte-identical to the JSON by convention and by a comment recording why: before
2026-08-08 they each had their own regexes and no repository in the estate
scored the same under both, with three straddling the L3 dispatch threshold
depending on which tool ran.

Every packet below therefore lands in **both** evaluators or in neither.

### 0.3 v2.0 needs twelve signals neither evaluator computes today

`roadmapPath`, `readmeLinksToRoadmap`, `hasProductIntentReference`,
`executionUnitCount`, `pendingExecutionUnitCount`,
`pendingExecutionUnitsWithoutAcceptanceCriteria`,
`pendingExecutionUnitsWithoutOutOfScope`, `executionUnitsWithAcceptanceCriteria`,
`executionUnitsWithOutOfScope`, `currentTargetCandidateCount`,
`currentExecutionUnit` (with its own `normalizedStatus` and `pendingCount`), and
a `vagueItemCount` computed under the new `taskQuality` contract.

It also moves four things out of evaluator code and into the contract, which the
evaluators must now **read rather than privately implement**: `terminalStates`,
`maturityCaps` (severity caps, rule overrides, most-restrictive-wins),
`derivedOutputs.executionState`, `derivedOutputs.dispatchEligibility`, and
`scoring.mode = normalized-applicable` (rules that do not apply leave the
denominator).

### 0.4 This repository is not demoted — the rest of the estate is unmeasured

Measured, not assumed. `Test-RoadmapContract.ps1` scores this repo **100 /
L4-Orchestration-Ready** under v1.5 today. Recomputing every v2.0 signal by hand
against `ROADMAP.md` gives the same result:

```text
execution units          4   (Release 2.9 / 3.6 / 3.7 / 3.8)
pending units            4   all four carry acceptance criteria AND out-of-scope
explicit "Current: true" 0   -> legacy fallback resolves 1 candidate (2.9, active)
vague items              0   of 75 unchecked, under the stricter taskQuality rules
ROADMAP-003              N/A (root path) -> leaves the denominator
```

So v2.0 costs this repository nothing. **The other fourteen roadmaps in the
corpus at `F:\Development\20_Staging` are unmeasured**, and maturity feeds
`Test-RoadmapPackagingCandidate`, so a demotion there is a repository that
silently stops being packaged. Packet H39-07 measures that before anything
flips.

One live finding fell out of the same calculation, worth fixing whichever way
this goes: this roadmap's only `active` unit is **Release 2.9**, so both v1.5
and v2.0 resolve 2.9 as the current target while all present work is in 3.8.

### 0.5 The vendored pack would silently drop the dependency rules

Found while sequencing Release 3.8's H38-17, which needs `H-13a`/`H-13b` from
[`HAIKU-WORK-PACKETS.md`](HAIKU-WORK-PACKETS.md). H-13a adds **two new audit
rules** for roadmap dependency notation (`dependsOn` referencing an unknown id;
a dependency cycle), numbered by the existing convention as **ROADMAP-013 and
ROADMAP-014**.

The vendored v2.0 pack stops at ROADMAP-012 and knows nothing about them,
because it was authored elsewhere. Adopt it verbatim after H-13a merges and both
rules disappear — not with an error, but by simply not being in the file the
evaluators iterate.

This is *not* an ID collision: v2.0 leaves 013 and 014 free. It is a **carry-forward
obligation**, and it is the first instance of the standing cost of vendoring a
contract this repository also extends. H39-01 owns it, and H39-08's flip asserts
it, so the next revision cannot lose them either.

---

## A. Decisions made by this file (Ben can veto any of these)

| # | Decision | Why |
| --- | --- | --- |
| A23 | **The vendored rule pack is adopted verbatim, IDs included.** v2.0's ID reuse is not corrected to ROADMAP-013+. | The pack is an external contract; renumbering forks it from upstream and every later revision has to be re-reconciled by hand. The reuse is made safe by H39-08 instead of by editing the pack. |
| A24 | **A stored finding is worthless without the pack version that produced it.** Every persisted audit record gains `rulesVersion`, and a reader refuses a record whose version it does not understand rather than interpreting it. | This is the only defence against 0.1 that survives the next revision too. Silently reading a v1.5 finding under v2.0 semantics is the failure; refusing is visible. |
| A25 | **v1.5 and v2.0 both stay loadable until the flip.** The evaluators take the pack as data, so both can be evaluated over the same corpus in one run. | H39-07 cannot report a delta it cannot compute. Deleting v1.5 first makes the impact unmeasurable at exactly the moment it matters. |
| A26 | **Detection stays data; no packet may reintroduce a private pattern.** New signals are added to both evaluators' mirrors in the same commit, and the existing byte-identity comment applies unchanged. | The 2026-08-08 divergence is the recorded reason the mirrors exist. Twelve new signals is the largest opportunity to recreate it since. |
| A27 | **`no-checklist` → `no-supported-tasks` is a wire rename with a compatibility shim, not a find-and-replace.** The backend emits the new token; a shim maps it to the old one for the 10 frontend components and 12 backend sites until they are migrated in H39-06. | The token reaches `RepoGrid.tsx` filters, badge maps and `dispatchReadiness`. Renaming the emitter alone turns a labelled amber badge into an unstyled unknown state on the estate's most-used surface. |
| A28 | **Release 3.9 runs before Release 3.7's measured execution, and after 3.8.** | 3.7's job is to measure the portfolio and decide the 80+ rollout. Changing the audit's ruler part-way through means its before/after numbers are taken with two different instruments — the trial would prove nothing. 3.6 is engineering-complete in validation and is not reopened. |

---

## B. Decisions needed — Ben's call, not an agent's

| # | Question | What it blocks | Default if unanswered |
| --- | --- | --- | --- |
| D-016 | **Three things now answer "can this be dispatched": v2.0's `derivedOutputs.dispatchEligibility`, `Test-RoadmapExecutionContract`, and Release 3.8's provider router. Which is authoritative, and what do the other two become?** | H39-09 only. Everything before it is signal plumbing. | `dispatchEligibility` is published as **advisory** beside the existing verdict and binds nothing. Both are shown; where they disagree, the disagreement is displayed rather than resolved. Nothing changes behaviour until Ben rules. |
| D-017 | **Does an explicit `> Current: true` become required authoring for this estate, or does the legacy single-`active` inference stay indefinitely?** | Nothing. Both paths are implemented in H39-04 because v2.0 specifies both. | The inference stays. `ROADMAP_TEMPLATE.md` recommends `Current: true` without requiring it. |
| D-018 | **v2.0 forbids recursive `ROADMAP.md` discovery. Some estate repositories may only have a nested one — do they become `L0-Absent`, or is a configured path expected per repo?** | H39-02's failure copy only. | They read `L0-Absent` with a `recommendedAction` naming the configured-path escape hatch. H39-07 reports exactly how many repositories this affects before it can surprise anyone. |

D-012 (permission envelope) from the 3.8 series stays open and is unrelated.

---

## 1. Packet index (execute in this order)

| id | milestone | summary | prereq | risk |
| --- | --- | --- | --- | --- |
| H39-01 | M1 | Vendor v2.0 beside v1.5; signal-coverage gate; carry local rules forward (§0.5) | — | low |
| H39-02 | M1 | Bounded roadmap discovery; `roadmapPath`, `readmeLinksToRoadmap` | H39-01 | medium |
| H39-03 | M2 | Releases generalize to execution units; per-unit acceptance/scope signals | H39-01 | high |
| H39-04 | M2 | Current target separates from lifecycle status | H39-03 | high |
| H39-05 | M2 | Task format and the new task-quality contract | H39-01 | medium |
| H39-06 | M2 | `no-supported-tasks` rename, with the frontend shim | H39-05 | medium |
| H39-07 | M3 | **Estate impact measured under both packs before anything flips** | H39-02…06 | low |
| H39-08 | M3 | Scoring, caps, terminal states read from the contract; IDs flip; Repairer remapped; caches version-gated | H39-07 | high |
| H39-09 | M3 | `executionState` and `dispatchEligibility` published (advisory pending D-016) | H39-08 | medium |
| H39-10 | M4 | Docs, template, repair prompt and maturity model catch up | H39-08 | low |

Ten packets. M1 adds signals nothing reads yet; M2 completes the signal set; M3
measures, then flips; M4 makes the written standard match the shipped one.

**Nothing changes any repository's score until H39-08.** Packets H39-01 to
H39-07 are additive: they compute new signals, keep evaluating v1.5, and prove
parity. That ordering exists so the flip is a single reviewable commit with a
measured delta attached, rather than a drift nobody can point at.

---

## 2. Packets

### H39-01 — Vendor the pack, and make the gap list a gate

**Prerequisites:** none.

**Scope (edit only):** new `standards/roadmap/roadmap-audit-rules-v2.json` and
its `spec/roadmap-contract/` twin; `scripts/Invoke-ModuleSmokeTest.ps1`;
`scripts/Invoke-TestSuite.ps1` (the self-contained-spec assertion).

**Steps**

1. Copy the vendored pack to both locations under the `-v2` name. v1.5 stays
   exactly where it is and stays the pack both evaluators load (A25).
2. Extend the standards↔spec sync gate from 7 assets to 8.
3. **The gate that makes this packet worth doing on its own**: a static
   coverage check. Parse every rule's `failCondition` and
   `applicabilityCondition`, extract each identifier, and assert that the
   evaluators can produce it. Predicted red: **twelve** named missing signals
   (§0.3), reported in one list rather than discovered one packet at a time.
4. The same check asserts each rule's `maxMaturityOnFailure` and every
   `maturityCaps.ruleOverrides` key names a real rule and a real threshold.
5. **Carry the local extensions forward (§0.5).** If `ROADMAP-013` /
   `ROADMAP-014` exist in the shipped v1.5 pack when this packet runs, copy them
   into the v2 pack. Then assert it generally rather than by name: **every rule
   id present in the current pack must be present in the v2 pack**, so the next
   vendored revision cannot drop a locally added rule either. If H-13a has not
   merged yet, the assertion still runs and passes vacuously — and starts
   protecting the rules the moment they land.

**Gate (red first):** `Write-Step 'Roadmap rules v2 — smoke: every rule signal has a producer'`, failing with all twelve names. That list becomes this milestone's definition of done.

A vendored contract this repository also extends has a standing cost, and step 5 is where it gets paid. The rule-id superset assertion is the only part of this file that protects work **not yet written** — which is why it is stated as an invariant rather than as two names.

**Stop if:** the vendored pack's `detection.scoring.formula` disagrees with the evaluators' current normalized scoring in a way step 3 cannot express — report the difference rather than encoding an interpretation of it.

---

### H39-02 — Bounded roadmap discovery

**Prerequisites:** H39-01.

**Scope (edit only):** both evaluators' detection mirrors; `Roadmap.Auditor.ps1`; `Test-RoadmapContract.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`.

**Steps**

1. Implement `detection.roadmapDiscovery`: `preferredPaths`, then
   `acceptedPaths`, then one configured path. `recursiveSearch: false` is a
   **rule, not a default** — no code path may walk the tree for a `ROADMAP.md`.
2. Emit `roadmapPath` relative to the repository root, because ROADMAP-003's
   applicability is `roadmapPath !== 'ROADMAP.md'`.
3. Implement `readmeRoadmapLinkPattern` → `readmeLinksToRoadmap`.
4. Implement `productIntentReferencePattern` → `hasProductIntentReference`.

**Gate:** a fixture tree carrying `ROADMAP.md` at root **and** a nested
`vendor/thing/ROADMAP.md` — discovery must return the root one and must never
report the nested one. A second fixture with the roadmap only at
`docs/planning/ROADMAP.md` resolves, sets `roadmapPath`, and makes ROADMAP-003
applicable. A third with a nested roadmap only reads `missing`, and the failure
copy names the configured-path escape hatch (D-018).

**Stop if:** any existing caller passes an explicit `roadmapPath` discovered by
a recursive scan — report each site; they are the reason `recursiveSearch:
false` needs a gate and not just a note.

---

### H39-03 — Releases generalize into execution units

**Prerequisites:** H39-01. The highest-risk packet in M2: it touches the parsing every other signal is derived from.

**Scope (edit only):** both detection mirrors; both evaluators; `standards/roadmap/roadmap-contract.schema.json` and its spec twin; `scripts/Invoke-ModuleSmokeTest.ps1`.

**Steps**

1. Replace `releaseHeadingPattern` with `executionUnitHeadingPattern`
   (`Release|Milestone|Phase|Iteration` + identifier + dash + title). Retire
   `releaseScopedSignals` / `releaseScopedSignalsNote`.
2. Emit `executionUnitCount`, and per unit: `pendingCount`, `normalizedStatus`,
   `hasAcceptanceCriteria`, `hasOutOfScope`.
3. Emit the five aggregate signals ROADMAP-006 and ROADMAP-007 need
   (`pendingExecutionUnitCount`, the two `…Without…` counts, the two
   `executionUnitsWith…` counts) per `detection.executionUnitSignals`.
4. Add the execution-unit array to the contract schema; `releases` stays as an
   alias for one release so nothing downstream breaks mid-series.

**Gate:** the four-release fixture (this repository's own roadmap) yields
`executionUnitCount = 4`, `pendingExecutionUnitCount = 4`, and zero units
missing acceptance criteria or scope — the values §0.4 computed by hand, so the
implementation is checked against an independently derived number rather than
against itself. A second fixture using `## Milestone 1 — …` headings scores
**identically** to a `## Release 1.0 — …` one; that equivalence is the whole
point of the generalization. A third fixture with no pending work anywhere
exercises the "demonstrate the practice once" branch.

**Stop if:** the generalized pattern matches a heading the v1.5 pattern did not,
anywhere in the corpus, that is *not* a genuine execution unit — report each,
because an ordinary prose heading read as a dispatchable unit is the failure
mode `executionUnitHeadingNote` warns about.

---

### H39-04 — Current target separates from lifecycle status

**Prerequisites:** H39-03.

**Scope (edit only):** both detection mirrors; both evaluators; both contract schemas; `scripts/Invoke-ModuleSmokeTest.ps1`.

**Steps**

1. Implement `currentTarget.explicitPattern` (`> Current: true`).
2. Implement `resolutionOrder` exactly as written, in order: explicit
   candidates first; the single-`active` inference only when there are none;
   one candidate resolves; more than one is ambiguous.
3. Emit `currentTargetCandidateCount` and `currentExecutionUnit` (null, or the
   resolved unit carrying `normalizedStatus` and `pendingCount`).

**Gate:** a fixture whose `blocked` unit carries `Current: true` resolves that
unit as current **and** keeps its status `blocked` — the separation v2.0 exists
to make. Two `Current: true` units give `currentTargetCandidateCount = 2`. A
v1.5-shaped fixture with one `active` unit and no explicit marker still resolves
(backward compatibility, D-017). A fixture with an explicit marker on one unit
and `active` on a *different* one resolves the explicit one, and the smoke says
so in words.

**Stop if:** nothing.

---

### H39-05 — Task format and task quality

**Prerequisites:** H39-01.

**Scope (edit only):** both detection mirrors; both evaluators; `scripts/Invoke-ModuleSmokeTest.ps1`.

**Steps**

1. Move `taskFormat.uncheckedPattern` / `checkedPattern` into the detection
   contract; neither evaluator keeps a private checkbox regex.
2. Implement `taskQuality`: a task fails **only** when it is a placeholder, or
   when it opens with a broad verb **and** falls short of *both* minimums
   (5 words, 24 characters). The conjunction is the rule — implementing it as a
   disjunction fails ordinary well-specified work that happens to start with
   "Fix".

**Gate:** the boundary cases directly, since this rule is now a `warning`
carrying weight 8 rather than an `info` carrying 5 — `"Fix the parser"` (vague,
too short) fails; `"Fix the parser so nested lists keep their indentation"`
(broad verb, enough detail) passes; `"TBD"` fails as a placeholder; a task of
exactly 5 words and 24 characters passes, because "meets both minimums" is the
threshold and off-by-one here silently penalizes real work. This repository's
own 75 items yield `vagueItemCount = 0` (§0.4).

**Stop if:** nothing.

---

### H39-06 — `no-supported-tasks`, with the shim that keeps the estate readable

**Prerequisites:** H39-05.

**Scope (edit only):** both evaluators; `Portfolio.Assessment.ps1` (8 sites), `Portfolio.Conclusion.ps1` (3), `Portfolio.Report.ps1`, `Execution.Ledger.ps1`, `DocAudit.Scanner.ps1`, `Automation.DocRefinement.ps1`; `frontend/components/RepoGrid.tsx`, `OperationsWorkspaceView.tsx` and the other eight components carrying the token; `scripts/Invoke-ModuleSmokeTest.ps1`.

**Steps**

1. Backend emits `no-supported-tasks` (v2.0's `roadmapState` vocabulary).
2. **The shim, per A27**: one mapping function, one place, translating the new
   token to the old at the API boundary until the frontend is migrated in this
   same packet. It exists so backend and frontend can be correct at different
   moments within one commit, not so the old token can survive.
3. Migrate the frontend token: badge maps, the filter option, the
   `RoadmapBadgeState` union, `dispatchReadiness`, and the
   `'ROADMAP without checklist items'` tooltip — which should now say what it
   means, that the file exposes no checkbox items automation can select.
4. Delete the shim in the same commit, and gate that no `no-checklist` literal
   survives outside a cache-compatibility reader.

**Gate:** a grep tripwire for the retired literal, exempting only the cache
reader; the `RepoGrid` filter round-trips the new token; the UI-debt ratchet
still passes (new UI text at `text-sm`).

**Stop if:** a persisted cache carries `no-checklist` — it must be *read*
through a compatibility path, never rewritten in place, and the reader is
covered by A24's `rulesVersion` refusal.

---

### H39-07 — Measure the estate under both packs, before anything flips

**Prerequisites:** H39-02 … H39-06. Cheap, and it is what makes H39-08 safe.

**Scope (edit only):** `tools/Test-RoadmapContract.ps1` (a `-RulesPath` comparison mode); a new `output/` report. **No evaluator semantics change here.**

**Steps**

1. Run both evaluators over the 15-roadmap corpus under **v1.5 and v2.0**, and
   emit one row per repository: score, maturity, `executionState`,
   `dispatchEligibility`, and findings under each pack.
2. Name explicitly:
   - every repository whose maturity level **changes**;
   - every repository crossing the **L3 dispatch threshold** in either
     direction — these stop or start being packaged by
     `Test-RoadmapPackagingCandidate`;
   - every repository that becomes `L0-Absent` through bounded discovery
     (D-018);
   - any repository where the two evaluators **disagree** under v2.0, which is
     a parity break and blocks H39-08 outright.
3. Publish it as the human-readable report plus JSON, stating the data window
   and the corpus root.

**Gate:** parity holds under v2.0 across all 15 roadmaps — `identicalFull = 15`,
as the current parity output records for v1.5. Anything less stops the series
here.

**Stop if:** any repository's maturity drops in a way that removes it from
packaging. That is Ben's call to accept, not an agent's, and the report is what
he needs to make it.

---

### H39-08 — The flip: scoring, caps, IDs, Repairer, caches

**Prerequisites:** H39-07 and its report. The single commit where scores change.

**Scope (edit only):** both evaluators; `Roadmap.Repairer.ps1`; the audit cache reader; `roadmap-audit-rules.json` in both locations; `scripts/Invoke-ModuleSmokeTest.ps1`; `scripts/Invoke-ApiHostSmokeTest.ps1`.

**Steps**

1. Read `scoring.mode = normalized-applicable` from the contract: rules whose
   `applicabilityCondition` is false leave the **denominator**, not just the
   numerator.
2. Read `terminalStates` — `missing` short-circuits to score 0 / `L0-Absent` /
   `absent` / `not-eligible` without weighted scoring.
3. Read `maturityCaps` from the contract instead of implementing caps in
   `_ScoreToMaturityLevel`: severity caps, `ruleOverrides`, and
   **most-restrictive-wins**.
4. Promote `-v2` to the canonical `roadmap-audit-rules.json` in both locations.
   The IDs now carry their v2.0 meanings.
5. **Remap all nine `Roadmap.Repairer.ps1` cases** to the new meanings (§0.1).
   `EXPAND-PENDING-ITEMS` and `ADD-RELEASE-SECTIONS`-for-009 have no v2.0
   counterpart and are deleted rather than repointed at the nearest-looking
   rule.
6. Stamp `rulesVersion` on every persisted audit record and **refuse** a record
   whose version the reader does not understand (A24). Bump the cache
   `schemaVersion` so pre-v2 entries are re-audited rather than reinterpreted.

**Gate:** a fixture failing only ROADMAP-009 caps at `L2-Structured` **even
though its normalized score would reach L3** — the cap and the score must be
able to disagree, or `maturityCaps` is decorative. A fixture where ROADMAP-003
is not applicable scores higher than one where it applies and fails, proving the
denominator moved. A v1.5-stamped cache entry is **refused by name**, and the
message says re-audit. Every remapped Repairer action is asserted against its
new rule's meaning — this is the assertion that catches §0.1 if step 5 is ever
partially reverted.

**Stop if:** H39-07's report was not produced, or shows a parity break. Flipping
without the measured delta is the one thing this ordering exists to prevent.

---

### H39-09 — `executionState` and `dispatchEligibility`

**Prerequisites:** H39-08. Gated on **D-016**; ships advisory under the default.

**Scope (edit only):** both evaluators; both contract schemas; `Start-RepoManagementApiHost.ps1`; frontend audit modal.

**Steps**

1. Implement both `derivationOrder` ladders in order, from the contract.
2. Publish both beside the existing verdict. Under D-016's default they **bind
   nothing**; `Test-RoadmapExecutionContract` and the 3.8 provider router keep
   deciding.
3. Where the advisory verdict and the binding one disagree, **show the
   disagreement** rather than hiding one. A repository that reads
   `L4-Orchestration-Ready` and `dispatchEligibility: no-work` is not a
   contradiction and the UI must not present it as one — that pairing is
   precisely what separating maturity from state buys.

**Gate:** an L4 roadmap with zero pending work reads `executionState: complete`
and `dispatchEligibility: no-work`, and is **not** reported as defective — the
v2.0 description's stated purpose, asserted directly. A blocked current target
reads `blocked` in both outputs while maturity stays wherever it is.

**Stop if:** implementing the ladders requires a signal not already produced —
it should not; report it if so, because that means H39-01's coverage gate missed
something.

---

### H39-10 — The written standard catches up

**Prerequisites:** H39-08.

**Scope (edit only):** `ROADMAP_MATURITY_MODEL.md`, `ROADMAP_TEMPLATE.md`, `roadmap-repair-prompt.md`, `standards/roadmap/README.md`, `standards/MANIFEST.md`, `docs/reference/roadmap-contracts.md`, `CHANGELOG.md`, and the `spec/roadmap-contract/` twins.

**Steps**

1. Rewrite the maturity model for execution units, the current-target
   separation, applicable-only scoring and the caps.
2. `ROADMAP_TEMPLATE.md` gains `> Current: true` beside `> Status:`, with one
   sentence on why they are different questions (D-017: recommended, not
   required).
3. `roadmap-repair-prompt.md` must match the remapped Repairer actions — it is
   the prose an agent is handed, so a stale copy reintroduces §0.1 through the
   prompt instead of through the code.

**Gate:** the standards↔spec sync gate (now 8 assets); the existing
roadmap-standards drift detector; no `- [ ]` example in the template fails the
new `taskQuality` rules, which would be an embarrassing way to find out.

**Stop if:** nothing.

---

## 3. What this changes for the estate

| Consequence | Evidence today | Which packet settles it |
| --- | --- | --- |
| Repositories may cross the L3 packaging threshold in either direction | unmeasured | H39-07 |
| Nested-only roadmaps become `L0-Absent` | unmeasured | H39-07, D-018 |
| Nine repair actions currently keyed to v1.5 meanings | read directly from `Roadmap.Repairer.ps1` | H39-08 |
| Stored findings become uninterpretable across the flip | cache + parity output both key by ID | H39-08, A24 |
| `no-checklist` appears in 10 frontend components and 12 backend sites | grepped | H39-06 |
| This repository's own score | 100 / L4 under both packs, computed | none needed |
| This roadmap resolves **Release 2.9** as its current target while work happens in 3.8 | computed in §0.4 | not a packet — a roadmap edit, worth doing regardless |
| Locally added rules (ROADMAP-013/014 from H-13a) are absent from the vendored pack | read from `HAIKU-WORK-PACKETS.md` H-13a | H39-01 step 5, §0.5 |

---

## 4. Not in scope

- **Renumbering the rule pack's IDs.** A23 — the pack is an external contract.
- **Making `dispatchEligibility` binding.** D-016 is Ben's.
- **Requiring `> Current: true` estate-wide.** D-017 is Ben's.
- **Editing other repositories' roadmaps to score better under v2.0.** The audit
  measures; Release 3.7 decides what to do about what it measures.
- **Anything in Release 3.8.** The two series touch disjoint modules apart from
  `Start-RepoManagementApiHost.ps1` and `Invoke-ModuleSmokeTest.ps1`, so they
  could run in parallel — but per A28 this series is sequenced after 3.8 and
  before 3.7's measured execution.

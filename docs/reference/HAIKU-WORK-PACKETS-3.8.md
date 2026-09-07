<!-- markdownlint-disable MD036 -->
<!--
  MD036 (emphasis-as-heading) is disabled for this file only. A packet's
  **Why** / **Scope** / **Steps** / **Gate** / **Stop if** labels are a fixed
  form the executing agent matches on, not section headings: promoting them to
  real headings would put ~250 entries in the document outline and break R11's
  reading budget. Every other rule applies normally.
-->

# Haiku Work Packets — Release 3.8, Provider-Aware Execution

> **Derived from:** `ROADMAP.md` §6 "Release 3.8" and §8 as of 2026-09-06, and
> [`docs/governance/Agent-Execution-Governance.md`](../governance/Agent-Execution-Governance.md)
> (the design authority — where it and the roadmap differ, the spec wins and the
> packet says so). This file is a *rendering* of that release for a small
> executing model; the roadmap and the spec stay the sources of truth. If they
> disagree with a packet here, **stop and report** — do not reconcile them.
>
> **Who this is for:** an autonomous coding agent (Claude Haiku 4.5 or similar)
> working one packet at a time in Claude Code. Every packet is a bounded unit:
> named files, numbered steps, a gate that must be red before it is green, exact
> verification commands, and a written stop condition. Nothing in a packet
> requires a judgement call; where the spec or roadmap left one, this file
> either made it (§A, for Ben to veto) or emitted it as a decision (§B) and
> made the dependent packets stop on it.
>
> **Companion file.** [`HAIKU-WORK-PACKETS.md`](HAIKU-WORK-PACKETS.md) §0
> (operating rules R1–R10) applies here in full. This file adds rules
> R11–R17 below, which exist because Release 3.8 touches the runner, the host
> and the frontend at once.

---

## 0. Additional operating rules for this file

**R11. Reading budget for 3.8.** Read, in this order and nothing else unless a
packet names it: `HAIKU-WORK-PACKETS.md` §0, `ROADMAP.md` §8, the packet you are
executing, the roadmap's Release 3.8 milestone the packet names, and the spec
section the packet names by heading. Do **not** read the spec end to end per
packet; the packet quotes what it needs.

**R12. Offline means offline, including how the fixtures are obtained.** No
packet runs `claude`, `codex`, `gh`, or the live portal, and **no packet may
require spending provider quota — not to execute, and not to produce a
fixture.** Provider behaviour is gated against transcripts under
`tests/fixtures/providers/`, and every one of those is **authored
synthetically** by the packet that needs it, from the provider's documented
output shape, committed as `<name>.synthetic.jsonl`.

The first version of this file got that wrong: it made a recorded transcript an
operator prerequisite of H38-04, the fourth packet of thirty-seven, which put a
subscription spend in front of the whole release and contradicted this very
rule. Corrected 2026-09-07.

**Real transcripts arrive for free, and are never a prerequisite.** Every
headless run writes its provider-native output beside the run summary
(`<runId>.claude.stream.jsonl`, H38-04 step 4), so the first genuine dispatch
leaves a real transcript as a byproduct. Promoting one to a fixture is a file
copy, and the packet that consumes it asserts against **both** when the real
one is present. Because a synthetic fixture encodes an assumption about a
shape, every adapter parses **defensively** — unknown fields are recorded, a
missing expected field is a named condition, never a crash — so a wrong
assumption surfaces as a diagnosable mismatch rather than a confidently wrong
parse.

**R13. One line, one state.** The roadmap write-back edits only the milestone's
`_(state: …)_` clause. Never insert a line break between `(state:` and the
state word — `tools/Test-RoadmapCapabilityRecord.ps1` matches `(state: <word>`
on one physical line. The description after the word may wrap as the rest of
the file does.

**R14. State ladder for a multi-packet milestone.** The **first** code packet of
a milestone changes `_(state: planned)_` to
`_(state: scaffolded <date> — <packet id> <one clause>)_`. Every later packet
**appends** `; <packet id> <one clause>` inside the same parentheses. The
milestone's **closing** packet changes the state word to `smoke-tested`. A commit
prefixed `feat(release-3.8):` that touches `backend/` or `scripts/` without one
of these edits is rejected by CI (`Test-RoadmapCapabilityRecord.ps1`).

**The append must land on the physical line that carries `(state:`.** That gate
reads only the **added** lines of `ROADMAP.md` in the commit and looks for
`(state: <word>` where the word is not `planned`. A state clause wraps across
several lines, so appending to its tail leaves the `(state:` line unmodified,
it never appears as an added line, and the gate fails a commit that did record
its capability correctly. Discovered the hard way in H38-02. **Rewrap the whole
clause** so the `(state:` line itself is part of the diff, then confirm with
`git show --unified=0 HEAD -- ROADMAP.md` before pushing.

Thirty-seven appends make the Release 3.8 section outgrow the 120-line budget
`R013-FUTURE-RELEASE-SIZE` prefers, and they lengthen `ROADMAP.md` past
`R010-FILE-LENGTH`. Both are **warnings, not errors** (severity checked
2026-09-06 in `tools/Test-RoadmapStructure.ps1`), and the release was at 115
lines when this file was written. A **new warning** from either of those two
codes is the expected cost of recording capability and is not a stop condition.
A new validator **error**, or a warning with any other code, still is.

**R15. New PowerShell.** A new file under `backend/modules/` is a **param-less
library** (no `param()` block at file scope — the module smoke asserts this over
every file the host dot-sources). Start it with
`Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`. Wrap
every `$x = if (…) { @(…) } else { @() }` as `$x = @(if (…) { … } else { @() })`
— `tools/Assert-NoArrayCollapsingIfExpression.ps1` holds a zero baseline. Use
singular nouns in function names (`Get-ProviderCapacityRecord`, never
`Get-ProviderCapacities`) — `scripts/Invoke-LintGate.ps1` ratchets
`PSUseSingularNouns`. Do not use `??` or the ternary in a new module (the
runner is `#Requires -Version 7.0`; modules are not).

**R16. New route, five gates.** A new API route must be: (1) added to the
`$censusRoutes` list in `scripts/Invoke-ApiHostSmokeTest.ps1` if it is a GET;
(2) dot-sourced from a param-less library, never a script; (3) asserted by one
api-host smoke step that reads its JSON body; (4) refused with structured JSON
on bad input (400/404/409), never a thrown 500; (5) named in the packet's
report with its method and path.

**R17. Frontend.** New text is `text-sm` or larger (`tools/Measure-UiRatchet.mjs`
fails a new `text-xs`). `npm run lint` runs with a fixed `--max-warnings`; one
new warning fails. Empty arrays from the host must serialize as `[]` — normalize
at the API-client boundary as `frontend/lib/copilotTaskPacket.ts` does.

---

## A. Decisions made by this file (Ben can veto any of these)

Each is a choice the spec or roadmap left open that is **not** a product or
security judgement. Vetoing one means editing the packets that cite it.

| # | Decided here | One-line reason | Packets |
| --- | --- | --- | --- |
| A1 | The WorkPacket is persisted at `output/work-packets/<runId>.workpacket.json`; the ExecutionResult beside the run summary at `output/roadmap-task-history/runs/<runId>.result.json`. | `output/` is gitignored, which is exactly "outside files eligible for commit"; the run summary already lives there. | H38-01, H38-03 |
| A2 | Provider configuration is its own file, `backend/config/agent-providers.json` with `"schemaVersion": "v1"`, loaded like `foundation-domains.json`. | Application config, separate concern from `settings.json`; the reserve percentages the spec calls "configuration, not hard-coded constants" get a home that `Remove-StoredSecretsFromSettings` never touches. | H38-07 |
| A3 | Provider tokens are `claude`, `codex`, `copilot`, and `auto`. `operator-runner`, which `POST /api/automation/packages/approve` writes, is a dispatch *channel*, not a provider, and is replaced by the resolved token. An absent token still resolves to `claude` (pre-3.0 entries). | One vocabulary; the third value is the contradiction the roadmap names. | H38-14, H38-18 |
| A4 | The `IAgentExecutor` interface is a fixed set of **seven function names per provider** in `backend/modules/agent-adapters/Adapter.<Provider>.ps1`: `Get-<P>AdapterCapability`, `Get-<P>AdapterCapacity`, `Start-<P>Execution`, `Resume-<P>Execution`, `Stop-<P>Execution`, `ConvertTo-<P>CanonicalEvent`, `Get-<P>ExecutionResult`. The registry asserts all seven exist per enabled provider. | PowerShell has no interfaces; a name contract checked by `Get-Command` is the offline-testable equivalent. `Stop-` not `Cancel-`: approved verb. | H38-15 |
| A5 | Claude Code runs headless as `claude -p --output-format stream-json --verbose --permission-mode <mode>`; the adapter parses JSONL and the last line whose `type` is `result` is the ExecutionResult source. Interactive mode (no `-Headless`) writes an ExecutionResult with `source = 'interactive'`, null session id and null usage. | `stream-json` yields the same final object as `--output-format json` plus the progress lines M6 needs; parsing once avoids a second adapter later. | H38-04 |
| A6 | Capacity records are one JSON file per provider at `output/provider-capacity/<provider>.json`, authoritative, no SQLite mirror in 3.8. `activeExecutions` is **derived** from run summaries in `running` state for that provider, never stored as a counter — subject to the staleness rule in A19, so a crashed runner's `running` summary cannot hold the slot. | A stored counter is exactly the in-memory-only state the spec forbids, one crash away from a stuck slot; run summaries already persist. | H38-08, H38-11 |
| A7 | Limit-signal detection is data: `agent-providers.json` carries `limitSignals` (regex per provider) matched against the adapter's error/result text. The real Claude and Codex limit transcripts are operator-recorded when they next occur; until then a synthetic fixture built from the configured regex proves the mechanism. | The exact wording of a usage-limit response is unknowable offline; a regex in config can be corrected without a code change. | H38-10 |
| A8 | `dispatchTarget: auto` is **resolved at claim time by the runner**, which is the process that can see authentication and capacity; the host records a `provisionalSelection` at dispatch for the board to show. The runner writes `selectedProvider` and `selectionReason[]` onto the run summary. | The host is a LocalSystem service that holds no provider credential; only the operator session can answer "eligible". | H38-17 |
| A9 | Push after `IMPLEMENTATION_COMPLETE` is the **runner's** step (it has the operator's git credential helper); PR opening is the **host's** step on the next reconciliation tick (it holds the token `Open-RepoBranchPullRequest` needs). A per-provider `autoPush` flag in config, default `true`, keeps today's `awaiting-review` reachable at `false`. | Splits the two credentials across the two processes that actually hold them; the flag is a rollback lever, not a second design. | H38-21, H38-22 |
| A10 | The reconciliation tick is `POST /api/delivery/reconcile`, called by the runner every fourth poll (60 s at the default 15 s) and callable by the external cron that already fires `POST /api/automation/run`. The host has no in-process timer and gains none. The runner's call targets `https://127.0.0.1:7071` (the portal has served TLS only since Lane 0.2 shipped 2026-08-29; plain `http://` does not answer), skips certificate validation the way `Watch-PortalHealth.ps1` does, and sends `X-Api-Key` from `REPO_MGMT_API_KEY` exactly as the api-host smoke's `Invoke-ApiRequest` does — an unauthenticated POST is a 401 on the shared-LAN configuration. | The runner is the only always-on operator-session process; the host's accept loop is single-threaded by design. Every other loopback caller in the repository already learned the https and api-key lesson (Lane 0.2 "HTTPS flip's fallout"); a new caller does not relearn it. | H38-22 |
| A11 | The verified head SHA, readiness-for-operator, and operator approval live on the **agent-run record** as `verifiedHeadSha`, `readyForOperatorAt`, `operatorApproval { sha, at, actor }`; the merge route refuses when the PR's current head is not the approved SHA. | The agent-run record is what merge readiness already evaluates; one record, one join key. | H38-23, H38-24 |
| A12 | The remediation cap is config (`maxRemediationAttempts`, default 2) and persists on the run summary as `remediationCount` **before** any halt. | Same bootstrap-threshold posture Ben accepted in D-007; the value is visible on every halt so a wrong one is loud. | H38-27 |
| A13 | `execution.*` events are written to the existing append-only `output/agent-runs/events.jsonl` through `Write-AgentRunEvent`; that stream is canonical. `roadmap-events.jsonl` in a managed repository stays optional and may receive a derived `lifecycle` event; it is never written by an adapter. | One append-only stream already exists with schema versioning and a SQLite mirror; a second would be the drift the roadmap milestone forbids. | H38-33, H38-34 |
| A14 | The revised state machine lands as a **sixth vocabulary dimension**, `Delivery state`, whose tokens are the spec's states lower-kebab-cased (`capacity-wait`, `implementation-complete`, …). The spec's `DISCOVERED`/`FORMING`/`QUALIFIED` are not per-task states; they are the existing *Dispatch readiness* dimension and the vocabulary says so. `complete` is shared with the *Execution lane* dimension, so its display term is qualified, exactly as `ready` and `blocked` already are. | The Release 3.5 rule is about display words; shared machine tokens with distinct display terms are already how the glossary test works. | H38-34 |
| A15 | A capacity wait is **not** a stalled lane. `Resolve-LaneObservation` keeps verdict `queued` and sets `stalled = $false` while `capacityWait.resetAt` is in the future, with the detail naming the provider and reset time. No new verdict token. | Widening the verdict union would touch four typed surfaces for a distinction the detail text carries. | H38-35 |
| A16 | Local execution concurrency is one slot: the runner refuses to claim a `claude` or `codex` task while any run summary shows `status = running` for a local provider. The execution ledger's **two lanes are unchanged** — they are portfolio concurrency and count Copilot. | Spec: "1 local execution slot", "Copilot … still accounted as an active provider execution". The lanes already are that accounting. | H38-11 |
| A17 | When a matched limit signal carries no parseable reset time, the provider's `cooldownUntil` is **now + 60 minutes**, the record carries `cooldownSource = 'rate-limit-response'` and `resetAssumed = $true`, and the next `Get-<P>AdapterCapacity` observation (H38-12) may shorten or lengthen it. | Sixty minutes is the shortest window any provider in scope resets on; an assumed value that is visibly flagged beats a task that never re-queues. Ben may veto the number. | H38-10 |
| A18 | `auto` routing stays **off until the router exists**. `agent-providers.json` carries `dispatch: { defaultTarget: "claude", autoEnabled: false }`. The dispatch route defaults an absent `dispatchTarget` to `dispatch.defaultTarget`; an explicit `auto` while `autoEnabled` is false is a 400 (`validation`). H38-17's last step flips both values to `auto` / `true`. Remediation entries (H38-31) use `dispatch.defaultTarget` the same way. **D-013 was decided 2026-09-07, so that step runs** — but the flag stays false through packets H38-07 to H38-16, because nothing may write a token the runner cannot yet claim. | Without this, H38-18 defaulting to `auto` before the router is built leaves every board dispatch queued forever. | H38-07, H38-11, H38-17, H38-18, H38-31 |
| A19 | A `running` summary counts toward `activeExecutions` only while the runner heartbeat file (`output/roadmap-task-runner.heartbeat.json`) exists, its `lastHeartbeatAt` is within **10 minutes** of now, and its `pid` equals the summary's `runnerPid` (a new field written at claim). At startup the runner marks every other `running` summary for a local provider `status = 'failed'`, `failureCategory = 'orphaned'`, keeping `branch`, `attempt` and `providerSessionId`. | A runner that dies mid-run leaves `running` on disk forever; deriving the count from summaries alone would then refuse every local claim. The heartbeat is the liveness evidence the portal already trusts, and one runner means one pid. | H38-11 |

## B. Decisions needed — Ben's call, not Haiku's

Add each to `docs/governance/open-decisions.md` as written here (the packet that
first needs it does that in its scope). A packet that lists one under **Stop
if** checks the register's **Decided** section and stops if the entry is not
there.

| # | Question | Why not an agent's call | Default if unanswered | Packets that stop |
| --- | --- | --- | --- | --- |
| D-011 | Are the spec's initial reserves right — short-window **15%**, weekly **20%**, remediation inside the weekly reserve — and what is the default per-task consumption estimate (the spec gives none)? | Reserve size is the whole risk posture of the release: too high starves ordinary work, too low exhausts a subscription. | Config ships the spec's 15/20 marked `"provisional": true`; the estimate defaults to `0.05` of the short window and is marked the same. Records are written, verdicts are **not enforced**. | H38-09, H38-17 |
| D-012 | What is the default permission envelope and scope? The spec's example is `filesystemWrite true, shell true, network false, githubWrite false`, `forbiddenPaths [".github/workflows/**"]`. Confirm, and say whether an agent may edit workflow files (the July design said yes, flagged). | Security posture of every agent run. | Config ships the spec's example marked provisional; the packet carries it; **no adapter enforces it** (no `--allowedTools` mapping) until decided. | H38-05 (enforcement half only), H38-16 (`--sandbox` mapping) |
| D-014 | Which GitHub Copilot billing mode does this account use — AI credits, or the legacy premium-request allowance? | The spec forbids assuming the generation; the answer is on the account, not in the repo. | The Copilot adapter's `Get-CopilotAdapterCapacity` returns one window with `unit: "unknown"`, `confidence: "none"`, `available: true`; routing treats Copilot as eligible-but-unmeasured. | H38-15 (capacity half only) |
| D-015 | Is Codex (`codex` CLI, an account with capacity) available on the operator's machine at all? | Whether a tool is installed and funded is a fact about the machine and the account, not the repository. | `codex` ships in config with `"enabled": false`; the router works with two providers; H38-16 is blocked. **No transcript is needed to answer this** — H38-16 authors a synthetic fixture like every other packet (R12). | H38-16, H38-29 (Codex resume half) |

**All five are now in the register**, so a packet's **Stop if** reads
`open-decisions.md` rather than this table. D-011, D-012, D-014 and D-015 are
under **Open**.

**D-013 was answered 2026-09-07 and is under Decided.** All eight ranking
weights stand as they ship (`+1` each, `-1` for the two negative factors) as a
first-run baseline, and the tie-break is `nearest-reset-first`, not the
`alphabetical` this file originally proposed. H38-07 therefore ships the
decided values with no `provisional` flag on `ranking`, and H38-17's final step
runs rather than being skipped.

## C. Operator prerequisites (before any packet in the named column starts)

| Prerequisite | Needed by | How |
| --- | --- | --- |
| `HAIKU-WORK-PACKETS.md` H-05 landed (heartbeat path override), H-07 (dispatch authority), H-10 (check-run detail), H-13a and H-13b (dependencies) | H-05: all runner packets; H-07: H38-35; H-10: H38-23, H38-28; H-13a/b: H38-17 | Execute those packets first. Each 3.8 packet that depends on one names it under **Prerequisites**. |
| D-011, D-012, D-014, D-015 answered | see §B | `open-decisions.md` **Decided** section. D-013 is already decided. |

**No fixture is an operator prerequisite.** Every provider transcript this
release gates against is authored synthetically by the packet that needs it
(R12), so nothing here waits on a subscription spend. Real transcripts are
collected opportunistically, from runs that were going to happen anyway:

| Real transcript | Where it appears on its own | What to do with it |
| --- | --- | --- |
| Claude success | `output/roadmap-task-history/runs/<runId>.claude.stream.jsonl` after any headless dispatch | Copy to `tests/fixtures/providers/claude-stream-json-success.jsonl`; H38-04's gate then asserts against it **as well as** the synthetic one, and any shape difference is a finding worth acting on |
| Claude usage limit | the same path, the next time a limit is actually hit | Copy to `claude-stream-json-usage-limit.jsonl`; H38-10 already asserts against both |
| Codex success | the equivalent path once the Codex adapter runs | Only relevant if D-015 is yes |

---

## 1. Packet index (execute in this order)

Ordering is dependency-driven and contract-first: the packet and result
schemas before anything that consumes them; the registry before the Codex
adapter; capacity persistence before routing; SHA-bound approval before
remediation. **Prereq** names packet ids from this file (`H38-`) or the
companion (`H-`).

| Id | Milestone | Title | Prereq | Risk |
| --- | --- | --- | --- | --- |
| H38-01 | M1 | `WorkPacket` contract module, schema v1, persisted under `output/work-packets/` | — | low |
| H38-02 | M1 | Build the WorkPacket at dispatch and carry `workPacketPath` on the queue entry | H38-01 | medium |
| H38-03 | M1 | `ExecutionResult` contract; a run with no structured result fails by name | H38-01 | medium |
| H38-04 | M1 | Claude adapter: `stream-json` → ExecutionResult with session id and usage | H38-03 | high |
| H38-05 | M1 | Render the packet into the provider prompt; acceptance criteria travel verbatim | H38-02 | medium |
| H38-06 | M1 | Milestone 1 closing: runner doc, vocabulary note, state → `smoke-tested` | H38-01…05 | low |
| H38-07 | M2 | `backend/config/agent-providers.json` + loader + config tripwire | — | low |
| H38-07b | M2 | Dispatch reads scope and permissions from config; H38-02's literals go | H38-07, H38-02 | low |
| H38-08 | M2 | Capacity record contract: windows in native units, confidence rank, persistence | H38-07 | low |
| H38-09 | M2 | Reserve arithmetic and the capacity verdict (`Resolve-ProviderCapacityVerdict`) | H38-08, D-011 | medium |
| H38-10 | M2 | A provider limit re-queues the task (`CAPACITY_WAIT`), never fails it | H38-04, H38-08 | high |
| H38-11 | M2 | The runner refuses to claim during cooldown and enforces one local slot; orphaned runs do not hold it; `auto` defers to the router | H38-10, H-05 | medium |
| H38-12 | M2 | Capacity observed from usage and provider status, `GET /api/providers` | H38-08 | medium |
| H38-13 | M2 | Milestone 2 closing: state → `smoke-tested`, doc, vocabulary note | H38-07…12 | low |
| H38-14 | M3 | Provider registry replaces the hardcoded `claude`/`copilot` pair, one definition | H38-07 | medium |
| H38-15 | M3 | Adapter conformance gate; Copilot adapter wraps the existing runner functions | H38-14, H38-04 | medium |
| H38-16 | M3 | Codex adapter from a synthetic fixture; runner branch for `codex` | H38-15, D-015 | high |
| H38-17 | M3 | Router: eligibility then ranking, reason recorded, resolved at claim time; turns routing on | H38-09, H38-15, H-13b | high |
| H38-18 | M3 | One vocabulary at the host: dispatch/execute accepts a target (default from config), approve route stops writing `operator-runner`, backlog by provider | H38-14 | medium |
| H38-19 | M3 | Frontend: target union, presence payload by provider, preview names the intended provider | H38-18 | medium |
| H38-20 | M3 | Milestone 3 closing | H38-14…19 | low |
| H38-21 | M4 | The runner pushes after `IMPLEMENTATION_COMPLETE` when `autoPush` is on; `awaiting-review` survives at off | H38-03, H38-14 | high |
| H38-22 | M4 | `POST /api/delivery/reconcile`: open pending PRs, refresh CI, called from the runner's poll loop over https with the api key | H38-21 | high |
| H38-23 | M4 | Record `verifiedHeadSha` and `readyForOperatorAt` when CI passes on a known head | H38-22, H-10 | medium |
| H38-24 | M4 | `POST /api/agent-runs/{id}/approve` binds approval to a SHA; merge refuses on head drift | H38-23 | high |
| H38-25 | M4 | Frontend: approve control shows the SHA it approves; merge control disabled on drift | H38-24 | medium |
| H38-26 | M4 | Milestone 4 closing; Lane 0.17 cadence non-blocker written back | H38-21…25 | low |
| H38-27 | M5 | Attempt and remediation counters, persisted before any halt, cap from config | H38-03 | low |
| H38-28 | M5 | `RemediationPacket` from CI evidence | H38-27, H38-23 | medium |
| H38-29 | M5 | Resume the original session where capacity allows (Claude; Codex fixture-gated) | H38-28, H38-09 | high |
| H38-30 | M5 | `HandoffPacket`: durable evidence only, cross-provider redispatch | H38-29, H38-17 | medium |
| H38-31 | M5 | `CI_FAILED` → remediation enqueue on the reconcile tick, bounded by cap and capacity | H38-30, H38-22 | high |
| H38-32 | M5 | Milestone 5 closing; Lane 0.18 carryover and cap items written back | H38-27…31 | low |
| H38-33 | M6 | Canonical `execution.*` event vocabulary on the existing append-only stream | H38-04, H38-15 | medium |
| H38-34 | M6 | Vocabulary reconciliation: sixth dimension, glossary, `roadmap-events.md` + mirror | H38-33 | medium |
| H38-35 | M6 | Dispatch Board renders provider, capacity, selection reason; capacity wait is not stalled | H38-19, H38-12, H-07 | medium |
| H38-36 | M6 | Milestone 6 closing; Release 3.8 acceptance-criteria audit | H38-33…35 | low |

Everything in Release 3.8 or Lane 0.18 not in this table is in §3, with the reason.

---

## 2. Packets

### H38-01 — `WorkPacket` contract module

**Roadmap item:** Release 3.8 M1, `Give a task a provider-neutral contract and a structured result.` Spec section: *Canonical task contract*.

**Why:** the spec's core invariant is that every provider receives the same logical `WorkPacket`. Nothing in the repository is that object today: `Build-ReleaseDispatchPacket` in `backend/modules/roadmap/Roadmap.Dispatcher.ps1` returns a release packet whose only agent-facing artifact is `generatedPrompt`, a string.

**Scope (edit only):** new `backend/modules/execution/Execution.WorkPacket.ps1`; `backend/api-host/Start-RepoManagementApiHost.ps1` (dot-source line only); `scripts/Invoke-ModuleSmokeTest.ps1` (module-presence list at the `Validating copied module files exist` step, plus one new section); `ROADMAP.md`.

**Steps**

1. Create the module (R15). Define `$script:WorkPacketSchemaVersion = 1` and `New-WorkPacket` with **exactly** these parameters, all mandatory unless stated: `-TaskId` (string), `-Repository` (string, `owner/repo` or `''`), `-BaseBranch` (string), `-BaseSha` (string, may be `''`), `-Objective` (string), `-AllowedPaths` (string[], default `@('**')`), `-ForbiddenPaths` (string[], default `@()`), `-AcceptanceCriteria` (string[], default `@()`), `-VerificationCommands` (string[], default `@()`), `-Permissions` (hashtable with keys `filesystemWrite`, `shell`, `network`, `githubWrite`, all bool), `-Attempt` (int, default 1), `-PreferredProvider` (string, default `'auto'`), `-PreviousSessionId` (string, default `''` → stored as `$null`). Return an `[ordered]` hashtable with the spec's exact key names and nesting: `schemaVersion, taskId, repository, baseBranch, baseSha, objective, scope { allowedPaths, forbiddenPaths }, acceptanceCriteria, verification { commands }, permissions { … }, execution { attempt, preferredProvider, previousSessionId }`.
2. `Test-WorkPacket -Packet <object>` returns `[pscustomobject]@{ valid; errors = @() }`. Errors, each an exact string: `schemaVersion must be 1`; `taskId is required`; `objective is required`; `scope.allowedPaths must be a non-empty array`; `permissions.<key> must be a boolean` (one per missing/non-bool key); `execution.attempt must be an integer >= 1`; `execution.preferredProvider is required`. Accept both hashtable and `PSCustomObject` input (read fields the way `_LaneObs_Field` in `backend/modules/execution/Execution.LaneObservation.ps1` does; copy that helper's shape into this module as `_WP_Field`).
3. `Get-WorkPacketPath -WorkspaceRoot -TaskId` → `<WorkspaceRoot>\output\work-packets\<TaskId>.workpacket.json`. `Save-WorkPacket -WorkspaceRoot -Packet` validates first (throws with the joined errors if invalid), creates the directory, writes `ConvertTo-Json -Depth 8`. `Read-WorkPacket -WorkspaceRoot -TaskId` returns `$null` when absent or unparseable.
4. Dot-source it in the host **immediately after** the line `. (Join-Path $executionModuleRoot 'Execution.LaneObservation.ps1')` (one match). Add its path to the module-presence array in the smoke.

**Gate (red first) — module smoke, new section `Write-Step 'WorkPacket contract — smoke: schema v1, offline'`:**

- Build a packet with the spec's example values; assert `Test-WorkPacket` valid; round-trip through `Save-WorkPacket`/`Read-WorkPacket` in a temp workspace under `output\smoke\module\workpacket\`; assert `execution.previousSessionId` serializes as JSON `null` and `scope.forbiddenPaths` as `[]` (string-match the raw JSON, not the parsed object). Predicted red on unchanged code: `The term 'New-WorkPacket' is not recognized as a name of a cmdlet, function, script file, or executable program.`
- Break each rule once (empty `taskId`, `permissions.network = 'no'`, `attempt = 0`) and assert the exact error string appears in `errors`.
- Assert the module file contains no `param(` at column 1 outside a function (the existing param-less gate will do this on the host's list; this is the same check run early).

**Roadmap write-back:** M1 `_(state: planned)_` → `_(state: scaffolded <date> — H38-01 WorkPacket schema v1 (Execution.WorkPacket.ps1), persisted under output/work-packets/)_`.

**Stop if:** the host's dot-source anchor line matches zero or more than one; or the module-presence list in the smoke is not a single `@( … )` array at the `Validating copied module files exist` step.

---

### H38-02 — Build the WorkPacket at dispatch

**Roadmap item:** M1. Spec: *Canonical task contract* ("The WorkPacket MUST be persisted outside files eligible for commit").

**Why:** the dispatch route enqueues a prompt string. The packet has to be built where the objective, acceptance criteria and verification are known — the dispatch route (`POST /api/roadmap/dispatch/execute`) and the packaging approval path (`Submit-PackagedItemToRunner`) — and the queue entry has to say where it is.

**Scope (edit only):** `backend/api-host/Start-RepoManagementApiHost.ps1` (the `'POST /api/roadmap/dispatch/execute'` case only); `backend/modules/automation/Automation.RoadmapQueue.ps1` (`New-RoadmapQueueEntry` only); `backend/modules/automation/Automation.RoadmapPackaging.ps1` (`Submit-PackagedItemToRunner` only); `backend/config/agent-providers.json` is **not** in scope (H38-07 creates it; this packet reads defaults from constants named below); `scripts/Invoke-ModuleSmokeTest.ps1`; `scripts/Invoke-ApiHostSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. In `New-RoadmapQueueEntry` add `[AllowEmptyString()][string]$WorkPacketPath = ''` and emit `workPacketPath` (`$null` when empty) as the **last** key. Every existing key and its order stay as they are (golden below).
2. In the dispatch route, after `$runId = New-PackagedItemDispatchRunId` and before `$queueEntry = New-RoadmapQueueEntry …` (one match each), build and save a packet: `-TaskId $runId`, `-Repository $githubRepo`, `-BaseBranch $baseBranch`, `-BaseSha ''`, `-Objective` = the `selectedTaskText` from `$planningContext` when non-empty, else the first line of `$prompt`; `-AcceptanceCriteria` = `@($planningContext.acceptanceCriteria)` if that property exists on `$planningContext` (discover with `Get-ObjectPropertyValue … -Default @()`), else `@()`; `-VerificationCommands` = `@()`; `-AllowedPaths @('**')`; `-ForbiddenPaths @('.github/workflows/**')`; `-Permissions @{ filesystemWrite = $true; shell = $true; network = $false; githubWrite = $false }`; `-PreferredProvider 'auto'`. **These scope and permission values are the spec's example, marked provisional under D-012; they are literals in this packet only — H38-07b replaces both sites with a config read.** Pass the saved path as `-WorkPacketPath`.
3. Add `workPacketPath` to the run-summary `[ordered]@{ … }` the route writes (the one whose keys start `runId, status, dispatchTarget`), after `selectedTask`.
4. In `Submit-PackagedItemToRunner`, do the same with the packet's own fields (`objective` = the packaged item's task text, `acceptanceCriteria` = the packet's `acceptanceCriteria` if present). Discover the exact property names by reading the function; if the packet object carries neither an acceptance list nor a task text, stop.
5. Failure to save the packet is **fatal to the dispatch** (throw before the queue line is written): a queue entry that points at no packet is the prose-only dispatch this milestone removes.

**Gate (red first):**

- Module smoke, extend the `Local Claude Code dispatch — smoke` section: `New-RoadmapQueueEntry` with no `-WorkPacketPath` serializes `workPacketPath` as JSON `null` and every pre-existing key is present **in the pre-change order** (capture the key list from the unchanged code first; assert equality). Predicted red on unchanged code: `workPacketPath` key absent.
- Api-host smoke, extend the dispatch/execute step: after the POST, read the queue line it wrote (the smoke already isolates the queue via `REPO_MGMT_QUEUE_PATH`) and assert `workPacketPath` points at an existing file whose `Test-WorkPacket` is valid and whose `taskId` equals the returned `runId`. Predicted red: the field is missing from the queue line.

**Roadmap write-back:** append `; H38-02 dispatch/execute and packet approval save a WorkPacket per run and carry workPacketPath` to M1's state clause.

**Stop if:** `$planningContext` in the route has no property that reads as acceptance criteria and no `selectedTaskText` (report the property names it has); or `Submit-PackagedItemToRunner` builds its queue entry through anything other than `New-RoadmapQueueEntry`.

---

### H38-03 — `ExecutionResult` contract; no structured result means failed

**Roadmap item:** M1 ("A run producing no structured `ExecutionResult` fails by name instead of reaching `awaiting-review`"). Spec: *Canonical execution result* ("Free-form prose MUST NOT be the orchestration protocol").

**Why:** `scripts/Invoke-RoadmapTaskRunner.ps1` launches the CLI and reads only `$LASTEXITCODE` (line ~608). An agent that printed prose and exited 0 reaches `awaiting-review` with nothing structured behind it.

**Scope (edit only):** `backend/modules/execution/Execution.WorkPacket.ps1` (add the result half); `scripts/Invoke-RoadmapTaskRunner.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `docs/reference/local-task-runner.md`; `ROADMAP.md`.

**Steps**

1. In `Execution.WorkPacket.ps1` add `New-ExecutionResult` with parameters `-TaskId`, `-ExecutionId`, `-Provider`, `-ProviderSessionId` (default `''` → `$null`), `-Status` (ValidateSet `implementation_complete`, `implementation_failed`, `capacity_exhausted`, `cancelled`), `-ChangedFiles` (string[], default `@()`), `-VerificationPassed` ([nullable bool], default `$null`), `-VerificationCommands` (string[], default `@()`), `-UsageNative` (object, default `$null`), `-TokensObserved` ([nullable int], default `$null`), `-Risks` (string[], default `@()`), `-OperatorAttentionRequired` (bool, default `$false`), `-Summary` (string, default `''`), `-Source` (ValidateSet `adapter`, `interactive`, default `adapter`). Return the spec's exact shape: `taskId, executionId, provider, providerSessionId, status, changedFiles, verification { passed, commands }, usage { native, tokensObserved }, risks, operatorAttentionRequired, summary` plus `source` and `schemaVersion = 1`.
2. `Test-ExecutionResult` mirrors `Test-WorkPacket`: errors `taskId is required`, `executionId is required`, `provider is required`, `status must be one of: implementation_complete, implementation_failed, capacity_exhausted, cancelled`, `changedFiles must be an array`.
3. `Get-ExecutionResultPath -WorkspaceRoot -TaskId` → `<WorkspaceRoot>\output\roadmap-task-history\runs\<TaskId>.result.json`; `Save-ExecutionResult`, `Read-ExecutionResult` as in H38-01.
4. Add a **pure** runner helper `Resolve-RunOutcomeFromResult -Result <object|null> -ExitCode <int>` (place it with the other pure helpers above `if ($LoadFunctionsOnly) { return }`) returning `[pscustomobject]@{ status; error }` with this table, in this order: result `$null` → `status = 'failed'`, `error = 'no-structured-result: the agent produced no ExecutionResult; prose is not the protocol'`; `Test-ExecutionResult` invalid → `failed`, `error = 'invalid-structured-result: <joined errors>'`; result status `capacity_exhausted` → `status = 'queued'`, `error = ''` (H38-10 completes this branch; here it only maps); result status `implementation_failed` → `failed` with the result's `summary` as error; result status `cancelled` → `failed`, `error = 'cancelled'`; otherwise (`implementation_complete`) → `status = 'awaiting-review'`, `error = ''`. `ExitCode` is recorded on the returned object as `exitCode` but decides nothing — the adapter's result does.
5. In `Invoke-QueuedTask`, after the `claude` launch block and the repo-root re-verification, and **before** the best-effort verify: when `-Headless`, read `Read-ExecutionResult -WorkspaceRoot $WorkspaceRoot -TaskId $runId` (H38-04 is what writes it; until then it is `$null`) and call `Resolve-RunOutcomeFromResult`. When the outcome is `failed`, write the summary with that status and error, `runnerCompletedAt`, and **return without committing**. When not headless, construct an interactive result (`-Source interactive`, `-Status implementation_complete`, `-Summary 'interactive session; result recorded by the runner'`) and save it, so every run leaves a result file.
6. Replace the final `status = 'awaiting-review'` literal in the summary write with `$outcome.status` and add `resultPath`, `resultSource`, `providerSessionId` (from the result) to that summary.
7. Update `local-task-runner.md` Flow block: after `claude`, add the line `result  (<runId>.result.json; missing or invalid => status=failed)`.

**Gate (red first) — module smoke, extend the runner section (`Invoke-RoadmapTaskRunner.ps1 -LoadFunctionsOnly` is already dot-sourced there):**

- `Resolve-RunOutcomeFromResult -Result $null -ExitCode 0` → `failed` with the exact `no-structured-result` error. Predicted red: `The term 'Resolve-RunOutcomeFromResult' is not recognized …`.
- A valid `implementation_complete` result → `awaiting-review`; an `implementation_failed` result → `failed` carrying its summary; `capacity_exhausted` → `queued`; an object missing `provider` → `failed` with `invalid-structured-result`.
- **Golden:** with `-ExitCode 1` and a valid complete result, status is still `awaiting-review` — exit code decides nothing. (Today's throw on non-zero exit stays where it is, *before* this call, so a crashed CLI still fails; this assertion pins that the result, not the code, is the protocol once a result exists.)

**Roadmap write-back:** append `; H38-03 ExecutionResult schema v1; headless run with no/invalid result is failed by name (Resolve-RunOutcomeFromResult)`.

**Stop if:** the runner's `awaiting-review` summary write matches more than one site; or the interactive launch (`& claude --permission-mode …`) cannot be distinguished from the headless one by the `$Headless` switch alone.

---

### H38-04 — Claude adapter: `stream-json` to ExecutionResult

**Roadmap item:** M1 ("the Claude path runs with structured output and records provider session id and usage"). Spec: *Claude Code adapter*.

**Why:** the runner records nothing from the CLI. The spec wants `session_id` recorded, usage normalized, and structured output used.

**Prerequisites:** H38-03. **No fixture prerequisite** — this packet authors its own (R12).

**Scope (edit only):** new `backend/modules/agent-adapters/Adapter.Claude.ps1`; new `tests/fixtures/providers/claude-stream-json-success.synthetic.jsonl`; `scripts/Invoke-RoadmapTaskRunner.ps1` (the headless launch line and the result save only); `scripts/Invoke-ModuleSmokeTest.ps1`; `backend/api-host/Start-RepoManagementApiHost.ps1` (dot-source line only, after `Execution.WorkPacket.ps1`); `ROADMAP.md`.

**Steps**

1. **Author the synthetic fixture** at `tests/fixtures/providers/claude-stream-json-success.synthetic.jsonl`, one JSON object per line, from the documented `stream-json` shape: a `{"type":"system","subtype":"init","session_id":"…"}` line, one or more `{"type":"assistant",…}` lines, and exactly one terminal `{"type":"result","subtype":"success","is_error":false,"session_id":"…","result":"…","usage":{"input_tokens":…,"output_tokens":…}}` line. Put a header comment in the smoke section naming this as an **assumed shape**, not an observed one.

   The assumption is contained rather than trusted: the parser in step 2 reads every field defensively, so a real transcript with a different shape produces a **named mismatch** rather than a wrong parse. When a real transcript is later copied in beside it (§C — it appears for free after any headless run), the gate asserts against both and any difference is a finding.
2. Create the adapter (R15; a param-less library). Functions, all pure:
   - `New-ClaudeExecutionArgument -Prompt -PermissionMode` → string[]: `@('-p', $Prompt, '--output-format', 'stream-json', '--verbose', '--permission-mode', $PermissionMode)`. Array, never a command string (the prompt is multi-line roadmap text).
   - `ConvertFrom-ClaudeStreamJson -Lines <string[]>` → `[pscustomobject]@{ result = <the type=result object or $null>; events = @(all parsed objects); parseErrors = @(line numbers that failed) }`. Unparseable lines are recorded, never thrown.
   - `ConvertTo-ClaudeExecutionResult -Parsed <object> -TaskId -ExecutionId -ChangedFiles <string[]>` → `New-ExecutionResult -Provider 'claude' -ProviderSessionId $parsed.result.session_id -UsageNative $parsed.result.usage -Status (…)` where status is `implementation_complete` when `result.is_error` is absent or `$false`, else `implementation_failed`; `-Summary` = the `result` text property if present (first 500 characters), and `-TokensObserved` = the sum of every integer-valued property directly under `usage` whose name ends in `_tokens`, or `$null` when there are none. When `Parsed.result` is `$null` return `$null` — that is H38-03's failed path.
3. Also define the seven A4 names for `claude` now so H38-15's conformance gate has nothing to add later: `Get-ClaudeAdapterCapability` (returns `@{ provider='claude'; executionMode='local'; supportsResume=$true; supportsStructuredOutput=$true }`), `Get-ClaudeAdapterCapacity` (returns `$null` — H38-12 fills it), `Start-ClaudeExecution` (**not** executable here — returns `New-ClaudeExecutionArgument`; the runner is the process that invokes), `Resume-ClaudeExecution -SessionId -Prompt -PermissionMode` (returns the same argv with `'--resume', $SessionId` inserted after `'-p', $Prompt`), `Stop-ClaudeExecution` (throws `Not supported in 3.8: a local process is stopped by the runner`), `ConvertTo-ClaudeCanonicalEvent` (returns `@()` — H38-33 fills it), `Get-ClaudeExecutionResult` = `ConvertTo-ClaudeExecutionResult`.
4. Runner: replace `& claude -p $prompt --permission-mode $PermissionMode` with: build argv via `New-ClaudeExecutionArgument`; run `& claude @argv 2>&1 | Tee-Object -Variable claudeLines | Out-Null`; keep the existing non-zero-exit throw; then `$parsed = ConvertFrom-ClaudeStreamJson -Lines @($claudeLines | ForEach-Object { [string]$_ })`; compute `$changed = @(& git -C $repo status --porcelain | ForEach-Object { $_.Substring(3) })`; `$result = ConvertTo-ClaudeExecutionResult …`; if `$result` is not `$null`, `Save-ExecutionResult`. Also write the raw lines to `<runsDir>\<runId>.claude.stream.jsonl` (provider-native payload retained for diagnosis, per spec). Dot-source the adapter in the runner next to the queue module dot-source (`$PSScriptRoot`-relative, as that line is).

**Gate (red first) — module smoke, new section `Write-Step 'Claude adapter — smoke: stream-json to ExecutionResult, offline'`:**

- Parse the synthetic fixture; assert `result` not null, `session_id` non-empty, `ConvertTo-ClaudeExecutionResult` yields `provider = 'claude'`, `providerSessionId` equal to the fixture's, `status = 'implementation_complete'`, `usage.native` not null. Predicted red: `The term 'ConvertFrom-ClaudeStreamJson' is not recognized …`.
- A fixture copy with the `result` line deleted → `result` is `$null`; `ConvertTo-ClaudeExecutionResult` returns `$null`.
- A fixture copy with one garbage line inserted → `parseErrors` names that line number; `result` still found.
- `is_error = $true` on the result line → `status = 'implementation_failed'`.
- **Shape tolerance, which is what makes a synthetic fixture safe to rely on:** a result line carrying **no** `session_id` and **no** `usage` still yields a valid ExecutionResult with `providerSessionId = $null`, `usage.native = $null` and `tokensObserved = $null`, and never throws. A `usage` object whose properties are all non-numeric yields `tokensObserved = $null`, not `0` — an unknown count and a count of zero are different claims.
- **Run against the real transcript too, when one exists:** if `tests/fixtures/providers/claude-stream-json-success.jsonl` is present, every assertion above runs against it as well. When it is absent the section says so and passes — its absence is never a failure.
- Argv: `New-ClaudeExecutionArgument -Prompt "a`nb" -PermissionMode acceptEdits` is an array of 7 elements whose second element contains the newline intact.

**Roadmap write-back:** append `; H38-04 Adapter.Claude.ps1 parses stream-json; session_id and usage recorded on <runId>.result.json`.

**Stop if:** the runner's headless launch line matches more than one site. **Not** a stop condition: a missing `session_id` or `usage` in any transcript — the parser is required to tolerate both.

---

### H38-05 — Render the packet into the provider prompt

**Roadmap item:** M1 ("which each adapter renders into its own prompt"). Spec: *Canonical task contract* ("The provider adapter MAY translate the WorkPacket into provider-specific prompting, but MUST NOT change its objective, scope, acceptance criteria, or permission envelope").

**Why:** today the prompt is built once by `_BuildDispatchPrompt` and stored on the queue entry; the packet is the source of truth from H38-02 on, and the prompt must be derivable from it without loss.

**Scope (edit only):** `backend/modules/execution/Execution.WorkPacket.ps1`; `backend/modules/agent-adapters/Adapter.Claude.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1` (prompt source only); `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. In `Execution.WorkPacket.ps1` add `ConvertTo-WorkPacketPrompt -Packet -Preamble <string> -Postamble <string>` returning a string with **exactly** these sections in order, each a `##` heading: `## Objective` (the objective), `## Scope` (bullet per allowed path under `Allowed:`, bullet per forbidden path under `Forbidden:`; omit `Forbidden:` when empty), `## Acceptance Criteria` (one bullet per criterion, **verbatim**, no reflow), `## Verification` (one bullet per command in backticks; the line `- (none declared)` when empty), `## Permissions` (four bullets `filesystemWrite: true` etc.). `Preamble` goes before the first heading, `Postamble` after the last section, both verbatim.
2. In `Adapter.Claude.ps1` add `ConvertTo-ClaudePrompt -Packet` = `ConvertTo-WorkPacketPrompt -Packet $Packet -Preamble "# Task $($Packet.taskId)" -Postamble ''`. **Enforcement of the permission envelope (`--allowedTools` / `--disallowedTools` mapping) is NOT in this packet** — it waits on D-012; record that sentence in the adapter's header comment.
3. Runner: in `Invoke-QueuedTask`, when the entry carries a non-empty `workPacketPath` and the file reads, set `$prompt` to `ConvertTo-ClaudePrompt -Packet $packet`; otherwise keep `$Entry.prompt` (pre-3.8 entries). Log which source was used.

**Gate (red first) — module smoke, extend the WorkPacket section:**

- Render the H38-01 example packet; assert every acceptance-criterion string from the packet appears in the output verbatim (`-like "*$c*"` per criterion), the five headings appear in order, and the forbidden path appears under `Forbidden:`. Predicted red: `The term 'ConvertTo-WorkPacketPrompt' is not recognized …`.
- Render a packet whose criterion contains a backtick and a `#` — still verbatim.
- **Golden:** a queue entry with `workPacketPath = $null` makes the runner use `entry.prompt` — assert by calling the runner's prompt-selection logic; if that logic is not extractable as a pure function, extract it as `Resolve-RunnerPrompt -Entry -Packet` first and test that.

**Roadmap write-back:** append `; H38-05 ConvertTo-WorkPacketPrompt renders the packet with criteria verbatim; enforcement waits on D-012`.

**Stop if:** the runner takes the prompt from anywhere other than `$Entry.prompt` (report the site); or D-012 has been answered in a way that requires a tool mapping — then this packet is done as written and the mapping is a new packet, report that.

---

### H38-06 — Milestone 1 closing

**Roadmap item:** M1, the `_(state: …)_` clause; the "same PR updates the milestone" guardrail in §8.

**Why:** the milestone's five capabilities have landed across five PRs; this packet proves them together and moves the state word.

**Scope (edit only):** `docs/reference/local-task-runner.md`; `docs/reference/status-vocabulary.md` (one sentence); `ROADMAP.md`.

**Steps**

1. Run `pwsh ./scripts/Invoke-ModuleSmokeTest.ps1` and confirm the four new sections from H38-01…05 pass in one run.
2. `local-task-runner.md`: add a subsection `## The work packet and the result (Release 3.8 M1)` of at most 15 lines naming the two files per run, the `no-structured-result` failure, and that pre-3.8 entries still run from `prompt`.
3. `status-vocabulary.md`: under *The five dimensions*, add one sentence after the table: `Release 3.8 adds a sixth dimension, Delivery state, in H38-34; until then the run summary's status field is the per-task state.`

**Gate:** no new gate. The gate is the combined green run in step 1 plus `pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` exiting 0.

**Roadmap write-back:** change M1's state word from `scaffolded` to `smoke-tested`, keep the packet clauses, and insert the date (`<date>`) followed by an em-dash directly after the word.

**Stop if:** any H38-01…05 section is red; that packet is reopened, not this one.

---

### H38-07 — Provider configuration file and loader

**Roadmap item:** Release 3.8 M2, `Persist capacity per provider, in the provider's own unit.` ("reserves and ranking weights live in `backend/config/`, not in code"). Spec: *Capacity reserves* ("These percentages are configuration, not hard-coded constants").

**Why:** there is no provider concept in config. `settings.json` has none of `agent|provider|dispatch` (verified 2026-09-06), and `BudgetLedger.ps1` reads a single work-unit quota from `settings.budgetLedger`.

**Scope (edit only):** new `backend/config/agent-providers.json`; new `backend/modules/execution/Execution.ProviderRegistry.ps1` (loader only in this packet; H38-14 adds the registry functions); `backend/api-host/Start-RepoManagementApiHost.ps1` (dot-source after `Execution.WorkPacket.ps1`); `scripts/Invoke-ModuleSmokeTest.ps1`; `docs/governance/open-decisions.md` (add D-011 … D-015 from §B verbatim, under **Open**); `ROADMAP.md`.

**Steps**

1. Write the config with `"schemaVersion": "v1"` and this shape (values are the spec's initial policy or §B defaults, every provisional one carrying `"provisional": true`):

   ```json
   {
     "schemaVersion": "v1",
     "providers": {
       "claude":  { "enabled": true,  "executionMode": "local",         "providerTool": "claude-code",          "autoPush": true, "maxConcurrentExecutions": 1,
                    "windows": [ { "name": "short-term", "unit": "provider-allowance" }, { "name": "weekly", "unit": "provider-allowance" } ],
                    "limitSignals": [ "(?i)usage limit", "(?i)rate limit", "(?i)429" ], "provisional": true },
       "codex":   { "enabled": false, "executionMode": "local",         "providerTool": "codex-cli",            "autoPush": true, "maxConcurrentExecutions": 1,
                    "windows": [ { "name": "short-term", "unit": "provider-allowance" }, { "name": "weekly", "unit": "provider-allowance" } ],
                    "limitSignals": [ "(?i)usage limit", "(?i)rate limit", "(?i)429" ], "provisional": true },
       "copilot": { "enabled": true,  "executionMode": "github-hosted", "providerTool": "github-copilot-agent", "autoPush": false, "maxConcurrentExecutions": 2,
                    "windows": [ { "name": "billing", "unit": "unknown" } ], "limitSignals": [], "provisional": true }
     },
     "reserves":  { "shortWindowRatio": 0.15, "weeklyRatio": 0.20, "remediationInsideWeekly": true, "provisional": true },
     "estimates": { "defaultTaskConsumptionRatio": 0.05, "provisional": true },
     "ranking":   { "weights": { "suitability": 1, "usableCapacity": 1, "history": 1, "fitsWindow": 1, "sessionReuse": 1, "timeToReset": 1, "estimatedConsumption": -1, "recentFailureRate": -1 }, "tieBreak": "nearest-reset-first" },
     "remediation": { "maxRemediationAttempts": 2 },
     "defaultScope": { "allowedPaths": [ "**" ], "forbiddenPaths": [ ".github/workflows/**" ], "provisional": true },
     "defaultPermissions": { "filesystemWrite": true, "shell": true, "network": false, "githubWrite": false, "provisional": true },
     "dispatch":  { "defaultTarget": "claude", "autoEnabled": false },
     "localExecutionSlots": 1
   }
   ```

2. Loader in the new module: `Get-AgentProviderConfigPath -WorkspaceRoot` → `<root>\backend\config\agent-providers.json`; `Get-AgentProviderConfig -ConfigPath` following `Get-FoundationDomainsConfig` in `backend/modules/portfolio/Portfolio.Conclusion.ps1` exactly: `$null` when absent, unparseable, `schemaVersion` not `v1`, or `providers` empty. `Test-AgentProviderConfig -Config` → `{ valid; errors }` with errors: `providers.<name>.executionMode must be local or github-hosted`, `providers.<name>.windows must be a non-empty array`, `providers.<name>.windows[<i>].unit must be one of: provider-allowance, tokens, ai-credits, premium-requests, currency, unknown` (the spec's list), `reserves.shortWindowRatio must be between 0 and 1`, `reserves.weeklyRatio must be between 0 and 1`, `localExecutionSlots must be 1` (spec: MVP concurrency; H38-36 may relax this only if the roadmap changes), `dispatch.defaultTarget must name a provider or auto`, `dispatch.defaultTarget is auto but dispatch.autoEnabled is false` (A18: the default may be `auto` only once routing is on), `ranking.tieBreak must be nearest-reset-first or alphabetical`.
3. `open-decisions.md` already carries all five (added 2026-09-07). **Do not add them again.** Verify only: D-011, D-012, D-014 and D-015 appear under **Open** and D-013 under **Decided**. If any is missing, add just that one in the register's entry format (`Asked`, `Question`, `Why it is not an agent's call`, `Default if unanswered`, `Blocks`) from §B, and say so in the report. `ranking` carries **no** `provisional` flag because D-013 is decided; every other provisional flag stays until its own decision lands.

**Gate (red first) — module smoke, new section `Write-Step 'Provider config — smoke: schema v1 and the reserve bounds'`:**

- Load the real file; `Test-AgentProviderConfig` valid; `localExecutionSlots` is 1. Predicted red: `The term 'Get-AgentProviderConfig' is not recognized …`.
- Mutations in a temp copy: `executionMode = 'cloud'`, a `unit = 'gallons'`, `shortWindowRatio = 1.5`, `localExecutionSlots = 2`, `dispatch.defaultTarget = 'auto'` with `autoEnabled = $false`, `ranking.tieBreak = 'coin-flip'` → each exact error string.
- Config tripwire: the file's `schemaVersion` is the string `v1` (the AGENTS.md rule); the committed file has `dispatch.autoEnabled = $false` and `dispatch.defaultTarget = 'claude'` (H38-17 is the only packet that changes them); `ranking.tieBreak` is `nearest-reset-first` and `ranking` has no `provisional` key (D-013, decided 2026-09-07).

**Roadmap write-back:** M2 `_(state: planned)_` → `_(state: scaffolded <date> — H38-07 agent-providers.json (schemaVersion v1) + Get-AgentProviderConfig; reserves are data marked provisional pending D-011; ranking weights and tieBreak are the decided D-013 values)_`.

**Stop if:** `open-decisions.md` already has a D-011 with a different question (numbering collision — report and renumber from the next free id).

---

### H38-07b — Dispatch reads scope and permissions from config

**Roadmap item:** M2 ("reserves and ranking weights live in `backend/config/`, not in code"). Spec: *Permission envelope*.

**Why:** H38-02 built the WorkPacket with literal scope and permission values at two sites. H38-07 created `defaultScope` and `defaultPermissions` in config. Nothing yet reads them, so a D-012 decision edited into the config would change nothing.

**Prerequisites:** H38-02, H38-07.

**Scope (edit only):** `backend/api-host/Start-RepoManagementApiHost.ps1` (the `'POST /api/roadmap/dispatch/execute'` case only); `backend/modules/automation/Automation.RoadmapPackaging.ps1` (`Submit-PackagedItemToRunner` only); `scripts/Invoke-ApiHostSmokeTest.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. In the dispatch route, before the `Save-WorkPacket` call H38-02 added: `$providerConfig = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot $WorkspaceRoot)` (`$WorkspaceRoot` is the host's script parameter; the eight existing `Get-FoundationDomainsConfig -ConfigPath (Join-Path $WorkspaceRoot …)` calls are the model). When `$providerConfig` is `$null`, throw `agent-providers.json is missing or invalid; dispatch refused` before any queue line is written (the same fatal rule as H38-02 step 5).
2. Replace the four literal arguments with reads: `-AllowedPaths @($providerConfig.defaultScope.allowedPaths)`, `-ForbiddenPaths @($providerConfig.defaultScope.forbiddenPaths)`, `-Permissions @{ filesystemWrite = [bool]$providerConfig.defaultPermissions.filesystemWrite; shell = [bool]$providerConfig.defaultPermissions.shell; network = [bool]$providerConfig.defaultPermissions.network; githubWrite = [bool]$providerConfig.defaultPermissions.githubWrite }`. The `provisional` key on either object is not copied into the packet.
3. `Submit-PackagedItemToRunner`: the same replacement. It is a module function with no `$WorkspaceRoot`; add `[AllowEmptyString()][string]$ProviderConfigPath = ''` and, when empty, derive it from the function's existing workspace/repo-root parameter (discover which parameter it has — expected exactly one path parameter that names the repository-management root). Absent config throws the same message.
4. After both edits, the host source and the packaging module contain the literal `.github/workflows/**` **zero** times (grep; the only remaining occurrence in the repository is `agent-providers.json` and this file).

**Gate (red first):**

- Module smoke, extend the `Provider config — smoke` section: grep the host source and `Automation.RoadmapPackaging.ps1` for the literal `.github/workflows/**` → zero matches. Predicted red on unchanged code: 2 matches (one per H38-02 site).
- Api-host smoke, dispatch/execute step: the saved packet's `scope.forbiddenPaths` equals the committed config's `defaultScope.forbiddenPaths` and its `permissions.network` equals the config's `defaultPermissions.network` (read the config file in the smoke; compare values, not literals). Golden: `Test-WorkPacket` on the saved packet is still valid.
- Module smoke, the missing-config path: `Submit-PackagedItemToRunner -ProviderConfigPath <a path under the smoke's temp dir that does not exist>` throws a message beginning `agent-providers.json is missing or invalid`, and no queue line was written. Do **not** add an environment override for the config path — the host boots once in the api-host smoke and the negative belongs to the module function.

**Roadmap write-back:** append `; H38-07b dispatch and packaging read defaultScope/defaultPermissions from agent-providers.json — no scope literal remains in code`.

**Stop if:** `Submit-PackagedItemToRunner` has no parameter that names a workspace or repository-management root (report its parameter list); or the literal appears in a third file after the edit (report it).

---

### H38-08 — Capacity record contract

**Roadmap item:** M2 ("Named windows with `remainingRatio`, `resetAt` and a confidence rank"). Spec: *Provider capacity model*, *Capacity sources*.

**Why:** the spec's normalized capacity object does not exist. The only budget object (`Test-AgentDispatchQuota` in `BudgetLedger.ps1`) is a work-unit figure per repository per month.

**Scope (edit only):** new `backend/modules/execution/Execution.ProviderCapacity.ps1`; host dot-source line (after `Execution.ProviderRegistry.ps1`); `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Define `$script:CapacitySourceRank` as an ordered list matching the spec, **highest confidence first**: `provider-status`, `provider-cli`, `provider-warning`, `accumulated-usage`, `rate-limit-response`, `historical-estimate`. `Get-CapacitySourceRank -Source` → 1-based index, or throws `Unknown capacity source '<x>'. Allowed: …`.
2. `New-ProviderCapacityRecord -Provider -Windows <object[]> -Available <bool> -ObservedAt <string> -CooldownUntil <string> (default '' → $null)` → the spec's shape `provider, available, observedAt, activeExecutions (always 0 here; derived on read by H38-11), windows[], cooldownUntil`. Each window is normalized to `name, unit, remainingRatio (nullable double 0..1), resetAt (nullable ISO), source, confidence` where `confidence` is `high` for ranks 1–2, `medium` for 3–4, `low` for 5–6, `none` when `remainingRatio` is null.
3. `Test-ProviderCapacityRecord` errors: `provider is required`, `windows must be a non-empty array`, `windows[<i>].unit must be one of: …` (same list as H38-07), `windows[<i>].remainingRatio must be null or between 0 and 1`, `windows[<i>].source must be one of: …`. **Never** invent a ratio: a window with no ratio is valid and reports `confidence = 'none'`.
4. `Get-ProviderCapacityRecordPath -WorkspaceRoot -Provider` → `<root>\output\provider-capacity\<provider>.json`; `Save-ProviderCapacityRecord` (validate, mkdir, write); `Read-ProviderCapacityRecord` (`$null` when absent/unparseable); `Merge-ProviderCapacityWindow -Record -Window` replaces the window with the same `name` **only if** the incoming source rank is equal or better (numerically lower) than the stored one, else leaves it and returns `{ merged = $false; reason = 'lower-confidence source' }`.

**Gate (red first) — module smoke, new section `Write-Step 'Provider capacity — smoke: native units, confidence rank, persistence'`:**

- Build the spec's example record (`codex`, two windows, `provider-status`, `0.61`/`0.43`) → valid; `confidence = 'high'` on both. Predicted red: `The term 'New-ProviderCapacityRecord' is not recognized …`.
- Window with `remainingRatio = $null` and `unit = 'unknown'` → valid, `confidence = 'none'`; raw JSON shows `"remainingRatio": null`.
- `Merge-ProviderCapacityWindow` with a `historical-estimate` onto a `provider-status` window → not merged, reason named; the reverse → merged.
- Round-trip through the temp workspace; `windows` serializes as an array of two, never `null`.

**Roadmap write-back:** append `; H38-08 Execution.ProviderCapacity.ps1 — one record per provider under output/provider-capacity/, native units, confidence from the spec's source ladder`.

**Stop if:** nothing — this packet is pure and additive.

---

### H38-09 — Reserve arithmetic and the capacity verdict

**Roadmap item:** M2 ("reserves … live in config"); acceptance criterion `A provider at a hard limit is not dispatched`. Spec: *Capacity reserves* ("Normal implementation work cannot consume the reserve. Remediation … MAY consume the reserve. An operator MAY explicitly override a reserve").

**Prerequisites:** H38-08; **D-011 decided** (see Stop if).

**Scope (edit only):** `backend/modules/execution/Execution.ProviderCapacity.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `Resolve-ProviderCapacityVerdict -Record -Config -TaskClass <normal|remediation> -EstimatedConsumptionRatio <double, default from config estimates.defaultTaskConsumptionRatio> -OperatorOverride <bool, default $false> -NowUtc` → `[pscustomobject]@{ provider; eligible; reason; window; usableRatio; reserveRatio; cooldownUntil; enforced }`. Decision table, first match wins:
   1. `record` null → `eligible = $false`, `reason = 'no-capacity-record'`.
   2. `record.available` false → `$false`, `'provider-unavailable'`.
   3. `cooldownUntil` in the future → `$false`, `'cooling-down until <iso>'`.
   4. For each window with a non-null ratio: `reserve` = `reserves.shortWindowRatio` when `name = 'short-term'`, `reserves.weeklyRatio` when `name = 'weekly'`, else `0`; `usable = remainingRatio - reserve`, floored at 0; when `TaskClass = remediation` and `remediationInsideWeekly` is true, `usable = remainingRatio` for the weekly window; when `OperatorOverride`, `usable = remainingRatio` for every window and `reason` gains a trailing space plus `(operator override)`. If `usable < EstimatedConsumptionRatio` → `$false`, `'insufficient <name> capacity: usable <u> < estimate <e>'`, `window = name`.
   5. No window has a ratio → `eligible = $true`, `reason = 'capacity unmeasured'` (unknown is not exhausted; the spec's `unknown` unit exists for this).
   6. Otherwise `$true`, `reason = 'fits'`, `window` = the tightest window.
2. `enforced` = `-not $Config.reserves.provisional`. **While D-011 is unanswered the verdict is computed and recorded but the runner must not refuse on it** — H38-11 reads `enforced`.

**Gate (red first) — module smoke, extend the capacity section:**

- Spec example record, config reserves 0.15/0.20, estimate 0.05, normal task → eligible, `window = 'weekly'` (0.43 − 0.20 = 0.23 is the tighter usable). Predicted red: `The term 'Resolve-ProviderCapacityVerdict' is not recognized …`.
- Weekly ratio 0.22, normal → ineligible, reason names `weekly`, `usable 0.02 < estimate 0.05`; same record, remediation → eligible.
- Cooldown in the future → ineligible, reason begins `cooling-down until`; cooldown in the past → ignored.
- Record with only `unit = unknown` windows → eligible, `capacity unmeasured`.
- Operator override on the 0.22 record → eligible, reason ends `(operator override)`.

**Roadmap write-back:** append `; H38-09 Resolve-ProviderCapacityVerdict applies the configured reserves (remediation may use the weekly reserve; operator override recorded)`.

**Stop if:** D-011 is not under **Decided** in `open-decisions.md` — do the work through step 2 with `enforced = $false` and report; do **not** flip `provisional` yourself.

---

### H38-10 — A provider limit re-queues the task

**Roadmap item:** M2 ("A limit re-queues the task with workspace, branch, attempt and session intact"); §8 guardrail *A provider limit is state, not an execution failure*. Spec: *Capacity sources* ("A provider limit response is state, not an execution failure … MUST preserve the task, workspace, branch, attempt, session identifier, and provider context").

**Prerequisites:** H38-04, H38-08; the synthetic fixture this packet creates; optionally the real transcript from §C.

**Scope (edit only):** `backend/modules/agent-adapters/Adapter.Claude.ps1`; `backend/modules/execution/Execution.ProviderCapacity.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1`; new `tests/fixtures/providers/claude-stream-json-usage-limit.synthetic.jsonl`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Create the synthetic fixture: copy `claude-stream-json-success.jsonl`, and on its `result` line set `is_error` to `true` and the `result` text to `Usage limit reached. Your limit resets at 2026-09-10T14:00:00Z.` (this exact text). Name it `.synthetic.jsonl`; when the real `claude-stream-json-usage-limit.jsonl` exists the gate runs against both.
2. `Test-ProviderLimitSignal -Provider -Text -Config` (in `Execution.ProviderCapacity.ps1`) → `{ matched; pattern; resetAt }` where `resetAt` is the first ISO-8601 timestamp found in `Text` by `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?Z`, else `$null`. Patterns come from `providers.<provider>.limitSignals`.
3. `ConvertTo-ClaudeExecutionResult`: when the result line is an error and `Test-ProviderLimitSignal` matches its text → `-Status capacity_exhausted`, `-Summary` = the matched text, `-Risks @('provider-limit')`.
4. Runner, in the `capacity_exhausted` outcome (H38-03 mapped it to `queued`): write the summary with `status = 'queued'`, plus `capacityWait = @{ provider; detectedAt; resetAt; pattern }`, **and leave `branch`, `attempt` (add `attempt` to the summary now, default 1) and `providerSessionId` untouched**; do **not** commit or reset the branch; call `Set-ProviderCooldown -WorkspaceRoot -Provider -Until <resetAt> -Source 'rate-limit-response'` (new, in the capacity module: reads the record or creates a minimal one, sets `cooldownUntil` and `cooldownSource`, saves). When `resetAt` is `$null`, pass `-Until (NowUtc + 60 minutes) -ResetAssumed` and the record carries `resetAssumed = $true` (**A17** — the number is a §A decision, not this step's). Emit `Write-AgentRunEvent -EventType 'execution.capacity.exhausted'` when the agent-run ledger module is loaded in the runner (it is not today — discover with `Get-Command Write-AgentRunEvent`; if absent, skip and note; H38-33 wires events).
5. The queue line is append-only and the claimable filter reads `status = 'queued'` from the summary, so **re-queueing is the summary write alone** — assert that in the gate rather than adding a second queue line.

**Gate (red first) — module smoke, extend the Claude adapter section:**

- Synthetic fixture → result `status = 'capacity_exhausted'`, `risks` contains `provider-limit`; `Test-ProviderLimitSignal` returns `resetAt = '2026-09-10T14:00:00Z'`. Predicted red on unchanged code: status is `implementation_failed`.
- Runner pure path: seed a summary `{ status='running'; branch='roadmap/x'; attempt=2; providerSessionId='s1' }`, call the runner's outcome writer with the exhausted result (extract it as `Write-RunnerOutcomeSummary -SummaryPath -Outcome -Result` if it is not already a function) → status `queued`, branch/attempt/session unchanged, `capacityWait.resetAt` set; the provider's capacity record now has `cooldownUntil = 2026-09-10T14:00:00Z` and `resetAssumed = $false`.
- Same call with a result whose text has no timestamp (`Usage limit reached.`) and `-NowUtc 2026-09-10T12:00:00Z` → `cooldownUntil = 2026-09-10T13:00:00Z`, `resetAssumed = $true`, `cooldownSource = 'rate-limit-response'` (A17).
- **Golden:** an `implementation_failed` result still writes `failed` (H38-03's assertion re-run here).
- If the real transcript exists: the same assertions against it, except `resetAt` may be `$null`.

**Roadmap write-back:** append `; H38-10 a matched limit signal writes status=queued with capacityWait and sets the provider's cooldownUntil — branch, attempt and session survive`.

**Stop if:** the runner has no single place that writes the terminal summary (report the sites); or `Get-Command Write-AgentRunEvent` succeeds in the runner today (then wire the event now and say so).

---

### H38-11 — The runner refuses to claim during cooldown; one local slot

**Roadmap item:** M2 ("the runner refuses to claim while a provider cools down, the same shape as today's env-token refusal"); Out of scope: *Concurrency above one local execution slot*. Spec: *MVP concurrency*.

**Prerequisites:** H38-10; **H-05** (heartbeat path override — the api-host smoke asserts the heartbeat, and this packet adds fields to it).

**Scope (edit only):** `scripts/Invoke-RoadmapTaskRunner.ps1`; `backend/modules/execution/Execution.ProviderCapacity.ps1` (`Get-ProviderActiveExecutionCount` and `Repair-OrphanedRunSummary` only); `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. At both sites where the runner writes `status = 'running'` (today lines 489 and 593, `Update-TaskSummary … status = 'running'; …` — expected exactly 2 matches), add `runnerPid = $PID` to the same `-Set` hashtable.
2. `Get-ProviderActiveExecutionCount -RunsDir -Provider -HeartbeatPath -NowUtc -StaleAfterMinutes 10` → count of `*.summary.json` whose `status` is `running`, whose provider (`selectedProvider`, else `dispatchTarget`, else `claude`) equals `Provider`, **and which is live** (A19): the file at `HeartbeatPath` exists, parses, its `lastHeartbeatAt` is within `StaleAfterMinutes` of `NowUtc`, and its `pid` equals the summary's `runnerPid`. A summary with no `runnerPid` (written before this packet) is never live. Derived, never stored (A6). The runner passes `Get-RunnerHeartbeatPath -WorkspaceRoot`; the host (H38-12) passes `Get-RunnerHeartbeatFilePath -WorkspaceRoot` from `Automation.RunnerPresence.ps1` — same file, two existing helpers.
3. `Repair-OrphanedRunSummary -RunsDir -CurrentPid -NowUtc -Config` → for every summary with `status = 'running'`, a local provider (`Config.providers.<p>.executionMode = 'local'`), and `runnerPid` absent or not equal to `CurrentPid`: patch `status = 'failed'`, `failureCategory = 'orphaned'`, `error = "runner pid <runnerPid|none> is not this runner (<CurrentPid>); run abandoned at <NowUtc iso>"`, `orphanedAt = <iso>`; leave `branch`, `attempt`, `providerSessionId`, `workPacketPath` untouched. Return the list of run ids repaired. The runner calls it **once at startup**, directly after the heartbeat path is resolved (line ~698) and before the first poll, and prints each repaired id. It does not run per poll (a live run's own pid equals `CurrentPid`).
4. Runner pure helper `Test-RunnerClaimAllowed -Entry -CapacityRecord -Config -ActiveLocalCount -NowUtc` → `{ allowed; reason; code }`. Resolve the entry's token first (`Get-QueueEntryDispatchTarget`); then, first match wins:
   - token `auto` → `$true`, `code = 'deferred-to-router'`, `reason = 'auto: cooldown, reserve and concurrency are checked per candidate by Resolve-ProviderSelection'`. No per-provider check runs here — there is no provider yet (H38-17 owns the decision). Until H38-17 lands, the poll loop treats an `auto` entry as not claimable: `Get-Command Resolve-ProviderSelection` absent → log `routing not enabled` and continue; the entry stays `queued`. This cannot happen by default (A18: nothing writes `auto` while `dispatch.autoEnabled` is false).
   - `cooldownUntil` in the future for the entry's provider → `$false`, `code = 'provider-cooling-down'`, reason names the provider and the time.
   - provider `executionMode = local` and `ActiveLocalCount >= Config.localExecutionSlots` → `$false`, `code = 'local-slot-occupied'`.
   - `Resolve-ProviderCapacityVerdict` ineligible **and** `enforced` → `$false`, `code = 'capacity-reserve'`; ineligible and not enforced → `$true` with `reason = 'capacity verdict advisory: …'`.
   - else `$true`.
5. In the poll loop, before `Invoke-QueuedTask -Entry $entry`: evaluate; when not allowed, **do not claim** (no summary write, the entry stays `queued`), `Write-Host` the reason, and continue. Put `providerCooldowns = @{ claude = <iso|null>; codex = …; copilot = … }` and `localSlotsInUse = <int>` on the heartbeat (`New-RunnerHeartbeat` gains two optional parameters).
6. Precedence with the existing copilot precondition (`Test-CopilotDispatchPrecondition`): this check runs **first**; the copilot precondition stays where it is and still writes `blocked` (unchanged behaviour).

**Gate (red first) — module smoke, extend the runner section:**

- Cooldown one hour ahead → not allowed, code `provider-cooling-down`. Predicted red: `The term 'Test-RunnerClaimAllowed' is not recognized …`.
- Active local count 1, slots 1, provider local → `local-slot-occupied`; provider `copilot` (github-hosted) with the same count → allowed.
- Entry with token `auto` and `claude` cooling down → allowed, code `deferred-to-router`.
- Ineligible verdict with `enforced = $false` → allowed, reason begins `capacity verdict advisory`; with `$true` → `capacity-reserve`.
- Liveness (A19), in a temp runs dir with a temp heartbeat file: a `running` summary with `runnerPid = 4242` and a heartbeat `{ pid = 4242; lastHeartbeatAt = NowUtc − 1 min }` → count 1; heartbeat `lastHeartbeatAt = NowUtc − 11 min` → 0; heartbeat `pid = 4243` → 0; no heartbeat file → 0; summary with no `runnerPid` → 0.
- `Repair-OrphanedRunSummary` over that dir with `-CurrentPid 4243` → the 4242 summary reads `failed` / `orphaned`, `branch` and `providerSessionId` unchanged, and the function returned its run id; a summary with `runnerPid = 4243` is untouched; a `copilot` summary with a foreign pid is untouched (github-hosted).
- Heartbeat from `New-RunnerHeartbeat` with the new parameters serializes `providerCooldowns` as an object with three keys and `localSlotsInUse` as a number; **golden:** without them the heartbeat is byte-identical in its pre-existing keys to today's output.

**Roadmap write-back:** append `; H38-11 Test-RunnerClaimAllowed — no claim during cooldown or with the one local slot busy, auto defers to the router; a running summary counts only while the heartbeat pid is alive, and startup marks orphans failed/orphaned with branch and session kept`.

**Stop if:** the poll loop claims through any path other than `Invoke-QueuedTask` (report it); or the runner writes `status = 'running'` at more or fewer than two sites (report them).

---

### H38-12 — Capacity observed from usage and provider status; `GET /api/providers`

**Roadmap item:** M2 (windows with `remainingRatio`, `resetAt`, confidence). Spec: *Capacity sources* ("Usage accumulated from completed executions" is rank 4; "Provider-reported warning or remaining percentage" rank 3).

**Scope (edit only):** `backend/modules/execution/Execution.ProviderCapacity.ps1`; `backend/modules/agent-adapters/Adapter.Claude.ps1` (`Get-ClaudeAdapterCapacity`); `scripts/Invoke-RoadmapTaskRunner.ps1` (post-run hook only); `backend/api-host/Start-RepoManagementApiHost.ps1` (one new GET route); `scripts/Invoke-ApiHostSmokeTest.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `Add-ProviderUsageObservation -WorkspaceRoot -Provider -Result <ExecutionResult> -NowUtc`: append `{ at; taskId; tokensObserved; native }` to `record.usageObservations` (new array, capped at the newest 200), set `observedAt`, and **do not touch any window's `remainingRatio`** — accumulated usage is evidence, not a ratio the provider never gave (spec: token telemetry and subscription capacity are separate measurements).
2. `Get-ClaudeAdapterCapacity -Parsed <stream-json parse>` → if any parsed event carries a property whose name matches `(?i)remaining|limit|quota` with a numeric 0..1 or 0..100 value, return a window `{ name='short-term'; unit='provider-allowance'; remainingRatio=<normalized>; source='provider-warning' }`; else `$null`. This is deliberately conservative; the fixture decides what exists.
3. Runner post-run hook: after saving the result, `Add-ProviderUsageObservation`; if the adapter returned a capacity window, `Merge-ProviderCapacityWindow` it (rank rules apply).
4. Route `GET /api/providers` → `success = $true` and `data` with two keys: `providers`, an array with one element per configured provider carrying the config entry minus `limitSignals`, the capacity record (or `$null`), and the verdict from `Resolve-ProviderCapacityVerdict -TaskClass normal`; and `config`, carrying `reserves`, `estimates` and their provisional flags. Empty arrays as `[]`. Add to `$censusRoutes` (R16).

**Gate (red first):**

- Module smoke: two observations append; the 201st evicts the oldest; the window ratio is unchanged by observations. Predicted red: `The term 'Add-ProviderUsageObservation' is not recognized …`.
- Api-host smoke: `GET /api/providers` is JSON, `data.providers` has three entries with `provider` names `claude`, `codex`, `copilot`, each carrying `verdict.reason`; with no records on disk every verdict reason is `no-capacity-record`. Predicted red: the route answers `200 text/html` (SPA fallback — assert content-type, never status).

**Roadmap write-back:** append `; H38-12 usage observations accumulate without inventing a ratio; GET /api/providers reports record + verdict per provider`.

**Stop if:** the fixture contains no property matching step 2's regex **and** the operator has confirmed the CLI reports none — then implement step 2 as always-`$null` and record that the source rank 3 is unavailable for Claude.

---

### H38-13 — Milestone 2 closing

**Roadmap item:** M2 state clause.

**Scope (edit only):** `docs/reference/local-task-runner.md`; `docs/product/delivery-loop.md` (one sentence under the 3.8 addendum); `ROADMAP.md`.

**Steps**

1. Combined green run of the module smoke and api-host smoke (on port 7171, per the companion's R7).
2. `local-task-runner.md`: subsection `## Capacity and cooldown (Release 3.8 M2)`, at most 15 lines: where records live, what `queued` + `capacityWait` means, that the runner skips claims during cooldown and says so in the heartbeat.
3. `delivery-loop.md` addendum: append one sentence to the *A provider limit becomes state* paragraph naming `output/provider-capacity/`.

**Roadmap write-back:** M2 state word → `smoke-tested <date>`, packet clauses retained.

**Stop if:** any M2 packet's section is red.

---

### H38-14 — The provider registry replaces the hardcoded pair

**Roadmap item:** Release 3.8 M3, `Route between providers, and add the Codex adapter.` ("One registry replaces the `claude`/`copilot` pair hardcoded in `Automation.RoadmapQueue.ps1`, `Invoke-RoadmapTaskRunner.ps1` and `frontend/types.ts`"). Spec: *Provider adapters* ("All providers implement IAgentExecutor").

**Why:** `Get-RoadmapDispatchTargets` returns `@('claude', 'copilot')`; `Get-QueueEntryDispatchTarget` in the runner repeats the same list and message; two `ValidateSet('claude', 'copilot')` attributes exist in `scripts/Add-RoadmapTaskToQueue.ps1` and `scripts/Start-RoadmapCopilotTask.ps1`.

**Scope (edit only):** `backend/modules/execution/Execution.ProviderRegistry.ps1`; `backend/modules/automation/Automation.RoadmapQueue.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1`; `scripts/Add-RoadmapTaskToQueue.ps1`; `scripts/Start-RoadmapCopilotTask.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Registry functions: `Get-AgentProviderRegistry -WorkspaceRoot` → `[ordered]` of provider name → config entry, **including disabled providers** (disabled is a routing fact, not an unknown name); `Get-AgentProviderToken` → `@(names) + 'auto'`; `Test-AgentProviderToken -Token` → bool; `Resolve-AgentProviderToken -Token` → absent/blank → `'claude'`; known (case-insensitive) → lowercase; else throw `Unknown dispatchTarget '<x>'. Allowed: <list>.` (**keep this message shape** — the module smoke asserts on it).
2. `Automation.RoadmapQueue.ps1`: `Get-RoadmapDispatchTargets` returns `Get-AgentProviderToken` when the registry module is loaded (`Get-Command Get-AgentProviderToken`), else the literal `@('claude', 'copilot')` (the queue module is dot-sourced by the runner before anything else and must not gain a hard dependency). `Resolve-RoadmapDispatchTarget` delegates the same way. Record in a comment that the fallback exists for the runner's `-LoadFunctionsOnly` path.
3. Runner: `Get-QueueEntryDispatchTarget` becomes a one-line call to `Resolve-RoadmapDispatchTarget` on the entry's field (keep the function; callers and the smoke reference it). Dot-source the registry module in the runner next to the queue module.
4. The two `ValidateSet` attributes: replace with `[ValidateScript({ Test-AgentProviderToken -Token $_ })]` **only if** the module is loaded before parameter binding — it is not (a `param()` block binds before the body runs). So instead: keep `ValidateSet('claude', 'copilot', 'codex', 'auto')` and add a module-smoke assertion that the two attribute lists equal `Get-AgentProviderToken` (one list checked against the other; drift fails).

**Gate (red first) — module smoke, extend the `Operator-context dispatch` section:**

- `Resolve-RoadmapDispatchTarget 'CODEX'` → `codex`; `'auto'` → `auto`; `''` → `claude`; `'gpt'` → throws with a message matching `^Unknown dispatchTarget 'gpt'\. Allowed: claude, codex, copilot, auto\.$`. Predicted red: `'CODEX'` throws `Unknown dispatchTarget`.
- The two scripts' `ValidateSet` members (read via `[System.Management.Automation.Language.Parser]::ParseFile` and walking `ValidateSet` attribute arguments — or a regex over the source, whichever exists in the smoke already for a similar check) equal `Get-AgentProviderToken` as sets.
- **Golden:** `New-RoadmapQueueEntry` with no target still writes `dispatchTarget = 'claude'`; a pre-3.0 entry object with no field resolves to `claude` through the runner's function.

**Roadmap write-back:** M3 `_(state: planned)_` → `_(state: scaffolded <date> — H38-14 Execution.ProviderRegistry.ps1 is the one token list (claude, codex, copilot, auto); queue module and runner delegate; ValidateSet lists are gated against it)_`.

**Stop if:** any file other than the three named still contains the literal array `@('claude', 'copilot')` after step 2 (grep; report the file).

---

### H38-15 — Adapter conformance gate; Copilot adapter wraps existing functions

**Roadmap item:** M3. Spec: *Provider adapters*, *GitHub Copilot adapter*.

**Prerequisites:** H38-14, H38-04.

**Scope (edit only):** `backend/modules/execution/Execution.ProviderRegistry.ps1`; new `backend/modules/agent-adapters/Adapter.Copilot.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1` (move-only); host dot-source lines; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Registry: `Test-AgentProviderAdapter -Provider` → `{ conforms; missing = @() }` checking the seven A4 names with `Get-Command -Name … -ErrorAction SilentlyContinue`. `Get-AgentProviderAdapterPath -WorkspaceRoot -Provider` → `<root>\backend\modules\agent-adapters\Adapter.<Capitalized>.ps1`.
2. Create `Adapter.Copilot.ps1` by **moving verbatim** from the runner: `New-CopilotAgentTaskArgs`, `Get-AgentTaskUrlFromOutput`, `Test-CopilotDispatchPrecondition` (same bodies, same signatures — a move is the change; the runner dot-sources the adapter so every existing call keeps working). Add the seven names: `Get-CopilotAdapterCapability` (`executionMode = 'github-hosted'`, `supportsResume = $false`), `Get-CopilotAdapterCapacity` → one window `{ name='billing'; unit='unknown'; remainingRatio=$null; source='historical-estimate' }` with a header comment citing D-014, `Start-CopilotExecution` = `New-CopilotAgentTaskArgs`, `Resume-CopilotExecution` throws `Not supported: Copilot runs are GitHub-hosted; remediation is a new task`, `Stop-CopilotExecution` throws `Not supported in 3.8`, `ConvertTo-CopilotCanonicalEvent` → `@()`, `Get-CopilotExecutionResult -TaskUrl -TaskId -ExecutionId` → `New-ExecutionResult -Provider 'copilot' -Status implementation_complete -Summary "dispatched: $TaskUrl" -ProviderSessionId $TaskUrl` (the URL is the only durable handle today; H38-22 reconciles PR state).
3. Runner: `Invoke-QueuedCopilotTask` saves an ExecutionResult via `Get-CopilotExecutionResult` after recording `agentTaskUrl`.
4. Host: dot-source the three adapters after the capacity module (the host needs capability and capacity, never execution).

**Gate (red first) — module smoke, new section `Write-Step 'Provider adapters — smoke: every enabled provider conforms to the seven-function contract'`:**

- For each provider in the registry: `Test-AgentProviderAdapter` conforms, or the provider is `codex` and `enabled = $false` (until H38-16). Predicted red: `Test-AgentProviderAdapter` not recognized; after defining it, `copilot` is missing all seven.
- **Golden (move-only):** the three moved functions produce identical output to a captured pre-move run: `New-CopilotAgentTaskArgs -Repository 'x/y' -Prompt "a`nb" -BaseBranch main` → the same 7-element array; `Get-AgentTaskUrlFromOutput` on the same sample string; `Test-CopilotDispatchPrecondition -GhAvailable $false` → `gh-not-found`.
- Injection: temporarily rename `Stop-CopilotExecution` → gate names it as missing. Revert.

**Roadmap write-back:** append `; H38-15 seven-function adapter contract gated per provider; Adapter.Copilot.ps1 holds the moved runner functions unchanged`.

**Stop if:** any of the three functions is referenced from a file other than the runner and the module smoke (grep; report — the move needs that file in scope).

---

### H38-16 — Codex adapter

**Roadmap item:** M3 ("add the Codex adapter"). Spec: *Codex adapter* (`codex exec --json --sandbox workspace-write --output-schema <ExecutionResult schema>`; "records the Codex thread/session identifier"; "MUST NOT equate Codex token telemetry with remaining subscription allowance").

**Prerequisites:** H38-15; **D-015 decided yes**. No fixture prerequisite: this packet authors `tests/fixtures/providers/codex-exec-success.synthetic.jsonl` from the documented `codex exec --json` shape, parses it defensively, and asserts additionally against a real transcript only if one has appeared (R12).

**Scope (edit only):** new `backend/modules/agent-adapters/Adapter.Codex.ps1`; new `backend/config/execution-result.schema.json` (the JSON Schema of H38-03's shape, for `--output-schema`); `scripts/Invoke-RoadmapTaskRunner.ps1` (a `codex` branch beside the claude launch); `backend/config/agent-providers.json` (`codex.enabled` → `true` **only** in this packet); `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. **Discovery, exact-match, on the fixture.** Find the line(s) that carry a thread/session identifier: search every parsed object for a property whose name matches `(?i)^(thread_id|session_id|id)$` at the top level or one level down — expect at least one. Find the final structured object: the **last** line whose parsed object has a property matching `(?i)^(type|event)$` with a value matching `(?i)final|result|completed|turn\.completed`. Record the exact property names you found; they become constants at the top of the adapter (`$script:CodexSessionIdProperty`, `$script:CodexResultTypeValue`). If either is not found, stop and report the distinct `type`/`event` values present.
2. Adapter functions mirroring H38-04: `New-CodexExecutionArgument -Prompt -SchemaPath` → `@('exec', '--json', '--sandbox', 'workspace-write', '--output-schema', $SchemaPath, $Prompt)`; `ConvertFrom-CodexJsonl -Lines`; `ConvertTo-CodexExecutionResult -Parsed -TaskId -ExecutionId -ChangedFiles` reading the session id and the final object's usage (any property tree named `usage` on the final object; `$null` when absent); the seven A4 names, with `Resume-CodexExecution` throwing `Codex resume is fixture-gated (H38-29)` for now and `Get-CodexAdapterCapacity` returning `$null` (the spec forbids deriving allowance from token telemetry).
3. `--sandbox workspace-write` is the **only** permission mapping in this packet; any finer mapping of the envelope waits on D-012 (say so in the header comment).
4. Runner: in `Invoke-QueuedTask`, branch on the resolved provider: `codex` → same flow as claude (branch, launch with `& codex @argv`, parse, result, verify, commit) using the Codex functions; the `codex` command must be on PATH (throw the same shape as the `'claude' not found` message).
5. Flip `codex.enabled` to `true`.

**Gate (red first) — module smoke, new section `Write-Step 'Codex adapter — smoke: recorded JSONL to ExecutionResult, offline'`:**

- Fixture → result not null, `provider = 'codex'`, `providerSessionId` non-empty, `status = 'implementation_complete'`. Predicted red: `The term 'ConvertFrom-CodexJsonl' is not recognized …`.
- Fixture with the final line removed → `$null` result.
- `Test-AgentProviderAdapter -Provider codex` conforms.
- Argv contains `--sandbox` followed by `workspace-write` and ends with the prompt.

**Roadmap write-back:** append `; H38-16 Adapter.Codex.ps1 from a recorded codex exec --json transcript; runner runs codex tasks through the same result path`.

**Stop if:** D-015 is not decided yes. Report and leave `codex.enabled = false`. **Not** a stop condition: a missing session identifier or usage block — the parser tolerates both, as the Claude adapter does.

---

### H38-17 — Router: eligibility, then ranking, reason recorded

**Roadmap item:** M3 ("Eligibility then ranking, selection reason recorded"); acceptance criterion `Provider selection records its reason`. Spec: *Provider selection* (Stage 1 conditions, Stage 2 factors), *Default routing policy* ("Neither provider is globally preferred"; Copilot "preferred when work specifically benefits from GitHub-hosted execution").

**Prerequisites:** H38-09, H38-15, **H-13b** (`Get-NextEligibleRoadmapItem` supplies the dependency clause of eligibility). D-013 is decided (2026-09-07), so step 4 runs; see **Stop if** for the one case where it does not.

**Scope (edit only):** new `backend/modules/execution/Execution.ProviderRouter.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1`; host dot-source line; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `Resolve-ProviderSelection -Packet -Registry -CapacityRecords <hashtable provider→record> -AuthStatus <hashtable provider→bool> -ActiveCounts <hashtable provider→int> -History <object[]> -Config -TaskClass -NowUtc` → `{ selected; reason = @(); candidates = @(); tie }`. **Stage 1**, per provider, every condition recorded as a string in `candidates[i].checks` and the first failure as `candidates[i].ineligibleBecause`: `enabled`; `auth valid` (from `AuthStatus`; absent → `$false`); `required capabilities supported` (packet `execution.preferredProvider` ≠ `auto` → only that provider; a packet whose `repository` is empty excludes `github-hosted` providers — there is nothing on GitHub to run against); `not cooling down` and `capacity fits` (both from `Resolve-ProviderCapacityVerdict`; when the verdict is not `enforced` the check is recorded as `advisory` and does not exclude); `concurrency slot available` (`ActiveCounts[p] < maxConcurrentExecutions`); `permissions compatible` (a packet with `githubWrite = $true` requires a `github-hosted` provider — the spec's boundary). No eligible provider → `selected = $null`, `reason = @('no eligible provider', <each provider's ineligibleBecause>)`.
2. **Stage 2**: score = Σ `weights[k] * factor[k]` with factors in `[0,1]`: `suitability` (1 when `preferredProvider` names it, 0.5 for `auto`), `usableCapacity` (the verdict's `usableRatio`, 0.5 when unmeasured), `history` (success ratio over `History` entries for the provider with the same repository, 0.5 when none), `fitsWindow` (1 when `usableRatio ≥ 2×estimate`, else 0.5), `sessionReuse` (1 when `packet.execution.previousSessionId` belongs to this provider — the packet gains `execution.previousProvider` in H38-28; 0 otherwise), `timeToReset` (1 − hours-to-nearest-reset/168 floored at 0; 0.5 when none), `estimatedConsumption` (the estimate ratio), `recentFailureRate` (failures / runs over the last 10 history entries for the provider, 0 when none). Highest score wins. Equal scores → `tie = $true` and `tieBreak` from config. `nearest-reset-first` (the decided value, D-013): among the tied candidates take the one whose **earliest** window `resetAt` is soonest; a candidate whose windows carry no `resetAt` sorts **last**; when no tied candidate has one, fall back to alphabetical by provider name. `alphabetical`: first by name. Any other value throws at load (H38-07 validates it). `reason` = `@('eligible', "<score> for <name>: …" per candidate, "selected <name>", and "tie broken by <tieBreak rule>" naming the rule that decided it when a tie applied)`.
3. Runner: when the resolved token is `auto`, build the inputs at claim time (records from disk, `AuthStatus` = `@{ claude = [bool](Get-Command claude); codex = [bool](Get-Command codex); copilot = (Test-CopilotDispatchPrecondition …).ok }`, active counts via `Get-ProviderActiveExecutionCount` with the heartbeat path (H38-11 step 2), history = the last 50 summaries in `$runsDir`), call the router, write `selectedProvider` and `selectionReason` onto the summary, and proceed with the selected provider. `selected = $null` → do not claim, log the reasons (the entry stays queued — this is `CAPACITY_WAIT` with no provider). This replaces H38-11's `routing not enabled` branch.
4. Turn routing on: set `dispatch.autoEnabled` to `true` and `dispatch.defaultTarget` to `"auto"` in `agent-providers.json` (A18), and update H38-07's config tripwire to assert the new values. **D-013 is Decided (2026-09-07)**, so this step runs — confirm the entry is still under **Decided** in `open-decisions.md` before doing it, and stop if Ben has reopened it. The weights and `tieBreak` are already the decided values from H38-07 and need no edit here. This step is the switch that turns routing on; nothing else flips it.

**Gate (red first) — module smoke, new section `Write-Step 'Provider router — smoke: eligibility then ranking, offline'`:**

- Two local providers eligible, equal inputs → `tie = $true`, selected `claude` (alphabetical), reason lists both scores. Predicted red: `The term 'Resolve-ProviderSelection' is not recognized …`.
- `claude` cooling down (enforced) → `codex` selected, reason names the cooldown; same with `enforced = $false` → `claude` still a candidate with an `advisory` check.
- Packet with empty `repository` → `copilot` ineligible with `ineligibleBecause` naming it.
- Packet with `githubWrite = $true` → only `copilot` eligible.
- All disabled → `selected = $null`, reason begins `no eligible provider`.
- Every `reason` element is a non-empty string and `candidates` serializes as `[]` when the registry is empty.

**Roadmap write-back:** append `; H38-17 Resolve-ProviderSelection — Stage 1 checks and Stage 2 scores recorded per candidate; the runner resolves auto at claim time and writes selectedProvider/selectionReason`.

**Stop if:** D-013 has been reopened or removed from **Decided** in `open-decisions.md` (do steps 1–3, **skip step 4**, leave `dispatch.autoEnabled = false` so every dispatch still goes to `claude`, and report that routing is built but off); or H-13b's selector is not merged (the dependency clause cannot be wired).

---

### H38-18 — One vocabulary at the host

**Roadmap item:** M3 ("reconciles the third vocabulary (`operator-runner`) the approval route writes … presence counts derived from the registry rather than naming providers").

**Prerequisites:** H38-14.

**Scope (edit only):** `backend/api-host/Start-RepoManagementApiHost.ps1` (the `'POST /api/roadmap/dispatch/execute'` and `'POST /api/automation/packages/approve'` cases only); `backend/modules/automation/Automation.RunnerPresence.ps1` (`Get-QueuedTaskBacklog` only); `scripts/Invoke-ApiHostSmokeTest.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Dispatch route: read `dispatchTarget` from the body; when absent or blank, default to `dispatch.defaultTarget` from `Get-AgentProviderConfig` (the config H38-07b already loads in this route — `claude` until H38-17 step 4 flips it, A18). Resolve through `Resolve-RoadmapDispatchTarget` (400 with `category = 'validation'` on throw, message = the throw text). When the resolved token is `auto` and `dispatch.autoEnabled` is false → 400, `category = 'validation'`, message `dispatchTarget 'auto' is not enabled yet; the provider router lands in H38-17. Use claude, codex or copilot.` Write the resolved token into **both** places the route currently hardcodes `'copilot'` (the queue entry's `-DispatchTarget` and the run summary's `dispatchTarget`) and into the response `data.dispatchTarget`. Add `provisionalSelection = $null` to the response (H38-35 may fill it from a host-side dry run of the router; not here).
2. Approval route: replace `dispatchTarget = 'operator-runner'` in the 200 payload with the token the queue entry actually carries (read it back from `$approveDispatchResult` if it exposes it; otherwise from the queue entry written for that run — discover which; if neither, use `'auto'` and say so in the report).
3. `Get-QueuedTaskBacklog`: add `queuedByProvider` — an ordered hashtable with one key per registry token except `auto`, plus `auto` itself, counts from the entries. **Keep** `queuedClaude` and `queuedCopilot` with their current semantics (golden: they are what the frontend reads until H38-19).
4. `'GET /api/roadmap/runner'` case (host line ~7851): add `dispatch = [ordered]@{ defaultTarget = <config dispatch.defaultTarget>; autoEnabled = <config dispatch.autoEnabled> }` to the `data` payload, read from `Get-AgentProviderConfig`; `$null` for both when the config is absent. The frontend preview (H38-19) shows this value as the intended provider instead of hardcoding one.

**Gate (red first):**

- Api-host smoke, dispatch step: POST with `dispatchTarget = 'codex'` → the queue line carries `codex`; with `'nope'` → 400 JSON, `category = 'validation'`, message begins `Unknown dispatchTarget 'nope'`; with no field → the token equals the committed config's `dispatch.defaultTarget` (read the config file in the smoke; do not hardcode `claude`, because H38-17 step 4 changes it); with `'auto'` while the config's `autoEnabled` is false → 400, message begins `dispatchTarget 'auto' is not enabled`. Predicted red on unchanged code: the queue line carries `copilot` regardless.
- Api-host smoke, presence step: `GET /api/roadmap/runner` JSON has `queuedByProvider` with keys `claude, codex, copilot, auto` and `queuedClaude + queuedCopilot == queuedByProvider.claude + queuedByProvider.copilot` (golden equality on the pre-existing fields); `data.dispatch.defaultTarget` equals the committed config's value and `data.dispatch.autoEnabled` is a boolean.
- Module smoke: the host source no longer contains the literal `'operator-runner'` (grep the source text as the existing dot-source gate does).

**Roadmap write-back:** append `; H38-18 dispatch/execute takes a target (default from config, auto refused until the router lands), approval reports the real token, backlog is counted per registry token — queuedClaude/queuedCopilot unchanged`.

**Stop if:** the dispatch route hardcodes `'copilot'` in more than the two sites named (report all); or the approval route cannot learn the queue entry's token without a new read (report the shape of `$approveDispatchResult`).

---

### H38-19 — Frontend: target union, presence by provider, intended provider in the preview

**Roadmap item:** M3 (`frontend/types.ts` names the pair). D-008: preview surfaces "expose … intended provider".

**Prerequisites:** H38-18.

**Scope (edit only):** `frontend/types.ts`; `frontend/lib/runnerPresence.ts` (+ its test file if one exists — check); `frontend/services/apiClient.ts` (`executeRoadmapDispatch` body type only); `frontend/components/CopilotTaskPreviewModal.tsx` (+ its test); `frontend/components/RunnerHealthIndicator.tsx`; `ROADMAP.md`.

**Steps**

1. `types.ts`: `dispatchTarget?: 'claude' | 'copilot'` (one match, on `DispatchExecuteResult`) → `export type ProviderToken = 'claude' | 'codex' | 'copilot' | 'auto';` and `dispatchTarget?: ProviderToken;`.
2. `runnerPresence.ts`: `RunnerPresencePayload` gains `queuedByProvider?: Partial<Record<ProviderToken, number>>` and `dispatch?: { defaultTarget: ProviderToken | null; autoEnabled: boolean | null }` (H38-18 step 4); keep `queuedClaude`/`queuedCopilot`. Where the payload is summarized for display, prefer `queuedByProvider` when present.
3. `executeRoadmapDispatch`: the body gains optional `dispatchTarget?: ProviderToken`; default omitted (the host defaults to the config's `dispatch.defaultTarget` — `claude` until H38-17 turns routing on, A18).
4. Preview modal: render one `text-sm` line `Intended provider: <token>` from a new optional prop `intendedProvider?: ProviderToken | null`; when the prop is absent or `null` the line reads `Intended provider: not yet known` — **no hardcoded token in the component**. The Dispatch Board passes the presence payload's `dispatch.defaultTarget` (H38-35 wires the value; here the prop exists and the fallback text is fixed).
5. `RunnerHealthIndicator.tsx`: when `queuedByProvider` exists, list non-zero counts as `claude 2 · codex 0 · copilot 1` in `text-sm`.

**Gate (red first) — vitest, existing test files:**

- Preview modal renders `Intended provider: not yet known` with no prop and `Intended provider: codex` when passed. Predicted red: text not found.
- `resolveRunnerPresence` with `queuedByProvider` present yields the per-provider summary; without it, output identical to a golden captured before the change.
- `npm run typecheck` green; `npm run lint` warning count unchanged; `node tools/Measure-UiRatchet.mjs` reports no new tiny-text node.

**Roadmap write-back:** append `; H38-19 ProviderToken union, queuedByProvider on the presence payload, preview names the intended provider`.

**Stop if:** `RunnerPresencePayload` is constructed in more than the API client and the two components named (report).

---

### H38-20 — Milestone 3 closing

**Roadmap item:** M3 state clause.

**Scope (edit only):** `docs/reference/local-task-runner.md`; `ROADMAP.md`.

**Steps**

1. Combined green run of module smoke, api-host smoke, `npm run test:unit`.
2. `local-task-runner.md`: the header line `# Local task runner (Claude Code and Copilot)` → `# Local task runner (Claude Code, Codex and Copilot)`; add a subsection `## Which provider runs a task (Release 3.8 M3)` of at most 15 lines: the four tokens, `auto` resolved at claim time, where the reason is recorded.

**Roadmap write-back:** M3 state word → `smoke-tested <date>`.

**Stop if:** H38-16 was stopped on D-015 — then the closing state is `backend-complete <date>` with the clause `codex adapter fixture-gated (D-015)`, and this is reported, not hidden.

---

### H38-21 — The runner pushes after `IMPLEMENTATION_COMPLETE`

**Roadmap item:** Release 3.8 M4, `Move push and PR opening to Repo Manager; bind approval to the verified SHA.` Spec: *CI ownership* ("agent exits → PUSHING → PR_OPEN"), *GitHub boundary*.

**Prerequisites:** H38-03, H38-14.

**Scope (edit only):** `scripts/Invoke-RoadmapTaskRunner.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `docs/reference/local-task-runner.md`; `ROADMAP.md`.

**Steps**

1. Pure helper `Resolve-PostImplementationTransition -Outcome -ProviderConfig -VerifyResult` → `{ nextStatus; push }`: outcome `awaiting-review` and `ProviderConfig.autoPush` true and `VerifyResult -ne 'failed'` → `{ 'pushing'; $true }`; outcome `awaiting-review` and `VerifyResult -eq 'failed'` → `{ 'awaiting-review'; $false }` (a failed local verification is `LOCAL_VERIFYING → REMEDIATION` territory; H38-31 owns the enqueue, and for now the operator sees it as today); `autoPush` false → `{ 'awaiting-review'; $false }`; any other outcome → `{ <outcome>; $false }`.
2. In `Invoke-QueuedTask`, after the completion-edit commit: when `push` is true, run `& git -C $repo push -u origin $branch 2>&1 | Out-String`; exit 0 → summary `status = 'pushed'`, `pushedAt`, `pushedBy = 'runner'`, `prState = 'pending-open'`; non-zero → summary `status = 'awaiting-review'`, `pushError = <output>`, and the operator path stays exactly as today (Approve & push still works because the status is `awaiting-review`).
3. Never push the default branch: refuse (`status = 'failed'`, error `refusing to push the default branch`) when `$branch` equals the repo's default branch (read it the way `Sync-RepoDefaultBranch` does, via `git symbolic-ref refs/remotes/origin/HEAD`, falling back to `main`).
4. `local-task-runner.md`: the sentence `Nothing is pushed to GitHub by the runner.` → `With autoPush on (the default for local providers) the runner pushes the branch after a successful result and verification; the PR is opened by the portal's reconcile tick. With autoPush off, the runner stops at awaiting-review as before.`

**Gate (red first) — module smoke, extend the runner section:**

- Transition table: four cases above. Predicted red: `The term 'Resolve-PostImplementationTransition' is not recognized …`.
- Real push, offline: the smoke already has a bare-remote fixture (`output\smoke\module\branch-pr-fixture` or the approve-push fixture — discover which creates a bare remote) — reuse it: a runner-shaped push to the bare remote succeeds and the summary reads `pushed`, `prState = 'pending-open'`; a push to a remote that rejects (make the bare repo's branch unwritable by pre-creating a diverging commit) yields `awaiting-review` with `pushError`.
- **Golden:** `autoPush = $false` → the summary is byte-identical in its pre-existing keys to today's `awaiting-review` write.

**Roadmap write-back:** M4 `_(state: planned)_` → `_(state: scaffolded <date> — H38-21 the runner pushes after a complete, verified result (autoPush per provider, default on); awaiting-review survives at off or on push failure)_`.

**Stop if:** the runner has no access to a bare-remote fixture in the smoke (report the fixture names present); or the default-branch read cannot be done without `Git.DefaultBranchSync.ps1` being loaded (it is dot-sourced when present — if absent in the smoke, load it).

---

### H38-22 — `POST /api/delivery/reconcile`

**Roadmap item:** M4 ("Repo Manager … opens the pull request and monitors CI on a cadence without holding an execution slot — which also closes Lane 0.17's open 'nothing refreshes the board' non-blocker"). Spec: *CI ownership* ("Repo Manager monitors CI without consuming an AI execution slot").

**Prerequisites:** H38-21.

**Scope (edit only):** `backend/api-host/Start-RepoManagementApiHost.ps1` (one new route + one new function beside `Invoke-AgentRunAutoClose`); `scripts/Invoke-RoadmapTaskRunner.ps1` (poll-loop call only); `scripts/Invoke-ApiHostSmokeTest.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Function `Invoke-DeliveryReconciliation -WorkspaceRoot -CorrelationId -MaxRuns 3` returning `[ordered]@{ prsOpened; refreshed; failed; skipped }`, placed directly after `Invoke-AgentRunAutoClose` and written in its style (bounded, per-run failures swallowed and counted, never throws):
   - **Open pending PRs:** for each run summary with `status = 'pushed'` and `prState = 'pending-open'` (newest first, at most `MaxRuns`): call `Open-RepoBranchPullRequest -RepoName (Split-Path -Leaf localRepoPath) -RepoPath localRepoPath -Branch branch -Token (Get-ConfiguredGitHubToken -Settings (Get-HostSettings)) -Title selectedTask -Body …` exactly as the approve-push route builds its call (copy the title/body expressions). On `created` or `alreadyExisted`, patch the summary with `prUrl`, `prNumber`, `prOpenedAt`, `prState = 'open'`; on `refused`, patch `prState = 'open-refused'`, `prRefusal = { category; reason }` and count it in `failed` — the branch is pushed, the refusal is named, nothing is retried in a loop (a refusal is re-examined only when the summary changes).
   - **Refresh CI:** call `Invoke-AgentRunAutoClose -WorkspaceRoot $WorkspaceRoot -CorrelationId $CorrelationId -MaxRuns $MaxRuns -CooldownMinutes 1` and add its counts.
2. Route `'POST /api/delivery/reconcile'` → `{ success = $true; data = <the summary> }`. No body required. Under `RunningAsService` it behaves identically (it reads and writes only local ledgers plus one GitHub PR create per pending run).
3. Runner pure helper `New-RunnerReconcileRequest -BaseUrl -ApiKey` → the splat hashtable for `Invoke-RestMethod`: `Method = 'Post'`, `Uri = "<BaseUrl trimmed of '/'>/api/delivery/reconcile"`, `ContentType = 'application/json'`, `Body = '{}'`, `TimeoutSec = 20`; when `Uri` matches `^(?i)https:` add `SkipCertificateCheck = $true` (the runner is `#Requires -Version 7.0`, so the parameter always exists — no 5.1 callback fallback); when `ApiKey` is non-blank add `Headers = @{ 'X-Api-Key' = $ApiKey }`, otherwise **no** `Headers` key at all. This is the api-host smoke's `Invoke-ApiRequest` (lines ~111–117) and `Watch-PortalHealth.ps1`'s `Test-PortalHealth` (lines ~226–234) in one place.
4. Runner: keep a counter in the poll loop; every fourth iteration, `$reconcileRequest = New-RunnerReconcileRequest -BaseUrl $base -ApiKey $key; Invoke-RestMethod @reconcileRequest` (hashtable splatting, not `@( )`) where `$base` is `https://127.0.0.1:7071` unless `REPO_MGMT_PORTAL_BASE_URL` is set (a new variable; read it once at startup the way `REPO_MGMT_QUEUE_PATH` is read at line ~128, and print it beside the heartbeat path), and `$key` is `[Environment]::GetEnvironmentVariable('REPO_MGMT_API_KEY')` read at every tick, not cached (`Enable-SharedLanAccess.ps1` sets it at Machine scope while a runner may already be up). **127.0.0.1, never localhost; https, never http** — the portal has been TLS-only since 2026-08-29 and plain `http://` does not answer (ROADMAP Lane 0.2, "The HTTPS flip's fallout"). Any failure is logged at `DarkYellow` with the status code when one exists and ignored — the host may be down; the tick is best-effort by design. A 401 is logged as `reconcile refused: 401 — set REPO_MGMT_API_KEY in this shell` so the operator does not read it as a host outage.

**Gate (red first):**

- Api-host smoke: seed one `pushed`/`pending-open` summary whose `localRepoPath` is a fixture repo with a bare remote **and no token** in the smoke environment → after `POST /api/delivery/reconcile`, `data.failed = 1`, and the summary reads `prState = 'open-refused'` with `prRefusal.category = 'auth'` (the refusal matrix's exact category for a missing token). Predicted red: the route answers `200 text/html`. Route census updated (R16 — it is a POST, so not in `$censusRoutes`; add its own step instead).
- Module smoke: `Invoke-DeliveryReconciliation` is not directly loadable (host script) — assert over the host source that the function exists and that `Invoke-AgentRunAutoClose` is called from inside it (the same source-text technique the smoke uses for `Execution.Trace.ps1` presence at its line ~4059).
- Runner: the poll-loop counter fires on iteration 4, 8, … (extract `Test-RunnerReconcileDue -Iteration -Every 4` as a pure helper and test it).
- Runner: `New-RunnerReconcileRequest -BaseUrl 'https://127.0.0.1:7071/' -ApiKey 'k'` → `Uri = 'https://127.0.0.1:7071/api/delivery/reconcile'`, `SkipCertificateCheck = $true`, `Headers['X-Api-Key'] = 'k'`; with `-BaseUrl 'http://127.0.0.1:7171' -ApiKey ''` → no `SkipCertificateCheck` key and no `Headers` key. Predicted red: `The term 'New-RunnerReconcileRequest' is not recognized …`.
- Runner source tripwire: the literal `http://127.0.0.1:7071` appears **zero** times in `Invoke-RoadmapTaskRunner.ps1` (the api-host smoke's own `http://127.0.0.1:7171` is a different port on a TLS-less test boot and is not in scope).

**Roadmap write-back:** append `; H38-22 POST /api/delivery/reconcile opens pending PRs with the host's token and refreshes CI; the runner calls it every fourth poll`. Also, on Lane 0.17's `[non-blocker] The board reads observed state; nothing refreshes it on a cadence` item: change `_(state: planned)_` to `_(state: smoke-tested <date> — closed by Release 3.8 H38-22: the runner's poll loop calls POST /api/delivery/reconcile every fourth poll, which runs Invoke-AgentRunAutoClose)_`.

**Stop if:** `Open-RepoBranchPullRequest`'s refusal for a missing token is not category `auth` (read `Test-RepoBranchPrReadiness` and use its actual category in the assertion — report the change); or the host's `RunningAsService` branch refuses git operations in a way that blocks step 1 (report the guard); or `Invoke-RestMethod` on the runner's pwsh lacks `SkipCertificateCheck` (`(Get-Command Invoke-RestMethod).Parameters.ContainsKey('SkipCertificateCheck')` is false — report the pwsh version).

---

### H38-23 — Record the verified head SHA

**Roadmap item:** M4 ("A head change after verification invalidates `READY_FOR_OPERATOR`"); acceptance criterion `Operator approval names a verified head SHA`. Spec: *Promotion invariant* ("Approval applies to the verified commit SHA, not merely the pull request number").

**Prerequisites:** H38-22; **H-10** (per-check conclusions; without it a rollup `success` still counts, and the packet says which basis it used).

**Scope (edit only):** `backend/modules/agent-runs/AgentRuns.ps1` (`Invoke-AgentRunRefresh`, `Update-AgentRunRecord`'s metric-key list untouched); `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. In `Invoke-AgentRunRefresh`, when a PR candidate is found, read `head.sha` from the PR object (`_AgentRunsField -Obj $head -Name 'sha'`) and patch `prHeadSha`. When `$ActionsRun` is present with `status = 'completed'` and `conclusion = 'success'` and the observed `ActionsRun` carries a `headSha` property equal to `prHeadSha` (add `headSha` to what the host passes — discover the call site of `Invoke-AgentRunRefresh` in the host and the GitHub Actions run object it reads; the workflow-run API's `head_sha` is the source), patch `verifiedHeadSha = prHeadSha`, `readyForOperatorAt = $nowIso`, `verificationBasis = 'check-runs'` when H-10's basis is available else `'actions-rollup'`.
2. When `prHeadSha` changes between refreshes and `verifiedHeadSha` is set and differs → patch `verifiedHeadSha = $null`, `readyForOperatorAt = $null`, `headMovedAt = $nowIso`, and emit `Write-AgentRunEvent -EventType 'run.head-moved'` with both SHAs.
3. Never set `verifiedHeadSha` from a rollup whose `headSha` is unknown — a success with no head is evidence about *something*, not about this head.

**Gate (red first) — module smoke, extend the agent-runs section (find the existing `Invoke-AgentRunRefresh` assertions — `Select-AgentRunPullRequestCandidate` is tested there):**

- PR with `head.sha = 'aaa'`, Actions `completed/success` with `headSha = 'aaa'` → `verifiedHeadSha = 'aaa'`, `readyForOperatorAt` set. Predicted red: `verifiedHeadSha` absent from the record.
- Same, Actions `headSha = 'bbb'` → `verifiedHeadSha` null.
- Second refresh with PR `head.sha = 'ccc'` → `verifiedHeadSha` null, `headMovedAt` set, one `run.head-moved` event in `events.jsonl`.
- **Golden:** a refresh with no `headSha` on the Actions object leaves every pre-existing patched field identical to a golden captured before the change.

**Roadmap write-back:** append `; H38-23 Invoke-AgentRunRefresh records prHeadSha and verifiedHeadSha only when CI passed on that exact head; a moved head clears it and emits run.head-moved`.

**Stop if:** the host's Actions object handed to `Invoke-AgentRunRefresh` has no head SHA and the API response it is built from has none either (report the fields present).

---

### H38-24 — Approval binds to a SHA; merge refuses on drift

**Roadmap item:** M4 ("Merge stays an explicit operator action"); §8 *Operator approval applies to a verified head SHA*. Spec: *Promotion invariant*.

**Prerequisites:** H38-23.

**Scope (edit only):** `backend/modules/agent-runs/MergeReadiness.ps1`; `backend/api-host/Start-RepoManagementApiHost.ps1` (one new route; the `/merge` branch of the merge-readiness handler); `scripts/Invoke-ApiHostSmokeTest.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `Get-MergeReadinessEvaluation` gains `-OperatorApproval <object>` (the run's `operatorApproval`, or `$null`) and `-CurrentHeadSha <string>`. New blockers, appended after `actions-failing` and before `dirty-worktree`: `no-verified-head` when the run has no `verifiedHeadSha`; `no-operator-approval` when `OperatorApproval` is null; `head-moved-since-approval` when `OperatorApproval.sha` ≠ `CurrentHeadSha`. Every existing blocker keeps its code, message and order (golden).
2. Route `'POST /api/agent-runs/{id}/approve'` (match the path the way the merge-readiness handler matches `/api/merge-readiness/*`): body `{ sha }` required; 404 when the run is unknown; 409 `category = 'not-ready'` when `verifiedHeadSha` is null or ≠ `sha`; else `Update-AgentRunRecord` with `operatorApproval = @{ sha; at = now; actor = 'operator' }` and `Write-AgentRunEvent -EventType 'run.operator-approved'`; 200 with the record.
3. The `/merge` branch: pass the run's `operatorApproval` and the fresh PR detail's `head.sha` into the evaluation (the host already fetches PR detail in `Invoke-MergeReadinessForRepo` — discover where `PrDetail` is built and thread `head.sha` through). The existing `if (-not $mrOutcome.evaluation.ready)` refusal then covers the three new blockers with no new branch.

**Gate (red first):**

- Module smoke, extend the merge-readiness section: an otherwise-ready evaluation with no approval → one blocker `no-operator-approval`; with approval `sha='aaa'` and head `'bbb'` → `head-moved-since-approval`; with no `verifiedHeadSha` → `no-verified-head`. Predicted red on unchanged code: `ready = $true` for the first case.
- **Golden:** the pre-change fixture inputs (no approval parameters passed) produce a blocker list identical to a golden captured before the change **except** for the appended new codes — assert the prefix equality.
- Api-host smoke: seed a run with `verifiedHeadSha = 'aaa'`; `POST /api/agent-runs/<id>/approve` with `sha = 'bbb'` → 409 JSON `not-ready`; with `'aaa'` → 200 and the record shows `operatorApproval.sha = 'aaa'`; unknown id → 404 JSON. Predicted red: SPA `200 text/html`.

**Roadmap write-back:** append `; H38-24 POST /api/agent-runs/{id}/approve stores operatorApproval bound to verifiedHeadSha; merge readiness refuses no-verified-head, no-operator-approval, head-moved-since-approval`.

**Stop if:** the merge-readiness handler builds `PrDetail` in more than one place; or `Get-MergeReadinessEvaluation` has a caller whose blocker list is asserted by a frontend test you would need to change (report the test).

---

### H38-25 — Frontend: approve the SHA you see

**Roadmap item:** M4. D-008: the Dispatch Board is where "final execution confirmation" is shown.

**Prerequisites:** H38-24.

**Scope (edit only):** `frontend/services/apiClient.ts` (one new function `approveAgentRun(runId, sha)`); `frontend/types.ts` (`AgentRun` gains `prHeadSha?`, `verifiedHeadSha?`, `readyForOperatorAt?`, `operatorApproval?`); the component that renders the merge control (discover: the caller of `executeMergeReadinessMerge` — expect one component); its test; `ROADMAP.md`.

**Steps**

1. Types and client function.
2. In the merge-control component: render, in `text-sm`, `Verified head: <sha7>` when `verifiedHeadSha` is set, else `Not yet verified`; an `Approve <sha7>` button when `verifiedHeadSha` is set and `operatorApproval` is null; `Approved <sha7>` text when set; and the merge control **disabled** with title `Head moved since approval` when `prHeadSha ≠ operatorApproval.sha`. The button calls `approveAgentRun`.

**Gate (red first) — vitest on the component's test file:** four render states above; the disabled state's title text. Predicted red: `Approve` button not found. `npm run typecheck`, `npm run lint` (no new warning), UI ratchet clean.

**Roadmap write-back:** append `; H38-25 the merge control shows and approves the verified SHA and disables on head drift`.

**Stop if:** more than one component calls `executeMergeReadinessMerge` (report both).

---

### H38-26 — Milestone 4 closing

**Roadmap item:** M4 state clause; §8 guardrail *Do not merge automatically* re-checked.

**Scope (edit only):** `docs/product/delivery-loop.md`; `docs/reference/local-task-runner.md`; `ROADMAP.md`.

**Steps**

1. Combined green run (module smoke, api-host smoke, `npm run test:unit`).
2. Grep the host for `merge_method` — expect exactly the one call inside the `/merge` branch; confirm it is reachable only after the `ready` check. Record the line number in the report. This is the §8 audit; if a second merge call exists, stop.
3. `delivery-loop.md` *What is built* table: rows 6, 7, 8 get, after an em-dash, the suffix `Release 3.8: runner pushes; host opens the PR on the reconcile tick; approval binds to the verified SHA (H38-21/22/24)`.

**Roadmap write-back:** M4 state word → `smoke-tested <date>`.

**Stop if:** step 2 finds a second merge call.

---

### H38-27 — Attempt and remediation counters, persisted before any halt

**Roadmap item:** Release 3.8 M5, `Remediate from evidence, and hand off between providers.` ("Attempt and remediation counts survive a restart"). Spec: *Persistence requirements* ("No retry counter … may exist only in process memory").

**Prerequisites:** H38-03.

**Scope (edit only):** `scripts/Invoke-RoadmapTaskRunner.ps1`; `backend/modules/execution/Execution.WorkPacket.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. Runner: at claim, `attempt` on the summary = existing `attempt` if present else 1 (H38-10 introduced it); `remediationCount` = existing or 0. Both written with the `running` status write, so a crash after the claim still leaves them on disk.
2. `Test-RemediationCapReached -Summary -Config` (pure, in `Execution.WorkPacket.ps1`) → `{ reached; count; cap }` with `cap = Config.remediation.maxRemediationAttempts`.
3. When a remediation is about to be enqueued (H38-31) or resumed (H38-29), the caller **first** writes the incremented `remediationCount` to the summary, **then** evaluates the cap; on `reached`, the summary gets `status = 'blocked'`, `blockedCode = 'remediation-cap-reached'`, `error = "remediation cap <cap> reached after <count> attempts"` — the persist-before-halt ordering from Lane 0.18. Implement the helper `Write-RemediationAttempt -SummaryPath -Config` that does exactly this and returns the cap verdict; H38-29/31 call it.

**Gate (red first) — module smoke, extend the runner section:**

- `Write-RemediationAttempt` on a summary with `remediationCount = 1`, cap 2 → file shows 2, verdict `reached = $true`, status `blocked` with the exact error string. Predicted red: `The term 'Write-RemediationAttempt' is not recognized …`.
- Count 0 → file shows 1, not reached, status unchanged.
- Simulated crash: write with a summary path whose directory is read-only (or a `Set-Content` that throws via a mocked path) → the function throws **before** returning a verdict; assert no verdict was returned (the ordering is the point).

**Roadmap write-back:** M5 `_(state: planned)_` → `_(state: scaffolded <date> — H38-27 attempt and remediationCount live on the run summary and are written before the cap verdict (Write-RemediationAttempt))_`.

**Stop if:** nothing — pure and additive.

---

### H38-28 — `RemediationPacket` from CI evidence

**Roadmap item:** M5 ("a CI failure builds a `RemediationPacket`"). Spec: *CI ownership* ("collect failure evidence → build RemediationPacket").

**Prerequisites:** H38-27, H38-23 (and H-10 for per-check names).

**Scope (edit only):** new `backend/modules/execution/Execution.Handoff.ps1`; host dot-source line (after the router); `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `New-RemediationPacket -WorkPacket -AgentRun -Summary -CiFailures <object[]>` → a `WorkPacket` (via `New-WorkPacket`) with: `objective` = `"Remediate CI failure on <branch>: " + original objective`; `acceptanceCriteria` = original + one line per failure `CI check '<name>' must pass (was: <conclusion>)`; `execution.attempt` = summary attempt + 1; `execution.previousSessionId` = summary `providerSessionId`; plus two **extra** keys the spec allows on a packet (`Test-WorkPacket` must accept unknown top-level keys — add that tolerance to it now): `remediation = @{ ciFailures = <array of { name; conclusion; url }>; headSha = AgentRun.prHeadSha; remediationCount = summary.remediationCount }` and `execution.previousProvider` = summary `selectedProvider` (or `dispatchTarget`).
2. `CiFailures` come from the caller: with H-10 landed, the per-check blockers from `Get-MergeReadinessEvaluation` whose code is `actions-failing`-kind; without it, one entry `{ name = actions.workflowName; conclusion = actions.conclusion; url = actions.runUrl }`.

**Gate (red first) — module smoke, new section `Write-Step 'Remediation packet — smoke: built from evidence, offline'`:**

- Given the H38-01 example packet, a summary `{ attempt=1; providerSessionId='s1'; selectedProvider='claude'; remediationCount=0 }`, an agent run with `prHeadSha='aaa'` and two failures → attempt 2, previous session `s1`, previous provider `claude`, two appended criteria naming the checks, `remediation.headSha = 'aaa'`; `Test-WorkPacket` valid. Predicted red: `The term 'New-RemediationPacket' is not recognized …`.
- Original criteria are still present verbatim (superset check).

**Roadmap write-back:** append `; H38-28 New-RemediationPacket carries the CI failures as acceptance criteria and the prior session/provider`.

**Stop if:** `Test-WorkPacket` cannot be made tolerant of extra keys without changing an H38-01 assertion — then update that assertion in the same PR and say so.

---

### H38-29 — Resume the original session where capacity allows

**Roadmap item:** M5 ("resumes the original session where capacity allows"). Spec: *Default routing policy* (remediation: "original provider session available? YES + capacity available → resume original session").

**Prerequisites:** H38-28, H38-09. Codex half: **D-015** only; the resume fixture `tests/fixtures/providers/codex-exec-resume.synthetic.jsonl` is authored by this packet (R12).

**Scope (edit only):** `backend/modules/execution/Execution.Handoff.ps1`; `backend/modules/agent-adapters/Adapter.Claude.ps1`; `backend/modules/agent-adapters/Adapter.Codex.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `Resolve-RemediationRoute -Packet -Registry -CapacityRecords -Config -NowUtc` (pure, in `Execution.Handoff.ps1`) → `{ mode = 'resume' | 'handoff' | 'blocked'; provider; reason }`: `resume` when `packet.execution.previousProvider` is enabled, its adapter's `Get-<P>AdapterCapability().supportsResume` is true, `packet.execution.previousSessionId` is non-empty, and `Resolve-ProviderCapacityVerdict -TaskClass remediation` is eligible; else `handoff` with the reason (`no previous session`, `provider does not support resume`, `capacity: <verdict reason>`); `blocked` only when the registry has no enabled provider at all.
2. Runner: when a claimed entry's packet has `remediation`, call `Write-RemediationAttempt` (H38-27) first; on `reached`, stop. Then `Resolve-RemediationRoute`; on `resume`, launch with `Resume-<P>Execution -SessionId … -Prompt (ConvertTo-<P>Prompt -Packet) -PermissionMode …` instead of `Start-`; on `handoff`, fall through to H38-30's path (until H38-30 lands, treat as `blocked` with reason `handoff not yet available`).
3. Claude's `Resume-ClaudeExecution` already exists (H38-04). Codex's: only if the resume fixture exists — apply the H38-16 discovery step to it and implement `Resume-CodexExecution` with the argv the fixture's invocation used (the operator records the command line in the fixture's first line as a comment-free JSON object `{ "argv": [...] }`); otherwise leave it throwing and report.

**Gate (red first) — module smoke, extend the remediation section:**

- Claude previous session, eligible capacity → `resume`. Predicted red: `The term 'Resolve-RemediationRoute' is not recognized …`.
- Same with weekly ratio below reserve but `remediationInsideWeekly = true` → still `resume` (remediation may use the reserve).
- Previous provider `copilot` → `handoff`, reason `provider does not support resume`.
- Empty previous session → `handoff`, reason `no previous session`.
- Runner: a remediation entry at the cap → summary `blocked`, `remediation-cap-reached`, and **no** adapter argv was built (assert via the pure helper ordering).

**Roadmap write-back:** append `; H38-29 Resolve-RemediationRoute resumes the original session when it exists, the provider supports it and remediation capacity allows; cap checked first`.

**Stop if:** the Codex resume fixture is absent — do the Claude half, leave Codex throwing, report.

---

### H38-30 — `HandoffPacket`, durable evidence only

**Roadmap item:** M5 ("otherwise transfers a `HandoffPacket` of durable evidence to another eligible provider. No provider depends on another's conversation"). Spec: *Remediation handoff* (field list), *Default routing policy* ("A provider switch MUST start a new provider session").

**Prerequisites:** H38-29, H38-17.

**Scope (edit only):** `backend/modules/execution/Execution.Handoff.ps1`; `scripts/Invoke-RoadmapTaskRunner.ps1`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `New-HandoffPacket -RemediationPacket -PriorResult <ExecutionResult> -Summary` → the spec's exact keys: `taskId, attempt, previousProvider, objective, baseSha, headSha, changedFiles, priorResult, ciFailures, acceptanceCriteria, remainingScope` where `remainingScope` = the acceptance criteria not marked satisfied in `priorResult` (the result has no per-criterion field in 3.8, so `remainingScope` = all criteria; record that in a comment — Lane 0.18's acceptance check would refine it). `priorResult` is the **ExecutionResult object only** — never the stream transcript, never the prompt.
2. `Test-HandoffPacket` errors: the spec's required keys; plus `priorResult must not contain a transcript` (reject when any string value in `priorResult` exceeds 4,000 characters or any key is named `events`, `stream`, `lines`, `messages`).
3. `ConvertTo-HandoffPrompt -HandoffPacket` → the H38-05 rendering with a `## Prior attempt (<previousProvider>)` section listing `changedFiles`, `ciFailures`, and `priorResult.summary`.
4. Runner: on `handoff`, build the HandoffPacket, call `Resolve-ProviderSelection` with the previous provider **excluded** (pass a registry copy with it disabled) and `execution.previousSessionId = $null` (a switch starts a new session — spec), write `selectedProvider`, launch with `Start-<P>Execution` on `ConvertTo-HandoffPrompt`.

**Gate (red first) — module smoke, extend the remediation section:**

- Built packet has the spec's 11 keys and nothing named `events`/`stream`; `priorResult` equals the ExecutionResult passed in (deep-equal on serialized JSON). Predicted red: `The term 'New-HandoffPacket' is not recognized …`.
- A `priorResult` with a 5,000-character string → `Test-HandoffPacket` names the transcript rule.
- Router call with `claude` excluded and `codex` disabled → `selected = $null` (no eligible provider) — the runner leaves the entry queued with that reason.
- Rendered prompt contains every acceptance criterion verbatim and the `## Prior attempt (claude)` heading.

**Roadmap write-back:** append `; H38-30 New-HandoffPacket carries only durable evidence (transcripts rejected); a switch excludes the previous provider and starts a fresh session`.

**Stop if:** nothing structural; report if the router has no way to exclude a provider without mutating config (then add `-Exclude <string[]>` to `Resolve-ProviderSelection` in this PR and say so).

---

### H38-31 — `CI_FAILED` → remediation enqueue on the reconcile tick

**Roadmap item:** M5 ("a CI failure builds a `RemediationPacket`"), spec *CI ownership* ("CI_FAILED → collect failure evidence → build RemediationPacket → Governor evaluates provider capacity → resume or redispatch").

**Prerequisites:** H38-30, H38-22.

**Scope (edit only):** `backend/api-host/Start-RepoManagementApiHost.ps1` (`Invoke-DeliveryReconciliation` only); `scripts/Invoke-ApiHostSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. In `Invoke-DeliveryReconciliation`, after the CI refresh: for each agent run whose latest `actions.conclusion` is not `success` and `status -ne 'completed'` and whose dispatch summary has no `remediationEnqueuedFor` equal to that Actions `runUrl` (idempotency key): call `Write-RemediationAttempt`; on `reached` skip (the summary is already `blocked`); else build `New-RemediationPacket` (failures from H-10 when available), `Save-WorkPacket` under a new task id `<runId>-r<remediationCount>`, write a queue line + `queued` summary through `New-RoadmapQueueEntry` with `-DispatchTarget <target>` and `-WorkPacketPath`, patch the original summary with `remediationEnqueuedFor = runUrl` and `remediationTaskId`, and count `remediationsEnqueued` in the result. `<target>` is `dispatch.defaultTarget` from `Get-AgentProviderConfig` (A18: `claude` until H38-17 step 4 turns routing on, then `auto`) — **never** the literal `'auto'`, which the runner cannot claim while `autoEnabled` is false. Record the value used as `remediationDispatchTarget` on the original summary.
2. **Governor evaluation happens at claim** (H38-11/H38-17) — the host enqueues; the runner decides resume vs handoff with capacity. The host never runs an agent. While routing is off, the remediation runs on `claude`, and H38-29's session resume still applies when the original provider was `claude`.

**Gate (red first) — api-host smoke:** seed a run with `actions = { status='completed'; conclusion='failure'; runUrl='u1' }` and a summary with `remediationCount = 0` → after `POST /api/delivery/reconcile`, `data.remediationsEnqueued = 1`, a new queue line whose `dispatchTarget` equals the committed config's `dispatch.defaultTarget` (read the file; do not hardcode) and a `workPacketPath` whose packet has `remediation.ciFailures` of length ≥ 1; a second POST enqueues **nothing** (idempotent on `u1`); a summary at the cap enqueues nothing and reads `blocked`. Predicted red: `remediationsEnqueued` absent from the response.

**Roadmap write-back:** append `; H38-31 the reconcile tick enqueues one remediation per failing CI run, idempotent on the Actions run URL, cap checked first, target from dispatch.defaultTarget`.

**Stop if:** the smoke's isolated queue (`REPO_MGMT_QUEUE_PATH`) is not the path `New-RoadmapQueueEntry`'s caller writes to in the host (report the resolver used).

---

### H38-32 — Milestone 5 closing; Lane 0.18 write-backs

**Roadmap item:** M5 state clause; Lane 0.18 items `Carry an amendment forward between dispatches` and `Cap cumulative spend across a dispatch sequence` (both re-scoped into 3.8 by the roadmap).

**Scope (edit only):** `docs/reference/local-task-runner.md`; `ROADMAP.md`.

**Steps**

1. Combined green run.
2. `local-task-runner.md`: subsection `## Remediation and handoff (Release 3.8 M5)`, at most 15 lines.

**Roadmap write-back:**

- M5 state word → `smoke-tested <date>`.
- Lane 0.18 carryover item: `_(state: planned)_` → `_(state: smoke-tested <date> — delivered as Release 3.8 H38-30: HandoffPacket.priorResult and remainingScope carry the prior run's evidence into the next prompt; a repository with no prior run renders the H38-05 prompt unchanged)_`.
- Lane 0.18 cumulative-cap item: `_(state: planned)_` → `_(state: smoke-tested <date> — delivered as Release 3.8 H38-09/H38-27: per-provider reserves in agent-providers.json and a remediation cap persisted before the halt; the work-unit quota in BudgetLedger.ps1 is unchanged)_`.

**Stop if:** either Lane 0.18 item's text no longer matches (someone edited it) — report rather than guess which item.

---

### H38-33 — Canonical `execution.*` events

**Roadmap item:** Release 3.8 M6, `Normalize execution events onto the Dispatch Board.` ("Provider output converts to the canonical `execution.*` vocabulary"). Spec: *Canonical execution events* (the 14 types; the 7 minimum fields).

**Prerequisites:** H38-04, H38-15.

**Scope (edit only):** new `backend/modules/execution/Execution.Events.ps1`; `backend/modules/agent-adapters/Adapter.Claude.ps1`, `Adapter.Codex.ps1`, `Adapter.Copilot.ps1` (`ConvertTo-<P>CanonicalEvent` bodies); `scripts/Invoke-RoadmapTaskRunner.ps1` (dot-source `AgentRuns.ps1` so `Write-AgentRunEvent` exists in the runner; emit at the five points below); host dot-source line; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `$script:ExecutionEventTypes` = the spec's 14 strings exactly. `Write-ExecutionEvent -WorkspaceRoot -Type -TaskId -ExecutionId -Provider -ProviderSessionId -Data` → validates `Type` (throw `Unknown execution event type '<x>'. Allowed: …`) and the four ids (throw `<name> is required` for `TaskId`, `ExecutionId`, `Provider`; `ProviderSessionId` may be `$null`), then calls `Write-AgentRunEvent -EventType $Type -RunId $TaskId -Data ([ordered]@{ executionId; provider; providerSessionId; payload = $Data })`. `eventId` and `timestamp` come from `Write-AgentRunEvent` (the spec's minimum fields are all present: eventId, taskId=runId, executionId, provider, providerSessionId, timestamp, type=eventType).
2. Adapters: `ConvertTo-ClaudeCanonicalEvent -Parsed` → for the fixture's event kinds: the first parsed object → `execution.started`; any object with a `type` of `assistant` → `execution.progress`; the `result` object → `execution.completed` (or `execution.failed` when `is_error`, or `execution.capacity.exhausted` when the limit signal matched); `execution.usage` from the result's `usage`. Codex: the same by the constants from H38-16. Copilot: `execution.queued` at dispatch only.
3. Runner emission points: claim → `execution.queued` is **not** emitted by the runner (dispatch does that in the host: add one `Write-ExecutionEvent -Type execution.queued` in the dispatch route with `ExecutionId = $runId`, `Provider = <token>`); runner: after launch → replay the adapter's canonical events; after verify → `execution.verification.started`/`completed`; capacity wait → `execution.capacity.exhausted` (H38-10's placeholder becomes real); cancel path (none in 3.8) — do not emit `execution.cancelled`.

**Gate (red first) — module smoke, new section `Write-Step 'Execution events — smoke: canonical vocabulary, minimum fields, offline'`:**

- `Write-ExecutionEvent` with `Type 'execution.bogus'` throws the exact message. Predicted red: `The term 'Write-ExecutionEvent' is not recognized …`.
- A valid write into a temp workspace appends one line to `output\agent-runs\events.jsonl` whose JSON has `eventId`, `runId`, `eventType`, `timestamp`, and `data.executionId`, `data.provider`, `data.providerSessionId` (null allowed) — seven fields checked by name on the raw JSON.
- Claude fixture → canonical events include `execution.started`, at least one `execution.progress`, exactly one `execution.completed`, and one `execution.usage`; the synthetic limit fixture → exactly one `execution.capacity.exhausted`.
- Every emitted type is in `$script:ExecutionEventTypes`.

**Roadmap write-back:** M6 `_(state: planned)_` → `_(state: scaffolded <date> — H38-33 Execution.Events.ps1 writes the spec's 14 execution.* types onto output/agent-runs/events.jsonl with the seven minimum fields; adapters emit canonical events from recorded fixtures)_`.

**Stop if:** dot-sourcing `AgentRuns.ps1` in the runner pulls in a dependency that fails under `-LoadFunctionsOnly` (report the error text).

---

### H38-34 — Vocabulary reconciliation: sixth dimension, glossary, events doc

**Roadmap item:** M6 ("reconciled with `roadmap-events.md` so exactly one is canonical. New states arrive as a mapped dimension in `status-vocabulary.md`, keeping the Release 3.5 rule that no two dimensions share a word"). Spec: *Revised delivery state machine*.

**Prerequisites:** H38-33.

**Scope (edit only):** `docs/reference/status-vocabulary.md`; `frontend/lib/glossary.ts`; `frontend/lib/glossary.test.ts`; `frontend/types.ts` (one new union `DeliveryState`); `standards/roadmap/roadmap-events.md` **and** `spec/roadmap-contract/roadmap-events.md` (identical edits — the module smoke's sync gate compares them); `ROADMAP.md`.

**Steps**

1. `status-vocabulary.md`: add a sixth row to the five-dimension table, dimension **Delivery state**, Values = the spec's states as backticked lower-kebab tokens in spec order from `queued` through `complete` (21 tokens: `queued`, `capacity-evaluating`, `capacity-wait`, `provider-selected`, `workspace-preparing`, `agent-running`, `local-verifying`, `remediation`, `implementation-complete`, `pushing`, `pr-open`, `ci-pending`, `ci-failed`, `ci-passed`, `ready-for-operator`, `operator-approved`, `merging`, `merged`, `post-merge-verifying`, `post-merge-remediation`, `complete`), Source = `run summary status + agent-run record (Release 3.8)`, Where it renders = `Dispatch Board lane detail`. Below the table add one paragraph: the spec's `DISCOVERED`, `FORMING`, `QUALIFIED` are not per-task states — they are the *Dispatch readiness* dimension — and `complete` is shared with *Execution lane*, so its display term is qualified. Rename the heading `## The five dimensions` → `## The six dimensions` and update the sentence that says "five".
2. `glossary.test.ts`: the `toEqual([...])` list of dimension names gains `'Delivery state'` as its sixth entry (this is the only test edit; it is the parser non-vacuity guard, and it must know the new count).
3. `glossary.ts`: a new group `delivery-state` with 21 terms, each `token` = the machine value, `term` = the display term **from the table below, verbatim**, `definition` one sentence from the spec, `basis` = `Read from the run summary and agent-run record; never inferred from a button press`. Type it as `Record<DeliveryState, GlossaryTerm>` so a missing member is a compile error. The table pre-resolves every collision so no display term is improvised. Two tests bite here: `never shows the same display term twice` (any term equal to an existing one, e.g. `Running`, `Complete`, `Merged`, fails) and `disambiguates values that two dimensions share` (a token that already exists in another group needs a qualified term). Collisions checked 2026-09-06 against `glossary.ts` (existing terms) and the rest of the codebase (same word, other meaning):

   | Token | Display term | Collides with |
   | --- | --- | --- |
   | `queued` | `Queued (delivery)` | the lane-observation verdict `queued` in `Execution.LaneObservation.ps1` (board label `Queued`), the queue-entry and run-summary status `queued` — qualify |
   | `capacity-evaluating` | `Evaluating capacity` | — |
   | `capacity-wait` | `Waiting for capacity` | H38-35's `verdictLabel` uses the same words for the same fact; a verdict label is not a glossary term, so no test collision |
   | `provider-selected` | `Provider selected` | — |
   | `workspace-preparing` | `Preparing workspace` | — |
   | `agent-running` | `Agent running` | Execution lane `running` / `Running` is a different token; the term must not be plain `Running` |
   | `local-verifying` | `Verifying locally` | — |
   | `remediation` | `Remediating` | — |
   | `implementation-complete` | `Implementation complete` | must not be plain `Complete` |
   | `pushing` | `Pushing` | — |
   | `pr-open` | `PR open` | the existing portfolio term `PRs` is a different term; the agent-run `prState = 'open'` is not a glossary token |
   | `ci-pending` | `CI pending` | — |
   | `ci-failed` | `CI failed` | — |
   | `ci-passed` | `CI passed` | — |
   | `ready-for-operator` | `Ready for operator` | `ready` (Dispatch readiness, Execution lane) is a different token; the term must not begin with `Ready (` |
   | `operator-approved` | `Operator approved` | — |
   | `merging` | `Merging` | — |
   | `merged` | `Merged (delivery)` | the agent-run outcome `merged` and `prState = 'merged'` (board verdict `finished`, label `Finished`); not a glossary token today, qualified anyway so the word is not shared |
   | `post-merge-verifying` | `Verifying after merge` | — |
   | `post-merge-remediation` | `Remediating after merge` | — |
   | `complete` | `Complete (delivery)` | Execution lane `complete` / `Complete` — the one true shared token; the qualified term is what the share test requires |

   If the `never shows the same display term twice` test still fails after this table, the colliding term is one added after 2026-09-06: report it, qualify the **delivery-state** side with `(delivery)`, and do not rename the other group's term.
4. `types.ts`: `export type DeliveryState = 'queued' | … | 'complete';` (21 members).
5. `roadmap-events.md` (both copies): append a section `## Relationship to Repo Manager execution events` of at most 12 lines: `execution.*` events are Repo Manager-internal, written to its own append-only stream, and are **canonical** for orchestration; a managed repository's `roadmap-events.jsonl` stays optional and MAY receive a derived `lifecycle` event (`state: completed`) when a task reaches `merged`; it is never written by a provider adapter. Add `actor` example `agent:codex` beside the existing `agent:claude-code`.

**Gate (red first):**

- `npm run test:unit`: `glossary.test.ts` fails first on the dimension list (`expected 6 rows, got 5` or the `toEqual` mismatch), then, after the doc edit, on `documents every Delivery state value` with 21 missing tokens; green after the group lands. `never shows the same display term twice` and `disambiguates values that two dimensions share` stay green throughout because the step 3 table pre-qualified `queued`, `merged` and `complete`.
- `npm run typecheck`: `Record<DeliveryState, …>` complete.
- Module smoke: the `standards/roadmap and spec/roadmap-contract stay in sync` step is green (both copies edited identically).
- `pwsh ./tools/Test-RoadmapStructure.ps1 -Path ./ROADMAP.md` exits 0.

**Roadmap write-back:** append `; H38-34 Delivery state is the sixth vocabulary dimension (21 tokens, glossary-typed); roadmap-events.md names the agent-runs stream canonical`.

**Stop if:** `glossary.test.ts` asserts the dimension count anywhere other than the one `toEqual` list (report the second site); or the sync gate names a third copy of `roadmap-events.md`.

---

### H38-35 — Dispatch Board: provider, capacity, reason; capacity wait is not stalled

**Roadmap item:** M6 ("Per D-008 this is the one surface that dispatches"). Spec: *Governor objective* ("An idle worker is preferable to consuming scarce provider capacity"), *Capacity sources* (`CAPACITY_EXHAUSTED → QUEUED`).

**Prerequisites:** H38-19, H38-12, **H-07** (the board is the only dispatching surface).

**Scope (edit only):** `backend/modules/execution/Execution.LaneObservation.ps1`; `backend/modules/execution/Execution.Ledger.ps1` (`Get-ExecutionQueueSummary` only, to attach provider data); `frontend/services/apiClient.ts` (`getProviders()`); `frontend/components/ExecutionQueuePanel.tsx` (+ test); `frontend/components/CopilotTaskPreviewModal.tsx` (the `intendedProvider` value only); `frontend/types.ts`; `scripts/Invoke-ModuleSmokeTest.ps1`; `ROADMAP.md`.

**Steps**

1. `Resolve-LaneObservation`: read `capacityWait` from `RunSummary`; when present and `resetAt` is in the future relative to `NowUtc`: verdict stays `queued`, `stalled = $false`, `stalledAfterMinutes = $null`, `verdictLabel = 'Waiting for capacity'`, `verdictDetail = "<provider> is at its limit; resets <resetAt>. Not stuck — the task re-queued itself."`; add `capacityWait` (the object) and `selectedProvider`, `selectionReason` (from the summary) to the returned object; `sources` unchanged. When `resetAt` is past, today's patience rules apply unchanged.
2. `Get-ExecutionQueueSummary`: attach `providers` = the `GET /api/providers` payload's `data.providers` (call the same functions, not the route) so the board makes one request.
3. Frontend: `ExecutionLaneObservation` gains `capacityWait?`, `selectedProvider?`, `selectionReason?: string[]` (normalize to `[]` at the client boundary); the lane card shows `Provider: <token>` and, when `selectionReason` is non-empty, a `text-sm` disclosure `Why this provider` listing the reasons; a capacity wait renders the label above with **no** stalled styling; the panel header shows one `text-sm` line per provider: `<name>: <verdict.reason>` from `providers`. The preview modal's `intendedProvider` = `'auto'` unless the operator picked a provider in a new `select` with the four tokens (D-008: the board is where the choice is made); the selected token is sent as `dispatchTarget` through `executeRoadmapDispatch`.

**Gate (red first):**

- Module smoke, extend the lane-observation decision table: summary `{ status='queued'; capacityWait=@{ provider='claude'; resetAt=<now+1h> } }` assigned 40 minutes ago → `stalled = $false`, label `Waiting for capacity`. Predicted red: `stalled = $true` (today's 15-minute patience). Same with `resetAt` one hour in the past → `stalled = $true` (golden for expired waits).
- Vitest, `ExecutionQueuePanel.test.tsx`: a lane with `selectionReason = ['eligible', 'selected claude']` shows the disclosure; a capacity-wait lane shows the label and no stalled marker; the provider header renders three lines; the preview `select` sends `dispatchTarget: 'codex'` when chosen (mock `executeRoadmapDispatch`). Predicted red: elements not found.
- `sources`, `selectionReason` and `providers` serialize as `[]`, never `null` — raw-JSON assertion in the module smoke.

**Roadmap write-back:** append `; H38-35 the board shows provider, capacity verdict and selection reason; a capacity wait is labelled and never stalled; the provider choice is made on the board (D-008)`.

**Stop if:** H-07 has not landed (the modal still dispatches from three surfaces) — the provider `select` would then be reachable from surfaces D-008 forbids; report and do steps 1–2 only.

---

### H38-36 — Milestone 6 closing; Release 3.8 acceptance audit

**Roadmap item:** M6 state clause; Release 3.8 *Acceptance criteria* (five bullets).

**Scope (edit only):** `docs/product/delivery-loop.md`; `docs/reference/local-task-runner.md`; `ROADMAP.md`.

**Steps**

1. Combined green run of every gate (module smoke, api-host smoke on 7171, `npm run typecheck`, `npm run lint`, `npm run test:unit`, both roadmap tools).
2. For each of the five acceptance criteria, write in the report the packet id and the smoke section name that asserts it: (1) provider-neutral contract → H38-01/H38-05; (2) hard limit not dispatched, re-queue, resume after reset → H38-09/H38-10/H38-11; (3) native units, no invented conversion, restart survival of attempt/session/cooldown/verified SHA → H38-08/H38-12/H38-27/H38-23; (4) selection reason, provider/session/usage recorded → H38-17/H38-04; (5) approval names a verified SHA, drift invalidates → H38-23/H38-24. If any criterion has no asserting section, stop — that is a missing packet, not a doc gap.
3. `delivery-loop.md` addendum: append a final paragraph `Landed <date>` listing the six milestones' closing packets.

**Roadmap write-back:** M6 state word → `smoke-tested <date>`. Do **not** change the release `**Status:**` line — `validation` and `done` are the operator's, after live proof.

**Stop if:** step 2 finds an unasserted criterion.

---

## Paths not found

Every path named above was checked with `Test-Path` on 2026-09-06. Paths that
do **not** exist yet and are **created by a packet** (so their absence is
expected): `backend/config/agent-providers.json` (H38-07),
`backend/config/execution-result.schema.json` (H38-16),
`backend/modules/agent-adapters/` and its three files (H38-04, H38-15, H38-16),
`backend/modules/execution/Execution.WorkPacket.ps1` (H38-01),
`Execution.ProviderRegistry.ps1` (H38-07), `Execution.ProviderCapacity.ps1`
(H38-08), `Execution.ProviderRouter.ps1` (H38-17), `Execution.Handoff.ps1`
(H38-28), `Execution.Events.ps1` (H38-33), `tests/fixtures/providers/` and its
synthetic transcripts (authored by the packet that needs each, R12),
`output/work-packets/` and
`output/provider-capacity/` (runtime, gitignored).

Paths named that exist today but whose **internal target** must be discovered
by the packet (an exact-match rule is given in the packet): the host's Actions
run object passed to `Invoke-AgentRunRefresh` (H38-23), the component calling
`executeMergeReadinessMerge` (H38-25), the bare-remote fixture in the module
smoke (H38-21), the `PrDetail` construction site (H38-24).

No path named in this file was found missing without a creating packet.

---

## 3. Not rendered — and why

| Release 3.8 / Lane 0.18 element | Reason | Who closes it |
| --- | --- | --- |
| Spec *Architectural responsibilities*: **isolated worktree** per task | Not claimed by any 3.8 milestone. The runner branches inside the operator's clone, and Lane 0.12's canonical-checkout logic and the runner's "repo vanished mid-run" guard both assume that. Changing it is a design decision about workspace ownership. | Ben — a decision entry, then a packet |
| Spec *Revised delivery state machine*: `POST_MERGE_VERIFYING`, `POST_MERGE_REMEDIATION` | No 3.8 milestone names post-merge verification; `Invoke-AgentRunRefresh` reads Actions for the PR branch, not for the default branch after merge. The vocabulary carries the tokens (H38-34) so the surface is honest about the gap. | A later release, or a 3.8 amendment |
| Spec *Claude Code adapter*: "Allowed and denied tools MUST be derived from the WorkPacket permission envelope"; *Codex adapter* sandbox mapping beyond `workspace-write` | Waits on D-012 (the envelope's contents and whether workflow files are editable). H38-05 and H38-16 carry the packet fields and say enforcement is pending. | Ben answers D-012 → one packet per adapter |
| Spec *GitHub Copilot adapter*: record "GitHub task identifier, issue identifier, agent session"; account for the account's **billing mode** | The runner records only the task URL (`Get-AgentTaskUrlFromOutput`); `gh agent-task create` output carries no other identifier in the recorded shape, and billing mode is D-014. `GET /api/providers` reports Copilot as unmeasured until then. | Ben answers D-014; a packet once `gh agent-task` output is recorded as a fixture |
| Spec *Capacity sources* ranks 1–2 (provider-supported machine-readable status; CLI account status) for Claude and Codex | No fixture shows either CLI exposing remaining allowance. H38-12 implements rank 3 conservatively against the recorded fixture and records rank 4 (usage) without inventing a ratio. | Operator: record `claude`/`codex` account-status output if such a command exists → packet |
| Lane 0.18 **acceptance-criteria check before a PR is called ready** (`Test-PhaseGate` port) | The check is a model-driven read-only pass — it needs a live model, which R12 forbids. H38-30 leaves `remainingScope` = all criteria and says so. | Fable-class pass with a live model, or an operator-recorded judge transcript as fixture |
| Lane 0.18 **dependency-aware selection** (`Get-NextEligibleRoadmapItem`) | Rendered in the companion file as H-13a/H-13b; H38-17 consumes it. | `HAIKU-WORK-PACKETS.md` |
| Release 3.8 `**Status:**` promotion to `validation` / `done`; operator verification on the live portal | No agent may claim live proof. | Operator |
| Spec *MVP concurrency*: raising concurrency above one local slot | Out of scope by the roadmap; `Test-AgentProviderConfig` refuses `localExecutionSlots ≠ 1` until the roadmap changes. | A later release |
| Codex adapter and Codex resume when D-015 is no | The packets exist (H38-16, H38-29 Codex half) and stop on the decision. | Ben answers D-015 |

---

## 4. Maintaining this file

- When a packet lands, delete it from §2 and remove its row from §1; the
  milestone's state clause is the record.
- When Ben answers a §B decision, move it to **Decided** in
  `open-decisions.md`, then edit every packet that lists it under **Stop if**
  to remove the stop and, where the default was provisional, flip the config
  flag in the packet's steps.
- When Ben vetoes a §A decision, rewrite the packets in its right-hand column
  before handing any of them to Haiku.
- If Haiku reports a *Stop if* three times on the same packet, the packet is
  under-specified, not the model. Rewrite the packet.

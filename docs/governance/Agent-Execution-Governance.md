# Agent Execution Governance

## Status

Design specification for the provider-aware execution layer.

This document governs how GitHub Repo Manager dispatches well-formed work to coding agents, manages provider capacity and subscription limits, receives execution results, resumes or transfers work, and returns control to the delivery loop.

`delivery-loop.md` remains authoritative for repository lifecycle and promotion state.

**Amended 2026-09-08.** Ben's *Multi-Provider Agent Execution Strategy* was
absorbed into this document rather than kept beside it: it covered the same
subject, and a second authority would have made the packet rule "where the
spec and the roadmap differ, the spec wins" unresolvable — an agent facing a
three-way disagreement has no tiebreak. The sections it added are *Task
classification*, *Execution tiers*, *Provider and model*, *Effective cost*,
*Historical performance*, *Adaptive routing*, *Independent review*,
*Confidence*, *Parallel execution*, and the acceptance criteria at the end.

Three of its claims were corrected by what Release 3.8 actually built, and the
corrected form is what appears below: routing resolves at **claim** time
rather than dispatch time, because the host holds no provider credential;
**supported** and **available** are different facts, one a repository property
and one per-installation; and an effective-cost model **cannot enforce**
anything until consumption has been measured.

## Core invariant

**The work contract is provider-neutral. The scheduler is provider-aware.**

A roadmap task MUST NOT contain provider-specific execution assumptions unless the task genuinely requires a provider-specific capability.

The Orchestrator MUST understand the differences between Codex, Claude Code, and GitHub Copilot when deciding:

- whether a provider is currently eligible;
- whether sufficient provider capacity remains;
- whether a new session should be started;
- whether an existing session should be resumed;
- whether work should be delayed;
- whether work should move to another provider;
- how execution events and usage are collected;
- what permissions the provider receives.

Provider neutrality applies to the **task contract**.

Provider awareness applies to **dispatch and execution**.

---

# Architectural responsibilities

```text
ROADMAP / TASK SYSTEM
        │
        │ WellFormedTask
        ▼
┌─────────────────────────┐
│ EXECUTION ORCHESTRATOR  │
│                         │
│ Strategy                │
│ Capacity Governor       │
│ Provider Router         │
└────────────┬────────────┘
             │
             │ DispatchDecision
             ▼
┌─────────────────────────┐
│ PROVIDER ADAPTER        │
│                         │
│ Codex                   │
│ Claude Code             │
│ GitHub Copilot          │
└────────────┬────────────┘
             │
             │ execution events
             ▼
┌─────────────────────────┐
│ TASK WORKSPACE          │
│                         │
│ isolated worktree       │
│ branch                  │
│ implementation          │
│ local verification      │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ GITHUB CONTROL PLANE    │
│                         │
│ commit / push           │
│ PR                      │
│ CI monitoring           │
│ merge readiness         │
└────────────┬────────────┘
             │
             ▼
      READY_FOR_OPERATOR
             │
             ▼
       human approval
             │
             ▼
            main
```

The coding agent is an execution worker.

The coding agent MUST NOT become the system of record for task state, provider capacity, GitHub CI state, or promotion state.

GitHub Repo Manager owns those concerns.

---

# Canonical task contract

Every provider receives the same logical `WorkPacket`.

Example:

```json
{
  "schemaVersion": 1,
  "taskId": "RM-1842",
  "repository": "xfaith4/GitHubRepoManagement",
  "baseBranch": "main",
  "baseSha": "7f21c62",
  "objective": "Implement provider-aware agent capacity management.",
  "scope": {
    "allowedPaths": [
      "backend/**",
      "scripts/**",
      "tests/**"
    ],
    "forbiddenPaths": [
      ".github/workflows/**"
    ]
  },
  "acceptanceCriteria": [
    "Provider capacity is persisted independently per provider.",
    "A provider at hard limit is not dispatched.",
    "Capacity exhaustion does not fail the roadmap task.",
    "The task can be resumed after capacity resets."
  ],
  "verification": {
    "commands": [
      "scripts/Invoke-TestSuite.ps1"
    ]
  },
  "permissions": {
    "filesystemWrite": true,
    "shell": true,
    "network": false,
    "githubWrite": false
  },
  "execution": {
    "attempt": 1,
    "preferredProvider": "auto",
    "previousSessionId": null
  }
}
```

The WorkPacket MUST be persisted outside files eligible for commit unless explicitly required by the task.

The provider adapter MAY translate the WorkPacket into provider-specific prompting, but MUST NOT change its objective, scope, acceptance criteria, or permission envelope.

---

# Task classification

Every task MUST carry a profile before dispatch. Routing reads the profile;
it does not re-derive it per provider.

```text
taskType
complexity              LOW | MEDIUM | HIGH
risk                    LOW | MEDIUM | HIGH
contextScope
expectedOutput
verificationAvailable
githubInteractionRequired
codeChangeRequired
reasoningRequired
estimatedContextSize
```

`taskType` is one of:

| Type | Covers |
| --- | --- |
| `CODE_SMALL` | Isolated fix, added test, config change, bounded rename, small UI change, lint/type correction |
| `CODE_COMPLEX` | Multi-file implementation, architectural refactor, concurrency or state defects, cross-module behaviour, migration, work whose files are initially unknown |
| `CODE_REMEDIATION` | A previous implementation failed tests, lint, build, security validation, CI, or acceptance criteria |
| `REPOSITORY_ANALYSIS` | Locating an implementation, tracing behaviour, identifying debt, roadmap qualification, root-cause investigation |
| `GITHUB_COMMUNICATION` | Issues, PR descriptions, review summaries, commit summaries, release notes, comment responses |
| `DOCUMENTATION` | README, ROADMAP, architecture docs, SECURITY.md, CONTRIBUTING.md, decision records |
| `PROMPT_OR_AGENT_REFINEMENT` | Agent instructions, skill files, system prompts, task contracts, acceptance criteria |
| `REVIEW` | Implementation, architectural or security review; verification of another agent's work |

Classification MUST NOT be a restatement of a provider preference. A profile
that is derived from the requested provider explains nothing and cannot
override a cold-start prior.

---

# Execution tiers

Capability is chosen before a provider is. The cheapest tier expected to
succeed is used first, and escalation MUST increase capability rather than
repeat the same request more expensively.

| Tier | Name | Use |
| --- | --- | --- |
| 0 | Deterministic | Any answer application logic, Git, the GitHub API, or schema validation can produce |
| 1 | Economical agent | Bounded changes, GitHub communication, formatting, basic documentation, obvious tests, well-specified implementation |
| 2 | Advanced agent | Multi-file coding, debugging, architectural reasoning, unclear implementation paths, failed Tier 1 |
| 3 | Frontier reasoning | High complexity or consequence, repeated lower-tier failure, architectural uncertainty, security-sensitive reasoning, unusually tangled context |

## Tier 0 is a routing outcome, not an absence of routing

`NO_AGENT` is a first-class selection result and MUST be recorded like any
other. Branch state, CI status, file existence, repository metrics, schema
validation, test execution, value comparison, branch creation from known
inputs, label application, mergeability, and configured policy evaluation are
all deterministic. Spending a provider turn on them is the most expensive way
to obtain an answer the repository already has.

---

# Provider and model

Provider choice and model choice are separate decisions wherever a provider
exposes model selection. A provider is an execution channel with an adapter,
a credential and a capacity envelope; a model is a capability and price point
inside it.

Collapsing the two makes "use a cheaper model on the same provider"
unexpressible, which is the most common way to reduce cost without losing a
task class. Telemetry, capacity records and routing records therefore all key
on `provider × model`, and a provider with one model records it explicitly
rather than leaving the field absent.

---

# Provider capacity model

Capacity MUST NOT be represented by one universal `tokensRemaining` value.

Each provider has one or more native capacity windows.

The normalized contract is:

```json
{
  "provider": "codex",
  "available": true,
  "observedAt": "2026-09-06T19:00:00Z",
  "activeExecutions": 0,
  "windows": [
    {
      "name": "short-term",
      "unit": "provider-allowance",
      "remainingRatio": 0.61,
      "resetAt": "2026-09-06T23:10:00Z",
      "source": "provider-status",
      "confidence": "high"
    },
    {
      "name": "weekly",
      "unit": "provider-allowance",
      "remainingRatio": 0.43,
      "resetAt": "2026-09-10T14:00:00Z",
      "source": "provider-status",
      "confidence": "high"
    }
  ],
  "cooldownUntil": null
}
```

Supported capacity units MAY include:

```text
provider-allowance
tokens
ai-credits
premium-requests
currency
unknown
```

The Governor MUST preserve the provider's native unit.

It MUST NOT invent a token conversion for a subscription allowance that the provider does not expose as tokens.

Actual execution token telemetry and subscription capacity are separate measurements.

---

# Capacity sources

Capacity observations are ranked by confidence:

```text
1. Provider-supported machine-readable status
2. Provider CLI/account status
3. Provider-reported warning or remaining percentage
4. Usage accumulated from completed executions
5. Observed rate-limit response and reset time
6. Historical estimate
```

A provider limit response is state, not an execution failure.

For example:

```text
AGENT_RUNNING
     │
     ├── implementation failure → AGENT_FAILED
     │
     └── provider limit reached → CAPACITY_EXHAUSTED
                                      │
                                      ▼
                                    QUEUED
```

The latter MUST preserve the task, workspace, branch, attempt, session identifier, and provider context.

---

# Capacity reserves

Ordinary roadmap work MUST NOT intentionally exhaust a provider.

Initial policy:

```text
Short-window reserve:       15%
Weekly reserve:             20%
Remediation reserve:        included inside the weekly reserve
```

These percentages are configuration, not hard-coded constants.

Normal implementation work cannot consume the reserve.

Remediation of already-started work MAY consume the reserve.

An operator MAY explicitly override a reserve.

The system learns actual consumption per task and provider and improves estimates over time.

---

# Provider selection

Provider selection has two stages.

## Selection resolves at claim time, not dispatch time

`auto` is resolved by the **runner**, when it claims the task — not by the
host when it enqueues one.

The host runs as a LocalSystem service and holds no provider credential, so it
cannot answer "is this provider eligible here": authentication and local
capacity are visible only in the operator session. Capacity and cooldowns also
move between enqueue and claim, so a decision made at dispatch can be stale
before the work starts.

The host MAY record a `provisionalSelection` for a board to display. The
binding decision, its `selectedProvider` and its `selectionReason` are written
by the runner onto the run summary.

## Supported and available are different facts

`supported` means *this build contains a conforming adapter*. It is a property
of the repository, identical for everyone, and CI can verify it.

Whether the CLI is installed, and whether the operator has switched the
provider off, are **per-installation** facts detected at runtime. They MUST
NOT be committed: a repository that records "this operator has no Codex"
asserts one machine's state on behalf of every installation, and no gate can
check it because CI has never seen that machine.

A provider is a routing candidate only when it is `supported`, detected as
available, and not opted out.

**Availability detection never authenticates.** The probe answers *is the CLI
present*, which costs nothing. Running the tool to prove the account works
would spend the very quota this layer exists to conserve, so authentication is
learned from the first real run — an auth failure is a cheap, distinguishable
outcome. Until then a provider reports `authenticated: "unknown"`, which is
honest rather than absent.

## Stage 1 — eligibility

A provider is eligible only when:

```text
provider enabled
AND authentication valid
AND required capabilities supported
AND provider not cooling down
AND concurrency slot available
AND task estimated to fit available capacity
AND required permissions are compatible
```

If no provider is eligible:

```text
QUEUED
   ↓
CAPACITY_WAIT
```

The task is not failed.

## Stage 2 — ranking

Eligible providers are ranked using:

```text
task suitability
+ remaining usable capacity
+ historical success for similar tasks
+ likelihood task fits current window
+ session reuse value
+ time until capacity reset
- estimated capacity consumption
- recent failure rate
```

The exact scoring weights are configuration.

Provider selection MUST be recorded with its reason.

Example:

```json
{
  "selected": "codex",
  "reason": [
    "eligible",
    "72% short-window usable capacity",
    "existing successful history for PowerShell task",
    "Claude weekly reserve protected",
    "Copilot credits preserved"
  ]
}
```

---

# Default routing policy

For ordinary local implementation:

```text
Codex OR Claude Code
        │
        ▼
choose using capacity + suitability
```

Neither provider is globally preferred.

GitHub Copilot is preferred when work specifically benefits from GitHub-hosted execution or GitHub-native agent behavior.

Copilot can also serve as overflow when local subscription capacity is constrained.

For remediation:

```text
CI failure
    │
    ▼
original provider session available?
    │
    ├── YES + capacity available
    │       ↓
    │     resume original session
    │
    └── NO
            ↓
       construct HandoffPacket
            ↓
       route to another eligible provider
```

A provider switch MUST start a new provider session.

Context MUST be transferred through structured evidence, not by pretending the second provider has access to the first provider's conversation.

---

# Effective cost

Routing compares an effective cost, not a list price:

```text
effective_cost =
    estimated_metered_cost
  + quota_pressure_cost
  + retry_cost
  + expected_failure_cost
```

Subscription capacity is not free. As remaining allowance becomes scarce its
shadow cost rises, so one provider cannot spend its month on trivial work.
Abundant capacity lowers a provider's effective cost; a nearly exhausted
window raises it; metered usage contributes its actual estimated token cost.

Provider pricing MUST NOT be hard-coded where it can be discovered or
configured.

## Effective cost cannot be enforced before it is measured

A reserve can only refuse work if the cost of a task is known. Until observed
consumption exists, the per-task estimate is a guess, and refusing dispatches
on a guessed number blocks real execution for an unmeasured reason.

Capacity verdicts are therefore **computed and recorded while enforcing
nothing** until both the reserve values and the consumption estimate are
non-provisional. A wrong estimate must be able to look wrong without being
able to stop work.

---

# Historical performance

The Repo Manager learns which provider performs best for *its* workload, not
which benchmarks best. Every execution records at minimum:

```text
provider              model                 taskType
repository            complexity            risk
estimatedContextSize  startTime             completionTime
inputUsage            outputUsage           estimatedCost
attemptCount          verificationPassed    firstPassSuccess
remediationRequired   crossProviderEscalation
humanInterventionRequired                   humanChangesAfterAgent
ciResult              finalTaskResult
```

Rolling metrics derive from those records:

```text
firstPassSuccessRate      eventualSuccessRate
averageCostPerSuccess     averageDurationPerSuccess
averageRemediations       humanInterventionRate
ciFailureRate
```

They MUST be broken down by `provider × model × taskType × complexity`. A
global provider average hides the case this exists to find: a provider that is
excellent at documentation and poor at one coding workload, or the reverse.

---

# Adaptive routing

Cold-start preferences are priors, not specialisations. Once sufficient
history exists for a task class, empirical results override them.

A provider with a higher invocation cost but a higher first-pass rate can be
the cheaper route per *verified* task, and the router must be able to reach
that conclusion from evidence rather than have it asserted. The reverse holds
equally: a cheaper provider that succeeds first time should dominate its class.

---

# Independent review

Cross-provider review is bought by risk, not applied to everything. Its value
is an independent evaluation; its cost is a second provider turn.

| Risk | Review |
| --- | --- |
| Low — documentation typo, small test, simple GitHub communication | None. Repository verification suffices |
| Medium — ordinary feature, multi-file refactor, meaningful behaviour change | Required when automated verification is incomplete, the diff exceeds the configured threshold, the implementing agent reported low confidence, or architecture changed |
| High — authentication, authorization, secrets, destructive operations, execution orchestration, Git operations affecting repository state, security controls, data migration, foundational architecture | Required, by a provider other than the implementer |

The reviewer receives the requirements and the resulting diff. It MUST NOT
receive the implementer's reasoning transcript: a reviewer shown the original
chain of thought tends to ratify it, which is the opposite of an independent
evaluation.

---

# Confidence

An agent MAY report `confidence: HIGH | MEDIUM | LOW`.

Low confidence MUST NOT automatically trigger another execution. It raises the
likelihood of stronger verification, independent review, or escalation. A
low-confidence result that passes comprehensive deterministic verification is
worth more than an expensive second opinion, because the verification is
evidence and the second opinion is another claim.

---

# Parallel execution

Prefer parallelising **different independent tasks** over asking several
providers to perform the same one. Redundant first-pass generation multiplies
routine cost by the number of providers and is disabled by default.

Two providers on one task is justified for foundational architectural
decisions, genuinely ambiguous defects, high-risk security decisions,
competing implementation approaches, work that has already failed sequential
escalation, and blockers where wall-clock time outweighs token cost. Prefer
two, never three.

Independent tasks may execute concurrently across providers only where their
file sets do not overlap, unless conflict handling is explicitly supported.
Provider availability is a scheduling resource like any other.

---

# Provider adapters

All providers implement:

```text
IAgentExecutor

GetCapabilities()
GetCapacity()
StartExecution(WorkPacket)
ResumeExecution(SessionId, WorkPacket)
CancelExecution(ExecutionId)
NormalizeEvent(ProviderEvent)
GetResult(ExecutionId)
```

A provider adapter is responsible only for translating between Repo Manager's canonical contracts and the provider's native interface.

It does not make roadmap, merge, or portfolio-priority decisions.

---

# Codex adapter

Execution mode:

```text
local
```

Primary machine interface:

```text
codex exec
```

The adapter SHOULD use the provider's machine-readable event stream and structured final output.

Conceptually:

```text
codex exec
    --json
    --sandbox workspace-write
    --output-schema <ExecutionResult schema>
```

The adapter records the Codex thread/session identifier.

Usage events are normalized into Repo Manager usage records.

A completed Codex process releases its worker slot.

A later remediation may resume the session if it remains useful and capacity permits.

The adapter MUST NOT equate Codex token telemetry with remaining subscription allowance unless an authoritative provider interface explicitly provides that conversion.

---

# Claude Code adapter

Execution mode:

```text
local
```

Primary machine interface:

```text
claude -p
```

The adapter SHOULD use structured or streaming JSON output.

Conceptually:

```text
claude -p
    --output-format stream-json
    --max-turns <policy>
    --allowedTools <policy>
```

The adapter records `session_id`.

The adapter MAY resume a session using the provider's resume mechanism.

Allowed and denied tools MUST be derived from the WorkPacket permission envelope.

A Claude usage-limit response transitions the provider into cooldown/capacity-exhausted state rather than failing the roadmap task.

---

# GitHub Copilot adapter

Execution mode:

```text
GitHub-hosted
```

Copilot is asynchronous relative to the local process model.

The adapter dispatches through the supported GitHub agent/issue mechanism and records:

```text
GitHub task identifier
issue identifier where applicable
agent session
branch
pull request
head SHA
```

There is no requirement to keep a local process alive.

GitHub state is reconciled asynchronously by Repo Manager.

Copilot consumption is accounted for using the account's applicable GitHub billing mode.

The adapter MUST NOT assume every account uses the same billing generation; current AI-credit and legacy request-based modes are distinct capacity types.

---

# Canonical execution events

All provider-specific output is converted to Repo Manager events.

Minimum event vocabulary:

```text
execution.queued
execution.started
execution.progress
execution.command.started
execution.command.completed
execution.files.changed
execution.verification.started
execution.verification.completed
execution.usage
execution.capacity.warning
execution.capacity.exhausted
execution.completed
execution.failed
execution.cancelled
```

Every event contains at minimum:

```json
{
  "eventId": "...",
  "taskId": "RM-1842",
  "executionId": "...",
  "provider": "codex",
  "providerSessionId": "...",
  "timestamp": "...",
  "type": "execution.completed"
}
```

Provider-native event payloads MAY also be retained for diagnosis, but Mission Control consumes the normalized events.

---

# Canonical execution result

Every provider eventually produces:

```json
{
  "taskId": "RM-1842",
  "executionId": "EX-991",
  "provider": "codex",
  "providerSessionId": "...",
  "status": "implementation_complete",
  "changedFiles": [],
  "verification": {
    "passed": true,
    "commands": []
  },
  "usage": {
    "native": {},
    "tokensObserved": null
  },
  "risks": [],
  "operatorAttentionRequired": false,
  "summary": "..."
}
```

Free-form prose MUST NOT be the orchestration protocol.

Prose is evidence for humans.

Structured state drives automation.

---

# GitHub boundary

Local agents SHOULD NOT require GitHub write credentials.

Preferred authority boundary:

```text
Agent
  ├─ inspect
  ├─ edit
  ├─ build
  └─ test

Repo Manager
  ├─ inspect diff
  ├─ commit
  ├─ push branch
  ├─ create PR
  ├─ monitor CI
  ├─ reconcile PR state
  └─ execute approved merge
```

This keeps GitHub mutation semantics identical regardless of whether Codex or Claude produced the implementation.

Copilot is the exception because execution itself occurs through GitHub.

---

# CI ownership

Coding agents MUST NOT remain active merely to wait for CI.

After implementation:

```text
AGENT_RUNNING
      ↓
LOCAL_VERIFYING
      ↓
IMPLEMENTATION_COMPLETE
      ↓
agent exits
      ↓
PUSHING
      ↓
PR_OPEN
      ↓
CI_PENDING
```

Repo Manager monitors CI without consuming an AI execution slot.

If CI fails:

```text
CI_FAILED
    ↓
collect failure evidence
    ↓
build RemediationPacket
    ↓
Governor evaluates provider capacity
    ↓
resume or redispatch
```

---

# Remediation handoff

A cross-provider remediation receives a `HandoffPacket` containing only durable evidence:

```json
{
  "taskId": "RM-1842",
  "attempt": 2,
  "previousProvider": "codex",
  "objective": "...",
  "baseSha": "...",
  "headSha": "...",
  "changedFiles": [],
  "priorResult": {},
  "ciFailures": [],
  "acceptanceCriteria": [],
  "remainingScope": []
}
```

The new provider MUST NOT depend on hidden conversational history from the previous provider.

The repository plus the HandoffPacket must be sufficient to continue.

---

# Revised delivery state machine

```text
DISCOVERED
    ↓
FORMING
    ↓
QUALIFIED
    ↓
QUEUED
    ↓
CAPACITY_EVALUATING
    │
    ├── no provider available
    │       ↓
    │   CAPACITY_WAIT
    │       ↓
    │   CAPACITY_EVALUATING
    │
    ▼
PROVIDER_SELECTED
    ↓
WORKSPACE_PREPARING
    ↓
AGENT_RUNNING
    │
    ├── provider exhausted
    │       ↓
    │   CAPACITY_WAIT
    │
    ▼
LOCAL_VERIFYING
    │
    ├── FAIL → REMEDIATION
    │
    ▼
IMPLEMENTATION_COMPLETE
    ↓
PUSHING
    ↓
PR_OPEN
    ↓
CI_PENDING
    │
    ├── CI_FAILED
    │       ↓
    │   REMEDIATION
    │       ↓
    │   CAPACITY_EVALUATING
    │
    ▼
CI_PASSED
    ↓
READY_FOR_OPERATOR
    ↓
OPERATOR_APPROVED
    ↓
MERGING
    ↓
MERGED
    ↓
POST_MERGE_VERIFYING
    │
    ├── FAIL → POST_MERGE_REMEDIATION
    │
    ▼
COMPLETE
```

`CAPACITY_WAIT` is a normal operating state, not an error state.

---

# Promotion invariant

Agent execution may be autonomous.

Promotion is not.

A well-formed roadmap grants permission to prepare and execute work, but it does not grant permission to merge that work into the protected default branch.

The promotion boundary is:

```text
CI_PASSED
    ↓
READY_FOR_OPERATOR
    ↓
operator reviews exact verified head SHA
    ↓
OPERATOR_APPROVED
    ↓
MERGING
```

Approval applies to the verified commit SHA, not merely the pull request number.

Any change to the PR head after verification invalidates `READY_FOR_OPERATOR`.

---

# MVP concurrency

Start with:

```text
1 local execution slot
```

Codex and Claude compete for that slot.

Copilot may execute remotely, but the Governor still accounts for it as an active provider execution and applies portfolio concurrency policy.

Concurrency is increased only after provider capacity accounting, session persistence, CI reconciliation, and recovery after process restart are proven.

---

# Persistence requirements

The following state MUST survive a Repo Manager restart:

```text
task state
execution state
selected provider
provider session ID
provider task ID
workspace
branch
base SHA
head SHA
attempt count
capacity observations
cooldown/reset times
usage observations
CI state
remediation count
verified SHA
operator approval state
```

No retry counter, provider cooldown, or usage window may exist only in process memory.

---

# Governor objective

The Governor does not maximize agent utilization.

It maximizes useful completed work subject to:

```text
subscription capacity
task suitability
repository safety
verification quality
human promotion control
```

An idle worker is preferable to consuming scarce provider capacity on a poorly formed or low-value task.

The desired outcome is not:

"keep every agent busy."

It is:

"use the available providers at the times and frequencies that maximize verified roadmap progress without unexpectedly exhausting any subscription."

## The metric that decides between routes

```text
Verified Tasks Completed
------------------------
     Total Agent Cost
```

Throughput and quality are tracked beside it, never in place of it:

```text
Verified Tasks Completed          First-Pass Verified Tasks
------------------------          -------------------------
    Wall Clock Hour                 Total Executed Tasks
```

Cost per request is not the objective. A cheaper request that fails
verification and is remediated twice costs more than one that succeeds.

No provider is "best" by benchmark reputation, token price, or preference. The
best provider is the one producing the most verified value for this
repository's actual workload — which is a measurement, and therefore cannot be
settled in this document.

---

# Acceptance criteria

The provider-aware execution layer is complete when:

1. tasks are classified before AI dispatch;
2. deterministic tasks bypass AI completely;
3. all three providers implement a common adapter contract;
4. provider and model are separately represented where the provider allows it;
5. routing considers task class, complexity, risk, cost, latency, capability, quota and historical performance;
6. provider pricing and usage assumptions are configurable or dynamically discoverable rather than embedded in code;
7. one remediation attempt can remain with the original provider;
8. repeated failure can trigger cross-provider escalation;
9. high-risk tasks can require review by a different provider;
10. redundant multi-provider execution is off by default;
11. independent roadmap tasks may execute concurrently across providers;
12. every execution captures cost, duration, verification, retry and final-result telemetry;
13. routing decisions are persisted with an explanation;
14. historical success data can override cold-start provider preferences;
15. circuit breakers prevent an unavailable or exhausted provider from blocking the queue;
16. repository verification and delivery-state semantics remain the authority on completion.

Which release satisfies which criterion is recorded in `ROADMAP.md`, not here.
This document states the design; the roadmap states the schedule.

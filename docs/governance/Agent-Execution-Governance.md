# Agent Execution Governance

## Status

Design specification for the provider-aware execution layer.

This document governs how GitHub Repo Manager dispatches well-formed work to coding agents, manages provider capacity and subscription limits, receives execution results, resumes or transfers work, and returns control to the delivery loop.

`delivery-loop.md` remains authoritative for repository lifecycle and promotion state.

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
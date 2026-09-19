# CLAUDE.md — Claude Provider Overlay

**Revision:** governed execution alignment
**Applies to:** Claude-backed implementation sessions in this repository

This file is a provider-specific overlay for [`AGENTS.md`](./AGENTS.md). Read
`AGENTS.md` first. Its authority model, lifecycle, safety rules, and delivery
requirements remain controlling.

This overlay may narrow Claude's behavior or describe Claude-specific mechanics.
It may not widen the active mandate, permission envelope, repository policy, or
merge authority.

---

## 1. Claude's role

Claude is an implementation provider. Unless an active WorkPacket explicitly
assigns a narrower role, Claude may:

- inspect the repository and relevant documentation;
- modify files inside the authorized scope;
- run authorized local verification;
- record durable implementation evidence;
- update proposed documentation and roadmap state when that work is in scope;
- return a structured implementation result to the Repo Manager.

Claude does **not** independently own:

- roadmap priority or selection;
- provider selection;
- policy approval;
- pull-request approval;
- promotion or merge decisions;
- declaring a roadmap item complete;
- post-merge reconciliation.

Those responsibilities stay with the roles and lifecycle defined in
`AGENTS.md`, the active mandate, and the Repo Manager.

---

## 2. Required inputs

Before making a change, Claude must have either:

1. an active, validated WorkPacket; or
2. an explicit operator instruction issued under the supervised execution mode
   described in `AGENTS.md`.

A WorkPacket is immutable input for the session. Claude must respect, at
minimum:

- mandate ID and work-unit ID;
- repository, base branch, and expected head or baseline;
- objective and acceptance criteria;
- allowed and forbidden paths;
- command, tool, network, and secret permissions;
- required verification;
- stop conditions and escalation route.

If any required field is missing, contradictory, expired, or no longer matches
repository state, stop at a durable boundary and return `BLOCKED` with a
decision-ready explanation. Do not silently infer broader authority.

---

## 3. Settings and permission boundaries

`.claude/settings.json` defines the maximum repository-versioned capability
available to Claude. It is not an instruction to use every allowed capability.

`.claude/settings.local.json` is machine-local convenience state only. It must
not become a source of product policy, roadmap authority, or portable
permissions, and it must not be committed.

Effective permission is the intersection of:

1. repository policy;
2. the active mandate;
3. the WorkPacket permission envelope;
4. the current runtime's available capabilities.

Any layer may narrow permission. No lower-authority layer may widen it.

---

## 4. Execution behavior

Claude must:

1. revalidate the mandate and repository baseline before the first mutation;
2. inspect relevant code, tests, and governing documents before editing;
3. keep changes inside the WorkPacket's scope and path constraints;
4. preserve unrelated user changes and avoid destructive recovery commands;
5. implement the smallest coherent change that satisfies the acceptance
   criteria;
6. run the required verification and record exact outcomes;
7. classify any failure before attempting remediation;
8. stop when the implementation result is durable and reportable.

Revalidate the mandate at meaningful phase boundaries, including before a new
mutation phase, after resuming, and before any externally visible action.

Claude must not treat a green local run, a green pull-request head, or a clean
working tree as merge authorization or proof of integrated completion.

---

## 5. Delivery boundary

Claude's normal terminal state is `IMPLEMENTATION_COMPLETE`, not `COMPLETE`.

At `IMPLEMENTATION_COMPLETE`, Claude has:

- produced the authorized change;
- run all available required local checks;
- documented any unavailable or failing checks;
- captured the changed-file set and implementation evidence;
- identified remaining risks, decisions, or follow-up work;
- returned control to the Repo Manager.

The Repo Manager owns branch publication, pull-request creation or
reconciliation, CI observation, review routing, promotion, merge, post-merge
verification, and roadmap reconciliation. Claude must not push, open a pull
request, approve, or merge merely to manufacture a delivery boundary.

If a WorkPacket assigns a transport-only action, that action remains bounded by
the packet and does not confer approval, promotion, or merge authority.

---

## 6. Structured result

Write the result using the repository's versioned `ExecutionResult` schema and
validate it before returning. The schema's field names and enum values are
authoritative; never invent a parallel result shape in prose or provider
configuration.

The result must carry, directly or through schema-defined references:

- result status and lifecycle transition requested;
- mandate, work-unit, run, and provider-session identifiers;
- repository identity and validated base revision;
- resulting revision or explicit working-tree state;
- concise implementation or stop summary;
- exact changed paths;
- each verification command, outcome, and durable evidence reference;
- remaining risks and residual scope;
- decisions or permissions required;
- one concrete recommended next action.

Request `IMPLEMENTATION_COMPLETE` only when Section 5 is satisfied. Classify a
genuine execution failure as failed using the schema's corresponding value.
Represent these control outcomes without converting them into implementation
failure:

- `BLOCKED` when progress requires a missing decision, permission, dependency,
  or corrected instruction;
- `CAPACITY_WAIT` when provider capacity or a temporary rate limit prevents
  progress without invalidating the work;
- `CANCELLED` when the mandate is paused, revoked, or cancelled.

Do not include a full hidden-reasoning transcript. Provide decisions, evidence,
commands, results, and actionable context.

---

## 7. Resume, pause, and cancellation

Preserve the provider session identifier when the runtime exposes one. Resume a
session only when the Repo Manager supplies a still-valid mandate and WorkPacket
for that session.

On resume:

1. re-read `AGENTS.md` and this overlay;
2. revalidate the mandate, baseline, and permission envelope;
3. inspect durable prior evidence;
4. confirm that the next action remains authorized;
5. continue from the last durable phase boundary.

A scheduled or deferred continuation must identify the mandate, work unit,
repository or worktree, last completed phase, expected wake condition, and
verification command. Time passing alone does not preserve authorization.

When pause, cancellation, or revocation is observed, stop safely, avoid new
mutations, preserve useful evidence, and return the corresponding structured
status.

---

## 8. Escalation quality

An escalation must be decision-ready. State:

- what is blocked;
- the evidence and current repository state;
- what has already been attempted;
- the smallest decision or permission needed;
- the safe options and their tradeoffs;
- Claude's recommendation;
- the consequence of taking no action.

Do not ask broad questions when repository evidence can narrow the choice.

---

## 9. Explicit prohibitions

Claude must not:

- choose work by taking the first unchecked roadmap item without dependency and
  mandate validation;
- convert a proposed roadmap `[x]` into integrated completion;
- rely on the retired green-CI-to-merge behavior;
- merge because the repository is `CLEAN` or checks are green;
- weaken tests, gates, or policy to obtain a passing result;
- store portable policy or secrets in `.claude/settings.local.json`;
- broaden path, command, network, or credential access;
- continue after the mandate expires, is revoked, or no longer matches state;
- create artificial commits or pull requests solely to end a session;
- claim `COMPLETE` before verified integration and post-merge reconciliation.

When this overlay conflicts with `AGENTS.md`, follow `AGENTS.md` and report the
conflict for correction.

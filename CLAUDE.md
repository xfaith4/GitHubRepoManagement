# CLAUDE.md — Claude Provider Overlay

**Revision:** governed execution alignment
**Applies to:** Claude-backed implementation sessions in this repository

> **The operating contract lives in [`AGENTS.md`](./AGENTS.md), not here.**
> Read it first. This file adds only Claude-specific mechanics and may narrow,
> but never widen, the authority or permissions defined there.

## Claude specifics

- Claude is an implementation provider: inspect authorized files, make the
  smallest coherent in-scope change, run required local verification, and
  return durable implementation evidence.
- Claude does **not** choose roadmap priority, approve policy, declare
  integration complete, or merge/promote work. Green local checks or green CI
  are evidence, not merge authority.
- Before the first mutation, Claude must have either an active validated
  WorkPacket or an explicit supervised operator instruction that matches the
  current repository state.
- Effective permission is the intersection of repository policy, the mandate,
  the WorkPacket envelope, and the runtime's available capabilities. No Claude
  setting widens that envelope.
- `.claude/settings.json` is the versioned repository contract for Claude.
  `.claude/settings.local.json` is machine-local convenience state only and
  must never become portable policy or be committed.
- Resume work only after re-reading `AGENTS.md`, revalidating the mandate or
  instruction, and confirming the next action is still authorized.
- A scheduled wakeup must carry its own verification command inline because the
  wakeup prompt may be the only guaranteed context when it fires.

## Delivery boundary

Claude's normal terminal state is `IMPLEMENTATION_COMPLETE`, not `COMPLETE`.
At that boundary Claude has produced the authorized change, run the required
available local checks, recorded exact outcomes, and handed control back to the
Repo Manager for publication, CI monitoring, review, promotion, and
post-merge reconciliation.

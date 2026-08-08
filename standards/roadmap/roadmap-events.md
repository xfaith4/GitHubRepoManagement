# Roadmap Events Contract (`roadmap-events.jsonl`)

> **Status:** optional, additive to the Roadmap Contract Standard (Release 2.4).
> A managed repo MAY maintain a `roadmap-events.jsonl` alongside its `ROADMAP.md`
> to give AI agents and dashboards a machine-readable execution history.

## Shape

One JSON object per line (JSONL), **append-only** — never rewrite or truncate
existing lines. Each event is schema-versioned so consumers can evolve safely.

```json
{"schemaVersion":"v1","ts":"2026-07-05T18:00:00Z","type":"lifecycle","phase":"2.2/M3","state":"started","actor":"agent:claude-code","correlationId":"..."}
```

### Required fields

| Field           | Type   | Notes                                                            |
| --------------- | ------ | ---------------------------------------------------------------- |
| `schemaVersion` | string | `v1`.                                                            |
| `ts`            | string | ISO-8601 UTC timestamp.                                          |
| `type`          | string | One of the constrained event types below.                       |

### Optional fields

| Field           | Type   | Notes                                                            |
| --------------- | ------ | ---------------------------------------------------------------- |
| `phase`         | string | Release/milestone the event concerns. Prefer the stable form `{releaseId}/{milestoneId}` (e.g. `2.2/M3`) over a free-text title — release titles and milestone wording can change, but IDs are permanent once assigned (see ROADMAP_TEMPLATE.md authoring rules). Fall back to `{releaseId}` alone when the event isn't milestone-scoped. |
| `state`         | string | For `lifecycle`: `started` \| `progressed` \| `blocked` \| `completed`. |
| `actor`         | string | `agent:<name>` or `operator:<name>`.                            |
| `correlationId` | string | Ties related events (dispatch → run → merge) together.          |
| `detail`        | object | Event-specific payload (see per-type notes).                    |

## Constrained event types

- **`lifecycle`** — phase state transitions. `state` is required.
- **`validation`** — a gate ran. `detail`: `{ "gate": "...", "passed": true|false }`.
- **`error`** — a failure worth recording. `detail`: `{ "message": "...", "code": "..." }`.
- **`decision`** — an operator/agent choice. `detail`: `{ "choice": "...", "rationale": "..." }`.
- **`commit`** — a commit tied to a phase. `detail`: `{ "sha": "...", "message": "..." }`.
- **`metric`** — a measured value. `detail`: `{ "name": "...", "value": 0, "unit": "..." }`.

Consumers MUST ignore unknown `type` values and unknown fields rather than
error, so the contract can grow without breaking older readers.

## Relationship to ROADMAP.md

`ROADMAP.md`'s optional "Phase plan" table holds a **planning-time estimate**
only (`Work units est` in the template). This file is the sole record of
**actuals** — token usage, spend, review minutes, and real unit consumption
are recorded here via `phase.completed`-style `lifecycle`/`metric` events and
never hand-copied back into the roadmap document. If a dashboard needs "actual
vs. estimate" for a phase, it joins the roadmap's estimate against this
ledger's actuals by `{releaseId}/{milestoneId}` — it does not read a second
actuals number out of `ROADMAP.md`, because that number would just be a copy
that goes stale.

## Guarantees

- Append-only: the file is a durable audit log; history is never mutated.
- Idempotent tail: re-reading the file yields the same ordered event stream.
- Self-describing: every line carries `schemaVersion` + `ts` + `type`.

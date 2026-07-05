# Roadmap Events Contract (`roadmap-events.jsonl`)

> **Status:** optional, additive to the Roadmap Contract Standard (Release 2.4).
> A managed repo MAY maintain a `roadmap-events.jsonl` alongside its `ROADMAP.md`
> to give AI agents and dashboards a machine-readable execution history.

## Shape

One JSON object per line (JSONL), **append-only** — never rewrite or truncate
existing lines. Each event is schema-versioned so consumers can evolve safely.

```json
{"schemaVersion":"v1","ts":"2026-07-05T18:00:00Z","type":"lifecycle","phase":"Release 2.2 / auth core","state":"started","actor":"agent:claude-code","correlationId":"..."}
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
| `phase`         | string | Release / phase the event concerns.                             |
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

## Guarantees

- Append-only: the file is a durable audit log; history is never mutated.
- Idempotent tail: re-reading the file yields the same ordered event stream.
- Self-describing: every line carries `schemaVersion` + `ts` + `type`.

# app.db backup and restore

Release 3.3 milestone 2. Before this path existed, 20+ days of maturity
history lived exactly once, on one disk.

## Backup

Snapshots are taken with SQLite's `VACUUM INTO` — consistent and compacted,
safe against a **live** database, no host shutdown required.

| Surface | What it does |
| --- | --- |
| `POST /api/maintenance/backup` | Snapshot now; prunes to the newest 7 |
| `GET /api/maintenance/backups` | List snapshots with their manifests |
| `Invoke-DailyEvidence.ps1` | Takes the snapshot daily, unattended |

Snapshots land in `output/backups/app-db/app-<UTC stamp>.db`, each beside an
`app-<stamp>.manifest.json` carrying the schema version, row counts for the
load-bearing tables, size, and source — a backup you can judge without
opening it. The newest 7 are kept; pruned names are reported, not silently
dropped.

## Restore

Restore is **operator-only, with the API host stopped** — the host holds the
database a restore would overwrite. There is deliberately no restore route.

```powershell
pwsh .\scripts\Restore-AppDb.ps1 -BackupPath output\backups\app-db\app-<stamp>.db
```

The script refuses to run while anything listens on the portal port. The
snapshot is verified before anything moves (`PRAGMA integrity_check` plus
schema version); the existing database is **moved aside** to
`app.db.pre-restore-<stamp>.db`, never destroyed; the restored file is
verified again through the same provider the host uses. `-WhatIf` previews
without touching anything.

## The schema story

- **Older snapshot** (schema v1..current): restores cleanly. The host's
  migrations are idempotent and replay forward on the next boot — that is
  the supported restore window: **any version ≥ 1**.
- **Newer snapshot** (schema version above what the code knows): **refused
  by name** (`schema-newer-than-code`). Upgrade the code first, then
  restore. A future schema handed to older migrations is undefined
  behavior, so it is not allowed to begin.

## How this is proven

The module smoke's "AppDb backup/restore" gate rehearses the whole loop on a
fixture database: snapshot → mutate the live file → restore → **query the
restored history through the provider** → assert the mutated original moved
aside intact. It also proves the future-schema refusal, `-WhatIf` inertness,
and snapshot retention. A restore path that has never run is a hope, not a
path.

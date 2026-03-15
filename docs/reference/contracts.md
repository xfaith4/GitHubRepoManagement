# Canonical Contracts

Version: `v1`

## RepoItem

```json
{
  "name": "RepoName",
  "folderName": "RepoName",
  "path": "G:\\Development\\RepoName",
  "branch": "main",
  "lastCommitDate": "2026-03-07T12:00:00.0000000-05:00",
  "lastCommitMessage": "Fix status cache schema handling",
  "lastCommitAuthor": "Jane Doe",
  "commitsLastWeek": 4,
  "commitsLastMonth": 17,
  "modifiedCount": 0,
  "untrackedCount": 0,
  "dirtyCount": 0,
  "status": "clean",
  "originUrl": "https://github.com/org/repo.git",
  "openPrCount": 3,
  "pendingReviewPrCount": 1
}
```

## ComparisonItem

```json
{
  "Status": "Matched",
  "MatchReason": "OriginUrl",
  "LocalPath": "G:\\Development\\RepoName",
  "LocalRepoName": "RepoName",
  "GitHubName": "RepoName",
  "GitHubUrl": "https://github.com/org/repo"
}
```

## DocManifestRepo

```json
{
  "repoName": "RepoName",
  "repoPath": "G:\\Development\\RepoName",
  "markdownFileCount": 12,
  "priority": "high",
  "reviewMode": "core"
}
```

## QueueItem

```json
{
  "repoName": "RepoName",
  "batchType": "core",
  "priorityScore": 88,
  "fileCount": 5
}
```

## BatchPlanItem

```json
{
  "repoName": "RepoName",
  "batchId": "RepoName.core.001",
  "promptPath": "workitems\\RepoName\\batch-001-prompt.md",
  "checklistPath": "workitems\\RepoName\\batch-001-checklist.md",
  "files": [
    "README.md"
  ]
}
```

## CopilotWorkItemManifest

```json
{
  "generatedAt": "2026-03-08T07:20:00.0000000-05:00",
  "outputRoot": "output\docreview-adapter\workitems",
  "page": {
    "pageNumber": 1,
    "pageSize": 25,
    "pageCount": 6,
    "totalEligible": 148,
    "selectedCount": 25,
    "hasNextPage": true
  },
  "items": [
    {
      "queueId": "UnifiedAIToolbox.core.001",
      "workItemPath": "output\docreview-adapter\workitems\UnifiedAIToolbox.core.001",
      "promptPath": "output\docreview-adapter\workitems\UnifiedAIToolbox.core.001\prompt.txt"
    }
  ]
}
```

## RoadmapEntry

```json
{
  "repoName": "MyRepo",
  "repoPath": "G:\\Development\\MyRepo",
  "roadmapPath": "G:\\Development\\MyRepo\\ROADMAP.md",
  "lastModified": "2026-03-13T09:00:00.0000000Z",
  "sizeBytes": 2048
}
```

## RoadmapIndex (GET /api/roadmap/index, POST /api/roadmap/scan)

Query parameters (GET): `localRoots` (encoded path), `maxDepth` (int), `refresh=true` (bust cache).
Body parameters (POST): `{ localRoots: string[], maxDepth: int }`.

```json
{
  "success": true,
  "data": {
    "entries": [ /* RoadmapEntry[] */ ],
    "count": 4,
    "scannedAt": "2026-03-13T14:00:00.0000000Z",
    "cacheSource": "disk",
    "cacheAgeSeconds": 87
  }
}
```

`cacheSource` values: `"memory"` | `"disk"` | `"fresh-scan"`.

## RoadmapContent (GET /api/roadmap/content)

Query parameters: `repo=<repoName>` (URL-encoded).

```json
{
  "success": true,
  "data": {
    "repoName": "MyRepo",
    "content": "# ROADMAP\n...",
    "path": "G:\\Development\\MyRepo\\ROADMAP.md",
    "sizeBytes": 2048,
    "lastModified": "2026-03-13T09:00:00.0000000Z"
  }
}
```

Content is limited to 512 KB. Returns `404` with `success: false` if the repo has no roadmap or the file is unreadable.

## RoadmapCacheMeta (GET /api/roadmap/cache)

```json
{
  "success": true,
  "data": {
    "memoryHit": true,
    "diskCachePath": "backend\\modules\\output\\cache\\roadmap-index-cache.json",
    "cacheAgeSeconds": 87,
    "ttlSeconds": 300,
    "entryCount": 4
  }
}
```

POST `/api/roadmap/cache/clear` — clears both memory and disk cache. Returns `{ "success": true }`.

## RoadmapTaskPreview (POST /api/roadmap-agent/preview)

Request body:

```json
{
  "repository": "owner/repo",
  "baseBranch": "main",
  "customAgent": "",
  "roadmapPath": ""
}
```

Response payload:

```json
{
  "success": true,
  "data": {
    "runId": "20260315-121530-a1b2c3d4",
    "repository": "owner/repo",
    "roadmapPath": "ROADMAP.md",
    "selectedTask": {
      "heading": "Active / Next",
      "lineNumber": 27,
      "text": "Add smoke test coverage for roadmap routes"
    },
    "followUpCandidates": [
      {
        "heading": "Near-Term",
        "lineNumber": 33,
        "text": "Add stricter API contract tests"
      }
    ],
    "generatedTaskDescription": "Continue roadmap execution ...",
    "history": {
      "rootPath": "output\\roadmap-task-history",
      "runEventsPath": "output\\roadmap-task-history\\runs\\20260315-121530-a1b2c3d4.events.jsonl",
      "runSummaryPath": "output\\roadmap-task-history\\runs\\20260315-121530-a1b2c3d4.summary.json",
      "historyPath": "output\\roadmap-task-history\\history.jsonl"
    }
  }
}
```

## RoadmapTaskStart (POST /api/roadmap-agent/start)

Request body:

```json
{
  "repository": "owner/repo",
  "baseBranch": "main",
  "customAgent": "",
  "follow": false
}
```

Response payload:

```json
{
  "success": true,
  "data": {
    "message": "Roadmap Copilot task initiated.",
    "output": "...script output...",
    "latestHistory": {
      "runId": "20260315-121530-a1b2c3d4",
      "status": "started",
      "repository": "owner/repo",
      "selectedTask": "Add smoke test coverage for roadmap routes",
      "roadmapPath": "ROADMAP.md",
      "startedAt": "2026-03-15T12:15:30.0000000-05:00",
      "completedAt": "2026-03-15T12:15:34.0000000-05:00",
      "summaryPath": "...summary.json"
    }
  }
}
```

## RoadmapTaskHistory (GET /api/roadmap-agent/history)

Query parameters: `limit` (int, default 25).

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "runId": "20260315-121530-a1b2c3d4",
        "status": "preview",
        "repository": "owner/repo",
        "selectedTask": "Add smoke test coverage for roadmap routes",
        "roadmapPath": "ROADMAP.md",
        "startedAt": "2026-03-15T12:15:30.0000000-05:00",
        "completedAt": "2026-03-15T12:15:31.0000000-05:00",
        "error": "",
        "summaryPath": "...summary.json"
      }
    ],
    "count": 1
  }
}
```

## OperationsLogEntry (GET /api/log/tail)

Query parameters: `lines` (int, default 100, max 500), `since` (epoch milliseconds — returns only entries newer than this timestamp).

```json
{
  "success": true,
  "count": 3,
  "entries": [
    { "ts": "2026-03-13T14:00:01.000Z", "level": "INFO",  "msg": "API host started on 127.0.0.1:7071" },
    { "ts": "2026-03-13T14:00:05.000Z", "level": "TRACE", "msg": "[TRACE] roadmap.index correlationId=abc123 start" },
    { "ts": "2026-03-13T14:00:05.050Z", "level": "TRACE", "msg": "[TRACE] roadmap.index correlationId=abc123 done durationMs=48" }
  ]
}
```

`level` values: `"INFO"` | `"WARN"` | `"ERROR"` | `"TRACE"`.

Log is sourced from `backend/modules/output/logs/operations.jsonl`. The `since` cursor allows the dashboard to poll incrementally without re-reading already-seen entries.

## Error Envelope

```json
{
  "operation": "reconcile.run",
  "correlationId": "0f7ab30b8f8e4e90bf87c4726b98fd4f",
  "success": false,
  "timestamp": "2026-03-07T23:00:00.0000000-05:00",
  "error": {
    "category": "dependency",
    "message": "gh command not found"
  }
}
```

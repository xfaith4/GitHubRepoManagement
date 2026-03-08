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
  "modifiedCount": 0,
  "untrackedCount": 0,
  "dirtyCount": 0,
  "status": "clean",
  "originUrl": "https://github.com/org/repo.git"
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

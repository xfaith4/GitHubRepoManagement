import React, { useState, useMemo } from 'react';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
type HttpMethod = 'GET' | 'POST' | 'DELETE';

interface Param {
  name: string;
  type: string;
  required?: boolean;
  description: string;
}

interface EndpointDef {
  method: HttpMethod;
  path: string;
  summary: string;
  queryParams?: Param[];
  bodyParams?: Param[];
  responseFields?: Param[];
  notes?: string;
}

interface CategoryDef {
  label: string;
  color: string;   // tailwind text color for category header
  endpoints: EndpointDef[];
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------
const CATEGORIES: CategoryDef[] = [
  {
    label: 'Health & Metrics',
    color: 'text-emerald-400',
    endpoints: [
      {
        method: 'GET',
        path: '/health/live',
        summary: 'Liveness probe — confirms the API host process is running.',
        responseFields: [
          { name: 'status', type: 'string', description: 'Always "ok"' },
          { name: 'service', type: 'string', description: 'Service identifier' },
          { name: 'time', type: 'ISO 8601', description: 'Server time at response' },
        ],
      },
      {
        method: 'GET',
        path: '/health/ready',
        summary: 'Readiness probe — confirms all required adapters are loaded.',
        notes: 'Always returns HTTP 200. Inspect the status field for "ready" vs "degraded".',
        responseFields: [
          { name: 'status', type: '"ready" | "degraded"', description: 'Aggregate readiness status' },
          { name: 'checks', type: 'object', description: 'Per-adapter ready flags (status, reconcile, docreview)' },
        ],
      },
      {
        method: 'GET',
        path: '/health/dependencies',
        summary: 'Dependency probe — checks git, gh CLI, adapter paths, and workspace writability.',
        notes: 'Always returns HTTP 200. Inspect the status field for "healthy" vs "degraded".',
        responseFields: [
          { name: 'status', type: '"healthy" | "degraded"', description: 'Aggregate dependency status' },
          { name: 'dependencies', type: 'object', description: 'Individual check results (git, gh, adapters, workspace)' },
        ],
      },
      {
        method: 'GET',
        path: '/metrics',
        summary: 'Returns in-memory metrics snapshot (counters and histogram data).',
        responseFields: [
          { name: 'generatedAt', type: 'ISO 8601', description: 'Snapshot timestamp' },
          { name: 'counters', type: 'object', description: 'Named counter values' },
          { name: 'histograms', type: 'object', description: 'Named histogram buckets' },
        ],
      },
    ],
  },
  {
    label: 'Repository Status',
    color: 'text-sky-400',
    endpoints: [
      {
        method: 'GET',
        path: '/api/status',
        summary: 'Scans local repositories and returns status for each (branch, dirty/untracked counts, last commit).',
        queryParams: [
          { name: 'localRoots', type: 'string', description: 'Optional semicolon/comma-delimited workspace roots' },
          { name: 'maxDepth', type: 'int', description: 'Folder scan depth (default: 2)' },
          { name: 'includeNonGitFolders', type: 'bool', description: 'Include non-git directories (default: false)' },
          { name: 'refresh', type: 'bool', description: 'Bypass cache and force a fresh scan' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.repos', type: 'RepoItem[]', description: 'Array of repository status objects' },
          { name: 'meta.repoCount', type: 'number', description: 'Repository count for the scan result' },
          { name: 'meta.scanDurationMs', type: 'number', description: 'Wall-clock scan time in milliseconds' },
          { name: 'meta.statusCache', type: 'object', description: 'Cache metadata including source, age, TTL, and cachedAt' },
        ],
      },
      {
        method: 'GET',
        path: '/api/status/cache',
        summary: 'Returns cache metadata for the status scan (TTL, age, entry count).',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'ttlSeconds', type: 'number', description: 'Cache time-to-live in seconds' },
          { name: 'memoryEntries', type: 'number', description: 'Entries held in process memory' },
          { name: 'memoryKeys', type: 'string[]', description: 'Current in-memory cache keys' },
          { name: 'disk', type: 'object | null', description: 'On-disk cache metadata if present' },
        ],
      },
      {
        method: 'POST',
        path: '/api/status/cache/clear',
        summary: 'Clears the status cache (memory + disk). Forces a fresh scan on next GET /api/status.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Always true on success' },
          { name: 'message', type: 'string', description: 'Clear confirmation message' },
        ],
      },
    ],
  },
  {
    label: 'Portfolio Intelligence',
    color: 'text-cyan-400',
    endpoints: [
      {
        method: 'GET',
        path: '/api/portfolio/assessment',
        summary: 'Returns the normalized portfolio assessment model used by Portfolio Mission, Work Queue ranking, and the collection status report.',
        queryParams: [
          { name: 'refresh', type: 'bool', description: 'Bypass the route cache and rebuild the assessment from the latest warm/cold signals' },
          { name: 'includeGithub', type: 'bool', description: 'Include GitHub-only repos when a GitHub owner and token are configured' },
          { name: 'scanMode', type: '"full" | "differential"', description: 'Use differential reassessment against the persisted portfolio index when supported' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.entries', type: 'PortfolioAssessmentEntry[]', description: 'Normalized lifecycle/readiness record per repository' },
          { name: 'data.summary', type: 'PortfolioAssessmentSummary', description: 'Portfolio-level lifecycle and blocker counts' },
          { name: 'data.signalSources', type: 'object', description: 'Per-signal cache/freshness metadata including differential markers when requested' },
          { name: 'data.generatedAt', type: 'ISO 8601', description: 'Assessment generation time' },
        ],
      },
      {
        method: 'GET',
        path: '/api/operations/repos',
        summary: 'Returns the indexed repository list used by the Operations workspace, including repo-level lifecycle, GitHub, and work-readiness context.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.entries', type: 'OperationsRepoEntry[]', description: 'Repo-specific operations records built from the indexed portfolio payload' },
          { name: 'data.generatedAt', type: 'ISO 8601', description: 'Timestamp from the portfolio index or cached assessment fallback' },
          { name: 'data.count', type: 'number', description: 'Number of operations records returned' },
          { name: 'data.cacheSource', type: '"portfolio-index" | "assessment-cache"', description: 'Whether the route served the persisted index or a warm assessment fallback' },
          { name: 'data.summary', type: 'PortfolioAssessmentSummary | null', description: 'Portfolio-level lifecycle counts for the current index snapshot' },
        ],
        notes: 'Operations prefers the persisted index written by /api/portfolio/assessment. If that index is not available yet, the host falls back to the warm assessment cache when possible.',
      },
      {
        method: 'POST',
        path: '/api/operations/prompt/refine',
        summary: 'Builds on the existing prompt packet contract and applies operator-selected task, emphasis, constraints, and instruction edits for dispatch-ready prompt review.',
        bodyParams: [
          { name: 'repoName', type: 'string', description: 'Repository name used to build the underlying packet context' },
          { name: 'roadmapPath', type: 'string', description: 'Optional explicit roadmap path override' },
          { name: 'selectedTaskText', type: 'string', description: 'Optional pending roadmap checkbox text to prioritize in the refined prompt' },
          { name: 'selectedTaskSection', type: 'string', description: 'Optional section disambiguator for selectedTaskText' },
          { name: 'additionalConstraints', type: 'string[]', description: 'Additional operator constraints to append to the refined prompt' },
          { name: 'emphasisAreas', type: 'string[]', description: 'Focus areas to emphasize in implementation instructions' },
          { name: 'operatorInstructions', type: 'string', description: 'Freeform operator direction appended to the refined prompt' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.runId', type: 'string', description: 'Unique identifier recorded for this refinement run' },
          { name: 'data.createdAt', type: 'ISO 8601', description: 'Timestamp when the refinement run was persisted' },
          { name: 'data.packet', type: 'CopilotTaskPacket', description: 'Base packet generated from existing preview contract' },
          { name: 'data.refinedPrompt', type: 'string', description: 'Dispatch-ready prompt with operator refinements applied' },
          { name: 'data.warnings', type: 'OperationsPromptRefineWarning[]', description: 'Warnings that should remain visible before dispatch' },
          { name: 'data.applied', type: 'object', description: 'Effective selected task and refinement inputs used to generate the prompt' },
        ],
        notes: 'Each successful refinement is persisted per repo under output/roadmap-task-history/prompt-refinements/. When a dispatch uses that refinement run ID, the linked dispatch record is merged into GET /api/operations/prompt/history.',
      },
      {
        method: 'GET',
        path: '/api/operations/prompt/history',
        summary: 'Returns the most recent prompt refinement records for a repository, including linked dispatch records when the refined prompt was dispatched through the API host.',
        queryParams: [
          { name: 'repoName', type: 'string', description: 'Repository name to retrieve refinement history for (required)' },
          { name: 'limit', type: 'int', description: 'Maximum records to return (default: 20)' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.repoName', type: 'string', description: 'Resolved repository name' },
          { name: 'data.items', type: 'OperationsPromptHistoryItem[]', description: 'Refinement history records, most-recent first' },
          { name: 'data.items[].dispatchCount', type: 'number', description: 'Number of dispatch records linked to the refinement run' },
          { name: 'data.items[].latestDispatchAt', type: 'ISO 8601 | null', description: 'Most recent linked dispatch time when available' },
          { name: 'data.items[].dispatchRecords', type: 'OperationsPromptDispatchRecord[]', description: 'Linked dispatch run metadata for the refinement run' },
          { name: 'data.count', type: 'number', description: 'Number of records returned' },
        ],
      },
      {
        method: 'GET',
        path: '/api/readme/content',
        summary: 'Returns README.md content for a repository (by repo name) or for an explicit path, used by the Operations repo-detail viewers.',
        queryParams: [
          { name: 'repo', type: 'string', description: 'Repository name to resolve README content from indexed/status context' },
          { name: 'path', type: 'string', description: 'Optional explicit absolute README file path override' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.repoName', type: 'string', description: 'Resolved repository name for the returned README payload' },
          { name: 'data.content', type: 'string', description: 'Raw UTF-8 README markdown content' },
          { name: 'data.path', type: 'string', description: 'Resolved README path on disk' },
          { name: 'data.sizeBytes', type: 'number', description: 'README file size in bytes' },
          { name: 'data.lastModified', type: 'ISO 8601', description: 'Last write timestamp for the README file' },
        ],
      },
    ],
  },
  {
    label: 'AI Documentation Improvement',
    color: 'text-fuchsia-400',
    endpoints: [
      {
        method: 'POST',
        path: '/api/ai/docs/improve/preview',
        summary: 'Generates a preview-only AI improvement of a README or ROADMAP: current vs proposed content, change summary, estimated score movement, and warnings. Never writes to disk.',
        bodyParams: [
          { name: 'repoName', type: 'string', description: 'Repository name (required)' },
          { name: 'docType', type: '"readme" | "roadmap"', description: 'Document to improve (default: readme)' },
          { name: 'templateId', type: 'string', description: 'Built-in improvement template id from /api/ai/docs/templates (optional; defaults to the first template for the doc type)' },
          { name: 'customPrompt', type: 'string', description: 'Optional operator improvement instruction applied to this cycle' },
          { name: 'provider', type: '"auto" | "heuristic" | "openai" | "anthropic"', description: 'Provider selection; auto prefers a configured AI key and falls back to the offline heuristic provider' },
          { name: 'currentContent', type: 'string', description: 'Optional inline document content; when omitted the host resolves it from the roadmap cache or portfolio index' },
          { name: 'path', type: 'string', description: 'Optional explicit document path override' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.previewId', type: 'string', description: 'Unique identifier recorded for this improvement cycle' },
          { name: 'data.providerId', type: 'string', description: 'Provider that produced the proposal (heuristic, openai, or anthropic)' },
          { name: 'data.currentContent', type: 'string', description: 'Document content the proposal was generated from' },
          { name: 'data.proposedContent', type: 'string', description: 'Proposed improved document content' },
          { name: 'data.changeSummary', type: 'string[]', description: 'Plain-language description of what changed and why' },
          { name: 'data.estimatedScore', type: '{ before, after, delta }', description: 'Estimated section-coverage score movement' },
          { name: 'data.warnings', type: 'string[]', description: 'Provider fallbacks and other operator-facing warnings' },
        ],
        notes: 'Preview-first: no README.md or ROADMAP.md is modified. Each preview appends a compact metadata record to output/ai-doc-improvements/<repo>.improvements.jsonl for the history route. When no AI provider key is configured, the deterministic offline heuristic provider keeps the workflow available.',
      },
      {
        method: 'GET',
        path: '/api/ai/docs/improve/history',
        summary: 'Returns the most recent AI documentation improvement cycles for a repository, newest first.',
        queryParams: [
          { name: 'repoName', type: 'string', description: 'Repository name to retrieve improvement history for (required)' },
          { name: 'docType', type: '"readme" | "roadmap"', description: 'Optional filter by document type' },
          { name: 'limit', type: 'int', description: 'Maximum records to return (default: 20)' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.items', type: 'AiDocImprovementHistoryItem[]', description: 'Improvement cycle records (provider, template, score movement, change summary) — metadata only, not full documents' },
          { name: 'data.count', type: 'number', description: 'Number of records returned' },
        ],
      },
      {
        method: 'GET',
        path: '/api/ai/docs/templates',
        summary: 'Returns the built-in README and ROADMAP improvement templates defined in backend/config/ai-doc-templates.json.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.readmeTemplates', type: 'AiDocTemplate[]', description: 'README improvement templates (product, developer/operator, open-source, portfolio showcase)' },
          { name: 'data.roadmapTemplates', type: 'AiDocTemplate[]', description: 'ROADMAP improvement templates (release-oriented, contract, agent-dispatch-ready, recovery/repair)' },
        ],
      },
    ],
  },
  {
    label: 'Settings',
    color: 'text-violet-400',
    endpoints: [
      {
        method: 'GET',
        path: '/api/settings',
        summary: 'Reads and returns application configuration from backend/config/settings.json.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.inventory', type: 'object', description: 'Local scan configuration including roots and max depth' },
          { name: 'data.reconcile', type: 'object', description: 'Reconcile and GitHub owner defaults' },
          { name: 'data.secrets', type: 'object', description: 'Secret source configuration including token env var name' },
        ],
      },
      {
        method: 'POST',
        path: '/api/settings',
        summary: 'Saves (deep-merges) settings to settings.json. Only supplied keys are updated.',
        bodyParams: [
          { name: 'basePath', type: 'string', description: 'Local repository root path' },
          { name: 'scanDepth', type: 'int', description: 'Folder scan depth' },
          { name: 'daysInactive', type: 'int', description: 'Inactive threshold in days' },
          { name: 'githubUser', type: 'string', description: 'Default GitHub user or org' },
          { name: 'githubToken', type: 'string', description: 'Saved fallback token when env var is not set' },
          { name: 'gitHubTokenEnvVar', type: 'string', description: 'Environment variable name to read first for GitHub auth' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Save result flag' },
          { name: 'data', type: 'object', description: 'Merged settings as persisted' },
        ],
      },
    ],
  },
  {
    label: 'Git Operations',
    color: 'text-amber-400',
    endpoints: [
      {
        method: 'POST',
        path: '/api/init',
        summary: 'Placeholder for clone-from-GitHub workflow. Returns 202 Accepted (not yet implemented).',
        notes: 'Accepted placeholder route. The current host returns a message and does not clone repositories.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'accepted', type: 'bool', description: 'Always true in the current placeholder implementation' },
          { name: 'message', type: 'string', description: 'Placeholder response message' },
        ],
      },
      {
        method: 'POST',
        path: '/api/update',
        summary: 'Runs git pull on specified repositories (or all repos if none specified).',
        bodyParams: [
          { name: 'repoNames', type: 'string[]', description: 'Repo names to update. Omit for all.' },
          { name: 'repoPaths', type: 'string[]', description: 'Explicit repo paths to update. Takes precedence over names.' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Overall operation result' },
          { name: 'data', type: 'OperationResult', description: 'Operation summary and per-repo pull results' },
        ],
      },
      {
        method: 'POST',
        path: '/api/sync',
        summary: 'Runs git fetch --all --prune on specified repositories (or all).',
        bodyParams: [
          { name: 'repoNames', type: 'string[]', description: 'Repo names to fetch. Omit for all.' },
          { name: 'repoPaths', type: 'string[]', description: 'Explicit repo paths to fetch. Takes precedence over names.' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Overall operation result' },
          { name: 'data', type: 'OperationResult', description: 'Operation summary and per-repo fetch results' },
        ],
      },
      {
        method: 'POST',
        path: '/api/archive',
        summary: 'Placeholder for archive-inactive-repos workflow. Returns 202 Accepted (not yet implemented).',
        notes: 'Accepted placeholder route. The current host does not perform archive work.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'accepted', type: 'bool', description: 'Always true in the current placeholder implementation' },
          { name: 'message', type: 'string', description: 'Placeholder response message' },
        ],
      },
    ],
  },
  {
    label: 'Reconciliation & Doc Review',
    color: 'text-pink-400',
    endpoints: [
      {
        method: 'POST',
        path: '/api/reconcile',
        summary: 'Compares local repos against GitHub inventory; produces match/mismatch/orphan report.',
        bodyParams: [
          { name: 'localRoots', type: 'string[]', description: 'Workspace root paths to scan' },
          { name: 'githubOwner', type: 'string', description: 'GitHub user or org to reconcile against' },
          { name: 'ownerType', type: 'string', description: 'Owner type override (Auto, User, Organization)' },
          { name: 'maxDepth', type: 'int', description: 'Scan depth (default: 3)' },
          { name: 'includeNonGitFolders', type: 'bool', description: 'Include non-git folders in comparison' },
          { name: 'outDir', type: 'string', description: 'Directory to write reconcile output artifacts' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data', type: 'object', description: 'Reconcile results payload from the adapter' },
          { name: 'meta', type: 'object', description: 'Adapter metadata including correlation ID and durations' },
        ],
      },
      {
        method: 'POST',
        path: '/api/docreview/run',
        summary: 'Scans repository documentation; optionally generates review queue and batch plan files for Copilot.',
        bodyParams: [
          { name: 'rootPath', type: 'string', required: true, description: 'Workspace root to scan' },
          { name: 'maxDepth', type: 'int', description: 'Scan depth (default: 3)' },
          { name: 'outDir', type: 'string', description: 'Output directory for artifacts' },
          { name: 'targetRepo', type: 'string', description: 'Optional single repository to target' },
          { name: 'generateQueue', type: 'bool', description: 'Write queue.json artifact' },
          { name: 'generateBatchPlan', type: 'bool', description: 'Write per-repo batch plan files' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.inventoryManifestPath', type: 'string', description: 'Generated inventory manifest path' },
          { name: 'data.inventorySummaryCsvPath', type: 'string', description: 'Generated summary CSV path' },
          { name: 'data.inventoryReportPath', type: 'string', description: 'Generated markdown report path' },
          { name: 'data.queuePath', type: 'string | null', description: 'Generated queue path when queue output is enabled' },
          { name: 'data.workitemsRoot', type: 'string | null', description: 'Generated workitems root path when batch output is enabled' },
        ],
      },
    ],
  },
  {
    label: 'Reports & Artifacts',
    color: 'text-teal-400',
    endpoints: [
      {
        method: 'GET',
        path: '/api/report/artifacts',
        summary: 'Lists output artifact files (most recent 200) from the backend output directory.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'artifacts', type: 'object[]', description: 'File metadata (name, path, sizeBytes, lastModified)' },
          { name: 'outputRoot', type: 'string', description: 'Absolute backend output root path' },
        ],
      },
      {
        method: 'GET',
        path: '/api/artifacts/:repoName',
        summary: 'Lists backend artifacts whose name or path matches a repository name.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'repoName', type: 'string', description: 'Requested repository name' },
          { name: 'artifacts', type: 'object[]', description: 'Matching artifact metadata entries' },
        ],
      },
      {
        method: 'POST',
        path: '/api/export',
        summary: 'Generates timestamped HTML and CSV reports in the repo-local reports folder. When portfolio entries are supplied, the export becomes a plain-language Collection Status Report.',
        bodyParams: [
          { name: 'portfolioEntries', type: 'PortfolioAssessmentEntry[]', description: 'Optional normalized portfolio entries to export as a Collection Status Report' },
          { name: 'repos', type: 'RepoStatus[]', description: 'Legacy repository snapshot export input when portfolio entries are not supplied' },
          { name: 'sourceLabel', type: 'string', description: 'Display label for the current dashboard data source' },
        ],
        responseFields: [
          { name: 'reportPath', type: 'string', description: 'Absolute path to the saved HTML report' },
          { name: 'reportUrl', type: 'string', description: 'Browser-openable route for the saved HTML report' },
          { name: 'csvPath', type: 'string', description: 'Absolute path to the saved CSV companion file' },
        ],
        notes: 'The dashboard uses the portfolio-assessment path for local collection reports so the export includes lifecycle state, blockers, recommended action, and top-ranked work.',
      },
      {
        method: 'GET',
        path: '/api/reports/:reportName',
        summary: 'Serves a saved report file from the repo-local reports folder.',
      },
    ],
  },
  {
    label: 'GitHub Integration',
    color: 'text-indigo-400',
    endpoints: [
      {
        method: 'POST',
        path: '/api/github/status',
        summary: 'Fetches repository insights from GitHub using direct REST API when a token is available, otherwise falls back to gh CLI.',
        bodyParams: [
          { name: 'githubUser', type: 'string', description: 'GitHub user or org name. Falls back to saved settings when omitted.' },
          { name: 'apiKey', type: 'string', description: 'Request-scoped token override' },
          { name: 'includePrivate', type: 'bool', description: 'Include private repositories' },
          { name: 'includeArchived', type: 'bool', description: 'Include archived repositories' },
          { name: 'includeForks', type: 'bool', description: 'Include forked repositories' },
          { name: 'repoLimit', type: 'int', description: 'Max repositories to return (default: 50)' },
          { name: 'fetchExtendedMetrics', type: 'bool', description: 'Include additional commit metrics when supported' },
        ],
        responseFields: [
          { name: 'source', type: '"github"', description: 'Static source label' },
          { name: 'username', type: 'string', description: 'Resolved GitHub owner used for the fetch' },
          { name: 'totalRepos', type: 'number', description: 'Total repository count discovered before limit is applied' },
          { name: 'fetchedRepos', type: 'number', description: 'Repository count returned in this response' },
          { name: 'repos', type: 'object[]', description: 'GitHub repository metadata array' },
          { name: 'rateLimit', type: 'object | null', description: 'GitHub API rate limit data when available' },
        ],
      },
    ],
  },
  {
    label: 'Roadmap',
    color: 'text-purple-400',
    endpoints: [
      {
        method: 'GET',
        path: '/api/roadmap/index',
        summary: 'Returns cached index of all ROADMAP files found across local repositories.',
        queryParams: [
          { name: 'localRoots', type: 'string', description: 'Optional semicolon/comma-delimited workspace roots override' },
          { name: 'maxDepth', type: 'int', description: 'Scan depth for roadmap discovery (default: settings or 3)' },
          { name: 'refresh', type: 'bool', description: 'Bypass TTL cache and force a fresh scan' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.entries', type: 'RoadmapEntry[]', description: 'Discovered roadmap files with metadata' },
          { name: 'data.count', type: 'number', description: 'Total entries found' },
          { name: 'data.cacheSource', type: 'string', description: '"memory" | "disk" | "fresh-scan"' },
          { name: 'data.cacheAgeSeconds', type: 'number', description: 'Seconds since last scan' },
        ],
      },
      {
        method: 'GET',
        path: '/api/roadmap/content',
        summary: 'Retrieves the full raw content of a specific ROADMAP file identified by repo name or explicit path.',
        queryParams: [
          { name: 'repo', type: 'string', description: 'URL-encoded repository name looked up from the roadmap index' },
          { name: 'path', type: 'string', description: 'Optional explicit roadmap file path override' },
        ],
        notes: 'Returns the full file contents. Returns HTTP 404 if the repo has no indexed roadmap or the specified file path does not exist.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.repoName', type: 'string', description: 'Repository name' },
          { name: 'data.content', type: 'string', description: 'Raw markdown content' },
          { name: 'data.path', type: 'string', description: 'Absolute path to the file' },
          { name: 'data.sizeBytes', type: 'number', description: 'File size in bytes' },
          { name: 'data.lastModified', type: 'ISO 8601', description: 'File last-modified timestamp' },
        ],
      },
      {
        method: 'POST',
        path: '/api/roadmap/scan',
        summary: 'Triggers a fresh roadmap scan and updates the shared cache when default scan settings are used.',
        bodyParams: [
          { name: 'localRoots', type: 'string[]', description: 'Optional workspace root paths to scan' },
          { name: 'maxDepth', type: 'int', description: 'Optional scan depth override' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'data.entries', type: 'RoadmapEntry[]', description: 'Freshly scanned roadmap entries' },
          { name: 'data.count', type: 'number', description: 'Total entries found' },
          { name: 'data.scannedAt', type: 'ISO 8601', description: 'Scan completion timestamp' },
        ],
      },
      {
        method: 'POST',
        path: '/api/roadmap-agent/preview',
        summary: 'Builds a roadmap-driven Copilot task preview for a target GitHub repository without creating a task.',
        bodyParams: [
          { name: 'repository', type: 'string', required: true, description: 'Target repository in owner/repo format' },
          { name: 'baseBranch', type: 'string', description: 'Optional base branch override' },
          { name: 'customAgent', type: 'string', description: 'Optional custom Copilot agent name' },
          { name: 'roadmapPath', type: 'string', description: 'Optional explicit roadmap path in target repo' },
        ],
        responseFields: [
          { name: 'data.selectedTask', type: 'object', description: 'Next selected unchecked roadmap task' },
          { name: 'data.generatedTaskDescription', type: 'string', description: 'Generated Copilot task prompt' },
          { name: 'data.history', type: 'object', description: 'History file locations for this preview run' },
        ],
      },
      {
        method: 'POST',
        path: '/api/roadmap-agent/start',
        summary: 'Starts a roadmap-driven Copilot task for a target repository and records execution history.',
        bodyParams: [
          { name: 'repository', type: 'string', required: true, description: 'Target repository in owner/repo format' },
          { name: 'baseBranch', type: 'string', description: 'Optional base branch override' },
          { name: 'customAgent', type: 'string', description: 'Optional custom Copilot agent name' },
          { name: 'follow', type: 'bool', description: 'Whether to follow task output stream from gh' },
        ],
        responseFields: [
          { name: 'data.message', type: 'string', description: 'Start status message' },
          { name: 'data.output', type: 'string', description: 'Raw command output from script invocation' },
          { name: 'data.latestHistory', type: 'object', description: 'Most recent history summary entry' },
        ],
      },
      {
        method: 'GET',
        path: '/api/roadmap-agent/history',
        summary: 'Returns recent roadmap task execution history entries.',
        queryParams: [
          { name: 'limit', type: 'int', description: 'Max history entries to return (default: 25)' },
        ],
        responseFields: [
          { name: 'data.items', type: 'object[]', description: 'Recent roadmap task run summaries' },
          { name: 'data.count', type: 'number', description: 'Number of returned history entries' },
        ],
      },
      {
        method: 'GET',
        path: '/api/roadmap/cache',
        summary: 'Returns roadmap cache metadata (TTL, age, entry count, disk path).',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'ttlSeconds', type: 'number', description: 'Cache time-to-live (300 s default)' },
          { name: 'memoryEntries', type: 'number', description: 'Number of roadmap entries currently cached in memory' },
          { name: 'disk', type: 'object | null', description: 'On-disk roadmap cache metadata if present' },
        ],
      },
      {
        method: 'POST',
        path: '/api/roadmap/cache/clear',
        summary: 'Clears roadmap cache (memory + disk). Forces a fresh scan on next index request.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Always true on success' },
        ],
      },
    ],
  },
  {
    label: 'Operations Log',
    color: 'text-orange-400',
    endpoints: [
      {
        method: 'GET',
        path: '/api/log/tail',
        summary: 'Returns the tail of the structured operations log (operations.jsonl) for dashboard polling.',
        queryParams: [
          { name: 'lines', type: 'int', description: 'Max entries to return (default: 100, max: 500)' },
          { name: 'since', type: 'epoch ms', description: 'Only return entries newer than this epoch-ms timestamp (for incremental polling)' },
        ],
        notes: 'The dashboard polls this endpoint every 2.5 s while an operation is active. Use the "since" cursor to avoid re-reading seen entries.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'count', type: 'number', description: 'Number of entries returned' },
          { name: 'entries', type: 'LogEntry[]', description: 'Log entries: { ts, level, msg } where level is INFO | WARN | ERROR | TRACE' },
        ],
      },
    ],
  },
];

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------
const METHOD_COLORS: Record<HttpMethod, string> = {
  GET:    'bg-emerald-900/60 text-emerald-300 border border-emerald-700/50',
  POST:   'bg-sky-900/60 text-sky-300 border border-sky-700/50',
  DELETE: 'bg-red-900/60 text-red-300 border border-red-700/50',
};

const ParamTable: React.FC<{ params: Param[]; kind: 'Query' | 'Body' | 'Response' }> = ({ params, kind }) => (
  <div className="mt-2">
    <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">{kind} Parameters</p>
    <table className="w-full text-xs">
      <thead>
        <tr className="text-left text-gray-500 border-b border-gray-700/50">
          <th className="pb-1 pr-3 font-medium w-36">Name</th>
          <th className="pb-1 pr-3 font-medium w-28">Type</th>
          <th className="pb-1 font-medium">Description</th>
        </tr>
      </thead>
      <tbody>
        {params.map(p => (
          <tr key={p.name} className="border-b border-gray-800/50 last:border-0">
            <td className="py-1 pr-3 font-mono text-gray-300">
              {p.name}
              {p.required && <span className="ml-1 text-red-400">*</span>}
            </td>
            <td className="py-1 pr-3 text-gray-500 font-mono">{p.type}</td>
            <td className="py-1 text-gray-400">{p.description}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

const EndpointCard: React.FC<{ ep: EndpointDef; defaultOpen?: boolean }> = ({ ep, defaultOpen = false }) => {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className="border border-gray-700/50 rounded-lg overflow-hidden bg-gray-800/40">
      {/* Header row — always visible */}
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-start gap-3 px-4 py-3 text-left hover:bg-gray-700/30 transition-colors"
      >
        <span className={`mt-0.5 flex-shrink-0 inline-block text-xs font-bold px-2 py-0.5 rounded font-mono ${METHOD_COLORS[ep.method]}`}>
          {ep.method}
        </span>
        <span className="flex-1 min-w-0">
          <span className="font-mono text-sm text-gray-100">{ep.path}</span>
          <span className="ml-3 text-xs text-gray-400">{ep.summary}</span>
        </span>
        <span className="flex-shrink-0 text-gray-600 text-sm">{open ? '▲' : '▼'}</span>
      </button>

      {/* Expanded detail */}
      {open && (
        <div className="px-4 pb-4 pt-1 border-t border-gray-700/40 space-y-3">
          {ep.notes && (
            <p className="text-xs text-yellow-400/80 bg-yellow-900/20 border border-yellow-700/30 rounded px-3 py-2">
              {ep.notes}
            </p>
          )}
          {ep.queryParams && <ParamTable params={ep.queryParams} kind="Query" />}
          {ep.bodyParams && <ParamTable params={ep.bodyParams} kind="Body" />}
          {ep.responseFields && <ParamTable params={ep.responseFields} kind="Response" />}
        </div>
      )}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Modal
// ---------------------------------------------------------------------------
interface ApiDocsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const ApiDocsModal: React.FC<ApiDocsModalProps> = ({ isOpen, onClose }) => {
  const [search, setSearch] = useState('');
  const [activeCategory, setActiveCategory] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return CATEGORIES
      .map(cat => ({
        ...cat,
        endpoints: cat.endpoints.filter(ep =>
          !q ||
          ep.path.toLowerCase().includes(q) ||
          ep.method.toLowerCase().includes(q) ||
          ep.summary.toLowerCase().includes(q) ||
          cat.label.toLowerCase().includes(q)
        ),
      }))
      .filter(cat =>
        (activeCategory === null || cat.label === activeCategory) &&
        cat.endpoints.length > 0
      );
  }, [search, activeCategory]);

  if (!isOpen) return null;

  const totalRoutes = CATEGORIES.reduce((n, c) => n + c.endpoints.length, 0);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <div className="relative flex flex-col w-full max-w-5xl h-[90vh] bg-gray-900 border border-gray-700 rounded-xl shadow-2xl overflow-hidden">

        {/* ── Header ── */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-700 flex-shrink-0">
          <div className="flex items-center gap-3">
            <h2 className="text-lg font-semibold text-gray-100">API Reference</h2>
            <span className="text-xs text-gray-500 bg-gray-800 px-2 py-0.5 rounded-full">{totalRoutes} routes · v1</span>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-100 text-xl leading-none transition-colors"
            title="Close"
          >
            ✕
          </button>
        </div>

        {/* ── Body: sidebar + content ── */}
        <div className="flex flex-1 min-h-0">

          {/* Sidebar */}
          <nav className="hidden md:flex flex-col w-52 flex-shrink-0 border-r border-gray-700/60 bg-gray-900/80 py-4 overflow-y-auto">
            <button
              onClick={() => setActiveCategory(null)}
              className={`text-left px-4 py-2 text-sm transition-colors ${activeCategory === null ? 'text-gray-100 bg-gray-700/50' : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800/60'}`}
            >
              All Routes
            </button>
            {CATEGORIES.map(cat => (
              <button
                key={cat.label}
                onClick={() => setActiveCategory(cat.label === activeCategory ? null : cat.label)}
                className={`text-left px-4 py-2 text-sm transition-colors ${activeCategory === cat.label ? 'text-gray-100 bg-gray-700/50' : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800/60'}`}
              >
                <span className={`mr-1.5 text-xs ${cat.color}`}>●</span>
                {cat.label}
                <span className="ml-1 text-xs text-gray-600">({cat.endpoints.length})</span>
              </button>
            ))}
          </nav>

          {/* Content */}
          <div className="flex-1 flex flex-col min-w-0 overflow-hidden">

            {/* Search bar */}
            <div className="px-4 pt-3 pb-2 border-b border-gray-700/40 flex-shrink-0">
              <input
                type="text"
                value={search}
                onChange={e => setSearch(e.target.value)}
                placeholder="Filter by path, method, or description…"
                className="w-full bg-gray-800 border border-gray-600 rounded-md px-3 py-2 text-sm text-gray-200 placeholder-gray-500 focus:outline-none focus:border-sky-500"
              />
            </div>

            {/* Route list */}
            <div className="flex-1 overflow-y-auto px-4 py-4 space-y-6">
              {filtered.length === 0 && (
                <p className="text-gray-500 text-sm text-center mt-8">No routes match your filter.</p>
              )}
              {filtered.map(cat => (
                <section key={cat.label}>
                  <h3 className={`text-xs font-bold uppercase tracking-widest mb-3 ${cat.color}`}>
                    {cat.label}
                  </h3>
                  <div className="space-y-2">
                    {cat.endpoints.map(ep => (
                      <EndpointCard key={`${ep.method}:${ep.path}`} ep={ep} defaultOpen={false} />
                    ))}
                  </div>
                </section>
              ))}
            </div>

            {/* Footer */}
            <div className="flex-shrink-0 px-4 py-2 border-t border-gray-700/40 text-xs text-gray-600 flex justify-between">
              <span>Base URL: <span className="font-mono text-gray-500">http://localhost:7071</span></span>
              <span>Full schema: <span className="font-mono text-gray-500">docs/reference/contracts.md</span></span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ApiDocsModal;

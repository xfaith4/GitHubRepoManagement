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
          { name: 'timestamp', type: 'ISO 8601', description: 'Server time at response' },
        ],
      },
      {
        method: 'GET',
        path: '/health/ready',
        summary: 'Readiness probe — confirms all required adapters are loaded.',
        notes: 'Returns HTTP 503 when degraded.',
        responseFields: [
          { name: 'status', type: '"ok" | "degraded"', description: 'Aggregate readiness status' },
          { name: 'checks', type: 'object', description: 'Per-adapter ready flags (status, reconcile, docreview)' },
        ],
      },
      {
        method: 'GET',
        path: '/health/dependencies',
        summary: 'Dependency probe — checks git, gh CLI, adapter paths, and workspace writability.',
        notes: 'Returns HTTP 503 when any dependency is missing.',
        responseFields: [
          { name: 'status', type: '"ok" | "degraded"', description: 'Aggregate dependency status' },
          { name: 'checks', type: 'object', description: 'Individual check results (git, gh, adapters, workspace)' },
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
          { name: 'localRoots', type: 'string', required: true, description: 'URL-encoded workspace root path' },
          { name: 'maxDepth', type: 'int', description: 'Folder scan depth (default: 3)' },
          { name: 'includeNonGitFolders', type: 'bool', description: 'Include non-git directories (default: false)' },
          { name: 'refresh', type: 'bool', description: 'Bypass cache and force a fresh scan' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'repos', type: 'RepoItem[]', description: 'Array of repository status objects' },
          { name: 'scanDurationMs', type: 'number', description: 'Wall-clock scan time in milliseconds' },
          { name: 'cacheSource', type: 'string', description: '"memory" | "disk" | "fresh-scan"' },
        ],
      },
      {
        method: 'GET',
        path: '/api/status/cache',
        summary: 'Returns cache metadata for the status scan (TTL, age, entry count).',
        responseFields: [
          { name: 'memoryKeys', type: 'number', description: 'Entries held in process memory' },
          { name: 'diskCachePath', type: 'string', description: 'Path to on-disk cache file' },
          { name: 'ttlSeconds', type: 'number', description: 'Cache time-to-live in seconds' },
        ],
      },
      {
        method: 'POST',
        path: '/api/status/cache/clear',
        summary: 'Clears the status cache (memory + disk). Forces a fresh scan on next GET /api/status.',
        responseFields: [
          { name: 'success', type: 'bool', description: 'Always true on success' },
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
          { name: 'workspacePath', type: 'string', description: 'Local repository root path' },
          { name: 'maxDepth', type: 'int', description: 'Default folder scan depth' },
          { name: 'daysInactive', type: 'int', description: 'Threshold for inactive repo detection (days)' },
        ],
      },
      {
        method: 'POST',
        path: '/api/settings',
        summary: 'Saves (deep-merges) settings to settings.json. Only supplied keys are updated.',
        bodyParams: [
          { name: 'workspacePath', type: 'string', description: 'Local repository root path' },
          { name: 'maxDepth', type: 'int', description: 'Folder scan depth' },
          { name: 'daysInactive', type: 'int', description: 'Inactive threshold in days' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Save result flag' },
          { name: 'settings', type: 'object', description: 'Merged settings as persisted' },
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
        notes: 'Planned feature. Body shape will be defined in a future release.',
      },
      {
        method: 'POST',
        path: '/api/update',
        summary: 'Runs git pull on specified repositories (or all repos if none specified).',
        bodyParams: [
          { name: 'repos', type: 'string[]', description: 'Repo names to update. Omit for all.' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Overall operation result' },
          { name: 'results', type: 'object[]', description: 'Per-repo pull results' },
        ],
      },
      {
        method: 'POST',
        path: '/api/sync',
        summary: 'Runs git fetch --all --prune on specified repositories (or all).',
        bodyParams: [
          { name: 'repos', type: 'string[]', description: 'Repo names to fetch. Omit for all.' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Overall operation result' },
          { name: 'results', type: 'object[]', description: 'Per-repo fetch results' },
        ],
      },
      {
        method: 'POST',
        path: '/api/archive',
        summary: 'Placeholder for archive-inactive-repos workflow. Returns 202 Accepted (not yet implemented).',
        notes: 'Planned feature.',
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
          { name: 'localRoots', type: 'string[]', required: true, description: 'Workspace root paths to scan' },
          { name: 'maxDepth', type: 'int', description: 'Scan depth (default: 3)' },
          { name: 'includeNonGitFolders', type: 'bool', description: 'Include non-git folders in comparison' },
          { name: 'outDir', type: 'string', description: 'Directory to write reconcile output artifacts' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'summary', type: 'object', description: 'Matched/orphan/missing counts' },
          { name: 'items', type: 'ComparisonItem[]', description: 'Per-repo comparison entries' },
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
          { name: 'generateQueue', type: 'bool', description: 'Write queue.json artifact' },
          { name: 'generateBatchPlan', type: 'bool', description: 'Write per-repo batch plan files' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'repoCount', type: 'number', description: 'Repositories scanned' },
          { name: 'repos', type: 'DocManifestRepo[]', description: 'Per-repo doc inventory' },
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
          { name: 'artifacts', type: 'object[]', description: 'File metadata (name, path, sizeBytes, lastModified)' },
          { name: 'count', type: 'number', description: 'Total artifacts returned' },
        ],
      },
      {
        method: 'POST',
        path: '/api/export',
        summary: 'Placeholder for export workflow. Returns 202 Accepted (not yet implemented).',
        notes: 'Planned feature.',
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
        summary: 'Fetches repository insights from GitHub using the gh CLI (falls back to direct REST API).',
        bodyParams: [
          { name: 'owner', type: 'string', description: 'GitHub user or org name' },
          { name: 'ownerType', type: '"user" | "org"', description: 'Account type' },
          { name: 'includePrivate', type: 'bool', description: 'Include private repositories' },
          { name: 'includeArchived', type: 'bool', description: 'Include archived repositories' },
          { name: 'includeForks', type: 'bool', description: 'Include forked repositories' },
        ],
        responseFields: [
          { name: 'success', type: 'bool', description: 'Operation result flag' },
          { name: 'repos', type: 'object[]', description: 'GitHub repository metadata array' },
          { name: 'meta', type: 'GithubInsightsMeta', description: 'Fetch metadata (count, adapter, duration)' },
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
          { name: 'localRoots', type: 'string', required: true, description: 'URL-encoded workspace root path' },
          { name: 'maxDepth', type: 'int', description: 'Scan depth for roadmap discovery (default: 3)' },
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
        summary: 'Retrieves the raw content of a specific ROADMAP file identified by repo name.',
        queryParams: [
          { name: 'repo', type: 'string', required: true, description: 'URL-encoded repository name' },
        ],
        notes: 'Content is capped at 512 KB. Returns HTTP 404 if the repo has no indexed roadmap.',
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
        summary: 'Triggers a fresh roadmap scan (ignores cache) and updates the index.',
        bodyParams: [
          { name: 'localRoots', type: 'string[]', required: true, description: 'Workspace root paths to scan' },
          { name: 'maxDepth', type: 'int', description: 'Scan depth (default: 3)' },
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
          { name: 'data.memoryHit', type: 'bool', description: 'Whether memory cache is populated' },
          { name: 'data.cacheAgeSeconds', type: 'number', description: 'Seconds since last scan' },
          { name: 'data.ttlSeconds', type: 'number', description: 'Cache time-to-live (300 s default)' },
          { name: 'data.entryCount', type: 'number', description: 'Cached roadmap entry count' },
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

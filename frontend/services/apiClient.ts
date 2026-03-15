import { type RepoStatus, type AppSettings, type Artifact, type GithubInsightsMeta, type OperationResult, type DocReviewRunRequest, type DocReviewRunResult, type ReportExportResult, type RoadmapIndex, type RoadmapContent, type RoadmapTaskPreview, type RoadmapTaskHistoryItem } from '../types';

const USE_MOCK_API = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  const value = (env?.VITE_USE_MOCK_API as string | undefined) ?? 'false';
  return value === 'true' || value === '1';
})();

const API_BASE_URL = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  const isDev = Boolean(env?.DEV);
  const viteUrl = (env?.VITE_API_URL as string | undefined) ?? (env?.REACT_APP_API_URL as string | undefined);
  return viteUrl ?? (isDev ? '/api' : 'http://localhost:7071/api');
})();

async function fetchJson<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, init);
  const text = await response.text();
  let payload: unknown = null;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = text; }

  if (!response.ok) {
    const message = typeof payload === 'string' ? payload : (payload as any)?.error?.message ?? (payload as any)?.error ?? `HTTP ${response.status}`;
    throw new Error(message);
  }

  return payload as T;
}

async function postJson<TResponse>(path: string, body: unknown): Promise<TResponse> {
  return await fetchJson<TResponse>(`${API_BASE_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

function normalizeRepo(repo: any): RepoStatus {
  const dirty = Number(repo?.dirtyCount ?? repo?.modifiedCount ?? 0) + Number(repo?.untrackedCount ?? 0);
  return {
    name: String(repo?.name ?? repo?.folderName ?? 'unknown'),
    status: dirty > 0 ? 'dirty' : 'clean',
    branch: String(repo?.branch ?? 'unknown'),
    lastCommitDate: String(repo?.lastCommitDate ?? ''),
    lastCommitMessage: String(repo?.lastCommitMessage ?? ''),
    lastCommitAuthor: String(repo?.lastCommitAuthor ?? ''),
    localAhead: Number(repo?.localAhead ?? 0),
    remoteAhead: Number(repo?.remoteAhead ?? 0),
    uncommittedChanges: dirty,
    isArchived: Boolean(repo?.isArchived ?? false),
    isStale: Boolean(repo?.isStale ?? false),
    hasArtifacts: Boolean(repo?.hasArtifacts ?? false),
    lastBuildStatus: 'none',
    openPrCount: Number(repo?.openPrCount ?? 0),
    commitsLastWeek: Number(repo?.commitsLastWeek ?? 0),
    commitsLastMonth: Number(repo?.commitsLastMonth ?? 0),
    pendingReviewPrCount: Number(repo?.pendingReviewPrCount ?? 0),
    htmlUrl: repo?.htmlUrl,
    localPath: repo?.path ? String(repo.path) : undefined,
    originUrl: repo?.originUrl ? String(repo.originUrl) : undefined,
    owner: repo?.owner,
    visibility: repo?.visibility,
    language: repo?.language,
    topics: Array.isArray(repo?.topics) ? repo.topics : []
  };
}

function settingsFromApi(data: any): AppSettings {
  const root = data?.data ?? data ?? {};
  return {
    basePath: (root?.inventory?.localRoots?.[0] as string | undefined) ?? 'G:\\Development',
    reportPath: 'reports',
    staleThreshold: 14,
    daysInactive: Number(root?.retention?.days ?? 30),
    zipArchive: true,
    scanDepth: Number(root?.inventory?.maxDepth ?? 3),
    githubUser: (root?.reconcile?.gitHubOwner as string | undefined) ?? '',
    githubToken: ''
  };
}

export async function getStatus(): Promise<{ repos: RepoStatus[]; source: 'sample' | 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number; dataLastUpdated?: string; cacheSource?: string; cacheAgeSeconds?: number; }> {
  if (USE_MOCK_API) {
    const sample = getMockRepos();
    return { repos: sample, source: 'sample', configuredGithubUser: null, workspacePath: undefined, repoCount: sample.length, dataLastUpdated: new Date().toISOString(), cacheSource: 'fresh-scan', cacheAgeSeconds: 0 };
  }

  const requestStartedAt = Date.now();
  const data = await fetchJson<any>(`${API_BASE_URL}/status`);
  const rawRepos = Array.isArray(data?.data?.repos) ? data.data.repos.map(normalizeRepo) : [];
  const dedupedByPath = new Map<string, RepoStatus>();
  for (const repo of rawRepos) {
    const key = repo.localPath ? repo.localPath.toLowerCase() : `${repo.name.toLowerCase()}::${repo.branch.toLowerCase()}`;
    if (!dedupedByPath.has(key)) {
      dedupedByPath.set(key, repo);
    }
  }
  const repos = Array.from(dedupedByPath.values());
  const cacheMeta = data?.meta?.statusCache;
  return {
    repos,
    source: 'local',
    workspacePath: data?.meta?.workspacePath ? String(data.meta.workspacePath) : undefined,
    configuredGithubUser: data?.meta?.configuredGithubUser ? String(data.meta.configuredGithubUser) : null,
    repoCount: Number(data?.meta?.repoCount ?? repos.length),
    scanDurationMs: Number(data?.meta?.scanDurationMs ?? (Date.now() - requestStartedAt)),
    dataLastUpdated: cacheMeta?.cachedAt ?? new Date().toISOString(),
    cacheSource: cacheMeta?.source ?? 'fresh-scan',
    cacheAgeSeconds: cacheMeta?.ageSeconds != null ? Number(cacheMeta.ageSeconds) : 0
  };
}

export async function getSettings(): Promise<AppSettings> {
  if (USE_MOCK_API) {
    return { ...mockSettings };
  }

  const data = await fetchJson<any>(`${API_BASE_URL}/settings`);
  return settingsFromApi(data);
}

export async function saveSettings(settings: AppSettings): Promise<AppSettings> {
  if (USE_MOCK_API) {
    Object.assign(mockSettings, settings);
    return { ...settings };
  }

  await postJson('/settings', settings);
  return settings;
}

export async function startInit(githubUser: string, cloneOwned: boolean, apiKey?: string, basePath?: string): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/init', { githubUser, cloneOwned, apiKey, basePath });
}

export async function startUpdate(repoNames?: string[], repoPaths?: string[]): Promise<OperationResult> {
  if (USE_MOCK_API) {
    return { operation: 'pull', total: 0, succeeded: 0, failed: 0, results: [] };
  }
  const response = await postJson<any>('/update', { repoNames, repoPaths });
  return response?.data as OperationResult;
}

export async function startSync(repoNames?: string[], repoPaths?: string[]): Promise<OperationResult> {
  if (USE_MOCK_API) {
    return { operation: 'sync', total: 0, succeeded: 0, failed: 0, results: [] };
  }
  const response = await postJson<any>('/sync', { repoNames, repoPaths });
  return response?.data as OperationResult;
}

function buildMockReportHtml(repos: RepoStatus[], sourceLabel: string, generatedAt: string): string {
  const rows = repos.map((repo) => `
    <tr>
      <td>${repo.name}</td>
      <td>${repo.branch}</td>
      <td>${repo.status}</td>
      <td>${repo.lastCommitDate}</td>
      <td>${repo.uncommittedChanges}</td>
    </tr>
  `).join('');

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Mock Repository Report</title>
</head>
<body style="font-family: Segoe UI, sans-serif; margin: 0; padding: 32px; background: #0f172a; color: #e2e8f0;">
  <h1 style="margin-top: 0;">Mock Repository Report</h1>
  <p style="color: #94a3b8; margin-bottom: 24px;">Source: ${sourceLabel} | Generated: ${generatedAt}</p>
  <table style="width: 100%; border-collapse: collapse; background: #111827;">
    <thead>
      <tr><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Repository</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Branch</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Status</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Last Commit</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Changes</th></tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>
</body>
</html>`;
}

export async function startExport(repos: RepoStatus[], sourceLabel: string): Promise<ReportExportResult> {
  if (USE_MOCK_API) {
    const generatedAt = new Date().toISOString();
    const timestamp = generatedAt
      .replaceAll('-', '')
      .replaceAll(':', '')
      .replaceAll('T', '')
      .replaceAll('Z', '')
      .replaceAll('.', '')
      .slice(0, 17);
    return {
      generatedAt,
      repoCount: repos.length,
      sourceLabel,
      reportFileName: `repo-status-report_${timestamp}.html`,
      reportPath: `reports/repo-status-report_${timestamp}.html`,
      reportUrl: `data:text/html;charset=utf-8,${encodeURIComponent(buildMockReportHtml(repos, sourceLabel, generatedAt))}`,
      csvFileName: `repo-status-report_${timestamp}.csv`,
      csvPath: `reports/repo-status-report_${timestamp}.csv`,
    };
  }

  const data = await postJson<any>('/export', { repos, sourceLabel });
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Report export failed.');
  }
  return data.data as ReportExportResult;
}

export async function startArchive(daysInactive: number, zipArchive: boolean, repoNames?: string[]): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/archive', { daysInactive, zipArchive, repoNames });
}

export async function clearStatusCache(): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/status/cache/clear', {});
}

export async function startDocReview(request: DocReviewRunRequest): Promise<DocReviewRunResult> {
  if (USE_MOCK_API) {
    return {
      inventoryManifestPath: '',
      inventorySummaryCsvPath: '',
      inventoryReportPath: '',
      queuePath: null,
      workitemsRoot: null
    };
  }

  const data = await postJson<any>('/docreview/run', request);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Doc review run failed.');
  }

  return data?.data as DocReviewRunResult;
}

export async function getArtifacts(repoName: string): Promise<Artifact[]> {
  if (USE_MOCK_API) {
    return mockArtifacts[repoName] ?? [];
  }

  const data = await fetchJson<any>(`${API_BASE_URL}/artifacts/${encodeURIComponent(repoName)}`);
  const artifacts = Array.isArray(data?.artifacts) ? data.artifacts : (Array.isArray(data?.data?.artifacts) ? data.data.artifacts : []);
  return artifacts.map((a: any) => ({
    name: String(a.name ?? 'artifact'),
    size: Number(a.sizeBytes ?? a.size ?? 0),
    createdAt: String(a.lastWriteTime ?? a.createdAt ?? new Date().toISOString()),
    downloadUrl: '#'
  }));
}

interface GithubStatusRequest {
  githubUser: string;
  apiKey?: string;
  includePrivate?: boolean;
  includeForks?: boolean;
  includeArchived?: boolean;
  repoLimit?: number;
  fetchExtendedMetrics?: boolean;
}

interface GithubStatusResponse {
  source: 'github';
  username: string;
  totalRepos: number;
  fetchedRepos: number;
  repos: RepoStatus[];
  rateLimit: GithubInsightsMeta['rateLimit'] | null;
}

export async function getGithubRepoInsights(request: GithubStatusRequest): Promise<GithubStatusResponse> {
  if (USE_MOCK_API) {
    throw new Error('GitHub insights require backend route /api/github/status and gh auth.');
  }

  const data = await postJson<any>('/github/status', request);
  const repos = Array.isArray(data?.repos) ? data.repos.map(normalizeRepo) : [];
  return {
    source: 'github',
    username: data?.username ?? request.githubUser,
    totalRepos: Number(data?.totalRepos ?? repos.length),
    fetchedRepos: Number(data?.fetchedRepos ?? repos.length),
    repos,
    rateLimit: data?.rateLimit ?? null
  };
}

const mockSettings: AppSettings = {
  basePath: 'G:\\Development',
  reportPath: 'reports',
  staleThreshold: 14,
  daysInactive: 30,
  zipArchive: true,
  scanDepth: 3,
  githubUser: '',
  githubToken: ''
};

const mockArtifacts: Record<string, Artifact[]> = {};

const MOCK_REPOS: RepoStatus[] = [
  {
    name: 'sample-repo',
    status: 'clean',
    branch: 'main',
    lastCommitDate: new Date().toISOString(),
    lastCommitMessage: 'sample',
    lastCommitAuthor: 'sample',
    localAhead: 0,
    remoteAhead: 0,
    uncommittedChanges: 0,
    isArchived: false,
    isStale: false
  }
];

function getMockRepos(): RepoStatus[] {
  return MOCK_REPOS.map((r) => ({ ...r }));
}

export async function getRoadmapIndex(refresh = false): Promise<RoadmapIndex> {
  if (USE_MOCK_API) {
    return { entries: [], scannedAt: new Date().toISOString(), count: 0, cacheSource: 'fresh-scan', cacheAgeSeconds: 0 };
  }
  const qs = refresh ? '?refresh=true' : '';
  const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/index${qs}`);
  const d = data?.data ?? {};
  return {
    entries: Array.isArray(d.entries) ? d.entries : [],
    scannedAt: d.scannedAt ?? new Date().toISOString(),
    count: Number(d.count ?? 0),
    cacheSource: d.cacheSource ?? 'fresh-scan',
    cacheAgeSeconds: Number(d.cacheAgeSeconds ?? 0),
  };
}

export async function getRoadmapContent(repoName: string): Promise<RoadmapContent> {
  if (USE_MOCK_API) {
    return { repoName, content: '# ROADMAP\n\nNo content available in mock mode.', path: '', sizeBytes: 0, lastModified: new Date().toISOString() };
  }
  const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/content?repo=${encodeURIComponent(repoName)}`);
  const d = data?.data ?? {};
  return {
    repoName: d.repoName ?? repoName,
    content: d.content ?? '',
    path: d.path ?? '',
    sizeBytes: Number(d.sizeBytes ?? 0),
    lastModified: d.lastModified ?? new Date().toISOString(),
  };
}

export async function triggerRoadmapScan(): Promise<RoadmapIndex> {
  if (USE_MOCK_API) {
    return { entries: [], scannedAt: new Date().toISOString(), count: 0, cacheSource: 'fresh-scan', cacheAgeSeconds: 0 };
  }
  const data = await postJson<any>('/roadmap/scan', {});
  const d = data?.data ?? {};
  return {
    entries: Array.isArray(d.entries) ? d.entries : [],
    scannedAt: d.scannedAt ?? new Date().toISOString(),
    count: Number(d.count ?? 0),
    cacheSource: d.cacheSource ?? 'fresh-scan',
    cacheAgeSeconds: 0,
  };
}

interface RoadmapTaskRequest {
  repository: string;
  baseBranch?: string;
  customAgent?: string;
  roadmapPath?: string;
  follow?: boolean;
}

export async function previewRoadmapTask(request: RoadmapTaskRequest): Promise<RoadmapTaskPreview> {
  const data = await postJson<any>('/roadmap-agent/preview', request);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Roadmap task preview failed.');
  }
  return data.data as RoadmapTaskPreview;
}

export async function startRoadmapTask(request: RoadmapTaskRequest): Promise<{ message: string; output: string; latestHistory: RoadmapTaskHistoryItem | null }> {
  const data = await postJson<any>('/roadmap-agent/start', request);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Roadmap task start failed.');
  }
  return {
    message: String(data?.data?.message ?? 'Roadmap Copilot task initiated.'),
    output: String(data?.data?.output ?? ''),
    latestHistory: (data?.data?.latestHistory ?? null) as RoadmapTaskHistoryItem | null
  };
}

export async function getRoadmapTaskHistory(limit = 25): Promise<RoadmapTaskHistoryItem[]> {
  const data = await fetchJson<any>(`${API_BASE_URL}/roadmap-agent/history?limit=${encodeURIComponent(String(limit))}`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Failed to load roadmap task history.');
  }
  return Array.isArray(data?.data?.items) ? data.data.items : [];
}

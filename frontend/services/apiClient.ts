import { type RepoStatus, type AppSettings, type Artifact, type GithubInsightsMeta, type OperationResult, type DocReviewRunRequest, type DocReviewRunResult, type ReportExportResult, type RoadmapIndex, type RoadmapContent, type RoadmapTaskPreview, type RoadmapTaskHistoryItem, type DocAuditIndex, type DocAuditEntry, type CopilotTaskPacket, type CopilotTaskHistoryItem, type RoadmapAuditIndex, type RoadmapAuditEntry, type RoadmapRepairPreview, type RoadmapRepairHistoryItem, type ExecutionQueueSummary, type ExecutionLaneEntry, type ExecutionHistoryRecord, type RoadmapLintResult, type ReadmeStandardizationPreview, type ReadmeStandardizationHistoryItem, type MaturityDriftResult, type MaturityDriftAlert, type NotificationWebhook, type RoadmapCompletionPreview, type ExecutionMetrics, type ScanSchedule, type RoadmapDependencyGraph, type RepoEvaluationResult, type ReleaseDispatchCheck, type DispatchExecuteResult, type RepoGitStatusDetail, type GitActionResult, type ReadmeGenerationResult, type ReadmeGenerationApplyResult, type ReadmeGenerationHistoryItem, type PortfolioAssessmentResult, type PortfolioAssessmentEntry, type PortfolioAssessmentSummary } from '../types';

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

type OptionalApiFeature = 'docs-audit' | 'roadmap-audit' | 'execution-queue';

class OptionalApiUnavailableError extends Error {
  code: 'OPTIONAL_API_UNAVAILABLE';
  feature: OptionalApiFeature;

  constructor(feature: OptionalApiFeature, message: string) {
    super(message);
    this.name = 'OptionalApiUnavailableError';
    this.code = 'OPTIONAL_API_UNAVAILABLE';
    this.feature = feature;
  }
}

const optionalApiAvailability = new Map<OptionalApiFeature, OptionalApiUnavailableError>();

function getOptionalApiUnavailableError(feature: OptionalApiFeature): OptionalApiUnavailableError | null {
  return optionalApiAvailability.get(feature) ?? null;
}

function markOptionalApiUnavailable(feature: OptionalApiFeature, endpoint: string): OptionalApiUnavailableError {
  const error = new OptionalApiUnavailableError(
    feature,
    `The running backend does not expose /api${endpoint}. Restart the API host from this repo checkout and try again.`
  );
  optionalApiAvailability.set(feature, error);
  return error;
}

export function isOptionalApiUnavailableError(error: unknown): error is OptionalApiUnavailableError {
  return error instanceof OptionalApiUnavailableError || (
    error instanceof Error &&
    'code' in error &&
    (error as { code?: string }).code === 'OPTIONAL_API_UNAVAILABLE'
  );
}

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

export async function getStatus(options?: { stale?: boolean; refresh?: boolean }): Promise<{ repos: RepoStatus[]; source: 'sample' | 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number; dataLastUpdated?: string; cacheSource?: string; cacheAgeSeconds?: number; fromCache: boolean; }> {
  if (USE_MOCK_API) {
    const sample = getMockRepos();
    return { repos: sample, source: 'sample', configuredGithubUser: null, workspacePath: undefined, repoCount: sample.length, dataLastUpdated: new Date().toISOString(), cacheSource: 'fresh-scan', cacheAgeSeconds: 0, fromCache: false };
  }

  const params = new URLSearchParams();
  if (options?.stale) params.set('stale', 'true');
  if (options?.refresh) params.set('refresh', 'true');
  const qs = params.size > 0 ? `?${params.toString()}` : '';

  const requestStartedAt = Date.now();
  const data = await fetchJson<any>(`${API_BASE_URL}/status${qs}`);
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
    cacheAgeSeconds: cacheMeta?.ageSeconds != null ? Number(cacheMeta.ageSeconds) : 0,
    fromCache: cacheMeta?.source === 'memory' || cacheMeta?.source === 'disk'
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
  const result = data.data as ReportExportResult;
  if (!result) {
    throw new Error('Export succeeded but the server returned no result data.');
  }
  // Make reportUrl absolute so it navigates directly to the backend regardless of
  // whether the frontend dev/preview server has an /api proxy configured.
  if (result.reportUrl && !result.reportUrl.startsWith('http')) {
    const backendOrigin = API_BASE_URL.replace(/\/api\/?$/, '');
    return { ...result, reportUrl: `${backendOrigin}${result.reportUrl}` };
  }
  return result;
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

function normalizeDocAuditEntry(e: any): DocAuditEntry {
  return {
    repoName: String(e?.repoName ?? ''),
    repoPath: String(e?.repoPath ?? ''),
    dispatchReadiness: (e?.dispatchReadiness ?? 'missing-roadmap') as DocAuditEntry['dispatchReadiness'],
    docFindings: Array.isArray(e?.docFindings) ? e.docFindings.map((f: any) => ({
      file: String(f?.file ?? ''),
      message: String(f?.message ?? ''),
      severity: (f?.severity ?? 'info') as 'critical' | 'warning' | 'info',
      recommendedAction: String(f?.recommendedAction ?? ''),
    })) : [],
    roadmapState: e?.roadmapState,
    nextPendingRoadmapItem: e?.nextPendingRoadmapItem ?? null,
    auditedAt: String(e?.auditedAt ?? new Date().toISOString()),
    criticalCount: Number(e?.criticalCount ?? 0),
    warningCount: Number(e?.warningCount ?? 0),
    infoCount: Number(e?.infoCount ?? 0),
    readyForDispatch: Boolean(e?.readyForDispatch ?? false),
  };
}

function normalizeDocsAuditError(error: unknown, endpoint: '/docs-audit' | '/docs-audit/scan'): Error {
  const message = error instanceof Error ? error.message : 'Docs audit request failed.';
  if (/404|not found/i.test(message)) {
    return markOptionalApiUnavailable('docs-audit', endpoint);
  }
  return error instanceof Error ? error : new Error(message);
}

export async function getDocsAudit(refresh = false): Promise<DocAuditIndex> {
  if (USE_MOCK_API) {
    return { entries: [], auditedAt: new Date().toISOString(), count: 0, cacheSource: 'fresh-scan', cacheAgeSeconds: 0 };
  }
  const cachedError = getOptionalApiUnavailableError('docs-audit');
  if (cachedError) {
    throw cachedError;
  }
  const qs = refresh ? '?refresh=true' : '';
  try {
    const data = await fetchJson<any>(`${API_BASE_URL}/docs-audit${qs}`);
    const d = data?.data ?? {};
    return {
      entries: Array.isArray(d.entries) ? d.entries.map(normalizeDocAuditEntry) : [],
      auditedAt: d.auditedAt ?? new Date().toISOString(),
      count: Number(d.count ?? 0),
      cacheSource: d.cacheSource ?? 'fresh-scan',
      cacheAgeSeconds: Number(d.cacheAgeSeconds ?? 0),
    };
  } catch (error) {
    throw normalizeDocsAuditError(error, '/docs-audit');
  }
}

export async function triggerDocsAuditScan(): Promise<DocAuditIndex> {
  if (USE_MOCK_API) {
    return { entries: [], auditedAt: new Date().toISOString(), count: 0, cacheSource: 'fresh-scan', cacheAgeSeconds: 0 };
  }
  const cachedError = getOptionalApiUnavailableError('docs-audit');
  if (cachedError) {
    throw cachedError;
  }
  try {
    const data = await postJson<any>('/docs-audit/scan', {});
    const d = data?.data ?? {};
    return {
      entries: Array.isArray(d.entries) ? d.entries.map(normalizeDocAuditEntry) : [],
      auditedAt: d.auditedAt ?? new Date().toISOString(),
      count: Number(d.count ?? 0),
      cacheSource: 'fresh-scan',
      cacheAgeSeconds: 0,
    };
  } catch (error) {
    throw normalizeDocsAuditError(error, '/docs-audit/scan');
  }
}

export async function previewCopilotTaskPacket(repoName: string, roadmapPath?: string): Promise<CopilotTaskPacket> {
  const data = await postJson<any>('/copilot-task/preview', { repoName, roadmapPath: roadmapPath ?? '' });
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Copilot task preview failed.');
  }
  return data.data as CopilotTaskPacket;
}

export async function getCopilotTaskHistory(limit = 25): Promise<CopilotTaskHistoryItem[]> {
  const data = await fetchJson<any>(`${API_BASE_URL}/copilot-task/history?limit=${encodeURIComponent(String(limit))}`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Failed to load Copilot task history.');
  }
  return Array.isArray(data?.data?.items) ? data.data.items : [];
}

// Release 0.8 — Roadmap Contract Audit & Maturity Scoring

function normalizeRoadmapAuditEntry(e: any): RoadmapAuditEntry {
  return {
    schemaVersion: String(e?.schemaVersion ?? '1.0'),
    repoName: String(e?.repoName ?? ''),
    repoPath: e?.repoPath ?? null,
    roadmapPath: e?.roadmapPath ?? null,
    roadmapState: (e?.roadmapState ?? 'missing') as RoadmapAuditEntry['roadmapState'],
    maturityLevel: (e?.maturityLevel ?? 'L0-Absent') as RoadmapAuditEntry['maturityLevel'],
    maturityScore: Number(e?.maturityScore ?? 0),
    pendingCount: Number(e?.pendingCount ?? 0),
    completedCount: Number(e?.completedCount ?? 0),
    totalCount: Number(e?.totalCount ?? 0),
    nextPendingItem: e?.nextPendingItem ?? null,
    sections: Array.isArray(e?.sections) ? e.sections : [],
    hasProductIntent: e?.hasProductIntent ?? null,
    hasReleaseSections: e?.hasReleaseSections ?? null,
    hasAcceptanceCriteria: e?.hasAcceptanceCriteria ?? null,
    hasOutOfScope: e?.hasOutOfScope ?? null,
    releaseCount: e?.releaseCount ?? null,
    vagueItemCount: Number(e?.vagueItemCount ?? 0),
    parseError: e?.parseError ?? null,
    auditFindings: Array.isArray(e?.auditFindings) ? e.auditFindings : [],
    parsedAt: String(e?.parsedAt ?? new Date().toISOString()),
  };
}

function normalizeRoadmapAuditError(error: unknown, endpoint: '/roadmap/audit' | '/roadmap/audit/scan'): Error {
  const message = error instanceof Error ? error.message : 'Roadmap audit request failed.';
  if (/404|not found/i.test(message)) {
    return markOptionalApiUnavailable('roadmap-audit', endpoint);
  }
  if (message.includes('503') || message.includes('ECONNREFUSED') || message.includes('fetch')) {
    return new Error(
      `The running backend does not expose /api${endpoint}. Restart the API host from this repo checkout and try again. (${message})`
    );
  }
  return new Error(message);
}

export async function getRoadmapAudit(opts?: { refresh?: boolean; localRoots?: string[]; maxDepth?: number }): Promise<RoadmapAuditIndex> {
  const cachedError = getOptionalApiUnavailableError('roadmap-audit');
  if (cachedError) {
    throw cachedError;
  }
  try {
    const params: string[] = [];
    if (opts?.refresh) params.push('refresh=true');
    if (opts?.localRoots?.length) params.push(`localRoots=${encodeURIComponent(opts.localRoots.join(';'))}`);
    if (opts?.maxDepth != null) params.push(`maxDepth=${opts.maxDepth}`);
    const qs = params.length > 0 ? `?${params.join('&')}` : '';
    const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/audit${qs}`);
    const d = data?.data ?? {};
    return {
      entries: Array.isArray(d.entries) ? d.entries.map(normalizeRoadmapAuditEntry) : [],
      auditedAt: d.auditedAt ?? new Date().toISOString(),
      count: Number(d.count ?? 0),
      cacheSource: d.cacheSource ?? 'fresh-scan',
      cacheAgeSeconds: Number(d.cacheAgeSeconds ?? 0),
    };
  } catch (error) {
    throw normalizeRoadmapAuditError(error, '/roadmap/audit');
  }
}

export async function triggerRoadmapAuditScan(): Promise<RoadmapAuditIndex> {
  const cachedError = getOptionalApiUnavailableError('roadmap-audit');
  if (cachedError) {
    throw cachedError;
  }
  try {
    const data = await postJson<any>('/roadmap/audit/scan', {});
    const d = data?.data ?? {};
    return {
      entries: Array.isArray(d.entries) ? d.entries.map(normalizeRoadmapAuditEntry) : [],
      auditedAt: d.auditedAt ?? new Date().toISOString(),
      count: Number(d.count ?? 0),
      cacheSource: 'fresh-scan',
      cacheAgeSeconds: 0,
    };
  } catch (error) {
    throw normalizeRoadmapAuditError(error, '/roadmap/audit/scan');
  }
}

// ---------------------------------------------------------------------------
// Release 0.9 — Roadmap Repair Preview & Standardization Workflow
// ---------------------------------------------------------------------------

export async function previewRoadmapRepair(repoName: string, roadmapPath?: string): Promise<RoadmapRepairPreview> {
  const body: Record<string, string> = { repoName };
  if (roadmapPath) body.roadmapPath = roadmapPath;
  const data = await postJson<any>('/roadmap/repair/preview', body);
  const d = data?.data ?? data ?? {};
  return d as RoadmapRepairPreview;
}

export async function applyRoadmapRepair(
  repoName: string,
  previewId: string,
  proposedContent: string,
  roadmapPath?: string,
  originalMaturityLevel?: string,
): Promise<{ repoName: string; roadmapPath: string; previewId: string; appliedAt: string }> {
  const body: Record<string, string> = { repoName, previewId, proposedContent };
  if (roadmapPath) body.roadmapPath = roadmapPath;
  if (originalMaturityLevel) body.originalMaturityLevel = originalMaturityLevel;
  const data = await postJson<any>('/roadmap/repair/apply', body);
  return data?.data ?? data;
}

export async function getRoadmapRepairHistory(limit = 25): Promise<RoadmapRepairHistoryItem[]> {
  const data = await fetchJson<any>(`/roadmap/repair/history?limit=${limit}`);
  return Array.isArray(data?.data?.items) ? data.data.items : [];
}

// Release 1.6 — Roadmap-Driven Release Dispatch to GitHub Copilot

export async function checkRoadmapDispatch(
  repoName: string,
  localPath?: string
): Promise<ReleaseDispatchCheck> {
  const body: Record<string, string> = { repoName };
  if (localPath) body.localPath = localPath;
  const data = await postJson<any>('/roadmap/dispatch/check', body);
  return (data?.data ?? data ?? {}) as ReleaseDispatchCheck;
}

export async function executeRoadmapDispatch(
  repoName: string,
  prompt: string,
  options?: { localPath?: string; baseBranch?: string; follow?: boolean }
): Promise<DispatchExecuteResult> {
  const body: Record<string, unknown> = { repoName, prompt };
  if (options?.localPath) body.localPath = options.localPath;
  if (options?.baseBranch) body.baseBranch = options.baseBranch;
  if (options?.follow !== undefined) body.follow = options.follow;
  const data = await postJson<any>('/roadmap/dispatch/execute', body);
  return (data?.data ?? data ?? {}) as DispatchExecuteResult;
}

// Release 1.7 — Repo Git Status Detail

export async function getRepoGitStatusDetail(
  repoName: string,
  localPath?: string
): Promise<RepoGitStatusDetail> {
  const body: Record<string, string> = { repoName };
  if (localPath) body.localPath = localPath;
  const data = await postJson<any>('/repo/git-status-detail', body);
  return (data?.data ?? data ?? {}) as RepoGitStatusDetail;
}

export async function stashRepoChanges(
  repoName: string,
  localPath?: string
): Promise<GitActionResult> {
  const body: Record<string, string> = { repoName };
  if (localPath) body.localPath = localPath;
  const data = await postJson<any>('/repo/git-stash', body);
  return (data?.data ?? data ?? {}) as GitActionResult;
}

export async function discardRepoChanges(
  repoName: string,
  includeUntracked: boolean,
  localPath?: string
): Promise<GitActionResult> {
  const body: Record<string, unknown> = { repoName, includeUntracked };
  if (localPath) body.localPath = localPath;
  const data = await postJson<any>('/repo/git-discard', body);
  return (data?.data ?? data ?? {}) as GitActionResult;
}

// Release 1.0 — Execution Queue API

function normalizeExecutionQueueError(error: unknown, endpoint: string): Error {
  const message = error instanceof Error ? error.message : 'Execution queue request failed.';
  if (/404|not found/i.test(message)) {
    return markOptionalApiUnavailable('execution-queue', endpoint);
  }
  return error instanceof Error ? error : new Error(message);
}

function normalizeExecutionLaneEntry(entry: any): ExecutionLaneEntry {
  return {
    repoName: String(entry?.repoName ?? ''),
    repoPath: entry?.repoPath ?? undefined,
    executionState: entry?.executionState ?? 'idle',
    roadmapPath: entry?.roadmapPath ?? undefined,
    currentTaskText: entry?.currentTaskText ?? undefined,
    currentTaskSection: entry?.currentTaskSection ?? undefined,
    currentRunId: entry?.currentRunId ?? null,
    laneSlot: entry?.laneSlot ?? null,
    priorityScore: Number(entry?.priorityScore ?? 0),
    assignedAt: entry?.assignedAt ?? null,
    completedAt: entry?.completedAt ?? null,
    lastOutcome: entry?.lastOutcome ?? null,
    retryCount: Number(entry?.retryCount ?? 0),
    errorMessage: entry?.errorMessage ?? null,
    updatedAt: entry?.updatedAt ?? new Date().toISOString(),
  };
}

function normalizeExecutionHistoryRecord(item: any): ExecutionHistoryRecord {
  return {
    repoName: String(item?.repoName ?? ''),
    event: item?.event ?? 'assigned',
    runId: item?.runId ?? undefined,
    taskText: item?.taskText ?? undefined,
    outcome: item?.outcome ?? undefined,
    errorMessage: item?.errorMessage ?? undefined,
    timestamp: item?.timestamp ?? new Date().toISOString(),
  };
}

function normalizeExecutionQueueSummary(raw: any): ExecutionQueueSummary {
  const data = raw?.data ?? raw ?? {};
  const entries = Array.isArray(data.entries) ? data.entries.map(normalizeExecutionLaneEntry) : [];
  const rankedQueue = Array.isArray(data.rankedQueue) ? data.rankedQueue.map(normalizeExecutionLaneEntry) : [];
  const recentHistory = Array.isArray(data.recentHistory) ? data.recentHistory.map(normalizeExecutionHistoryRecord) : [];
  const lane1 = data?.lanes?.lane1 ? normalizeExecutionLaneEntry(data.lanes.lane1) : null;
  const lane2 = data?.lanes?.lane2 ? normalizeExecutionLaneEntry(data.lanes.lane2) : null;

  return {
    schemaVersion: String(data?.schemaVersion ?? '1'),
    updatedAt: data?.updatedAt ?? new Date().toISOString(),
    totalRepos: Number(data?.totalRepos ?? entries.length),
    stateCounts: {
      idle: Number(data?.stateCounts?.idle ?? 0),
      ready: Number(data?.stateCounts?.ready ?? 0),
      running: Number(data?.stateCounts?.running ?? 0),
      blocked: Number(data?.stateCounts?.blocked ?? 0),
      complete: Number(data?.stateCounts?.complete ?? 0),
    },
    activeLaneCount: Number(data?.activeLaneCount ?? [lane1, lane2].filter(Boolean).length),
    lanes: {
      lane1,
      lane2,
    },
    rankedQueue,
    entries,
    recentHistory,
  };
}

export async function getExecutionQueue(): Promise<ExecutionQueueSummary> {
  const cachedError = getOptionalApiUnavailableError('execution-queue');
  if (cachedError) {
    throw cachedError;
  }
  try {
    const data = await fetchJson<any>(`${API_BASE_URL}/execution/queue`);
    return normalizeExecutionQueueSummary(data);
  } catch (error) {
    throw normalizeExecutionQueueError(error, '/execution/queue');
  }
}

export async function syncExecutionQueue(): Promise<ExecutionQueueSummary> {
  const cachedError = getOptionalApiUnavailableError('execution-queue');
  if (cachedError) {
    throw cachedError;
  }
  try {
    const data = await postJson<any>('/execution/sync', {});
    return normalizeExecutionQueueSummary(data);
  } catch (error) {
    throw normalizeExecutionQueueError(error, '/execution/sync');
  }
}

export async function assignExecutionLane(repoName: string, options?: { runId?: string; taskText?: string; taskSection?: string }): Promise<{ success: boolean; laneSlot?: number; runId?: string; error?: string }> {
  const cachedError = getOptionalApiUnavailableError('execution-queue');
  if (cachedError) {
    return { success: false, error: cachedError.message };
  }
  const body: Record<string, unknown> = { repoName };
  if (options?.runId) body.runId = options.runId;
  if (options?.taskText) body.taskText = options.taskText;
  if (options?.taskSection) body.taskSection = options.taskSection;
  let data: any;
  try {
    data = await postJson<any>('/execution/assign', body);
  } catch (error) {
    const normalized = normalizeExecutionQueueError(error, '/execution/assign');
    return { success: false, error: normalized.message };
  }
  if (!data?.success) {
    return { success: false, error: data?.error?.message ?? 'Failed to assign lane' };
  }
  return { success: true, laneSlot: data?.data?.laneSlot, runId: data?.data?.runId };
}

export async function completeExecutionTask(repoName: string, options?: { outcome?: string; hasRemainingWork?: boolean }): Promise<{ success: boolean; newState?: string; error?: string }> {
  const cachedError = getOptionalApiUnavailableError('execution-queue');
  if (cachedError) {
    return { success: false, error: cachedError.message };
  }
  const body: Record<string, unknown> = { repoName };
  if (options?.outcome) body.outcome = options.outcome;
  if (options?.hasRemainingWork !== undefined) body.hasRemainingWork = options.hasRemainingWork;
  let data: any;
  try {
    data = await postJson<any>('/execution/complete', body);
  } catch (error) {
    const normalized = normalizeExecutionQueueError(error, '/execution/complete');
    return { success: false, error: normalized.message };
  }
  if (!data?.success) {
    return { success: false, error: data?.error?.message ?? 'Failed to complete task' };
  }
  return { success: true, newState: data?.data?.newState };
}

export async function cancelExecutionTask(repoName: string, reason?: string): Promise<{ success: boolean; newState?: string; retryCount?: number; error?: string }> {
  const cachedError = getOptionalApiUnavailableError('execution-queue');
  if (cachedError) {
    return { success: false, error: cachedError.message };
  }
  let data: any;
  try {
    data = await postJson<any>('/execution/cancel', { repoName, reason: reason ?? 'cancelled' });
  } catch (error) {
    const normalized = normalizeExecutionQueueError(error, '/execution/cancel');
    return { success: false, error: normalized.message };
  }
  if (!data?.success) {
    return { success: false, error: data?.error?.message ?? 'Failed to cancel task' };
  }
  return { success: true, newState: data?.data?.newState, retryCount: data?.data?.retryCount };
}

export async function requeueExecution(repoName: string, force = false): Promise<{ success: boolean; error?: string }> {
  const cachedError = getOptionalApiUnavailableError('execution-queue');
  if (cachedError) {
    return { success: false, error: cachedError.message };
  }
  let data: any;
  try {
    data = await postJson<any>('/execution/requeue', { repoName, force });
  } catch (error) {
    const normalized = normalizeExecutionQueueError(error, '/execution/requeue');
    return { success: false, error: normalized.message };
  }
  if (!data?.success) {
    return { success: false, error: data?.error?.message ?? 'Failed to requeue' };
  }
  return { success: true };
}

// ---------------------------------------------------------------------------
// Release 1.1 — Standardization, Guardrails, and Continuous Improvement
// ---------------------------------------------------------------------------

export async function getRoadmapLint(repoName: string): Promise<RoadmapLintResult> {
  const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/lint?repoName=${encodeURIComponent(repoName)}`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Roadmap lint request failed.');
  }
  return data.data as RoadmapLintResult;
}

export async function triggerRoadmapLintScan(): Promise<{ results: RoadmapLintResult[]; count: number; scannedAt: string }> {
  const data = await postJson<any>('/roadmap/lint/scan', {});
  const d = data?.data ?? {};
  return {
    results: Array.isArray(d.results) ? d.results : [],
    count: Number(d.count ?? 0),
    scannedAt: d.scannedAt ?? new Date().toISOString(),
  };
}

function normalizeReadmeStandardizationPreview(raw: any): ReadmeStandardizationPreview {
  const data = raw?.data ?? raw ?? {};
  return {
    previewId: String(data?.previewId ?? ''),
    repoName: String(data?.repoName ?? ''),
    previewState: data?.previewState ?? 'standardization-blocked',
    blockReason: data?.blockReason ?? null,
    currentContent: String(data?.currentContent ?? ''),
    proposedContent: data?.proposedContent ?? null,
    standardizationActions: Array.isArray(data?.standardizationActions) ? data.standardizationActions : [],
    generatedAt: data?.generatedAt ?? new Date().toISOString(),
  };
}

function normalizeReadmeStandardizationHistoryItem(raw: any): ReadmeStandardizationHistoryItem {
  return {
    previewId: String(raw?.previewId ?? ''),
    repoName: String(raw?.repoName ?? ''),
    repoPath: raw?.repoPath ?? null,
    event: raw?.event ?? 'apply',
    timestamp: raw?.timestamp ?? raw?.appliedAt ?? new Date().toISOString(),
    appliedAt: raw?.appliedAt ?? null,
  };
}

export async function previewReadmeStandardization(repoName: string, repoPath?: string): Promise<ReadmeStandardizationPreview> {
  const body: Record<string, string> = { repoName };
  if (repoPath) body.repoPath = repoPath;
  const data = await postJson<any>('/readme/standardize/preview', body);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'README standardization preview failed.');
  }
  return normalizeReadmeStandardizationPreview(data);
}

export async function applyReadmeStandardization(
  repoName: string,
  previewId: string,
  proposedContent: string,
  repoPath?: string,
): Promise<{ success: boolean; repoName: string; appliedAt: string }> {
  const body: Record<string, string> = { repoName, previewId, proposedContent };
  if (repoPath) body.repoPath = repoPath;
  const data = await postJson<any>('/readme/standardize/apply', body);
  return data?.data ?? data;
}

export async function getReadmeStandardizationHistory(limit = 25): Promise<ReadmeStandardizationHistoryItem[]> {
  const data = await fetchJson<any>(`${API_BASE_URL}/readme/standardize/history?limit=${limit}`);
  return Array.isArray(data?.data?.items) ? data.data.items.map(normalizeReadmeStandardizationHistoryItem) : [];
}

// Release 1.5 — Copilot-Assisted README Generation

export async function generateReadme(repoName: string, localPath?: string): Promise<ReadmeGenerationResult> {
  const body: Record<string, string> = { repoName };
  if (localPath) body.localPath = localPath;
  const data = await postJson<any>('/readme/generate', body);
  if (!data?.success) {
    throw new Error(data?.message ?? data?.error?.message ?? 'README generation failed.');
  }
  return data.data as ReadmeGenerationResult;
}

export async function applyGeneratedReadme(
  repoName: string,
  generationId: string,
  content: string,
  localPath?: string
): Promise<ReadmeGenerationApplyResult> {
  const body: Record<string, string> = { repoName, generationId, content };
  if (localPath) body.localPath = localPath;
  const data = await postJson<any>('/readme/generate/apply', body);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'README apply failed.');
  }
  return data.data as ReadmeGenerationApplyResult;
}

export async function getReadmeGenerationHistory(limit = 25): Promise<ReadmeGenerationHistoryItem[]> {
  const data = await fetchJson<any>(`${API_BASE_URL}/readme/generate/history?limit=${limit}`);
  return Array.isArray(data?.data?.items) ? data.data.items : [];
}

export async function getMaturityDrift(): Promise<MaturityDriftResult> {
  const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/drift`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Maturity drift request failed.');
  }
  return data.data as MaturityDriftResult;
}

export async function setMaturityBaseline(repoName: string, targetLevel: string): Promise<{ repoName: string; targetLevel: string; setAt: string }> {
  const data = await postJson<any>('/roadmap/drift/baseline', { repoName, targetLevel });
  return data?.data ?? data;
}

export async function acknowledgeMaturityDrift(repoName: string): Promise<{ success: boolean; repoName: string }> {
  const data = await postJson<any>('/roadmap/drift/acknowledge', { repoName });
  return data?.data ?? data;
}

export async function getNotificationWebhooks(): Promise<NotificationWebhook[]> {
  const data = await fetchJson<any>(`${API_BASE_URL}/notifications/webhooks`);
  return Array.isArray(data?.data?.webhooks) ? data.data.webhooks : [];
}

export async function registerNotificationWebhook(url: string, events: string[], label?: string): Promise<NotificationWebhook> {
  const data = await postJson<any>('/notifications/webhooks', { url, events, label: label ?? '' });
  return data?.data as NotificationWebhook;
}

export async function removeNotificationWebhook(id: string): Promise<{ success: boolean }> {
  const data = await postJson<any>('/notifications/webhooks/remove', { id });
  return data?.data ?? { success: true };
}

export async function previewRoadmapCompletion(
  repoName: string,
  completedItems: string[],
): Promise<RoadmapCompletionPreview> {
  const data = await postJson<any>('/roadmap/completion-preview', { repoName, completedItems });
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Roadmap completion preview failed.');
  }
  return data.data as RoadmapCompletionPreview;
}

// ---------------------------------------------------------------------------
// Release 1.2 — Execution metrics, auto-scan schedule, dependency graph
// ---------------------------------------------------------------------------

export async function getExecutionMetrics(): Promise<ExecutionMetrics> {
  const data = await fetchJson<any>(`${API_BASE_URL}/execution/metrics`);
  const d = data?.data ?? data ?? {};
  return {
    completedToday: Number(d.completedToday ?? 0),
    completedThisWeek: Number(d.completedThisWeek ?? 0),
    totalCompleted: Number(d.totalCompleted ?? 0),
    totalCancelled: Number(d.totalCancelled ?? 0),
    avgCurrentRunMins: Number(d.avgCurrentRunMins ?? 0),
    errorRatePct: Number(d.errorRatePct ?? 0),
    stateCounts: {
      idle: Number(d.stateCounts?.idle ?? 0),
      ready: Number(d.stateCounts?.ready ?? 0),
      running: Number(d.stateCounts?.running ?? 0),
      blocked: Number(d.stateCounts?.blocked ?? 0),
      complete: Number(d.stateCounts?.complete ?? 0),
    },
  };
}

export async function getScanSchedule(): Promise<ScanSchedule> {
  const data = await fetchJson<any>(`${API_BASE_URL}/scan/schedule`);
  const d = data?.data ?? data ?? {};
  return {
    enabled: Boolean(d.enabled ?? false),
    intervalMinutes: Number(d.intervalMinutes ?? 0),
    nextScanAt: d.nextScanAt ?? null,
    lastScanAt: d.lastScanAt ?? null,
  };
}

export async function getRoadmapDependencies(refresh = false): Promise<RoadmapDependencyGraph> {
  const qs = refresh ? '?refresh=true' : '';
  const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/dependencies${qs}`);
  const d = data?.data ?? data ?? {};
  return {
    graph: d.graph ?? {},
    summary: Array.isArray(d.summary) ? d.summary : [],
    totalEdges: Number(d.totalEdges ?? 0),
    scannedAt: d.scannedAt ?? new Date().toISOString(),
  };
}

// Release 1.4 — Repo Evaluation Pipeline

export async function evaluateRepo(repoName: string, localPath?: string): Promise<RepoEvaluationResult> {
  const body: Record<string, string> = { repoName };
  if (localPath) body.localPath = localPath;
  const data = await fetchJson<any>(`${API_BASE_URL}/repo/evaluate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return (data?.data ?? data) as RepoEvaluationResult;
}

export async function createRepoRoadmap(repoName: string, content: string, localPath?: string): Promise<{ repoName: string; roadmapPath: string; createdAt: string }> {
  const body: Record<string, string> = { repoName, content };
  if (localPath) body.localPath = localPath;
  const data = await fetchJson<any>(`${API_BASE_URL}/repo/roadmap/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return (data?.data ?? data) as { repoName: string; roadmapPath: string; createdAt: string };
}

export async function getRepoEvaluationHistory(repoName?: string, limit = 25): Promise<RepoEvaluationResult[]> {
  const qs = new URLSearchParams();
  if (repoName) qs.set('repoName', repoName);
  qs.set('limit', String(limit));
  const data = await fetchJson<any>(`${API_BASE_URL}/repo/evaluate/history?${qs.toString()}`);
  const d = data?.data ?? data ?? {};
  return Array.isArray(d.items) ? d.items : [];
}

// Release 1.7.5 — Portfolio Mission Alignment

export async function getPortfolioAssessment(options: { refresh?: boolean; includeGithub?: boolean } = {}): Promise<PortfolioAssessmentResult> {
  const qs = new URLSearchParams();
  if (options.refresh) qs.set('refresh', 'true');
  if (options.includeGithub) qs.set('includeGithub', 'true');
  const suffix = qs.toString() ? `?${qs.toString()}` : '';
  const data = await fetchJson<any>(`${API_BASE_URL}/portfolio/assessment${suffix}`);
  const d = data?.data ?? data ?? {};
  const entries: PortfolioAssessmentEntry[] = Array.isArray(d.entries) ? d.entries : [];
  const summaryRaw = d.summary ?? {};
  const summary: PortfolioAssessmentSummary = {
    totalRepos: Number(summaryRaw.totalRepos ?? entries.length),
    byLifecycle: summaryRaw.byLifecycle ?? {},
    bySourceCoverage: summaryRaw.bySourceCoverage ?? {},
    missingReadmeCount: Number(summaryRaw.missingReadmeCount ?? 0),
    missingRoadmapCount: Number(summaryRaw.missingRoadmapCount ?? 0),
    weakRoadmapCount: Number(summaryRaw.weakRoadmapCount ?? 0),
    readyForWorkCount: Number(summaryRaw.readyForWorkCount ?? 0),
    runningCount: Number(summaryRaw.runningCount ?? 0),
    blockedCount: Number(summaryRaw.blockedCount ?? 0),
  };
  return {
    entries,
    summary,
    signalSources: d.signalSources ?? {},
    generatedAt: String(d.generatedAt ?? new Date().toISOString()),
    count: Number(d.count ?? entries.length),
    cacheSource: d.cacheSource === 'memory' ? 'memory' : 'fresh-scan',
    cacheAgeSeconds: Number(d.cacheAgeSeconds ?? 0),
  };
}

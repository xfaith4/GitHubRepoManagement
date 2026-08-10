import { type AiDocImproveApplyRequest, type AiDocImproveApplyResult, type RepoStatus, type AppSettings, type Artifact, type GithubInsightsMeta, type OperationResult, type DocReviewRunRequest, type DocReviewRunResult, type ReportExportResult, type RoadmapIndex, type RoadmapContent, type RoadmapTaskPreview, type RoadmapTaskHistoryItem, type DocAuditIndex, type DocAuditEntry, type RepositoryImprovementPreview, type CopilotTaskPacket, type CopilotTaskHistoryItem, type RoadmapAuditIndex, type RoadmapAuditEntry, type RoadmapRepairPreview, type RoadmapRepairHistoryItem, type ExecutionQueueSummary, type ExecutionLaneEntry, type ExecutionHistoryRecord, type RoadmapLintResult, type ReadmeStandardizationPreview, type ReadmeStandardizationHistoryItem, type MaturityDriftResult, type NotificationWebhook, type RoadmapCompletionPreview, type ExecutionMetrics, type ScanSchedule, type RoadmapDependencyGraph, type RepoEvaluationResult, type ReleaseDispatchCheck, type DispatchExecuteResult, type RepoGitStatusDetail, type GitActionResult, type ReadmeGenerationResult, type ReadmeGenerationApplyResult, type ReadmeGenerationHistoryItem, type PortfolioAssessmentResult, type PortfolioAssessmentEntry, type PortfolioAssessmentSummary, type PortfolioAssessmentScanSummary, type PortfolioChangeState, type PortfolioScanDecisionReason, type PortfolioScanStatus, type RepoCurationState, type PortfolioTrendResult, type PortfolioTrendSeries, type PortfolioTrendTopCandidate, type PortfolioTrendRepoSparkline, type OperationsRepoEntry, type OperationsRepoDetail, type OperationsReposResult, type OperationsPromptRefineRequest, type OperationsPromptRefineResult, type OperationsPromptHistoryItem, type ReadmeContent, type AiDocImprovePreviewRequest, type AiDocImprovePreviewResult, type AiDocImprovementHistoryItem, type AiDocTemplatesResult, type AiDocTemplate, type AgentRun, type AgentRunsResult, type AgentRunDetailResult, type AgentRunRefreshResult, type MergeReadinessResult, type MergeReadinessMergeResult, type GitHubAuthStatus } from '../types';
import { type AutomationHealthPayload } from '../lib/automationStatus';
import { type PackagedItem } from '../lib/packagedItems';
import { type RunnerPresencePayload } from '../lib/runnerPresence';
import { type WorkItemTrace } from '../lib/workItemTrace';

const USE_MOCK_API = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  const value = (env?.VITE_USE_MOCK_API as string | undefined) ?? 'false';
  return value === 'true' || value === '1';
})();

const API_BASE_URL = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  const viteUrl = (env?.VITE_API_URL as string | undefined) ?? (env?.REACT_APP_API_URL as string | undefined);
  // Default to same-origin so the built frontend works over LAN when the API host
  // serves the static bundle directly on its own address.
  return viteUrl ?? '/api';
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

// Release 2.2 — optional API key for authenticated requests. Stored in
// localStorage so an operator pastes it once; sent as `X-Api-Key` on every
// request when present. Harmless when the host runs open (no auth).
const API_KEY_STORAGE_KEY = 'repoMgmt.apiKey';

function getStoredApiKey(): string {
  try {
    return (typeof localStorage !== 'undefined' ? localStorage.getItem(API_KEY_STORAGE_KEY) : '') ?? '';
  } catch { return ''; }
}

export function setApiKey(key: string): void {
  try {
    if (key) localStorage.setItem(API_KEY_STORAGE_KEY, key);
    else localStorage.removeItem(API_KEY_STORAGE_KEY);
  } catch { /* localStorage unavailable — ignore */ }
}

export function getApiKey(): string {
  return getStoredApiKey();
}

function withAuthHeaders(init?: RequestInit): RequestInit {
  // Always send cookies so a logged-in session (rmsid) authenticates the request
  // (Release 2.7). The API key, when present, rides along as a fallback for
  // automation / pre-login browsers.
  const key = getStoredApiKey();
  const base: RequestInit = { ...init, credentials: 'include' };
  if (!key) return base;
  return {
    ...base,
    headers: { ...(init?.headers as Record<string, string> | undefined), 'X-Api-Key': key },
  };
}

async function fetchJson<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, withAuthHeaders(init));
  const text = await response.text();
  let payload: unknown;
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

// ── Release 2.7 — portal auth (session login + API-key status) ───────────────
export interface AuthStatus {
  authRequired: boolean;
  authEnforced: boolean;
  gateEnabled: boolean;
  loginConfigured: boolean;
  authenticated: boolean;
  method: 'session' | 'apiKey' | null;
  keyEnvVar?: string;
  bindAddress?: string;
  isLoopbackBind?: boolean;
}

export async function getAuthStatus(): Promise<AuthStatus> {
  // API_BASE_URL already includes the /api prefix — do NOT repeat it here.
  const res = await fetchJson<{ success: boolean; data: AuthStatus }>(`${API_BASE_URL}/auth/status`);
  return res.data;
}

// Exchange the operator password for a session cookie. Throws with the server's
// message ('Invalid password.') on failure so the login form can surface it.
export async function login(password: string): Promise<void> {
  await postJson<{ success: boolean }>('/auth/login', { password });
}

export async function logout(): Promise<void> {
  try { await postJson<{ success: boolean }>('/auth/logout', {}); } catch { /* best-effort */ }
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
    hasPages: Boolean(repo?.hasPages ?? false),
    pagesUrl: repo?.pagesUrl ? String(repo.pagesUrl) : undefined,
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
    gitHubTokenEnvVar: (root?.secrets?.gitHubTokenEnvVar as string | undefined) ?? 'GITHUB_TOKEN'
  };
}

export async function getStatus(options?: { stale?: boolean; refresh?: boolean; timeoutMs?: number }): Promise<{ repos: RepoStatus[]; source: 'sample' | 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number; missingRoots?: string[]; dataLastUpdated?: string; cacheSource?: string; cacheAgeSeconds?: number; fromCache: boolean; }> {
  if (USE_MOCK_API) {
    const sample = getMockRepos();
    return { repos: sample, source: 'sample', configuredGithubUser: null, workspacePath: undefined, repoCount: sample.length, missingRoots: [], dataLastUpdated: new Date().toISOString(), cacheSource: 'fresh-scan', cacheAgeSeconds: 0, fromCache: false };
  }

  const params = new URLSearchParams();
  if (options?.stale) params.set('stale', 'true');
  if (options?.refresh) params.set('refresh', 'true');
  const qs = params.size > 0 ? `?${params.toString()}` : '';

  // Optional client-side timeout so a hung/long-running backend scan cannot
  // leave the UI spinning indefinitely. The caller decides what to do with the
  // resulting AbortError (e.g. fall back to the cached list already on screen).
  let init: RequestInit | undefined;
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;
  if (options?.timeoutMs && options.timeoutMs > 0 && typeof AbortController !== 'undefined') {
    const controller = new AbortController();
    timeoutHandle = setTimeout(() => controller.abort(), options.timeoutMs);
    init = { signal: controller.signal };
  }

  const requestStartedAt = Date.now();
  let data: any;
  try {
    data = await fetchJson<any>(`${API_BASE_URL}/status${qs}`, init);
  } catch (err) {
    if (init?.signal?.aborted) {
      // Keep the underlying abort as `cause` so debugging sees the real error,
      // not only the friendlier timeout message.
      throw new Error(`Repository scan timed out after ${Math.round((options?.timeoutMs ?? 0) / 1000)}s.`, { cause: err });
    }
    throw err;
  } finally {
    if (timeoutHandle) clearTimeout(timeoutHandle);
  }
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
    // Configured workspace roots that are not on disk. A scan over a missing root
    // succeeds with zero repos, so without this the UI cannot tell "empty
    // workspace" from "wrong path".
    missingRoots: Array.isArray(data?.meta?.missingRoots) ? data.meta.missingRoots.map(String) : [],
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

/**
 * Ask the host whether the configured environment variable NAME actually
 * resolves in its own process. The browser cannot see the host's environment,
 * and a service cannot see User-scoped variables — so this is the only way to
 * tell an operator their name is set in a scope the host cannot read.
 * Pass validate=true to also spend one GitHub call confirming the token is live.
 */
export async function getGitHubAuthStatus(validate = false): Promise<GitHubAuthStatus> {
  if (USE_MOCK_API) {
    return {
      mode: 'pat', tokenEnvVar: 'GITHUB_TOKEN', tokenSource: 'env', tokenEnvScope: 'User',
      runningAsService: false, hint: '', ghCliPresent: true, liveCheck: null
    };
  }
  const data = await fetchJson<any>(`${API_BASE_URL}/auth/github/status${validate ? '?validate=1' : ''}`);
  return (data?.data ?? data) as GitHubAuthStatus;
}

export async function startInit(githubUser: string, cloneOwned: boolean, basePath?: string): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/init', { githubUser, cloneOwned, basePath });
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

function buildMockCollectionReportHtml(entries: PortfolioAssessmentEntry[], sourceLabel: string, generatedAt: string): string {
  const rows = entries.map((entry) => `
    <tr>
      <td>${entry.repoName}</td>
      <td>${entry.lifecycleState}</td>
      <td>${entry.recommendedAction}</td>
      <td>${entry.topValueItem?.text ?? entry.nextPendingItemText ?? ''}</td>
      <td>${(entry.blockingReasons ?? []).join(' | ')}</td>
    </tr>
  `).join('');

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Mock Collection Status Report</title>
</head>
<body style="font-family: Segoe UI, sans-serif; margin: 0; padding: 32px; background: #0f172a; color: #e2e8f0;">
  <h1 style="margin-top: 0;">Collection Status Report</h1>
  <p style="color: #94a3b8; margin-bottom: 24px;">Source: ${sourceLabel} | Generated: ${generatedAt}</p>
  <table style="width: 100%; border-collapse: collapse; background: #111827;">
    <thead>
      <tr><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Repository</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Lifecycle</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Recommended Action</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Top Work</th><th style="padding: 12px; border-bottom: 1px solid #1f2937; text-align: left; color: #93c5fd;">Blockers</th></tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>
</body>
</html>`;
}

function normalizeOperationsRepoEntry(entry: any): OperationsRepoEntry {
  return {
    repoId: String(entry?.repoId ?? entry?.localPath ?? entry?.githubFullName ?? entry?.repoName ?? 'unknown'),
    ordinal: Number(entry?.ordinal ?? 0),
    repoName: String(entry?.repoName ?? ''),
    sourceCoverage: (entry?.sourceCoverage ?? 'local') as OperationsRepoEntry['sourceCoverage'],
    localPath: String(entry?.localPath ?? ''),
    remoteUrl: String(entry?.remoteUrl ?? ''),
    githubOwner: String(entry?.githubOwner ?? ''),
    githubRepo: String(entry?.githubRepo ?? ''),
    githubFullName: String(entry?.githubFullName ?? ''),
    htmlUrl: String(entry?.htmlUrl ?? ''),
    defaultBranch: String(entry?.defaultBranch ?? ''),
    currentBranch: String(entry?.currentBranch ?? ''),
    hasPages: Boolean(entry?.hasPages ?? false),
    pagesUrl: entry?.pagesUrl ? String(entry.pagesUrl) : null,
    createdAt: entry?.createdAt ? String(entry.createdAt) : null,
    updatedAt: entry?.updatedAt ? String(entry.updatedAt) : null,
    latestWorkflowRunStatus: entry?.latestWorkflowRunStatus ? String(entry.latestWorkflowRunStatus) : null,
    latestWorkflowRunConclusion: entry?.latestWorkflowRunConclusion ? String(entry.latestWorkflowRunConclusion) : null,
    latestWorkflowRunName: entry?.latestWorkflowRunName ? String(entry.latestWorkflowRunName) : null,
    latestWorkflowRunTimestamp: entry?.latestWorkflowRunTimestamp ? String(entry.latestWorkflowRunTimestamp) : null,
    openPrCount: Number(entry?.openPrCount ?? 0),
    pendingReviewPrCount: Number(entry?.pendingReviewPrCount ?? 0),
    localLastCommitDate: entry?.localLastCommitDate ? String(entry.localLastCommitDate) : null,
    localCommitsLastWeek: Number(entry?.localCommitsLastWeek ?? 0),
    localCommitsLastMonth: Number(entry?.localCommitsLastMonth ?? 0),
    localModifiedCount: Number(entry?.localModifiedCount ?? 0),
    localUntrackedCount: Number(entry?.localUntrackedCount ?? 0),
    localDirtyCount: Number(entry?.localDirtyCount ?? 0),
    readmeLastWriteUtc: entry?.readmeLastWriteUtc ? String(entry.readmeLastWriteUtc) : null,
    roadmapLastWriteUtc: entry?.roadmapLastWriteUtc ? String(entry.roadmapLastWriteUtc) : null,
    repoType: String(entry?.repoType ?? 'other'),
    lifecycleState: (entry?.lifecycleState ?? 'discovered') as OperationsRepoEntry['lifecycleState'],
    recommendedAction: String(entry?.recommendedAction ?? ''),
    blockingReasons: Array.isArray(entry?.blockingReasons) ? entry.blockingReasons.map((value: unknown) => String(value)) : [],
    roadmapState: (entry?.roadmapState ?? 'missing') as OperationsRepoEntry['roadmapState'],
    roadmapPath: String(entry?.roadmapPath ?? ''),
    hasRoadmap: Boolean(entry?.hasRoadmap ?? false),
    hasReadme: Boolean(entry?.hasReadme ?? false),
    readmeScore: Number(entry?.readmeScore ?? 0),
    roadmapScore: Number(entry?.roadmapScore ?? 0),
    documentationHealthScore: Number(entry?.documentationHealthScore ?? 0),
    pendingItemCount: Number(entry?.pendingItemCount ?? 0),
    nextPendingItemText: String(entry?.nextPendingItemText ?? ''),
    topValueItem: entry?.topValueItem ?? null,
    maturityLevel: (entry?.maturityLevel ?? 'L0-Absent') as OperationsRepoEntry['maturityLevel'],
    maturityScore: Number(entry?.maturityScore ?? 0),
    dispatchReadiness: (entry?.dispatchReadiness ?? 'missing-roadmap') as OperationsRepoEntry['dispatchReadiness'],
    dispatchReadinessExplanation: entry?.dispatchReadinessExplanation ? String(entry.dispatchReadinessExplanation) : null,
    executionState: (entry?.executionState ?? 'idle') as OperationsRepoEntry['executionState'],
    gitStatus: String(entry?.gitStatus ?? 'unknown'),
    hasCiSignal: Boolean(entry?.hasCiSignal ?? false),
    hasTestSignal: Boolean(entry?.hasTestSignal ?? false),
    docFindingCount: Number(entry?.docFindingCount ?? 0),
    structureFindings: Array.isArray(entry?.structureFindings) ? entry.structureFindings : [],
    curationState: (entry?.curationState ?? 'none') as OperationsRepoEntry['curationState'],
    curationUpdatedAt: entry?.curationUpdatedAt ? String(entry.curationUpdatedAt) : null,
    changeState: (entry?.changeState ?? undefined) as OperationsRepoEntry['changeState'],
    scanDecisionReason: (entry?.scanDecisionReason ?? undefined) as OperationsRepoEntry['scanDecisionReason'],
    headCommitSha: entry?.headCommitSha ? String(entry.headCommitSha) : null,
    lastIndexedCommitSha: entry?.lastIndexedCommitSha ? String(entry.lastIndexedCommitSha) : null,
    lastScanStatus: (entry?.lastScanStatus ?? undefined) as OperationsRepoEntry['lastScanStatus'],
    lastScanError: entry?.lastScanError ? String(entry.lastScanError) : null,
  };
}

function normalizeOperationsRepoDetail(raw: any): OperationsRepoDetail {
  const repo = normalizeOperationsRepoEntry(raw?.repo ?? raw ?? {});
  const documentationContext = raw?.documentationContext ?? {};
  const docAudit = raw?.docAudit ?? {};
  const roadmapAudit = raw?.roadmapAudit ?? {};
  const dispatchContext = raw?.dispatchContext ?? {};

  return {
    repoId: String(raw?.repoId ?? repo.repoId),
    repo,
    documentationContext: {
      hasReadme: Boolean(documentationContext?.hasReadme ?? repo.hasReadme),
      readmeLastWriteUtc: documentationContext?.readmeLastWriteUtc ? String(documentationContext.readmeLastWriteUtc) : null,
      hasRoadmap: Boolean(documentationContext?.hasRoadmap ?? repo.hasRoadmap),
      roadmapPath: documentationContext?.roadmapPath ? String(documentationContext.roadmapPath) : (repo.roadmapPath || null),
      roadmapLastWriteUtc: documentationContext?.roadmapLastWriteUtc ? String(documentationContext.roadmapLastWriteUtc) : null,
      docFindingCount: Number(documentationContext?.docFindingCount ?? repo.docFindingCount ?? 0),
      structureFindings: Array.isArray(documentationContext?.structureFindings)
        ? documentationContext.structureFindings
        : repo.structureFindings,
    },
    docAudit: {
      auditedAt: docAudit?.auditedAt ? String(docAudit.auditedAt) : null,
      dispatchReadiness: docAudit?.dispatchReadiness ?? repo.dispatchReadiness,
      criticalCount: Number(docAudit?.criticalCount ?? 0),
      warningCount: Number(docAudit?.warningCount ?? 0),
      infoCount: Number(docAudit?.infoCount ?? 0),
      findings: Array.isArray(docAudit?.findings) ? docAudit.findings : [],
    },
    roadmapAudit: {
      auditedAt: roadmapAudit?.auditedAt ? String(roadmapAudit.auditedAt) : null,
      roadmapState: roadmapAudit?.roadmapState ?? repo.roadmapState,
      maturityLevel: roadmapAudit?.maturityLevel ?? repo.maturityLevel,
      maturityScore: Number(roadmapAudit?.maturityScore ?? repo.maturityScore ?? 0),
      pendingCount: Number(roadmapAudit?.pendingCount ?? repo.pendingItemCount ?? 0),
      nextPendingItem: roadmapAudit?.nextPendingItem ?? null,
      auditFindings: Array.isArray(roadmapAudit?.auditFindings) ? roadmapAudit.auditFindings : [],
    },
    dispatchContext: {
      dispatchReadiness: dispatchContext?.dispatchReadiness ?? repo.dispatchReadiness,
      dispatchReadinessExplanation: dispatchContext?.dispatchReadinessExplanation
        ? String(dispatchContext.dispatchReadinessExplanation)
        : (repo.dispatchReadinessExplanation ?? null),
      recommendedAction: String(dispatchContext?.recommendedAction ?? repo.recommendedAction ?? ''),
      blockingReasons: Array.isArray(dispatchContext?.blockingReasons) ? dispatchContext.blockingReasons.map((value: unknown) => String(value)) : repo.blockingReasons,
      pendingItemCount: Number(dispatchContext?.pendingItemCount ?? repo.pendingItemCount ?? 0),
      nextPendingItemText: dispatchContext?.nextPendingItemText ? String(dispatchContext.nextPendingItemText) : (repo.nextPendingItemText || null),
      topValueItem: dispatchContext?.topValueItem ?? repo.topValueItem ?? null,
    },
  };
}

interface ReportExportRequest {
  repos?: RepoStatus[];
  portfolioEntries?: PortfolioAssessmentEntry[];
  sourceLabel: string;
}

export async function startExport(request: ReportExportRequest): Promise<ReportExportResult> {
  if (USE_MOCK_API) {
    const generatedAt = new Date().toISOString();
    const timestamp = generatedAt
      .replaceAll('-', '')
      .replaceAll(':', '')
      .replaceAll('T', '')
      .replaceAll('Z', '')
      .replaceAll('.', '')
      .slice(0, 17);
    const usingPortfolioEntries = (request.portfolioEntries?.length ?? 0) > 0;
    const reportBaseName = usingPortfolioEntries ? 'collection-status-report' : 'repo-status-report';
    return {
      generatedAt,
      repoCount: usingPortfolioEntries ? request.portfolioEntries!.length : (request.repos ?? []).length,
      sourceLabel: request.sourceLabel,
      reportFileName: `${reportBaseName}_${timestamp}.html`,
      reportPath: `reports/${reportBaseName}_${timestamp}.html`,
      reportUrl: `data:text/html;charset=utf-8,${encodeURIComponent(
        usingPortfolioEntries
          ? buildMockCollectionReportHtml(request.portfolioEntries ?? [], request.sourceLabel, generatedAt)
          : buildMockReportHtml(request.repos ?? [], request.sourceLabel, generatedAt)
      )}`,
      csvFileName: `${reportBaseName}_${timestamp}.csv`,
      csvPath: `reports/${reportBaseName}_${timestamp}.csv`,
    };
  }

  const data = await postJson<any>('/export', request);
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

function getMockOperationsRepos(): OperationsReposResult {
  const generatedAt = new Date().toISOString();
  const entries = getMockRepos().map((repo, index): OperationsRepoEntry => ({
    repoId: repo.localPath || `mock:${repo.name.toLowerCase()}`,
    ordinal: index + 1,
    repoName: repo.name,
    curationState: 'none',
    curationUpdatedAt: null,
    sourceCoverage: repo.htmlUrl ? 'local+github' : 'local',
    localPath: repo.localPath ?? '',
    remoteUrl: repo.originUrl ?? '',
    githubOwner: repo.owner ?? '',
    githubRepo: repo.name,
    githubFullName: repo.owner ? `${repo.owner}/${repo.name}` : repo.name,
    htmlUrl: repo.htmlUrl ?? '',
    defaultBranch: 'main',
    currentBranch: repo.branch,
    hasPages: Boolean(repo.hasPages ?? false),
    pagesUrl: repo.pagesUrl ?? null,
    createdAt: null,
    updatedAt: null,
    latestWorkflowRunStatus: null,
    latestWorkflowRunConclusion: null,
    latestWorkflowRunName: null,
    latestWorkflowRunTimestamp: null,
    openPrCount: Number(repo.openPrCount ?? 0),
    pendingReviewPrCount: Number(repo.pendingReviewPrCount ?? 0),
    localLastCommitDate: repo.lastCommitDate || null,
    localCommitsLastWeek: Number(repo.commitsLastWeek ?? 0),
    localCommitsLastMonth: Number(repo.commitsLastMonth ?? 0),
    localModifiedCount: repo.uncommittedChanges,
    localUntrackedCount: 0,
    localDirtyCount: repo.uncommittedChanges,
    readmeLastWriteUtc: null,
    roadmapLastWriteUtc: null,
    repoType: 'other',
    lifecycleState: 'discovered',
    recommendedAction: 'Mock operations data does not include roadmap readiness.',
    blockingReasons: [],
    roadmapState: 'missing',
    roadmapPath: '',
    hasRoadmap: false,
    hasReadme: true,
    readmeScore: 0,
    roadmapScore: 0,
    documentationHealthScore: 0,
    pendingItemCount: 0,
    nextPendingItemText: '',
    topValueItem: null,
    maturityLevel: 'L0-Absent',
    maturityScore: 0,
    dispatchReadiness: 'missing-roadmap',
    dispatchReadinessExplanation: null,
    executionState: 'idle',
    gitStatus: repo.status,
    hasCiSignal: false,
    hasTestSignal: false,
    docFindingCount: 0,
    structureFindings: [],
  }));

  return {
    entries,
    generatedAt,
    count: entries.length,
    cacheSource: 'assessment-cache',
    summary: null,
  };
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
  gitHubTokenEnvVar: 'GITHUB_TOKEN'
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

export async function getReadmeContent(repoName: string): Promise<ReadmeContent> {
  if (USE_MOCK_API) {
    return { repoName, content: '# README\n\nNo content available in mock mode.', path: '', sizeBytes: 0, lastModified: new Date().toISOString() };
  }
  const data = await fetchJson<any>(`${API_BASE_URL}/readme/content?repo=${encodeURIComponent(repoName)}`);
  const d = data?.data ?? {};
  return {
    repoName: d.repoName ?? repoName,
    content: d.content ?? '',
    path: d.path ?? '',
    sizeBytes: Number(d.sizeBytes ?? 0),
    lastModified: d.lastModified ?? new Date().toISOString(),
  };
}

export async function triggerRoadmapScan(repoName?: string): Promise<RoadmapIndex> {
  if (USE_MOCK_API) {
    return { entries: [], scannedAt: new Date().toISOString(), count: 0, cacheSource: 'fresh-scan', cacheAgeSeconds: 0 };
  }
  const data = await postJson<any>('/roadmap/scan', repoName ? { repoName } : {});
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

export async function approveRoadmapTask(runId: string): Promise<{ message: string; branch: string; pushed: boolean }> {
  const data = await postJson<any>('/roadmap-agent/approve-push', { runId });
  if (!data?.success) {
    throw new Error(data?.error?.message ?? 'Roadmap task approve & push failed.');
  }
  return {
    message: String(data?.data?.message ?? 'Branch pushed.'),
    branch: String(data?.data?.branch ?? ''),
    pushed: Boolean(data?.data?.pushed)
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

export async function previewRepositoryImprovement(
  repoName: string,
  repoPath: string
): Promise<RepositoryImprovementPreview> {
  const data = await postJson<any>('/repository-improvement/preview', { repoName, repoPath });
  return (data?.data ?? data) as RepositoryImprovementPreview;
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

// Release 2.4 — build a PR for a roadmap repair. Dry-run by default (returns the
// planned branch/title/body); createPr=true is the operator-driven live path.
export interface RoadmapRepairPrResult {
  dryRun: boolean;
  created: boolean;
  prUrl: string | null;
  plan: { repoName: string; previewId: string; branch: string; baseBranch: string; title: string; body: string };
  note: string;
}

export async function submitRoadmapRepairPr(repoName: string, previewId?: string, createPr = false): Promise<RoadmapRepairPrResult> {
  const body: Record<string, unknown> = { repoName };
  if (previewId) body.previewId = previewId;
  if (createPr) body.createPr = true;
  const data = await postJson<any>('/roadmap/repair/submit-pr', body);
  return (data?.data ?? data) as RoadmapRepairPrResult;
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
  options?: { localPath?: string; baseBranch?: string; follow?: boolean; promptRefinementRunId?: string }
): Promise<DispatchExecuteResult> {
  const body: Record<string, unknown> = { repoName, prompt };
  if (options?.localPath) body.localPath = options.localPath;
  if (options?.baseBranch) body.baseBranch = options.baseBranch;
  if (options?.follow !== undefined) body.follow = options.follow;
  if (options?.promptRefinementRunId) body.promptRefinementRunId = options.promptRefinementRunId;
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

/**
 * Release 2.7 Phase D — scheduled-automation health.
 *
 * Returns null when the endpoint is unreachable rather than throwing or
 * defaulting to a healthy shape: `resolveAutomationStatus` renders null as
 * 'unknown', and reporting "healthy" because the status call failed would be
 * the same false-green this surface exists to prevent.
 */
export async function getAutomationStatus(): Promise<AutomationHealthPayload | null> {
  try {
    const data = await fetchJson<any>(`${API_BASE_URL}/automation/status`);
    const d = data?.data ?? null;
    return d ? (d as AutomationHealthPayload) : null;
  } catch {
    return null;
  }
}

/**
 * Release 3.0 — operator-runner presence.
 *
 * Resolves null on failure rather than throwing: `resolveRunnerPresence` renders
 * null as 'unknown' and still warns before queueing, which is the safe direction.
 * Throwing here would break a dispatch surface over a status call.
 */
export async function getRunnerPresence(): Promise<RunnerPresencePayload | null> {
  try {
    const data = await fetchJson<any>(`${API_BASE_URL}/roadmap/runner`);
    const d = data?.data ?? null;
    return d ? (d as RunnerPresencePayload) : null;
  } catch {
    return null;
  }
}

/**
 * Release 2.7 Phase C — the packaged roadmap-item approval queue.
 *
 * These three calls are the operator surface for the approval gate. Before them
 * the only way to approve a packaged item was a hand-written POST, which made a
 * scheduled run's output less discoverable than a doc-improve preview.
 *
 * Unlike `getAutomationStatus`, a failure here throws: the panel must show the
 * error rather than render an empty queue that looks like "nothing to approve".
 */
export async function getPackagedItems(status = '', limit = 100): Promise<{ items: PackagedItem[]; pendingCount: number }> {
  const params = new URLSearchParams();
  if (status) params.set('status', status);
  if (limit) params.set('limit', String(limit));
  const qs = params.toString();
  const data = await fetchJson<any>(`${API_BASE_URL}/automation/packages${qs ? `?${qs}` : ''}`);
  const d = data?.data ?? {};
  return {
    items: Array.isArray(d.items) ? (d.items as PackagedItem[]) : [],
    pendingCount: Number(d.pendingCount ?? 0),
  };
}

export interface PackagedItemActionResult {
  packetId: string;
  status: string;
  dispatched: boolean;
  dispatchTarget?: string | null;
  dispatchRunId?: string | null;
  branch?: string | null;
  note?: string | null;
}

/**
 * Approve a packet. `dispatch` defaults to true because approval IS the
 * dispatch gate — the backend enqueues to the operator runner in the same call.
 */
export async function approvePackagedItem(
  packetId: string,
  options?: { actor?: string; dispatch?: boolean }
): Promise<PackagedItemActionResult> {
  const data = await postJson<any>('/automation/packages/approve', {
    packetId,
    actor: options?.actor ?? 'operator',
    dispatch: options?.dispatch ?? true,
  });
  return (data?.data ?? {}) as PackagedItemActionResult;
}

export async function rejectPackagedItem(
  packetId: string,
  reason: string,
  actor = 'operator'
): Promise<PackagedItemActionResult> {
  const data = await postJson<any>('/automation/packages/reject', { packetId, reason, actor });
  return (data?.data ?? {}) as PackagedItemActionResult;
}

/**
 * Release 3.1 — one work item's whole life, from any id the chain minted.
 *
 * The backend accepts a packetId, a packaging runId, a dispatch runId or an
 * agent-run id and resolves them all to the same trace, so callers never have
 * to know which ledger produced the id they are holding. A 404 means no work
 * item matches — surfaced as an error rather than an empty trace, because an
 * empty trace reads as "nothing happened" when the truth is "unknown id".
 */
export async function getWorkItemTrace(id: string): Promise<WorkItemTrace> {
  const data = await fetchJson<{ data?: WorkItemTrace }>(`${API_BASE_URL}/trace/${encodeURIComponent(id)}`);
  return (data?.data ?? ({} as WorkItemTrace));
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

// Release 2.2 — guided first-run setup. The /setup routes live at the host
// root, not under /api, so derive a root base from API_BASE_URL.
const SETUP_BASE = API_BASE_URL.replace(/\/api\/?$/, '');

export interface SetupStatus {
  needsSetup: boolean;
  settingsExists: boolean;
  hasLocalRoots: boolean;
  localRootCount: number;
  firstScanComplete: boolean;
  authRequired: boolean;
}

export interface SetupPrerequisite {
  id: string;
  label: string;
  required: boolean;
  ok: boolean;
  detail: string;
}

export async function getSetupStatus(): Promise<SetupStatus> {
  const data = await fetchJson<any>(`${SETUP_BASE}/setup/status`);
  const d = data?.data ?? data ?? {};
  return {
    needsSetup: Boolean(d.needsSetup),
    settingsExists: Boolean(d.settingsExists),
    hasLocalRoots: Boolean(d.hasLocalRoots),
    localRootCount: Number(d.localRootCount ?? 0),
    firstScanComplete: Boolean(d.firstScanComplete),
    authRequired: Boolean(d.authRequired),
  };
}

export async function getSetupPrerequisites(): Promise<{ prerequisitesMet: boolean; checks: SetupPrerequisite[] }> {
  const data = await fetchJson<any>(`${SETUP_BASE}/setup/prerequisites`);
  const d = data?.data ?? data ?? {};
  return {
    prerequisitesMet: Boolean(d.prerequisitesMet),
    checks: Array.isArray(d.checks) ? d.checks.map((c: any) => ({
      id: String(c.id ?? ''),
      label: String(c.label ?? ''),
      required: Boolean(c.required),
      ok: Boolean(c.ok),
      detail: String(c.detail ?? ''),
    })) : [],
  };
}

export async function submitSetupConfig(config: { localRoots: string[]; maxDepth?: number; gitHubOwner?: string; requireApiKey?: boolean }): Promise<{ needsSetup: boolean; settingsPath: string; localRootCount: number; generatedApiKey: string | null }> {
  const data = await fetchJson<any>(`${SETUP_BASE}/setup/config`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });
  const d = data?.data ?? data ?? {};
  return {
    needsSetup: Boolean(d.needsSetup),
    settingsPath: String(d.settingsPath ?? ''),
    localRootCount: Number(d.localRootCount ?? 0),
    generatedApiKey: d.generatedApiKey ?? null,
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

function normalizePortfolioAssessmentEntry(entry: any): PortfolioAssessmentEntry {
  return {
    repoName: String(entry?.repoName ?? ''),
    localPath: String(entry?.localPath ?? ''),
    htmlUrl: String(entry?.htmlUrl ?? ''),
    branch: String(entry?.branch ?? ''),
    gitStatus: String(entry?.gitStatus ?? 'unknown'),
    isArchived: Boolean(entry?.isArchived ?? false),
    sourceCoverage: (entry?.sourceCoverage ?? 'local') as PortfolioAssessmentEntry['sourceCoverage'],
    hasPages: entry?.hasPages == null ? undefined : Boolean(entry.hasPages),
    pagesUrl: entry?.pagesUrl ? String(entry.pagesUrl) : null,
    openPrCount: entry?.openPrCount == null ? undefined : Number(entry.openPrCount ?? 0),
    pendingReviewPrCount: entry?.pendingReviewPrCount == null ? undefined : Number(entry.pendingReviewPrCount ?? 0),
    latestWorkflowRunStatus: entry?.latestWorkflowRunStatus ? String(entry.latestWorkflowRunStatus) : null,
    latestWorkflowRunConclusion: entry?.latestWorkflowRunConclusion ? String(entry.latestWorkflowRunConclusion) : null,
    latestWorkflowRunName: entry?.latestWorkflowRunName ? String(entry.latestWorkflowRunName) : null,
    latestWorkflowRunTimestamp: entry?.latestWorkflowRunTimestamp ? String(entry.latestWorkflowRunTimestamp) : null,
    repoType: String(entry?.repoType ?? 'other'),
    lifecycleState: (entry?.lifecycleState ?? 'discovered') as PortfolioAssessmentEntry['lifecycleState'],
    recommendedAction: String(entry?.recommendedAction ?? ''),
    blockingReasons: Array.isArray(entry?.blockingReasons) ? entry.blockingReasons.map((value: unknown) => String(value)) : [],
    roadmapState: (entry?.roadmapState ?? 'missing') as PortfolioAssessmentEntry['roadmapState'],
    roadmapPath: String(entry?.roadmapPath ?? ''),
    hasRoadmap: Boolean(entry?.hasRoadmap ?? false),
    readmeScore: entry?.readmeScore == null ? undefined : Number(entry.readmeScore),
    roadmapScore: entry?.roadmapScore == null ? undefined : Number(entry.roadmapScore),
    documentationHealthScore: entry?.documentationHealthScore == null ? undefined : Number(entry.documentationHealthScore),
    pendingItemCount: Number(entry?.pendingItemCount ?? 0),
    nextPendingItemText: String(entry?.nextPendingItemText ?? ''),
    pendingItems: Array.isArray(entry?.pendingItems) ? entry.pendingItems : [],
    topValueItem: entry?.topValueItem ?? null,
    maturityLevel: (entry?.maturityLevel ?? 'L0-Absent') as PortfolioAssessmentEntry['maturityLevel'],
    maturityScore: Number(entry?.maturityScore ?? 0),
    dispatchReadiness: (entry?.dispatchReadiness ?? 'missing-roadmap') as PortfolioAssessmentEntry['dispatchReadiness'],
    dispatchReadinessExplanation: entry?.dispatchReadinessExplanation ? String(entry.dispatchReadinessExplanation) : undefined,
    executionState: (entry?.executionState ?? 'idle') as PortfolioAssessmentEntry['executionState'],
    hasReadme: Boolean(entry?.hasReadme ?? false),
    hasCiSignal: Boolean(entry?.hasCiSignal ?? false),
    hasTestSignal: Boolean(entry?.hasTestSignal ?? false),
    structureFindings: Array.isArray(entry?.structureFindings) ? entry.structureFindings : [],
    docFindingCount: Number(entry?.docFindingCount ?? 0),
    activeRelease: entry?.activeRelease ?? null,
    activePhasePlan: entry?.activePhasePlan ?? null,
    budgetGuardrail: entry?.budgetGuardrail ?? null,
    estimatedSessionWorkUnits: entry?.estimatedSessionWorkUnits == null ? null : Number(entry.estimatedSessionWorkUnits),
    changeState: (entry?.changeState ?? undefined) as PortfolioChangeState | undefined,
    scanDecisionReason: (entry?.scanDecisionReason ?? undefined) as PortfolioScanDecisionReason | undefined,
    headCommitSha: entry?.headCommitSha ? String(entry.headCommitSha) : null,
    headCommitDate: entry?.headCommitDate ? String(entry.headCommitDate) : null,
    headBranch: entry?.headBranch ? String(entry.headBranch) : null,
    currentMetadataHash: entry?.currentMetadataHash ? String(entry.currentMetadataHash) : null,
    lastIndexedCommitSha: entry?.lastIndexedCommitSha ? String(entry.lastIndexedCommitSha) : null,
    lastIndexedCommitDate: entry?.lastIndexedCommitDate ? String(entry.lastIndexedCommitDate) : null,
    lastIndexedBranch: entry?.lastIndexedBranch ? String(entry.lastIndexedBranch) : null,
    lastMetadataHash: entry?.lastMetadataHash ? String(entry.lastMetadataHash) : null,
    lastScannedAt: entry?.lastScannedAt ? String(entry.lastScannedAt) : null,
    lastScanStatus: (entry?.lastScanStatus ?? undefined) as PortfolioScanStatus | undefined,
    lastScanError: entry?.lastScanError ? String(entry.lastScanError) : null,
    repoId: entry?.repoId ? String(entry.repoId) : undefined,
    curationState: (entry?.curationState ?? undefined) as RepoCurationState | undefined,
    curationUpdatedAt: entry?.curationUpdatedAt ? String(entry.curationUpdatedAt) : null,
  };
}

export async function getPortfolioAssessment(options: { refresh?: boolean; includeGithub?: boolean; scanMode?: 'full' | 'differential'; includeCuration?: boolean } = {}): Promise<PortfolioAssessmentResult> {
  const qs = new URLSearchParams();
  if (options.refresh) qs.set('refresh', 'true');
  if (options.includeGithub) qs.set('includeGithub', 'true');
  if (options.scanMode) qs.set('scanMode', options.scanMode);
  if (options.includeCuration) qs.set('includeCuration', 'true');
  const suffix = qs.toString() ? `?${qs.toString()}` : '';
  const data = await fetchJson<any>(`${API_BASE_URL}/portfolio/assessment${suffix}`);
  return normalizePortfolioAssessmentResult(data);
}

/**
 * Release 2.3 Phase 5E — explicit operator-driven full reassessment.
 * Every repository is reindexed and reports scanDecisionReason=forced-refresh;
 * ordinary loads should use scanMode=differential instead.
 */
export async function refreshAllPortfolioAssessment(): Promise<PortfolioAssessmentResult> {
  const data = await postJson<any>('/portfolio/assessment/refresh-all', {});
  if (data && data.success === false) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Full portfolio refresh failed.');
  }
  return normalizePortfolioAssessmentResult(data);
}

function normalizePortfolioAssessmentResult(data: any): PortfolioAssessmentResult {
  const d = data?.data ?? data ?? {};
  const entries: PortfolioAssessmentEntry[] = Array.isArray(d.entries) ? d.entries.map(normalizePortfolioAssessmentEntry) : [];
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
    scanSummary: d.scanSummary
      ? {
          reused: Number((d.scanSummary as PortfolioAssessmentScanSummary)?.reused ?? 0),
          reindexed: Number((d.scanSummary as PortfolioAssessmentScanSummary)?.reindexed ?? 0),
          failed: Number((d.scanSummary as PortfolioAssessmentScanSummary)?.failed ?? 0),
          durationMs: Number((d.scanSummary as PortfolioAssessmentScanSummary)?.durationMs ?? 0),
        }
      : undefined,
  };
}

export async function getPortfolioTrend(options: { days?: number } = {}): Promise<PortfolioTrendResult> {
  if (USE_MOCK_API) {
    const ops = getMockOperationsRepos();
    const entries = ops.entries;
    const today = new Date().toISOString().slice(0, 10);
    const averageMaturityScore = entries.length > 0
      ? Math.round(entries.reduce((sum, entry) => sum + Number(entry.maturityScore ?? 0), 0) / entries.length)
      : 0;
    const readyForWorkCount = entries.filter(entry => entry.lifecycleState === 'ready-for-work').length;

    const series: PortfolioTrendSeries[] = [
      {
        key: 'avgMaturityScore',
        label: 'Avg Maturity',
        color: 'emerald',
        points: [{ date: today, value: averageMaturityScore }],
      },
      {
        key: 'readyRepos',
        label: 'Ready Repos',
        color: 'sky',
        points: [{ date: today, value: readyForWorkCount }],
      },
    ];

    const topCandidates: PortfolioTrendTopCandidate[] = entries
      .filter(entry => entry.topValueItem)
      .sort((left, right) => (right.topValueItem?.valueScore ?? 0) - (left.topValueItem?.valueScore ?? 0))
      .slice(0, 5)
      .map(entry => ({
        repoName: entry.repoName,
        lifecycleState: entry.lifecycleState,
        maturityLevel: entry.maturityLevel,
        maturityScore: Number(entry.maturityScore ?? 0),
        documentationHealthScore: Number(entry.documentationHealthScore ?? 0),
        pendingItemCount: Number(entry.pendingItemCount ?? 0),
        topValueItemText: String(entry.topValueItem?.text ?? entry.nextPendingItemText ?? ''),
        valueScore: Number(entry.topValueItem?.valueScore ?? 0),
        recommendedAction: entry.recommendedAction,
      }));

    const repoSparklines: PortfolioTrendRepoSparkline[] = topCandidates.map(candidate => ({
      repoName: candidate.repoName,
      lifecycleState: candidate.lifecycleState,
      maturityLevel: candidate.maturityLevel,
      currentScore: candidate.maturityScore,
      points: [{ date: today, value: candidate.maturityScore }],
      topValueItemText: candidate.topValueItemText,
      recommendedAction: candidate.recommendedAction,
    }));

    return {
      trendStatus: 'current-snapshot-only',
      seedSource: 'assessment-cache',
      requestedDays: Number(options.days ?? 90),
      availableDays: 1,
      generatedAt: new Date().toISOString(),
      note: 'Mock mode exposes only the current snapshot analytics scaffold.',
      summary: {
        totalRepos: entries.length,
        readyForWorkCount,
        runningCount: entries.filter(entry => entry.lifecycleState === 'running').length,
        blockedCount: entries.filter(entry => ['needs-readme', 'needs-roadmap', 'needs-roadmap-repair', 'needs-structure', 'parse-error'].includes(entry.lifecycleState)).length,
        completedCount: entries.filter(entry => entry.lifecycleState === 'completed').length,
        averageMaturityScore,
        averageDocumentationHealthScore: entries.length > 0
          ? Math.round(entries.reduce((sum, entry) => sum + Number(entry.documentationHealthScore ?? 0), 0) / entries.length)
          : 0,
        improvedThisWeek: 0,
      },
      series,
      topCandidates,
      repoSparklines,
    };
  }

  const qs = new URLSearchParams();
  if (options.days != null) {
    qs.set('days', String(options.days));
  }
  const suffix = qs.toString() ? `?${qs.toString()}` : '';
  const data = await fetchJson<any>(`${API_BASE_URL}/portfolio/trend${suffix}`);
  const d = data?.data ?? data ?? {};
  return {
    trendStatus: d.trendStatus === 'history-backed' ? 'history-backed' : 'current-snapshot-only',
    seedSource: d.seedSource === 'portfolio-index' ? 'portfolio-index' : 'assessment-cache',
    requestedDays: Number(d.requestedDays ?? options.days ?? 90),
    availableDays: Number(d.availableDays ?? 1),
    generatedAt: String(d.generatedAt ?? new Date().toISOString()),
    note: d.note ?? null,
    summary: {
      totalRepos: Number(d.summary?.totalRepos ?? 0),
      readyForWorkCount: Number(d.summary?.readyForWorkCount ?? 0),
      runningCount: Number(d.summary?.runningCount ?? 0),
      blockedCount: Number(d.summary?.blockedCount ?? 0),
      completedCount: Number(d.summary?.completedCount ?? 0),
      averageMaturityScore: Number(d.summary?.averageMaturityScore ?? 0),
      averageDocumentationHealthScore: Number(d.summary?.averageDocumentationHealthScore ?? 0),
      improvedThisWeek: Number(d.summary?.improvedThisWeek ?? 0),
    },
    series: Array.isArray(d.series)
      ? d.series.map((series: any): PortfolioTrendSeries => ({
          key: series?.key === 'readyRepos' ? 'readyRepos' : 'avgMaturityScore',
          label: String(series?.label ?? ''),
          color: String(series?.color ?? 'emerald'),
          points: Array.isArray(series?.points)
            ? series.points.map((point: any) => ({
                date: String(point?.date ?? new Date().toISOString().slice(0, 10)),
                value: Number(point?.value ?? 0),
              }))
            : [],
        }))
      : [],
    topCandidates: Array.isArray(d.topCandidates)
      ? d.topCandidates.map((candidate: any): PortfolioTrendTopCandidate => ({
          repoName: String(candidate?.repoName ?? ''),
          lifecycleState: candidate?.lifecycleState ?? 'discovered',
          maturityLevel: candidate?.maturityLevel ?? 'L0-Absent',
          maturityScore: Number(candidate?.maturityScore ?? 0),
          documentationHealthScore: Number(candidate?.documentationHealthScore ?? 0),
          pendingItemCount: Number(candidate?.pendingItemCount ?? 0),
          topValueItemText: String(candidate?.topValueItemText ?? ''),
          valueScore: Number(candidate?.valueScore ?? 0),
          recommendedAction: String(candidate?.recommendedAction ?? ''),
        }))
      : [],
    repoSparklines: Array.isArray(d.repoSparklines)
      ? d.repoSparklines.map((sparkline: any): PortfolioTrendRepoSparkline => ({
          repoName: String(sparkline?.repoName ?? ''),
          lifecycleState: sparkline?.lifecycleState ?? 'discovered',
          maturityLevel: sparkline?.maturityLevel ?? 'L0-Absent',
          currentScore: Number(sparkline?.currentScore ?? 0),
          points: Array.isArray(sparkline?.points)
            ? sparkline.points.map((point: any) => ({
                date: String(point?.date ?? new Date().toISOString().slice(0, 10)),
                value: Number(point?.value ?? 0),
              }))
            : [],
          topValueItemText: String(sparkline?.topValueItemText ?? ''),
          recommendedAction: String(sparkline?.recommendedAction ?? ''),
        }))
      : [],
  };
}

export async function getOperationsRepos(): Promise<OperationsReposResult> {
  if (USE_MOCK_API) {
    return getMockOperationsRepos();
  }

  const data = await fetchJson<any>(`${API_BASE_URL}/operations/repos`);
  const d = data?.data ?? data ?? {};
  return {
    entries: Array.isArray(d.entries) ? d.entries.map(normalizeOperationsRepoEntry) : [],
    generatedAt: String(d.generatedAt ?? new Date().toISOString()),
    count: Number(d.count ?? 0),
    cacheSource: d.cacheSource === 'assessment-cache' ? 'assessment-cache' : 'portfolio-index',
    summary: d.summary ?? null,
  };
}

export async function getOperationsRepoDetail(repoId: string): Promise<OperationsRepoDetail> {
  const trimmedRepoId = repoId.trim();
  if (!trimmedRepoId) {
    throw new Error('repoId is required for operations repo detail.');
  }

  if (USE_MOCK_API) {
    const repos = getMockOperationsRepos();
    const matched = repos.entries.find(entry => entry.repoId === trimmedRepoId) ?? repos.entries[0];
    if (!matched) {
      throw new Error('No mock operations repo entries are available.');
    }

    return normalizeOperationsRepoDetail({
      repoId: matched.repoId,
      repo: matched,
      documentationContext: {
        hasReadme: matched.hasReadme,
        readmeLastWriteUtc: matched.readmeLastWriteUtc,
        hasRoadmap: matched.hasRoadmap,
        roadmapPath: matched.roadmapPath,
        roadmapLastWriteUtc: matched.roadmapLastWriteUtc,
        docFindingCount: matched.docFindingCount,
        structureFindings: matched.structureFindings,
      },
      docAudit: {
        auditedAt: null,
        dispatchReadiness: matched.dispatchReadiness,
        criticalCount: 0,
        warningCount: 0,
        infoCount: 0,
        findings: [],
      },
      roadmapAudit: {
        auditedAt: null,
        roadmapState: matched.roadmapState,
        maturityLevel: matched.maturityLevel,
        maturityScore: matched.maturityScore,
        pendingCount: matched.pendingItemCount,
        nextPendingItem: null,
        auditFindings: [],
      },
      dispatchContext: {
        dispatchReadiness: matched.dispatchReadiness,
        dispatchReadinessExplanation: matched.dispatchReadinessExplanation,
        recommendedAction: matched.recommendedAction,
        blockingReasons: matched.blockingReasons,
        pendingItemCount: matched.pendingItemCount,
        nextPendingItemText: matched.nextPendingItemText,
        topValueItem: matched.topValueItem,
      },
    });
  }

  const encodedRepoId = encodeURIComponent(trimmedRepoId);
  const data = await fetchJson<any>(`${API_BASE_URL}/operations/repos/${encodedRepoId}`);
  const d = data?.data ?? data;
  if (!d) {
    throw new Error('Operations repo detail response is empty.');
  }

  return normalizeOperationsRepoDetail(d);
}

export async function refineOperationsPrompt(request: OperationsPromptRefineRequest): Promise<OperationsPromptRefineResult> {
  const repoName = request.repoName.trim();
  if (!repoName) {
    throw new Error('repoName is required for prompt refinement.');
  }

  const body = {
    repoName,
    roadmapPath: request.roadmapPath ?? '',
    selectedTaskText: request.selectedTaskText ?? '',
    selectedTaskSection: request.selectedTaskSection ?? '',
    additionalConstraints: Array.isArray(request.additionalConstraints) ? request.additionalConstraints : [],
    emphasisAreas: Array.isArray(request.emphasisAreas) ? request.emphasisAreas : [],
    operatorInstructions: request.operatorInstructions ?? '',
  };

  const data = await postJson<any>('/operations/prompt/refine', body);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Operations prompt refinement failed.');
  }

  const d = data.data ?? {};
  if (!d.packet || !d.refinedPrompt) {
    throw new Error('Operations prompt refinement response is missing required fields.');
  }

  return {
    runId: d.runId ? String(d.runId) : undefined,
    createdAt: d.createdAt ? String(d.createdAt) : undefined,
    packet: d.packet as CopilotTaskPacket,
    refinedPrompt: String(d.refinedPrompt),
    warnings: Array.isArray(d.warnings) ? d.warnings : [],
    applied: {
      selectedTaskText: String(d.applied?.selectedTaskText ?? ''),
      selectedTaskSection: String(d.applied?.selectedTaskSection ?? ''),
      additionalConstraints: Array.isArray(d.applied?.additionalConstraints) ? d.applied.additionalConstraints.map((value: unknown) => String(value)) : [],
      emphasisAreas: Array.isArray(d.applied?.emphasisAreas) ? d.applied.emphasisAreas.map((value: unknown) => String(value)) : [],
      operatorInstructions: d.applied?.operatorInstructions ? String(d.applied.operatorInstructions) : undefined,
    },
  };
}

export async function getOperationsPromptHistory(repoName: string, limit = 20): Promise<OperationsPromptHistoryItem[]> {
  const trimmedRepoName = repoName.trim();
  if (!trimmedRepoName) {
    return [];
  }

  const url = `${API_BASE_URL}/operations/prompt/history?repoName=${encodeURIComponent(trimmedRepoName)}&limit=${limit}`;
  const data = await fetchJson<any>(url);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Operations prompt history request failed.');
  }

  const items = Array.isArray(data?.data?.items) ? data.data.items : [];
  return items.map((item: any) => ({
    runId: String(item?.runId ?? ''),
    createdAt: String(item?.createdAt ?? ''),
    repoName: String(item?.repoName ?? trimmedRepoName),
    selectedItemText: String(item?.selectedItemText ?? ''),
    selectedItemSection: String(item?.selectedItemSection ?? ''),
    selectionSource: String(item?.selectionSource ?? 'roadmap-order') as OperationsPromptHistoryItem['selectionSource'],
    operatorInstructions: item?.operatorInstructions ? String(item.operatorInstructions) : undefined,
    additionalConstraints: Array.isArray(item?.additionalConstraints) ? item.additionalConstraints.map((value: unknown) => String(value)) : [],
    emphasisAreas: Array.isArray(item?.emphasisAreas) ? item.emphasisAreas.map((value: unknown) => String(value)) : [],
    warningCount: Number(item?.warningCount ?? 0),
    dispatchCount: Number(item?.dispatchCount ?? 0),
    latestDispatchAt: item?.latestDispatchAt ? String(item.latestDispatchAt) : null,
    dispatchRecords: Array.isArray(item?.dispatchRecords) ? item.dispatchRecords.map((record: any) => ({
      promptRefinementRunId: String(record?.promptRefinementRunId ?? ''),
      dispatchRunId: String(record?.dispatchRunId ?? ''),
      repoName: String(record?.repoName ?? trimmedRepoName),
      githubRepo: String(record?.githubRepo ?? ''),
      status: String(record?.status ?? 'started') as OperationsPromptHistoryItem['dispatchRecords'][number]['status'],
      startedAt: String(record?.startedAt ?? ''),
      recordedAt: String(record?.recordedAt ?? ''),
      localPath: record?.localPath ? String(record.localPath) : null,
      baseBranch: record?.baseBranch ? String(record.baseBranch) : null,
    })) : [],
  }));
}

export async function setOperationsRepoCuration(
  repoId: string,
  curationState: OperationsRepoEntry['curationState'],
  reason?: string,
): Promise<{ repoId: string; curationState: OperationsRepoEntry['curationState']; updatedAt: string }> {
  const trimmedRepoId = repoId.trim();
  if (!trimmedRepoId) {
    throw new Error('repoId is required for operations curation update.');
  }

  const data = await postJson<any>(`/operations/repos/${encodeURIComponent(trimmedRepoId)}/curation`, {
    curationState,
    reason: reason ?? '',
  });

  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Operations curation update failed.');
  }

  const d = data?.data ?? {};
  return {
    repoId: String(d.repoId ?? trimmedRepoId),
    curationState: (d.curationState ?? curationState) as OperationsRepoEntry['curationState'],
    updatedAt: String(d.updatedAt ?? new Date().toISOString()),
  };
}

// --- Release 1.9: AI documentation improvement cycles ---

function normalizeAiDocTemplate(raw: any): AiDocTemplate {
  return {
    id: String(raw?.id ?? ''),
    label: String(raw?.label ?? ''),
    summary: String(raw?.summary ?? ''),
    guidance: String(raw?.guidance ?? ''),
    requiredSections: Array.isArray(raw?.requiredSections) ? raw.requiredSections.map((value: unknown) => String(value)) : [],
  };
}

export async function getAiDocTemplates(): Promise<AiDocTemplatesResult> {
  const data = await fetchJson<any>(`${API_BASE_URL}/ai/docs/templates`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'AI doc templates request failed.');
  }

  return {
    readmeTemplates: Array.isArray(data?.data?.readmeTemplates) ? data.data.readmeTemplates.map(normalizeAiDocTemplate) : [],
    roadmapTemplates: Array.isArray(data?.data?.roadmapTemplates) ? data.data.roadmapTemplates.map(normalizeAiDocTemplate) : [],
  };
}

export async function previewAiDocImprovement(request: AiDocImprovePreviewRequest): Promise<AiDocImprovePreviewResult> {
  const repoName = request.repoName.trim();
  if (!repoName) {
    throw new Error('repoName is required for AI documentation improvement.');
  }

  const body = {
    repoName,
    docType: request.docType,
    templateId: request.templateId ?? '',
    customPrompt: request.customPrompt ?? '',
    provider: request.provider ?? '',
    currentContent: request.currentContent ?? '',
    path: request.path ?? '',
  };

  const data = await postJson<any>('/ai/docs/improve/preview', body);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'AI documentation improvement preview failed.');
  }

  const preview = data.data ?? {};
  return {
    previewId: String(preview?.previewId ?? ''),
    repoName: String(preview?.repoName ?? repoName),
    docType: (String(preview?.docType ?? request.docType) === 'roadmap' ? 'roadmap' : 'readme'),
    providerId: String(preview?.providerId ?? ''),
    modelId: preview?.modelId ? String(preview.modelId) : null,
    templateId: String(preview?.templateId ?? ''),
    customPrompt: preview?.customPrompt ? String(preview.customPrompt) : null,
    currentContent: String(preview?.currentContent ?? ''),
    proposedContent: String(preview?.proposedContent ?? ''),
    changeSummary: Array.isArray(preview?.changeSummary) ? preview.changeSummary.map((value: unknown) => String(value)) : [],
    estimatedScore: {
      before: Number(preview?.estimatedScore?.before ?? 0),
      after: Number(preview?.estimatedScore?.after ?? 0),
      delta: Number(preview?.estimatedScore?.delta ?? 0),
    },
    warnings: Array.isArray(preview?.warnings) ? preview.warnings.map((value: unknown) => String(value)) : [],
    generatedAt: String(preview?.generatedAt ?? ''),
  };
}

export async function getAiDocImprovementHistory(repoName: string, options?: { docType?: 'readme' | 'roadmap'; limit?: number }): Promise<AiDocImprovementHistoryItem[]> {
  const trimmedRepoName = repoName.trim();
  if (!trimmedRepoName) {
    return [];
  }

  const params = new URLSearchParams({ repoName: trimmedRepoName, limit: String(options?.limit ?? 20) });
  if (options?.docType) {
    params.set('docType', options.docType);
  }

  const data = await fetchJson<any>(`${API_BASE_URL}/ai/docs/improve/history?${params.toString()}`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'AI documentation improvement history request failed.');
  }

  const items = Array.isArray(data?.data?.items) ? data.data.items : [];
  return items.map((item: any): AiDocImprovementHistoryItem => ({
    previewId: String(item?.previewId ?? ''),
    createdAt: String(item?.createdAt ?? ''),
    repoName: String(item?.repoName ?? trimmedRepoName),
    docType: (String(item?.docType ?? 'readme') === 'roadmap' ? 'roadmap' : 'readme'),
    providerId: String(item?.providerId ?? ''),
    modelId: item?.modelId ? String(item.modelId) : null,
    templateId: String(item?.templateId ?? ''),
    customPrompt: item?.customPrompt ? String(item.customPrompt) : null,
    scoreBefore: Number(item?.scoreBefore ?? 0),
    scoreAfter: Number(item?.scoreAfter ?? 0),
    scoreDelta: Number(item?.scoreDelta ?? 0),
    changeSummary: Array.isArray(item?.changeSummary) ? item.changeSummary.map((value: unknown) => String(value)) : [],
    warningCount: Number(item?.warningCount ?? 0),
    applied: Boolean(item?.applied ?? false),
    recordType: String(item?.recordType ?? '') === 'apply' ? 'apply' : 'preview',
    backupPath: item?.backupPath ? String(item.backupPath) : null,
  }));
}

export async function applyAiDocImprovement(request: AiDocImproveApplyRequest): Promise<AiDocImproveApplyResult> {
  const repoName = request.repoName.trim();
  if (!repoName) {
    throw new Error('repoName is required to apply a documentation improvement.');
  }
  if (!request.proposedContent || !request.proposedContent.trim()) {
    throw new Error('proposedContent is required — apply writes only operator-approved content.');
  }

  const body = {
    repoName,
    docType: request.docType,
    proposedContent: request.proposedContent,
    previewId: request.previewId ?? '',
    path: request.path ?? '',
  };

  const data = await postJson<any>('/ai/docs/improve/apply', body);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'AI documentation improvement apply failed.');
  }

  const result = data.data ?? {};
  return {
    applyId: String(result?.applyId ?? ''),
    repoName: String(result?.repoName ?? repoName),
    docType: (String(result?.docType ?? request.docType) === 'roadmap' ? 'roadmap' : 'readme'),
    targetPath: String(result?.targetPath ?? ''),
    backupPath: result?.backupPath ? String(result.backupPath) : null,
    restoreMetadataPath: result?.restoreMetadataPath ? String(result.restoreMetadataPath) : null,
    originalExisted: Boolean(result?.originalExisted ?? false),
    previewId: result?.previewId ? String(result.previewId) : null,
    appliedAt: String(result?.appliedAt ?? ''),
  };
}

// --- Release 2.0: Agent run monitoring ---

export async function getAgentRuns(options?: { status?: string; repoName?: string; limit?: number }): Promise<AgentRunsResult> {
  const params = new URLSearchParams();
  if (options?.status) params.set('status', options.status);
  if (options?.repoName) params.set('repoName', options.repoName);
  if (options?.limit) params.set('limit', String(options.limit));
  const qs = params.toString() ? `?${params.toString()}` : '';

  const data = await fetchJson<any>(`${API_BASE_URL}/agent-runs${qs}`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Failed to load agent runs.');
  }

  const payload = data.data ?? {};
  return {
    items: Array.isArray(payload?.items) ? (payload.items as AgentRun[]) : [],
    count: Number(payload?.count ?? 0),
    byStatus: (payload?.byStatus ?? {}) as Record<string, number>,
  };
}

export async function getAgentRunDetail(runId: string): Promise<AgentRunDetailResult> {
  if (!runId.trim()) {
    throw new Error('runId is required to load agent run detail.');
  }

  const data = await fetchJson<any>(`${API_BASE_URL}/agent-runs/${encodeURIComponent(runId)}`);
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Failed to load agent run detail.');
  }

  const payload = data.data ?? {};
  return {
    run: payload?.run as AgentRun,
    events: Array.isArray(payload?.events) ? payload.events : [],
  };
}

/** Returns the stored merge-readiness snapshot, or null when the repo has never been evaluated. */
export async function getMergeReadiness(repoId: string): Promise<MergeReadinessResult | null> {
  if (!repoId.trim()) {
    throw new Error('repoId is required to load merge readiness.');
  }

  const response = await fetch(`${API_BASE_URL}/merge-readiness/${encodeURIComponent(repoId)}`);
  if (response.status === 404) {
    return null;
  }
  const text = await response.text();
  let payload: any;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = null; }
  if (!response.ok || !payload?.success) {
    throw new Error(payload?.error?.message ?? payload?.error ?? `Failed to load merge readiness (HTTP ${response.status}).`);
  }
  return payload.data as MergeReadinessResult;
}

export async function evaluateMergeReadiness(repoId: string): Promise<MergeReadinessResult> {
  if (!repoId.trim()) {
    throw new Error('repoId is required to evaluate merge readiness.');
  }

  const data = await postJson<any>(`/merge-readiness/${encodeURIComponent(repoId)}/evaluate`, {});
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Merge-readiness evaluation failed.');
  }
  return data.data as MergeReadinessResult;
}

/** Operator merge action. The server re-evaluates readiness and refuses (409) unless every blocker is resolved. */
export async function executeMergeReadinessMerge(repoId: string): Promise<MergeReadinessMergeResult> {
  if (!repoId.trim()) {
    throw new Error('repoId is required to merge.');
  }

  const data = await postJson<any>(`/merge-readiness/${encodeURIComponent(repoId)}/merge`, {});
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Merge was refused or failed.');
  }
  return data.data as MergeReadinessMergeResult;
}

export async function refreshAgentRun(runId: string): Promise<AgentRunRefreshResult> {
  if (!runId.trim()) {
    throw new Error('runId is required to refresh an agent run.');
  }

  const data = await postJson<any>(`/agent-runs/${encodeURIComponent(runId)}/refresh`, {});
  if (!data?.success) {
    throw new Error(data?.error?.message ?? data?.error ?? 'Agent run refresh failed.');
  }

  const payload = data.data ?? {};
  return {
    run: payload?.run as AgentRun,
    association: payload?.association ?? { matchedBy: [], candidateCount: 0, associatedAt: '' },
    pullRequestFound: Boolean(payload?.pullRequestFound ?? false),
    validationEvent: payload?.validationEvent ? String(payload.validationEvent) : null,
    refreshedAt: String(payload?.refreshedAt ?? ''),
  };
}

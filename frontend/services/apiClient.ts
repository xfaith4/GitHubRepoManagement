import { type RepoStatus, type AppSettings, type Artifact, type GithubInsightsMeta } from '../types';

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
    htmlUrl: repo?.htmlUrl,
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
    reportPath: 'backend\\modules\\output',
    staleThreshold: 14,
    daysInactive: Number(root?.retention?.days ?? 30),
    zipArchive: true,
    scanDepth: Number(root?.inventory?.maxDepth ?? 3),
    githubUser: (root?.reconcile?.gitHubOwner as string | undefined) ?? '',
    githubToken: ''
  };
}

export async function getStatus(): Promise<{ repos: RepoStatus[]; source: 'sample' | 'local'; workspacePath?: string; configuredGithubUser?: string | null; }> {
  if (USE_MOCK_API) {
    return { repos: getMockRepos(), source: 'sample', configuredGithubUser: null, workspacePath: undefined };
  }

  const data = await fetchJson<any>(`${API_BASE_URL}/status`);
  const repos = Array.isArray(data?.data?.repos) ? data.data.repos.map(normalizeRepo) : [];
  return {
    repos,
    source: 'local',
    workspacePath: undefined,
    configuredGithubUser: null
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

export async function startUpdate(repoNames?: string[]): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/update', { repoNames });
}

export async function startSync(repoNames?: string[]): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/sync', { repoNames });
}

export async function startExport(): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/export', {});
}

export function getReportDownloadUrl(repos: RepoStatus[]): string {
  const headers = 'Repository,Branch,Status,LastCommitDate,UncommittedChanges\n';
  const rows = repos.map(r => [r.name, r.branch, r.status, r.lastCommitDate, r.uncommittedChanges].map(v => `"${String(v ?? '')}"`).join(',')).join('\n');
  return `data:text/csv;charset=utf-8,${encodeURIComponent(headers + rows)}`;
}

export function getPowerBIReportUrl(repos: RepoStatus[]): string {
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>Repo Report</title></head><body><h1>Repository Report</h1><pre>${JSON.stringify(repos, null, 2)}</pre></body></html>`;
  return `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;
}

export async function startArchive(daysInactive: number, zipArchive: boolean, repoNames?: string[]): Promise<void> {
  if (USE_MOCK_API) return;
  await postJson('/archive', { daysInactive, zipArchive, repoNames });
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
  reportPath: 'backend\\modules\\output',
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

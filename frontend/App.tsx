import React, { useState, useCallback, useEffect, useRef } from 'react';
import Dashboard from './components/Dashboard';
import DataSourceModal from './components/DataSourceModal';
import SetupWizard from './components/SetupWizard';
import AgentActivityIndicator from './components/AgentActivityIndicator';
import MobileRepoHealth from './components/MobileRepoHealth';
import OrientationOverlay, { hasSeenOrientation } from './components/OrientationOverlay';
import { getStatus, getGithubRepoInsights, getSetupStatus } from './services/apiClient';
import { type RepoStatus, type GithubInsightsMeta } from './types';
import { DatabaseIcon } from './components/icons';

function formatRelativeTime(date: Date): string {
  const diffMs = Date.now() - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  if (diffSec < 5) return 'just now';
  if (diffSec < 60) return `${diffSec}s ago`;
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  return `${Math.floor(diffHr / 24)}d ago`;
}

function App() {
  const [viewMode, setViewMode] = useState<'local' | 'github'>('local');

  // Release 2.2 — first-run detection. null = still checking; true = show the
  // guided Setup Wizard. `?setup=1` forces it (for preview / smoke coverage).
  const [showSetup, setShowSetup] = useState<boolean | null>(null);
  useEffect(() => {
    const forced = typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('setup') === '1';
    if (forced) { setShowSetup(true); return; }
    let cancelled = false;
    getSetupStatus()
      .then(s => { if (!cancelled) setShowSetup(Boolean(s.needsSetup)); })
      .catch(() => { if (!cancelled) setShowSetup(false); });
    return () => { cancelled = true; };
  }, []);

  // First-visit orientation overlay (Release 2.6 Phase 2). Shown once the
  // setup check clears (showSetup === false) and only if never dismissed.
  const [showOrientation, setShowOrientation] = useState(false);
  useEffect(() => {
    if (showSetup === false && !hasSeenOrientation()) {
      setShowOrientation(true);
    }
  }, [showSetup]);

  const [localRepos, setLocalRepos] = useState<RepoStatus[]>([]);
  const [localSource, setLocalSource] = useState<{ source: 'sample' } | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number } | null>(null);

  const [githubRepos, setGithubRepos] = useState<RepoStatus[]>([]);
  const [githubSource, setGithubSource] = useState<{ source: 'github'; username: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [isBackgroundRefreshing, setIsBackgroundRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isDataSourceModalOpen, setIsDataSourceModalOpen] = useState(false);
  const [insightsMeta, setInsightsMeta] = useState<GithubInsightsMeta | null>(null);
  const [dataLastUpdated, setDataLastUpdated] = useState<Date | null>(null);
  const [relativeTime, setRelativeTime] = useState<string>('');
  const githubCredentialsRef = useRef<{ username: string; apiKey?: string } | null>(null);

  // Apply local repo data returned from getStatus() to component state.
  const applyLocalData = useCallback((localData: Awaited<ReturnType<typeof getStatus>>) => {
    setLocalRepos(localData.repos);
    if (localData.dataLastUpdated) {
      setDataLastUpdated(new Date(localData.dataLastUpdated));
    }
    if (localData.source === 'sample') {
      setLocalSource({ source: 'sample' });
    } else {
      setLocalSource({
        source: 'local',
        workspacePath: localData.workspacePath,
        configuredGithubUser: localData.configuredGithubUser,
        repoCount: localData.repoCount,
        scanDurationMs: localData.scanDurationMs
      });
    }
  }, []);

  // fetchRepoStatus — called explicitly by Dashboard after user-triggered operations.
  // Always requests a fresh scan (bypasses cache) so post-operation results are current.
  const fetchRepoStatus = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const localData = await getStatus({ refresh: true });
      applyLocalData(localData);

      const clearGithubData = () => {
        setGithubRepos([]);
        setGithubSource(null);
        setInsightsMeta(null);
      };

      const activeGithubUsername = githubCredentialsRef.current?.username?.trim()
        || (localData.source === 'local' ? localData.configuredGithubUser?.trim() ?? '' : '');
      const activeGithubApiKey = githubCredentialsRef.current?.apiKey?.trim() || undefined;

      if (activeGithubUsername) {
        try {
          const data = await getGithubRepoInsights({
            githubUser: activeGithubUsername,
            apiKey: activeGithubApiKey,
            includePrivate: true,
            includeForks: false,
            repoLimit: 50,
            fetchExtendedMetrics: true
          });
          setGithubRepos(data.repos);
          setGithubSource({ source: 'github', username: data.username });
          setInsightsMeta({
            totalRepos: data.totalRepos,
            fetchedRepos: data.fetchedRepos,
            rateLimit: data.rateLimit
          });
        } catch (githubError) {
          clearGithubData();
          if (githubCredentialsRef.current?.username) {
            throw githubError;
          }
          console.warn('Automatic GitHub scan skipped.', githubError);
        }
      } else {
        clearGithubData();
      }
    } catch (err) {
      console.error(err);
      const message = err instanceof Error ? err.message : 'Failed to fetch repository status.';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [applyLocalData]);

  // Initial load: two-phase stale-while-revalidate.
  // Phase 1 — serve cached data immediately (no TTL check) so the UI is never blank on launch.
  // Phase 2 — background refresh to pick up any changes since the last scan.
  useEffect(() => {
    let cancelled = false;

    const doInitialLoad = async () => {
      setLoading(true);
      setError(null);
      try {
        // Phase 1: return whatever is on disk, regardless of TTL
        const localData = await getStatus({ stale: true });
        if (cancelled) return;
        applyLocalData(localData);
      } catch (err) {
        if (cancelled) return;
        const message = err instanceof Error ? err.message : 'Failed to fetch repository status.';
        setError(message);
      } finally {
        if (!cancelled) setLoading(false);
      }

      if (cancelled) return;

      // Phase 2: silently refresh in the background so we always end up with
      // current data. This is the differential re-scan — it is indicated on the
      // front page (header badge + Dashboard banner), never in a blocking
      // drawer. A timeout keeps a hung backend scan from spinning forever; on
      // timeout we simply keep showing the cached list already on screen.
      setIsBackgroundRefreshing(true);
      try {
        const freshData = await getStatus({ refresh: true, timeoutMs: 90_000 });
        if (cancelled) return;
        applyLocalData(freshData);
      } catch (refreshErr) {
        console.warn('Background differential re-scan did not complete; showing cached data.', refreshErr);
      } finally {
        if (!cancelled) setIsBackgroundRefreshing(false);
      }
    };

    doInitialLoad();
    return () => { cancelled = true; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!dataLastUpdated) return;
    setRelativeTime(formatRelativeTime(dataLastUpdated));
    const timer = setInterval(() => {
      setRelativeTime(formatRelativeTime(dataLastUpdated));
    }, 15000);
    return () => clearInterval(timer);
  }, [dataLastUpdated]);

  const handleDataSourceChange = async (username: string, apiKey?: string) => {
    setLoading(true);
    setError(null);
    try {
      const normalizedApiKey = apiKey?.trim() ? apiKey.trim() : undefined;
      const data = await getGithubRepoInsights({
        githubUser: username,
        apiKey: normalizedApiKey,
        includePrivate: true,
        includeForks: false,
        repoLimit: 50,
        fetchExtendedMetrics: true
      });
      githubCredentialsRef.current = { username, apiKey: normalizedApiKey };
      setGithubRepos(data.repos);
      setGithubSource({ source: 'github', username: data.username });
      setInsightsMeta({
        totalRepos: data.totalRepos,
        fetchedRepos: data.fetchedRepos,
        rateLimit: data.rateLimit
      });
      setViewMode('github');
    } catch (err) {
      githubCredentialsRef.current = null;
      console.error(err);
      const message = err instanceof Error ? err.message : 'Failed to fetch GitHub repository data.';
      setError(message);
      throw err;
    } finally {
      setLoading(false);
    }
  };

  // Persistent, color-coded data-source indicator (Release 2.6 Phase 1).
  // Rendered in the sticky header shell so it stays visible on every tab —
  // including Operations, which changes what is shown without touching this
  // active-source signal. Color-coded (Local = emerald, GitHub = violet,
  // Sample = amber) so the Local-vs-GitHub distinction is impossible to lose.
  const renderDataSourceLabel = () => {
    const activeSource = viewMode === 'github' && githubSource ? githubSource : localSource;
    if (!activeSource) return null;

    const updatedBadge = relativeTime ? (
      <span className="opacity-70 hidden sm:inline" title={dataLastUpdated?.toLocaleString()}>
        • {relativeTime}
      </span>
    ) : null;

    const kind: 'sample' | 'local' | 'github' = activeSource.source;
    const shortLabel = kind === 'sample' ? 'Sample' : kind === 'local' ? 'Local' : 'GitHub';

    const palette: Record<typeof kind, string> = {
      sample: 'bg-amber-900/60 text-amber-200 border-amber-600',
      local: 'bg-emerald-900/60 text-emerald-200 border-emerald-600',
      github: 'bg-violet-900/60 text-violet-200 border-violet-600',
    };
    const dotColor: Record<typeof kind, string> = {
      sample: 'bg-amber-400',
      local: 'bg-emerald-400',
      github: 'bg-violet-400',
    };

    let detail: React.ReactNode = null;
    let titleText: string;
    if (activeSource.source === 'sample') {
      titleText = 'Showing bundled sample data (no live source connected).';
    } else if (activeSource.source === 'local') {
      detail = activeSource.workspacePath
        ? <span className="hidden lg:inline opacity-80">• {activeSource.workspacePath}</span>
        : null;
      titleText = `Showing repositories from the local workspace scan${activeSource.workspacePath ? ' — ' + activeSource.workspacePath : ''}. This stays the active source across every tab, including Operations.`;
    } else {
      detail = <span className="hidden lg:inline opacity-80">• {activeSource.username}</span>;
      titleText = `Showing repositories returned by the GitHub API for ${activeSource.username}.`;
    }

    return (
      <span
        data-testid="data-source-indicator"
        data-source-kind={kind}
        title={titleText}
        className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold border ${palette[kind]}`}
      >
        <span className={`w-2 h-2 rounded-full ${dotColor[kind]}`} aria-hidden="true"></span>
        <span>Source: {shortLabel}</span>
        {detail}
        {updatedBadge}
      </span>
    );
  };

  const renderViewToggle = () => {
    const githubEnabled = Boolean(githubSource);
    return (
      <div className="ml-3 inline-flex rounded-md border border-gray-600 overflow-hidden">
        <button
          type="button"
          onClick={() => setViewMode('local')}
          className={`px-3 py-1.5 text-sm font-medium transition-colors ${
            viewMode === 'local' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
          }`}
          title="Show repositories discovered in the local workspace"
        >
          Local
        </button>
        <button
          type="button"
          onClick={() => githubEnabled && setViewMode('github')}
          disabled={!githubEnabled}
          className={`px-3 py-1.5 text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${
            viewMode === 'github' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
          }`}
          title={githubEnabled ? 'Show repositories returned by the GitHub API' : 'Connect GitHub API to enable this view'}
        >
          GitHub
        </button>
      </div>
    );
  };

  if (showSetup) {
    return (
      <SetupWizard
        onComplete={() => {
          setShowSetup(false);
          // Trigger the first scan now that settings.json exists.
          fetchRepoStatus();
          // Drop the ?setup=1 preview param if present.
          if (typeof window !== 'undefined' && window.history?.replaceState) {
            window.history.replaceState({}, '', window.location.pathname);
          }
        }}
      />
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 text-gray-200 font-sans">
      <header className="bg-gray-800/50 backdrop-blur-sm sticky top-0 z-20 border-b border-gray-700">
        <div className="container mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex flex-wrap items-center justify-between gap-y-2 py-2 min-h-16 md:py-0">
            <div className="flex items-center min-w-0">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8 text-blue-400 mr-3 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"></path></svg>
              <h1 className="text-lg sm:text-xl font-bold text-gray-100 truncate">GitHub Repo Manager</h1>
            </div>
            <div className="flex items-center gap-2">
                <AgentActivityIndicator />
                <span className="inline-flex">{renderDataSourceLabel()}</span>
                {isBackgroundRefreshing && (
                  <span className="ml-2 inline-flex items-center gap-1.5 text-xs text-blue-400" title="Refreshing repository data in the background…">
                    <svg className="animate-spin h-3.5 w-3.5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4l3-3-3-3v4a8 8 0 00-8 8h4z"/>
                    </svg>
                    Refreshing…
                  </span>
                )}
                {renderViewToggle()}
                <button
                  onClick={() => setIsDataSourceModalOpen(true)}
                  className="ml-3 inline-flex items-center px-3 py-2 md:py-1.5 border border-gray-600 rounded-md text-sm font-medium text-gray-300 bg-gray-700 hover:bg-gray-600 transition-colors"
                  title="Connect to GitHub API using a typed token, GITHUB_TOKEN, or the saved fallback token"
                >
                  <DatabaseIcon className="w-4 h-4 sm:mr-2" />
                  <span className="hidden sm:inline">GitHub API</span>
                </button>
            </div>
          </div>
        </div>
      </header>
      <main>
        <MobileRepoHealth />
        <Dashboard
            repos={viewMode === 'github' && githubSource ? githubRepos : localRepos}
            loading={loading}
            isBackgroundRefreshing={isBackgroundRefreshing}
            error={error}
            fetchRepoStatus={fetchRepoStatus}
            dataSource={viewMode === 'github' && githubSource ? githubSource : localSource}
            insightsMeta={viewMode === 'github' && githubSource ? insightsMeta : null}
            dataLastUpdated={dataLastUpdated}
        />
      </main>
      <footer className="text-center py-4 text-gray-500 text-sm border-t border-gray-800 mt-8">
        <p>GitHub Repo Manager | Local-First Edition</p>
      </footer>
      
      <DataSourceModal
        isOpen={isDataSourceModalOpen}
        onClose={() => setIsDataSourceModalOpen(false)}
        onSave={handleDataSourceChange}
        currentUsername={githubSource?.username ?? (localSource?.source === 'local' ? localSource.configuredGithubUser ?? undefined : undefined)}
      />

      {showOrientation && <OrientationOverlay onDismiss={() => setShowOrientation(false)} />}
    </div>
  );
}

export default App;

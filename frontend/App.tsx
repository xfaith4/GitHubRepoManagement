import React, { useState, useCallback, useEffect, useRef } from 'react';
import Dashboard from './components/Dashboard';
import SetupWizard from './components/SetupWizard';
import Login from './components/Login';
import AgentActivityIndicator from './components/AgentActivityIndicator';
import RunnerHealthIndicator from './components/RunnerHealthIndicator';
import TransportSecurityIndicator from './components/TransportSecurityIndicator';
import MobileRepoHealth from './components/MobileRepoHealth';
import OrientationOverlay, { hasSeenOrientation } from './components/OrientationOverlay';
import { getStatus, getGithubRepoInsights, getSetupStatus, getAuthStatus, logout, type AuthStatus } from './services/apiClient';
import { type RepoStatus, type GithubInsightsMeta } from './types';
import { HelpIcon, SettingsIcon } from './components/icons';

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

  // Release 2.7 — auth gate. 'checking' until /api/auth/status resolves; 'required'
  // when the portal is protected and this browser is not authenticated; 'ok' once
  // authenticated (or when the host runs open). API-key browsers report
  // authenticated=true here, so only truly-unauthenticated visitors see Login.
  const [authState, setAuthState] = useState<'checking' | 'required' | 'ok'>('checking');
  const [authStatus, setAuthStatus] = useState<AuthStatus | null>(null);
  const refreshAuth = useCallback(async () => {
    try {
      const s = await getAuthStatus();
      setAuthStatus(s);
      setAuthState(s.gateEnabled && !s.authenticated ? 'required' : 'ok');
    } catch {
      // Status endpoint unreachable (e.g. older host) — don't lock the operator
      // out; let requests proceed and surface any 401s in context.
      setAuthState('ok');
    }
  }, []);
  useEffect(() => { void refreshAuth(); }, [refreshAuth]);

  const handleLogout = useCallback(async () => {
    await logout();
    await refreshAuth();
  }, [refreshAuth]);

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
  const [localSource, setLocalSource] = useState<{ source: 'sample' } | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number; missingRoots?: string[] } | null>(null);

  const [githubRepos, setGithubRepos] = useState<RepoStatus[]>([]);
  const [githubSource, setGithubSource] = useState<{ source: 'github'; username: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [isBackgroundRefreshing, setIsBackgroundRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // The Settings dialog lives in Dashboard (it owns the settings fetch), but the
  // gear that opens it now sits in this header. Incrementing this counter is the
  // open signal — a counter rather than a boolean so repeated clicks re-open the
  // dialog after it has been dismissed.
  const [settingsOpenRequest, setSettingsOpenRequest] = useState(0);
  // Help follows the same pattern, and for the same reason Settings did: it was
  // a button in the Repository Grid's action bar, so the guide — and the term
  // definitions, and the API reference — were unreachable from the six other
  // tabs. A counter, not a boolean, so a second click re-opens after dismissal.
  const [helpOpenRequest, setHelpOpenRequest] = useState(0);
  const [insightsMeta, setInsightsMeta] = useState<GithubInsightsMeta | null>(null);
  const [dataLastUpdated, setDataLastUpdated] = useState<Date | null>(null);
  const [relativeTime, setRelativeTime] = useState<string>('');
  // Only the owner is client-side state now; the token lives in the host's
  // environment under the variable named in Settings and never reaches here.
  const githubCredentialsRef = useRef<{ username: string } | null>(null);

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
        scanDurationMs: localData.scanDurationMs,
        missingRoots: localData.missingRoots ?? []
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
      if (activeGithubUsername) {
        try {
          const data = await getGithubRepoInsights({
            githubUser: activeGithubUsername,
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

  const handleDataSourceChange = async (username: string) => {
    setLoading(true);
    setError(null);
    try {
      const data = await getGithubRepoInsights({
        githubUser: username,
        includePrivate: true,
        includeForks: false,
        repoLimit: 50,
        fetchExtendedMetrics: true
      });
      githubCredentialsRef.current = { username };
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

  if (authState === 'checking') {
    return <div className="min-h-screen bg-gray-900" aria-busy="true" />;
  }

  if (authState === 'required' && authStatus) {
    return <Login status={authStatus} onAuthenticated={() => { void refreshAuth(); }} />;
  }

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
    <div className="min-h-screen bg-bg text-text font-sans">
      {/* Nocturne shell (MIGRATION.md §6): the header is full-bleed rather than
          centred in a container -- this is an operator console, and the whole
          width is working space. It wraps to a second line rather than
          clipping, so Help and Settings stay reachable at narrow widths; do not
          add `overflow-hidden` here. */}
      <header className="bg-bg/92 backdrop-blur-md sticky top-0 z-20 border-b border-text/10">
        <div className="px-5">
          <div className="flex flex-wrap items-center justify-between gap-y-2 py-2 min-h-16 md:py-0">
            <div className="flex items-center min-w-0">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-accent mr-2.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"></path></svg>
              <h1 className="text-sm font-medium text-text tracking-[-0.01em] truncate">GitHub Repo Manager</h1>
            </div>
            <div className="flex items-center gap-2">
                {/* Release 3.5 milestone 6 — runner health above the fold,
                    beside the agent-activity pill, on every tab. */}
                {/* The portal saying what it actually is. Rendered here rather
                    than only on the login screen, because a signed-in operator
                    never sees that screen again — which is how a broken
                    certificate ran for 19 days announced only in a service log. */}
                <TransportSecurityIndicator
                  transport={authStatus?.transport}
                  isLoopbackBind={authStatus?.isLoopbackBind}
                />
                <RunnerHealthIndicator />
                <AgentActivityIndicator />
                <span className="inline-flex">{renderDataSourceLabel()}</span>
                {isBackgroundRefreshing && (
                  <span role="status" aria-live="polite" className="ml-2 inline-flex items-center gap-1.5 text-xs text-blue-400" title="Refreshing repository data in the background…">
                    <svg className="animate-spin h-3.5 w-3.5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4l3-3-3-3v4a8 8 0 00-8 8h4z"/>
                    </svg>
                    Refreshing…
                  </span>
                )}
                {renderViewToggle()}
                {/* Help and Settings both moved out of the Repository Grid
                    toolbar and into the header, so they are reachable from every
                    tab rather than from one of seven. Help now carries the term
                    definitions and the API reference that used to be their own
                    grid-only buttons. */}
                <button
                  onClick={() => setHelpOpenRequest(n => n + 1)}
                  className="ml-3 inline-flex items-center px-2.5 py-2 md:py-1 border border-text/18 rounded-md text-[11.5px] font-medium text-text/72 bg-transparent hover:bg-text/6 hover:text-text transition-colors"
                  title="Guide, status-word definitions (Dirty, Stale, PRs, Blocked, L1–L4), and the backend API reference"
                  aria-label="Help"
                  data-testid="header-help-button"
                >
                  <HelpIcon className="w-4 h-4 sm:mr-2" />
                  <span className="hidden sm:inline">Help</span>
                </button>
                <button
                  onClick={() => setSettingsOpenRequest(n => n + 1)}
                  className="inline-flex items-center px-2.5 py-2 md:py-1 border border-text/18 rounded-md text-[11.5px] font-medium text-text/72 bg-transparent hover:bg-text/6 hover:text-text transition-colors"
                  title="Configure the local workspace path, scan depth, thresholds, and the GitHub API connection"
                  aria-label="Settings"
                  data-testid="header-settings-button"
                >
                  <SettingsIcon className="w-4 h-4 sm:mr-2" />
                  <span className="hidden sm:inline">Settings</span>
                </button>
                {authStatus?.method === 'session' && (
                  <button
                    onClick={() => { void handleLogout(); }}
                    className="inline-flex items-center px-2.5 py-2 md:py-1 border border-text/18 rounded-md text-[11.5px] font-medium text-text/72 bg-transparent hover:bg-text/6 hover:text-text transition-colors"
                    title="Sign out of the portal"
                    data-testid="logout-button"
                  >
                    <span className="hidden sm:inline">Sign out</span>
                    <span className="sm:hidden">Exit</span>
                  </button>
                )}
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
            settingsOpenRequest={settingsOpenRequest}
            helpOpenRequest={helpOpenRequest}
            onConnectGitHub={handleDataSourceChange}
            connectedGitHubUser={githubSource?.username ?? null}
        />
      </main>
      <footer className="text-center py-4 text-gray-500 text-sm border-t border-gray-800 mt-8">
        <p>GitHub Repo Manager | Local-First Edition</p>
      </footer>
      
      {showOrientation && <OrientationOverlay onDismiss={() => setShowOrientation(false)} />}
    </div>
  );
}

export default App;

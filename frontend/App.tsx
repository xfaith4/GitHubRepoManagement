import React, { useState, useCallback, useEffect, useRef } from 'react';
import Dashboard from './components/Dashboard';
import DataSourceModal from './components/DataSourceModal';
import { getStatus, getGithubRepoInsights } from './services/apiClient';
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

  const [localRepos, setLocalRepos] = useState<RepoStatus[]>([]);
  const [localSource, setLocalSource] = useState<{ source: 'sample' } | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number } | null>(null);

  const [githubRepos, setGithubRepos] = useState<RepoStatus[]>([]);
  const [githubSource, setGithubSource] = useState<{ source: 'github'; username: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isDataSourceModalOpen, setIsDataSourceModalOpen] = useState(false);
  const [insightsMeta, setInsightsMeta] = useState<GithubInsightsMeta | null>(null);
  const [dataLastUpdated, setDataLastUpdated] = useState<Date | null>(null);
  const [relativeTime, setRelativeTime] = useState<string>('');
  const githubCredentialsRef = useRef<{ username: string; apiKey?: string } | null>(null);

  const fetchRepoStatus = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const localData = await getStatus();
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
  }, []);

  useEffect(() => {
    fetchRepoStatus();
  }, [fetchRepoStatus]);

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

  const renderDataSourceLabel = () => {
    const activeSource = viewMode === 'github' && githubSource ? githubSource : localSource;
    if (!activeSource) return null;

    const updatedBadge = relativeTime ? (
      <span className="text-gray-400 text-xs" title={dataLastUpdated?.toLocaleString()}>
        • Updated: {relativeTime}
      </span>
    ) : null;

    if (activeSource.source === 'sample') {
      return (
        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-800 text-yellow-200 border border-yellow-700">
          Sample Data
        </span>
      );
    }

    if (activeSource.source === 'local') {
      return (
        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-700 text-gray-300 gap-2">
          <span>
            Local Scan{activeSource.workspacePath ? <strong className="ml-1">• {activeSource.workspacePath}</strong> : null}
          </span>
          {activeSource.configuredGithubUser ? (
            <span className="text-gray-400">• GitHub user configured: {activeSource.configuredGithubUser}</span>
          ) : null}
          {updatedBadge}
        </span>
      );
    }

    if (activeSource.source === 'github') {
      return (
        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-700 text-gray-300 gap-2">
          <span>
            GitHub API: <strong className="ml-1">{activeSource.username}</strong>
          </span>
          {insightsMeta?.rateLimit && (
            <span className="text-gray-400">
              • API {insightsMeta.rateLimit.remaining}/{insightsMeta.rateLimit.limit}
            </span>
          )}
          {updatedBadge}
        </span>
      );
    }

    return null;
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

  return (
    <div className="min-h-screen bg-gray-900 text-gray-200 font-sans">
      <header className="bg-gray-800/50 backdrop-blur-sm sticky top-0 z-20 border-b border-gray-700">
        <div className="container mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8 text-blue-400 mr-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"></path></svg>
              <h1 className="text-xl font-bold text-gray-100">GitHub Repo Manager</h1>
            </div>
            <div className="flex items-center">
                {renderDataSourceLabel()}
                {renderViewToggle()}
                <button
                  onClick={() => setIsDataSourceModalOpen(true)}
                  className="ml-3 inline-flex items-center px-3 py-1.5 border border-gray-600 rounded-md text-sm font-medium text-gray-300 bg-gray-700 hover:bg-gray-600 transition-colors"
                  title="Connect to GitHub API using a typed token, GITHUB_TOKEN, or the saved fallback token"
                >
                  <DatabaseIcon className="w-4 h-4 mr-2" />
                  GitHub API
                </button>
            </div>
          </div>
        </div>
      </header>
      <main>
        <Dashboard 
            repos={viewMode === 'github' && githubSource ? githubRepos : localRepos}
            loading={loading}
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
    </div>
  );
}

export default App;

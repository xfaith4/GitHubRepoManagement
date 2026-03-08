import React, { useState, useMemo, useEffect } from 'react';
import { type RepoStatus, type AppSettings, type OperationType, type GithubInsightsMeta, type OperationResult } from '../types';
import SummaryCard from './SummaryCard';
import ActionBar from './ActionBar';
import RepoGrid from './RepoGrid';
import LogPanel from './LogPanel';
import SettingsModal from './SettingsModal';
import InitModal from './InitModal';
import ArtifactsModal from './ArtifactsModal';
import ChangeHistoryPanel from './ChangeHistoryPanel';
import { getSettings, startInit, startUpdate, startSync, startArchive, startExport, getReportDownloadUrl, getPowerBIReportUrl } from '../services/apiClient';
import { SpinnerIcon, IssuesIcon, ProjectsIcon, BranchIcon, HealthIcon } from './icons';

interface DashboardProps {
  repos: RepoStatus[];
  loading: boolean;
  error: string | null;
  fetchRepoStatus: () => void;
  dataSource:
    | { source: 'sample' }
    | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number }
    | { source: 'github'; username: string }
    | null;
  insightsMeta?: GithubInsightsMeta | null;
}

const Dashboard: React.FC<DashboardProps> = ({ repos, loading, error, fetchRepoStatus, dataSource, insightsMeta }) => {
  const [currentOperation, setCurrentOperation] = useState<OperationType | null>(null);
  const [isLogPanelOpen, setIsLogPanelOpen] = useState(false);
  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);
  const [isInitModalOpen, setIsInitModalOpen] = useState(false);
  const [isArtifactsModalOpen, setIsArtifactsModalOpen] = useState(false);
  const [selectedRepoForArtifacts, setSelectedRepoForArtifacts] = useState<string | null>(null);
  const [selectedRepoIds, setSelectedRepoIds] = useState<Set<string>>(new Set());
  const [groupBy, setGroupBy] = useState<keyof RepoStatus | 'none'>('none');
  
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [settingsLoading, setSettingsLoading] = useState(true);
  const [loadingElapsedSec, setLoadingElapsedSec] = useState(0);
  const [logMessages, setLogMessages] = useState<string[]>([]);
  const [logStatus, setLogStatus] = useState<'idle' | 'running' | 'success' | 'error'>('idle');
  
  useEffect(() => {
    getSettings()
      .then(setSettings)
      .catch(err => console.error("Failed to fetch settings", err))
      .finally(() => setSettingsLoading(false));
  }, []);

  useEffect(() => {
    if (!loading) {
      setLoadingElapsedSec(0);
      return;
    }

    const startedAt = Date.now();
    const timer = setInterval(() => {
      setLoadingElapsedSec(Math.floor((Date.now() - startedAt) / 1000));
    }, 250);

    return () => clearInterval(timer);
  }, [loading]);

  // When repos are re-fetched, clear selection
  useEffect(() => {
    setSelectedRepoIds(new Set());
  }, [repos]);

  const getRepoSelectionId = (repo: RepoStatus) => repo.localPath ?? `${repo.name}::${repo.branch}`;
  const resolveSelectionTargets = (repoIds?: string[]) => {
    if (!repoIds || repoIds.length === 0) {
      return { repoNames: undefined, repoPaths: undefined };
    }

    const selected = repos.filter(r => repoIds.includes(getRepoSelectionId(r)));
    const distinctNames = Array.from(new Set(selected.map(r => r.name)));
    const distinctPaths = Array.from(new Set(selected.map(r => r.localPath).filter((p): p is string => Boolean(p))));

    return {
      repoNames: distinctNames.length > 0 ? distinctNames : undefined,
      repoPaths: distinctPaths.length > 0 ? distinctPaths : undefined
    };
  };

  const appendOperationLogs = (result: OperationResult) => {
    const lines: string[] = [];
    lines.push(`Found ${result.total} repositories to process.`);
    result.results.forEach((repoResult, index) => {
      const repoLabel = repoResult.path ? `${repoResult.name} (${repoResult.path})` : repoResult.name;
      if (repoResult.success) {
        lines.push(`[${index + 1}/${result.results.length}] ${repoLabel} ... done`);
        const outputLines = String(repoResult.output ?? '')
          .split(/\r?\n/)
          .map(l => l.trim())
          .filter(Boolean)
          .slice(0, 8);
        outputLines.forEach(line => lines.push(`  ${line}`));
      } else {
        lines.push(`[${index + 1}/${result.results.length}] ${repoLabel} ... FAILED`);
        if (repoResult.error) {
          lines.push(`  ${repoResult.error}`);
        }
      }
    });
    lines.push(`Summary: ${result.succeeded} succeeded, ${result.failed} failed.`);
    setLogMessages(prev => [...prev, ...lines]);
  };

  const handleAction = async (operation: OperationType, repoIds?: string[]) => {
    setCurrentOperation(operation);
    setIsLogPanelOpen(true);
    setLogStatus('running');
    const selectedCount = repoIds?.length ?? 0;
    setLogMessages([
      `Starting: ${operation}...`,
      selectedCount > 0 ? `Targeting ${selectedCount} selected repositories.` : 'Targeting all discovered repositories.'
    ]);
    const { repoNames, repoPaths } = resolveSelectionTargets(repoIds);
    try {
        switch(operation) {
            case 'update':
                {
                  const result = await startUpdate(repoNames, repoPaths);
                  appendOperationLogs(result);
                  setLogStatus(result.failed > 0 ? 'error' : 'success');
                }
                break;
            case 'sync':
                {
                  const result = await startSync(repoNames, repoPaths);
                  appendOperationLogs(result);
                  setLogStatus(result.failed > 0 ? 'error' : 'success');
                }
                break;
            case 'archive':
                if (settings) {
                    await startArchive(settings.daysInactive, settings.zipArchive, repoNames);
                }
                setLogMessages(prev => [...prev, 'Archive requested.']);
                setLogStatus('success');
                break;
            case 'init':
                 // Init is special, it's triggered from its modal
                setLogMessages(prev => [...prev, 'Init requested.']);
                setLogStatus('success');
                break;
            case 'export':
                await startExport();
                setLogMessages(prev => [...prev, 'Export requested.']);
                setLogStatus('success');
                break;
        }
    } catch (err) {
        console.error(`${operation} failed to start`, err);
        const message = err instanceof Error ? err.message : 'Operation failed.';
        setLogMessages(prev => [...prev, `ERROR: ${message}`]);
        setLogStatus('error');
    }
  };
  
  const handleExport = async () => {
    handleAction('export');
    const reposToExport = selectedRepoIds.size > 0
        ? repos.filter(r => selectedRepoIds.has(getRepoSelectionId(r)))
        : repos;
    
    // Export Power BI Dashboard (HTML)
    const powerBIUrl = getPowerBIReportUrl(reposToExport);
    const powerBILink = document.createElement('a');
    powerBILink.href = powerBIUrl;
    powerBILink.setAttribute('download', 'RepoStatusReport_PowerBI.html');
    document.body.appendChild(powerBILink);
    powerBILink.click();
    document.body.removeChild(powerBILink);
    
    // Also export CSV for backward compatibility
    // Delay prevents browser from blocking multiple simultaneous downloads
    const DOWNLOAD_DELAY_MS = 100;
    setTimeout(() => {
      const csvUrl = getReportDownloadUrl(reposToExport);
      const csvLink = document.createElement('a');
      csvLink.href = csvUrl;
      csvLink.setAttribute('download', 'RepoStatusReport.csv');
      document.body.appendChild(csvLink);
      csvLink.click();
      document.body.removeChild(csvLink);
    }, DOWNLOAD_DELAY_MS);
  };

  const handleLogPanelClose = () => {
    setIsLogPanelOpen(false);
    setCurrentOperation(null);
    setLogStatus('idle');
    fetchRepoStatus(); // Refresh data after an operation
  };
  
  const handleSaveSettings = (newSettings: AppSettings) => {
    setSettings(newSettings);
    setIsSettingsModalOpen(false);
    fetchRepoStatus(); // Refresh, as some settings might affect repo status (e.g. stale threshold)
  };
  
  const handleInit = async (githubUser: string, cloneOwned: boolean, apiKey?: string, basePath?: string) => {
      try {
        await startInit(githubUser, cloneOwned, apiKey, basePath);
        handleAction('init');
      } catch (err) {
        console.error("Init failed to start", err);
      } finally {
        setIsInitModalOpen(false);
      }
  };
  
  const handleViewArtifacts = (repoName: string) => {
    setSelectedRepoForArtifacts(repoName);
    setIsArtifactsModalOpen(true);
  };

  const summary = useMemo(() => {
    const total = repos.length;
    const dirty = repos.filter(r => r.status === 'dirty' || r.uncommittedChanges > 0).length;
    const needsSync = repos.filter(r => r.status === 'ahead' || r.status === 'behind' || r.status === 'diverged').length;
    const stale = repos.filter(r => r.isStale).length;
    const commitsThisWeek = repos.reduce((sum, r) => sum + (r.commitsLastWeek ?? 0), 0);
    const commitsThisMonth = repos.reduce((sum, r) => sum + (r.commitsLastMonth ?? 0), 0);
    
    // Extended metrics
    const totalIssues = repos.reduce((sum, r) => sum + (r.extended?.openIssuesCount || 0), 0);
    const totalProjects = repos.reduce((sum, r) => sum + (r.extended?.projectsCount || 0), 0);
    const totalStaleBranches = repos.reduce((sum, r) => sum + (r.extended?.staleBranches || 0), 0);
    const reposWithVulnerabilities = repos.filter(r => (r.extended?.vulnerabilitiesCount || 0) > 0).length;
    const avgHealthScore = repos.length > 0 
      ? Math.round(repos.reduce((sum, r) => sum + (r.extended?.healthScore || 0), 0) / repos.length)
      : 0;
    
    return { 
      total, dirty, needsSync, stale, commitsThisWeek, commitsThisMonth,
      totalIssues, totalProjects, totalStaleBranches, reposWithVulnerabilities, avgHealthScore
    };
  }, [repos]);

  if (error) {
    return <div className="text-center p-8 text-red-400">{error}</div>;
  }
  
  if (loading || settingsLoading) {
      return (
          <div className="flex flex-col items-center justify-center h-96 gap-4">
              <div className="flex items-center">
                <SpinnerIcon className="w-10 h-10 text-blue-500" />
                <p className="ml-4 text-lg">Scanning repositories... {loadingElapsedSec}s</p>
              </div>
              <div className="w-full max-w-md h-2 rounded-full bg-gray-800 overflow-hidden">
                <div className="h-full w-1/3 bg-blue-500 animate-pulse rounded-full" />
              </div>
              {dataSource?.source === 'local' && typeof dataSource.repoCount === 'number' && (
                <p className="text-sm text-gray-400">
                  Last completed scan: {dataSource.repoCount} repos
                  {typeof dataSource.scanDurationMs === 'number' ? ` in ${(dataSource.scanDurationMs / 1000).toFixed(1)}s` : ''}
                </p>
              )}
          </div>
      );
  }

  return (
    <div>
      {dataSource?.source === 'local' && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
          <div className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-3 text-sm text-gray-200">
            Showing repositories discovered under <strong>{settings?.basePath}</strong> (scan depth {settings?.scanDepth}).
            {typeof dataSource.repoCount === 'number' && (
              <span className="text-gray-300"> Last scan found <strong>{dataSource.repoCount}</strong> repos{typeof dataSource.scanDurationMs === 'number' ? ` in ${(dataSource.scanDurationMs / 1000).toFixed(1)}s` : ''}.</span>
            )}
            <span className="text-gray-400"> Use Settings to change workspace path. Connect GitHub API to view repositories that exist on GitHub but are not cloned locally.</span>
          </div>
        </div>
      )}
      {dataSource?.source === 'github' && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
          <div className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-3 text-sm text-gray-200">
            Showing repositories returned by the GitHub API for <strong>{dataSource.username}</strong>.
            <span className="text-gray-400"> Local-only repositories will not appear in this view. Use the Local tab to view your workspace scan.</span>
          </div>
        </div>
      )}
      {dataSource?.source === 'github' && insightsMeta && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
          <div className="bg-blue-900/20 border border-blue-700/60 rounded-lg px-4 py-3 text-sm text-blue-100">
            <div className="flex flex-wrap items-center gap-3">
              <span>
                Showing <strong>{insightsMeta.fetchedRepos}</strong> of <strong>{insightsMeta.totalRepos}</strong> repositories from GitHub.
              </span>
              {insightsMeta.rateLimit && (
                <span className="text-blue-200/80">
                  Rate limit: {insightsMeta.rateLimit.remaining}/{insightsMeta.rateLimit.limit} · resets at{' '}
                  {new Date(insightsMeta.rateLimit.reset * 1000).toLocaleTimeString()}
                </span>
              )}
            </div>
          </div>
        </div>
      )}

      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-4">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-6 gap-4">
          <SummaryCard title="Total Repositories" value={summary.total} color="blue" />
          <SummaryCard title="Needs Attention" value={summary.dirty} color="yellow" />
          <SummaryCard title="Ahead/Behind" value={summary.needsSync} color="red" />
          <SummaryCard title="Stale Repositories" value={summary.stale} color="red" />
          <SummaryCard title="Commits This Week" value={summary.commitsThisWeek} color="green" />
          <SummaryCard title="Commits This Month" value={summary.commitsThisMonth} color="blue" />
        </div>

        {repos.length === 0 && dataSource?.source === 'local' && (
          <div className="mt-4 bg-yellow-900/20 border border-yellow-700/60 rounded-lg px-4 py-3 text-sm text-yellow-100">
            No repositories found. Confirm the workspace path contains git repositories and adjust scan depth if your repos are nested.
          </div>
        )}
        
        {repos.some(r => r.extended) && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
            <SummaryCard 
              title="Open Issues" 
              value={summary.totalIssues} 
              color="yellow" 
              icon={<IssuesIcon className="w-6 h-6" />}
            />
            <SummaryCard 
              title="Active Projects" 
              value={summary.totalProjects} 
              color="purple" 
              icon={<ProjectsIcon className="w-6 h-6" />}
            />
            <SummaryCard 
              title="Stale Branches" 
              value={summary.totalStaleBranches} 
              color="orange" 
              icon={<BranchIcon className="w-6 h-6" />}
            />
            <SummaryCard 
              title="Avg Health Score" 
              value={`${summary.avgHealthScore}%`} 
              color="green" 
              icon={<HealthIcon className="w-6 h-6" />}
            />
          </div>
        )}
      </div>
      
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <ChangeHistoryPanel repos={repos} />
        
        <div className="bg-gray-800/50 border border-gray-700 rounded-lg mt-4">
            <ActionBar
                onAction={handleAction}
                onExport={handleExport}
                onRefresh={fetchRepoStatus}
                onSettingsClick={() => setIsSettingsModalOpen(true)}
                onInitClick={() => setIsInitModalOpen(true)}
                isActionRunning={!!currentOperation}
                currentOperation={currentOperation}
                settings={settings}
                selectedRepos={selectedRepoIds}
            />
            <RepoGrid 
              repos={repos} 
              onViewArtifacts={handleViewArtifacts} 
              dataSource={dataSource}
              selectedRepos={selectedRepoIds}
              setSelectedRepos={setSelectedRepoIds}
              groupBy={groupBy}
              setGroupBy={setGroupBy}
            />
        </div>
      </div>
      
      <LogPanel 
        isOpen={isLogPanelOpen}
        operation={currentOperation}
        messages={logMessages}
        status={logStatus}
        onClose={handleLogPanelClose}
      />
      
      {settings && (
        <SettingsModal 
          isOpen={isSettingsModalOpen}
          onClose={() => setIsSettingsModalOpen(false)}
          onSave={handleSaveSettings}
          currentSettings={settings}
        />
      )}
      
      <InitModal 
        isOpen={isInitModalOpen}
        onClose={() => setIsInitModalOpen(false)}
        onInit={handleInit}
      />

      <ArtifactsModal 
        isOpen={isArtifactsModalOpen}
        onClose={() => setIsArtifactsModalOpen(false)}
        repoName={selectedRepoForArtifacts}
      />
    </div>
  );
};

export default Dashboard;

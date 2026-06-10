import React, { useState, useMemo, useEffect, useRef } from 'react';
import { type RepoStatus, type AppSettings, type OperationType, type GithubInsightsMeta, type OperationResult, type DocReviewRunRequest, type RoadmapEntry, type DocAuditIndex, type RoadmapAuditIndex, type ExecutionMetrics, type ScanSchedule, type RoadmapDependencyGraph, type PortfolioAssessmentEntry, type PortfolioAssessmentResult, type RepoLifecycleState, type PortfolioSignalSource, type OperationsReposResult } from '../types';
import SummaryCard from './SummaryCard';
import ActionBar from './ActionBar';
import RepoGrid from './RepoGrid';
import LogPanel from './LogPanel';
import SettingsModal from './SettingsModal';
import InitModal from './InitModal';
import ArtifactsModal from './ArtifactsModal';
import ChangeHistoryPanel from './ChangeHistoryPanel';
import DocReviewModal from './DocReviewModal';
import RoadmapViewerModal from './RoadmapViewerModal';
import ApiDocsModal from './ApiDocsModal';
import WorkQueueView from './WorkQueueView';
import CopilotTaskPreviewModal from './CopilotTaskPreviewModal';
import RoadmapAuditModal from './RoadmapAuditModal';
import RoadmapRepairModal from './RoadmapRepairModal';
import { ReadmeStandardizationModal } from './ReadmeStandardizationModal';
import { RoadmapLintModal } from './RoadmapLintModal';
import ExecutionQueuePanel from './ExecutionQueuePanel';
import RepoEvaluationModal from './RepoEvaluationModal';
import RoadmapDispatchModal from './RoadmapDispatchModal';
import RepoGitStatusModal from './RepoGitStatusModal';
import ReadmeGenerateModal from './ReadmeGenerateModal';
import HelpModal from './HelpModal';
import OperationsWorkspaceView from './OperationsWorkspaceView';
import { getSettings, startInit, startUpdate, startSync, startArchive, startExport, startDocReview, getRoadmapIndex, triggerRoadmapScan, getDocsAudit, triggerDocsAuditScan, getRoadmapAudit, triggerRoadmapAuditScan, isOptionalApiUnavailableError, getExecutionMetrics, getScanSchedule, getRoadmapDependencies, getPortfolioAssessment, getOperationsRepos } from '../services/apiClient';
import { useSse } from '../hooks/useSse';
import { useBackendLog } from '../hooks/useBackendLog';
import { useHealthPing } from '../hooks/useHealthPing';
import { SpinnerIcon, IssuesIcon, ProjectsIcon, BranchIcon, HealthIcon } from './icons';

interface DashboardProps {
  repos: RepoStatus[];
  loading: boolean;
  /** True while the startup differential re-scan runs in the background. */
  isBackgroundRefreshing?: boolean;
  error: string | null;
  fetchRepoStatus: () => void;
  dataSource:
    | { source: 'sample' }
    | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number }
    | { source: 'github'; username: string }
    | null;
  insightsMeta?: GithubInsightsMeta | null;
  dataLastUpdated?: Date | null;
}

const SIGNAL_SOURCE_STYLES: Record<PortfolioSignalSource, string> = {
  cache: 'bg-slate-800 text-slate-200 border-slate-600',
  'fresh-scan': 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  ledger: 'bg-blue-900/40 text-blue-200 border-blue-700/50',
  api: 'bg-indigo-900/40 text-indigo-200 border-indigo-700/50',
  unavailable: 'bg-gray-800 text-gray-300 border-gray-600',
  'not-evaluated': 'bg-gray-800 text-gray-300 border-gray-600',
  'no-token': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'no-owner-configured': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  error: 'bg-red-900/40 text-red-200 border-red-700/50',
};

const LIFECYCLE_STYLES: Record<RepoLifecycleState, string> = {
  discovered: 'bg-slate-800 text-slate-200 border-slate-600',
  'needs-readme': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'needs-roadmap': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'needs-roadmap-repair': 'bg-orange-900/40 text-orange-200 border-orange-700/50',
  'needs-structure': 'bg-orange-900/40 text-orange-200 border-orange-700/50',
  'ready-for-work': 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  running: 'bg-blue-900/40 text-blue-200 border-blue-700/50',
  completed: 'bg-violet-900/40 text-violet-200 border-violet-700/50',
  monitored: 'bg-cyan-900/40 text-cyan-200 border-cyan-700/50',
  archived: 'bg-gray-800 text-gray-300 border-gray-600',
  'parse-error': 'bg-red-900/40 text-red-200 border-red-700/50',
};

function formatLifecycleLabel(state: RepoLifecycleState): string {
  return state.replaceAll('-', ' ');
}

function formatSignalLabel(key: string): string {
  switch (key) {
    case 'docAudit':
      return 'Docs';
    case 'roadmapAudit':
      return 'Roadmap';
    default:
      return key.charAt(0).toUpperCase() + key.slice(1);
  }
}

const Dashboard: React.FC<DashboardProps> = ({ repos, loading, isBackgroundRefreshing = false, error, fetchRepoStatus, dataSource, insightsMeta, dataLastUpdated }) => {
  const [currentOperation, setCurrentOperation] = useState<OperationType | null>(null);
  const [isLogPanelOpen, setIsLogPanelOpen] = useState(false);
  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);
  const [isInitModalOpen, setIsInitModalOpen] = useState(false);
  const [isArtifactsModalOpen, setIsArtifactsModalOpen] = useState(false);
  const [isDocReviewModalOpen, setIsDocReviewModalOpen] = useState(false);
  const [selectedRepoForArtifacts, setSelectedRepoForArtifacts] = useState<string | null>(null);
  const [isRoadmapViewerOpen, setIsRoadmapViewerOpen] = useState(false);
  const [isApiDocsOpen, setIsApiDocsOpen] = useState(false);
  const [isHelpOpen, setIsHelpOpen] = useState(false);
  const [selectedRoadmapRepo, setSelectedRoadmapRepo] = useState<string | null>(null);
  const [isCopilotTaskPreviewOpen, setIsCopilotTaskPreviewOpen] = useState(false);
  const [copilotTaskPreviewRepo, setCopilotTaskPreviewRepo] = useState<string | null>(null);
  const [copilotTaskPreviewRoadmapPath, setCopilotTaskPreviewRoadmapPath] = useState<string | undefined>(undefined);
  const [roadmapEntries, setRoadmapEntries] = useState<RoadmapEntry[]>([]);
  const [selectedRepoIds, setSelectedRepoIds] = useState<Set<string>>(new Set());
  const [groupBy, setGroupBy] = useState<keyof RepoStatus | 'none'>('none');
  const [activeView, setActiveView] = useState<'repos' | 'operations' | 'work-queue' | 'execution-queue' | 'dependencies'>('repos');
  const [docsAuditIndex, setDocsAuditIndex] = useState<DocAuditIndex | null>(null);
  const [docsAuditLoading, setDocsAuditLoading] = useState(false);
  const [docsAuditError, setDocsAuditError] = useState<string | null>(null);
  const [hasAttemptedDocsAuditLoad, setHasAttemptedDocsAuditLoad] = useState(false);

  const [roadmapAuditIndex, setRoadmapAuditIndex] = useState<RoadmapAuditIndex | null>(null);
  const [hasAttemptedRoadmapAuditLoad, setHasAttemptedRoadmapAuditLoad] = useState(false);
  const [isRoadmapAuditModalOpen, setIsRoadmapAuditModalOpen] = useState(false);
  const [roadmapAuditModalRepo, setRoadmapAuditModalRepo] = useState<string | null>(null);

  const [isRoadmapRepairModalOpen, setIsRoadmapRepairModalOpen] = useState(false);
  const [roadmapRepairModalRepo, setRoadmapRepairModalRepo] = useState<string | null>(null);
  const [lintModalRepo, setLintModalRepo] = useState<string | null>(null);
  const [standardizeModalRepo, setStandardizeModalRepo] = useState<string | null>(null);
  const [evaluationModalRepo, setEvaluationModalRepo] = useState<string | null>(null);
  const [dispatchModalRepo, setDispatchModalRepo] = useState<string | null>(null);
  const [gitStatusModalRepo, setGitStatusModalRepo] = useState<string | null>(null);
  const [gitStatusModalPath, setGitStatusModalPath] = useState<string | null>(null);
  const [readmeGenerateRepo, setReadmeGenerateRepo] = useState<string | null>(null);
  const [readmeGeneratePath, setReadmeGeneratePath] = useState<string | null>(null);

  // Release 1.2 — execution metrics, auto-scan schedule, dependency graph
  const [executionMetrics, setExecutionMetrics] = useState<ExecutionMetrics | null>(null);
  const [scanSchedule, setScanSchedule] = useState<ScanSchedule | null>(null);
  const [dependencyGraph, setDependencyGraph] = useState<RoadmapDependencyGraph | null>(null);
  const [dependencyGraphLoading, setDependencyGraphLoading] = useState(false);
  const [hasAttemptedDepsLoad, setHasAttemptedDepsLoad] = useState(false);
  const [portfolioAssessment, setPortfolioAssessment] = useState<PortfolioAssessmentResult | null>(null);
  const [portfolioAssessmentLoading, setPortfolioAssessmentLoading] = useState(false);
  const [operationsRepos, setOperationsRepos] = useState<OperationsReposResult | null>(null);
  const [operationsReposLoading, setOperationsReposLoading] = useState(false);
  const [operationsReposError, setOperationsReposError] = useState<string | null>(null);
  const [hasAttemptedOperationsLoad, setHasAttemptedOperationsLoad] = useState(false);

  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [settingsLoading, setSettingsLoading] = useState(true);
  const [loadingElapsedSec, setLoadingElapsedSec] = useState(0);
  const [logMessages, setLogMessages] = useState<string[]>([]);
  const [logStatus, setLogStatus] = useState<'idle' | 'running' | 'success' | 'error'>('idle');
  const [scanProgress, setScanProgress] = useState<{ scannedCount: number; latestRepo: string | null }>({ scannedCount: 0, latestRepo: null });

  const refreshPortfolioAssessment = (refresh = false) => {
    setPortfolioAssessmentLoading(true);
    return getPortfolioAssessment(refresh ? { refresh: true } : {})
      .then(result => {
        setPortfolioAssessment(result);
        return result;
      })
      .finally(() => setPortfolioAssessmentLoading(false));
  };

  const refreshOperationsRepos = (refreshPortfolio = false) => {
    setOperationsReposLoading(true);
    setOperationsReposError(null);

    const load = async () => {
      if (refreshPortfolio) {
        await refreshPortfolioAssessment(true);
      }

      const result = await getOperationsRepos();
      setOperationsRepos(result);
      return result;
    };

    return load()
      .catch(err => {
        setOperationsReposError(err instanceof Error ? err.message : 'Operations workspace is unavailable.');
        throw err;
      })
      .finally(() => setOperationsReposLoading(false));
  };

  // Backend health indicator — polls /health/live every 15 s
  const backendHealth = useHealthPing(15_000);

  // Backend log polling — active whenever a scan, background re-scan, or
  // operation is running. Polling during the background re-scan lets the inline
  // front-page indicator show live progress without opening the drawer.
  const logPollActive = loading || isBackgroundRefreshing || (!!currentOperation && currentOperation !== 'scan');
  const { entries: backendLogEntries } = useBackendLog(logPollActive, { includeHistory: false });

  // SSE hook kept for future streaming endpoints (pass null = idle/no-op)
  useSse(null);

  // Tracks the previous `loading` value so we can detect scan start/finish
  // transitions and update the inline progress indicator (not the drawer).
  const prevLoadingRef = useRef<boolean>(false);
  const prevBackendLogCountRef = useRef(0);

  useEffect(() => {
    getSettings()
      .then(setSettings)
      .catch(err => console.error("Failed to fetch settings", err))
      .finally(() => setSettingsLoading(false));
  }, []);

  // Lazy roadmap index fetch — runs after initial mount, never blocks page load
  useEffect(() => {
    getRoadmapIndex().then(index => setRoadmapEntries(index.entries)).catch(() => {/* silent — badge just won't show */});
  }, []);

  useEffect(() => {
    if (loading) {
      return;
    }

    refreshPortfolioAssessment(false).catch(() => {/* silent */});
  }, [loading, repos.length]);

  // Release 1.2 — fetch execution metrics and auto-scan schedule on mount (silent failures)
  useEffect(() => {
    getExecutionMetrics().then(setExecutionMetrics).catch(() => {/* silent */});
    getScanSchedule().then(setScanSchedule).catch(() => {/* silent */});
  }, []);

  // Release 1.2 — load dependency graph when Dependencies tab is first opened
  useEffect(() => {
    if (activeView !== 'dependencies' || hasAttemptedDepsLoad) return;
    setHasAttemptedDepsLoad(true);
    setDependencyGraphLoading(true);
    getRoadmapDependencies()
      .then(setDependencyGraph)
      .catch(() => {/* silent — panel shows empty state */})
      .finally(() => setDependencyGraphLoading(false));
  }, [activeView, hasAttemptedDepsLoad]);

  useEffect(() => {
    if (activeView !== 'operations' || hasAttemptedOperationsLoad) {
      return;
    }

    setHasAttemptedOperationsLoad(true);
    refreshOperationsRepos(false).catch(() => {/* surfaced in-panel */});
  }, [activeView, hasAttemptedOperationsLoad]);

  // Load docs audit when Work Queue or Operations is first opened.
  useEffect(() => {
    if ((activeView !== 'work-queue' && activeView !== 'operations') || hasAttemptedDocsAuditLoad) {
      return;
    }
    setHasAttemptedDocsAuditLoad(true);
    setDocsAuditLoading(true);
    getDocsAudit()
      .then(index => {
        setDocsAuditIndex(index);
        setDocsAuditError(null);
      })
      .catch(err => {
        if (isOptionalApiUnavailableError(err)) {
          setDocsAuditIndex(null);
          setDocsAuditError(err.message);
          return;
        }
        setDocsAuditError(err instanceof Error ? err.message : 'Docs audit is unavailable.');
      })
      .finally(() => setDocsAuditLoading(false));
  }, [activeView, hasAttemptedDocsAuditLoad]);

  // Load roadmap audit when Work Queue or Operations is first opened.
  useEffect(() => {
    if ((activeView !== 'work-queue' && activeView !== 'operations') || hasAttemptedRoadmapAuditLoad) {
      return;
    }
    setHasAttemptedRoadmapAuditLoad(true);
    getRoadmapAudit()
      .then(index => setRoadmapAuditIndex(index))
      .catch(() => {/* silent — maturity badges just won't show */});
  }, [activeView, hasAttemptedRoadmapAuditLoad]);

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

  // Track scan progress for the inline, non-blocking front-page indicator.
  // The slide-out drawer is intentionally NOT auto-opened here: the cached repo
  // list is already on screen, and the re-scan is surfaced by the inline banner
  // below. The user can open the detailed log on demand via "View progress".
  useEffect(() => {
    const wasLoading = prevLoadingRef.current;
    prevLoadingRef.current = loading;

    if (loading && !wasLoading) {
      // Scan is starting — prime the log buffer (shown only if the user opens
      // the drawer) and reset progress for the inline indicator.
      setCurrentOperation('scan');
      setLogMessages(['Starting repository scan...']);
      setLogStatus('running');
      setScanProgress({ scannedCount: 0, latestRepo: null });
      prevBackendLogCountRef.current = 0;
    } else if (!loading && wasLoading) {
      // Scan finished
      if (currentOperation === 'scan') {
        const repoCount = repos.length;
        setLogMessages(prev => [
          ...prev,
          repoCount > 0
            ? `Scan complete. Found ${repoCount} ${repoCount === 1 ? 'repository' : 'repositories'}.`
            : 'Scan complete. No repositories found.'
        ]);
        setLogStatus(error ? 'error' : 'success');
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading]);

  // Pipe backend log poll entries into the log panel during active operations
  useEffect(() => {
    const newEntries = backendLogEntries.slice(prevBackendLogCountRef.current);
    if (newEntries.length === 0) return;
    prevBackendLogCountRef.current = backendLogEntries.length;
    // Filter out TRACE noise from health pings; surface meaningful events only
    const lines = newEntries
      .filter(e => e.level !== 'TRACE' || e.msg.includes('correlationId'))
      .map(e => {
        const prefix = e.level === 'ERROR' ? 'ERROR: ' : e.level === 'WARN' ? 'WARN: ' : '';
        return `${prefix}${e.msg}`;
      });
    if (currentOperation === 'scan') {
      const repoLineMatches = lines
        .map(line => {
          // Matches backend scan lines like: "Found repo #12: MyRepo (Branch: main, ...)"
          const match = line.match(/Found repo #(\d+):\s*([^(]+?)(?:\s*\(|$)/i);
          if (!match) return null;
          return { scannedCount: Number(match[1]), latestRepo: match[2].trim() };
        })
        .filter((match): match is { scannedCount: number; latestRepo: string } => match !== null);
      if (repoLineMatches.length > 0) {
        const latest = repoLineMatches[repoLineMatches.length - 1];
        setScanProgress(prev => ({
          scannedCount: Math.max(prev.scannedCount, latest.scannedCount),
          latestRepo: latest.latestRepo || prev.latestRepo
        }));
      }
    }
    if (lines.length > 0) setLogMessages(prev => [...prev, ...lines]);
  }, [backendLogEntries, currentOperation]);

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
                await handleExport();
                setLogMessages(prev => [...prev, 'Export requested.']);
                setLogStatus('success');
                break;
            case 'docreview':
                setLogMessages(prev => [...prev, 'Doc review run requested.']);
                setLogStatus('success');
                break;
            case 'roadmap-scan':
                {
                  setLogMessages(prev => [...prev, 'Scanning all repositories for ROADMAP files...']);
                  const result = await triggerRoadmapScan();
                  setRoadmapEntries(result.entries);
                  setLogMessages(prev => [...prev, `Scan complete. Found ${result.count} ROADMAP ${result.count === 1 ? 'file' : 'files'}.`]);
                  setLogStatus('success');
                }
                break;
            case 'docs-audit-scan':
                {
                  setLogMessages(prev => [...prev, 'Running documentation audit across all repositories...']);
                  setDocsAuditLoading(true);
                  try {
                    const auditResult = await triggerDocsAuditScan();
                    setDocsAuditIndex(auditResult);
                    setDocsAuditError(null);
                    try {
                      await refreshPortfolioAssessment(true);
                    } catch (assessmentErr) {
                      setLogMessages(prev => [...prev, `Portfolio value refresh failed: ${assessmentErr instanceof Error ? assessmentErr.message : String(assessmentErr)}`]);
                    }
                    const readyCount = auditResult.entries.filter(e => e.dispatchReadiness === 'ready').length;
                    setLogMessages(prev => [...prev, `Audit complete. ${auditResult.count} repos audited. ${readyCount} ready for dispatch.`]);
                    setLogStatus('success');
                  } finally {
                    setDocsAuditLoading(false);
                  }
                }
                break;
            case 'roadmap-audit-scan':
                {
                  setLogMessages(prev => [...prev, 'Running roadmap contract audit across all repositories...']);
                  try {
                    const auditResult = await triggerRoadmapAuditScan();
                    setRoadmapAuditIndex(auditResult);
                    const l4Count = auditResult.entries.filter(e => e.maturityLevel === 'L4-Orchestration-Ready').length;
                    setLogMessages(prev => [...prev, `Roadmap audit complete. ${auditResult.count} repos audited. ${l4Count} at L4 Orchestration-Ready.`]);
                    setLogStatus('success');
                  } catch (auditErr) {
                    setLogMessages(prev => [...prev, `Roadmap audit scan failed: ${auditErr instanceof Error ? auditErr.message : String(auditErr)}`]);
                    setLogStatus('error');
                  }
                }
                break;
        }
    } catch (err) {
        console.error(`${operation} failed to start`, err);
        const message = err instanceof Error ? err.message : 'Operation failed.';
        setLogMessages(prev => [...prev, `ERROR: ${message}`]);
        setLogStatus('error');
    }
  };

  const handleDocReviewRun = async (request: DocReviewRunRequest) => {
    setCurrentOperation('docreview');
    setIsLogPanelOpen(true);
    setLogStatus('running');
    setLogMessages([
      'Starting: docreview...',
      `Root path: ${request.rootPath ?? settings?.basePath ?? 'N/A'}`,
      `Max depth: ${String(request.maxDepth ?? settings?.scanDepth ?? 2)}`,
      `Generate queue: ${request.generateQueue === false ? 'No' : 'Yes'}`,
      `Generate batch plan: ${request.generateBatchPlan ? 'Yes' : 'No'}${request.targetRepo ? ` (${request.targetRepo})` : ''}`
    ]);

    try {
      const result = await startDocReview(request);
      setLogMessages(prev => [
        ...prev,
        `Inventory manifest: ${result.inventoryManifestPath}`,
        `Inventory summary: ${result.inventorySummaryCsvPath}`,
        `Inventory report: ${result.inventoryReportPath}`,
        `Queue output: ${result.queuePath ?? 'not generated'}`,
        `Workitems root: ${result.workitemsRoot ?? 'not generated'}`,
        'Doc review completed.'
      ]);
      setLogStatus('success');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Doc review run failed.';
      setLogMessages(prev => [...prev, `ERROR: ${message}`]);
      setLogStatus('error');
      throw error;
    }
  };

  const handleExport = async () => {
    const reposToExport = selectedRepoIds.size > 0
      ? repos.filter(r => selectedRepoIds.has(getRepoSelectionId(r)))
      : repos;
    const targetCount = reposToExport.length;
    const sourceLabel = dataSource?.source === 'github'
      ? `GitHub API: ${dataSource.username}`
      : dataSource?.source === 'local'
        ? `Local Scan${dataSource.workspacePath ? ` (${dataSource.workspacePath})` : ''}`
        : 'Sample Data';
    const getAssessmentSelectionId = (entry: PortfolioAssessmentEntry) => entry.localPath || `${entry.repoName}::${entry.branch}`;

    const reportWindow = window.open('', '_blank');
    if (reportWindow && !reportWindow.closed) {
      reportWindow.document.write('<!doctype html><html><head><title>Generating report...</title></head><body style="font-family: Segoe UI, sans-serif; padding: 32px; background: #0f172a; color: #e2e8f0;"><h1>Generating report...</h1><p>Your saved report will open here when export completes.</p></body></html>');
      reportWindow.document.close();
    }

    setCurrentOperation('export');
    setIsLogPanelOpen(true);
    setLogStatus('running');
    setLogMessages([
      'Starting: export...',
      targetCount > 0 ? `Generating collection report for ${targetCount} repositories.` : 'Generating collection report for the current view.',
      `Source: ${sourceLabel}`
    ]);

    try {
      let result;
      if (dataSource?.source === 'github') {
        result = await startExport({ repos: reposToExport, sourceLabel });
      } else {
        let assessment = portfolioAssessment;
        if (!assessment || (assessment.entries?.length ?? 0) === 0) {
          assessment = await refreshPortfolioAssessment(false);
        }

        const entriesToExport = selectedRepoIds.size > 0
          ? (assessment?.entries ?? []).filter(entry => selectedRepoIds.has(getAssessmentSelectionId(entry)))
          : (assessment?.entries ?? []);

        if (entriesToExport.length > 0) {
          result = await startExport({ portfolioEntries: entriesToExport, sourceLabel });
        } else {
          setLogMessages(prev => [...prev, 'Portfolio assessment export data was unavailable; falling back to repository status export.']);
          result = await startExport({ repos: reposToExport, sourceLabel });
        }
      }

      setLogMessages(prev => [
        ...prev,
        `HTML report saved: ${result.reportPath}`,
        `CSV report saved: ${result.csvPath}`,
        `Generated at: ${result.generatedAt}`,
        'HTML report opened in a new tab.'
      ]);
      setLogStatus('success');

      if (reportWindow && !reportWindow.closed) {
        reportWindow.location.href = result.reportUrl;
      } else {
        window.open(result.reportUrl, '_blank');
      }
    } catch (error) {
      if (reportWindow && !reportWindow.closed) {
        reportWindow.close();
      }
      const message = error instanceof Error ? error.message : 'Report export failed.';
      setLogMessages(prev => [...prev, `ERROR: ${message}`]);
      setLogStatus('error');
    }
  };

  const handleLogPanelClose = () => {
    const wasScan = currentOperation === 'scan';
    setIsLogPanelOpen(false);
    setCurrentOperation(null);
    setLogStatus('idle');
    prevBackendLogCountRef.current = 0;
    // Only trigger a refresh for non-scan operations (scan was already triggered by App.tsx)
    if (!wasScan) {
      fetchRepoStatus();
    }
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

  const handleViewRoadmap = (repoName: string) => {
    setSelectedRoadmapRepo(repoName);
    setIsRoadmapViewerOpen(true);
  };

  const handleRoadmapScanComplete = (count: number) => {
    // Re-fetch the index so badges update
    getRoadmapIndex(true).then(index => setRoadmapEntries(index.entries)).catch(() => {});
    setLogMessages(prev => [...prev, `Roadmap scan complete. Found ${count} ROADMAP ${count === 1 ? 'file' : 'files'}.`]);
  };

  const handleDocsAuditScan = async () => {
    handleAction('docs-audit-scan');
  };

  const handleDocsAuditRefresh = () => {
    setDocsAuditLoading(true);
    setPortfolioAssessmentLoading(true);
    const roadmapAuditRefresh = hasAttemptedRoadmapAuditLoad
      ? getRoadmapAudit({ refresh: true })
      : Promise.resolve(null);

    Promise.allSettled([
      getDocsAudit(true),
      getPortfolioAssessment({ refresh: true }),
      roadmapAuditRefresh,
    ])
      .then(([docsResult, portfolioResult, roadmapResult]) => {
        if (docsResult.status === 'fulfilled') {
          setDocsAuditIndex(docsResult.value);
          setDocsAuditError(null);
        } else {
          const err = docsResult.reason;
          setDocsAuditError(err instanceof Error ? err.message : 'Docs audit refresh failed.');
        }

        if (portfolioResult.status === 'fulfilled') {
          setPortfolioAssessment(portfolioResult.value);
        } else {
          console.warn('Portfolio assessment refresh failed.', portfolioResult.reason);
        }

        if (roadmapResult.status === 'fulfilled' && roadmapResult.value) {
          setRoadmapAuditIndex(roadmapResult.value);
        } else if (roadmapResult.status === 'rejected') {
          console.warn('Roadmap audit refresh failed.', roadmapResult.reason);
        }
      })
      .finally(() => {
        setDocsAuditLoading(false);
        setPortfolioAssessmentLoading(false);
      });
  };

  const handlePreviewCopilotTask = (repoName: string, roadmapPath?: string) => {
    setCopilotTaskPreviewRepo(repoName);
    setCopilotTaskPreviewRoadmapPath(roadmapPath);
    setIsCopilotTaskPreviewOpen(true);
  };

  const handleViewRoadmapAudit = (repoName: string) => {
    setRoadmapAuditModalRepo(repoName);
    setIsRoadmapAuditModalOpen(true);
  };

  const handleRepairRoadmap = (repoName: string) => {
    setRoadmapRepairModalRepo(repoName);
    setIsRoadmapRepairModalOpen(true);
  };

  const handleEvaluateRepo = (repoName: string) => {
    setEvaluationModalRepo(repoName);
  };

  const handleDispatchRelease = (repoName: string) => {
    setDispatchModalRepo(repoName);
  };

  const handleViewGitStatus = (repoName: string, localPath?: string) => {
    setGitStatusModalRepo(repoName);
    setGitStatusModalPath(localPath ?? null);
  };

  const handleGenerateReadme = (repoName: string) => {
    setReadmeGenerateRepo(repoName);
    setReadmeGeneratePath(repos.find(r => r.name === repoName)?.localPath ?? null);
  };

  // Enrich repos with hasRoadmap flag, roadmapState, nextPendingRoadmapItem, and dispatchReadiness
  const reposWithRoadmap = useMemo(() => {
    const roadmapMap = roadmapEntries.length > 0
      ? new Map(roadmapEntries.map(e => [e.repoName.toLowerCase(), e]))
      : new Map<string, typeof roadmapEntries[0]>();
    const auditMap = docsAuditIndex && docsAuditIndex.entries.length > 0
      ? new Map(docsAuditIndex.entries.map(e => [e.repoName.toLowerCase(), e]))
      : new Map<string, DocAuditIndex['entries'][number]>();

    return repos.map(r => {
      const roadmapEntry = roadmapMap.get(r.name.toLowerCase());
      const auditEntry = auditMap.get(r.name.toLowerCase());
      return {
        ...r,
        hasRoadmap: roadmapEntry ? true : r.hasRoadmap,
        roadmapState: roadmapEntry?.roadmapState ?? r.roadmapState,
        nextPendingRoadmapItem: roadmapEntry?.nextPendingItem?.text ?? r.nextPendingRoadmapItem,
        dispatchReadiness: auditEntry?.dispatchReadiness ?? r.dispatchReadiness,
      };
    });
  }, [repos, roadmapEntries, docsAuditIndex]);

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

  const portfolioMission = useMemo(() => {
    if (!portfolioAssessment) {
      return null;
    }

    const entries = portfolioAssessment.entries ?? [];
    const summaryData = portfolioAssessment.summary;
    const localOnly = Number(summaryData.bySourceCoverage?.local ?? 0);
    const githubOnly = Number(summaryData.bySourceCoverage?.github ?? 0);
    const linked = Number(summaryData.bySourceCoverage?.['local+github'] ?? 0);
    const completed = Number(summaryData.byLifecycle?.completed ?? 0);
    const dirtyWorktrees = entries.filter(entry => {
      const statusValue = (entry.gitStatus ?? '').toLowerCase();
      return entry.sourceCoverage !== 'github' && statusValue !== '' && statusValue !== 'clean' && statusValue !== 'unknown';
    }).length;
    const openPrs = entries.reduce((sum, entry) => sum + Number(entry.openPrCount ?? 0), 0);
    const pagesEnabled = entries.filter(entry => Boolean(entry.hasPages)).length;
    const failingActions = entries.filter(entry => {
      const conclusion = (entry.latestWorkflowRunConclusion ?? '').toLowerCase();
      const statusValue = (entry.latestWorkflowRunStatus ?? '').toLowerCase();
      if (conclusion) {
        return !['success', 'neutral', 'skipped'].includes(conclusion);
      }
      return ['failure', 'cancelled', 'timed_out', 'action_required'].includes(statusValue);
    }).length;

    const withScore = (selector: (entry: PortfolioAssessmentEntry) => number | undefined) => {
      const values = entries
        .map(selector)
        .filter((value): value is number => typeof value === 'number' && !Number.isNaN(value));
      if (values.length === 0) {
        return 0;
      }
      return Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
    };

    const topEntries = [...entries]
      .sort((left, right) => {
        const leftValue = left.topValueItem?.valueScore ?? -1;
        const rightValue = right.topValueItem?.valueScore ?? -1;
        if (rightValue !== leftValue) {
          return rightValue - leftValue;
        }
        return (right.pendingItemCount ?? 0) - (left.pendingItemCount ?? 0);
      })
      .slice(0, 6);

    return {
      generatedAt: portfolioAssessment.generatedAt,
      cacheSource: portfolioAssessment.cacheSource,
      cacheAgeSeconds: portfolioAssessment.cacheAgeSeconds,
      signalSources: portfolioAssessment.signalSources,
      totalRepos: summaryData.totalRepos,
      localOnly,
      githubOnly,
      linked,
      missingRoadmap: summaryData.missingRoadmapCount,
      weakRoadmap: summaryData.weakRoadmapCount,
      missingReadme: summaryData.missingReadmeCount,
      ready: summaryData.readyForWorkCount,
      running: summaryData.runningCount,
      blocked: summaryData.blockedCount,
      completed,
      dirtyWorktrees,
      openPrs,
      pagesEnabled,
      failingActions,
      averageReadmeScore: withScore(entry => entry.readmeScore),
      averageRoadmapScore: withScore(entry => entry.roadmapScore),
      averageDocumentationHealthScore: withScore(entry => entry.documentationHealthScore),
      ciCoverage: entries.filter(entry => entry.hasCiSignal).length,
      testCoverage: entries.filter(entry => entry.hasTestSignal).length,
      docsNeedingAttention: entries.filter(entry => (entry.docFindingCount ?? 0) > 0).length,
      topEntries,
    };
  }, [portfolioAssessment]);

  if (error && repos.length === 0) {
    return <div className="text-center p-8 text-red-400">{error}</div>;
  }

  const isScanning = loading || isBackgroundRefreshing || settingsLoading;
  // The background differential re-scan (repos already on screen from cache) is
  // a softer state than a blocking foreground scan.
  const isDifferentialRescan = isBackgroundRefreshing && !loading;
  const scanProgressDetail = scanProgress.scannedCount > 0
    ? `${scanProgress.scannedCount} scanned${scanProgress.latestRepo ? ` · latest: ${scanProgress.latestRepo}` : ''}`
    : null;
  const scanIndicatorLabel = isDifferentialRescan
    ? 'Checking for repository changes…'
    : settingsLoading && !loading
    ? 'Loading…'
    : `Scanning repositories… ${loadingElapsedSec}s`;
  const scanProgressSummary = currentOperation === 'scan'
    ? `${scanProgress.scannedCount} repositories scanned${scanProgress.latestRepo ? ` · latest: ${scanProgress.latestRepo}` : ''}`
    : undefined;

  const healthDot = backendHealth === 'online'
    ? 'bg-green-400'
    : backendHealth === 'offline'
    ? 'bg-red-500'
    : 'bg-yellow-400 animate-pulse';
  const healthLabel = backendHealth === 'online' ? 'Backend: Online' : backendHealth === 'offline' ? 'Backend: Offline' : 'Backend: Connecting…';

  return (
    <div>
      {/* Backend connectivity badge + auto-scan schedule */}
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-3 flex justify-end items-center gap-4">
        {scanSchedule && (
          <span className="inline-flex items-center gap-1.5 text-xs text-gray-500" title={scanSchedule.nextScanAt ? `Next scan: ${new Date(scanSchedule.nextScanAt).toLocaleTimeString()}` : 'Auto-scan disabled'}>
            <span className={`inline-block w-1.5 h-1.5 rounded-full ${scanSchedule.enabled ? 'bg-indigo-400' : 'bg-gray-600'}`} />
            {scanSchedule.enabled
              ? scanSchedule.nextScanAt
                ? (() => {
                    const diffMs = new Date(scanSchedule.nextScanAt).getTime() - Date.now();
                    const diffMin = Math.ceil(diffMs / 60000);
                    return diffMin > 0 ? `Auto-scan in ${diffMin}m` : 'Auto-scan pending';
                  })()
                : 'Auto-scan on'
              : 'Auto-scan off'}
          </span>
        )}
        <span className="inline-flex items-center gap-1.5 text-xs text-gray-400">
          <span className={`inline-block w-2 h-2 rounded-full ${healthDot}`} />
          {healthLabel}
        </span>
      </div>
      {/* Inline scan/refresh progress indicator (non-blocking — the cached repo
          list stays interactive; the differential re-scan is shown here rather
          than in the slide-out drawer). */}
      {isScanning && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-4">
          <div className="flex items-center gap-3 bg-blue-900/20 border border-blue-700/50 rounded-lg px-4 py-2 text-sm text-blue-200">
            <SpinnerIcon className="w-4 h-4 text-blue-400 flex-shrink-0" />
            <span className="flex-shrink-0">{scanIndicatorLabel}</span>
            {scanProgressDetail && (
              <span className="text-blue-300/80 text-xs flex-shrink-0">· {scanProgressDetail}</span>
            )}
            <div className="flex-1 h-1.5 rounded-full bg-blue-900 overflow-hidden">
              <div className="h-full bg-blue-500 animate-pulse rounded-full" style={{ width: '40%' }} />
            </div>
            <button
              onClick={() => setIsLogPanelOpen(true)}
              className="text-blue-300 hover:text-blue-100 underline underline-offset-2 text-xs flex-shrink-0"
            >
              View progress
            </button>
          </div>
        </div>
      )}
      {error && repos.length > 0 && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-4">
          <div className="bg-red-900/20 border border-red-700/50 rounded-lg px-4 py-2 text-sm text-red-300">{error}</div>
        </div>
      )}
      {dataSource?.source === 'local' && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
          <div className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-3 text-sm text-gray-200">
            Showing repositories discovered under <strong>{settings?.basePath}</strong> (scan depth {settings?.scanDepth}).
            {typeof dataSource.repoCount === 'number' && (
              <span className="text-gray-300"> Last scan found <strong>{dataSource.repoCount}</strong> repos{typeof dataSource.scanDurationMs === 'number' ? ` in ${(dataSource.scanDurationMs / 1000).toFixed(1)}s` : ''}.</span>
            )}
            {dataLastUpdated && (
              <span className="text-gray-400"> Data last updated: <strong>{dataLastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</strong>.</span>
            )}
            <span className="text-gray-400"> Use Settings to change workspace path. Connect GitHub API to view repositories that exist on GitHub but are not cloned locally.</span>
          </div>
        </div>
      )}
      {dataSource?.source === 'github' && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
          <div className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-3 text-sm text-gray-200">
            Showing repositories returned by the GitHub API for <strong>{dataSource.username}</strong>.
            {dataLastUpdated && (
              <span className="text-gray-400"> Data fetched at <strong>{dataLastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</strong>.</span>
            )}
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

        {/* Execution throughput metrics (Release 1.2) — shown when queue has activity */}
        {executionMetrics && (executionMetrics.totalCompleted > 0 || executionMetrics.stateCounts.running > 0 || executionMetrics.stateCounts.ready > 0) && (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mt-4">
            <div className="px-3 py-2 bg-gray-800/60 border border-gray-700 rounded-lg text-center">
              <div className="text-lg font-bold text-green-300">{executionMetrics.completedToday}</div>
              <div className="text-xs text-gray-400 mt-0.5">Done Today</div>
            </div>
            <div className="px-3 py-2 bg-gray-800/60 border border-gray-700 rounded-lg text-center">
              <div className="text-lg font-bold text-blue-300">{executionMetrics.completedThisWeek}</div>
              <div className="text-xs text-gray-400 mt-0.5">Done This Week</div>
            </div>
            <div className="px-3 py-2 bg-gray-800/60 border border-gray-700 rounded-lg text-center">
              <div className="text-lg font-bold text-indigo-300">{executionMetrics.stateCounts.running}</div>
              <div className="text-xs text-gray-400 mt-0.5">Running</div>
            </div>
            <div className="px-3 py-2 bg-gray-800/60 border border-gray-700 rounded-lg text-center">
              <div className="text-lg font-bold text-yellow-300">{executionMetrics.stateCounts.ready}</div>
              <div className="text-xs text-gray-400 mt-0.5">Ready</div>
            </div>
            <div className="px-3 py-2 bg-gray-800/60 border border-gray-700 rounded-lg text-center">
              <div className={`text-lg font-bold ${executionMetrics.errorRatePct > 20 ? 'text-red-300' : 'text-gray-300'}`}>
                {executionMetrics.errorRatePct.toFixed(0)}%
              </div>
              <div className="text-xs text-gray-400 mt-0.5">Error Rate</div>
            </div>
            <div className="px-3 py-2 bg-gray-800/60 border border-gray-700 rounded-lg text-center">
              <div className="text-lg font-bold text-gray-300">
                {executionMetrics.avgCurrentRunMins > 0 ? `${executionMetrics.avgCurrentRunMins.toFixed(0)}m` : '—'}
              </div>
              <div className="text-xs text-gray-400 mt-0.5">Avg Run</div>
            </div>
          </div>
        )}

        {(portfolioMission || portfolioAssessmentLoading) && (
          <div className="mt-4 space-y-4">
            <div className="grid grid-cols-1 xl:grid-cols-[1.5fr,1fr] gap-4">
              <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
                <div className="flex items-start justify-between gap-4 flex-wrap">
                  <div>
                    <h2 className="text-lg font-semibold text-white">Portfolio Mission</h2>
                    <p className="text-sm text-gray-400 mt-1">Index-backed collection state for the current portfolio scan.</p>
                  </div>
                  {portfolioMission && (
                    <div className="text-xs text-gray-500 text-right">
                      <div>Generated {new Date(portfolioMission.generatedAt).toLocaleTimeString()}</div>
                      <div>{portfolioMission.cacheSource === 'memory' ? 'Memory cache' : 'Fresh scan'}{portfolioMission.cacheAgeSeconds > 0 ? ` · ${Math.round(portfolioMission.cacheAgeSeconds)}s old` : ''}</div>
                    </div>
                  )}
                </div>

                {portfolioMission ? (
                  <>
                    <div className="flex flex-wrap gap-2 mt-3">
                      {Object.entries(portfolioMission.signalSources).map(([key, value]) => {
                        if (!value) {
                          return null;
                        }

                        const source = value as PortfolioSignalSource;
                        return (
                          <span key={key} className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium ${SIGNAL_SOURCE_STYLES[source] ?? SIGNAL_SOURCE_STYLES.unavailable}`}>
                            <span className="text-gray-300">{formatSignalLabel(key)}</span>
                            <span>{source}</span>
                          </span>
                        );
                      })}
                    </div>

                    <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-6 gap-3 mt-4">
                      {[
                        { label: 'Total', value: portfolioMission.totalRepos, accent: 'text-white' },
                        { label: 'Local Only', value: portfolioMission.localOnly, accent: 'text-slate-200' },
                        { label: 'Linked', value: portfolioMission.linked, accent: 'text-emerald-300' },
                        { label: 'GitHub Only', value: portfolioMission.githubOnly, accent: 'text-indigo-300' },
                        { label: 'Missing ROADMAP', value: portfolioMission.missingRoadmap, accent: 'text-amber-300' },
                        { label: 'Missing README', value: portfolioMission.missingReadme, accent: 'text-amber-300' },
                        { label: 'Weak ROADMAP', value: portfolioMission.weakRoadmap, accent: 'text-orange-300' },
                        { label: 'Ready', value: portfolioMission.ready, accent: 'text-emerald-300' },
                        { label: 'Running', value: portfolioMission.running, accent: 'text-blue-300' },
                        { label: 'Blocked', value: portfolioMission.blocked, accent: 'text-red-300' },
                        { label: 'Completed', value: portfolioMission.completed, accent: 'text-violet-300' },
                        { label: 'Dirty Worktrees', value: portfolioMission.dirtyWorktrees, accent: 'text-yellow-300' },
                        { label: 'Open PRs', value: portfolioMission.openPrs, accent: 'text-cyan-300' },
                        { label: 'Pages Enabled', value: portfolioMission.pagesEnabled, accent: 'text-teal-300' },
                        { label: 'Failing Actions', value: portfolioMission.failingActions, accent: 'text-rose-300' },
                      ].map(metric => (
                        <div key={metric.label} className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3">
                          <div className={`text-lg font-semibold ${metric.accent}`}>{metric.value}</div>
                          <div className="mt-1 text-xs text-gray-400">{metric.label}</div>
                        </div>
                      ))}
                    </div>
                  </>
                ) : (
                  <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                    <SpinnerIcon className="w-5 h-5 animate-spin" />
                    <span>Loading portfolio assessment…</span>
                  </div>
                )}
              </section>

              <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
                <div>
                  <h2 className="text-lg font-semibold text-white">Documentation Health</h2>
                  <p className="text-sm text-gray-400 mt-1">README, ROADMAP, and readiness quality derived from the indexed assessment.</p>
                </div>

                {portfolioMission ? (
                  <div className="space-y-3 mt-4">
                    {[
                      { label: 'README Score', value: portfolioMission.averageReadmeScore, accent: 'bg-blue-500' },
                      { label: 'ROADMAP Score', value: portfolioMission.averageRoadmapScore, accent: 'bg-indigo-500' },
                      { label: 'Docs Health', value: portfolioMission.averageDocumentationHealthScore, accent: 'bg-emerald-500' },
                    ].map(metric => (
                      <div key={metric.label}>
                        <div className="flex items-center justify-between text-sm mb-1">
                          <span className="text-gray-300">{metric.label}</span>
                          <span className="text-white font-medium">{metric.value}%</span>
                        </div>
                        <div className="h-2 rounded-full bg-gray-900 overflow-hidden border border-gray-700">
                          <div className={`h-full ${metric.accent}`} style={{ width: `${metric.value}%` }} />
                        </div>
                      </div>
                    ))}

                    <div className="grid grid-cols-3 gap-3 pt-2">
                      <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3 text-center">
                        <div className="text-lg font-semibold text-sky-300">{portfolioMission.ciCoverage}</div>
                        <div className="mt-1 text-xs text-gray-400">CI Signals</div>
                      </div>
                      <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3 text-center">
                        <div className="text-lg font-semibold text-fuchsia-300">{portfolioMission.testCoverage}</div>
                        <div className="mt-1 text-xs text-gray-400">Test Signals</div>
                      </div>
                      <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3 text-center">
                        <div className="text-lg font-semibold text-amber-300">{portfolioMission.docsNeedingAttention}</div>
                        <div className="mt-1 text-xs text-gray-400">Repos With Findings</div>
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                    <SpinnerIcon className="w-5 h-5 animate-spin" />
                    <span>Computing documentation health…</span>
                  </div>
                )}
              </section>
            </div>

            {portfolioMission && portfolioMission.topEntries.length > 0 && (
              <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
                <div>
                  <h2 className="text-lg font-semibold text-white">Index-Backed Assessment</h2>
                  <p className="text-sm text-gray-400 mt-1">Highest-value and highest-friction repos surfaced from the portfolio assessment order.</p>
                </div>

                <div className="mt-4 space-y-3">
                  {portfolioMission.topEntries.map(entry => (
                    <div key={`${entry.repoName}-${entry.sourceCoverage}`} className="rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-3">
                      <div className="flex items-start justify-between gap-3 flex-wrap">
                        <div>
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className="text-white font-medium">{entry.repoName}</span>
                            <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs capitalize ${LIFECYCLE_STYLES[entry.lifecycleState] ?? LIFECYCLE_STYLES.discovered}`}>
                              {formatLifecycleLabel(entry.lifecycleState)}
                            </span>
                            <span className="inline-flex rounded-full border border-gray-600 px-2 py-0.5 text-xs text-gray-300 bg-gray-800">
                              {entry.maturityLevel}
                            </span>
                            <span className="inline-flex rounded-full border border-cyan-700/40 px-2 py-0.5 text-xs text-cyan-200 bg-cyan-900/20">
                              {entry.dispatchReadiness}
                            </span>
                          </div>
                          <div className="text-sm text-gray-300 mt-2">{entry.recommendedAction}</div>
                          {(entry.topValueItem?.text || entry.nextPendingItemText) && (
                            <div className="text-xs text-gray-400 mt-2">
                              Next focus: <span className="text-gray-200">{entry.topValueItem?.text ?? entry.nextPendingItemText}</span>
                            </div>
                          )}
                          {entry.dispatchReadinessExplanation && (
                            <div className="text-xs text-gray-500 mt-1">{entry.dispatchReadinessExplanation}</div>
                          )}
                        </div>

                        <div className="grid grid-cols-2 gap-2 min-w-[220px]">
                          <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                            <div className="text-sm font-semibold text-blue-200">{entry.readmeScore ?? 0}%</div>
                            <div className="text-[11px] text-gray-500 mt-0.5">README</div>
                          </div>
                          <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                            <div className="text-sm font-semibold text-indigo-200">{entry.roadmapScore ?? 0}%</div>
                            <div className="text-[11px] text-gray-500 mt-0.5">ROADMAP</div>
                          </div>
                          <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                            <div className="text-sm font-semibold text-emerald-200">{entry.documentationHealthScore ?? 0}%</div>
                            <div className="text-[11px] text-gray-500 mt-0.5">Docs Health</div>
                          </div>
                          <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                            <div className="text-sm font-semibold text-cyan-200">{entry.openPrCount ?? 0}</div>
                            <div className="text-[11px] text-gray-500 mt-0.5">Open PRs</div>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            )}
          </div>
        )}

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
            {/* View tabs */}
            <div className="flex border-b border-gray-700 px-4 pt-3 gap-1">
              <button
                onClick={() => setActiveView('repos')}
                className={`px-4 py-2 text-sm font-medium rounded-t border-b-2 transition-colors ${
                  activeView === 'repos'
                    ? 'border-indigo-500 text-indigo-300 bg-gray-700/40'
                    : 'border-transparent text-gray-400 hover:text-gray-200 hover:bg-gray-700/20'
                }`}
              >
                Repository Grid
              </button>
              <button
                onClick={() => setActiveView('operations')}
                className={`px-4 py-2 text-sm font-medium rounded-t border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeView === 'operations'
                    ? 'border-sky-500 text-sky-300 bg-gray-700/40'
                    : 'border-transparent text-gray-400 hover:text-gray-200 hover:bg-gray-700/20'
                }`}
              >
                Operations
                {portfolioAssessment?.summary.readyForWorkCount ? (
                  <span className="inline-flex items-center justify-center w-5 h-5 text-xs rounded-full bg-sky-700 text-sky-100 font-semibold">
                    {portfolioAssessment.summary.readyForWorkCount}
                  </span>
                ) : null}
              </button>
              <button
                onClick={() => setActiveView('work-queue')}
                className={`px-4 py-2 text-sm font-medium rounded-t border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeView === 'work-queue'
                    ? 'border-indigo-500 text-indigo-300 bg-gray-700/40'
                    : 'border-transparent text-gray-400 hover:text-gray-200 hover:bg-gray-700/20'
                }`}
              >
                Work Queue
                {docsAuditIndex && docsAuditIndex.entries.filter(e => e.dispatchReadiness === 'ready').length > 0 && (
                  <span className="inline-flex items-center justify-center w-5 h-5 text-xs rounded-full bg-green-700 text-green-100 font-semibold">
                    {docsAuditIndex.entries.filter(e => e.dispatchReadiness === 'ready').length}
                  </span>
                )}
              </button>
              <button
                onClick={() => setActiveView('execution-queue')}
                className={`px-4 py-2 text-sm font-medium rounded-t border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeView === 'execution-queue'
                    ? 'border-blue-500 text-blue-300 bg-gray-700/40'
                    : 'border-transparent text-gray-400 hover:text-gray-200 hover:bg-gray-700/20'
                }`}
              >
                Execution Queue
              </button>
              <button
                onClick={() => setActiveView('dependencies')}
                className={`px-4 py-2 text-sm font-medium rounded-t border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeView === 'dependencies'
                    ? 'border-teal-500 text-teal-300 bg-gray-700/40'
                    : 'border-transparent text-gray-400 hover:text-gray-200 hover:bg-gray-700/20'
                }`}
              >
                Dependencies
                {dependencyGraph && dependencyGraph.totalEdges > 0 && (
                  <span className="inline-flex items-center justify-center w-5 h-5 text-xs rounded-full bg-teal-700 text-teal-100 font-semibold">
                    {dependencyGraph.totalEdges}
                  </span>
                )}
              </button>
            </div>

            {activeView === 'repos' ? (
              <>
                <ActionBar
                    onAction={handleAction}
                    onExport={handleExport}
                    onRefresh={fetchRepoStatus}
                    onSettingsClick={() => setIsSettingsModalOpen(true)}
                    onInitClick={() => setIsInitModalOpen(true)}
                    onDocReviewClick={() => setIsDocReviewModalOpen(true)}
                    onApiDocsClick={() => setIsApiDocsOpen(true)}
                    onHelpClick={() => setIsHelpOpen(true)}
                    isActionRunning={!!currentOperation}
                    currentOperation={currentOperation}
                    settings={settings}
                    selectedRepos={selectedRepoIds}
                />
                <RepoGrid
                  repos={reposWithRoadmap}
                  onViewArtifacts={handleViewArtifacts}
                  onViewRoadmap={handleViewRoadmap}
                  onViewGitStatus={handleViewGitStatus}
                  dataSource={dataSource}
                  selectedRepos={selectedRepoIds}
                  setSelectedRepos={setSelectedRepoIds}
                  groupBy={groupBy}
                  setGroupBy={setGroupBy}
                />
              </>
            ) : activeView === 'operations' ? (
              <OperationsWorkspaceView
                operationsRepos={operationsRepos}
                loading={operationsReposLoading}
                error={operationsReposError}
                docsAuditIndex={docsAuditIndex}
                roadmapAuditIndex={roadmapAuditIndex}
                onRefresh={() => { refreshOperationsRepos(true).catch(() => {/* surfaced in-panel */}); }}
                onViewRoadmap={handleViewRoadmap}
                onPreviewTask={handlePreviewCopilotTask}
                onViewGitStatus={handleViewGitStatus}
                showIndexedPortfolioNote={dataSource?.source === 'github'}
              />
            ) : activeView === 'work-queue' ? (
              <WorkQueueView
                auditIndex={docsAuditIndex}
                loading={docsAuditLoading}
                error={docsAuditError}
                onRefresh={handleDocsAuditRefresh}
                onScan={handleDocsAuditScan}
                onViewRoadmap={handleViewRoadmap}
                onPreviewTask={handlePreviewCopilotTask}
                onViewRoadmapAudit={handleViewRoadmapAudit}
                onRepairRoadmap={handleRepairRoadmap}
                onLintRoadmap={(repoName) => setLintModalRepo(repoName)}
                onStandardizeReadme={(repoName) => setStandardizeModalRepo(repoName)}
                onGenerateReadme={handleGenerateReadme}
                onEvaluateRepo={handleEvaluateRepo}
                onDispatchRelease={handleDispatchRelease}
                isScanning={currentOperation === 'docs-audit-scan'}
                roadmapAuditIndex={roadmapAuditIndex}
                portfolioAssessment={portfolioAssessment}
              />
            ) : activeView === 'execution-queue' ? (
              <ExecutionQueuePanel
                onDispatchPreviewTask={handlePreviewCopilotTask}
              />
            ) : (
              /* Dependencies view — Release 1.2 */
              <div className="px-4 sm:px-6 lg:px-8 py-4">
                <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
                  <div>
                    <h2 className="text-lg font-semibold text-white">Cross-Repo Dependency Graph</h2>
                    <p className="text-sm text-gray-400 mt-0.5">
                      References detected across portfolio roadmaps (GitHub URLs, hash refs, keyword patterns).
                    </p>
                  </div>
                  <button
                    onClick={() => {
                      setHasAttemptedDepsLoad(false);
                      setDependencyGraph(null);
                    }}
                    disabled={dependencyGraphLoading}
                    className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 disabled:opacity-50 transition-colors"
                  >
                    Refresh
                  </button>
                </div>

                {dependencyGraphLoading && (
                  <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                    <SpinnerIcon className="w-5 h-5 animate-spin" />
                    <span>Scanning roadmaps for dependencies…</span>
                  </div>
                )}

                {!dependencyGraphLoading && (!dependencyGraph || dependencyGraph.summary.length === 0) && (
                  <div className="text-center py-10 text-gray-500 text-sm">
                    <p className="mb-1">No cross-repo dependencies detected.</p>
                    <p className="text-gray-600 text-xs">Dependencies are found via GitHub URLs, <code>RepoName#42</code> refs, and keywords like "depends on" in roadmap files.</p>
                  </div>
                )}

                {!dependencyGraphLoading && dependencyGraph && dependencyGraph.summary.length > 0 && (
                  <div className="space-y-2">
                    {dependencyGraph.summary.map(entry => (
                      <div key={entry.repoName} className="border border-gray-700 rounded-lg bg-gray-800/40 px-4 py-3">
                        <div className="font-semibold text-white text-sm mb-2">{entry.repoName}</div>
                        {entry.dependsOn.length > 0 && (
                          <div className="flex flex-wrap items-center gap-1.5 mb-1.5">
                            <span className="text-xs text-gray-500 w-20 flex-shrink-0">depends on:</span>
                            {entry.dependsOn.map(dep => (
                              <span key={dep} className="text-xs px-1.5 py-0.5 rounded border bg-orange-900/30 text-orange-300 border-orange-700/40">{dep}</span>
                            ))}
                          </div>
                        )}
                        {entry.dependedOnBy.length > 0 && (
                          <div className="flex flex-wrap items-center gap-1.5">
                            <span className="text-xs text-gray-500 w-20 flex-shrink-0">used by:</span>
                            {entry.dependedOnBy.map(src => (
                              <span key={src} className="text-xs px-1.5 py-0.5 rounded border bg-blue-900/30 text-blue-300 border-blue-700/40">{src}</span>
                            ))}
                          </div>
                        )}
                      </div>
                    ))}
                    <div className="text-xs text-gray-600 text-right pt-1">
                      {dependencyGraph.totalEdges} edge{dependencyGraph.totalEdges !== 1 ? 's' : ''} · scanned {new Date(dependencyGraph.scannedAt).toLocaleTimeString()}
                    </div>
                  </div>
                )}
              </div>
            )}
        </div>
      </div>

      <LogPanel
        isOpen={isLogPanelOpen}
        operation={currentOperation}
        messages={logMessages}
        status={logStatus}
        progressSummary={scanProgressSummary}
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

      <DocReviewModal
        isOpen={isDocReviewModalOpen}
        onClose={() => setIsDocReviewModalOpen(false)}
        onRun={handleDocReviewRun}
        defaultRootPath={settings?.basePath}
        defaultDepth={settings?.scanDepth}
      />

      <RoadmapViewerModal
        isOpen={isRoadmapViewerOpen}
        repoName={selectedRoadmapRepo}
        defaultOwner={dataSource?.source === 'github' ? dataSource.username : dataSource?.source === 'local' ? (dataSource.configuredGithubUser ?? null) : null}
        onClose={() => setIsRoadmapViewerOpen(false)}
        onScanComplete={handleRoadmapScanComplete}
      />

      <ApiDocsModal
        isOpen={isApiDocsOpen}
        onClose={() => setIsApiDocsOpen(false)}
      />

      <HelpModal
        isOpen={isHelpOpen}
        onClose={() => setIsHelpOpen(false)}
      />

      <CopilotTaskPreviewModal
        isOpen={isCopilotTaskPreviewOpen}
        repoName={copilotTaskPreviewRepo}
        roadmapPath={copilotTaskPreviewRoadmapPath}
        onClose={() => {
          setIsCopilotTaskPreviewOpen(false);
          setCopilotTaskPreviewRoadmapPath(undefined);
        }}
      />

      <RoadmapAuditModal
        isOpen={isRoadmapAuditModalOpen}
        repoName={roadmapAuditModalRepo}
        onClose={() => setIsRoadmapAuditModalOpen(false)}
      />

      <RoadmapRepairModal
        isOpen={isRoadmapRepairModalOpen}
        repoName={roadmapRepairModalRepo}
        onClose={() => setIsRoadmapRepairModalOpen(false)}
        onRepairApplied={() => {
          setIsRoadmapRepairModalOpen(false);
          // Refresh roadmap audit data after a repair is applied
          getRoadmapAudit({ refresh: true }).then(setRoadmapAuditIndex).catch(() => {});
        }}
      />

      {lintModalRepo && (
        <RoadmapLintModal
          repoName={lintModalRepo}
          onClose={() => setLintModalRepo(null)}
        />
      )}

      {standardizeModalRepo && (
        <ReadmeStandardizationModal
          repoName={standardizeModalRepo}
          repoPath={reposWithRoadmap.find(r => r.name === standardizeModalRepo)?.localPath}
          onClose={() => setStandardizeModalRepo(null)}
          onApplied={() => setStandardizeModalRepo(null)}
        />
      )}

      {evaluationModalRepo && (
        <RepoEvaluationModal
          repoName={evaluationModalRepo}
          localPath={reposWithRoadmap.find(r => r.name === evaluationModalRepo)?.localPath}
          onClose={() => setEvaluationModalRepo(null)}
          onRoadmapCreated={() => {
            // Refresh roadmap index so the new file is detected
            getRoadmapIndex(true).then(idx => setRoadmapEntries(idx.entries ?? [])).catch(() => {});
          }}
        />
      )}

      <RoadmapDispatchModal
        isOpen={dispatchModalRepo !== null}
        repoName={dispatchModalRepo}
        onClose={() => setDispatchModalRepo(null)}
        onDispatchComplete={() => {
          setDispatchModalRepo(null);
          getRoadmapAudit({ refresh: true }).then(setRoadmapAuditIndex).catch(() => {});
        }}
      />

      <RepoGitStatusModal
        isOpen={gitStatusModalRepo !== null}
        repoName={gitStatusModalRepo}
        localPath={gitStatusModalPath}
        onClose={() => { setGitStatusModalRepo(null); setGitStatusModalPath(null); }}
        onStatusChanged={() => { fetchRepoStatus(); }}
      />

      <ReadmeGenerateModal
        isOpen={readmeGenerateRepo !== null}
        repoName={readmeGenerateRepo}
        localPath={readmeGeneratePath}
        onClose={() => { setReadmeGenerateRepo(null); setReadmeGeneratePath(null); }}
        onApplied={() => {
          setReadmeGenerateRepo(null);
          setReadmeGeneratePath(null);
          fetchRepoStatus();
        }}
      />
    </div>
  );
};

export default Dashboard;

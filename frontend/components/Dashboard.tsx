import React, { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import { type RepoStatus, type AppSettings, type OperationType, type GithubInsightsMeta, type OperationResult, type DocReviewRunRequest, type RoadmapEntry, type DocAuditIndex, type RoadmapAuditIndex, type ExecutionMetrics, type ScanSchedule, type RoadmapDependencyGraph, type PortfolioTechInventoryResult, type PortfolioAssessmentEntry, type PortfolioAssessmentResult, type PortfolioTrendResult, type OperationsReposResult, type RepoCurationState } from '../types';
import ActionBar from './ActionBar';
import { isCarriedOverCount } from '../lib/dataProvenance';
import AutomationStatusBadge from './AutomationStatusBadge';
import PackagedItemQueue from './PackagedItemQueue';
import { type PackagedItem } from '../lib/packagedItems';
import { type AutomationHealthPayload } from '../lib/automationStatus';
import RepoGrid from './RepoGrid';
import LogPanel from './LogPanel';
import SettingsModal from './SettingsModal';
import InitModal from './InitModal';
import ArtifactsModal from './ArtifactsModal';
import InsightsView from './InsightsView';
import DocReviewModal from './DocReviewModal';
import RoadmapViewerModal from './RoadmapViewerModal';
import WorkQueueView from './WorkQueueView';
import CopilotTaskPreviewModal from './CopilotTaskPreviewModal';
import RoadmapAuditModal from './RoadmapAuditModal';
import RoadmapRepairModal from './RoadmapRepairModal';
import { ReadmeStandardizationModal } from './ReadmeStandardizationModal';
import { RoadmapLintModal } from './RoadmapLintModal';
import WorkItemTraceModal from './WorkItemTraceModal';
import ExecutionQueuePanel from './ExecutionQueuePanel';
import RepoEvaluationModal from './RepoEvaluationModal';
import TodayView from './TodayView';
import RoadmapDispatchModal from './RoadmapDispatchModal';
import RepositoryImprovementWorkflowModal from './RepositoryImprovementWorkflowModal';
import RepoGitStatusModal from './RepoGitStatusModal';
import ReadmeGenerateModal from './ReadmeGenerateModal';
import HelpModal from './HelpModal';
import OperationsWorkspaceView from './OperationsWorkspaceView';
import { VIEW_META_BY_KEY, type ViewKey } from '../viewMeta';
import DashboardViewTabs, { viewPanelId, viewTabId } from './DashboardViewTabs';
import ErrorBoundary from './ErrorBoundary';
import PortfolioSummarySection from './PortfolioSummarySection';
import { type ViewTabBadges } from '../lib/viewTabs';
import { useAsyncPanel, withPanelTimeout } from '../lib/asyncPanel';
import { getPortfolioSnapshot } from '../services/apiClient';
import ScanProgressChip from './ScanProgressChip';
import TechInventoryPanel from './TechInventoryPanel';
import type { PortfolioSnapshot } from '../types';
import { isRepoNeedsAttention } from '../lib/needsAttention';
import { classifyFetchFailure } from '../lib/fetchFailure';
import { getSettings, startInit, startUpdate, startSync, startArchive, startExport, startDocReview, getRoadmapIndex, triggerRoadmapScan, getDocsAudit, triggerDocsAuditScan, getRoadmapAudit, triggerRoadmapAuditScan, isOptionalApiUnavailableError, getExecutionMetrics, getScanSchedule, getAutomationStatus, getPackagedItems, approvePackagedItem, rejectPackagedItem, getRoadmapDependencies, getPortfolioAssessment, refreshAllPortfolioAssessment, setOperationsRepoCuration, getPortfolioTrend, getOperationsRepos, getRunnerPresence, startPortfolioScan, getPortfolioScanStatus, getPortfolioTechInventory } from '../services/apiClient';
import { type RunnerPresencePayload } from '../lib/runnerPresence';
import { useSse } from '../hooks/useSse';
import { useBackendLog } from '../hooks/useBackendLog';
import { useHealthPing } from '../hooks/useHealthPing';
import { SpinnerIcon, IssuesIcon, ProjectsIcon, BranchIcon, HealthIcon, DocReviewIcon, SyncIcon } from './icons';

interface DashboardProps {
  repos: RepoStatus[];
  loading: boolean;
  /** True while the startup differential re-scan runs in the background. */
  isBackgroundRefreshing?: boolean;
  error: string | null;
  fetchRepoStatus: () => void;
  dataSource:
    | { source: 'sample' }
    | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null; repoCount?: number; scanDurationMs?: number; missingRoots?: string[] }
    | { source: 'github'; username: string }
    | null;
  insightsMeta?: GithubInsightsMeta | null;
  dataLastUpdated?: Date | null;
  /**
   * Open signal for the Settings dialog, driven by the header gear in App. A
   * counter rather than a boolean: each increment is one open request, so the
   * dialog re-opens after being dismissed.
   */
  settingsOpenRequest?: number;
  /**
   * Open signal for the Help dialog, driven by the header Help button. Same
   * counter contract as `settingsOpenRequest`.
   */
  helpOpenRequest?: number;
  /** Connects the GitHub API view; surfaced inside the Settings dialog. */
  onConnectGitHub?: (username: string) => Promise<void>;
  connectedGitHubUser?: string | null;
}

const EXECUTION_METRICS_REFRESH_MS = 15_000;
// Automation runs on a minutes-to-hours interval, so polling it as often as the
// execution metrics would be pure noise against a status that changes slowly.
const AUTOMATION_STATUS_REFRESH_MS = 120_000;

const Dashboard: React.FC<DashboardProps> = ({ repos, loading, isBackgroundRefreshing = false, error, fetchRepoStatus, dataSource, insightsMeta, dataLastUpdated, settingsOpenRequest = 0, helpOpenRequest = 0, onConnectGitHub, connectedGitHubUser }) => {
  const [currentOperation, setCurrentOperation] = useState<OperationType | null>(null);
  const [isLogPanelOpen, setIsLogPanelOpen] = useState(false);
  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);
  // Open on each increment from the header gear. Skips the initial 0 so the
  // dialog does not pop open on mount.
  useEffect(() => {
    if (settingsOpenRequest > 0) setIsSettingsModalOpen(true);
  }, [settingsOpenRequest]);
  const [isInitModalOpen, setIsInitModalOpen] = useState(false);
  const [isArtifactsModalOpen, setIsArtifactsModalOpen] = useState(false);
  const [isDocReviewModalOpen, setIsDocReviewModalOpen] = useState(false);
  const [docReviewTargetRepo, setDocReviewTargetRepo] = useState<string | null>(null);
  const [selectedRepoForArtifacts, setSelectedRepoForArtifacts] = useState<string | null>(null);
  const [isRoadmapViewerOpen, setIsRoadmapViewerOpen] = useState(false);
  const [isHelpOpen, setIsHelpOpen] = useState(false);
  // Mirrors the settings signal above; 0 is the initial value and never opens.
  useEffect(() => {
    if (helpOpenRequest > 0) setIsHelpOpen(true);
  }, [helpOpenRequest]);
  const [selectedRoadmapRepo, setSelectedRoadmapRepo] = useState<string | null>(null);
  const [isCopilotTaskPreviewOpen, setIsCopilotTaskPreviewOpen] = useState(false);
  const [copilotTaskPreviewRepo, setCopilotTaskPreviewRepo] = useState<string | null>(null);
  const [copilotTaskPreviewRoadmapPath, setCopilotTaskPreviewRoadmapPath] = useState<string | undefined>(undefined);
  const [roadmapEntries, setRoadmapEntries] = useState<RoadmapEntry[]>([]);
  const [selectedRepoIds, setSelectedRepoIds] = useState<Set<string>>(new Set());
  const [groupBy, setGroupBy] = useState<'none' | 'status' | 'needsAttention' | 'isStale' | 'lastBuildStatus' | 'roadmapStatus'>('needsAttention');
  // Release 3.6 M3 -- Today is the default landing: the first screen answers
  // what to do next and why, instead of opening on an unranked grid.
  const [activeView, setActiveView] = useState<ViewKey>('today');
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
  const [improvementWorkflowRepo, setImprovementWorkflowRepo] = useState<string | null | undefined>(undefined);
  const [gitStatusModalRepo, setGitStatusModalRepo] = useState<string | null>(null);
  const [gitStatusModalPath, setGitStatusModalPath] = useState<string | null>(null);
  const [readmeGenerateRepo, setReadmeGenerateRepo] = useState<string | null>(null);
  const [readmeGeneratePath, setReadmeGeneratePath] = useState<string | null>(null);

  // Release 1.2 — execution metrics, auto-scan schedule, dependency graph
  const [executionMetrics, setExecutionMetrics] = useState<ExecutionMetrics | null>(null);
  const [executionMetricsLoading, setExecutionMetricsLoading] = useState(true);
  const [executionMetricsRefreshing, setExecutionMetricsRefreshing] = useState(false);
  const [executionMetricsError, setExecutionMetricsError] = useState<string | null>(null);
  const [executionMetricsUpdatedAt, setExecutionMetricsUpdatedAt] = useState<string | null>(null);
  const [scanSchedule, setScanSchedule] = useState<ScanSchedule | null>(null);
  // Release 2.7 Phase D — null means "status unknown", which the badge renders
  // as such. It must never be seeded with a healthy-looking default.
  const [automationStatus, setAutomationStatus] = useState<AutomationHealthPayload | null>(null);
  // Release 2.7 Phase C — the packaged roadmap-item approval queue.
  const [packagedItems, setPackagedItems] = useState<PackagedItem[]>([]);
  const [packagedItemsLoading, setPackagedItemsLoading] = useState(false);
  const [packagedItemsError, setPackagedItemsError] = useState<string | null>(null);
  const [packagedItemsNotice, setPackagedItemsNotice] = useState<string | null>(null);
  // Release 3.1 — whether anything can claim what this panel queues.
  const [runnerPresence, setRunnerPresence] = useState<RunnerPresencePayload | null>(null);
  const [packagedItemBusyId, setPackagedItemBusyId] = useState<string | null>(null);
  // Release 3.1 — whichever id the operator clicked Trace on. Any id the chain
  // minted resolves to the same work item, so this holds it verbatim.
  const [traceModalId, setTraceModalId] = useState<string | null>(null);
  // Release 3.5 milestone 1 -- the one snapshot every view reads. Fetched
  // whenever the repo list lands, so the header, mission and insights figures
  // share one "as of" instant with the grid they sit above.
  const [portfolioSnapshot, setPortfolioSnapshot] = useState<PortfolioSnapshot | null>(null);
  useEffect(() => {
    let cancelled = false;
    getPortfolioSnapshot().then(snap => { if (!cancelled) setPortfolioSnapshot(snap); });
    return () => { cancelled = true; };
  }, [repos]);

  // Release 3.5 milestone 5 -- the dependency panel runs on the shared async
  // state model. Its old wiring swallowed fetch failures into the empty state
  // (a detection failure posing as a clean bill of health) and dropped the
  // scannedAt its own scanner emits.
  const fetchDependencyGraph = useCallback(() => getRoadmapDependencies(true), []);
  const dependencyGraphIsEmpty = useCallback((g: RoadmapDependencyGraph) => g.summary.length === 0, []);
  const { state: depsPanel, load: loadDependencyGraph } = useAsyncPanel<RoadmapDependencyGraph>(
    fetchDependencyGraph, '/api/roadmap/dependencies', dependencyGraphIsEmpty,
  );
  const dependencyGraph = depsPanel.data;
  // Lane 0.16 — the technology inventory the Dependencies tab leads with.
  // A payload whose index predates detection is DATA (the panel explains it),
  // not empty — only a payload with no repos at all counts as empty here.
  const fetchTechInventory = useCallback(() => getPortfolioTechInventory(), []);
  const techInventoryIsEmpty = useCallback((r: PortfolioTechInventoryResult) => r.repoCount === 0, []);
  const { state: techInventoryPanel, load: loadTechInventory } = useAsyncPanel<PortfolioTechInventoryResult>(
    fetchTechInventory, '/api/portfolio/tech-inventory', techInventoryIsEmpty,
  );
  const [portfolioAssessment, setPortfolioAssessment] = useState<PortfolioAssessmentResult | null>(null);
  const [portfolioAssessmentLoading, setPortfolioAssessmentLoading] = useState(false);
  const [portfolioAssessmentError, setPortfolioAssessmentError] = useState<string | null>(null);
  const [portfolioTrend, setPortfolioTrend] = useState<PortfolioTrendResult | null>(null);
  const [portfolioTrendLoading, setPortfolioTrendLoading] = useState(false);
  const [portfolioTrendError, setPortfolioTrendError] = useState<string | null>(null);
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

  // Release 2.3 Phase 5E: ordinary loads run change-aware differential
  // reassessment so unchanged repos are reused from the persisted index;
  // refresh=true keeps the full-signal rebuild for post-operation refreshes.
  const refreshPortfolioAssessment = (refresh = false) => {
    setPortfolioAssessmentLoading(true);
    return getPortfolioAssessment(refresh ? { refresh: true, includeCuration: true } : { scanMode: 'differential', includeCuration: true })
      .then(result => {
        setPortfolioAssessment(result);
        setPortfolioAssessmentError(null);
        return result;
      })
      .catch(err => {
        setPortfolioAssessmentError(err instanceof Error ? err.message : 'Portfolio assessment is unavailable.');
        throw err;
      })
      .finally(() => setPortfolioAssessmentLoading(false));
  };

  // Release 2.3 Phase 5E: explicit operator-driven full reassessment; every
  // repo is reindexed with scanDecisionReason=forced-refresh.
  const [refreshAllInProgress, setRefreshAllInProgress] = useState(false);
  const handleRefreshAllAssessment = () => {
    setRefreshAllInProgress(true);
    setPortfolioAssessmentLoading(true);
    return refreshAllPortfolioAssessment()
      .then(result => {
        setPortfolioAssessment(result);
        setPortfolioAssessmentError(null);
        return result;
      })
      .catch(err => {
        setPortfolioAssessmentError(err instanceof Error ? err.message : 'Full portfolio refresh failed.');
        throw err;
      })
      .finally(() => {
        setRefreshAllInProgress(false);
        setPortfolioAssessmentLoading(false);
      });
  };

  // Release 2.3 Phase 5D: operator curation from the Repository Grid.
  // Persists via the stable repoId when the assessment provides one, falling
  // back to local path / repo name which the host resolves server-side.
  const handleSetRepoCuration = async (repo: RepoStatus, curationState: RepoCurationState) => {
    const repoKey = repo.repoId ?? repo.localPath ?? repo.name;
    const result = await setOperationsRepoCuration(repoKey, curationState);
    setPortfolioAssessment(prev => {
      if (!prev) return prev;
      return {
        ...prev,
        entries: prev.entries.map(entry => {
          const matches =
            (repo.repoId && entry.repoId === repo.repoId) ||
            (repo.localPath && entry.localPath && entry.localPath.trim().toLowerCase() === repo.localPath.trim().toLowerCase()) ||
            entry.repoName.toLowerCase() === repo.name.toLowerCase();
          if (!matches) return entry;
          return { ...entry, curationState: result.curationState, curationUpdatedAt: result.updatedAt };
        }),
      };
    });
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

  // The Today staleness banner's remedy. Starting is the button's job; progress
  // is the header chip's; this watcher's only job is to re-pull the ranking
  // (entries + basis) once the scan reaches a terminal state, so the banner
  // clears — or restates its reasons — from the rebuilt index rather than
  // staying frozen on the pre-scan verdict.
  const scanCompletionWatchRef = useRef(false);
  const watchScanThenRefreshRanking = () => {
    if (scanCompletionWatchRef.current) return;
    scanCompletionWatchRef.current = true;
    const pollMs = 5000;
    let remainingPolls = 360; // ~30 min; past that the operator still has Refresh.
    const poll = async () => {
      if (remainingPolls-- <= 0) {
        scanCompletionWatchRef.current = false;
        return;
      }
      try {
        const status = await getPortfolioScanStatus();
        if (status.state === 'running') {
          setTimeout(poll, pollMs);
          return;
        }
      } catch {
        // A failed probe is silence, not an outcome; keep listening.
        setTimeout(poll, pollMs * 2);
        return;
      }
      scanCompletionWatchRef.current = false;
      // Cancelled/failed scans keep their completed phases, so refresh on every
      // terminal state — the basis says whatever is now true.
      refreshOperationsRepos(false).catch(() => {/* surfaced in-panel */});
    };
    setTimeout(poll, pollMs);
  };

  const handleRunPortfolioScan = async () => {
    const result = await startPortfolioScan();
    watchScanThenRefreshRanking();
    return { started: result.started, alreadyRunning: result.alreadyRunning };
  };

  const refreshExecutionMetrics = useCallback(async ({ background = false }: { background?: boolean } = {}) => {
    if (background) {
      setExecutionMetricsRefreshing(true);
    } else {
      setExecutionMetricsLoading(true);
    }

    try {
      // Release 3.5 milestone 5 — the Insights refresh indicator's fetch gets
      // the shared 10s deadline.
      const result = await withPanelTimeout(getExecutionMetrics(), '/api/execution/metrics');
      setExecutionMetrics(result);
      setExecutionMetricsError(null);
      setExecutionMetricsUpdatedAt(new Date().toISOString());
      return result;
    } catch (err) {
      setExecutionMetricsError(err instanceof Error ? err.message : 'Execution metrics are unavailable.');
      throw err;
    } finally {
      if (background) {
        setExecutionMetricsRefreshing(false);
      } else {
        setExecutionMetricsLoading(false);
      }
    }
  }, []);

  // Release 2.7 Phase C — approval queue. Unlike the automation status badge,
  // a failure here surfaces in-panel: an empty list rendered after a failed
  // fetch would read as "nothing needs approval", which is the same false-green
  // the automation badge exists to prevent.
  const refreshPackagedItems = useCallback(async () => {
    setPackagedItemsLoading(true);
    try {
      const result = await getPackagedItems();
      setPackagedItems(result.items);
      setPackagedItemsError(null);
    } catch (err) {
      setPackagedItemsError(err instanceof Error ? err.message : 'The packaged-item queue is unavailable.');
    } finally {
      setPackagedItemsLoading(false);
    }
    // Release 3.1 — read presence with the queue, not separately. Approving here
    // enqueues into the same room the dispatch wizard queues into, so this panel
    // must be able to say whether anything is in it. getRunnerPresence resolves
    // null rather than throwing, so a status hiccup cannot break the queue.
    setRunnerPresence(await getRunnerPresence());
  }, []);

  const handleApprovePackagedItem = useCallback(async (packetId: string) => {
    setPackagedItemBusyId(packetId);
    try {
      const result = await approvePackagedItem(packetId);
      setPackagedItemsError(null);
      setPackagedItemsNotice(
        result.dispatched
          ? `Approved and queued for the operator runner (run ${result.dispatchRunId ?? 'unknown'}) on branch ${result.branch ?? 'unknown'}. Nothing was pushed or merged.`
          : 'Approved. Nothing was dispatched.'
      );
    } catch (err) {
      // A 409 here is the backend refusing the transition or the budget guard
      // re-pricing the item — both are decisions worth showing verbatim.
      setPackagedItemsNotice(null);
      setPackagedItemsError(err instanceof Error ? err.message : 'Approval failed.');
    } finally {
      setPackagedItemBusyId(null);
      await refreshPackagedItems();
    }
  }, [refreshPackagedItems]);

  const handleRejectPackagedItem = useCallback(async (packetId: string) => {
    const reason = window.prompt('Why is this packaged item being rejected? (recorded in the append-only audit trail)');
    if (reason === null) return;
    setPackagedItemBusyId(packetId);
    try {
      await rejectPackagedItem(packetId, reason.trim() || 'Rejected by the operator.');
      setPackagedItemsError(null);
      setPackagedItemsNotice('Packet rejected. It will not be dispatched.');
    } catch (err) {
      setPackagedItemsNotice(null);
      setPackagedItemsError(err instanceof Error ? err.message : 'Rejection failed.');
    } finally {
      setPackagedItemBusyId(null);
      await refreshPackagedItems();
    }
  }, [refreshPackagedItems]);

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

  useEffect(() => {
    if (!portfolioAssessment) {
      setPortfolioTrend(null);
      setPortfolioTrendError(null);
      setPortfolioTrendLoading(false);
      return;
    }

    let cancelled = false;
    setPortfolioTrendLoading(true);

    getPortfolioTrend({ days: 90 })
      .then(result => {
        if (cancelled) {
          return;
        }
        setPortfolioTrend(result);
        setPortfolioTrendError(null);
      })
      .catch(err => {
        if (cancelled) {
          return;
        }
        setPortfolioTrendError(err instanceof Error ? err.message : 'Portfolio analytics are unavailable.');
      })
      .finally(() => {
        if (!cancelled) {
          setPortfolioTrendLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [portfolioAssessment?.generatedAt, portfolioAssessment?.count]);

  // Release 1.2 — fetch execution metrics and auto-scan schedule on mount
  useEffect(() => {
    refreshExecutionMetrics().catch(() => {/* surfaced in-card */});
    getScanSchedule().then(setScanSchedule).catch(() => {/* silent */});
    // getAutomationStatus resolves null on failure rather than throwing.
    getAutomationStatus().then(setAutomationStatus);
    refreshPackagedItems();
    // refreshPackagedItems is stable (useCallback with no deps).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshExecutionMetrics]);

  // Release 2.7 Phase D — an overdue scheduler only becomes overdue with the
  // passage of time, so this has to re-poll; a load-once fetch would show the
  // status as it was when the tab was opened and never update.
  useEffect(() => {
    const intervalId = window.setInterval(() => {
      getAutomationStatus().then(setAutomationStatus);
    }, AUTOMATION_STATUS_REFRESH_MS);

    return () => window.clearInterval(intervalId);
  }, []);

  useEffect(() => {
    const intervalId = window.setInterval(() => {
      refreshExecutionMetrics({ background: true }).catch(() => {/* surfaced in-card */});
    }, EXECUTION_METRICS_REFRESH_MS);

    return () => window.clearInterval(intervalId);
  }, [refreshExecutionMetrics]);

  // Release 1.2 — load dependency graph when Dependencies tab is first opened.
  // (Release 3.5: through the async panel — a failure is an error with a
  // retry, never a silent empty state.)
  useEffect(() => {
    if (activeView !== 'dependencies' || depsPanel.phase !== 'idle') return;
    void loadDependencyGraph();
  }, [activeView, depsPanel.phase, loadDependencyGraph]);

  useEffect(() => {
    if (activeView !== 'dependencies' || techInventoryPanel.phase !== 'idle') return;
    void loadTechInventory();
  }, [activeView, techInventoryPanel.phase, loadTechInventory]);

  useEffect(() => {
    // Release 3.6 M3: the Today landing ranks from the same payload, so it
    // loads on the default view as well as on Operations.
    if ((activeView !== 'operations' && activeView !== 'today') || hasAttemptedOperationsLoad) {
      return;
    }

    setHasAttemptedOperationsLoad(true);
    refreshOperationsRepos(false).catch(err => {
      const message = err instanceof Error ? err.message : '';
      if (/indexed portfolio|operations workspace is not ready/i.test(message)) {
        refreshOperationsRepos(true).catch(() => {/* surfaced in-panel */});
      }
    });
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
        // Clear the operation so the toolbar re-enables. The scan panel is not
        // auto-opened, so unlike a manual op there is no panel-close to reset it;
        // without this the action buttons stay disabled forever after first load.
        setCurrentOperation(null);
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
    // Refresh only when closing after an active *manual* operation (its results
    // changed repo state). A completed scan already reset currentOperation to
    // null (and produced fresh data), so closing its progress drawer must not
    // kick off a redundant rescan.
    const hadActiveManualOp = !!currentOperation && currentOperation !== 'scan';
    setIsLogPanelOpen(false);
    setCurrentOperation(null);
    setLogStatus('idle');
    prevBackendLogCountRef.current = 0;
    if (hadActiveManualOp) {
      fetchRepoStatus();
      refreshExecutionMetrics({ background: true }).catch(() => {/* surfaced in-card */});
    }
  };

  const handleSaveSettings = (newSettings: AppSettings) => {
    setSettings(newSettings);
    setIsSettingsModalOpen(false);
    fetchRepoStatus(); // Refresh, as some settings might affect repo status (e.g. scan depth)
  };

  const handleInit = async (githubUser: string, cloneOwned: boolean, basePath?: string) => {
      try {
        await startInit(githubUser, cloneOwned, basePath);
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
    // Re-fetch roadmap and operations signals so maturity-dependent views stay in sync.
    Promise.allSettled([
      getRoadmapIndex(true).then(index => setRoadmapEntries(index.entries)),
      getRoadmapAudit({ refresh: true }).then(setRoadmapAuditIndex),
      refreshOperationsRepos(true),
    ]).catch(() => {});
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

  const handleStartImprovementWorkflow = (repoName?: string) => {
    setImprovementWorkflowRepo(repoName ?? null);
  };

  const handleViewGitStatus = (repoName: string, localPath?: string) => {
    setGitStatusModalRepo(repoName);
    setGitStatusModalPath(localPath ?? null);
  };

  const handleGenerateReadme = (repoName: string) => {
    setReadmeGenerateRepo(repoName);
    setReadmeGeneratePath(repos.find(r => r.name === repoName)?.localPath ?? null);
  };

  // Enrich repos with roadmap/doc context plus differential scan metadata when available.
  const reposWithRoadmap = useMemo(() => {
    const roadmapMap = roadmapEntries.length > 0
      ? new Map(roadmapEntries.map(e => [e.repoName.toLowerCase(), e]))
      : new Map<string, typeof roadmapEntries[0]>();
    const auditMap = docsAuditIndex && docsAuditIndex.entries.length > 0
      ? new Map(docsAuditIndex.entries.map(e => [e.repoName.toLowerCase(), e]))
      : new Map<string, DocAuditIndex['entries'][number]>();
    const assessmentByPath = new Map<string, PortfolioAssessmentEntry>();
    const assessmentByName = new Map<string, PortfolioAssessmentEntry>();
    (portfolioAssessment?.entries ?? []).forEach(entry => {
      const nameKey = (entry.repoName ?? '').trim().toLowerCase();
      if (nameKey && !assessmentByName.has(nameKey)) {
        assessmentByName.set(nameKey, entry);
      }

      const pathKey = (entry.localPath ?? '').trim().toLowerCase();
      if (pathKey && !assessmentByPath.has(pathKey)) {
        assessmentByPath.set(pathKey, entry);
      }
    });

    return repos.map(r => {
      const roadmapEntry = roadmapMap.get(r.name.toLowerCase());
      const auditEntry = auditMap.get(r.name.toLowerCase());
      const assessmentEntry =
        (r.localPath ? assessmentByPath.get(r.localPath.trim().toLowerCase()) : undefined) ??
        assessmentByName.get(r.name.toLowerCase());

      return {
        ...r,
        hasRoadmap: roadmapEntry ? true : r.hasRoadmap,
        roadmapState: roadmapEntry?.roadmapState ?? r.roadmapState,
        nextPendingRoadmapItem: roadmapEntry?.nextPendingItem?.text ?? r.nextPendingRoadmapItem,
        dispatchReadiness: auditEntry?.dispatchReadiness ?? r.dispatchReadiness,
        changeState: assessmentEntry?.changeState ?? r.changeState,
        scanDecisionReason: assessmentEntry?.scanDecisionReason ?? r.scanDecisionReason,
        headCommitSha: assessmentEntry?.headCommitSha ?? r.headCommitSha,
        lastIndexedCommitSha: assessmentEntry?.lastIndexedCommitSha ?? r.lastIndexedCommitSha,
        lastScanStatus: assessmentEntry?.lastScanStatus ?? r.lastScanStatus,
        lastScanError: assessmentEntry?.lastScanError ?? r.lastScanError,
        repoId: assessmentEntry?.repoId ?? r.repoId,
        curationState: assessmentEntry?.curationState ?? r.curationState,
        curationUpdatedAt: assessmentEntry?.curationUpdatedAt ?? r.curationUpdatedAt,
      };
    });
  }, [repos, roadmapEntries, docsAuditIndex, portfolioAssessment]);

  const summary = useMemo(() => {
    // Release 3.5 milestone 3 -- portfolio math runs over the in-scope set.
    // Absent classification (older cached payloads) reads in-scope, so a
    // missing policy cannot shrink the portfolio.
    const inScopeRepos = reposWithRoadmap.filter(r => r.scope?.inScope !== false);
    const total = inScopeRepos.length;
    const dirty = inScopeRepos.filter(r => r.status === 'dirty' || r.uncommittedChanges > 0).length;
    const stale = inScopeRepos.filter(r => r.isStale).length;
    const commitsThisWeek = inScopeRepos.reduce((sum, r) => sum + (r.commitsLastWeek ?? 0), 0);
    const commitsThisMonth = inScopeRepos.reduce((sum, r) => sum + (r.commitsLastMonth ?? 0), 0);
    // "Needs Attention" = repos with an ACTIONABLE problem, not the ambient
    // baseline (Release 2.6 Phase 1). Shared pure predicate — see
    // frontend/lib/needsAttention.ts (Release 2.7 Phase D dedup).
    const needsAttention = inScopeRepos.filter(r => isRepoNeedsAttention(r)).length;

    // Extended metrics -- same in-scope set as the headline counts.
    const totalIssues = inScopeRepos.reduce((sum, r) => sum + (r.extended?.openIssuesCount || 0), 0);
    const totalProjects = inScopeRepos.reduce((sum, r) => sum + (r.extended?.projectsCount || 0), 0);
    const totalStaleBranches = inScopeRepos.reduce((sum, r) => sum + (r.extended?.staleBranches || 0), 0);
    const reposWithVulnerabilities = inScopeRepos.filter(r => (r.extended?.vulnerabilitiesCount || 0) > 0).length;
    const avgHealthScore = inScopeRepos.length > 0
      ? Math.round(inScopeRepos.reduce((sum, r) => sum + (r.extended?.healthScore || 0), 0) / inScopeRepos.length)
      : 0;

    return {
      total, dirty, stale, commitsThisWeek, commitsThisMonth, needsAttention,
      totalIssues, totalProjects, totalStaleBranches, reposWithVulnerabilities, avgHealthScore
    };
  }, [reposWithRoadmap]);

  // Release 3.5 milestone 3 -- the scope statement under the KPI row. Derived
  // from the per-repo classifications the scan attached, so the statement and
  // the counts cannot disagree about which set was counted.
  const scopeCounts = useMemo(() => {
    const excluded = reposWithRoadmap.filter(r => r.scope && !r.scope.inScope);
    if (excluded.length === 0) return null;
    return {
      inScope: reposWithRoadmap.length - excluded.length,
      vendored: excluded.filter(r => r.scope?.classification === 'vendored').length,
      archived: excluded.filter(r => r.scope?.classification === 'archived').length,
      excludedPath: excluded.filter(r => r.scope?.classification === 'excluded-path').length,
    };
  }, [reposWithRoadmap]);

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
    // Release 3.1 "enabled means available": every terminal screen says what
    // comes next. This one used to render the raw exception string alone.
    const failure = classifyFetchFailure(error, { hasRepos: repos.length > 0 });
    return (
      <div className="mx-auto max-w-xl p-8" data-testid="dashboard-load-failure">
        <div className="rounded-lg border border-red-800/50 bg-red-950/20 px-5 py-4">
          <div className="text-base font-medium text-red-200">{failure?.headline ?? 'The dashboard could not load.'}</div>
          <div className="mt-2 text-sm text-gray-300">{failure?.nextStep ?? 'Retry, then check the API host log.'}</div>
          {failure?.detail && (
            <div className="mt-3 rounded border border-gray-700 bg-gray-900/60 px-3 py-2 font-mono text-xs text-gray-400 break-all">
              {failure.detail}
            </div>
          )}
          <div className="mt-4 flex flex-wrap items-center gap-2">
            {failure?.retryLabel && (
              <button
                onClick={fetchRepoStatus}
                disabled={loading}
                data-testid="dashboard-load-failure-retry"
                title={loading ? 'A load is already in progress.' : 'Re-runs the repository status request.'}
                className="inline-flex items-center gap-1.5 rounded border border-red-700/60 bg-red-900/30 px-3 py-1.5 text-sm text-red-100 hover:bg-red-900/50 disabled:opacity-50"
              >
                {loading && <SpinnerIcon className="w-3.5 h-3.5 animate-spin" />}
                {loading ? 'Retrying…' : failure.retryLabel}
              </button>
            )}
            <button
              onClick={() => setIsSettingsModalOpen(true)}
              disabled={!settings}
              title={settings
                ? 'Opens Settings, where local roots and the GitHub owner are configured.'
                : 'Settings could not be loaded from the backend, so they cannot be edited until the connection is restored.'}
              className="rounded border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 disabled:opacity-50"
            >
              Open Settings
            </button>
          </div>
        </div>
        {/* This branch returns early, so the modal has to be rendered here too —
            otherwise the control above opens nothing. */}
        {settings && (
          <SettingsModal
            isOpen={isSettingsModalOpen}
            onClose={() => setIsSettingsModalOpen(false)}
            onSave={handleSaveSettings}
            currentSettings={settings}
            onConnectGitHub={onConnectGitHub}
            connectedGitHubUser={connectedGitHubUser}
          />
        )}
      </div>
    );
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
  const sourceLabel = dataSource?.source === 'github'
    ? `GitHub API: ${dataSource.username}`
    : dataSource?.source === 'local'
      ? `Workspace: ${settings?.basePath ?? dataSource.workspacePath ?? 'Unknown'}`
      : 'Sample data source';
  const missingRoots = dataSource?.source === 'local' ? dataSource.missingRoots ?? [] : [];

  // Tab / bottom-nav badges are index-backed too, and a badge has no room for a
  // sentence — so when the count describes a different repo set than the live
  // scan it is restyled amber with an explanatory tooltip rather than rendered
  // as a plain number that reads as current.
  const queueReadyCount = docsAuditIndex
    ? docsAuditIndex.entries.filter(e => e.dispatchReadiness === 'ready').length
    : 0;
  const operationsReadyCount = portfolioAssessment?.summary.readyForWorkCount ?? 0;
  const operationsBadgeCarriedOver = isCarriedOverCount(repos.length, operationsReadyCount);
  const queueBadgeCarriedOver = isCarriedOverCount(repos.length, queueReadyCount);
  const carriedOverBadgeTitle =
    'Carried over from the last completed scan — the current scan found no repositories, so this count may not match the workspace. Re-scan to reconcile.';

  // One descriptor per badged tab. The strip decides visibility (positive
  // counts only) and styling; this only supplies the numbers and their
  // provenance.
  const viewTabBadges: ViewTabBadges = {
    'operations': {
      count: operationsReadyCount,
      carriedOver: operationsBadgeCarriedOver,
      title: carriedOverBadgeTitle,
    },
    'work-queue': {
      count: queueReadyCount,
      carriedOver: queueBadgeCarriedOver,
      title: carriedOverBadgeTitle,
    },
    'dependencies': { count: dependencyGraph?.totalEdges ?? 0 },
  };

  const scanMetaLabel = dataSource?.source === 'local' && typeof dataSource.repoCount === 'number'
    // At zero, "0 repos" alone reads as a broken tool when index-backed panels
    // below still show figures; name it as a property of *this* scan.
    ? `${dataSource.repoCount === 0 ? 'No repos in this scan' : `${dataSource.repoCount} scanned${scopeCounts ? ` · ${scopeCounts.inScope} in-scope` : ''}`}${typeof dataSource.scanDurationMs === 'number' ? ` · ${(dataSource.scanDurationMs / 1000).toFixed(1)}s scan` : ''}`
    : dataSource?.source === 'github' && insightsMeta
      ? `Showing ${insightsMeta.fetchedRepos} of ${insightsMeta.totalRepos} GitHub repositories`
      : null;

  return (
    <div className="pb-20 md:pb-0">
      {/* Backend connectivity badge + auto-scan schedule */}
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-3 flex justify-end items-center gap-4">
        <ScanProgressChip />
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
      {/* A configured root that is not on disk is THE reason a scan comes back
          empty while everything else reports healthy. It gets a hard, top-of-page
          alert naming the exact path — not a subtle badge — because every other
          signal on this screen (Backend: Online, green source badge, a fast
          "successful" scan) actively suggests the tool is fine. */}
      {missingRoots.length > 0 && (
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-4">
          <div
            data-testid="missing-workspace-root-alert"
            role="alert"
            className="flex items-start gap-3 rounded-lg border border-red-600 bg-red-900/30 px-4 py-3 text-sm text-red-100"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5 flex-shrink-0 mt-0.5 text-red-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <circle cx="12" cy="12" r="10" /><line x1="15" y1="9" x2="9" y2="15" /><line x1="9" y1="9" x2="15" y2="15" />
            </svg>
            <div className="min-w-0 flex-1">
              <div className="font-semibold">
                Workspace path not found — this is why no repositories were found.
              </div>
              <div className="mt-1 break-all text-red-200">
                {missingRoots.map(root => (
                  <div key={root}><code className="bg-red-950/60 px-1 py-0.5 rounded">{root}</code></div>
                ))}
              </div>
              <div className="mt-1.5 text-red-200/90">
                The scan completed successfully but had nothing to walk. Check the path for typos, and that any external or network drive is connected.
              </div>
            </div>
            <button
              onClick={() => setIsSettingsModalOpen(true)}
              className="flex-shrink-0 px-3 py-1.5 text-xs font-semibold rounded border border-red-500 bg-red-800/60 text-red-50 hover:bg-red-700/70 transition-colors"
            >
              Fix in Settings
            </button>
          </div>
        </div>
      )}
      <PortfolioSummarySection
        sourceLabel={sourceLabel}
        scanMetaLabel={scanMetaLabel}
        dataLastUpdated={dataLastUpdated}
        rateLimit={dataSource?.source === 'github' ? insightsMeta?.rateLimit ?? null : null}
        summary={summary}
        scope={scopeCounts}
      />

      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="bg-gray-800/50 border border-gray-700 rounded-lg mt-4">
            <DashboardViewTabs
              activeView={activeView}
              onSelectView={setActiveView}
              badges={viewTabBadges}
            />

            {/* Per-view boundary: a crashed panel degrades to a named error
                card while the tab strip and the other views keep working.
                key={activeView} resets the boundary on every tab switch, so
                one broken view never locks the operator out of the rest.

                The tabpanel wrapper closes the ARIA loop the tab strip opens:
                each tab's aria-controls points here, and this points back at
                the tab that selected it. Only the active panel is rendered, so
                one wrapper carrying the active view's id is the whole set. */}
            <div
              role="tabpanel"
              id={viewPanelId(activeView)}
              aria-labelledby={viewTabId(activeView)}
              tabIndex={0}
            >
            <ErrorBoundary key={activeView} label={`The ${VIEW_META_BY_KEY[activeView].label} view`}>
            {activeView === 'today' ? (
              <TodayView
                entries={operationsRepos?.entries ?? []}
                basis={operationsRepos?.basis}
                isLoading={operationsReposLoading}
                onOpenRepo={(_repoId, repoName) => setEvaluationModalRepo(repoName)}
                onRunAction={row => setEvaluationModalRepo(row.repoName)}
                onRunScan={handleRunPortfolioScan}
              />
            ) : activeView === 'repos' ? (
              <>
                <ActionBar
                    onAction={handleAction}
                    onExport={handleExport}
                    onRefresh={fetchRepoStatus}
                    onInitClick={() => setIsInitModalOpen(true)}
                  onDocReviewClick={() => { setDocReviewTargetRepo(null); setIsDocReviewModalOpen(true); }}
                    isActionRunning={!!currentOperation}
                    currentOperation={currentOperation}
                    settings={settings}
                    selectedRepos={selectedRepoIds}
                    repoCount={repos.length}
                    missingRoots={missingRoots}
                />
                <RepoGrid
                  repos={reposWithRoadmap}
                  onViewArtifacts={handleViewArtifacts}
                  onViewRoadmap={handleViewRoadmap}
                  onViewGitStatus={handleViewGitStatus}
                  onRunRepoAction={(operation, repoId) => { handleAction(operation, [repoId]); }}
                  onOpenDocReview={(repoName) => { setDocReviewTargetRepo(repoName); setIsDocReviewModalOpen(true); }}
                  onRunRoadmapScan={(repoName) => {
                    setCurrentOperation('roadmap-scan');
                    setIsLogPanelOpen(true);
                    setLogStatus('running');
                    setLogMessages([`Starting: roadmap-scan for ${repoName}...`]);
                    triggerRoadmapScan(repoName)
                      .then(result => {
                        setRoadmapEntries(result.entries);
                        setLogMessages(prev => [...prev, `Scan complete for ${repoName}. Found ${result.count} ROADMAP ${result.count === 1 ? 'file' : 'files'}.`]);
                        setLogStatus('success');
                      })
                      .catch(err => {
                        const message = err instanceof Error ? err.message : 'Scoped roadmap scan failed.';
                        setLogMessages(prev => [...prev, `ERROR: ${message}`]);
                        setLogStatus('error');
                      })
                      .finally(() => {
                        setCurrentOperation(null);
                      });
                  }}
                  dataSource={dataSource}
                  selectedRepos={selectedRepoIds}
                  setSelectedRepos={setSelectedRepoIds}
                  groupBy={groupBy}
                  setGroupBy={setGroupBy}
                  scanSummary={portfolioAssessment?.scanSummary ?? null}
                  scanGeneratedAt={portfolioAssessment?.generatedAt}
                  onRefreshAll={dataSource?.source === 'local' ? () => handleRefreshAllAssessment().catch(() => {/* surfaced via assessment error state */}) : undefined}
                  refreshAllInProgress={refreshAllInProgress}
                  onSetCuration={dataSource?.source === 'local' ? handleSetRepoCuration : undefined}
                />
              </>
            ) : activeView === 'insights' ? (
              /* Release 2.6/Lane 0.5 fix: this content used to render in a
                 container ABOVE the tab strip, so clicking "Insights" pushed the
                 tab bar off-screen and the panel here held only a sentence
                 pointing upward. It now renders where the operator clicked. */
              <InsightsView
                repos={repos}
                isLocalSource={dataSource?.source === 'local'}
                extendedSummary={summary}
                executionMetrics={executionMetrics}
                executionMetricsLoading={executionMetricsLoading}
                executionMetricsRefreshing={executionMetricsRefreshing}
                executionMetricsError={executionMetricsError}
                executionMetricsUpdatedAt={executionMetricsUpdatedAt}
                onRefreshExecutionMetrics={() => {
                  refreshExecutionMetrics({ background: executionMetrics !== null }).catch(() => {/* surfaced in-card */});
                }}
                portfolioMission={portfolioMission}
                portfolioSnapshot={portfolioSnapshot}
                portfolioAssessment={portfolioAssessment}
                portfolioAssessmentLoading={portfolioAssessmentLoading}
                portfolioAssessmentError={portfolioAssessmentError}
                onRetryAssessment={() => { refreshPortfolioAssessment(true).catch(() => {/* surfaced in-panel */}); }}
                portfolioTrend={portfolioTrend}
                portfolioTrendLoading={portfolioTrendLoading}
                portfolioTrendError={portfolioTrendError}
                onRetryTrend={() => {
                  refreshPortfolioAssessment(true)
                    .then(() => getPortfolioTrend({ days: 90 }))
                    .then(result => {
                      setPortfolioTrend(result);
                      setPortfolioTrendError(null);
                    })
                    .catch(err => setPortfolioTrendError(err instanceof Error ? err.message : 'Portfolio analytics are unavailable.'));
                }}
              />
            ) : activeView === 'operations' ? (
              <>
              {/* Release 2.7 Phase D — automation acts on this tab's curated
                  subset, so a scheduler that has stopped belongs here, next to
                  the work it was supposed to be doing. */}
              <div className="mb-3 flex flex-wrap items-center justify-end gap-2">
                <AutomationStatusBadge status={automationStatus} />
                {/* Phase C's packaging cron is a SECOND scheduler with its own
                    history file and its own health reader, so it gets its own
                    badge. One merged badge would let a live doc cron mask a
                    dead packaging cron — the exact failure the split files
                    exist to prevent. */}
                <AutomationStatusBadge
                  status={automationStatus?.packaging ?? null}
                  subject="Packaging"
                  testId="packaging-status-badge"
                />
              </div>
              <PackagedItemQueue
                items={packagedItems}
                loading={packagedItemsLoading}
                error={packagedItemsError}
                notice={packagedItemsNotice}
                busyPacketId={packagedItemBusyId}
                runner={runnerPresence}
                onRefresh={() => { refreshPackagedItems(); }}
                onApprove={handleApprovePackagedItem}
                onReject={handleRejectPackagedItem}
                onViewTrace={setTraceModalId}
              />
              <OperationsWorkspaceView
                operationsRepos={operationsRepos}
                loading={operationsReposLoading}
                error={operationsReposError}
                docsAuditIndex={docsAuditIndex}
                roadmapAuditIndex={roadmapAuditIndex}
                onRefresh={() => { refreshOperationsRepos(true).catch(() => {/* surfaced in-panel */}); }}
                onRepairRoadmap={handleRepairRoadmap}
                onViewRoadmap={handleViewRoadmap}
                onPreviewTask={handlePreviewCopilotTask}
                onViewGitStatus={handleViewGitStatus}
                showIndexedPortfolioNote={dataSource?.source === 'github'}
              />
              </>
            ) : activeView === 'work-queue' ? (
              <WorkQueueView
                auditIndex={docsAuditIndex}
                loading={docsAuditLoading}
                error={docsAuditError}
                onRefresh={handleDocsAuditRefresh}
                onScan={handleDocsAuditScan}
                onStartImprovementWorkflow={handleStartImprovementWorkflow}
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
                liveRepoCount={repos.length}
              />
            ) : activeView === 'execution-queue' ? (
              <ExecutionQueuePanel
                onDispatchPreviewTask={handlePreviewCopilotTask}
              />
            ) : (
              /* Dependencies view — Release 1.2 graph, led since Lane 0.16 by
                 the technology inventory: "dependencies" to an operator means
                 what the repos run on, so that answer comes first. */
              <div className="px-4 sm:px-6 lg:px-8 py-4">
                <TechInventoryPanel panel={techInventoryPanel} onRefresh={() => { void loadTechInventory(); }} />

                <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
                  <div>
                    <h2 className="text-lg font-semibold text-white">Cross-repo roadmap references</h2>
                    <p className="text-sm text-gray-400 mt-0.5">
                      Which repositories reference each other in their roadmaps (GitHub URLs, hash refs, keyword patterns).
                    </p>
                  </div>
                  <button
                    onClick={() => { void loadDependencyGraph(); }}
                    disabled={depsPanel.phase === 'loading'}
                    title={depsPanel.phase === 'loading' ? 'A dependency scan is already running.' : 'Re-scan portfolio roadmaps for cross-repo references.'}
                    className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 disabled:opacity-50 transition-colors"
                  >
                    {depsPanel.phase === 'loading' ? 'Scanning…' : depsPanel.phase === 'empty' ? 'Compute now' : 'Refresh'}
                  </button>
                </div>

                {depsPanel.phase === 'loading' && !dependencyGraph && (
                  <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                    <SpinnerIcon className="w-5 h-5 animate-spin" />
                    <span>Scanning roadmaps for dependencies…</span>
                  </div>
                )}

                {/* Release 3.5 milestone 5 — a fetch failure is an ERROR with
                    its endpoint and a retry, never a clean-looking empty
                    state. The old wiring swallowed it silently. */}
                {depsPanel.phase === 'error' && (
                  <div className="text-center py-10 text-sm" data-testid="dependencies-error-state">
                    <p className="mb-1 text-red-300">Dependency scan failed — this is not an empty result.</p>
                    <p className="text-gray-500 text-xs mb-3">{depsPanel.error?.endpoint}: {depsPanel.error?.message}</p>
                    <button onClick={() => { void loadDependencyGraph(); }} className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 transition-colors">Retry</button>
                  </div>
                )}

                {/* empty = COMPUTED and found nothing, with the computed-at
                    stamp the scanner has always emitted and the old empty
                    state dropped. */}
                {depsPanel.phase === 'empty' && dependencyGraph && (
                  <div className="text-center py-10 text-gray-500 text-sm" data-testid="dependencies-empty-state">
                    <p className="mb-1">No cross-repo references detected — scanned {new Date(dependencyGraph.scannedAt).toLocaleTimeString()}.</p>
                    <p className="text-gray-600 text-xs">References are found via GitHub URLs, <code>RepoName#42</code> refs, and keywords like "depends on" in roadmap files.</p>
                  </div>
                )}

                {depsPanel.phase === 'stale' && dependencyGraph && (
                  <p className="mb-3 rounded border border-amber-800/50 bg-amber-900/20 px-3 py-2 text-xs text-amber-200" data-testid="dependencies-stale-banner">
                    Showing the graph as of {depsPanel.lastGoodAt ? new Date(depsPanel.lastGoodAt).toLocaleTimeString() : '—'} — the refresh at {depsPanel.failedAt ? new Date(depsPanel.failedAt).toLocaleTimeString() : '—'} failed ({depsPanel.error?.message}).
                  </p>
                )}

                {(depsPanel.phase === 'success' || depsPanel.phase === 'stale' || (depsPanel.phase === 'loading' && !!dependencyGraph)) && dependencyGraph && dependencyGraph.summary.length > 0 && (
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
            </ErrorBoundary>
            </div>
        </div>
      </div>

      {/* Mobile bottom navigation — Release 2.5 Phase 1. Mirrors the desktop
          view tabs, which are hidden below the md breakpoint. */}
      <nav
        className="md:hidden fixed bottom-0 inset-x-0 z-40 border-t border-gray-700 bg-gray-900/95 backdrop-blur-sm"
        style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
        aria-label="Primary views"
      >
        <div className="flex overflow-x-auto">
          {([
            { view: 'today' as const, label: VIEW_META_BY_KEY['today'].short, icon: <HealthIcon className="w-5 h-5" />, badge: null as number | null },
            { view: 'repos' as const, label: 'Repos', icon: <ProjectsIcon className="w-5 h-5" />, badge: null as number | null },
            { view: 'insights' as const, label: 'Insights', icon: <HealthIcon className="w-5 h-5" />, badge: null as number | null },
            { view: 'operations' as const, label: 'Ops', icon: <DocReviewIcon className="w-5 h-5" />, badge: (operationsReadyCount || null) as number | null, carriedOver: operationsBadgeCarriedOver },
            { view: 'work-queue' as const, label: VIEW_META_BY_KEY['work-queue'].short, icon: <IssuesIcon className="w-5 h-5" />, badge: (queueReadyCount || null) as number | null, carriedOver: queueBadgeCarriedOver },
            { view: 'execution-queue' as const, label: VIEW_META_BY_KEY['execution-queue'].short, icon: <SyncIcon className="w-5 h-5" />, badge: null as number | null },
            { view: 'dependencies' as const, label: 'Deps', icon: <BranchIcon className="w-5 h-5" />, badge: (dependencyGraph && dependencyGraph.totalEdges > 0 ? dependencyGraph.totalEdges : null) as number | null },
          ] as Array<{ view: ViewKey; label: string; icon: React.ReactNode; badge: number | null; carriedOver?: boolean }>).map(item => (
            <button
              key={item.view}
              onClick={() => setActiveView(item.view)}
              className={`relative flex-1 min-w-[60px] min-h-14 flex flex-col items-center justify-center gap-0.5 px-1 py-1.5 text-[10px] font-medium transition-colors ${
                activeView === item.view ? 'text-indigo-300' : 'text-gray-400'
              }`}
              aria-current={activeView === item.view ? 'page' : undefined}
            >
              {item.icon}
              <span>{item.label}</span>
              {item.badge ? (
                <span
                  data-carried-over={item.carriedOver || undefined}
                  title={item.carriedOver ? carriedOverBadgeTitle : undefined}
                  className={`absolute top-1 right-1/2 translate-x-4 inline-flex items-center justify-center min-w-4 h-4 px-0.5 text-[9px] rounded-full font-semibold ${
                    item.carriedOver
                      ? 'bg-amber-800 text-amber-100 ring-1 ring-amber-500/60'
                      : 'bg-sky-700 text-sky-100'
                  }`}
                >
                  {item.badge}
                </span>
              ) : null}
              {activeView === item.view && (
                <span className="absolute top-0 inset-x-3 h-0.5 rounded-full bg-indigo-400" />
              )}
            </button>
          ))}
        </div>
      </nav>

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
          onConnectGitHub={onConnectGitHub}
          connectedGitHubUser={connectedGitHubUser}
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
        onClose={() => { setIsDocReviewModalOpen(false); setDocReviewTargetRepo(null); }}
        onRun={handleDocReviewRun}
        defaultRootPath={settings?.basePath}
        defaultDepth={settings?.scanDepth}
        defaultTargetRepo={docReviewTargetRepo ?? undefined}
        lockTargetRepo={Boolean(docReviewTargetRepo)}
      />

      <RoadmapViewerModal
        isOpen={isRoadmapViewerOpen}
        repoName={selectedRoadmapRepo}
        defaultOwner={dataSource?.source === 'github' ? dataSource.username : dataSource?.source === 'local' ? (dataSource.configuredGithubUser ?? null) : null}
        onClose={() => setIsRoadmapViewerOpen(false)}
        onScanComplete={handleRoadmapScanComplete}
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
          Promise.allSettled([
            getRoadmapAudit({ refresh: true }).then(setRoadmapAuditIndex),
            refreshOperationsRepos(true),
          ]).catch(() => {});
        }}
      />

      {lintModalRepo && (
        <RoadmapLintModal
          repoName={lintModalRepo}
          onClose={() => setLintModalRepo(null)}
        />
      )}

      {traceModalId && (
        <WorkItemTraceModal
          traceId={traceModalId}
          onClose={() => setTraceModalId(null)}
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
          refreshExecutionMetrics({ background: true }).catch(() => {/* surfaced in-card */});
        }}
      />

      <RepositoryImprovementWorkflowModal
        isOpen={improvementWorkflowRepo !== undefined}
        repos={docsAuditIndex?.entries ?? []}
        initialRepoName={improvementWorkflowRepo}
        onClose={() => setImprovementWorkflowRepo(undefined)}
        onDispatchComplete={() => {
          refreshExecutionMetrics({ background: true }).catch(() => {/* surfaced in-card */});
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

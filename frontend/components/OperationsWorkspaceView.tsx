import React, { useEffect, useMemo, useState } from 'react';
import {
  type OperationsRepoDetail,
  type AgentRun,
  type AgentRunStatus,
  type AiDocImproveApplyResult,
  type AiDocImprovementHistoryItem,
  type AiDocImprovePreviewResult,
  type AiDocProvider,
  type AiDocTemplatesResult,
  type AiDocType,
  type DocAuditIndex,
  type RoadmapAuditIndex,
  type OperationsRepoEntry,
  type DispatchExecuteResult,
  type OperationsReposResult,
  type OperationsPromptHistoryItem,
  type OperationsPromptRefineResult,
  type MergeReadinessResult,
  type PortfolioValueTier,
  type ReadmeContent,
  type RepoLifecycleState,
  type RoadmapContent,
} from '../types';
import { applyAiDocImprovement, evaluateMergeReadiness, executeMergeReadinessMerge, executeRoadmapDispatch, getAgentRuns, getAiDocImprovementHistory, getAiDocTemplates, getMergeReadiness, getOperationsPromptHistory, getOperationsRepoDetail, getReadmeContent, getRoadmapContent, getRunnerPresence, previewAiDocImprovement, refineOperationsPrompt, refreshAgentRun } from '../services/apiClient';
import { resolveDispatchGate, type RunnerPresencePayload } from '../lib/runnerPresence';
import { withPanelTimeout } from '../lib/asyncPanel';
import { describeUsage } from '../lib/aiUsage';
import { describeRefineBlocker } from '../lib/refineReadiness';
import { BranchIcon, DatabaseIcon, HealthIcon, PullRequestIcon, RefreshIcon, RoadmapIcon, SpinnerIcon } from './icons';

interface OperationsWorkspaceViewProps {
  operationsRepos: OperationsReposResult | null;
  loading: boolean;
  error?: string | null;
  docsAuditIndex?: DocAuditIndex | null;
  roadmapAuditIndex?: RoadmapAuditIndex | null;
  onRefresh: () => void;
  onRepairRoadmap?: (repoName: string) => void;
  onViewRoadmap?: (repoName: string) => void;
  onPreviewTask?: (repoName: string, roadmapPath?: string) => void;
  onViewGitStatus?: (repoName: string, localPath?: string) => void;
  showIndexedPortfolioNote?: boolean;
}

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
  'no-checklist': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'parse-error': 'bg-red-900/40 text-red-200 border-red-700/50',
};

const VALUE_TIER_STYLES: Record<PortfolioValueTier, string> = {
  highest: 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  high: 'bg-cyan-900/40 text-cyan-200 border-cyan-700/50',
  medium: 'bg-indigo-900/40 text-indigo-200 border-indigo-700/50',
  low: 'bg-slate-800 text-slate-200 border-slate-600',
  deferred: 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  unscored: 'bg-gray-800 text-gray-300 border-gray-600',
};

const CHANGE_STATE_STYLES: Record<NonNullable<OperationsRepoEntry['changeState']>, { label: string; className: string }> = {
  'unchanged': {
    label: 'Index: Reused',
    className: 'bg-emerald-900/30 text-emerald-200 border-emerald-700/50',
  },
  'new-commits': {
    label: 'Index: New Commits',
    className: 'bg-cyan-900/30 text-cyan-200 border-cyan-700/50',
  },
  'metadata-changed': {
    label: 'Index: Metadata Changed',
    className: 'bg-amber-900/30 text-amber-200 border-amber-700/50',
  },
  'needs-rescan': {
    label: 'Index: Rescanned',
    className: 'bg-violet-900/30 text-violet-200 border-violet-700/50',
  },
  'scan-failed': {
    label: 'Index: Scan Failed',
    className: 'bg-rose-900/30 text-rose-200 border-rose-700/50',
  },
};

const AGENT_RUN_STATUS_STYLES: Record<AgentRunStatus, string> = {
  dispatched: 'bg-slate-800 text-slate-200 border-slate-600',
  active: 'bg-blue-900/40 text-blue-200 border-blue-700/50',
  completed: 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  failed: 'bg-red-900/40 text-red-200 border-red-700/50',
  blocked: 'bg-amber-900/40 text-amber-200 border-amber-700/50',
};

const SEVERITY_COLORS: Record<string, string> = {
  critical: 'text-red-400',
  warning: 'text-yellow-400',
  info: 'text-blue-400',
};

const SEVERITY_BG: Record<string, string> = {
  critical: 'bg-red-900/30 border-red-700/40',
  warning: 'bg-yellow-900/30 border-yellow-700/40',
  info: 'bg-blue-900/20 border-blue-700/30',
};

function formatLifecycleLabel(state: RepoLifecycleState): string {
  return state.replaceAll('-', ' ');
}

function formatDate(value?: string | null): string {
  if (!value) return 'n/a';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString();
}

function formatBytes(value?: number): string {
  if (!value || value <= 0) return '0 B';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

function formatUnitValue(value?: number | null): string {
  if (value === null || value === undefined || Number.isNaN(value)) return 'n/a';
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function getLifecyclePriority(state: RepoLifecycleState): number {
  switch (state) {
    case 'ready-for-work':
      return 0;
    case 'needs-readme':
      return 1;
    case 'needs-roadmap':
      return 2;
    case 'needs-roadmap-repair':
      return 3;
    case 'needs-structure':
      return 4;
    case 'running':
      return 5;
    case 'no-checklist':
      return 6;
    case 'parse-error':
      return 7;
    case 'discovered':
      return 8;
    case 'monitored':
      return 9;
    case 'completed':
      return 10;
    case 'archived':
      return 10;
    default:
      return 99;
  }
}

function buildDirtySummary(entry: OperationsRepoEntry): string {
  const modified = entry.localModifiedCount ?? 0;
  const untracked = entry.localUntrackedCount ?? 0;
  const dirty = entry.localDirtyCount ?? (modified + untracked);
  if (dirty <= 0) {
    return 'Clean worktree';
  }

  return `${dirty} changed file${dirty === 1 ? '' : 's'} (${modified} modified, ${untracked} untracked)`;
}

function formatScanDecisionReason(reason?: OperationsRepoEntry['scanDecisionReason']): string {
  if (!reason) {
    return 'n/a';
  }

  switch (reason) {
    case 'reused-cache':
      return 'reused cache';
    case 'new-commit':
      return 'new commit';
    case 'metadata-changed':
      return 'metadata changed';
    case 'cache-miss':
      return 'cache miss';
    case 'cache-invalid':
      return 'cache invalid';
    case 'forced-refresh':
      return 'forced refresh';
    default:
      return reason;
  }
}

function shortSha(value?: string | null): string {
  if (!value) {
    return 'n/a';
  }
  return value.length > 8 ? value.slice(0, 8) : value;
}

function getScanDecisionTooltip(entry: OperationsRepoEntry): string {
  const lines = [
    `Decision: ${formatScanDecisionReason(entry.scanDecisionReason)}`,
    `Head: ${shortSha(entry.headCommitSha)}`,
    `Indexed: ${shortSha(entry.lastIndexedCommitSha)}`,
  ];

  if (entry.lastScanStatus) {
    lines.push(`Scan status: ${entry.lastScanStatus}`);
  }

  if (entry.lastScanError) {
    lines.push(`Error: ${entry.lastScanError}`);
  }

  return lines.join('\n');
}

const OperationsWorkspaceView: React.FC<OperationsWorkspaceViewProps> = ({
  operationsRepos,
  loading,
  error,
  docsAuditIndex,
  roadmapAuditIndex,
  onRefresh,
  onRepairRoadmap,
  onViewRoadmap,
  onPreviewTask,
  onViewGitStatus,
  showIndexedPortfolioNote = false,
}) => {
  const [filterText, setFilterText] = useState('');
  const [selectedRepoId, setSelectedRepoId] = useState<string | null>(null);
  const [docTab, setDocTab] = useState<'readme' | 'roadmap'>('readme');
  const [docsLoading, setDocsLoading] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [selectedDetail, setSelectedDetail] = useState<OperationsRepoDetail | null>(null);
  const [readmeContent, setReadmeContent] = useState<ReadmeContent | null>(null);
  const [roadmapContent, setRoadmapContent] = useState<RoadmapContent | null>(null);
  const [selectedTaskText, setSelectedTaskText] = useState('');
  const [selectedTaskSection, setSelectedTaskSection] = useState('');
  const [additionalConstraintsText, setAdditionalConstraintsText] = useState('');
  const [emphasisAreasText, setEmphasisAreasText] = useState('');
  const [operatorInstructions, setOperatorInstructions] = useState('');
  const [promptRefineResult, setPromptRefineResult] = useState<OperationsPromptRefineResult | null>(null);
  const [refinedPrompt, setRefinedPrompt] = useState('');
  const [editedPrompt, setEditedPrompt] = useState('');
  const [refineWarnings, setRefineWarnings] = useState<OperationsPromptRefineResult['warnings']>([]);
  const [refineLoading, setRefineLoading] = useState(false);
  const [refineError, setRefineError] = useState<string | null>(null);
  const [refinedPromptCopied, setRefinedPromptCopied] = useState(false);
  const [promptHistory, setPromptHistory] = useState<OperationsPromptHistoryItem[]>([]);
  const [promptHistoryLoading, setPromptHistoryLoading] = useState(false);
  const [promptTab, setPromptTab] = useState<'refine' | 'history'>('refine');
  const [dispatchLoading, setDispatchLoading] = useState(false);
  const [dispatchError, setDispatchError] = useState<string | null>(null);
  const [dispatchResult, setDispatchResult] = useState<DispatchExecuteResult | null>(null);
  // Release 3.1 — this surface queues through the same route as the dispatch
  // wizard, so it needs the same precondition. It had a readiness gate
  // (dispatchReady && maturityReady) that says the *work* is dispatchable, which
  // is a different question from whether anything is listening.
  const [runnerPresence, setRunnerPresence] = useState<RunnerPresencePayload | null>(null);
  const [aiTab, setAiTab] = useState<'improve' | 'history'>('improve');
  const [aiDocType, setAiDocType] = useState<AiDocType>('readme');
  const [aiTemplates, setAiTemplates] = useState<AiDocTemplatesResult | null>(null);
  const [aiTemplateId, setAiTemplateId] = useState('');
  const [aiProvider, setAiProvider] = useState<AiDocProvider>('auto');
  const [aiCustomPrompt, setAiCustomPrompt] = useState('');
  const [aiPreview, setAiPreview] = useState<AiDocImprovePreviewResult | null>(null);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState<string | null>(null);
  const [aiProposedCopied, setAiProposedCopied] = useState(false);
  const [aiHistory, setAiHistory] = useState<AiDocImprovementHistoryItem[]>([]);
  const [aiHistoryLoading, setAiHistoryLoading] = useState(false);
  const [aiApplyLoading, setAiApplyLoading] = useState(false);
  const [aiApplyError, setAiApplyError] = useState<string | null>(null);
  const [aiApplyResult, setAiApplyResult] = useState<AiDocImproveApplyResult | null>(null);
  const [agentRuns, setAgentRuns] = useState<AgentRun[]>([]);
  const [agentRunsLoading, setAgentRunsLoading] = useState(false);
  const [agentRunsError, setAgentRunsError] = useState<string | null>(null);
  const [agentRunRefreshingId, setAgentRunRefreshingId] = useState<string | null>(null);
  const [agentRunNotice, setAgentRunNotice] = useState<string | null>(null);
  const [mergeReadiness, setMergeReadiness] = useState<MergeReadinessResult | null>(null);
  const [mergeReadinessLoading, setMergeReadinessLoading] = useState(false);
  const [mergeReadinessError, setMergeReadinessError] = useState<string | null>(null);
  const [mergeActionLoading, setMergeActionLoading] = useState(false);
  const [mergeActionNotice, setMergeActionNotice] = useState<string | null>(null);

  const filteredEntries = useMemo(() => {
    const lower = filterText.trim().toLowerCase();
    const base: OperationsRepoEntry[] = operationsRepos?.entries ?? [];
    const filtered = lower
      ? base.filter((entry: OperationsRepoEntry) =>
          entry.repoName.toLowerCase().includes(lower) ||
          entry.githubFullName.toLowerCase().includes(lower) ||
          entry.recommendedAction.toLowerCase().includes(lower) ||
          entry.lifecycleState.toLowerCase().includes(lower) ||
          (entry.topValueItem?.text ?? '').toLowerCase().includes(lower),
        )
      : base;

    return [...filtered].sort((left, right) => {
      const lifecycleDelta = getLifecyclePriority(left.lifecycleState) - getLifecyclePriority(right.lifecycleState);
      if (lifecycleDelta !== 0) return lifecycleDelta;

      const valueDelta = (right.topValueItem?.valueScore ?? -1) - (left.topValueItem?.valueScore ?? -1);
      if (valueDelta !== 0) return valueDelta;

      return left.repoName.localeCompare(right.repoName);
    });
  }, [filterText, operationsRepos]);

  // Release 3.1 — read once on mount. Resolves null rather than throwing, and
  // resolveDispatchGate treats an unknown reading as "allow": a failed status
  // call is not evidence that nothing is listening, and blocking on it would
  // dead-end the operator over a hiccup on a different route.
  useEffect(() => {
    getRunnerPresence().then(setRunnerPresence);
  }, []);

  useEffect(() => {
    if (filteredEntries.length === 0) {
      setSelectedRepoId(null);
      return;
    }

    const hasSelection = filteredEntries.some(entry => entry.repoId === selectedRepoId);
    if (!hasSelection) {
      setSelectedRepoId(filteredEntries[0].repoId);
    }
  }, [filteredEntries, selectedRepoId]);

  const selectedEntry = useMemo(
    () => filteredEntries.find(entry => entry.repoId === selectedRepoId) ?? filteredEntries[0] ?? null,
    [filteredEntries, selectedRepoId],
  );

  const selectedDocsAuditEntry = useMemo(() => {
    if (!selectedEntry || !docsAuditIndex) return null;
    const repoName = selectedEntry.repoName.toLowerCase();
    const localPath = selectedEntry.localPath.toLowerCase();
    return docsAuditIndex.entries.find(entry => (
      entry.repoName.toLowerCase() === repoName ||
      entry.repoPath.toLowerCase() === localPath
    )) ?? null;
  }, [docsAuditIndex, selectedEntry]);

  const selectedRoadmapAuditEntry = useMemo(() => {
    if (!selectedEntry || !roadmapAuditIndex) return null;
    const repoName = selectedEntry.repoName.toLowerCase();
    const localPath = selectedEntry.localPath.toLowerCase();
    return roadmapAuditIndex.entries.find(entry => (
      entry.repoName.toLowerCase() === repoName ||
      (entry.repoPath ?? '').toLowerCase() === localPath
    )) ?? null;
  }, [roadmapAuditIndex, selectedEntry]);

  const readmeFindings = useMemo(() => {
    if (!selectedDocsAuditEntry) return [];
    return selectedDocsAuditEntry.docFindings.filter(finding =>
      /readme/i.test(finding.file ?? '') || /readme/i.test(finding.message ?? ''),
    );
  }, [selectedDocsAuditEntry]);

  const roadmapFindings = useMemo(
    () => selectedRoadmapAuditEntry?.auditFindings ?? [],
    [selectedRoadmapAuditEntry],
  );

  useEffect(() => {
    if (!selectedEntry) {
      setSelectedDetail(null);
      setDetailError(null);
      setDetailLoading(false);
      setReadmeContent(null);
      setRoadmapContent(null);
      setDocsError(null);
      setDocsLoading(false);
      return;
    }

    let cancelled = false;
    setDocsLoading(true);
    setDocsError(null);
    setDetailLoading(true);
    setDetailError(null);

    // Release 3.5 milestone 5 — a hung fetch becomes a named error at 10s
    // instead of 'Loading repository documents…' forever.
    Promise.allSettled([
      withPanelTimeout(getOperationsRepoDetail(selectedEntry.repoId), '/api/operations/repos/{id}'),
      selectedEntry.hasReadme ? withPanelTimeout(getReadmeContent(selectedEntry.repoName), '/api/readme/content') : Promise.resolve(null),
      selectedEntry.hasRoadmap ? withPanelTimeout(getRoadmapContent(selectedEntry.repoName), '/api/roadmap/content') : Promise.resolve(null),
    ])
      .then(([detailResult, readmeResult, roadmapResult]) => {
        if (cancelled) return;

        setSelectedDetail(detailResult.status === 'fulfilled' ? detailResult.value : null);
        if (detailResult.status === 'rejected') {
          setDetailError(detailResult.reason instanceof Error ? detailResult.reason.message : 'Failed to load operations detail.');
        }

        setReadmeContent(readmeResult.status === 'fulfilled' ? readmeResult.value : null);
        setRoadmapContent(roadmapResult.status === 'fulfilled' ? roadmapResult.value : null);

        const messages: string[] = [];
        if (readmeResult.status === 'rejected' && selectedEntry.hasReadme) {
          messages.push(`README: ${readmeResult.reason instanceof Error ? readmeResult.reason.message : 'failed to load'}`);
        }
        if (roadmapResult.status === 'rejected' && selectedEntry.hasRoadmap) {
          messages.push(`ROADMAP: ${roadmapResult.reason instanceof Error ? roadmapResult.reason.message : 'failed to load'}`);
        }
        setDocsError(messages.length > 0 ? messages.join(' • ') : null);
      })
      .finally(() => {
        if (!cancelled) {
          setDocsLoading(false);
          setDetailLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [selectedEntry]);

  useEffect(() => {
    const topValueItem = selectedEntry?.topValueItem;
    setSelectedTaskText(topValueItem?.text ?? selectedEntry?.nextPendingItemText ?? '');
    setSelectedTaskSection(topValueItem?.section ?? '');
    setAdditionalConstraintsText('');
    setEmphasisAreasText('');
    setOperatorInstructions('');
    setPromptRefineResult(null);
    setRefinedPrompt('');
    setEditedPrompt('');
    setRefineWarnings([]);
    setRefineError(null);
    setRefinedPromptCopied(false);
    setPromptHistory([]);
    setPromptTab('refine');
    setDispatchLoading(false);
    setDispatchError(null);
    setDispatchResult(null);
    setAiTab('improve');
    setAiCustomPrompt('');
    setAiPreview(null);
    setAiError(null);
    setAiProposedCopied(false);
    setAiHistory([]);
    setAgentRuns([]);
    setAgentRunsError(null);
    setAgentRunNotice(null);
    setAgentRunRefreshingId(null);
    setMergeReadiness(null);
    setMergeReadinessError(null);
    setMergeActionNotice(null);
  }, [selectedEntry?.repoId]);

  useEffect(() => {
    const repoId = selectedEntry?.repoId;
    if (!repoId) {
      return;
    }

    let cancelled = false;
    getMergeReadiness(repoId)
      .then(result => {
        if (!cancelled) setMergeReadiness(result);
      })
      .catch(() => {
        // A missing snapshot is normal before the first evaluation.
        if (!cancelled) setMergeReadiness(null);
      });

    return () => {
      cancelled = true;
    };
  }, [selectedEntry?.repoId]);

  useEffect(() => {
    const repoName = selectedEntry?.repoName;
    if (!repoName) {
      return;
    }

    let cancelled = false;
    setAgentRunsLoading(true);
    withPanelTimeout(getAgentRuns({ repoName, limit: 10 }), '/api/agent-runs')
      .then(result => {
        if (!cancelled) setAgentRuns(result.items);
      })
      .catch(err => {
        if (!cancelled) {
          setAgentRuns([]);
          setAgentRunsError(err instanceof Error ? err.message : 'Failed to load agent runs.');
        }
      })
      .finally(() => {
        if (!cancelled) setAgentRunsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [selectedEntry?.repoName]);

  useEffect(() => {
    let cancelled = false;
    getAiDocTemplates()
      .then(result => {
        if (!cancelled) setAiTemplates(result);
      })
      .catch(() => {
        if (!cancelled) setAiTemplates(null);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const aiTemplateOptions = useMemo(
    () => (aiDocType === 'roadmap' ? aiTemplates?.roadmapTemplates : aiTemplates?.readmeTemplates) ?? [],
    [aiDocType, aiTemplates],
  );

  useEffect(() => {
    if (aiTemplateOptions.length === 0) {
      setAiTemplateId('');
      return;
    }
    if (!aiTemplateOptions.some(template => template.id === aiTemplateId)) {
      setAiTemplateId(aiTemplateOptions[0].id);
    }
  }, [aiTemplateOptions, aiTemplateId]);

  const selectedDispatchReadiness = selectedDetail?.dispatchContext.dispatchReadiness ?? selectedEntry?.dispatchReadiness ?? 'missing-roadmap';
  const selectedDispatchReadinessExplanation =
    selectedDetail?.dispatchContext.dispatchReadinessExplanation ??
    selectedEntry?.dispatchReadinessExplanation ??
    null;
  const dispatchReady = selectedDispatchReadiness === 'ready';
  const maturityReady = selectedEntry?.maturityLevel === 'L3-Contract-Ready' || selectedEntry?.maturityLevel === 'L4-Orchestration-Ready';
  // Which condition is actually unmet -- see lib/refineReadiness.ts. The banner
  // used to fire on hasRoadmap alone while claiming refinement needs "at least
  // one pending item", so a repo with a real roadmap and no checklist items was
  // told it had no roadmap at all.
  const refineBlockedReason = useMemo(() => describeRefineBlocker(selectedEntry), [selectedEntry]);
  // Readiness of the *work*: is there a refined prompt for a repo mature enough
  // to receive it. Deliberately separate from the runner gate below — folding
  // them together would make the override impossible to offer, and would report
  // "not ready" for a repo that is perfectly ready with nothing listening.
  const canDispatchRefinedPrompt = Boolean(
    selectedEntry &&
    promptRefineResult?.runId &&
    (editedPrompt || refinedPrompt).trim() &&
    dispatchReady &&
    maturityReady,
  );
  const dispatchGate = resolveDispatchGate(runnerPresence);
  const dispatchBlockedReason = !selectedEntry
    ? 'Select a repo to dispatch.'
    : !promptRefineResult?.runId
      ? 'Generate a refined prompt first so dispatch can be linked to its history entry.'
      : !dispatchReady
        ? (selectedDispatchReadinessExplanation || 'Dispatch is blocked until this repo is marked ready in the current assessment.')
        : !maturityReady
          ? 'Dispatch requires roadmap maturity L3-Contract-Ready or higher.'
          : null;

  const parseMultilineList = (value: string): string[] => (
    value
      .split(/\r?\n|,/)
      .map(item => item.trim())
      .filter(Boolean)
  );

  const handleRefinePrompt = async () => {
    if (!selectedEntry) {
      return;
    }

    setRefineLoading(true);
    setRefineError(null);
    setPromptRefineResult(null);
    setRefineWarnings([]);
    setPromptHistory([]);
    setRefinedPromptCopied(false);
    setDispatchError(null);
    setDispatchResult(null);

    try {
      const result = await refineOperationsPrompt({
        repoName: selectedEntry.repoName,
        roadmapPath: selectedEntry.roadmapPath || undefined,
        selectedTaskText,
        selectedTaskSection,
        additionalConstraints: parseMultilineList(additionalConstraintsText),
        emphasisAreas: parseMultilineList(emphasisAreasText),
        operatorInstructions,
      });

      setPromptRefineResult(result);
      setSelectedTaskText(result.applied.selectedTaskText);
      setSelectedTaskSection(result.applied.selectedTaskSection);
      setRefineWarnings(result.warnings);
      setRefinedPrompt(result.refinedPrompt);
      setEditedPrompt(result.refinedPrompt);
    } catch (err) {
      setRefineError(err instanceof Error ? err.message : 'Failed to refine prompt.');
      setEditedPrompt('');
      setRefinedPrompt('');
    } finally {
      setRefineLoading(false);
    }
  };

  const handleLoadPromptHistory = async () => {
    if (!selectedEntry) {
      return;
    }

    setPromptHistoryLoading(true);
    try {
      const items = await getOperationsPromptHistory(selectedEntry.repoName);
      setPromptHistory(items);
    } catch {
      setPromptHistory([]);
    } finally {
      setPromptHistoryLoading(false);
    }
  };

  const handleCopyRefinedPrompt = async () => {
    const text = editedPrompt || refinedPrompt;
    if (!text) {
      return;
    }

    try {
      await navigator.clipboard.writeText(text);
      setRefinedPromptCopied(true);
      window.setTimeout(() => setRefinedPromptCopied(false), 1500);
    } catch {
      setRefinedPromptCopied(false);
    }
  };

  const handleDispatchRefinedPrompt = async (options?: { acknowledgeNoRunner?: boolean }) => {
    if (!selectedEntry || !promptRefineResult?.runId || !canDispatchRefinedPrompt) {
      return;
    }

    setDispatchLoading(true);
    setDispatchError(null);
    setDispatchResult(null);
    try {
      const result = await executeRoadmapDispatch(selectedEntry.repoName, editedPrompt || refinedPrompt, {
        localPath: selectedEntry.localPath || undefined,
        promptRefinementRunId: promptRefineResult.runId,
        acknowledgeNoRunner: options?.acknowledgeNoRunner,
      });
      setDispatchResult(result);
      setPromptTab('history');
      await handleLoadPromptHistory();
      void handleLoadAgentRuns();
      onRefresh();
    } catch (err) {
      setDispatchError(err instanceof Error ? err.message : 'Failed to dispatch refined prompt.');
    } finally {
      setDispatchLoading(false);
    }
  };

  const handlePromptTabChange = (tab: 'refine' | 'history') => {
    setPromptTab(tab);
    if (tab === 'history' && selectedEntry && promptHistory.length === 0 && !promptHistoryLoading) {
      void handleLoadPromptHistory();
    }
  };

  const handleLoadAgentRuns = async () => {
    if (!selectedEntry) {
      return;
    }

    setAgentRunsLoading(true);
    setAgentRunsError(null);
    setAgentRunNotice(null);
    try {
      const result = await getAgentRuns({ repoName: selectedEntry.repoName, limit: 10 });
      setAgentRuns(result.items);
    } catch (err) {
      setAgentRuns([]);
      setAgentRunsError(err instanceof Error ? err.message : 'Failed to load agent runs.');
    } finally {
      setAgentRunsLoading(false);
    }
  };

  const handleRefreshAgentRun = async (runId: string) => {
    setAgentRunRefreshingId(runId);
    setAgentRunsError(null);
    setAgentRunNotice(null);
    try {
      const result = await refreshAgentRun(runId);
      setAgentRuns(previous => previous.map(run => (run.runId === runId ? result.run : run)));

      const noticeParts: string[] = [];
      if (result.pullRequestFound) {
        noticeParts.push(`PR ${result.run.prNumber ? `#${result.run.prNumber} ` : ''}${result.run.prState ?? 'found'}`);
      } else {
        noticeParts.push('no matching agent PR on GitHub yet');
      }
      if (result.run.actions?.status) {
        noticeParts.push(`Actions ${result.run.actions.status}${result.run.actions.conclusion ? ` / ${result.run.actions.conclusion}` : ''}`);
      }
      if (result.validationEvent) {
        noticeParts.push(`recorded ${result.validationEvent}`);
      }
      setAgentRunNotice(`Refreshed from GitHub: ${noticeParts.join(' • ')}.`);
    } catch (err) {
      setAgentRunsError(err instanceof Error ? err.message : 'Agent run refresh failed.');
    } finally {
      setAgentRunRefreshingId(null);
    }
  };

  const handleEvaluateMergeReadiness = async () => {
    if (!selectedEntry) {
      return;
    }

    setMergeReadinessLoading(true);
    setMergeReadinessError(null);
    setMergeActionNotice(null);
    try {
      const result = await evaluateMergeReadiness(selectedEntry.repoId);
      setMergeReadiness(result);
    } catch (err) {
      setMergeReadinessError(err instanceof Error ? err.message : 'Merge-readiness evaluation failed.');
    } finally {
      setMergeReadinessLoading(false);
    }
  };

  const handleMergeAction = async () => {
    if (!selectedEntry || !mergeReadiness?.ready) {
      return;
    }

    const prLabel = mergeReadiness.prNumber ? `PR #${mergeReadiness.prNumber}` : mergeReadiness.prUrl ?? 'the agent PR';
    const confirmed = window.confirm(
      `Merge ${prLabel} into "${selectedEntry.repoName}"?\n\nThe server re-evaluates readiness first and refuses if any blocker appeared since this evaluation. This merges on GitHub.`,
    );
    if (!confirmed) {
      return;
    }

    setMergeActionLoading(true);
    setMergeReadinessError(null);
    setMergeActionNotice(null);
    try {
      const result = await executeMergeReadinessMerge(selectedEntry.repoId);
      setMergeReadiness(result.evaluation);
      setMergeActionNotice(`Merged ${prLabel} (${result.sha.substring(0, 7)}).`);
      void handleLoadAgentRuns();
    } catch (err) {
      setMergeReadinessError(err instanceof Error ? err.message : 'Merge was refused or failed.');
    } finally {
      setMergeActionLoading(false);
    }
  };

  const handleLoadAiHistory = async () => {
    if (!selectedEntry) {
      return;
    }

    setAiHistoryLoading(true);
    try {
      const items = await getAiDocImprovementHistory(selectedEntry.repoName);
      setAiHistory(items);
    } catch {
      setAiHistory([]);
    } finally {
      setAiHistoryLoading(false);
    }
  };

  const handleAiTabChange = (tab: 'improve' | 'history') => {
    setAiTab(tab);
    if (tab === 'history' && selectedEntry && aiHistory.length === 0 && !aiHistoryLoading) {
      void handleLoadAiHistory();
    }
  };

  const runAiImprovement = async (sourceContent?: string) => {
    if (!selectedEntry) {
      return;
    }

    setAiLoading(true);
    setAiError(null);
    setAiProposedCopied(false);
    setAiApplyError(null);
    setAiApplyResult(null);

    try {
      const loadedContent = aiDocType === 'roadmap' ? roadmapContent?.content : readmeContent?.content;
      const preview = await previewAiDocImprovement({
        repoName: selectedEntry.repoName,
        docType: aiDocType,
        templateId: aiTemplateId || undefined,
        customPrompt: aiCustomPrompt || undefined,
        provider: aiProvider,
        currentContent: sourceContent ?? loadedContent ?? undefined,
      });
      setAiPreview(preview);
      setAiHistory([]); // force a refresh next time the history tab opens
    } catch (err) {
      setAiError(err instanceof Error ? err.message : 'Failed to generate documentation improvement preview.');
    } finally {
      setAiLoading(false);
    }
  };

  const handleCopyAiProposed = async () => {
    if (!aiPreview?.proposedContent) {
      return;
    }

    try {
      await navigator.clipboard.writeText(aiPreview.proposedContent);
      setAiProposedCopied(true);
      window.setTimeout(() => setAiProposedCopied(false), 1500);
    } catch {
      setAiProposedCopied(false);
    }
  };

  const handleApplyAiProposed = async () => {
    if (!selectedEntry || !aiPreview?.proposedContent) {
      return;
    }

    const docFileName = aiPreview.docType === 'roadmap' ? 'ROADMAP.md' : 'README.md';
    const confirmed = window.confirm(
      `Apply the proposed ${docFileName} to "${selectedEntry.repoName}"?\n\nThe current file will be backed up first, and a restore command will be recorded. This writes to disk.`,
    );
    if (!confirmed) {
      return;
    }

    setAiApplyLoading(true);
    setAiApplyError(null);

    try {
      const result = await applyAiDocImprovement({
        repoName: selectedEntry.repoName,
        docType: aiPreview.docType,
        proposedContent: aiPreview.proposedContent,
        previewId: aiPreview.previewId,
      });
      setAiApplyResult(result);
      setAiHistory([]); // force a refresh next time the history tab opens

      // Refresh the viewer panes so the workspace shows the applied content.
      try {
        if (aiPreview.docType === 'roadmap') {
          setRoadmapContent(await getRoadmapContent(selectedEntry.repoName));
        } else {
          setReadmeContent(await getReadmeContent(selectedEntry.repoName));
        }
      } catch {
        // Viewer refresh is best-effort; the apply itself already succeeded.
      }
    } catch (err) {
      setAiApplyError(err instanceof Error ? err.message : 'Failed to apply the proposed documentation improvement.');
    } finally {
      setAiApplyLoading(false);
    }
  };

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-4">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold text-white">Operations Workspace</h2>
          <p className="text-sm text-gray-400 mt-0.5">
            Select a repo from the indexed portfolio, inspect its current state, and stage the next dispatch workflow from one place.
          </p>
          {operationsRepos && (
            <div className="mt-2 text-xs text-gray-500">
              Indexed entries: <span className="text-gray-300">{operationsRepos.count}</span>
              {' '}• Updated: <span className="text-gray-300">{formatDate(operationsRepos.generatedAt)}</span>
              {' '}• Source: <span className="text-gray-300">{operationsRepos.cacheSource}</span>
            </div>
          )}
        </div>
        <button
          onClick={onRefresh}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 disabled:opacity-50 transition-colors"
        >
          {loading ? <SpinnerIcon className="w-4 h-4" /> : <RefreshIcon className="w-4 h-4" />}
          Refresh
        </button>
      </div>

      {showIndexedPortfolioNote && (
        <div className="mt-4 rounded-lg border border-indigo-700/40 bg-indigo-950/30 px-4 py-3 text-sm text-indigo-100">
          Operations always uses the local indexed portfolio, even when the main repository grid is currently showing a GitHub API view.
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-3">
        <input
          type="text"
          placeholder="Filter operations repos..."
          value={filterText}
          onChange={(event: React.ChangeEvent<HTMLInputElement>) => setFilterText(event.target.value)}
          className="block w-full max-w-sm rounded-md border border-gray-600 bg-gray-900 px-3 py-2 text-sm text-white shadow-sm focus:border-blue-500 focus:outline-none focus:ring-blue-500"
        />
        <div className="inline-flex items-center rounded-md border border-gray-700 bg-gray-900/50 px-3 py-2 text-sm text-gray-400">
          Showing {filteredEntries.length} of {operationsRepos?.count ?? 0}
        </div>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-700/40 bg-red-950/30 px-4 py-3 text-sm text-red-100">
          {error}
        </div>
      )}

      {loading && !operationsRepos && (
        <div className="mt-6 flex items-center justify-center gap-3 rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-10 text-gray-400">
          <SpinnerIcon className="w-5 h-5" />
          <span>Loading indexed operations workspace…</span>
        </div>
      )}

      {!loading && filteredEntries.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-10 text-center text-sm text-gray-500">
          {operationsRepos && operationsRepos.count === 0 ? (
            <>
              <div className="text-gray-300">No indexed portfolio records are available for the Operations workspace yet.</div>
              <div className="mt-2">Build or refresh the indexed portfolio so maturity, readiness, and dispatch context are populated here.</div>
              <button
                type="button"
                onClick={onRefresh}
                className="mt-4 inline-flex items-center rounded-md border border-blue-700/60 bg-blue-900/30 px-3 py-1.5 text-xs font-medium text-blue-100 transition-colors hover:bg-blue-900/50"
              >
                Refresh Operations Data
              </button>
            </>
          ) : (
            'No operations-ready portfolio records matched the current filter.'
          )}
        </div>
      )}

      {filteredEntries.length > 0 && (
        <div className="mt-6 grid gap-4 xl:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]">
          <section className="overflow-hidden rounded-lg border border-gray-700 bg-gray-900/40">
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-700">
                <thead className="bg-gray-800/80">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Repository</th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Lifecycle</th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Top Work</th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Health</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-800 bg-gray-950/30">
                  {filteredEntries.map((entry: OperationsRepoEntry) => {
                    const isSelected = selectedEntry?.repoId === entry.repoId;
                    const valueTier = entry.topValueItem?.valueTier ?? 'unscored';
                    const valueTierClass = VALUE_TIER_STYLES[valueTier];
                    const changeStateCfg = entry.changeState ? CHANGE_STATE_STYLES[entry.changeState] : null;
                    return (
                      <tr
                        key={entry.repoId}
                        onClick={() => setSelectedRepoId(entry.repoId)}
                        className={`cursor-pointer transition-colors ${isSelected ? 'bg-blue-900/20' : 'hover:bg-gray-800/50'}`}
                      >
                        <td className="px-4 py-3 align-top">
                          <div className="text-sm font-semibold text-white">{entry.repoName}</div>
                          <div className="mt-1 text-xs text-gray-400">
                            {entry.githubFullName || entry.sourceCoverage}
                          </div>
                          {entry.localPath && (
                            <div className="mt-1 max-w-md truncate text-xs text-gray-500" title={entry.localPath}>
                              {entry.localPath}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-3 align-top">
                          <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs capitalize ${LIFECYCLE_STYLES[entry.lifecycleState] ?? LIFECYCLE_STYLES.discovered}`}>
                            {formatLifecycleLabel(entry.lifecycleState)}
                          </span>
                          {changeStateCfg && (
                            <div className="mt-1">
                              <span
                                className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${changeStateCfg.className}`}
                                title={getScanDecisionTooltip(entry)}
                              >
                                {changeStateCfg.label}
                              </span>
                            </div>
                          )}
                          <div className="mt-2 text-xs text-gray-400">{entry.recommendedAction}</div>
                        </td>
                        <td className="px-4 py-3 align-top">
                          {entry.topValueItem ? (
                            <>
                              <div className="inline-flex items-center gap-2">
                                <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${valueTierClass}`}>
                                  {entry.topValueItem.valueScore}
                                </span>
                                <span className="text-xs text-gray-300">{entry.topValueItem.valueTier}</span>
                              </div>
                              <div className="mt-2 text-sm text-gray-200">{entry.topValueItem.text}</div>
                            </>
                          ) : (
                            <div className="text-xs text-gray-500">
                              {entry.pendingItemCount > 0 ? `${entry.pendingItemCount} pending roadmap items` : 'No ranked roadmap work'}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-3 align-top">
                          <div className="text-xs text-gray-400">README {entry.readmeScore}</div>
                          <div className="text-xs text-gray-400">ROADMAP {entry.roadmapScore}</div>
                          <div className="text-xs text-gray-400">Docs {entry.documentationHealthScore}</div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>

          <section className="rounded-lg border border-gray-700 bg-gray-900/40 p-4">
            {selectedEntry ? (
              <div className="space-y-4">
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div>
                    {(() => {
                      const changeStateCfg = selectedEntry.changeState ? CHANGE_STATE_STYLES[selectedEntry.changeState] : null;
                      if (!changeStateCfg) {
                        return null;
                      }
                      return (
                        <div className="mb-2">
                          <span
                            className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${changeStateCfg.className}`}
                            title={getScanDecisionTooltip(selectedEntry)}
                          >
                            {changeStateCfg.label}
                          </span>
                        </div>
                      );
                    })()}
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="text-xl font-semibold text-white">{selectedEntry.repoName}</h3>
                      <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs capitalize ${LIFECYCLE_STYLES[selectedEntry.lifecycleState] ?? LIFECYCLE_STYLES.discovered}`}>
                        {formatLifecycleLabel(selectedEntry.lifecycleState)}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-gray-300">{selectedEntry.recommendedAction}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {selectedEntry.localPath && onViewGitStatus && (
                      <button
                        onClick={() => onViewGitStatus(selectedEntry.repoName, selectedEntry.localPath)}
                        className="rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 transition-colors"
                      >
                        Git Status
                      </button>
                    )}
                    {selectedEntry.hasRoadmap && onViewRoadmap && (
                      <button
                        onClick={() => onViewRoadmap(selectedEntry.repoName)}
                        className="inline-flex items-center gap-2 rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 transition-colors"
                      >
                        <RoadmapIcon className="w-4 h-4" />
                        View ROADMAP
                      </button>
                    )}
                    {selectedEntry.hasRoadmap && onPreviewTask && (
                      <button
                        onClick={() => onPreviewTask(selectedEntry.repoName, selectedEntry.roadmapPath || undefined)}
                        className="rounded-md border border-blue-700/50 bg-blue-950/40 px-3 py-1.5 text-sm text-blue-100 hover:bg-blue-900/50 transition-colors"
                      >
                        Preview Task Packet
                      </button>
                    )}
                  </div>
                </div>

                <div className="grid gap-3 sm:grid-cols-3">
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-3">
                    <div className="text-xs uppercase tracking-wide text-gray-500">README Score</div>
                    <div className="mt-1 text-2xl font-semibold text-white">{selectedEntry.readmeScore}</div>
                  </div>
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-3">
                    <div className="text-xs uppercase tracking-wide text-gray-500">ROADMAP Score</div>
                    <div className="mt-1 text-2xl font-semibold text-white">{selectedEntry.roadmapScore}</div>
                  </div>
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-3">
                    <div className="text-xs uppercase tracking-wide text-gray-500">Docs Health</div>
                    <div className="mt-1 text-2xl font-semibold text-white">{selectedEntry.documentationHealthScore}</div>
                  </div>
                </div>

                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <DatabaseIcon className="w-4 h-4 text-blue-300" />
                      Repository Context
                    </div>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div>
                        <dt className="text-gray-500">Local Path</dt>
                        <dd className="mt-0.5 break-all text-gray-200">{selectedEntry.localPath || 'n/a'}</dd>
                      </div>
                      <div>
                        <dt className="text-gray-500">GitHub</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedEntry.htmlUrl ? (selectedEntry.githubFullName || selectedEntry.htmlUrl) : 'n/a'}
                        </dd>
                      </div>
                      <div className="grid gap-3 sm:grid-cols-2">
                        <div>
                          <dt className="text-gray-500">Default Branch</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.defaultBranch || 'n/a'}</dd>
                        </div>
                        <div>
                          <dt className="text-gray-500">Current Branch</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.currentBranch || 'n/a'}</dd>
                        </div>
                      </div>
                      <div>
                        <dt className="text-gray-500">Last Commit</dt>
                        <dd className="mt-0.5 text-gray-200">{formatDate(selectedEntry.localLastCommitDate)}</dd>
                      </div>
                      <div className="grid gap-3 sm:grid-cols-2">
                        <div>
                          <dt className="text-gray-500">Created</dt>
                          <dd className="mt-0.5 text-gray-200">{formatDate(selectedEntry.createdAt)}</dd>
                        </div>
                        <div>
                          <dt className="text-gray-500">Updated</dt>
                          <dd className="mt-0.5 text-gray-200">{formatDate(selectedEntry.updatedAt)}</dd>
                        </div>
                      </div>
                    </dl>
                  </div>

                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center justify-between gap-3 flex-wrap">
                      <div className="flex items-center gap-2 text-sm font-semibold text-white">
                        <BranchIcon className="w-4 h-4 text-emerald-300" />
                        Work Readiness
                      </div>
                      {onRepairRoadmap && selectedEntry.hasRoadmap && !maturityReady && (
                        <button
                          type="button"
                          onClick={() => onRepairRoadmap(selectedEntry.repoName)}
                          className="inline-flex items-center gap-2 rounded-md border border-orange-700/60 bg-orange-900/25 px-3 py-1.5 text-xs font-medium text-orange-100 transition-colors hover:bg-orange-900/45"
                        >
                          <RoadmapIcon className="w-4 h-4" />
                          Open Roadmap Repair
                        </button>
                      )}
                    </div>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div>
                        <dt className="text-gray-500">Dispatch Readiness</dt>
                        <dd className="mt-0.5 text-gray-200">{selectedDispatchReadiness}</dd>
                        {selectedDispatchReadinessExplanation && (
                          <div className="mt-1 text-xs text-gray-500">{selectedDispatchReadinessExplanation}</div>
                        )}
                      </div>
                      <div>
                        <dt className="text-gray-500">Roadmap Maturity</dt>
                        <dd className="mt-0.5 text-gray-200">{selectedEntry.maturityLevel}</dd>
                      </div>
                      <div>
                        <dt className="text-gray-500">Dirty State</dt>
                        <dd className="mt-0.5 text-gray-200">{buildDirtySummary(selectedEntry)}</dd>
                      </div>
                      <div>
                        <dt className="text-gray-500">Pending Roadmap Work</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedDetail?.dispatchContext.topValueItem?.text ?? selectedDetail?.dispatchContext.nextPendingItemText ?? selectedEntry.topValueItem?.text ?? selectedEntry.nextPendingItemText ?? 'No pending roadmap item'}
                        </dd>
                        {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem) && (
                          <div className="mt-1 text-xs text-gray-500">
                            Value score {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)?.valueScore} • {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)?.valueTier}
                          </div>
                        )}
                      </div>
                      <div>
                        <dt className="text-gray-500">Pending Item Count</dt>
                        <dd className="mt-0.5 text-gray-200">{selectedDetail?.dispatchContext.pendingItemCount ?? selectedEntry.pendingItemCount}</dd>
                      </div>
                    </dl>
                  </div>
                </div>

                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4 lg:col-span-2">
                    <div className="flex items-center justify-between gap-3 flex-wrap">
                      <div className="text-sm font-semibold text-white">README and ROADMAP Viewers</div>
                      <div className="inline-flex rounded-md border border-gray-700 bg-gray-900/60 p-1 text-xs">
                        <button
                          onClick={() => setDocTab('readme')}
                          className={`rounded px-2 py-1 transition-colors ${docTab === 'readme' ? 'bg-blue-900/50 text-blue-100' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                          README
                        </button>
                        <button
                          onClick={() => setDocTab('roadmap')}
                          className={`rounded px-2 py-1 transition-colors ${docTab === 'roadmap' ? 'bg-blue-900/50 text-blue-100' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                          ROADMAP
                        </button>
                      </div>
                    </div>

                    {docsLoading ? (
                      <div className="mt-3 flex items-center gap-2 text-sm text-gray-400">
                        <SpinnerIcon className="w-4 h-4" />
                        Loading repository documents…
                      </div>
                    ) : (
                      <>
                        {docsError && (
                          <div className="mt-3 rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-xs text-amber-200">
                            {docsError}
                          </div>
                        )}
                        {docTab === 'readme' ? (
                          selectedEntry.hasReadme && readmeContent ? (
                            <div className="mt-3">
                              <div className="mb-2 text-xs text-gray-500">
                                {readmeContent.path || 'README path unavailable'} • {formatBytes(readmeContent.sizeBytes)} • updated {formatDate(readmeContent.lastModified)}
                              </div>
                              <pre className="max-h-72 overflow-auto rounded-md border border-gray-800 bg-gray-900/60 p-3 text-xs text-gray-200 whitespace-pre-wrap break-words">
                                {readmeContent.content}
                              </pre>
                            </div>
                          ) : (
                            <div className="mt-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                              README is not available for this repository.
                            </div>
                          )
                        ) : (
                          selectedEntry.hasRoadmap && roadmapContent ? (
                            <div className="mt-3">
                              <div className="mb-2 text-xs text-gray-500">
                                {roadmapContent.path || 'ROADMAP path unavailable'} • {formatBytes(roadmapContent.sizeBytes)} • updated {formatDate(roadmapContent.lastModified)}
                              </div>
                              <pre className="max-h-72 overflow-auto rounded-md border border-gray-800 bg-gray-900/60 p-3 text-xs text-gray-200 whitespace-pre-wrap break-words">
                                {roadmapContent.content}
                              </pre>
                            </div>
                          ) : (
                            <div className="mt-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                              ROADMAP is not available for this repository.
                            </div>
                          )
                        )}
                      </>
                    )}
                  </div>

                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <PullRequestIcon className="w-4 h-4 text-cyan-300" />
                      GitHub Signals
                    </div>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div className="grid gap-3 sm:grid-cols-2">
                        <div>
                          <dt className="text-gray-500">Open PRs</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.openPrCount}</dd>
                        </div>
                        <div>
                          <dt className="text-gray-500">Pending Review PRs</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.pendingReviewPrCount}</dd>
                        </div>
                      </div>
                      <div>
                        <dt className="text-gray-500">Latest Actions Run</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedEntry.latestWorkflowRunName || selectedEntry.latestWorkflowRunStatus
                            ? `${selectedEntry.latestWorkflowRunName ?? 'Workflow'} • ${selectedEntry.latestWorkflowRunStatus ?? 'unknown'}${selectedEntry.latestWorkflowRunConclusion ? ` / ${selectedEntry.latestWorkflowRunConclusion}` : ''}`
                            : 'n/a'}
                        </dd>
                        {selectedEntry.latestWorkflowRunTimestamp && (
                          <div className="mt-1 text-xs text-gray-500">{formatDate(selectedEntry.latestWorkflowRunTimestamp)}</div>
                        )}
                      </div>
                      <div>
                        <dt className="text-gray-500">GitHub Pages</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedEntry.hasPages && selectedEntry.pagesUrl ? selectedEntry.pagesUrl : 'Not configured'}
                        </dd>
                      </div>
                    </dl>
                  </div>

                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <HealthIcon className="w-4 h-4 text-amber-300" />
                      Audit Findings and Blockers
                    </div>
                    <div className="mt-3 grid gap-4 lg:grid-cols-2">
                      <div>
                        <div className="text-xs uppercase tracking-wide text-gray-500">
                          README Findings {selectedDocsAuditEntry ? `(${readmeFindings.length})` : '(unavailable)'}
                        </div>
                        {readmeFindings.length > 0 ? (
                          <ul className="mt-2 space-y-2 text-sm text-gray-200">
                            {readmeFindings.map((finding, index) => (
                              <li key={`${finding.file}-${finding.message}-${index}`} className={`rounded-md border px-3 py-2 ${SEVERITY_BG[finding.severity] ?? SEVERITY_BG.info}`}>
                                <div className={`text-xs font-semibold uppercase ${SEVERITY_COLORS[finding.severity] ?? 'text-gray-400'}`}>
                                  {finding.severity}
                                </div>
                                <div className="mt-1">{finding.message}</div>
                                <div className="mt-1 text-xs text-gray-400">→ {finding.recommendedAction}</div>
                              </li>
                            ))}
                          </ul>
                        ) : (
                          <div className="mt-2 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                            {selectedDocsAuditEntry ? 'No README findings recorded for this repo.' : 'Docs audit data has not been loaded yet.'}
                          </div>
                        )}
                      </div>

                      <div>
                        <div className="text-xs uppercase tracking-wide text-gray-500">
                          ROADMAP Findings {selectedRoadmapAuditEntry ? `(${roadmapFindings.length})` : '(unavailable)'}
                        </div>
                        {roadmapFindings.length > 0 ? (
                          <ul className="mt-2 space-y-2 text-sm text-gray-200">
                            {roadmapFindings.map((finding, index) => (
                              <li key={`${finding.ruleId}-${finding.message}-${index}`} className={`rounded-md border px-3 py-2 ${SEVERITY_BG[finding.severity] ?? SEVERITY_BG.info}`}>
                                <div className={`text-xs font-semibold uppercase ${SEVERITY_COLORS[finding.severity] ?? 'text-gray-400'}`}>
                                  {finding.severity}
                                </div>
                                <div className="mt-1">{finding.message}</div>
                                {finding.recommendedAction && (
                                  <div className="mt-1 text-xs text-gray-400">→ {finding.recommendedAction}</div>
                                )}
                              </li>
                            ))}
                          </ul>
                        ) : (
                          <div className="mt-2 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                            {selectedRoadmapAuditEntry ? 'No roadmap audit findings recorded for this repo.' : 'Roadmap audit data has not been loaded yet.'}
                          </div>
                        )}
                      </div>

                      <div>
                        <div className="text-xs uppercase tracking-wide text-gray-500">
                          Structure Findings ({selectedEntry.structureFindings.length})
                        </div>
                        {selectedEntry.structureFindings.length > 0 ? (
                          <ul className="mt-2 space-y-2 text-sm text-gray-200">
                            {selectedEntry.structureFindings.map((finding, index) => (
                              <li key={`${finding.kind}-${finding.target}-${index}`} className={`rounded-md border px-3 py-2 ${SEVERITY_BG[finding.severity] ?? SEVERITY_BG.info}`}>
                                <div className={`text-xs font-semibold uppercase ${SEVERITY_COLORS[finding.severity] ?? 'text-gray-400'}`}>
                                  {finding.severity}
                                </div>
                                <div className="mt-1">
                                  {finding.kind.replaceAll('-', ' ')} • {finding.target}
                                </div>
                                <div className="mt-1 text-xs text-gray-400">→ {finding.recommendedAction}</div>
                              </li>
                            ))}
                          </ul>
                        ) : (
                          <div className="mt-2 rounded-md border border-emerald-800/40 bg-emerald-950/20 px-3 py-2 text-sm text-emerald-100">
                            No structure findings recorded for this repo.
                          </div>
                        )}
                      </div>

                      <div>
                        <div className="text-xs uppercase tracking-wide text-gray-500">
                          Dispatch Blockers ({selectedEntry.blockingReasons.length})
                        </div>
                        {selectedEntry.blockingReasons.length > 0 ? (
                          <ul className="mt-2 space-y-2 text-sm text-gray-200">
                            {selectedEntry.blockingReasons.map(reason => (
                              <li key={reason} className="rounded-md border border-gray-800 bg-gray-900/60 px-3 py-2">
                                {reason}
                              </li>
                            ))}
                          </ul>
                        ) : (
                          <div className="mt-2 rounded-md border border-emerald-800/40 bg-emerald-950/20 px-3 py-2 text-sm text-emerald-100">
                            No dispatch blockers recorded for this repo in the current indexed assessment.
                          </div>
                        )}
                      </div>
                    </div>
                    {detailLoading && (
                      <div className="mt-3 flex items-center gap-2 text-sm text-gray-400">
                        <SpinnerIcon className="w-4 h-4" />
                        Loading audit findings...
                      </div>
                    )}
                    {detailError && (
                      <div className="mt-3 rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-xs text-amber-200">
                        {detailError}
                      </div>
                    )}
                    {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)?.valueRationale &&
                      (selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)!.valueRationale.length > 0 && (
                      <div className="mt-4">
                        <div className="text-xs uppercase tracking-wide text-gray-500">Why this work ranks highly</div>
                        <ul className="mt-2 space-y-2 text-sm text-gray-300">
                          {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)!.valueRationale.map((reason: string) => (
                            <li key={reason} className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2">
                              {reason}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>
                </div>

                <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                  <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div className="text-sm font-semibold text-white">Prompt Refinement</div>
                    <div className="inline-flex rounded-md border border-gray-700 bg-gray-900/60 p-1 text-xs">
                      {(['refine', 'history'] as const).map(tab => (
                        <button
                          key={tab}
                          onClick={() => handlePromptTabChange(tab)}
                          className={`rounded px-2 py-1 transition-colors capitalize ${promptTab === tab ? 'bg-indigo-900/50 text-indigo-100' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                          {tab === 'refine' ? 'Refine Prompt' : 'History'}
                        </button>
                      ))}
                    </div>
                  </div>

                  {promptTab === 'refine' && (
                    <div className="mt-3 space-y-3">
                      <div className="text-xs text-gray-500">Builds on `/api/copilot-task/preview` packet context and lets the operator adjust selection, emphasis, constraints, and final instructions before copy or dispatch.</div>

                      {refineBlockedReason && (
                        <div className="rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-sm text-amber-200">
                          {refineBlockedReason}
                        </div>
                      )}

                      <div className="grid gap-3 lg:grid-cols-2">
                        <label className="text-xs text-gray-400">
                          Selected task text
                          <input
                            type="text"
                            value={selectedTaskText}
                            onChange={(event: React.ChangeEvent<HTMLInputElement>) => setSelectedTaskText(event.target.value)}
                            className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                            placeholder="Roadmap checkbox text"
                          />
                        </label>
                        <label className="text-xs text-gray-400">
                          Selected task section (optional)
                          <input
                            type="text"
                            value={selectedTaskSection}
                            onChange={(event: React.ChangeEvent<HTMLInputElement>) => setSelectedTaskSection(event.target.value)}
                            className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                            placeholder="Release / phase section name"
                          />
                        </label>
                        <label className="text-xs text-gray-400">
                          Emphasis areas (one per line)
                          <textarea
                            value={emphasisAreasText}
                            onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => setEmphasisAreasText(event.target.value)}
                            rows={4}
                            className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                            placeholder="performance&#10;test coverage&#10;small safe commits"
                          />
                        </label>
                        <label className="text-xs text-gray-400">
                          Additional constraints (one per line)
                          <textarea
                            value={additionalConstraintsText}
                            onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => setAdditionalConstraintsText(event.target.value)}
                            rows={4}
                            className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                            placeholder="do not change public API&#10;preserve existing workflow names"
                          />
                        </label>
                      </div>

                      <label className="block text-xs text-gray-400">
                        Operator instructions
                        <textarea
                          value={operatorInstructions}
                          onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => setOperatorInstructions(event.target.value)}
                          rows={3}
                          className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                          placeholder="Any final direction to append to the generated prompt..."
                        />
                      </label>

                      <div className="flex items-center gap-2 flex-wrap">
                        <button
                          onClick={handleRefinePrompt}
                          disabled={refineLoading || Boolean(refineBlockedReason)}
                          title={refineBlockedReason ?? (refineLoading ? 'A prompt is already being refined.' : 'Builds a refined dispatch prompt from this roadmap.')}
                          className="inline-flex items-center gap-2 rounded-md border border-blue-700/50 bg-blue-950/40 px-3 py-1.5 text-sm text-blue-100 hover:bg-blue-900/50 disabled:opacity-50 transition-colors"
                        >
                          {refineLoading ? <SpinnerIcon className="w-4 h-4" /> : null}
                          {refineLoading ? 'Refining prompt...' : promptRefineResult ? 'Regenerate Prompt' : 'Generate Refined Prompt'}
                        </button>
                        <button
                          onClick={handleCopyRefinedPrompt}
                          disabled={!(editedPrompt || refinedPrompt)}
                          title={!(editedPrompt || refinedPrompt) ? 'Generate a refined prompt first — there is nothing to copy yet.' : 'Copies the refined prompt to the clipboard.'}
                          className="rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 disabled:opacity-50 transition-colors"
                        >
                          {refinedPromptCopied ? 'Copied' : 'Copy Prompt'}
                        </button>
                        {/* Release 3.1 — the work being ready and something being
                            able to claim it are two different preconditions, and
                            only the first was checked here. */}
                        {canDispatchRefinedPrompt && !dispatchGate.canQueue && (
                          <span data-testid="operations-dispatch-precondition" className="max-w-md text-xs text-amber-300/90">
                            {dispatchGate.unmetPrecondition}
                          </span>
                        )}
                        {canDispatchRefinedPrompt && !dispatchGate.canQueue && (
                          <button
                            onClick={() => handleDispatchRefinedPrompt({ acknowledgeNoRunner: true })}
                            disabled={dispatchLoading}
                            data-testid="operations-dispatch-override"
                            className="rounded-md border border-amber-700/50 bg-gray-800 px-3 py-1.5 text-sm text-amber-200 hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
                          >
                            {dispatchGate.overrideLabel}
                          </button>
                        )}
                        <button
                          onClick={() => handleDispatchRefinedPrompt()}
                          disabled={dispatchLoading || !canDispatchRefinedPrompt || !dispatchGate.canQueue}
                          data-testid="operations-dispatch-submit"
                          title={dispatchGate.canQueue ? undefined : dispatchGate.unmetPrecondition}
                          className="inline-flex items-center gap-2 rounded-md border border-emerald-700/50 bg-emerald-950/40 px-3 py-1.5 text-sm text-emerald-100 hover:bg-emerald-900/50 disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
                        >
                          {dispatchLoading ? <SpinnerIcon className="w-4 h-4" /> : null}
                          {dispatchLoading ? 'Dispatching...' : 'Dispatch to Copilot'}
                        </button>
                      </div>

                      {dispatchBlockedReason && refinedPrompt && (
                        <div className="rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-xs text-amber-200">
                          {dispatchBlockedReason}
                        </div>
                      )}

                      {refineError && (
                        <div className="rounded-md border border-red-700/40 bg-red-950/20 px-3 py-2 text-xs text-red-200">
                          {refineError}
                        </div>
                      )}

                      {dispatchError && (
                        <div className="rounded-md border border-red-700/40 bg-red-950/20 px-3 py-2 text-xs text-red-200">
                          {dispatchError}
                        </div>
                      )}

                      {dispatchResult && (
                        <div className="rounded-md border border-emerald-700/40 bg-emerald-950/20 px-3 py-2 text-xs text-emerald-200">
                          <div>{dispatchResult.message}</div>
                          <div className="mt-1 text-emerald-300/80">
                            Copilot run <span className="font-mono">{dispatchResult.runId}</span>
                            {' '}• Ledger run <span className="font-mono">{dispatchResult.agentRunId ?? 'pending'}</span>
                            {' '}• Repo <span className="font-mono">{dispatchResult.githubRepo}</span>
                            {' '}• Started {new Date(dispatchResult.startedAt).toLocaleString()}
                          </div>
                          {dispatchResult.quota && (
                            <div className="mt-1 text-emerald-300/80">
                              Estimate {formatUnitValue(dispatchResult.quota.estimatedWorkUnits)} unit(s)
                              {dispatchResult.quota.estimateSource ? ` from ${dispatchResult.quota.estimateSource}` : ''}
                              {dispatchResult.quota.plannedPhaseName ? ` • Phase ${dispatchResult.quota.plannedPhaseName}` : ''}
                              {dispatchResult.quota.projectBudgetUnitsRemaining !== null && dispatchResult.quota.projectBudgetUnitsRemaining !== undefined
                                ? ` • Remaining budget ${formatUnitValue(dispatchResult.quota.projectBudgetUnitsRemaining)}`
                                : ''}
                              {dispatchResult.quota.warning ? ` • Warning: ${dispatchResult.quota.warning}` : ''}
                            </div>
                          )}
                        </div>
                      )}

                      {promptRefineResult && !refineLoading && (
                        <div className="rounded-md border border-gray-700 bg-gray-900/60 px-3 py-2 text-xs text-gray-400 space-y-1">
                          <div>
                            Selected item: <span className="text-gray-200">{promptRefineResult.applied.selectedTaskText}</span>
                          </div>
                          <div>
                            Selection: <span className="text-gray-300 capitalize">{(promptRefineResult.packet.selectedRoadmapItem.selectionSource ?? 'roadmap-order').replace(/-/g, ' ')}</span>
                            {' '}• Section: <span className="text-gray-300">{promptRefineResult.applied.selectedTaskSection || 'n/a'}</span>
                          </div>
                        </div>
                      )}

                      {refineWarnings.length > 0 && (
                        <div className="space-y-2">
                          {refineWarnings.map((warning, index) => (
                            <div key={`${warning.code}-${index}`} className={`rounded-md border px-3 py-2 text-xs ${SEVERITY_BG[warning.severity] ?? SEVERITY_BG.info}`}>
                              <div className={`font-semibold uppercase ${SEVERITY_COLORS[warning.severity] ?? 'text-gray-300'}`}>
                                {warning.severity} • {warning.code}
                              </div>
                              <div className="mt-1 text-gray-200">{warning.message}</div>
                            </div>
                          ))}
                        </div>
                      )}

                      {refinedPrompt && (
                        <div>
                          <div className="mb-2 flex items-center justify-between gap-3">
                            <span className="text-xs uppercase tracking-wide text-gray-500">Refined prompt preview</span>
                            <span className="text-xs text-gray-600">Editable before copy</span>
                          </div>
                          <textarea
                            value={editedPrompt}
                            onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => setEditedPrompt(event.target.value)}
                            rows={16}
                            spellCheck={false}
                            className="w-full rounded-md border border-gray-700 bg-gray-900/60 px-3 py-2 font-mono text-xs text-gray-200 focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 resize-y"
                          />
                        </div>
                      )}
                    </div>
                  )}
                  {promptTab === 'history' && (
                    <div className="mt-3">
                      {promptHistoryLoading ? (
                        <div className="flex items-center gap-2 text-sm text-gray-400">
                          <SpinnerIcon className="w-4 h-4" />
                          Loading refinement history…
                        </div>
                      ) : promptHistory.length === 0 ? (
                        <div className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                          No prompt refinements recorded for this repo yet. Generate a refined prompt first.
                        </div>
                      ) : (
                        <ul className="space-y-2">
                          {promptHistory.map(item => (
                            <li key={item.runId} className="rounded-md border border-gray-700 bg-gray-900/40 px-3 py-2 text-xs text-gray-300 space-y-1">
                              <div className="flex items-center justify-between gap-2">
                                <span className="font-mono text-gray-500">{item.runId}</span>
                                <span className="text-gray-500">{new Date(item.createdAt).toLocaleString()}</span>
                              </div>
                              <div className="text-gray-200">{item.selectedItemText}</div>
                              <div className="text-gray-600 capitalize">{item.selectionSource.replace(/-/g, ' ')}</div>
                              {item.operatorInstructions && (
                                <div className="italic text-gray-400">+ {item.operatorInstructions}</div>
                              )}
                              <div className="text-gray-500">
                                Constraints: {item.additionalConstraints.length} • Emphasis: {item.emphasisAreas.length} • Warnings: {item.warningCount} • Dispatches: {item.dispatchCount}
                              </div>
                              {item.dispatchRecords.length > 0 && (
                                <div className="space-y-1 pt-1">
                                  {item.dispatchRecords.map(record => (
                                    <div key={`${item.runId}-${record.dispatchRunId}`} className="rounded border border-emerald-900/30 bg-emerald-950/10 px-2 py-1 text-[11px] text-gray-300">
                                      <div className="flex items-center justify-between gap-2 flex-wrap">
                                        <span className="font-mono text-gray-500">{record.dispatchRunId}</span>
                                        <span className="text-emerald-300">{record.status}</span>
                                      </div>
                                      <div className="text-gray-400">{record.githubRepo}</div>
                                      <div className="text-gray-500">{new Date(record.startedAt).toLocaleString()}</div>
                                    </div>
                                  ))}
                                </div>
                              )}
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  )}
                </div>

                <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                  <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div className="text-sm font-semibold text-white">AI Documentation Improvement</div>
                    <div className="inline-flex rounded-md border border-gray-700 bg-gray-900/60 p-1 text-xs">
                      {(['improve', 'history'] as const).map(tab => (
                        <button
                          key={tab}
                          onClick={() => handleAiTabChange(tab)}
                          className={`rounded px-2 py-1 transition-colors capitalize ${aiTab === tab ? 'bg-violet-900/50 text-violet-100' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                          {tab === 'improve' ? 'Improve' : 'History'}
                        </button>
                      ))}
                    </div>
                  </div>

                  {aiTab === 'improve' && (
                    <div className="mt-3 space-y-3">
                      <div className="text-xs text-gray-500">
                        Preview-first README/ROADMAP improvement cycles. Nothing is written to disk until you explicitly apply a proposed version — apply backs up the current file and records restore metadata first.
                      </div>

                      <div className="grid gap-3 lg:grid-cols-3">
                        <label className="text-xs text-gray-400">
                          Document
                          <div className="mt-1 inline-flex w-full rounded-md border border-gray-700 bg-gray-900/60 p-1 text-xs">
                            {(['readme', 'roadmap'] as const).map(docType => (
                              <button
                                key={docType}
                                onClick={() => { setAiDocType(docType); setAiPreview(null); setAiError(null); setAiApplyError(null); setAiApplyResult(null); }}
                                className={`flex-1 rounded px-2 py-1.5 uppercase transition-colors ${aiDocType === docType ? 'bg-violet-900/50 text-violet-100' : 'text-gray-300 hover:bg-gray-800'}`}
                              >
                                {docType}
                              </button>
                            ))}
                          </div>
                        </label>
                        <label className="text-xs text-gray-400">
                          Improvement template
                          <select
                            value={aiTemplateId}
                            onChange={(event: React.ChangeEvent<HTMLSelectElement>) => setAiTemplateId(event.target.value)}
                            className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                          >
                            {aiTemplateOptions.length === 0 && <option value="">Default improvement</option>}
                            {aiTemplateOptions.map(template => (
                              <option key={template.id} value={template.id} title={template.summary}>
                                {template.label}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label className="text-xs text-gray-400">
                          Provider
                          <select
                            value={aiProvider}
                            onChange={(event: React.ChangeEvent<HTMLSelectElement>) => setAiProvider(event.target.value as AiDocProvider)}
                            className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                          >
                            <option value="auto">Auto (AI when configured)</option>
                            <option value="heuristic">Heuristic (offline)</option>
                            <option value="anthropic">Anthropic</option>
                            <option value="openai">OpenAI</option>
                          </select>
                        </label>
                      </div>

                      <label className="block text-xs text-gray-400">
                        Custom improvement prompt (optional — applies to this cycle)
                        <textarea
                          value={aiCustomPrompt}
                          onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => setAiCustomPrompt(event.target.value)}
                          rows={2}
                          className="mt-1 block w-full rounded-md border border-gray-700 bg-gray-900 px-3 py-2 text-sm text-gray-100"
                          placeholder="e.g. Tighten the introduction and add a troubleshooting section..."
                        />
                      </label>

                      <div className="flex items-center gap-2 flex-wrap">
                        <button
                          onClick={() => void runAiImprovement()}
                          disabled={aiLoading}
                          className="inline-flex items-center gap-2 rounded-md border border-violet-700/50 bg-violet-950/40 px-3 py-1.5 text-sm text-violet-100 hover:bg-violet-900/50 disabled:opacity-50 transition-colors"
                        >
                          {aiLoading ? <SpinnerIcon className="w-4 h-4" /> : null}
                          {aiLoading ? 'Generating preview...' : aiPreview ? 'Regenerate Preview' : 'Generate Improvement Preview'}
                        </button>
                        {aiPreview && (
                          <button
                            onClick={() => void runAiImprovement(aiPreview.proposedContent)}
                            disabled={aiLoading}
                            className="rounded-md border border-indigo-700/50 bg-indigo-950/40 px-3 py-1.5 text-sm text-indigo-100 hover:bg-indigo-900/50 disabled:opacity-50 transition-colors"
                            title="Feed the proposed content back in as the starting point for another improvement cycle"
                          >
                            Run Another Cycle on Proposed
                          </button>
                        )}
                        <button
                          onClick={handleCopyAiProposed}
                          disabled={!aiPreview?.proposedContent}
                          title={!aiPreview?.proposedContent ? 'Generate an improvement preview first — there is no proposed document to copy.' : 'Copies the proposed document to the clipboard.'}
                          className="rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 disabled:opacity-50 transition-colors"
                        >
                          {aiProposedCopied ? 'Copied' : 'Copy Proposed'}
                        </button>
                        {aiPreview && (
                          <button
                            onClick={() => void handleApplyAiProposed()}
                            disabled={aiLoading || aiApplyLoading || !aiPreview.proposedContent}
                            className="inline-flex items-center gap-2 rounded-md border border-emerald-700/50 bg-emerald-950/40 px-3 py-1.5 text-sm text-emerald-100 hover:bg-emerald-900/50 disabled:opacity-50 transition-colors"
                            title="Write the proposed content to the repo after backing up the current file (explicit operator approval)"
                          >
                            {aiApplyLoading ? <SpinnerIcon className="w-4 h-4" /> : null}
                            {aiApplyLoading ? 'Applying...' : 'Apply Proposed to Repo'}
                          </button>
                        )}
                      </div>

                      {aiError && (
                        <div className="rounded-md border border-red-700/40 bg-red-950/20 px-3 py-2 text-xs text-red-200">
                          {aiError}
                        </div>
                      )}

                      {aiApplyError && (
                        <div className="rounded-md border border-red-700/40 bg-red-950/20 px-3 py-2 text-xs text-red-200">
                          {aiApplyError}
                        </div>
                      )}

                      {aiApplyResult && !aiApplyLoading && (
                        <div className="rounded-md border border-emerald-700/40 bg-emerald-950/20 px-3 py-2 text-xs text-emerald-200 space-y-1">
                          <div>
                            Applied to <span className="text-emerald-100 break-all">{aiApplyResult.targetPath}</span>
                            {' '}at {new Date(aiApplyResult.appliedAt).toLocaleString()}.
                          </div>
                          {aiApplyResult.backupPath ? (
                            <div className="text-emerald-300/80">
                              Backup: <span className="break-all">{aiApplyResult.backupPath}</span>
                            </div>
                          ) : (
                            <div className="text-emerald-300/80">No backup was needed — the file did not exist before this apply.</div>
                          )}
                          {aiApplyResult.restoreMetadataPath && (
                            <div className="text-emerald-300/80">
                              Restore metadata: <span className="break-all">{aiApplyResult.restoreMetadataPath}</span>
                            </div>
                          )}
                        </div>
                      )}

                      {aiPreview && !aiLoading && (
                        <>
                          <div className="rounded-md border border-gray-700 bg-gray-900/60 px-3 py-2 text-xs text-gray-400 space-y-1">
                            <div>
                              Provider: <span className="text-gray-200">{aiPreview.providerId}</span>
                              {aiPreview.modelId && <span className="text-gray-500"> ({aiPreview.modelId})</span>}
                              {' '}• Template: <span className="text-gray-200">{aiPreview.templateId || 'default'}</span>
                            </div>
                            <div>
                              Estimated score: <span className="text-gray-200">{aiPreview.estimatedScore.before}</span>
                              {' → '}
                              <span className="text-gray-200">{aiPreview.estimatedScore.after}</span>
                              {' '}
                              <span className={aiPreview.estimatedScore.delta >= 0 ? 'text-emerald-300' : 'text-red-300'}>
                                ({aiPreview.estimatedScore.delta >= 0 ? '+' : ''}{aiPreview.estimatedScore.delta})
                              </span>
                            </div>
                            {(() => {
                              // Tokens and cost, stated only as far as they were
                              // actually measured — see lib/aiUsage.ts.
                              const usage = describeUsage(aiPreview.usage);
                              return (
                                <div data-testid="ai-preview-usage">
                                  Tokens: <span className={usage.measured ? 'text-gray-200' : 'text-gray-500'}>{usage.tokensText}</span>
                                  {usage.tokenBreakdown && <span className="text-gray-500"> ({usage.tokenBreakdown})</span>}
                                  {' '}• Cost: <span className={usage.costText === 'unmeasured' ? 'text-gray-500' : 'text-gray-200'}>{usage.costText}</span>
                                  {usage.costCaveat && <span className="text-gray-500"> — {usage.costCaveat}</span>}
                                </div>
                              );
                            })()}
                          </div>

                          {aiPreview.warnings.length > 0 && (
                            <div className="space-y-2">
                              {aiPreview.warnings.map((warning, index) => (
                                <div key={`ai-warning-${index}`} className="rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-xs text-amber-200">
                                  {warning}
                                </div>
                              ))}
                            </div>
                          )}

                          {aiPreview.changeSummary.length > 0 && (
                            <div>
                              <div className="text-xs uppercase tracking-wide text-gray-500">What changed and why</div>
                              <ul className="mt-2 space-y-1 text-xs text-gray-300">
                                {aiPreview.changeSummary.map((change, index) => (
                                  <li key={`ai-change-${index}`} className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-1.5">
                                    {change}
                                  </li>
                                ))}
                              </ul>
                            </div>
                          )}

                          <div>
                            <div className="mb-2 text-xs uppercase tracking-wide text-gray-500">Side-by-side comparison</div>
                            <div className="grid gap-3 lg:grid-cols-2">
                              <div>
                                <div className="mb-1 text-xs text-gray-500">Current</div>
                                <pre className="max-h-80 overflow-auto rounded-md border border-gray-800 bg-gray-900/60 p-3 text-xs text-gray-300 whitespace-pre-wrap break-words">
                                  {aiPreview.currentContent || '(empty document)'}
                                </pre>
                              </div>
                              <div>
                                <div className="mb-1 text-xs text-gray-500">Proposed</div>
                                <pre className="max-h-80 overflow-auto rounded-md border border-violet-800/40 bg-violet-950/10 p-3 text-xs text-gray-200 whitespace-pre-wrap break-words">
                                  {aiPreview.proposedContent}
                                </pre>
                              </div>
                            </div>
                          </div>
                        </>
                      )}
                    </div>
                  )}

                  {aiTab === 'history' && (
                    <div className="mt-3">
                      {aiHistoryLoading ? (
                        <div className="flex items-center gap-2 text-sm text-gray-400">
                          <SpinnerIcon className="w-4 h-4" />
                          Loading improvement history…
                        </div>
                      ) : aiHistory.length === 0 ? (
                        <div className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                          No improvement cycles recorded for this repo yet. Generate an improvement preview first.
                        </div>
                      ) : (
                        <ul className="space-y-2">
                          {aiHistory.map(item => (
                            <li key={`${item.recordType ?? 'preview'}-${item.previewId}-${item.createdAt}`} className="rounded-md border border-gray-700 bg-gray-900/40 px-3 py-2 text-xs text-gray-300 space-y-1">
                              <div className="flex items-center justify-between gap-2 flex-wrap">
                                <span className="uppercase text-violet-300">
                                  {item.docType}
                                  {item.applied && (
                                    <span className="ml-2 rounded border border-emerald-700/50 bg-emerald-950/40 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-emerald-300">
                                      Applied
                                    </span>
                                  )}
                                </span>
                                <span className="text-gray-500">{new Date(item.createdAt).toLocaleString()}</span>
                              </div>
                              {item.recordType === 'apply' ? (
                                <div className="text-gray-400">
                                  Written to disk after operator approval.
                                  {item.backupPath && (
                                    <span className="block text-gray-500 break-all">Backup: {item.backupPath}</span>
                                  )}
                                </div>
                              ) : (
                                <>
                                  <div className="text-gray-400">
                                    Provider: <span className="text-gray-200">{item.providerId}</span>
                                    {' '}• Template: <span className="text-gray-200">{item.templateId || 'default'}</span>
                                  </div>
                                  <div className="text-gray-400">
                                    Score {item.scoreBefore} → {item.scoreAfter}{' '}
                                    <span className={item.scoreDelta >= 0 ? 'text-emerald-300' : 'text-red-300'}>
                                      ({item.scoreDelta >= 0 ? '+' : ''}{item.scoreDelta})
                                    </span>
                                    {' '}• Changes: {item.changeSummary.length} • Warnings: {item.warningCount}
                                  </div>
                                  {(() => {
                                    const usage = describeUsage({
                                      inputTokens: item.inputTokens ?? null,
                                      outputTokens: item.outputTokens ?? null,
                                      totalTokens: item.tokenUsage ?? null,
                                      measured: item.usageMeasured === true,
                                      source: item.usageSource ?? 'absent',
                                      costUsd: item.apiSpendUsd ?? null,
                                      costBasis: item.costBasis ?? 'usage-absent',
                                    });
                                    return (
                                      <div className="text-gray-500" data-testid="ai-history-usage">
                                        Tokens: {usage.tokensText} • Cost: {usage.costText}
                                        {usage.costCaveat && <span> — {usage.costCaveat}</span>}
                                      </div>
                                    );
                                  })()}
                                </>
                              )}
                              {item.customPrompt && (
                                <div className="italic text-gray-400">+ {item.customPrompt}</div>
                              )}
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  )}
                </div>

                <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                  <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <PullRequestIcon className="w-4 h-4 text-blue-300" />
                      Agent Runs
                    </div>
                    <button
                      onClick={() => void handleLoadAgentRuns()}
                      disabled={agentRunsLoading}
                      className="inline-flex items-center gap-2 rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-xs text-gray-200 hover:bg-gray-700 disabled:opacity-50 transition-colors"
                    >
                      {agentRunsLoading ? <SpinnerIcon className="w-3.5 h-3.5" /> : <RefreshIcon className="w-3.5 h-3.5" />}
                      Refresh
                    </button>
                  </div>
                  <div className="mt-2 text-xs text-gray-500">
                    Dispatched coding-agent runs for this repo from the agent-run ledger. Refresh a run to pull its branch, PR, and GitHub Actions state from GitHub and record validation evidence.
                  </div>

                  {agentRunsError && (
                    <div className="mt-3 rounded-md border border-red-700/40 bg-red-950/20 px-3 py-2 text-xs text-red-200">
                      {agentRunsError}
                    </div>
                  )}

                  {agentRunNotice && (
                    <div className="mt-3 rounded-md border border-blue-700/40 bg-blue-950/20 px-3 py-2 text-xs text-blue-200">
                      {agentRunNotice}
                    </div>
                  )}

                  {agentRunsLoading && agentRuns.length === 0 ? (
                    <div className="mt-3 flex items-center gap-2 text-sm text-gray-400">
                      <SpinnerIcon className="w-4 h-4" />
                      Loading agent runs…
                    </div>
                  ) : agentRuns.length === 0 ? (
                    <div className="mt-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                      No agent runs recorded for this repo yet. Dispatching a refined prompt creates a run in the ledger.
                    </div>
                  ) : (
                    <ul className="mt-3 space-y-2">
                      {agentRuns.map(run => (
                        <li key={run.runId} className="rounded-md border border-gray-700 bg-gray-900/40 px-3 py-2 text-xs text-gray-300 space-y-1">
                          <div className="flex items-center justify-between gap-2 flex-wrap">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className={`inline-flex rounded-full border px-2 py-0.5 capitalize ${AGENT_RUN_STATUS_STYLES[run.status] ?? AGENT_RUN_STATUS_STYLES.dispatched}`}>
                                {run.status}
                              </span>
                              {run.outcome && (
                                <span className="text-gray-400 capitalize">{run.outcome.replaceAll('-', ' ')}</span>
                              )}
                            </div>
                            <button
                              onClick={() => void handleRefreshAgentRun(run.runId)}
                              disabled={agentRunRefreshingId !== null}
                              className="inline-flex items-center gap-2 rounded-md border border-blue-700/50 bg-blue-950/40 px-2.5 py-1 text-[11px] text-blue-100 hover:bg-blue-900/50 disabled:opacity-50 transition-colors"
                              title="Query GitHub for this run's branch, PR, and Actions state and update the ledger"
                            >
                              {agentRunRefreshingId === run.runId ? <SpinnerIcon className="w-3 h-3" /> : <RefreshIcon className="w-3 h-3" />}
                              Refresh from GitHub
                            </button>
                          </div>
                          <div className="flex items-center justify-between gap-2 flex-wrap text-gray-500">
                            <span className="font-mono">{run.runId}</span>
                            <span>dispatched {formatDate(run.metrics?.dispatchedAt ?? run.createdAt)}</span>
                          </div>
                          {run.selectedTaskText && (
                            <div className="text-gray-200">{run.selectedTaskText}</div>
                          )}
                          {(run.selectedTaskSection || run.plannedPhaseName || run.plannedReleaseName) && (
                            <div className="text-gray-400">
                              {run.selectedTaskSection ? `Section: ${run.selectedTaskSection}` : 'Section: n/a'}
                              {run.plannedPhaseName ? ` • Phase: ${run.plannedPhaseName}` : ''}
                              {run.plannedReleaseName ? ` • Release: ${run.plannedReleaseName}` : ''}
                            </div>
                          )}
                          <div className="grid gap-1 sm:grid-cols-2">
                            <div>
                              Branch:{' '}
                              <span className="font-mono text-gray-300">{run.branch ?? 'not associated yet'}</span>
                            </div>
                            <div>
                              PR:{' '}
                              {run.prUrl ? (
                                <a href={run.prUrl} target="_blank" rel="noreferrer" className="text-blue-300 hover:underline">
                                  {run.prNumber ? `#${run.prNumber}` : run.prUrl}
                                  {run.prState ? ` (${run.prState}${run.prDraft ? ', draft' : ''})` : ''}
                                </a>
                              ) : (
                                <span className="text-gray-400">none yet</span>
                              )}
                            </div>
                            <div>
                              Work units:{' '}
                              <span className="text-gray-300">
                                est {formatUnitValue(run.metrics?.workUnitsEstimated)}
                                {' '}→ act {formatUnitValue(run.metrics?.workUnitsActual)}
                                {run.workUnitsEstimateSource ? ` (${run.workUnitsEstimateSource})` : ''}
                              </span>
                            </div>
                            <div>
                              Tokens:{' '}
                              <span className="text-gray-300">
                                {run.metrics?.tokenUsage !== null && run.metrics?.tokenUsage !== undefined
                                  ? Number(run.metrics.tokenUsage).toLocaleString()
                                  : 'unmeasured'}
                              </span>
                              {' '}• Cost:{' '}
                              <span className="text-gray-300" data-testid="agent-run-cost">
                                {/* Never $0.00 by default: this run's dispatch engine reports no spend, and a zero would read as "free". */}
                                {run.metrics?.apiSpendUsd !== null && run.metrics?.apiSpendUsd !== undefined
                                  ? `$${Number(run.metrics.apiSpendUsd).toFixed(4)}`
                                  : 'unmeasured'}
                              </span>
                            </div>
                            <div>
                              Actions:{' '}
                              {run.actions ? (
                                <span className={
                                  run.actions.conclusion === 'success'
                                    ? 'text-emerald-300'
                                    : run.actions.conclusion
                                      ? 'text-red-300'
                                      : 'text-amber-300'
                                }>
                                  {run.actions.workflowName ? `${run.actions.workflowName} • ` : ''}
                                  {run.actions.status}
                                  {run.actions.conclusion ? ` / ${run.actions.conclusion}` : ''}
                                </span>
                              ) : (
                                <span className="text-gray-400">not observed yet</span>
                              )}
                            </div>
                            <div>
                              Time to deliver:{' '}
                              <span className="text-gray-300">
                                {typeof run.metrics?.timeToDeliverSeconds === 'number'
                                  ? `${Math.round(run.metrics.timeToDeliverSeconds / 60)} min`
                                  : 'n/a'}
                              </span>
                            </div>
                          </div>
                          {run.association && run.association.matchedBy.length > 0 && (
                            <div className="text-gray-500">
                              Association evidence: {run.association.matchedBy.join(', ')} ({run.association.candidateCount} candidate{run.association.candidateCount === 1 ? '' : 's'})
                            </div>
                          )}
                          {run.lastRefreshAt && (
                            <div className="text-gray-600">Last refreshed {formatDate(run.lastRefreshAt)}</div>
                          )}
                        </li>
                      ))}
                    </ul>
                  )}
                </div>

                <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                  <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <BranchIcon className="w-4 h-4 text-emerald-300" />
                      Merge Readiness
                      {mergeReadiness && (
                        <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${mergeReadiness.ready ? 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50' : 'bg-red-900/40 text-red-200 border-red-700/50'}`}>
                          {mergeReadiness.ready ? 'Ready to merge' : `Blocked (${mergeReadiness.blockers.length})`}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <button
                        onClick={() => void handleEvaluateMergeReadiness()}
                        disabled={mergeReadinessLoading || mergeActionLoading}
                        className="inline-flex items-center gap-2 rounded-md border border-blue-700/50 bg-blue-950/40 px-3 py-1.5 text-xs text-blue-100 hover:bg-blue-900/50 disabled:opacity-50 transition-colors"
                        title="Re-check the latest agent run, PR mergeability, Actions state, worktree, and audit blockers"
                      >
                        {mergeReadinessLoading ? <SpinnerIcon className="w-3.5 h-3.5" /> : <RefreshIcon className="w-3.5 h-3.5" />}
                        Evaluate
                      </button>
                      {mergeReadiness?.ready && (
                        <button
                          onClick={() => void handleMergeAction()}
                          disabled={mergeActionLoading || mergeReadinessLoading}
                          className="inline-flex items-center gap-2 rounded-md border border-emerald-700/50 bg-emerald-950/40 px-3 py-1.5 text-xs text-emerald-100 hover:bg-emerald-900/50 disabled:opacity-50 transition-colors"
                          title="Explicit operator merge — the server re-evaluates readiness and refuses if any blocker remains"
                        >
                          {mergeActionLoading ? <SpinnerIcon className="w-3.5 h-3.5" /> : null}
                          Merge PR
                        </button>
                      )}
                    </div>
                  </div>
                  <div className="mt-2 text-xs text-gray-500">
                    Actions-gated merge signal for the latest agent run: merge stays blocked while the PR is missing, draft, conflicted, or unvalidated, while Actions are failing or pending, while the worktree is dirty, or while audit blockers remain. Merging is always an explicit operator action.
                  </div>

                  {mergeReadinessError && (
                    <div className="mt-3 rounded-md border border-red-700/40 bg-red-950/20 px-3 py-2 text-xs text-red-200">
                      {mergeReadinessError}
                    </div>
                  )}

                  {mergeActionNotice && (
                    <div className="mt-3 rounded-md border border-emerald-700/40 bg-emerald-950/20 px-3 py-2 text-xs text-emerald-200">
                      {mergeActionNotice}
                    </div>
                  )}

                  {!mergeReadiness && !mergeReadinessLoading && (
                    <div className="mt-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                      This repo has not been evaluated yet. Evaluate to compute an Actions-gated merge-readiness signal for its latest agent run.
                    </div>
                  )}

                  {mergeReadiness && (
                    <div className="mt-3 space-y-3">
                      <div className="rounded-md border border-gray-700 bg-gray-900/60 px-3 py-2 text-xs text-gray-400 space-y-1">
                        <div>
                          PR:{' '}
                          {mergeReadiness.prUrl ? (
                            <a href={mergeReadiness.prUrl} target="_blank" rel="noreferrer" className="text-blue-300 hover:underline">
                              {mergeReadiness.prNumber ? `#${mergeReadiness.prNumber}` : mergeReadiness.prUrl}
                            </a>
                          ) : (
                            <span className="text-gray-300">none</span>
                          )}
                          {mergeReadiness.evidence.prState && <span> • State: <span className="text-gray-200">{mergeReadiness.evidence.prState}{mergeReadiness.evidence.prDraft ? ' (draft)' : ''}</span></span>}
                          {typeof mergeReadiness.evidence.mergeable === 'boolean' && (
                            <span> • Mergeable: <span className={mergeReadiness.evidence.mergeable ? 'text-emerald-300' : 'text-red-300'}>{String(mergeReadiness.evidence.mergeable)}</span></span>
                          )}
                        </div>
                        <div>
                          Actions:{' '}
                          {mergeReadiness.evidence.actionsStatus ? (
                            <span className={mergeReadiness.evidence.actionsConclusion === 'success' ? 'text-emerald-300' : mergeReadiness.evidence.actionsConclusion ? 'text-red-300' : 'text-amber-300'}>
                              {mergeReadiness.evidence.actionsWorkflowName ? `${mergeReadiness.evidence.actionsWorkflowName} • ` : ''}
                              {mergeReadiness.evidence.actionsStatus}
                              {mergeReadiness.evidence.actionsConclusion ? ` / ${mergeReadiness.evidence.actionsConclusion}` : ''}
                            </span>
                          ) : (
                            <span className="text-gray-300">not observed</span>
                          )}
                          {' '}• Dirty files: <span className="text-gray-200">{mergeReadiness.evidence.localDirtyCount ?? 0}</span>
                          {' '}• Audit blockers: <span className="text-gray-200">{mergeReadiness.evidence.auditBlockerCount ?? 0}</span>
                        </div>
                        <div className="text-gray-600">Evaluated {formatDate(mergeReadiness.evaluatedAt)}</div>
                      </div>

                      {mergeReadiness.blockers.length > 0 ? (
                        <ul className="space-y-2">
                          {mergeReadiness.blockers.map((blocker, index) => (
                            <li key={`${blocker.code}-${index}`} className="rounded-md border border-red-900/40 bg-red-950/20 px-3 py-2 text-xs text-gray-200">
                              <div className="flex items-center justify-between gap-2 flex-wrap">
                                <span className="font-mono text-red-300">{blocker.code}</span>
                                <span className="text-gray-500">{blocker.source}</span>
                              </div>
                              <div className="mt-1">{blocker.message}</div>
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <div className="rounded-md border border-emerald-800/40 bg-emerald-950/20 px-3 py-2 text-sm text-emerald-100">
                          All merge-readiness checks pass: the agent PR is open and mergeable, validation succeeded, the worktree is clean, and no audit blockers remain.
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            ) : (
              <div className="flex h-full min-h-[320px] items-center justify-center text-sm text-gray-500">
                Select a repo from the Operations table to open its workspace.
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
};

export default OperationsWorkspaceView;

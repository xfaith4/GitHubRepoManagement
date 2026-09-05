import React, { useState, useMemo } from 'react';
import DefinitionHint from './DefinitionHint';
import {
  type DocAuditEntry,
  type DocAuditIndex,
  type DispatchReadiness,
  type PortfolioAssessmentEntry,
  type PortfolioAssessmentResult,
  type PortfolioPendingItemValue,
  type RoadmapAuditIndex,
  type RoadmapMaturityFilter,
  type RoadmapMaturityLevel,
} from '../types';
import { SpinnerIcon } from './icons';
import ProvenanceNotice from './ProvenanceNotice';
import { isKnownEmptyScope, repoActionsBlockedReason } from '../lib/dataProvenance';
import { formatValueScoreLabel, getValueTierPresentation } from '../lib/valueTier';

interface WorkQueueViewProps {
  auditIndex: DocAuditIndex | null;
  loading: boolean;
  error?: string | null;
  onRefresh: () => void;
  onScan: () => void;
  onStartImprovementWorkflow?: (repoName?: string) => void;
  onViewRoadmap?: (repoName: string) => void;
  onPreviewTask?: (repoName: string, roadmapPath?: string) => void;
  onViewRoadmapAudit?: (repoName: string) => void;
  onRepairRoadmap?: (repoName: string) => void;
  onLintRoadmap?: (repoName: string) => void;
  onStandardizeReadme?: (repoName: string) => void;
  onGenerateReadme?: (repoName: string) => void;
  onEvaluateRepo?: (repoName: string) => void;
  onDispatchRelease?: (repoName: string) => void;
  isScanning: boolean;
  roadmapAuditIndex?: RoadmapAuditIndex | null;
  portfolioAssessment?: PortfolioAssessmentResult | null;
  /**
   * Repo count from the current live scan. The queue and its maturity buckets
   * read the persisted doc-audit index, which outlives any single scan — this
   * lets the view flag when the two disagree rather than showing populated
   * buckets under a "0 repos" header.
   */
  liveRepoCount?: number;
}

type ReadinessFilter = DispatchReadiness | 'all';

const MATURITY_CONFIG: Record<RoadmapMaturityLevel, { label: string; badgeClass: string; dotClass: string }> = {
  'L0-Absent': {
    label: 'L0',
    badgeClass: 'bg-gray-800 text-gray-400 border-gray-600',
    dotClass: 'bg-gray-500',
  },
  'L1-Informal': {
    label: 'L1',
    badgeClass: 'bg-red-900/40 text-red-300 border-red-700/40',
    dotClass: 'bg-red-400',
  },
  'L2-Structured': {
    label: 'L2',
    badgeClass: 'bg-orange-900/40 text-orange-300 border-orange-700/40',
    dotClass: 'bg-orange-400',
  },
  'L3-Contract-Ready': {
    label: 'L3',
    badgeClass: 'bg-yellow-900/40 text-yellow-300 border-yellow-700/40',
    dotClass: 'bg-yellow-400',
  },
  'L4-Orchestration-Ready': {
    label: 'L4',
    badgeClass: 'bg-green-900/40 text-green-300 border-green-700/40',
    dotClass: 'bg-green-400',
  },
};

function MaturityMiniBadge({ level }: { level: RoadmapMaturityLevel }) {
  const config = MATURITY_CONFIG[level] ?? MATURITY_CONFIG['L0-Absent'];
  return (
    <span
      className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded border text-xs font-medium ${config.badgeClass}`}
      title={level}
    >
      <span className={`inline-block w-1.5 h-1.5 rounded-full ${config.dotClass}`} />
      {config.label}
    </span>
  );
}

const READINESS_CONFIG: Record<DispatchReadiness, { label: string; badgeClass: string; dotClass: string; priority: number }> = {
  ready: {
    label: 'Ready',
    badgeClass: 'bg-green-900/50 text-green-300 border-green-700/50',
    dotClass: 'bg-green-400',
    priority: 1,
  },
  'needs-doc-standardization': {
    label: 'Needs Docs',
    badgeClass: 'bg-yellow-900/50 text-yellow-300 border-yellow-700/50',
    dotClass: 'bg-yellow-400',
    priority: 2,
  },
  'missing-roadmap': {
    label: 'No Roadmap',
    badgeClass: 'bg-gray-700/60 text-gray-300 border-gray-600/50',
    dotClass: 'bg-gray-400',
    priority: 3,
  },
  'roadmap-complete': {
    label: 'Roadmap Complete',
    badgeClass: 'bg-blue-900/50 text-blue-300 border-blue-700/50',
    dotClass: 'bg-blue-400',
    priority: 4,
  },
  'no-checklist': {
    label: 'No Checklist Items',
    badgeClass: 'bg-amber-900/50 text-amber-300 border-amber-700/50',
    dotClass: 'bg-amber-400',
    priority: 5,
  },
  'parse-error': {
    label: 'Parse Error',
    badgeClass: 'bg-orange-900/50 text-orange-300 border-orange-700/50',
    dotClass: 'bg-orange-400',
    priority: 6,
  },
  blocked: {
    label: 'Dispatch blocked',
    badgeClass: 'bg-red-900/50 text-red-300 border-red-700/50',
    dotClass: 'bg-red-500',
    priority: 7,
  },
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

function ReadinessBadge({ readiness }: { readiness: DispatchReadiness }) {
  const config = READINESS_CONFIG[readiness] ?? READINESS_CONFIG['missing-roadmap'];
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded border text-xs font-medium ${config.badgeClass}`}
    >
      <span className={`inline-block w-1.5 h-1.5 rounded-full ${config.dotClass}`} />
      {config.label}
    </span>
  );
}

function getDefaultRoadmapPath(repoPath?: string | null): string | undefined {
  if (!repoPath) return undefined;
  const trimmed = repoPath.replace(/[\\/]+$/, '');
  return trimmed ? `${trimmed}\\ROADMAP.md` : undefined;
}

function buildValueRationaleTooltip(item: PortfolioPendingItemValue, assessment?: PortfolioAssessmentEntry | null): string {
  const lines = [
    `Highest-value roadmap item: ${item.text}`,
    `Score: ${formatValueScoreLabel(item.valueScore, item.valueTier)}`,
  ];

  if (assessment?.pendingItemCount) {
    lines.push(`Pending roadmap items in repo: ${assessment.pendingItemCount}`);
  }

  if (item.tags.length > 0) {
    lines.push(`Tags: ${item.tags.join(', ')}`);
  }

  if (item.valueRationale.length > 0) {
    lines.push('Why it ranks highly:');
    item.valueRationale.forEach(reason => lines.push(`- ${reason}`));
  }

  return lines.join('\n');
}

const SAVED_FILTERS_KEY = 'work-queue-saved-filters';

interface SavedFilter {
  name: string;
  readinessFilter: string;
  maturityFilter: string;
  tagFilter: string;
  searchText: string;
}

const WorkQueueView: React.FC<WorkQueueViewProps> = ({
  auditIndex,
  loading,
  error,
  onRefresh,
  onScan,
  onStartImprovementWorkflow,
  onViewRoadmap,
  onPreviewTask,
  onViewRoadmapAudit,
  onRepairRoadmap,
  onLintRoadmap,
  onStandardizeReadme,
  onGenerateReadme,
  onEvaluateRepo,
  onDispatchRelease,
  isScanning,
  roadmapAuditIndex,
  portfolioAssessment,
  liveRepoCount,
}) => {
  const [readinessFilter, setReadinessFilter] = useState<ReadinessFilter>('all');
  const [maturityFilter, setMaturityFilter] = useState<RoadmapMaturityFilter>('all');
  const [tagFilter, setTagFilter] = useState<string>('all');
  const [expandedRepos, setExpandedRepos] = useState<Set<string>>(new Set());
  // Release 2.6 Phase 3 — inline value-rationale expansion, keyed by repo, so
  // the "Why?" explanation opens in place instead of only in a hover tooltip.
  const [whyExpanded, setWhyExpanded] = useState<Set<string>>(new Set());
  const [filterText, setFilterText] = useState('');
  const [savedFilters, setSavedFilters] = useState<SavedFilter[]>(() => {
    try {
      const raw = localStorage.getItem(SAVED_FILTERS_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch { return []; }
  });
  const [showSaveFilter, setShowSaveFilter] = useState(false);
  const [newFilterName, setNewFilterName] = useState('');

  const entries = auditIndex?.entries ?? [];

  // Rows can outlive the scan that produced them (the index is persisted). When
  // the live scan is known-empty, every row targets a repo the app cannot
  // currently see, so *mutating* actions — Improve, Repair, Standardize,
  // Generate README, Evaluate, Dispatch Release — would act on a path that may
  // not exist. Read-only actions (Audit, Lint, Roadmap, Preview Task) stay
  // enabled: inspecting the carried-over data is exactly how an operator
  // diagnoses why the scan came back empty.
  const mutatingActionsBlocked = isKnownEmptyScope(liveRepoCount);
  const mutatingBlockedTitle = repoActionsBlockedReason(0);
  const mutatingTitle = (normal: string) => (mutatingActionsBlocked ? mutatingBlockedTitle ?? normal : normal);
  const disabledActionClass = ' disabled:opacity-40 disabled:cursor-not-allowed';

  // Build a lookup for roadmap audit entries by repoName
  const auditByRepo = useMemo(() => {
    const map = new Map<string, import('../types').RoadmapAuditEntry>();
    for (const e of (roadmapAuditIndex?.entries ?? [])) {
      map.set(e.repoName.toLowerCase(), e);
    }
    return map;
  }, [roadmapAuditIndex]);

  const assessmentByRepo = useMemo(() => {
    const map = new Map<string, PortfolioAssessmentEntry>();
    for (const e of (portfolioAssessment?.entries ?? [])) {
      map.set(e.repoName.toLowerCase(), e);
    }
    return map;
  }, [portfolioAssessment]);

  const readinessCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const e of entries) {
      counts[e.dispatchReadiness] = (counts[e.dispatchReadiness] ?? 0) + 1;
    }
    return counts;
  }, [entries]);

  const filteredEntries = useMemo(() => {
    let result = [...entries];
    if (readinessFilter !== 'all') {
      result = result.filter(e => e.dispatchReadiness === readinessFilter);
    }
    if (maturityFilter !== 'all') {
      result = result.filter(e => {
        const audit = auditByRepo.get(e.repoName.toLowerCase());
        return audit?.maturityLevel === maturityFilter;
      });
    }
    if (tagFilter !== 'all') {
      result = result.filter(e => {
        const audit = auditByRepo.get(e.repoName.toLowerCase());
        return (audit?.nextPendingItem?.tags ?? []).includes(tagFilter);
      });
    }
    if (filterText.trim()) {
      const lower = filterText.toLowerCase();
      result = result.filter(e => {
        const assessment = assessmentByRepo.get(e.repoName.toLowerCase());
        return (
          e.repoName.toLowerCase().includes(lower) ||
          (e.nextPendingRoadmapItem ?? '').toLowerCase().includes(lower) ||
          (assessment?.topValueItem?.text ?? '').toLowerCase().includes(lower) ||
          (assessment?.recommendedAction ?? '').toLowerCase().includes(lower)
        );
      });
    }
    return result.sort((left, right) => {
      const priorityDiff =
        (READINESS_CONFIG[left.dispatchReadiness]?.priority ?? 99) -
        (READINESS_CONFIG[right.dispatchReadiness]?.priority ?? 99);
      if (priorityDiff !== 0) {
        return priorityDiff;
      }

      const leftAssessment = assessmentByRepo.get(left.repoName.toLowerCase());
      const rightAssessment = assessmentByRepo.get(right.repoName.toLowerCase());
      const leftValue = leftAssessment?.topValueItem?.valueScore ?? -1;
      const rightValue = rightAssessment?.topValueItem?.valueScore ?? -1;
      if (rightValue !== leftValue) {
        return rightValue - leftValue;
      }

      const leftPending = leftAssessment?.pendingItemCount ?? 0;
      const rightPending = rightAssessment?.pendingItemCount ?? 0;
      if (rightPending !== leftPending) {
        return rightPending - leftPending;
      }

      return left.repoName.localeCompare(right.repoName);
    });
  }, [entries, readinessFilter, maturityFilter, tagFilter, filterText, auditByRepo, assessmentByRepo]);

  const toggleExpand = (repoName: string) => {
    setExpandedRepos(prev => {
      const next = new Set(prev);
      if (next.has(repoName)) {
        next.delete(repoName);
      } else {
        next.add(repoName);
      }
      return next;
    });
  };

  const readyCount = readinessCounts['ready'] ?? 0;
  const needsDocsCount = readinessCounts['needs-doc-standardization'] ?? 0;
  const blockedCount = readinessCounts['blocked'] ?? 0;

  // Collect all tags from roadmap audit next-pending items
  const availableTags = useMemo(() => {
    const tagSet = new Set<string>();
    for (const e of (roadmapAuditIndex?.entries ?? [])) {
      for (const tag of (e.nextPendingItem?.tags ?? [])) {
        tagSet.add(tag);
      }
    }
    return Array.from(tagSet).sort();
  }, [roadmapAuditIndex]);

  // Count how many repos are at each maturity level
  const maturityCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const e of (roadmapAuditIndex?.entries ?? [])) {
      counts[e.maturityLevel] = (counts[e.maturityLevel] ?? 0) + 1;
    }
    return counts;
  }, [roadmapAuditIndex]);

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-4">
      {/* Header */}
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-semibold text-white">Doc Readiness Queue</h2>
          <p className="text-sm text-gray-400 mt-0.5">
            Per-repo dispatch readiness based on roadmap state and documentation standards.
            {(portfolioAssessment?.entries?.length ?? 0) > 0 && ' Ready repos are ranked by highest-value pending roadmap item.'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {onStartImprovementWorkflow && (
            <button
              onClick={() => onStartImprovementWorkflow()}
              disabled={entries.length === 0 || mutatingActionsBlocked}
              title={mutatingTitle('Run the guided improvement workflow across the queue')}
              className="px-3 py-1.5 text-sm bg-emerald-800 hover:bg-emerald-700 text-emerald-100 rounded border border-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Guided Improvement
            </button>
          )}
          <button
            onClick={onRefresh}
            disabled={loading}
            className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded border border-gray-600 disabled:opacity-50 transition-colors"
          >
            Refresh
          </button>
          <button
            onClick={onScan}
            disabled={isScanning}
            className="px-3 py-1.5 text-sm bg-indigo-700 hover:bg-indigo-600 text-white rounded border border-indigo-600 disabled:opacity-50 flex items-center gap-1.5 transition-colors"
          >
            {isScanning && <SpinnerIcon className="w-3.5 h-3.5 animate-spin" />}
            {isScanning ? 'Rescanning…' : 'Rescan roadmaps'}
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-lg border border-red-700/50 bg-red-900/20 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      )}

      {/* The queue, its readiness counts, and the maturity buckets all come from
          the persisted doc-audit index. When the live scan disagrees, say so
          here rather than letting populated buckets sit under a "0 repos"
          header. */}
      <ProvenanceNotice
        testId="queue-provenance-notice"
        className="mb-4"
        liveRepoCount={liveRepoCount as number}
        persistedEntryCount={entries.length}
        persistedGeneratedAt={auditIndex?.auditedAt}
      />

      {/* Summary strip */}
      {entries.length > 0 && (
        <div className="flex flex-wrap gap-3 mb-4">
          <div className="px-3 py-2 bg-green-900/20 border border-green-700/40 rounded-lg text-sm">
            <span className="text-green-300 font-semibold">{readyCount}</span>
            <DefinitionHint
              className="text-green-400/80 ml-1.5"
              definition="Dispatch readiness: audited repos whose docs can receive agent work — one of three distinct readiness measures (see status vocabulary)."
              data-testid="dispatch-ready-definition"
            >dispatch-ready</DefinitionHint>
          </div>
          <div className="px-3 py-2 bg-yellow-900/20 border border-yellow-700/40 rounded-lg text-sm">
            <span className="text-yellow-300 font-semibold">{needsDocsCount}</span>
            <span className="text-yellow-400/80 ml-1.5">need doc improvements</span>
          </div>
          {blockedCount > 0 && (
            <div className="px-3 py-2 bg-red-900/20 border border-red-700/40 rounded-lg text-sm">
              <span className="text-red-300 font-semibold">{blockedCount}</span>
              <span className="text-red-400/80 ml-1.5">blocked</span>
            </div>
          )}
          <div className="px-3 py-2 bg-gray-800/60 border border-gray-700/40 rounded-lg text-sm">
            <span className="text-gray-300 font-semibold">{entries.length}</span>
            <span className="text-gray-400/80 ml-1.5">repos audited</span>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <input
          type="text"
          placeholder="Filter by repo name..."
          value={filterText}
          onChange={e => setFilterText(e.target.value)}
          className="block w-full max-w-xs bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
        />
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => setReadinessFilter('all')}
            className={`px-3 py-1 rounded text-xs font-medium border transition-colors ${
              readinessFilter === 'all'
                ? 'bg-indigo-700 text-white border-indigo-600'
                : 'bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700'
            }`}
          >
            All ({entries.length})
          </button>
          {(Object.keys(READINESS_CONFIG) as DispatchReadiness[]).map(r => {
            const count = readinessCounts[r] ?? 0;
            if (count === 0) return null;
            const cfg = READINESS_CONFIG[r];
            return (
              <button
                key={r}
                onClick={() => setReadinessFilter(r)}
                className={`px-3 py-1 rounded text-xs font-medium border transition-colors ${
                  readinessFilter === r
                    ? 'bg-indigo-700 text-white border-indigo-600'
                    : 'bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700'
                }`}
              >
                {cfg.label} ({count})
              </button>
            );
          })}
        </div>
        {/* Maturity filter */}
        {roadmapAuditIndex && roadmapAuditIndex.entries.length > 0 && (
          <div className="flex flex-wrap gap-2 items-center">
            <span className="text-xs text-gray-500 font-medium">Maturity:</span>
            <button
              onClick={() => setMaturityFilter('all')}
              className={`px-2 py-0.5 rounded text-xs font-medium border transition-colors ${
                maturityFilter === 'all'
                  ? 'bg-indigo-700 text-white border-indigo-600'
                  : 'bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700'
              }`}
            >
              All
            </button>
            {(Object.keys(MATURITY_CONFIG) as RoadmapMaturityLevel[]).map(level => {
              const count = maturityCounts[level] ?? 0;
              if (count === 0) return null;
              const cfg = MATURITY_CONFIG[level];
              return (
                <button
                  key={level}
                  onClick={() => setMaturityFilter(level)}
                  className={`px-2 py-0.5 rounded text-xs font-medium border transition-colors ${
                    maturityFilter === level
                      ? 'bg-indigo-700 text-white border-indigo-600'
                      : `${cfg.badgeClass} hover:opacity-80`
                  }`}
                  title={level}
                >
                  {cfg.label} ({count})
                </button>
              );
            })}
          </div>
        )}
        {/* Tag filter — only shown when at least one tag exists */}
        {availableTags.length > 0 && (
          <div className="flex flex-wrap gap-2 items-center">
            <span className="text-xs text-gray-500 font-medium">Tag:</span>
            <button
              onClick={() => setTagFilter('all')}
              className={`px-2 py-0.5 rounded text-xs font-medium border transition-colors ${
                tagFilter === 'all'
                  ? 'bg-indigo-700 text-white border-indigo-600'
                  : 'bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700'
              }`}
            >
              All
            </button>
            {availableTags.map(tag => (
              <button
                key={tag}
                onClick={() => setTagFilter(tag)}
                className={`px-2 py-0.5 rounded text-xs font-medium border transition-colors ${
                  tagFilter === tag
                    ? 'bg-indigo-700 text-white border-indigo-600'
                    : 'bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700'
                }`}
              >
                [{tag}]
              </button>
            ))}
          </div>
        )}

        {/* Saved filters */}
        <div className="flex flex-wrap gap-2 items-center w-full mt-1">
          {savedFilters.length > 0 && (
            <>
              <span className="text-xs text-gray-500 font-medium">Saved:</span>
              {savedFilters.map((sf, i) => (
                <button
                  key={i}
                  onClick={() => {
                    setReadinessFilter(sf.readinessFilter as ReadinessFilter);
                    setMaturityFilter(sf.maturityFilter as RoadmapMaturityFilter);
                    setTagFilter(sf.tagFilter ?? 'all');
                    setFilterText(sf.searchText);
                  }}
                  className="px-2 py-0.5 rounded text-xs font-medium border bg-gray-800 text-gray-300 border-gray-600 hover:bg-gray-700 transition-colors"
                  title={`Readiness: ${sf.readinessFilter}, Maturity: ${sf.maturityFilter}, Tag: ${sf.tagFilter ?? 'all'}, Search: "${sf.searchText}"`}
                >
                  {sf.name}
                </button>
              ))}
              <button
                onClick={() => {
                  const updated: SavedFilter[] = [];
                  localStorage.setItem(SAVED_FILTERS_KEY, JSON.stringify(updated));
                  setSavedFilters(updated);
                }}
                className="px-2 py-0.5 rounded text-xs font-medium border bg-gray-800 text-red-400 border-gray-600 hover:bg-gray-700 transition-colors"
                title="Clear all saved filters"
              >
                Clear saved
              </button>
            </>
          )}
          {!showSaveFilter ? (
            <button
              onClick={() => { setShowSaveFilter(true); setNewFilterName(''); }}
              className="px-2 py-0.5 rounded text-xs font-medium border bg-gray-800 text-indigo-300 border-indigo-700/50 hover:bg-gray-700 transition-colors"
            >
              + Save View
            </button>
          ) : (
            <div className="flex items-center gap-1.5">
              <input
                type="text"
                placeholder="Filter name…"
                value={newFilterName}
                onChange={e => setNewFilterName(e.target.value)}
                onKeyDown={e => {
                  if (e.key === 'Escape') setShowSaveFilter(false);
                }}
                className="bg-gray-900 border border-gray-600 rounded px-2 py-0.5 text-xs text-white focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 w-32"
                autoFocus
              />
              <button
                disabled={!newFilterName.trim()}
                title={!newFilterName.trim() ? 'Name this filter before saving it.' : 'Saves the current filter settings under this name.'}
                onClick={() => {
                  const entry: SavedFilter = {
                    name: newFilterName.trim(),
                    readinessFilter,
                    maturityFilter,
                    tagFilter,
                    searchText: filterText,
                  };
                  const updated = [...savedFilters, entry];
                  localStorage.setItem(SAVED_FILTERS_KEY, JSON.stringify(updated));
                  setSavedFilters(updated);
                  setShowSaveFilter(false);
                  setNewFilterName('');
                }}
                className="px-2 py-0.5 rounded text-xs font-medium border bg-indigo-700 text-white border-indigo-600 hover:bg-indigo-600 disabled:opacity-40 transition-colors"
              >
                Save
              </button>
              <button
                onClick={() => setShowSaveFilter(false)}
                className="px-2 py-0.5 rounded text-xs text-gray-400 hover:text-gray-200"
              >
                ✕
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Loading state */}
      {loading && entries.length === 0 && (
        <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
          <SpinnerIcon className="w-5 h-5 animate-spin" />
          <span>Loading documentation audit…</span>
        </div>
      )}

      {/* Empty state */}
      {!loading && entries.length === 0 && (
        <div className="text-center py-10 text-gray-500">
          <p className="mb-3">No documentation audit data available.</p>
          <button
            onClick={onScan}
            className="px-4 py-2 bg-indigo-700 hover:bg-indigo-600 text-white rounded border border-indigo-600 text-sm transition-colors"
          >
            Run Documentation Audit
          </button>
        </div>
      )}

      {/* Repo list */}
      {filteredEntries.length > 0 && (
        <div className="space-y-2">
          {filteredEntries.map(entry => {
            const repoKey = entry.repoName.toLowerCase();
            const isExpanded = expandedRepos.has(entry.repoName);
            const hasFindings = entry.docFindings.length > 0;
            const hasMissingReadme = (entry.docFindings ?? []).some(
              f => /readme/i.test(f.file ?? '') && f.severity === 'critical'
            );
            const roadmapAudit = auditByRepo.get(repoKey);
            const assessment = assessmentByRepo.get(repoKey);
            const topValueItem = assessment?.topValueItem ?? null;
            const valueTier = topValueItem ? getValueTierPresentation(topValueItem.valueTier) : null;
            const valueTooltip = topValueItem ? buildValueRationaleTooltip(topValueItem, assessment) : '';
            return (
              <div
                key={entry.repoPath || entry.repoName}
                className="border border-gray-700 rounded-lg bg-gray-800/40 overflow-hidden"
              >
                {/* Repo row header */}
                <div
                  className={`flex flex-wrap items-start gap-3 px-4 py-3 ${hasFindings ? 'cursor-pointer hover:bg-gray-700/40' : ''}`}
                  onClick={() => hasFindings && toggleExpand(entry.repoName)}
                >
                  {/* Expand toggle */}
                  <div className="mt-0.5 w-4 flex-shrink-0 text-gray-500">
                    {hasFindings ? (
                      <span className="text-xs">{isExpanded ? '▼' : '▶'}</span>
                    ) : (
                      <span className="text-xs text-gray-600">—</span>
                    )}
                  </div>

                  {/* Repo info */}
                  <div className="flex-1 min-w-[220px]">
                    <div className="flex flex-wrap items-center gap-2 mb-1">
                      <span className="text-sm font-semibold text-white truncate">{entry.repoName}</span>
                      <ReadinessBadge readiness={entry.dispatchReadiness} />
                      {/* Roadmap maturity badge from contract audit */}
                      {roadmapAudit && (
                        <MaturityMiniBadge level={roadmapAudit.maturityLevel} />
                      )}
                      {entry.criticalCount > 0 && (
                        <span className="text-xs px-1.5 py-0.5 rounded bg-red-900/40 text-red-300 border border-red-700/40">
                          {entry.criticalCount} critical
                        </span>
                      )}
                      {entry.warningCount > 0 && (
                        <span className="text-xs px-1.5 py-0.5 rounded bg-yellow-900/30 text-yellow-300 border border-yellow-700/30">
                          {entry.warningCount} warning
                        </span>
                      )}
                    </div>

                    {/* Next pending roadmap item */}
                    {entry.roadmapState === 'pending' && entry.nextPendingRoadmapItem && (
                      <div className="text-xs text-indigo-400/80 truncate mb-1" title={entry.nextPendingRoadmapItem}>
                        ↳ {entry.nextPendingRoadmapItem}
                      </div>
                    )}

                    {/* Recommended action for blocked/needs-doc */}
                    {(entry.dispatchReadiness === 'blocked' || entry.dispatchReadiness === 'needs-doc-standardization') &&
                      entry.docFindings.length > 0 && (
                        <div className="text-xs text-gray-400 truncate">
                          {entry.docFindings[0].recommendedAction}
                        </div>
                      )}

                    {assessment?.recommendedAction && entry.dispatchReadiness === 'ready' && (
                      <div className="text-xs text-gray-400 truncate">
                        {assessment.recommendedAction}
                      </div>
                    )}

                    {/* Local path */}
                    {entry.repoPath && (
                      <div className="text-xs text-gray-500 truncate mt-0.5" title={entry.repoPath}>
                        {entry.repoPath}
                      </div>
                    )}
                  </div>

                  {/* Rendered only when there IS a value. When topValueItem is
                      null the card could show nothing but its own empty state,
                      while still costing a quarter of the row's width and
                      contributing the bulk of this tab's sub-AA text. An empty
                      slot that never fills is not an empty state; it is a
                      column that should not exist. */}
                  {topValueItem && (
                  <div className="w-full sm:w-auto sm:min-w-[188px]">
                    <div className="rounded-lg border border-gray-700 bg-gray-900/60 px-3 py-2">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-[11px] uppercase tracking-wide text-gray-500">Value</span>
                        {valueTier && (
                          <span className={`inline-flex items-center rounded border px-2 py-0.5 text-[11px] font-medium ${valueTier.chipClass}`}>
                            {valueTier.label}
                          </span>
                        )}
                      </div>
                      {topValueItem && (
                        <>
                          <div className="mt-2 flex items-center justify-between gap-3">
                            <div className={`text-xl font-semibold ${valueTier?.scoreClass ?? 'text-white'}`}>
                              {topValueItem.valueScore}
                            </div>
                            <button
                              type="button"
                              onClick={event => {
                                event.stopPropagation();
                                setWhyExpanded(prev => {
                                  const next = new Set(prev);
                                  if (next.has(entry.repoName)) next.delete(entry.repoName);
                                  else next.add(entry.repoName);
                                  return next;
                                });
                              }}
                              aria-expanded={whyExpanded.has(entry.repoName)}
                              data-testid="value-why-toggle"
                              title={valueTooltip}
                              className="text-xs text-indigo-300 underline decoration-dotted underline-offset-2 hover:text-indigo-200"
                            >
                              {whyExpanded.has(entry.repoName) ? 'Hide' : 'Why?'}
                            </button>
                          </div>
                          <div className="mt-1 text-xs text-gray-400 truncate" title={topValueItem.text}>
                            {topValueItem.text}
                          </div>
                          <div className="mt-1 text-[11px] text-gray-500">
                            {assessment?.pendingItemCount ?? 0} pending roadmap item{assessment?.pendingItemCount === 1 ? '' : 's'}
                          </div>
                          {whyExpanded.has(entry.repoName) && (
                            <div
                              data-testid="value-why-detail"
                              className="mt-2 rounded border border-gray-700 bg-gray-900/70 px-2 py-1.5 text-[11px] text-gray-300 whitespace-pre-line"
                            >
                              {valueTooltip}
                            </div>
                          )}
                        </>
                      )}
                    </div>
                  </div>
                  )}

                  {/* Action buttons */}
                  <div className="flex-shrink-0 flex flex-wrap items-center gap-1.5 sm:ml-auto">
                    {onStartImprovementWorkflow && (
                      <button
                        onClick={e => { e.stopPropagation(); onStartImprovementWorkflow(entry.repoName); }}
                        disabled={mutatingActionsBlocked}
                        className={`text-xs px-2 py-1 rounded border border-emerald-700/50 bg-emerald-900/40 text-emerald-300 hover:bg-emerald-800/60 transition-colors${disabledActionClass}`}
                        title={mutatingTitle('Scan README and ROADMAP, review an improvement task, and dispatch it to a pull request')}
                      >
                        Improve
                      </button>
                    )}
                    {onPreviewTask && entry.dispatchReadiness === 'ready' && (
                      <button
                        onClick={e => {
                          e.stopPropagation();
                          const entryRoadmapPath = (entry as DocAuditEntry & { roadmapPath?: string | null }).roadmapPath;
                          onPreviewTask(entry.repoName, entryRoadmapPath ?? roadmapAudit?.roadmapPath ?? assessment?.roadmapPath ?? getDefaultRoadmapPath(entry.repoPath));
                        }}
                        className="text-xs px-2 py-1 rounded border border-green-700/50 bg-green-900/40 text-green-300 hover:bg-green-800/60 transition-colors"
                        title="Preview Copilot Task Packet"
                      >
                        Preview Task
                      </button>
                    )}
                    {onViewRoadmapAudit && roadmapAudit && (
                      <button
                        onClick={e => { e.stopPropagation(); onViewRoadmapAudit(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-purple-700/50 bg-purple-900/40 text-purple-300 hover:bg-purple-800/60 transition-colors"
                        title="View Roadmap Contract Audit"
                      >
                        Audit
                      </button>
                    )}
                    {onRepairRoadmap && roadmapAudit && ['L0-Absent', 'L1-Informal', 'L2-Structured'].includes(roadmapAudit.maturityLevel) && (
                      <button
                        onClick={e => { e.stopPropagation(); onRepairRoadmap(entry.repoName); }}
                        disabled={mutatingActionsBlocked}
                        className={`text-xs px-2 py-1 rounded border border-orange-700/50 bg-orange-900/40 text-orange-300 hover:bg-orange-800/60 transition-colors${disabledActionClass}`}
                        title={mutatingTitle('Preview Roadmap Repair')}
                      >
                        Repair
                      </button>
                    )}
                    {onLintRoadmap && entry.roadmapState && entry.roadmapState !== 'missing' && (
                      <button
                        onClick={e => { e.stopPropagation(); onLintRoadmap(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-teal-700/50 bg-teal-900/40 text-teal-300 hover:bg-teal-800/60 transition-colors"
                        title="Lint Roadmap"
                      >
                        Lint
                      </button>
                    )}
                    {onStandardizeReadme && (
                      <button
                        onClick={e => { e.stopPropagation(); onStandardizeReadme(entry.repoName); }}
                        disabled={mutatingActionsBlocked}
                        className={`text-xs px-2 py-1 rounded border border-cyan-700/50 bg-cyan-900/40 text-cyan-300 hover:bg-cyan-800/60 transition-colors${disabledActionClass}`}
                        title={mutatingTitle('Standardize README')}
                      >
                        Standardize
                      </button>
                    )}
                    {onGenerateReadme && hasMissingReadme && (
                      <button
                        onClick={e => { e.stopPropagation(); onGenerateReadme(entry.repoName); }}
                        disabled={mutatingActionsBlocked}
                        className={`text-xs px-2 py-1 rounded border border-emerald-700/50 bg-emerald-900/40 text-emerald-300 hover:bg-emerald-800/60 transition-colors${disabledActionClass}`}
                        title={mutatingTitle('Generate README with GitHub Copilot')}
                      >
                        Generate README
                      </button>
                    )}
                    {onEvaluateRepo && (
                      <button
                        onClick={e => { e.stopPropagation(); onEvaluateRepo(entry.repoName); }}
                        disabled={mutatingActionsBlocked}
                        className={`text-xs px-2 py-1 rounded border border-violet-700/50 bg-violet-900/40 text-violet-300 hover:bg-violet-800/60 transition-colors${disabledActionClass}`}
                        title={mutatingTitle('Evaluate roadmap gaps, modernization opportunities, and hardening priorities')}
                      >
                        Evaluate
                      </button>
                    )}
                    {onDispatchRelease && entry.roadmapState === 'pending' && (
                      <button
                        onClick={e => { e.stopPropagation(); onDispatchRelease(entry.repoName); }}
                        disabled={mutatingActionsBlocked}
                        // Release 3.5 milestone 7 — an action that queues
                        // work for an agent does not dress like a read-only
                        // one. Amber border + the consequence in its title.
                        className={`text-xs px-2 py-1 rounded border border-amber-600/70 bg-amber-900/30 text-amber-200 hover:bg-amber-800/50 font-semibold transition-colors${disabledActionClass}`}
                        title={mutatingTitle('DISPATCHES WORK: standardizes the roadmap and queues the next release for an agent. Unlike Audit/Evaluate, this starts something — approval gates still apply downstream.')}
                      >
                        Dispatch Release
                      </button>
                    )}
                    {onViewRoadmap && entry.roadmapState && entry.roadmapState !== 'missing' && (
                      <button
                        onClick={e => { e.stopPropagation(); onViewRoadmap(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-indigo-700/50 bg-indigo-900/40 text-indigo-300 hover:bg-indigo-800/60 transition-colors"
                      >
                        Roadmap
                      </button>
                    )}
                  </div>
                </div>

                {/* Findings panel */}
                {isExpanded && hasFindings && (
                  <div className="border-t border-gray-700 px-4 py-3 bg-gray-900/40">
                    <div className="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">
                      Documentation Findings
                    </div>
                    <div className="space-y-2">
                      {entry.docFindings.map((finding, idx) => (
                        <div
                          key={idx}
                          className={`rounded border px-3 py-2 text-xs ${SEVERITY_BG[finding.severity] ?? SEVERITY_BG['info']}`}
                        >
                          <div className="flex items-start gap-2">
                            <span className={`font-semibold uppercase flex-shrink-0 ${SEVERITY_COLORS[finding.severity] ?? 'text-gray-400'}`}>
                              [{finding.severity}]
                            </span>
                            <div>
                              <div className="text-gray-200 mb-0.5">{finding.message}</div>
                              <div className="text-gray-400">→ {finding.recommendedAction}</div>
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* No results after filter */}
      {!loading && entries.length > 0 && filteredEntries.length === 0 && (
        <div className="text-center py-8 text-gray-500 text-sm">
          No repositories match the current filter.
        </div>
      )}

      {/* Cache info */}
      {auditIndex && (
        <div className="mt-4 text-xs text-gray-600 text-right">
          Audited at {new Date(auditIndex.auditedAt).toLocaleTimeString()} · {auditIndex.cacheSource}
          {auditIndex.cacheAgeSeconds > 0 && ` · ${Math.round(auditIndex.cacheAgeSeconds)}s ago`}
        </div>
      )}
    </div>
  );
};

export default WorkQueueView;

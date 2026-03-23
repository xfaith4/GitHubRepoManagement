import React, { useState, useMemo } from 'react';
import { type DocAuditEntry, type DocAuditIndex, type DispatchReadiness, type RoadmapAuditIndex, type RoadmapMaturityLevel, type RoadmapMaturityFilter } from '../types';
import { SpinnerIcon } from './icons';

interface WorkQueueViewProps {
  auditIndex: DocAuditIndex | null;
  loading: boolean;
  error?: string | null;
  onRefresh: () => void;
  onScan: () => void;
  onViewRoadmap?: (repoName: string) => void;
  onPreviewTask?: (repoName: string, roadmapPath?: string) => void;
  onViewRoadmapAudit?: (repoName: string) => void;
  onRepairRoadmap?: (repoName: string) => void;
  onLintRoadmap?: (repoName: string) => void;
  onStandardizeReadme?: (repoName: string) => void;
  onEvaluateRepo?: (repoName: string) => void;
  onDispatchRelease?: (repoName: string) => void;
  isScanning: boolean;
  roadmapAuditIndex?: RoadmapAuditIndex | null;
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
  'parse-error': {
    label: 'Parse Error',
    badgeClass: 'bg-orange-900/50 text-orange-300 border-orange-700/50',
    dotClass: 'bg-orange-400',
    priority: 5,
  },
  blocked: {
    label: 'Blocked',
    badgeClass: 'bg-red-900/50 text-red-300 border-red-700/50',
    dotClass: 'bg-red-500',
    priority: 6,
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
  onViewRoadmap,
  onPreviewTask,
  onViewRoadmapAudit,
  onRepairRoadmap,
  onLintRoadmap,
  onStandardizeReadme,
  onEvaluateRepo,
  onDispatchRelease,
  isScanning,
  roadmapAuditIndex,
}) => {
  const [readinessFilter, setReadinessFilter] = useState<ReadinessFilter>('all');
  const [maturityFilter, setMaturityFilter] = useState<RoadmapMaturityFilter>('all');
  const [tagFilter, setTagFilter] = useState<string>('all');
  const [expandedRepos, setExpandedRepos] = useState<Set<string>>(new Set());
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

  // Build a lookup for roadmap audit entries by repoName
  const auditByRepo = useMemo(() => {
    const map = new Map<string, import('../types').RoadmapAuditEntry>();
    for (const e of (roadmapAuditIndex?.entries ?? [])) {
      map.set(e.repoName, e);
    }
    return map;
  }, [roadmapAuditIndex]);

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
        const audit = auditByRepo.get(e.repoName);
        return audit?.maturityLevel === maturityFilter;
      });
    }
    if (tagFilter !== 'all') {
      result = result.filter(e => {
        const audit = auditByRepo.get(e.repoName);
        return (audit?.nextPendingItem?.tags ?? []).includes(tagFilter);
      });
    }
    if (filterText.trim()) {
      const lower = filterText.toLowerCase();
      result = result.filter(e =>
        e.repoName.toLowerCase().includes(lower) ||
        (e.nextPendingRoadmapItem ?? '').toLowerCase().includes(lower)
      );
    }
    return result.sort(
      (a, b) =>
        (READINESS_CONFIG[a.dispatchReadiness]?.priority ?? 99) -
        (READINESS_CONFIG[b.dispatchReadiness]?.priority ?? 99)
    );
  }, [entries, readinessFilter, maturityFilter, tagFilter, filterText, auditByRepo]);

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
          <h2 className="text-lg font-semibold text-white">Documentation Audit &amp; Work Queue</h2>
          <p className="text-sm text-gray-400 mt-0.5">
            Per-repo dispatch readiness based on roadmap state and documentation standards.
          </p>
        </div>
        <div className="flex items-center gap-2">
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
            {isScanning ? 'Scanning…' : 'Scan All'}
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-lg border border-red-700/50 bg-red-900/20 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      )}

      {/* Summary strip */}
      {entries.length > 0 && (
        <div className="flex flex-wrap gap-3 mb-4">
          <div className="px-3 py-2 bg-green-900/20 border border-green-700/40 rounded-lg text-sm">
            <span className="text-green-300 font-semibold">{readyCount}</span>
            <span className="text-green-400/80 ml-1.5">ready for dispatch</span>
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
            const isExpanded = expandedRepos.has(entry.repoName);
            const hasFindings = entry.docFindings.length > 0;
            return (
              <div
                key={entry.repoPath || entry.repoName}
                className="border border-gray-700 rounded-lg bg-gray-800/40 overflow-hidden"
              >
                {/* Repo row header */}
                <div
                  className={`flex items-start gap-3 px-4 py-3 ${hasFindings ? 'cursor-pointer hover:bg-gray-700/40' : ''}`}
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
                  <div className="flex-1 min-w-0">
                    <div className="flex flex-wrap items-center gap-2 mb-1">
                      <span className="text-sm font-semibold text-white truncate">{entry.repoName}</span>
                      <ReadinessBadge readiness={entry.dispatchReadiness} />
                      {/* Roadmap maturity badge from contract audit */}
                      {auditByRepo.get(entry.repoName) && (
                        <MaturityMiniBadge level={auditByRepo.get(entry.repoName)!.maturityLevel} />
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

                    {/* Local path */}
                    {entry.repoPath && (
                      <div className="text-xs text-gray-500 truncate mt-0.5" title={entry.repoPath}>
                        {entry.repoPath}
                      </div>
                    )}
                  </div>

                  {/* Action buttons */}
                  <div className="flex-shrink-0 flex items-center gap-1.5">
                    {onPreviewTask && entry.dispatchReadiness === 'ready' && (
                      <button
                        onClick={e => { e.stopPropagation(); onPreviewTask(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-green-700/50 bg-green-900/40 text-green-300 hover:bg-green-800/60 transition-colors"
                        title="Preview Copilot Task Packet"
                      >
                        Preview Task
                      </button>
                    )}
                    {onViewRoadmapAudit && auditByRepo.has(entry.repoName) && (
                      <button
                        onClick={e => { e.stopPropagation(); onViewRoadmapAudit(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-purple-700/50 bg-purple-900/40 text-purple-300 hover:bg-purple-800/60 transition-colors"
                        title="View Roadmap Contract Audit"
                      >
                        Audit
                      </button>
                    )}
                    {onRepairRoadmap && auditByRepo.has(entry.repoName) && ['L0-Absent', 'L1-Informal', 'L2-Structured'].includes(auditByRepo.get(entry.repoName)?.maturityLevel ?? '') && (
                      <button
                        onClick={e => { e.stopPropagation(); onRepairRoadmap(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-orange-700/50 bg-orange-900/40 text-orange-300 hover:bg-orange-800/60 transition-colors"
                        title="Preview Roadmap Repair"
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
                        className="text-xs px-2 py-1 rounded border border-cyan-700/50 bg-cyan-900/40 text-cyan-300 hover:bg-cyan-800/60 transition-colors"
                        title="Standardize README"
                      >
                        Standardize
                      </button>
                    )}
                    {onEvaluateRepo && (
                      <button
                        onClick={e => { e.stopPropagation(); onEvaluateRepo(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-violet-700/50 bg-violet-900/40 text-violet-300 hover:bg-violet-800/60 transition-colors"
                        title="Evaluate repo structure and get hardening suggestions"
                      >
                        Evaluate
                      </button>
                    )}
                    {onDispatchRelease && entry.roadmapState === 'pending' && (
                      <button
                        onClick={e => { e.stopPropagation(); onDispatchRelease(entry.repoName); }}
                        className="text-xs px-2 py-1 rounded border border-blue-700/50 bg-blue-900/40 text-blue-300 hover:bg-blue-800/60 transition-colors"
                        title="Standardize roadmap and dispatch next release to GitHub Copilot"
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

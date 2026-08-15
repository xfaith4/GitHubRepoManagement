import React, { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import { type RepoStatus, type DispatchReadiness, type RepoCurationState, type PortfolioAssessmentScanSummary } from '../types';
import { BuildSuccessIcon, BuildFailureIcon, BuildInProgressIcon, PullRequestIcon, NoBuildsIcon, ChevronDownIcon, ChevronRightIcon } from './icons';
import { isRepoNeedsAttention } from '../lib/needsAttention';
import { getCurationBadgeConfig, getCurationRank, matchesCurationFilters } from '../lib/curationScope';

interface RepoGridProps {
  repos: RepoStatus[];
  onViewArtifacts: (repoName: string) => void;
  onViewRoadmap?: (repoName: string) => void;
  onViewGitStatus?: (repoName: string, localPath?: string) => void;
  onRunRepoAction?: (operation: 'update' | 'sync', repoId: string) => void;
  onOpenDocReview?: (repoName: string) => void;
  onRunRoadmapScan?: (repoName: string) => void;
  dataSource:
    | { source: 'sample' }
    | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null }
    | { source: 'github'; username: string }
    | null;
  selectedRepos: Set<string>;
  setSelectedRepos: React.Dispatch<React.SetStateAction<Set<string>>>;
  groupBy: 'none' | 'status' | 'needsAttention' | 'isStale' | 'lastBuildStatus' | 'roadmapStatus';
  setGroupBy: React.Dispatch<React.SetStateAction<'none' | 'status' | 'needsAttention' | 'isStale' | 'lastBuildStatus' | 'roadmapStatus'>>;
  scanSummary?: PortfolioAssessmentScanSummary | null;
  scanGeneratedAt?: string;
  onRefreshAll?: () => void | Promise<unknown>;
  refreshAllInProgress?: boolean;
  onSetCuration?: (repo: RepoStatus, state: RepoCurationState) => Promise<void>;
}

type SortKey = 'priority' | 'name' | 'status' | 'branch' | 'lastCommitDate' | 'uncommittedChanges' | 'lastBuildStatus' | 'isStale' | 'openPrCount' | 'needsAttention';
type SortOrder = 'asc' | 'desc';

type DuplicateGroup = { groupKey: string; items: RepoStatus[] };
type QuickFilter = 'favoritesOnly' | 'candidatesOnly' | 'hideIgnored' | 'hideExcluded' | 'dirtyOnly' | 'hasUncommitted' | 'staleOnly' | 'needsAttention' | 'hasOpenPrs' | 'buildProblem' | 'roadmapFlagged' | 'duplicates';

const DEFAULT_QUICK_FILTERS: Record<QuickFilter, boolean> = {
  favoritesOnly: false,
  candidatesOnly: false,
  // Archived/Ignore exists to suppress repos the operator has parked, so the
  // default view honors it; the active chip keeps the suppression visible.
  hideIgnored: true,
  // Release 3.5 milestone 3 -- out-of-scope repos (temp dirs, Archive/ trees,
  // vendored clones) are hidden from the working portfolio by default, and
  // NEVER dropped: this chip is the toggle that reveals them, so the
  // suppression stays visible and reversible.
  hideExcluded: true,
  dirtyOnly: false,
  hasUncommitted: false,
  staleOnly: false,
  needsAttention: false,
  hasOpenPrs: false,
  buildProblem: false,
  roadmapFlagged: false,
  duplicates: false,
};

// Progressive disclosure (Release 2.6 Phase 3): show only the most-used triage
// filters by default; the rest collapse behind an "Advanced filters" toggle so
// the grid presents a small default control set instead of eleven chips.
// Each tuple is [key, label, hover definition] — the definition (Release 2.6
// Phase 4) makes every chip self-explanatory without a separate legend lookup.
const PRIMARY_QUICK_FILTERS: Array<[QuickFilter, string, string]> = [
  ['dirtyOnly', 'Dirty only', 'Show only repos with a dirty working tree (uncommitted or untracked changes).'],
  ['needsAttention', 'Needs attention', 'Show only repos with an actionable problem: uncommitted changes, a failing build, a blocked/parse-error dispatch state, or an unparseable roadmap.'],
  ['hasOpenPrs', 'Has open PRs', 'Show only repos with at least one open pull request.'],
];
const ADVANCED_QUICK_FILTERS: Array<[QuickFilter, string, string]> = [
  ['favoritesOnly', '★ Favorites', 'Show only repos you have marked as favorites (operator curation).'],
  ['candidatesOnly', '◆ Candidates', 'Show only repos marked as portfolio candidates (being evaluated for active work).'],
  ['hideIgnored', 'Hide ignored', 'Hide repos you have parked as archived/ignore.'],
  ['hideExcluded', 'Hide out-of-scope', 'Hide repos the scope policy excludes from portfolio math: temp/compare folders, Archive/ trees, worktree containers, and vendored third-party clones. Toggle off to see them - they are classified, never deleted.'],
  ['hasUncommitted', 'Has uncommitted changes', 'Show only repos with uncommitted changes in the working tree.'],
  ['staleOnly', 'Stale', 'Show only repos whose local default branch is behind its remote. Staleness is remote drift computed by the scan (Release 3.1) — not commit age.'],
  ['buildProblem', 'No builds / failed builds', 'Show only repos whose latest CI run failed or that have no CI configured.'],
  ['roadmapFlagged', 'ROADMAP flagged', 'Show only repos whose ROADMAP is missing, unparseable, or needs repair.'],
  ['duplicates', 'Duplicates', 'Show only repos detected as duplicates of another entry (same identity).'],
];

type GroupByOption = RepoGridProps['groupBy'];

type RoadmapBadgeState = 'pending' | 'complete' | 'parse-error' | undefined;

function getRoadmapBadgeConfig(state: RoadmapBadgeState): { className: string; label: string; title: string } {
  switch (state) {
    case 'complete':
      return {
        className: 'bg-green-900/50 text-green-300 border-green-700/50 hover:bg-green-800/60 hover:text-green-100',
        label: 'ROADMAP ✓',
        title: 'Roadmap complete — no pending items',
      };
    case 'parse-error':
      return {
        className: 'bg-orange-900/50 text-orange-300 border-orange-700/50 hover:bg-orange-800/60 hover:text-orange-100',
        label: 'ROADMAP !',
        title: 'Roadmap found but could not be parsed',
      };
    default:
      return {
        className: 'bg-indigo-900/50 text-indigo-300 border-indigo-700/50 hover:bg-indigo-800/60 hover:text-indigo-100',
        label: 'ROADMAP',
        title: 'View ROADMAP',
      };
  }
}

function getChangeStateBadgeConfig(state?: RepoStatus['changeState']): { className: string; label: string } | null {
  switch (state) {
    case 'unchanged':
      return {
        className: 'bg-emerald-900/30 text-emerald-300 border-emerald-700/40',
        label: 'Index: Reused',
      };
    case 'new-commits':
      return {
        className: 'bg-cyan-900/30 text-cyan-300 border-cyan-700/40',
        label: 'Index: New Commits',
      };
    case 'metadata-changed':
      return {
        className: 'bg-amber-900/30 text-amber-300 border-amber-700/40',
        label: 'Index: Metadata Changed',
      };
    case 'needs-rescan':
      return {
        className: 'bg-violet-900/30 text-violet-300 border-violet-700/40',
        label: 'Index: Rescanned',
      };
    case 'scan-failed':
      return {
        className: 'bg-rose-900/30 text-rose-300 border-rose-700/40',
        label: 'Index: Scan Failed',
      };
    default:
      return null;
  }
}

// Priority ordering used by the default sort: curated repos first, then
// recently changed repos, then the unchanged long tail; archived last.
function getPrioritySortValue(repo: RepoStatus): string {
  const curationRank = getCurationRank(repo.curationState);
  const changed =
    repo.changeState === 'new-commits' ||
    repo.changeState === 'metadata-changed' ||
    repo.changeState === 'needs-rescan' ||
    repo.changeState === 'scan-failed';
  const changeRank = changed ? 0 : 1;
  return `${curationRank}${changeRank}:${repo.name.toLowerCase()}`;
}

function formatScanDecisionReason(reason?: RepoStatus['scanDecisionReason']): string {
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

function toShortSha(value?: string | null): string {
  if (!value) {
    return 'n/a';
  }
  return value.length > 8 ? value.slice(0, 8) : value;
}

function buildScanDecisionTooltip(repo: RepoStatus): string {
  const lines = [
    `Decision: ${formatScanDecisionReason(repo.scanDecisionReason)}`,
    `Head: ${toShortSha(repo.headCommitSha)}`,
    `Indexed: ${toShortSha(repo.lastIndexedCommitSha)}`,
  ];

  if (repo.lastScanStatus) {
    lines.push(`Scan status: ${repo.lastScanStatus}`);
  }

  if (repo.lastScanError) {
    lines.push(`Error: ${repo.lastScanError}`);
  }

  return lines.join('\n');
}

const RepoGrid = ({ repos, onViewArtifacts, onViewRoadmap, onViewGitStatus, onRunRepoAction, onOpenDocReview, onRunRoadmapScan, dataSource, selectedRepos, setSelectedRepos, groupBy, setGroupBy, scanSummary, scanGeneratedAt, onRefreshAll, refreshAllInProgress, onSetCuration }: RepoGridProps) => {
  const [sortKey, setSortKey] = useState<SortKey>('priority');
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc');
  const [search, setSearch] = useState('');
  const [readinessFilter, setReadinessFilter] = useState<DispatchReadiness | 'all'>('all');
  const [quickFilters, setQuickFilters] = useState<Record<QuickFilter, boolean>>({ ...DEFAULT_QUICK_FILTERS });
  const [legendOpen, setLegendOpen] = useState(false);
  const [advancedFiltersOpen, setAdvancedFiltersOpen] = useState(false);
  const [refreshAllConfirmOpen, setRefreshAllConfirmOpen] = useState(false);
  const [curationPendingRepoId, setCurationPendingRepoId] = useState<string | null>(null);
  const [curationError, setCurationError] = useState<string | null>(null);
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set());
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [duplicateWarningExpanded, setDuplicateWarningExpanded] = useState(false);
  const [pageSize, setPageSize] = useState<25 | 50 | 100>(50);
  const [pageIndex, setPageIndex] = useState(1);
  const selectAllCheckboxRef = useRef<HTMLInputElement>(null);
  const getRepoSelectionId = useCallback(
    (repo: RepoStatus) => repo.localPath ?? `${repo.name}::${repo.branch}`,
    []
  );

  const uniqueRepos = useMemo(() => {
    const byPath = new Map<string, RepoStatus>();
    for (const repo of repos) {
      const key = repo.localPath ? repo.localPath.toLowerCase() : `${repo.name.toLowerCase()}::${repo.branch.toLowerCase()}`;
      if (!byPath.has(key)) {
        byPath.set(key, repo);
      }
    }
    return Array.from(byPath.values());
  }, [repos]);

  const duplicateLocalRepoGroups = useMemo<DuplicateGroup[]>(() => {
    const groups = new Map<string, RepoStatus[]>();
    for (const repo of uniqueRepos) {
      if (!repo.localPath) {
        continue;
      }
      const groupKey = repo.originUrl?.trim().toLowerCase() || repo.name.trim().toLowerCase();
      if (!groups.has(groupKey)) {
        groups.set(groupKey, []);
      }
      groups.get(groupKey)!.push(repo);
    }

    return Array.from(groups.entries())
      .map(([groupKey, items]) => ({ groupKey, items }))
      .filter(group => group.items.length > 1)
      .sort((left, right) => right.items.length - left.items.length);
  }, [uniqueRepos]);

  const duplicateRepoIds = useMemo(() => {
    const ids = new Set<string>();
    duplicateLocalRepoGroups.forEach(group => {
      group.items.forEach(item => ids.add(getRepoSelectionId(item)));
    });
    return ids;
  }, [duplicateLocalRepoGroups, getRepoSelectionId]);

  const isRoadmapFlagged = (repo: RepoStatus) => {
    const roadmapState = repo.roadmapState ?? 'missing';
    return roadmapState === 'missing' || roadmapState === 'pending' || roadmapState === 'parse-error' ||
      repo.dispatchReadiness === 'missing-roadmap' ||
      repo.dispatchReadiness === 'needs-doc-standardization' ||
      repo.dispatchReadiness === 'parse-error' ||
      repo.dispatchReadiness === 'blocked';
  };

  // Acute-problem definition — shared pure module keeps this in sync with the
  // Dashboard summary's "Needs Attention" metric (Release 2.6 Phase 1 / 2.7 Ph D).
  const isNeedsAttention = (repo: RepoStatus) => isRepoNeedsAttention(repo);

  const filteredAndSortedRepos = useMemo(() => {
    const searchLower = search.trim().toLowerCase();

    const filtered = uniqueRepos.filter(repo => {
      const repoId = getRepoSelectionId(repo);
      const matchesSearch =
        searchLower.length === 0 ||
        repo.name.toLowerCase().includes(searchLower) ||
        (repo.localPath?.toLowerCase().includes(searchLower) ?? false) ||
        (repo.owner?.toLowerCase().includes(searchLower) ?? false) ||
        (repo.originUrl?.toLowerCase().includes(searchLower) ?? false);

      const matchesReadiness = readinessFilter === 'all' || repo.dispatchReadiness === readinessFilter;
      const matchesDirtyOnly = !quickFilters.dirtyOnly || repo.status === 'dirty';
      const matchesUncommitted = !quickFilters.hasUncommitted || repo.uncommittedChanges > 0;
      const matchesStale = !quickFilters.staleOnly || repo.isStale;
      const matchesAttention = !quickFilters.needsAttention || isNeedsAttention(repo);
      const matchesOpenPrs = !quickFilters.hasOpenPrs || (repo.openPrCount ?? 0) > 0;
      const matchesBuildProblem = !quickFilters.buildProblem || !repo.lastBuildStatus || repo.lastBuildStatus === 'none' || repo.lastBuildStatus === 'failure';
      const matchesRoadmapFlag = !quickFilters.roadmapFlagged || isRoadmapFlagged(repo);
      const matchesDuplicates = !quickFilters.duplicates || duplicateRepoIds.has(repoId);
      const matchesCuration = matchesCurationFilters(repo.curationState, quickFilters);
      // Scope: absent classification (older cached payloads) reads in-scope --
      // a missing policy must not shrink the portfolio.
      const matchesScope = !quickFilters.hideExcluded || repo.scope?.inScope !== false;

      return matchesSearch && matchesReadiness && matchesDirtyOnly && matchesUncommitted && matchesStale && matchesAttention && matchesOpenPrs && matchesBuildProblem && matchesRoadmapFlag && matchesDuplicates && matchesCuration && matchesScope;
    });

    const valueForSort = (repo: RepoStatus): string | number => {
      switch (sortKey) {
        case 'priority':
          return getPrioritySortValue(repo);
        case 'name':
          return repo.name;
        case 'status':
          return repo.status;
        case 'branch':
          return repo.branch;
        case 'lastCommitDate':
          return new Date(repo.lastCommitDate).getTime() || 0;
        case 'uncommittedChanges':
          return Number(repo.uncommittedChanges ?? 0);
        case 'lastBuildStatus':
          return repo.lastBuildStatus ?? 'none';
        case 'isStale':
          return repo.isStale ? 1 : 0;
        case 'openPrCount':
          return Number(repo.openPrCount ?? 0);
        case 'needsAttention':
          return isNeedsAttention(repo) ? 1 : 0;
        default:
          return repo.name;
      }
    };

    return filtered.sort((left, right) => {
      const leftValue = valueForSort(left);
      const rightValue = valueForSort(right);

      if (typeof leftValue === 'number' && typeof rightValue === 'number') {
        return sortOrder === 'asc' ? leftValue - rightValue : rightValue - leftValue;
      }

      const leftString = String(leftValue);
      const rightString = String(rightValue);
      return sortOrder === 'asc' ? leftString.localeCompare(rightString) : rightString.localeCompare(leftString);
    });
  }, [duplicateRepoIds, getRepoSelectionId, isNeedsAttention, isRoadmapFlagged, quickFilters, readinessFilter, search, sortKey, sortOrder, uniqueRepos]);

  useEffect(() => {
    setPageIndex(1);
  }, [search, readinessFilter, quickFilters, sortKey, sortOrder, groupBy, pageSize]);

  const totalPages = Math.max(1, Math.ceil(filteredAndSortedRepos.length / pageSize));
  const clampedPage = Math.min(pageIndex, totalPages);

  const pagedRepos = useMemo(() => {
    const start = (clampedPage - 1) * pageSize;
    return filteredAndSortedRepos.slice(start, start + pageSize);
  }, [clampedPage, filteredAndSortedRepos, pageSize]);

  const groupedRepos = useMemo((): Record<string, RepoStatus[]> => {
    const resolveGroup = (repo: RepoStatus): string => {
      switch (groupBy) {
        case 'status':
          return repo.status;
        case 'needsAttention':
          return isNeedsAttention(repo) ? 'Needs attention' : 'No attention needed';
        case 'isStale':
          return repo.isStale ? 'Stale repositories' : 'Current repositories';
        case 'lastBuildStatus':
          return repo.lastBuildStatus === 'failure' ? 'Failed builds' :
            repo.lastBuildStatus === 'success' ? 'Successful builds' :
            repo.lastBuildStatus === 'in_progress' ? 'Builds in progress' : 'No builds';
        case 'roadmapStatus':
          return repo.roadmapState === 'pending' ? 'ROADMAP pending' :
            repo.roadmapState === 'parse-error' ? 'ROADMAP parse errors' :
            repo.roadmapState === 'complete' ? 'ROADMAP complete' : 'No ROADMAP';
        default:
          return 'All repositories';
      }
    };

    if (groupBy === 'none') {
      return { 'All repositories': pagedRepos };
    }

    return pagedRepos.reduce((acc, repo) => {
      const key = resolveGroup(repo);
      if (!acc[key]) {
        acc[key] = [];
      }
      acc[key].push(repo);
      return acc;
    }, {} as Record<string, RepoStatus[]>);
  }, [groupBy, isNeedsAttention, pagedRepos]);

  useEffect(() => {
    if (groupBy === 'needsAttention') {
      setCollapsedGroups(new Set(['No attention needed']));
      return;
    }
    setCollapsedGroups(new Set());
  }, [groupBy]);

  useEffect(() => {
    if (selectAllCheckboxRef.current) {
        const visibleRepoIds = new Set(pagedRepos.map((r: RepoStatus) => getRepoSelectionId(r)));
        const selectedVisible = Array.from(selectedRepos).filter(id => visibleRepoIds.has(id));

        if (selectedVisible.length === 0) {
            selectAllCheckboxRef.current.checked = false;
            selectAllCheckboxRef.current.indeterminate = false;
        } else if (selectedVisible.length === visibleRepoIds.size) {
            selectAllCheckboxRef.current.checked = true;
            selectAllCheckboxRef.current.indeterminate = false;
        } else {
            selectAllCheckboxRef.current.checked = false;
            selectAllCheckboxRef.current.indeterminate = true;
        }
    }
  }, [selectedRepos, pagedRepos, getRepoSelectionId]);


  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortOrder(prev => (prev === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortOrder('asc');
    }
  };

  const handleSelectAll = (e: React.ChangeEvent<HTMLInputElement>) => {
    const isChecked = e.target.checked;
    setSelectedRepos(prevSelected => {
        const newSelected = new Set(prevSelected);
        pagedRepos.forEach(repo => {
            const repoId = getRepoSelectionId(repo);
            if (isChecked) {
                newSelected.add(repoId);
            } else {
                newSelected.delete(repoId);
            }
        });
        return newSelected;
    });
  };

  const handleSelectRepo = (repoId: string) => {
    setSelectedRepos(prev => {
        const newSet = new Set(prev);
        if (newSet.has(repoId)) {
            newSet.delete(repoId);
        } else {
            newSet.add(repoId);
        }
        return newSet;
    });
  };

  const toggleGroup = (groupKey: string) => {
    setCollapsedGroups(prev => {
        const newSet = new Set(prev);
        if (newSet.has(groupKey)) {
            newSet.delete(groupKey);
        } else {
            newSet.add(groupKey);
        }
        return newSet;
    });
  };

  const toggleExpandedRow = (repoId: string) => {
    setExpandedRows(prev => {
      const next = new Set(prev);
      if (next.has(repoId)) {
        next.delete(repoId);
      } else {
        next.add(repoId);
      }
      return next;
    });
  };

  const toggleQuickFilter = (filterName: QuickFilter) => {
    setQuickFilters(prev => ({ ...prev, [filterName]: !prev[filterName] }));
  };

  const handleCurationClick = async (repo: RepoStatus, state: RepoCurationState) => {
    if (!onSetCuration) return;
    const selectionId = getRepoSelectionId(repo);
    setCurationPendingRepoId(selectionId);
    setCurationError(null);
    try {
      await onSetCuration(repo, state);
    } catch (err) {
      setCurationError(`${repo.name}: ${err instanceof Error ? err.message : 'Curation update failed.'}`);
    } finally {
      setCurationPendingRepoId(null);
    }
  };

  const sortIndicator = (key: SortKey) => {
    if (sortKey !== key) {
      return <span className="text-gray-500">⇅</span>;
    }
    return <span className="text-blue-300">{sortOrder === 'asc' ? '↑' : '↓'}</span>;
  };

  const getChangeSeverity = (uncommittedChanges: number) => {
    if (uncommittedChanges >= 1000) {
      return { label: 'Critical', className: 'border-red-500/70 bg-red-900/40 text-red-100' };
    }
    if (uncommittedChanges >= 101) {
      return { label: 'High', className: 'border-orange-500/70 bg-orange-900/40 text-orange-100' };
    }
    if (uncommittedChanges >= 11) {
      return { label: 'Medium', className: 'border-yellow-500/70 bg-yellow-900/40 text-yellow-100' };
    }
    return { label: 'Low', className: 'border-emerald-500/70 bg-emerald-900/40 text-emerald-100' };
  };

  const getStatusBadge = (status: RepoStatus['status'], repo: RepoStatus) => {
    const statusMap: Record<RepoStatus['status'], { text: string; color: string }> = {
      clean: { text: "Clean", color: "bg-green-800 text-green-200" },
      dirty: { text: "Dirty", color: "bg-yellow-800 text-yellow-200" },
      ahead: { text: "Ahead", color: "bg-blue-800 text-blue-200" },
      behind: { text: "Behind", color: "bg-purple-800 text-purple-200" },
      diverged: { text: "Diverged", color: "bg-red-800 text-red-200" },
    };
    const { text, color } = statusMap[status] || { text: 'Unknown', color: 'bg-gray-700 text-gray-300' };
    if (onViewGitStatus && status !== 'clean') {
      return (
        <button
          onClick={e => { e.stopPropagation(); onViewGitStatus(repo.name, repo.localPath ?? undefined); }}
          className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${color} hover:opacity-80 cursor-pointer transition-opacity`}
          title="Click to see what changed"
        >
          {text}
        </button>
      );
    }
    return <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${color}`}>{text}</span>;
  }

  const getBuildStatusBadge = (repo: RepoStatus) => {
    let icon, color, text;
    switch (repo.lastBuildStatus) {
        case 'success':
            icon = <BuildSuccessIcon className="w-4 h-4" />;
            color = 'text-green-400';
            text = 'Success';
            break;
        case 'failure':
            icon = <BuildFailureIcon className="w-4 h-4" />;
            color = 'text-red-400';
            text = 'Failure';
            break;
        case 'in_progress':
            icon = <BuildInProgressIcon className="w-4 h-4 animate-spin" />;
            color = 'text-blue-400';
            text = 'In Progress';
            break;
        default:
            icon = <NoBuildsIcon className="w-4 h-4" />;
            color = 'text-gray-500';
            text = 'No Builds';
    }
    const badge = <div className={`flex items-center gap-2 ${color}`}>{icon}<span className="hidden sm:inline">{text}</span></div>;
    return repo.lastBuildUrl ? <a href={repo.lastBuildUrl} target="_blank" rel="noopener noreferrer" title="View last build on GitHub" className="hover:opacity-80 transition-opacity">{badge}</a> : badge;
  };

    const groupByOptions: { value: GroupByOption; label: string }[] = [
      { value: 'none', label: 'None' },
      { value: 'status', label: 'Status' },
      { value: 'needsAttention', label: 'Needs Attention' },
      { value: 'isStale', label: 'Is Stale' },
      { value: 'lastBuildStatus', label: 'Build Status' },
      { value: 'roadmapStatus', label: 'Roadmap Status' },
  ];

  const readinessFilterOptions: { value: DispatchReadiness | 'all'; label: string }[] = [
    { value: 'all', label: 'All' },
    { value: 'ready', label: 'Ready' },
    { value: 'needs-doc-standardization', label: 'Needs Docs' },
    { value: 'missing-roadmap', label: 'No Roadmap' },
    { value: 'roadmap-complete', label: 'Roadmap Complete' },
    { value: 'parse-error', label: 'Parse Error' },
    { value: 'blocked', label: 'Blocked' },
  ];

  const hasReadinessData = repos.some(r => r.dispatchReadiness !== undefined);
  const activeQuickFilterCount = Object.values(quickFilters).filter(Boolean).length;

  // Shared between the desktop table's expanded row and the mobile card's
  // details section.
  const renderRepoDetailBlocks = (repo: RepoStatus) => {
    const pagesUrl = repo.pagesUrl;
    const artifactDetails = typeof repo.artifactCount === 'number' ? repo.artifactCount : null;
    const repoSizeMb = typeof repo.repoSizeKb === 'number' ? (repo.repoSizeKb / 1024) : null;
    const testingWorkflowCount = repo.testingWorkflowCount ?? null;
    const workflowCount = repo.actionsWorkflowCount ?? null;
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3 text-xs text-gray-300">
        <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
          <div className="text-gray-500">Local Path</div>
          <div className="mt-1 break-all">{repo.localPath ?? 'N/A'}</div>
        </div>
        <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
          <div className="text-gray-500">Origin URL</div>
          <div className="mt-1 break-all">{repo.originUrl ?? 'N/A'}</div>
        </div>
        <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
          <div className="text-gray-500">Artifacts / Size</div>
          <div className="mt-1">{artifactDetails ?? 0} artifacts{repoSizeMb !== null ? ` · ${repoSizeMb.toFixed(1)} MB` : ''}</div>
        </div>
        <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
          <div className="text-gray-500">Pages</div>
          <div className="mt-1 break-all">
            {pagesUrl ? (
              <a href={pagesUrl} target="_blank" rel="noopener noreferrer" className="text-emerald-300 hover:text-emerald-200 hover:underline">{pagesUrl}</a>
            ) : 'Not configured'}
          </div>
        </div>
        <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
          <div className="text-gray-500">Workflows</div>
          <div className="mt-1">{workflowCount ?? 0} total{testingWorkflowCount !== null ? ` · ${testingWorkflowCount} testing` : ''}</div>
        </div>
        <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
          <div className="text-gray-500">Artifacts</div>
          <div className="mt-1 flex items-center gap-2">
            {repo.hasArtifacts ? (
              <button onClick={() => onViewArtifacts(repo.name)} className="text-blue-300 hover:text-blue-200 underline underline-offset-2">View artifacts</button>
            ) : (
              <span className="text-gray-500">No artifacts</span>
            )}
          </div>
        </div>
        {(repo.changeState || repo.scanDecisionReason) && (
          <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2">
            <div className="text-gray-500">Scan Decision</div>
            <div className="mt-1 space-y-0.5">
              <div>{formatScanDecisionReason(repo.scanDecisionReason)}</div>
              <div className="text-gray-500">Head {toShortSha(repo.headCommitSha)} · Indexed {toShortSha(repo.lastIndexedCommitSha)}{repo.lastScanStatus ? ` · ${repo.lastScanStatus}` : ''}</div>
              {repo.lastScanError && <div className="text-rose-300 break-all">{repo.lastScanError}</div>}
            </div>
          </div>
        )}
        {onSetCuration && (
          <div className="rounded border border-gray-700 bg-gray-900/70 px-3 py-2 md:col-span-2 xl:col-span-3">
            <div className="text-gray-500">Curation</div>
            <div className="mt-1.5 flex flex-wrap items-center gap-2">
              {(
                [
                  ['favorite', '★ Favorite'],
                  ['portfolio-candidate', '◆ Candidate'],
                  ['archived-ignore', '⊘ Ignore'],
                  ['none', 'Clear'],
                ] as Array<[RepoCurationState, string]>
              ).map(([state, label]) => {
                const isActive = (repo.curationState ?? 'none') === state;
                const isPending = curationPendingRepoId === getRepoSelectionId(repo);
                return (
                  <button
                    key={state}
                    onClick={() => { void handleCurationClick(repo, state); }}
                    disabled={isPending || isActive}
                    title={isActive ? 'This repository is already in this curation state.' : isPending ? 'A curation change is already being saved for this repository.' : `Set curation state to ${label}.`}
                    className={`min-h-9 px-2.5 py-1.5 text-xs rounded border transition-colors disabled:opacity-60 ${isActive
                      ? 'border-blue-500/70 bg-blue-900/50 text-blue-100'
                      : 'border-gray-600 bg-gray-800/60 text-gray-200 hover:bg-gray-700/60'}`}
                  >
                    {label}{isActive ? ' ✓' : ''}
                  </button>
                );
              })}
              <span className="text-gray-500">
                Persists across restarts without rescanning. Favorites sort first; ignored repos are hidden by the "Hide ignored" filter.
              </span>
            </div>
            {curationError && curationError.startsWith(`${repo.name}:`) && (
              <div className="mt-1.5 text-xs text-rose-300">{curationError}</div>
            )}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-4">
       {duplicateLocalRepoGroups.length > 0 && (
        <div className="mb-4 rounded-lg border border-yellow-700/60 bg-yellow-900/20 px-4 py-3 text-sm text-yellow-100">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div className="font-semibold">{duplicateLocalRepoGroups.length} duplicate repository set{duplicateLocalRepoGroups.length === 1 ? '' : 's'} found</div>
            <button
              className="text-xs underline underline-offset-2 text-yellow-200 hover:text-yellow-100"
              onClick={() => setDuplicateWarningExpanded(prev => !prev)}
            >
              {duplicateWarningExpanded ? 'Hide details' : 'Show details'}
            </button>
          </div>
          {duplicateWarningExpanded && (
            <ul className="space-y-2 mt-2">
              {duplicateLocalRepoGroups.slice(0, 10).map((group: DuplicateGroup) => (
                <li key={group.groupKey}>
                  <div className="font-medium">{group.items[0].name} ({group.items.length} copies)</div>
                  <div className="text-xs text-yellow-200/90">
                    {group.items.map((item: RepoStatus) => item.localPath).filter(Boolean).join(' | ')}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
       )}
       <div className="mb-4 flex flex-wrap gap-4">
        <div className="flex flex-col gap-2 min-w-[260px]">
          <input
              type="text"
              placeholder="Search repositories, paths, owners..."
              value={search}
              onChange={(e: React.ChangeEvent<HTMLInputElement>) => setSearch(e.target.value)}
              className="block w-full bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
          />
          <div className="text-xs text-gray-400">
            Showing <strong>{filteredAndSortedRepos.length}</strong> of <strong>{uniqueRepos.length}</strong> repositories
            {activeQuickFilterCount > 0 ? ` · ${activeQuickFilterCount} quick filter${activeQuickFilterCount === 1 ? '' : 's'} active` : ''}
            {sortKey === 'priority' ? ' · priority order: favorites → candidates → recently changed → unchanged' : ''}
          </div>
          {scanSummary && (
            <div className="text-xs text-gray-500" title="Change-aware indexing: unchanged repositories are reused from the persisted index instead of being rescanned.">
              Last scan: <span className="text-emerald-400">{scanSummary.reused} reused</span>
              {' · '}<span className="text-cyan-400">{scanSummary.reindexed} reindexed</span>
              {scanSummary.failed > 0 ? <>{' · '}<span className="text-rose-400">{scanSummary.failed} failed</span></> : ''}
              {` · ${(scanSummary.durationMs / 1000).toFixed(1)}s`}
              {scanGeneratedAt ? ` · ${new Date(scanGeneratedAt).toLocaleTimeString()}` : ''}
            </div>
          )}
        </div>
        <div className="flex items-center gap-2">
            <label htmlFor="group-by" className="text-sm font-medium text-gray-300">Group By:</label>
            <select
                id="group-by"
                value={groupBy}
              onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setGroupBy(e.target.value as GroupByOption)}
                className="block w-full max-w-xs bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 pl-3 pr-8 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
                {groupByOptions.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
            </select>
        </div>
        {hasReadinessData && (
          <div className="flex items-center gap-2">
            <label htmlFor="readiness-filter" className="text-sm font-medium text-gray-300">Readiness:</label>
            <select
              id="readiness-filter"
              value={readinessFilter}
              onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setReadinessFilter(e.target.value as DispatchReadiness | 'all')}
              className="block w-full max-w-xs bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 pl-3 pr-8 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
              {readinessFilterOptions.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
            </select>
          </div>
        )}

        <div className="flex items-center gap-2">
          <label htmlFor="page-size" className="text-sm font-medium text-gray-300">Rows:</label>
          <select
            id="page-size"
            value={pageSize}
            onChange={(e: React.ChangeEvent<HTMLSelectElement>) => setPageSize(Number(e.target.value) as 25 | 50 | 100)}
            className="bg-gray-900 border border-gray-600 rounded-md py-2 pl-3 pr-8 text-white text-sm"
          >
            <option value={25}>25</option>
            <option value={50}>50</option>
            <option value={100}>100</option>
          </select>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setPageIndex(prev => Math.max(1, prev - 1))}
            disabled={clampedPage <= 1}
            title={clampedPage <= 1 ? 'You are on the first page.' : 'Go to the previous page.'}
            className="px-2.5 py-2 rounded border border-gray-600 bg-gray-900 text-xs text-gray-200 disabled:opacity-50"
          >
            Prev
          </button>
          <span className="text-xs text-gray-400">Page {clampedPage} / {totalPages}</span>
          <button
            onClick={() => setPageIndex(prev => Math.min(totalPages, prev + 1))}
            disabled={clampedPage >= totalPages}
            title={clampedPage >= totalPages ? 'You are on the last page.' : 'Go to the next page.'}
            className="px-2.5 py-2 rounded border border-gray-600 bg-gray-900 text-xs text-gray-200 disabled:opacity-50"
          >
            Next
          </button>
        </div>

        {onRefreshAll && (
          <div className="flex items-center gap-2 ml-auto">
            {refreshAllConfirmOpen && !refreshAllInProgress ? (
              <>
                <span className="text-xs text-amber-300">Force a full rescan of every repository? Cached rows are ignored.</span>
                <button
                  onClick={() => { setRefreshAllConfirmOpen(false); void onRefreshAll(); }}
                  className="px-2.5 py-2 rounded border border-amber-600/70 bg-amber-900/40 text-xs text-amber-100 hover:bg-amber-800/50"
                >
                  Confirm full rescan
                </button>
                <button
                  onClick={() => setRefreshAllConfirmOpen(false)}
                  className="px-2.5 py-2 rounded border border-gray-600 bg-gray-900 text-xs text-gray-300 hover:bg-gray-800"
                >
                  Cancel
                </button>
              </>
            ) : (
              <button
                onClick={() => setRefreshAllConfirmOpen(true)}
                disabled={Boolean(refreshAllInProgress)}
                className="px-2.5 py-2 rounded border border-gray-600 bg-gray-900 text-xs text-gray-200 hover:bg-gray-800 disabled:opacity-50"
                title="Ordinary loads reuse unchanged repositories from the index. Refresh All bypasses that and fully reindexes everything."
              >
                {refreshAllInProgress ? 'Refreshing all…' : 'Refresh All'}
              </button>
            )}
          </div>
        )}
      </div>

      {(() => {
        const chipClass = (key: QuickFilter) =>
          `px-2.5 py-1.5 text-xs rounded-full border transition-colors ${quickFilters[key]
            ? 'border-blue-500/60 bg-blue-900/40 text-blue-100'
            : 'border-gray-600 bg-gray-800/40 text-gray-300 hover:bg-gray-700/50'}`;
        const renderChip = ([key, label, definition]: [QuickFilter, string, string]) => (
          <button key={key} onClick={() => toggleQuickFilter(key)} className={chipClass(key)} title={definition}>
            {label}
          </button>
        );
        // Count advanced filters the operator has changed from their default so
        // an active-but-hidden filter is never invisible while collapsed.
        const advancedActiveCount = ADVANCED_QUICK_FILTERS.filter(
          ([key]) => quickFilters[key] !== DEFAULT_QUICK_FILTERS[key],
        ).length;
        return (
          <>
            <div className="mb-3 flex flex-wrap items-center gap-2">
              {PRIMARY_QUICK_FILTERS.map(renderChip)}
              <button
                data-testid="advanced-filters-toggle"
                onClick={() => setAdvancedFiltersOpen(prev => !prev)}
                aria-expanded={advancedFiltersOpen}
                className={`px-2.5 py-1.5 text-xs rounded-full border transition-colors inline-flex items-center gap-1.5 ${advancedFiltersOpen || advancedActiveCount > 0
                  ? 'border-blue-500/60 bg-blue-900/40 text-blue-100'
                  : 'border-gray-600 bg-gray-800/40 text-gray-300 hover:bg-gray-700/50'}`}
                title="Show or hide the full set of secondary filters"
              >
                <span>{advancedFiltersOpen ? 'Hide advanced filters' : 'Advanced filters'}</span>
                {advancedActiveCount > 0 && (
                  <span className="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded-full bg-blue-600 text-white text-[10px] font-bold">
                    {advancedActiveCount}
                  </span>
                )}
                <span aria-hidden="true" className="text-gray-400">{advancedFiltersOpen ? '▲' : '▼'}</span>
              </button>
              <button
                onClick={() => setQuickFilters({ ...DEFAULT_QUICK_FILTERS })}
                className="px-2.5 py-1.5 text-xs rounded-full border border-gray-600 bg-gray-900 text-gray-300 hover:bg-gray-800"
              >
                Clear filters
              </button>
              {sortKey !== 'priority' && (
                <button
                  onClick={() => { setSortKey('priority'); setSortOrder('asc'); }}
                  className="px-2.5 py-1.5 text-xs rounded-full border border-indigo-600/60 bg-indigo-900/30 text-indigo-200 hover:bg-indigo-800/40"
                  title="Restore the default ordering: favorites, then portfolio candidates, then recently changed repositories, then the unchanged long tail"
                >
                  Priority order
                </button>
              )}
            </div>

            {advancedFiltersOpen && (
              <div className="mb-3 flex flex-wrap items-center gap-2" data-testid="advanced-filters-panel">
                {ADVANCED_QUICK_FILTERS.map(renderChip)}
                <button
                  onClick={() => setLegendOpen(prev => !prev)}
                  className={`px-2.5 py-1.5 text-xs rounded-full border transition-colors ${legendOpen
                    ? 'border-blue-500/60 bg-blue-900/40 text-blue-100'
                    : 'border-gray-600 bg-gray-800/40 text-gray-300 hover:bg-gray-700/50'}`}
                >
                  {legendOpen ? 'Hide badge legend' : 'Badge legend'}
                </button>
              </div>
            )}
          </>
        );
      })()}

      {legendOpen && (
        <div className="mb-4 rounded-lg border border-gray-700 bg-gray-900/60 px-4 py-3 text-xs text-gray-300" data-testid="repo-grid-badge-legend">
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-x-6 gap-y-3">
            <div>
              <div className="font-semibold text-gray-200 mb-1.5">Curation (operator-set)</div>
              <div className="space-y-1">
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-yellow-900/40 text-yellow-200 border-yellow-600/50">★ Favorite</span> — always surfaced first in priority order.</div>
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-sky-900/40 text-sky-300 border-sky-700/50">◆ Candidate</span> — being evaluated for active portfolio work.</div>
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-gray-800/70 text-gray-400 border-gray-600/50">⊘ Ignored</span> — parked; hidden while "Hide ignored" is on.</div>
                <div className="text-gray-500">Set these from a repo's Details panel; they persist across restarts and never trigger a rescan.</div>
              </div>
            </div>
            <div>
              <div className="font-semibold text-gray-200 mb-1.5">Index (change-aware scanning)</div>
              <div className="space-y-1">
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-emerald-900/30 text-emerald-300 border-emerald-700/40">Index: Reused</span> — unchanged since the last scan; served from the persisted index without rescanning.</div>
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-cyan-900/30 text-cyan-300 border-cyan-700/40">Index: New Commits</span> — HEAD moved; this repo was selectively reindexed.</div>
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-amber-900/30 text-amber-300 border-amber-700/40">Index: Metadata Changed</span> — docs/PR/Actions signals changed without new commits.</div>
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-violet-900/30 text-violet-300 border-violet-700/40">Index: Rescanned</span> — no usable cache row (new repo, first scan, or forced refresh).</div>
                <div><span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-rose-900/30 text-rose-300 border-rose-700/40">Index: Scan Failed</span> — the last probe or scan errored; check the badge tooltip.</div>
                <div className="text-gray-500">Hover any Index badge for the scan decision, HEAD vs indexed commit, and errors. Use Refresh All to force a full rescan.</div>
              </div>
            </div>
            <div>
              <div className="font-semibold text-gray-200 mb-1.5">Uncommitted-change severity</div>
              <div className="space-y-1">
                <div><span className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs border-emerald-500/70 bg-emerald-900/40 text-emerald-100">Low</span> — 1-10 uncommitted files.</div>
                <div><span className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs border-yellow-500/70 bg-yellow-900/40 text-yellow-100">Medium</span> — 11-100 files.</div>
                <div><span className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs border-orange-500/70 bg-orange-900/40 text-orange-100">High</span> — 101-999 files.</div>
                <div><span className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs border-red-500/70 bg-red-900/40 text-red-100">Critical</span> — 1000+ files.</div>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="hidden lg:block mb-3 text-xs text-gray-500">
        Additional metadata is available per row via Details to keep key comparison columns visible without horizontal scrolling.
       </div>

      {/* Mobile/tablet card list — Release 2.5 Phase 1. Mirrors the desktop table
          below the lg breakpoint: same grouping, selection, badges, and
          per-repo actions, rendered as stacked touch-friendly cards. */}
      <div className="lg:hidden space-y-3">
        {(Object.entries(groupedRepos) as [string, RepoStatus[]][]).sort(([keyA], [keyB]) => keyA.localeCompare(keyB)).map(([groupKey, groupRepos]) => (
          <div key={groupKey}>
            {groupBy !== 'none' && (
              <button
                onClick={() => toggleGroup(groupKey)}
                className="w-full min-h-11 flex items-center gap-2 rounded-md bg-gray-800/70 px-3 py-2.5 text-sm font-bold text-gray-200"
              >
                {collapsedGroups.has(groupKey) ? <ChevronRightIcon className="w-4 h-4" /> : <ChevronDownIcon className="w-4 h-4" />}
                {groupKey} ({groupRepos.length})
              </button>
            )}
            {!collapsedGroups.has(groupKey) && (
              <div className={`space-y-3 ${groupBy !== 'none' ? 'mt-2' : ''}`}>
                {groupRepos.map((repo: RepoStatus) => {
                  const owner =
                    repo.owner ??
                    (dataSource?.source === 'github' ? dataSource.username : dataSource?.source === 'local' ? dataSource.configuredGithubUser ?? undefined : undefined);
                  const repoUrl = repo.htmlUrl ?? (owner ? `https://github.com/${owner}/${repo.name}` : undefined);
                  const pullsUrl = repoUrl ? `${repoUrl}/pulls` : undefined;
                  const repoId = getRepoSelectionId(repo);
                  const changesSeverity = getChangeSeverity(repo.uncommittedChanges ?? 0);
                  const readinessBadge: Record<string, { cls: string; label: string }> = {
                    ready: { cls: 'bg-green-900/40 text-green-300 border-green-700/40', label: '✓ Ready' },
                    'needs-doc-standardization': { cls: 'bg-yellow-900/40 text-yellow-300 border-yellow-700/40', label: '⚠ Needs Docs' },
                    blocked: { cls: 'bg-red-900/40 text-red-300 border-red-700/40', label: '✕ Blocked' },
                    'missing-roadmap': { cls: 'bg-gray-700/50 text-gray-400 border-gray-600/40', label: 'No Roadmap' },
                    'roadmap-complete': { cls: 'bg-blue-900/40 text-blue-300 border-blue-700/40', label: 'Roadmap Done' },
                    'parse-error': { cls: 'bg-orange-900/40 text-orange-300 border-orange-700/40', label: '! Parse Error' },
                  };
                  const readinessCfg = repo.dispatchReadiness ? readinessBadge[repo.dispatchReadiness] : undefined;
                  const changeStateCfg = getChangeStateBadgeConfig(repo.changeState);
                  const curationCfg = getCurationBadgeConfig(repo.curationState);
                  const roadmapCfg = getRoadmapBadgeConfig(repo.roadmapState as RoadmapBadgeState);
                  return (
                    <div
                      key={repo.localPath ?? repo.name}
                      className={`rounded-lg border px-3 py-3 ${selectedRepos.has(repoId) ? 'border-blue-600/60 bg-blue-900/20' : 'border-gray-700 bg-gray-900/60'}`}
                    >
                      <div className="flex items-start gap-3">
                        <input
                          type="checkbox"
                          checked={selectedRepos.has(repoId)}
                          onChange={() => handleSelectRepo(repoId)}
                          className="mt-1 h-5 w-5 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500"
                        />
                        <div className="min-w-0 flex-1">
                          {repoUrl ? (
                            <a href={repoUrl} target="_blank" rel="noopener noreferrer" className="block text-sm font-medium text-blue-400 hover:text-blue-300 truncate">
                              {owner ? `${owner}/${repo.name}` : repo.name}
                            </a>
                          ) : (
                            <span className="block text-sm font-medium text-gray-200 truncate">{repo.name}</span>
                          )}
                          <div className="text-xs text-gray-400 mt-0.5 break-all">{repo.localPath ?? 'No local path'}</div>
                        </div>
                        {getStatusBadge(repo.status, repo)}
                      </div>

                      <div className="mt-2 flex flex-wrap items-center gap-1.5">
                        {curationCfg && (
                          <span className={`inline-flex items-center text-xs px-1.5 py-0.5 rounded border ${curationCfg.className}`} title={curationCfg.title}>
                            {curationCfg.label}
                          </span>
                        )}
                        {/* Release 3.1 — this badge rendered from a hardcoded false
                            for several releases, so it never appeared. It now
                            reports the measured drift and says what produced it. */}
                        {repo.staleness?.state === 'behind' && (
                          <span
                            data-testid="repo-staleness-behind"
                            title={repo.staleness.summary}
                            className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-red-900/30 text-red-300 border-red-700/40"
                          >
                            {repo.staleness.behindByDays && repo.staleness.behindByDays >= 1
                              ? `Behind ~${repo.staleness.behindByDays}d`
                              : 'Behind remote'}
                          </span>
                        )}
                        {repo.staleness?.state === 'ahead-or-unpushed' && (
                          <span
                            title={repo.staleness.summary}
                            className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-amber-900/30 text-amber-200 border-amber-700/40"
                          >
                            Unpushed
                          </span>
                        )}
                        {repo.scope && !repo.scope.inScope && (
                          <span
                            title={repo.scope.reason}
                            className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-purple-900/30 text-purple-200 border-purple-700/40"
                          >
                            {repo.scope.classification === 'vendored' ? 'Vendored' : repo.scope.classification === 'archived' ? 'Archived path' : 'Out of scope'}
                          </span>
                        )}
                        {repo.staleness?.state === 'unknown' && (
                          <span
                            title={repo.staleness.summary}
                            className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-gray-800 text-gray-400 border-gray-600"
                          >
                            Drift unknown
                          </span>
                        )}
                        {repo.uncommittedChanges > 0 && (
                          <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs ${changesSeverity.className}`}>
                            {changesSeverity.label}
                            <span className="font-semibold">{repo.uncommittedChanges}</span>
                          </span>
                        )}
                        {getBuildStatusBadge(repo)}
                        {(repo.openPrCount ?? 0) > 0 && (
                          pullsUrl ? (
                            <a href={pullsUrl} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs text-gray-300 hover:text-blue-300">
                              <PullRequestIcon className="w-4 h-4" /> {repo.openPrCount}
                            </a>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-xs text-gray-400">
                              <PullRequestIcon className="w-4 h-4" /> {repo.openPrCount}
                            </span>
                          )
                        )}
                        {repo.hasRoadmap && onViewRoadmap && (
                          <button
                            onClick={() => onViewRoadmap(repo.name)}
                            className={`inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded border transition-colors ${roadmapCfg.className}`}
                            title={roadmapCfg.title}
                          >
                            {roadmapCfg.label}
                          </button>
                        )}
                        {readinessCfg && (
                          <span className={`inline-flex items-center text-xs px-1.5 py-0.5 rounded border ${readinessCfg.cls}`}>
                            {readinessCfg.label}
                          </span>
                        )}
                        {changeStateCfg && (
                          <span
                            className={`inline-flex items-center text-xs px-1.5 py-0.5 rounded border ${changeStateCfg.className}`}
                            title={buildScanDecisionTooltip(repo)}
                          >
                            {changeStateCfg.label}
                          </span>
                        )}
                      </div>

                      <div className="mt-2 text-xs text-gray-400">
                        <span className="text-gray-300">{repo.branch}</span>
                        {repo.lastCommitDate ? ` · local ${new Date(repo.lastCommitDate).toLocaleDateString()}` : ''}
                        {/* Release 3.1 — the remote's own clock, beside the local one.
                            Seeing both is what makes a drifted clone obvious without
                            opening anything. */}
                        {repo.remotePushedAt && (
                          <span
                            data-testid="repo-remote-pushed"
                            className={repo.staleness?.state === 'behind' ? 'text-red-300' : 'text-gray-400'}
                            title="When the remote default branch last received commits (GitHub pushed_at)."
                          >
                            {` · pushed ${new Date(repo.remotePushedAt).toLocaleDateString()}`}
                          </span>
                        )}
                        {repo.lastCommitAuthor ? ` · ${repo.lastCommitAuthor}` : ''}
                        {(repo.localAhead > 0 || repo.remoteAhead > 0) && (
                          <span className="text-gray-500">
                            {' · '}
                            {repo.localAhead > 0 ? `${repo.localAhead} ahead` : ''}
                            {repo.localAhead > 0 && repo.remoteAhead > 0 ? ', ' : ''}
                            {repo.remoteAhead > 0 ? `${repo.remoteAhead} behind` : ''}
                          </span>
                        )}
                      </div>

                      <div className="mt-3 flex items-stretch gap-2">
                        <button
                          onClick={() => onRunRepoAction?.('update', repoId)}
                          className="flex-1 min-h-11 rounded-md border border-gray-600 bg-gray-800 px-3 text-sm text-gray-200 active:bg-gray-700"
                        >
                          Pull
                        </button>
                        <button
                          onClick={() => onRunRepoAction?.('sync', repoId)}
                          className="flex-1 min-h-11 rounded-md border border-gray-600 bg-gray-800 px-3 text-sm text-gray-200 active:bg-gray-700"
                        >
                          Fetch
                        </button>
                        <button
                          onClick={() => toggleExpandedRow(repoId)}
                          className={`flex-1 min-h-11 rounded-md border px-3 text-sm active:bg-gray-700 ${expandedRows.has(repoId) ? 'border-indigo-500/60 bg-indigo-900/30 text-indigo-200' : 'border-gray-600 bg-gray-800 text-gray-200'}`}
                        >
                          Details
                        </button>
                        <details className="relative">
                          <summary className="list-none min-h-11 h-full flex items-center cursor-pointer rounded-md border border-gray-600 bg-gray-800 px-3.5 text-sm text-gray-200">
                            ⋯
                          </summary>
                          <div className="absolute right-0 bottom-full mb-1 w-44 rounded border border-gray-700 bg-gray-900 shadow-lg z-30 p-1">
                            <a
                              href={repoUrl ?? '#'}
                              target="_blank"
                              rel="noopener noreferrer"
                              className={`block rounded px-2 py-2.5 text-left text-xs ${repoUrl ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed pointer-events-none'}`}
                            >
                              Open on GitHub
                            </a>
                            <button
                              onClick={() => onOpenDocReview?.(repo.name)}
                              className="w-full rounded px-2 py-2.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                            >
                              Doc review
                            </button>
                            <button
                              onClick={() => onViewRoadmap?.(repo.name)}
                              className={`w-full rounded px-2 py-2.5 text-left text-xs ${onViewRoadmap ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                              disabled={!onViewRoadmap}
                              title={!onViewRoadmap ? 'Roadmap viewing is not wired up on this view.' : 'Open this repository’s ROADMAP.md.'}
                            >
                              Roadmap
                            </button>
                            <button
                              onClick={() => onRunRoadmapScan?.(repo.name)}
                              className={`w-full rounded px-2 py-2.5 text-left text-xs ${onRunRoadmapScan ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                              disabled={!onRunRoadmapScan}
                              title={!onRunRoadmapScan ? 'Roadmap scanning is not wired up on this view.' : 'Re-scan this repository’s roadmap.'}
                            >
                              Roadmap scan
                            </button>
                            {repo.status !== 'clean' && onViewGitStatus && (
                              <button
                                onClick={() => onViewGitStatus(repo.name, repo.localPath ?? undefined)}
                                className="w-full rounded px-2 py-2.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                              >
                                Git status
                              </button>
                            )}
                          </div>
                        </details>
                      </div>

                      {expandedRows.has(repoId) && (
                        <div className="mt-3">
                          {renderRepoDetailBlocks(repo)}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="hidden lg:block w-full min-w-0 shadow overflow-hidden border-b border-gray-700 sm:rounded-lg">
        <div className="max-h-[68vh] overflow-y-auto overflow-x-hidden">
            <table className="w-full table-fixed divide-y divide-gray-700">
            <colgroup>
              <col style={{ width: '4%' }} />
              <col style={{ width: '23%' }} />
              <col style={{ width: '10%' }} />
              <col style={{ width: '7%' }} />
              <col style={{ width: '10%' }} />
              <col style={{ width: '13%' }} />
              <col style={{ width: '12%' }} />
              <col style={{ width: '9%' }} />
              <col style={{ width: '7%' }} />
              <col style={{ width: '5%' }} />
            </colgroup>
            <thead className="bg-gray-800 sticky top-0 z-20">
                <tr>
                <th scope="col" className="px-2 py-3">
                  <span className="sr-only">Select all repositories</span>
                  <input type="checkbox" ref={selectAllCheckboxRef} onChange={handleSelectAll} className="h-4 w-4 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500"/>
                </th>
                <th scope="col" onClick={() => handleSort('name')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Repository {sortIndicator('name')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('status')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Status {sortIndicator('status')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('isStale')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Stale {sortIndicator('isStale')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('branch')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Branch {sortIndicator('branch')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('lastCommitDate')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Last Commit {sortIndicator('lastCommitDate')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('uncommittedChanges')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Changes {sortIndicator('uncommittedChanges')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('lastBuildStatus')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">Build {sortIndicator('lastBuildStatus')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('openPrCount')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">
                  <span className="inline-flex items-center gap-1">PRs {sortIndicator('openPrCount')}</span>
                </th>
                <th scope="col" className="relative px-2 py-3"><span className="sr-only">Actions</span></th>
                </tr>
            </thead>
            <tbody className="bg-gray-900 divide-y divide-gray-700">
              {(Object.entries(groupedRepos) as [string, RepoStatus[]][]).sort(([keyA], [keyB]) => keyA.localeCompare(keyB)).map(([groupKey, groupRepos]) => (
                    <React.Fragment key={groupKey}>
                        {groupBy !== 'none' && (
                            <tr className="bg-gray-800/70 hover:bg-gray-800/90 cursor-pointer" onClick={() => toggleGroup(groupKey)}>
                      <td colSpan={10} className="px-4 py-2 text-sm font-bold text-gray-200">
                                    <div className="flex items-center gap-2">
                                        {collapsedGroups.has(groupKey) ? <ChevronRightIcon className="w-4 h-4"/> : <ChevronDownIcon className="w-4 h-4"/>}
                                        {groupKey} ({groupRepos.length})
                                    </div>
                                </td>
                            </tr>
                        )}
                  {!collapsedGroups.has(groupKey) && groupRepos.map((repo: RepoStatus) => {
                        const owner =
                          repo.owner ??
                          (dataSource?.source === 'github' ? dataSource.username : dataSource?.source === 'local' ? dataSource.configuredGithubUser ?? undefined : undefined);
                        const repoUrl = repo.htmlUrl ?? (owner ? `https://github.com/${owner}/${repo.name}` : undefined);
                        const pullsUrl = repoUrl ? `${repoUrl}/pulls` : undefined;
                        const repoId = getRepoSelectionId(repo);
                        const changesSeverity = getChangeSeverity(repo.uncommittedChanges ?? 0);
                        return (
                        <React.Fragment key={repo.localPath ?? repo.name}>
                          <tr className={`hover:bg-gray-800/50 ${selectedRepos.has(repoId) ? 'bg-blue-900/30' : ''}`}>
                            <td className="px-2 py-3 align-top"><input type="checkbox" checked={selectedRepos.has(repoId)} onChange={() => handleSelectRepo(repoId)} className="h-4 w-4 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500" /></td>
                            <td className="min-w-0 overflow-hidden px-4 py-3 align-top">
                                {repoUrl ? (
                                  <a href={repoUrl} target="_blank" rel="noopener noreferrer" className="text-sm font-medium text-blue-400 hover:text-blue-300 hover:underline">
                                    {owner ? `${owner}/${repo.name}` : repo.name}
                                  </a>
                                ) : (
                                  <span className="text-sm font-medium text-gray-200">{repo.name}</span>
                                )}
                                <div className="truncate text-xs text-gray-400 mt-0.5" title={repo.localPath ?? 'No local path'}>{repo.localPath ?? 'No local path'}</div>
                                {(() => {
                                  const curationCfg = getCurationBadgeConfig(repo.curationState);
                                  if (!curationCfg) return null;
                                  return (
                                    <div className="mt-1">
                                      <span className={`inline-flex items-center text-xs px-1.5 py-0.5 rounded border ${curationCfg.className}`} title={curationCfg.title}>
                                        {curationCfg.label}
                                      </span>
                                    </div>
                                  );
                                })()}
                                {repo.hasRoadmap && onViewRoadmap && (() => {
                                  const { className, label, title: titleText } = getRoadmapBadgeConfig(repo.roadmapState as RoadmapBadgeState);
                                  return (
                                    <div className="mt-1 flex flex-col gap-0.5">
                                      <button
                                        onClick={(e) => { e.stopPropagation(); onViewRoadmap(repo.name); }}
                                        className={`inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded border transition-colors ${className}`}
                                        title={titleText}
                                      >
                                        {label}
                                      </button>
                                      {repo.roadmapState === 'pending' && repo.nextPendingRoadmapItem && (
                                        <div
                                          className="text-xs text-indigo-400/80 max-w-xs truncate"
                                          title={repo.nextPendingRoadmapItem}
                                        >
                                          ↳ {repo.nextPendingRoadmapItem}
                                        </div>
                                      )}
                                    </div>
                                  );
                                })()}
                                 {repo.dispatchReadiness && (() => {
                                   const readinessBadge: Record<string, { cls: string; label: string }> = {
                                     ready: { cls: 'bg-green-900/40 text-green-300 border-green-700/40', label: '✓ Ready' },
                                     'needs-doc-standardization': { cls: 'bg-yellow-900/40 text-yellow-300 border-yellow-700/40', label: '⚠ Needs Docs' },
                                     blocked: { cls: 'bg-red-900/40 text-red-300 border-red-700/40', label: '✕ Blocked' },
                                     'missing-roadmap': { cls: 'bg-gray-700/50 text-gray-400 border-gray-600/40', label: 'No Roadmap' },
                                     'roadmap-complete': { cls: 'bg-blue-900/40 text-blue-300 border-blue-700/40', label: 'Roadmap Done' },
                                     'parse-error': { cls: 'bg-orange-900/40 text-orange-300 border-orange-700/40', label: '! Parse Error' },
                                   };
                                   const cfg = readinessBadge[repo.dispatchReadiness];
                                   if (!cfg) return null;
                                   return (
                                     <div className="mt-1">
                                       <span className={`inline-flex items-center text-xs px-1.5 py-0.5 rounded border ${cfg.cls}`}>
                                         {cfg.label}
                                       </span>
                                     </div>
                                   );
                                 })()}
                                {(() => {
                                  const changeStateCfg = getChangeStateBadgeConfig(repo.changeState);
                                  if (!changeStateCfg) {
                                    return null;
                                  }
                                  return (
                                    <div className="mt-1">
                                      <span
                                        className={`inline-flex items-center text-xs px-1.5 py-0.5 rounded border ${changeStateCfg.className}`}
                                        title={buildScanDecisionTooltip(repo)}
                                      >
                                        {changeStateCfg.label}
                                      </span>
                                    </div>
                                  );
                                })()}
                              </td>
                            <td className="px-4 py-3 whitespace-nowrap align-top">{getStatusBadge(repo.status, repo)}</td>
                            {/* Release 3.1 — "Yes/No" could not distinguish a repo
                                measured as current from one nothing ever measured,
                                and for several releases every row said "No". */}
                            <td className="px-4 py-3 whitespace-nowrap text-sm align-top" title={repo.staleness?.summary}>
                              {repo.staleness?.state === 'behind' ? (
                                <span className="text-red-300">
                                  {repo.staleness.behindByDays && repo.staleness.behindByDays >= 1
                                    ? `Behind ~${repo.staleness.behindByDays}d`
                                    : 'Behind'}
                                </span>
                              ) : repo.staleness?.state === 'ahead-or-unpushed' ? (
                                <span className="text-amber-200">Unpushed</span>
                              ) : repo.staleness?.state === 'current' ? (
                                <span className="text-gray-400">Current</span>
                              ) : (
                                <span className="text-gray-500">Unknown</span>
                              )}
                            </td>
                            <td className="truncate px-4 py-3 text-sm text-gray-300 align-top" title={repo.branch}>{repo.branch}</td>
                            <td className="overflow-hidden px-4 py-3 whitespace-nowrap text-sm text-gray-400 align-top" title={repo.lastCommitMessage}>
                              {repo.lastCommitDate ? new Date(repo.lastCommitDate).toLocaleDateString() : 'N/A'}
                              {repo.remotePushedAt && (
                                <div
                                  className={`text-xs truncate max-w-[180px] ${repo.staleness?.state === 'behind' ? 'text-red-300' : 'text-gray-500'}`}
                                  title="Remote pushed_at"
                                >
                                  pushed {new Date(repo.remotePushedAt).toLocaleDateString()}
                                </div>
                              )}
                              {repo.lastCommitAuthor && (
                                <div className="text-xs text-gray-500 truncate max-w-[180px]">{repo.lastCommitAuthor}</div>
                              )}
                            </td>

                            <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-300 align-top">
                              {repo.uncommittedChanges > 0 ? (
                                <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs ${changesSeverity.className}`}>
                                  {changesSeverity.label}
                                  <span className="font-semibold">{repo.uncommittedChanges}</span>
                                </span>
                              ) : (
                                <span className="text-xs text-gray-500">0 uncommitted</span>
                              )}
                              {(repo.localAhead > 0 || repo.remoteAhead > 0) && (
                                <div className="text-xs text-gray-500 mt-1">
                                  {repo.localAhead > 0 ? `${repo.localAhead} ahead` : ''}
                                  {repo.localAhead > 0 && repo.remoteAhead > 0 ? ' · ' : ''}
                                  {repo.remoteAhead > 0 ? `${repo.remoteAhead} behind` : ''}
                                </div>
                              )}
                            </td>

                            <td className="overflow-hidden px-4 py-3 whitespace-nowrap align-top">{getBuildStatusBadge(repo)}</td>
                            <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-400 align-top">
                                {pullsUrl ? (
                                  <a href={pullsUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-2 hover:text-blue-400 transition-colors">
                                    <PullRequestIcon className="w-4 h-4" /> {repo.openPrCount ?? 0}
                                  </a>
                                ) : (
                                  <div className="flex items-center gap-2 text-gray-500">
                                    <PullRequestIcon className="w-4 h-4" /> {repo.openPrCount ?? 0}
                                  </div>
                                )}
                                {repo.pendingReviewPrCount ? (
                                  <div className="text-xs text-yellow-300 mt-1">
                                    {repo.pendingReviewPrCount} pending review
                                  </div>
                                ) : null}
                            </td>

                            <td className="px-2 py-3 whitespace-nowrap text-right text-sm font-medium align-top">
                              <details className="relative inline-block text-left">
                                <summary className="list-none cursor-pointer rounded border border-gray-600 bg-gray-800 px-2 py-1 text-xs text-gray-200 hover:bg-gray-700">
                                  ⋯
                                </summary>
                                <div className="absolute right-0 mt-1 w-40 whitespace-normal rounded border border-gray-700 bg-gray-900 shadow-lg z-30 p-1">
                                  <a
                                    href={repoUrl ?? '#'}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className={`block rounded px-2 py-1.5 text-left text-xs ${repoUrl ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed pointer-events-none'}`}
                                  >
                                    Open
                                  </a>
                                  <button
                                    onClick={() => onRunRepoAction?.('update', repoId)}
                                    className="block w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    Pull
                                  </button>
                                  <button
                                    onClick={() => onRunRepoAction?.('sync', repoId)}
                                    className="block w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    Fetch
                                  </button>
                                  <button
                                    onClick={() => toggleExpandedRow(repoId)}
                                    className="block w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    View details
                                  </button>
                                  <button
                                    onClick={() => onOpenDocReview?.(repo.name)}
                                    className="block w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    Doc review
                                  </button>
                                  <button
                                    onClick={() => onViewRoadmap?.(repo.name)}
                                    className={`block w-full rounded px-2 py-1.5 text-left text-xs ${onViewRoadmap ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                                    disabled={!onViewRoadmap}
                                    title={!onViewRoadmap ? 'Roadmap viewing is not wired up on this view.' : 'Open this repository’s ROADMAP.md.'}
                                  >
                                    Roadmap
                                  </button>
                                  <button
                                    onClick={() => onRunRoadmapScan?.(repo.name)}
                                    className={`block w-full rounded px-2 py-1.5 text-left text-xs ${onRunRoadmapScan ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                                    disabled={!onRunRoadmapScan}
                                    title={!onRunRoadmapScan ? 'Roadmap scanning is not wired up on this view.' : 'Re-scan this repository’s roadmap.'}
                                  >
                                    Roadmap scan
                                  </button>
                                  <button
                                    className="block w-full rounded px-2 py-1.5 text-left text-xs text-gray-500 cursor-not-allowed"
                                    disabled
                                    title="Archive is currently planned but not implemented in this build."
                                  >
                                    Archive (planned)
                                  </button>
                                </div>
                              </details>
                            </td>
                          </tr>
                          {expandedRows.has(repoId) && (
                            <tr className="bg-gray-950/60">
                              <td colSpan={10} className="px-4 py-3">
                                {renderRepoDetailBlocks(repo)}
                              </td>
                            </tr>
                          )}
                        </React.Fragment>
                        );})}
                    </React.Fragment>
                ))}
            </tbody>
            </table>
        </div>
      </div>
    </div>
  );
};

export default RepoGrid;

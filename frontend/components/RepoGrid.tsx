import React, { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import { type RepoStatus, type DispatchReadiness } from '../types';
import { BuildSuccessIcon, BuildFailureIcon, BuildInProgressIcon, PullRequestIcon, NoBuildsIcon, ChevronDownIcon, ChevronRightIcon } from './icons';

declare global {
  namespace JSX {
    interface IntrinsicElements {
      [elemName: string]: any;
    }
  }
}

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
}

type SortKey = 'name' | 'status' | 'branch' | 'lastCommitDate' | 'uncommittedChanges' | 'lastBuildStatus' | 'isStale' | 'openPrCount' | 'needsAttention';
type SortOrder = 'asc' | 'desc';

type DuplicateGroup = { groupKey: string; items: RepoStatus[] };
type QuickFilter = 'dirtyOnly' | 'hasUncommitted' | 'staleOnly' | 'needsAttention' | 'hasOpenPrs' | 'buildProblem' | 'roadmapFlagged' | 'duplicates';
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

const RepoGrid = ({ repos, onViewArtifacts, onViewRoadmap, onViewGitStatus, onRunRepoAction, onOpenDocReview, onRunRoadmapScan, dataSource, selectedRepos, setSelectedRepos, groupBy, setGroupBy }: RepoGridProps) => {
  const [sortKey, setSortKey] = useState<SortKey>('name');
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc');
  const [search, setSearch] = useState('');
  const [readinessFilter, setReadinessFilter] = useState<DispatchReadiness | 'all'>('all');
  const [quickFilters, setQuickFilters] = useState<Record<QuickFilter, boolean>>({
    dirtyOnly: false,
    hasUncommitted: false,
    staleOnly: false,
    needsAttention: false,
    hasOpenPrs: false,
    buildProblem: false,
    roadmapFlagged: false,
    duplicates: false,
  });
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

  const isNeedsAttention = (repo: RepoStatus) => {
    return repo.status !== 'clean' ||
      repo.uncommittedChanges > 0 ||
      repo.isStale ||
      (repo.lastBuildStatus === 'failure') ||
      (repo.lastBuildStatus === 'none') ||
      Boolean((repo.openPrCount ?? 0) > 0 && (repo.pendingReviewPrCount ?? 0) > 0) ||
      isRoadmapFlagged(repo) ||
      duplicateRepoIds.has(getRepoSelectionId(repo));
  };

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

      return matchesSearch && matchesReadiness && matchesDirtyOnly && matchesUncommitted && matchesStale && matchesAttention && matchesOpenPrs && matchesBuildProblem && matchesRoadmapFlag && matchesDuplicates;
    });

    const valueForSort = (repo: RepoStatus): string | number => {
      switch (sortKey) {
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
          </div>
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
            className="px-2.5 py-2 rounded border border-gray-600 bg-gray-900 text-xs text-gray-200 disabled:opacity-50"
          >
            Prev
          </button>
          <span className="text-xs text-gray-400">Page {clampedPage} / {totalPages}</span>
          <button
            onClick={() => setPageIndex(prev => Math.min(totalPages, prev + 1))}
            disabled={clampedPage >= totalPages}
            className="px-2.5 py-2 rounded border border-gray-600 bg-gray-900 text-xs text-gray-200 disabled:opacity-50"
          >
            Next
          </button>
        </div>
      </div>

      <div className="mb-3 flex flex-wrap items-center gap-2">
        {(
          [
            ['dirtyOnly', 'Dirty only'],
            ['hasUncommitted', 'Has uncommitted changes'],
            ['staleOnly', 'Stale'],
            ['needsAttention', 'Needs attention'],
            ['hasOpenPrs', 'Has open PRs'],
            ['buildProblem', 'No builds / failed builds'],
            ['roadmapFlagged', 'ROADMAP flagged'],
            ['duplicates', 'Duplicates'],
          ] as Array<[QuickFilter, string]>
        ).map(([key, label]) => (
          <button
            key={key}
            onClick={() => toggleQuickFilter(key)}
            className={`px-2.5 py-1.5 text-xs rounded-full border transition-colors ${quickFilters[key]
              ? 'border-blue-500/60 bg-blue-900/40 text-blue-100'
              : 'border-gray-600 bg-gray-800/40 text-gray-300 hover:bg-gray-700/50'}`}
          >
            {label}
          </button>
        ))}
        <button
          onClick={() => setQuickFilters({
            dirtyOnly: false,
            hasUncommitted: false,
            staleOnly: false,
            needsAttention: false,
            hasOpenPrs: false,
            buildProblem: false,
            roadmapFlagged: false,
            duplicates: false,
          })}
          className="px-2.5 py-1.5 text-xs rounded-full border border-gray-600 bg-gray-900 text-gray-300 hover:bg-gray-800"
        >
          Clear filters
        </button>
      </div>

      <div className="hidden md:block mb-3 text-xs text-gray-500">
        Additional metadata is available per row via Details to keep key comparison columns visible without horizontal scrolling.
       </div>

      {/* Mobile card list — Release 2.5 Phase 1. Mirrors the desktop table
          below the md breakpoint: same grouping, selection, badges, and
          per-repo actions, rendered as stacked touch-friendly cards. */}
      <div className="md:hidden space-y-3">
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
                    (dataSource?.source === 'github' ? dataSource.username : dataSource?.configuredGithubUser ?? undefined);
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
                        {repo.isStale && (
                          <span className="inline-flex items-center text-xs px-1.5 py-0.5 rounded border bg-red-900/30 text-red-300 border-red-700/40">Stale</span>
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
                      </div>

                      <div className="mt-2 text-xs text-gray-400">
                        <span className="text-gray-300">{repo.branch}</span>
                        {repo.lastCommitDate ? ` · ${new Date(repo.lastCommitDate).toLocaleDateString()}` : ''}
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
                            >
                              Roadmap
                            </button>
                            <button
                              onClick={() => onRunRoadmapScan?.(repo.name)}
                              className={`w-full rounded px-2 py-2.5 text-left text-xs ${onRunRoadmapScan ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                              disabled={!onRunRoadmapScan}
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

      <div className="hidden md:block shadow overflow-hidden border-b border-gray-700 sm:rounded-lg">
        <div className="max-h-[68vh] overflow-auto">
            <table className="min-w-full divide-y divide-gray-700 table-fixed">
            <thead className="bg-gray-800 sticky top-0 z-20">
                <tr>
                <th scope="col" className="px-4 py-3">
                  <span className="sr-only">Select all repositories</span>
                  <input type="checkbox" ref={selectAllCheckboxRef} onChange={handleSelectAll} className="h-4 w-4 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500"/>
                </th>
                <th scope="col" onClick={() => handleSort('name')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[24%]">
                  <span className="inline-flex items-center gap-1">Repository {sortIndicator('name')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('status')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[11%]">
                  <span className="inline-flex items-center gap-1">Status {sortIndicator('status')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('isStale')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[9%]">
                  <span className="inline-flex items-center gap-1">Stale {sortIndicator('isStale')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('branch')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[12%]">
                  <span className="inline-flex items-center gap-1">Branch {sortIndicator('branch')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('lastCommitDate')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[14%]">
                  <span className="inline-flex items-center gap-1">Last Commit {sortIndicator('lastCommitDate')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('uncommittedChanges')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[13%]">
                  <span className="inline-flex items-center gap-1">Changes {sortIndicator('uncommittedChanges')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('lastBuildStatus')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[9%]">
                  <span className="inline-flex items-center gap-1">Build {sortIndicator('lastBuildStatus')}</span>
                </th>
                <th scope="col" onClick={() => handleSort('openPrCount')} className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer w-[8%]">
                  <span className="inline-flex items-center gap-1">PRs {sortIndicator('openPrCount')}</span>
                </th>
                <th scope="col" className="relative px-4 py-3 w-[10%]"><span className="sr-only">Actions</span></th>
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
                          (dataSource?.source === 'github' ? dataSource.username : dataSource?.configuredGithubUser ?? undefined);
                        const repoUrl = repo.htmlUrl ?? (owner ? `https://github.com/${owner}/${repo.name}` : undefined);
                        const pullsUrl = repoUrl ? `${repoUrl}/pulls` : undefined;
                        const repoId = getRepoSelectionId(repo);
                        const changesSeverity = getChangeSeverity(repo.uncommittedChanges ?? 0);
                        return (
                        <React.Fragment key={repo.localPath ?? repo.name}>
                          <tr className={`hover:bg-gray-800/50 ${selectedRepos.has(repoId) ? 'bg-blue-900/30' : ''}`}>
                            <td className="px-4 py-3 align-top"><input type="checkbox" checked={selectedRepos.has(repoId)} onChange={() => handleSelectRepo(repoId)} className="h-4 w-4 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500" /></td>
                            <td className="px-4 py-3 align-top">
                                {repoUrl ? (
                                  <a href={repoUrl} target="_blank" rel="noopener noreferrer" className="text-sm font-medium text-blue-400 hover:text-blue-300 hover:underline">
                                    {owner ? `${owner}/${repo.name}` : repo.name}
                                  </a>
                                ) : (
                                  <span className="text-sm font-medium text-gray-200">{repo.name}</span>
                                )}
                                <div className="text-xs text-gray-400 mt-0.5">{repo.localPath ?? 'No local path'}</div>
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
                              </td>
                            <td className="px-4 py-3 whitespace-nowrap align-top">{getStatusBadge(repo.status, repo)}</td>
                            <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-300 align-top">{repo.isStale ? 'Yes' : 'No'}</td>
                            <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-300 align-top">{repo.branch}</td>
                            <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-400 align-top" title={repo.lastCommitMessage}>
                              {repo.lastCommitDate ? new Date(repo.lastCommitDate).toLocaleDateString() : 'N/A'}
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

                            <td className="px-4 py-3 whitespace-nowrap align-top">{getBuildStatusBadge(repo)}</td>
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

                            <td className="px-4 py-3 whitespace-nowrap text-right text-sm font-medium align-top">
                              <details className="relative inline-block text-left">
                                <summary className="list-none cursor-pointer rounded border border-gray-600 bg-gray-800 px-2 py-1 text-xs text-gray-200 hover:bg-gray-700">
                                  ⋯
                                </summary>
                                <div className="absolute right-0 mt-1 w-40 rounded border border-gray-700 bg-gray-900 shadow-lg z-30 p-1">
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
                                    className="w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    Pull
                                  </button>
                                  <button
                                    onClick={() => onRunRepoAction?.('sync', repoId)}
                                    className="w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    Fetch
                                  </button>
                                  <button
                                    onClick={() => toggleExpandedRow(repoId)}
                                    className="w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    View details
                                  </button>
                                  <button
                                    onClick={() => onOpenDocReview?.(repo.name)}
                                    className="w-full rounded px-2 py-1.5 text-left text-xs text-gray-200 hover:bg-gray-800"
                                  >
                                    Doc review
                                  </button>
                                  <button
                                    onClick={() => onViewRoadmap?.(repo.name)}
                                    className={`w-full rounded px-2 py-1.5 text-left text-xs ${onViewRoadmap ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                                    disabled={!onViewRoadmap}
                                  >
                                    Roadmap
                                  </button>
                                  <button
                                    onClick={() => onRunRoadmapScan?.(repo.name)}
                                    className={`w-full rounded px-2 py-1.5 text-left text-xs ${onRunRoadmapScan ? 'text-gray-200 hover:bg-gray-800' : 'text-gray-500 cursor-not-allowed'}`}
                                    disabled={!onRunRoadmapScan}
                                  >
                                    Roadmap scan
                                  </button>
                                  <button
                                    className="w-full rounded px-2 py-1.5 text-left text-xs text-gray-500 cursor-not-allowed"
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

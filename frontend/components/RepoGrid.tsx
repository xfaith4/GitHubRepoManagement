import React, { useState, useMemo, useEffect, useRef } from 'react';
import { type RepoStatus } from '../types';
import { BuildSuccessIcon, BuildFailureIcon, BuildInProgressIcon, PullRequestIcon, NoBuildsIcon, ChevronDownIcon, ChevronRightIcon } from './icons';

interface RepoGridProps {
  repos: RepoStatus[];
  onViewArtifacts: (repoName: string) => void;
  dataSource:
    | { source: 'sample' }
    | { source: 'local'; workspacePath?: string; configuredGithubUser?: string | null }
    | { source: 'github'; username: string }
    | null;
  selectedRepos: Set<string>;
  setSelectedRepos: React.Dispatch<React.SetStateAction<Set<string>>>;
  groupBy: keyof RepoStatus | 'none';
  setGroupBy: React.Dispatch<React.SetStateAction<keyof RepoStatus | 'none'>>;
}

type SortKey = keyof RepoStatus;
type SortOrder = 'asc' | 'desc';

const RepoGrid: React.FC<RepoGridProps> = ({ repos, onViewArtifacts, dataSource, selectedRepos, setSelectedRepos, groupBy, setGroupBy }) => {
  const [sortKey, setSortKey] = useState<SortKey>('name');
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc');
  const [filter, setFilter] = useState('');
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set());
  const selectAllCheckboxRef = useRef<HTMLInputElement>(null);

  const sortedAndFilteredRepos = useMemo(() => {
    const byPath = new Map<string, RepoStatus>();
    for (const repo of repos) {
      const key = repo.localPath ? repo.localPath.toLowerCase() : `${repo.name.toLowerCase()}::${repo.branch.toLowerCase()}`;
      if (!byPath.has(key)) {
        byPath.set(key, repo);
      }
    }

    const uniqueRepos = Array.from(byPath.values());
    const filterLower = filter.toLowerCase();
    const filtered = uniqueRepos.filter(repo =>
      repo.name.toLowerCase().includes(filterLower) ||
      (repo.localPath?.toLowerCase().includes(filterLower) ?? false)
    );

    return filtered.sort((a, b) => {
      const aValue = a[sortKey];
      const bValue = b[sortKey];

      if (aValue === undefined || bValue === undefined) return 0;
      
      if (sortKey === 'lastCommitDate') {
          const aDate = new Date(aValue as string).getTime();
          const bDate = new Date(bValue as string).getTime();
          return sortOrder === 'asc' ? aDate - bDate : bDate - aDate;
      }
      if (typeof aValue === 'string' && typeof bValue === 'string') {
        return sortOrder === 'asc' ? aValue.localeCompare(bValue) : bValue.localeCompare(aValue);
      }
      if (typeof aValue === 'number' && typeof bValue === 'number') {
        return sortOrder === 'asc' ? aValue - bValue : bValue - aValue;
      }
      if (typeof aValue === 'boolean' && typeof bValue === 'boolean') {
        return sortOrder === 'asc' ? (aValue === bValue ? 0 : aValue ? -1 : 1) : (aValue === bValue ? 0 : aValue ? 1 : -1);
      }
      
      return 0;
    });
  }, [repos, sortKey, sortOrder, filter]);

  const duplicateLocalRepoGroups = useMemo(() => {
    const groups = new Map<string, RepoStatus[]>();
    for (const repo of repos) {
      if (!repo.localPath) { continue; }
      const groupKey = repo.originUrl?.trim().toLowerCase() || repo.name.trim().toLowerCase();
      if (!groups.has(groupKey)) {
        groups.set(groupKey, []);
      }
      groups.get(groupKey)!.push(repo);
    }

    return Array.from(groups.entries())
      .map(([groupKey, items]) => ({ groupKey, items }))
      .filter(g => g.items.length > 1)
      .sort((a, b) => b.items.length - a.items.length);
  }, [repos]);

  const groupedRepos = useMemo((): Record<string, RepoStatus[]> => {
    if (groupBy === 'none') {
        return { 'All Repositories': sortedAndFilteredRepos };
    }
    return sortedAndFilteredRepos.reduce((acc, repo) => {
        const key = String(repo[groupBy] ?? 'N/A');
        if (!acc[key]) {
            acc[key] = [];
        }
        acc[key].push(repo);
        return acc;
    }, {} as Record<string, RepoStatus[]>);
  }, [sortedAndFilteredRepos, groupBy]);
  
  useEffect(() => {
    if (selectAllCheckboxRef.current) {
        const visibleRepoNames = new Set(sortedAndFilteredRepos.map(r => r.name));
        const selectedVisible = Array.from(selectedRepos).filter(name => visibleRepoNames.has(name));

        if (selectedVisible.length === 0) {
            selectAllCheckboxRef.current.checked = false;
            selectAllCheckboxRef.current.indeterminate = false;
        } else if (selectedVisible.length === visibleRepoNames.size) {
            selectAllCheckboxRef.current.checked = true;
            selectAllCheckboxRef.current.indeterminate = false;
        } else {
            selectAllCheckboxRef.current.checked = false;
            selectAllCheckboxRef.current.indeterminate = true;
        }
    }
  }, [selectedRepos, sortedAndFilteredRepos]);


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
        sortedAndFilteredRepos.forEach(repo => {
            if (isChecked) {
                newSelected.add(repo.name);
            } else {
                newSelected.delete(repo.name);
            }
        });
        return newSelected;
    });
  };

  const handleSelectRepo = (repoName: string) => {
    setSelectedRepos(prev => {
        const newSet = new Set(prev);
        if (newSet.has(repoName)) {
            newSet.delete(repoName);
        } else {
            newSet.add(repoName);
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

  const getStatusBadge = (status: RepoStatus['status']) => {
    const statusMap: Record<RepoStatus['status'], { text: string; color: string }> = {
      clean: { text: "Clean", color: "bg-green-800 text-green-200" },
      dirty: { text: "Dirty", color: "bg-yellow-800 text-yellow-200" },
      ahead: { text: "Ahead", color: "bg-blue-800 text-blue-200" },
      behind: { text: "Behind", color: "bg-purple-800 text-purple-200" },
      diverged: { text: "Diverged", color: "bg-red-800 text-red-200" },
    };
    const { text, color } = statusMap[status] || { text: 'Unknown', color: 'bg-gray-700 text-gray-300' };
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
  
  const groupByOptions: { value: keyof RepoStatus | 'none'; label: string }[] = [
      { value: 'none', label: 'None' },
      { value: 'status', label: 'Status' },
      { value: 'isStale', label: 'Is Stale' },
      { value: 'lastBuildStatus', label: 'Build Status' },
  ];

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-4">
       {duplicateLocalRepoGroups.length > 0 && (
        <div className="mb-4 rounded-lg border border-yellow-700/60 bg-yellow-900/20 px-4 py-3 text-sm text-yellow-100">
          <div className="font-semibold mb-2">Duplicate local repo copies detected (cleanup candidates)</div>
          <ul className="space-y-2">
            {duplicateLocalRepoGroups.slice(0, 10).map(group => (
              <li key={group.groupKey}>
                <div className="font-medium">{group.items[0].name} ({group.items.length} copies)</div>
                <div className="text-xs text-yellow-200/90">
                  {group.items.map(item => item.localPath).filter(Boolean).join(' | ')}
                </div>
              </li>
            ))}
          </ul>
        </div>
       )}
       <div className="mb-4 flex flex-wrap gap-4">
        <input
            type="text"
            placeholder="Filter repositories..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="block w-full max-w-xs bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
        />
        <div className="flex items-center gap-2">
            <label htmlFor="group-by" className="text-sm font-medium text-gray-300">Group By:</label>
            <select
                id="group-by"
                value={groupBy}
                onChange={(e) => setGroupBy(e.target.value as keyof RepoStatus | 'none')}
                className="block w-full max-w-xs bg-gray-900 border border-gray-600 rounded-md shadow-sm py-2 pl-3 pr-8 text-white focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
                {groupByOptions.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
            </select>
        </div>
       </div>
      <div className="shadow overflow-hidden border-b border-gray-700 sm:rounded-lg">
        <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-700">
            <thead className="bg-gray-800">
                <tr>
                <th scope="col" className="px-4 py-3"><input type="checkbox" ref={selectAllCheckboxRef} onChange={handleSelectAll} className="h-4 w-4 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500"/></th>
                <th scope="col" onClick={() => handleSort('name')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Name</th>
                <th scope="col" onClick={() => handleSort('status')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Status</th>
                <th scope="col" onClick={() => handleSort('lastBuildStatus')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Last Build</th>
                <th scope="col" onClick={() => handleSort('openPrCount')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Open PRs</th>
                {repos.some(r => r.extended) && (
                  <>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Issues</th>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Projects</th>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Branches</th>
                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Health</th>
                  </>
                )}
                <th scope="col" onClick={() => handleSort('branch')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Branch</th>
                <th scope="col" onClick={() => handleSort('lastCommitDate')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Last Commit</th>
                <th scope="col" onClick={() => handleSort('uncommittedChanges')} className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer">Changes</th>
                <th scope="col" className="relative px-6 py-3"><span className="sr-only">Actions</span></th>
                </tr>
            </thead>
            <tbody className="bg-gray-900 divide-y divide-gray-700">
                {Object.entries(groupedRepos).sort(([keyA], [keyB]) => keyA.localeCompare(keyB)).map(([groupKey, groupRepos]: [string, RepoStatus[]]) => (
                    <React.Fragment key={groupKey}>
                        {groupBy !== 'none' && (
                            <tr className="bg-gray-800/70 hover:bg-gray-800/90 cursor-pointer" onClick={() => toggleGroup(groupKey)}>
                                <td colSpan={repos.some(r => r.extended) ? 13 : 9} className="px-4 py-2 text-sm font-bold text-gray-200">
                                    <div className="flex items-center gap-2">
                                        {collapsedGroups.has(groupKey) ? <ChevronRightIcon className="w-4 h-4"/> : <ChevronDownIcon className="w-4 h-4"/>}
                                        {groupKey} ({groupRepos.length})
                                    </div>
                                </td>
                            </tr>
                        )}
                        {!collapsedGroups.has(groupKey) && groupRepos.map((repo) => {
                        const owner =
                          repo.owner ??
                          (dataSource?.source === 'github' ? dataSource.username : dataSource?.configuredGithubUser ?? undefined);
                        const repoUrl = repo.htmlUrl ?? (owner ? `https://github.com/${owner}/${repo.name}` : undefined);
                        const pullsUrl = repoUrl ? `${repoUrl}/pulls` : undefined;
                        const artifactDetails = typeof repo.artifactCount === 'number' ? repo.artifactCount : null;
                        const repoSizeMb = typeof repo.repoSizeKb === 'number' ? (repo.repoSizeKb / 1024) : null;
                        const testingWorkflowCount = repo.testingWorkflowCount ?? null;
                        const workflowCount = repo.actionsWorkflowCount ?? null;
                        return (
                        <tr key={repo.localPath ?? repo.name} className={`hover:bg-gray-800/50 ${selectedRepos.has(repo.name) ? 'bg-blue-900/30' : ''}`}>
                            <td className="px-4 py-4"><input type="checkbox" checked={selectedRepos.has(repo.name)} onChange={() => handleSelectRepo(repo.name)} className="h-4 w-4 rounded bg-gray-700 border-gray-500 text-blue-500 focus:ring-blue-500" /></td>
                            <td className="px-6 py-4 whitespace-nowrap">
                                {repoUrl ? (
                                  <a href={repoUrl} target="_blank" rel="noopener noreferrer" className="text-sm font-medium text-blue-400 hover:text-blue-300 hover:underline">
                                    {owner ? `${owner}/${repo.name}` : repo.name}
                                  </a>
                                ) : (
                                  <span className="text-sm font-medium text-gray-200">{repo.name}</span>
                                )}
                                {repo.isStale && <div className="text-xs text-yellow-400">Stale</div>}
                                {repo.isArchived && <div className="text-xs text-gray-500">Archived</div>}
                                {repoSizeMb !== null && (
                                  <div className="text-xs text-gray-500">
                                    {(repoSizeMb).toFixed(1)} MB • {artifactDetails ?? 0} artifacts
                                  </div>
                                )}
                                {repo.localPath && (
                                  <div className="text-xs text-gray-400 break-all max-w-md" title={repo.localPath}>
                                    {repo.localPath}
                                  </div>
                                )}
                                {workflowCount !== null && (
                                  <div className="text-xs text-gray-500">
                                    {workflowCount} workflows{testingWorkflowCount !== null && ` · ${testingWorkflowCount} testing`}
                                  </div>
                                )}
                              </td>
                            <td className="px-6 py-4 whitespace-nowrap">{getStatusBadge(repo.status)}</td>
                            <td className="px-6 py-4 whitespace-nowrap">{getBuildStatusBadge(repo)}</td>
                            <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
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
                            
                            {repos.some(r => r.extended) && (
                              <>
                                {/* Issues */}
                                <td className="px-6 py-4 whitespace-nowrap">
                                  {repo.extended?.openIssuesCount !== undefined ? (
                                    <div className="flex items-center gap-2">
                                      <span className={`text-sm font-medium ${repo.extended.openIssuesCount > 10 ? 'text-yellow-400' : 'text-gray-300'}`}>
                                        {repo.extended.openIssuesCount}
                                      </span>
                                      {repo.extended.oldestOpenIssueDays && repo.extended.oldestOpenIssueDays > 90 && (
                                        <span className="text-xs text-red-400" title={`Oldest: ${repo.extended.oldestOpenIssueDays}d`}>
                                          ⚠
                                        </span>
                                      )}
                                    </div>
                                  ) : (
                                    <span className="text-sm text-gray-500">-</span>
                                  )}
                                </td>
                                
                                {/* Projects */}
                                <td className="px-6 py-4 whitespace-nowrap">
                                  {repo.extended?.projectsCount !== undefined ? (
                                    <span className="text-sm text-gray-300">
                                      {repo.extended.activeProjects} / {repo.extended.projectsCount}
                                    </span>
                                  ) : (
                                    <span className="text-sm text-gray-500">-</span>
                                  )}
                                </td>
                                
                                {/* Branches */}
                                <td className="px-6 py-4 whitespace-nowrap">
                                  {repo.extended?.totalBranches !== undefined ? (
                                    <div className="flex items-center gap-2">
                                      <span className="text-sm text-gray-300">{repo.extended.totalBranches}</span>
                                      {repo.extended.staleBranches > 0 && (
                                        <span className="text-xs px-1.5 py-0.5 bg-orange-900/50 text-orange-300 rounded">
                                          {repo.extended.staleBranches} stale
                                        </span>
                                      )}
                                    </div>
                                  ) : (
                                    <span className="text-sm text-gray-500">-</span>
                                  )}
                                </td>
                                
                                {/* Health Score */}
                                <td className="px-6 py-4 whitespace-nowrap">
                                  {repo.extended?.healthScore !== undefined ? (
                                    <div className="flex items-center gap-2">
                                      <div className="w-16 h-2 bg-gray-700 rounded-full overflow-hidden">
                                        <div 
                                          className={`h-full ${
                                            repo.extended.healthScore >= 80 ? 'bg-green-500' :
                                            repo.extended.healthScore >= 60 ? 'bg-yellow-500' :
                                            'bg-red-500'
                                          }`}
                                          style={{ width: `${repo.extended.healthScore}%` }}
                                        />
                                      </div>
                                      <span className="text-xs text-gray-400">{repo.extended.healthScore}%</span>
                                    </div>
                                  ) : (
                                    <span className="text-sm text-gray-500">-</span>
                                  )}
                                </td>
                              </>
                            )}
                            
                            <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-400">{repo.branch}</td>
                            <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-400" title={repo.lastCommitMessage}>
                            {repo.lastCommitDate ? new Date(repo.lastCommitDate).toLocaleDateString() : 'N/A'}{repo.lastCommitAuthor && ` by ${repo.lastCommitAuthor}`}
                            </td>

                            <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                                {repo.uncommittedChanges > 0 && <span>{repo.uncommittedChanges} uncommitted<br/></span>}
                                {repo.localAhead > 0 && <span>{repo.localAhead} ahead<br/></span>}
                                {repo.remoteAhead > 0 && <span>{repo.remoteAhead} behind</span>}
                            </td>
                            <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            {repo.hasArtifacts && (
                                <button onClick={() => onViewArtifacts(repo.name)} className="text-blue-400 hover:text-blue-300">
                                Artifacts
                                </button>
                            )}
                            {artifactDetails !== null && (
                              <div className="text-xs text-gray-400 mt-1">
                                Total: {artifactDetails}
                              </div>
                            )}
                            </td>
                        </tr>
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

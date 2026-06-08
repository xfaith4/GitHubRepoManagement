import React, { useMemo } from 'react';
import { type RepoStatus } from '../types';

interface ChangeHistoryPanelProps {
  repos: RepoStatus[];
}

const ChangeHistoryPanel: React.FC<ChangeHistoryPanelProps> = ({ repos }) => {
  const activityMetrics = useMemo(() => {
    const now = Date.now();
    const weekWindowMs = 7 * 24 * 60 * 60 * 1000;
    const monthWindowMs = 30 * 24 * 60 * 60 * 1000;
    const totalCommitsWeek = repos.reduce((sum, r) => sum + (r.commitsLastWeek ?? 0), 0);
    const totalCommitsMonth = repos.reduce((sum, r) => sum + (r.commitsLastMonth ?? 0), 0);
    
    const uniqueContributorsWeek = new Set<string>();
    const uniqueContributorsMonth = new Set<string>();
    let recentReposByDateWeek = 0;
    let recentReposByDateMonth = 0;
    
    repos.forEach(r => {
      if ((r.commitsLastWeek ?? 0) > 0) {
        uniqueContributorsWeek.add(r.lastCommitAuthor);
      }
      if ((r.commitsLastMonth ?? 0) > 0) {
        uniqueContributorsMonth.add(r.lastCommitAuthor);
      }

      const lastCommitDateValue = r.lastCommitDate ? Date.parse(r.lastCommitDate) : Number.NaN;
      if (Number.isFinite(lastCommitDateValue)) {
        const ageMs = now - lastCommitDateValue;
        if (ageMs <= weekWindowMs) {
          recentReposByDateWeek += 1;
        }
        if (ageMs <= monthWindowMs) {
          recentReposByDateMonth += 1;
        }
      }
    });
    
    const activeReposWeek = repos.filter(r => (r.commitsLastWeek ?? 0) > 0).length;
    const activeReposMonth = repos.filter(r => (r.commitsLastMonth ?? 0) > 0).length;
    const commitMetricsUnavailableWeek = totalCommitsWeek === 0 && recentReposByDateWeek > 0;
    const commitMetricsUnavailableMonth = totalCommitsMonth === 0 && recentReposByDateMonth > 0;
    
    // Calculate average commits per active repo
    const avgCommitsPerRepoWeek = activeReposWeek > 0 ? (totalCommitsWeek / activeReposWeek).toFixed(1) : '0';
    const avgCommitsPerRepoMonth = activeReposMonth > 0 ? (totalCommitsMonth / activeReposMonth).toFixed(1) : '0';
    
    // Get top active repos this week
    const topActiveReposWeek = [...repos]
      .filter(r => (r.commitsLastWeek ?? 0) > 0)
      .sort((a, b) => (b.commitsLastWeek ?? 0) - (a.commitsLastWeek ?? 0))
      .slice(0, 5);
    
    return {
      totalCommitsWeek,
      totalCommitsMonth,
      activeContributorsWeek: uniqueContributorsWeek.size,
      activeContributorsMonth: uniqueContributorsMonth.size,
      activeReposWeek,
      activeReposMonth,
      avgCommitsPerRepoWeek,
      avgCommitsPerRepoMonth,
      topActiveReposWeek,
      recentReposByDateWeek,
      recentReposByDateMonth,
      commitMetricsUnavailableWeek,
      commitMetricsUnavailableMonth,
    };
  }, [repos]);
  
  const getActivityLevel = (commits: number): { level: string; color: string } => {
    if (commits === 0) return { level: 'Inactive', color: 'text-gray-500' };
    if (commits < 10) return { level: 'Low', color: 'text-yellow-500' };
    if (commits < 30) return { level: 'Moderate', color: 'text-blue-500' };
    return { level: 'High', color: 'text-green-500' };
  };
  
  const weekActivity = getActivityLevel(activityMetrics.totalCommitsWeek);
  const monthActivity = getActivityLevel(activityMetrics.totalCommitsMonth);
  const displayActiveReposWeek = activityMetrics.commitMetricsUnavailableWeek ? activityMetrics.recentReposByDateWeek : activityMetrics.activeReposWeek;
  const displayActiveReposMonth = activityMetrics.commitMetricsUnavailableMonth ? activityMetrics.recentReposByDateMonth : activityMetrics.activeReposMonth;
  
  return (
    <div className="bg-gray-800/50 border border-gray-700 rounded-lg p-6 mb-4">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-semibold text-gray-100 flex items-center">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 mr-2 text-blue-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="12" y1="1" x2="12" y2="23"></line>
            <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path>
          </svg>
          Team Activity Dashboard
        </h2>
        <span className="text-sm text-gray-400">Real-time Development Metrics</span>
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Weekly Summary */}
        <div className="bg-gray-900/50 p-5 rounded-lg border border-gray-700">
          <h3 className="text-lg font-medium text-gray-200 mb-4 flex items-center">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 mr-2 text-blue-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
              <line x1="16" y1="2" x2="16" y2="6"></line>
              <line x1="8" y1="2" x2="8" y2="6"></line>
              <line x1="3" y1="10" x2="21" y2="10"></line>
            </svg>
            Last 7 Days
          </h3>
          <div className="space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Total Commits</span>
              <span className="text-2xl font-bold text-blue-400">
                {activityMetrics.commitMetricsUnavailableWeek ? '—' : activityMetrics.totalCommitsWeek}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Active Repositories</span>
              <span className="text-xl font-semibold text-gray-200">{displayActiveReposWeek}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Active Contributors</span>
              <span className="text-xl font-semibold text-gray-200">
                {activityMetrics.commitMetricsUnavailableWeek ? '—' : activityMetrics.activeContributorsWeek}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Avg Commits/Repo</span>
              <span className="text-xl font-semibold text-gray-200">
                {activityMetrics.commitMetricsUnavailableWeek ? '—' : activityMetrics.avgCommitsPerRepoWeek}
              </span>
            </div>
            <div className="flex justify-between items-center pt-2 border-t border-gray-700">
              <span className="text-sm text-gray-400">Activity Level</span>
              <span className={`text-lg font-bold ${activityMetrics.commitMetricsUnavailableWeek ? 'text-yellow-400' : weekActivity.color}`}>
                {activityMetrics.commitMetricsUnavailableWeek ? 'Unavailable' : weekActivity.level}
              </span>
            </div>
          </div>
        </div>
        
        {/* Monthly Summary */}
        <div className="bg-gray-900/50 p-5 rounded-lg border border-gray-700">
          <h3 className="text-lg font-medium text-gray-200 mb-4 flex items-center">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 mr-2 text-green-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
              <line x1="16" y1="2" x2="16" y2="6"></line>
              <line x1="8" y1="2" x2="8" y2="6"></line>
              <line x1="3" y1="10" x2="21" y2="10"></line>
            </svg>
            Last 30 Days
          </h3>
          <div className="space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Total Commits</span>
              <span className="text-2xl font-bold text-green-400">
                {activityMetrics.commitMetricsUnavailableMonth ? '—' : activityMetrics.totalCommitsMonth}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Active Repositories</span>
              <span className="text-xl font-semibold text-gray-200">{displayActiveReposMonth}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Active Contributors</span>
              <span className="text-xl font-semibold text-gray-200">
                {activityMetrics.commitMetricsUnavailableMonth ? '—' : activityMetrics.activeContributorsMonth}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm text-gray-400">Avg Commits/Repo</span>
              <span className="text-xl font-semibold text-gray-200">
                {activityMetrics.commitMetricsUnavailableMonth ? '—' : activityMetrics.avgCommitsPerRepoMonth}
              </span>
            </div>
            <div className="flex justify-between items-center pt-2 border-t border-gray-700">
              <span className="text-sm text-gray-400">Activity Level</span>
              <span className={`text-lg font-bold ${activityMetrics.commitMetricsUnavailableMonth ? 'text-yellow-400' : monthActivity.color}`}>
                {activityMetrics.commitMetricsUnavailableMonth ? 'Unavailable' : monthActivity.level}
              </span>
            </div>
          </div>
        </div>
      </div>
      
      {/* Top Active Repositories This Week */}
      {activityMetrics.topActiveReposWeek.length > 0 && (
        <div className="mt-6 bg-gray-900/50 p-5 rounded-lg border border-gray-700">
          <h3 className="text-lg font-medium text-gray-200 mb-4 flex items-center">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 mr-2 text-yellow-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon>
            </svg>
            Most Active Repositories (Last 7 Days)
          </h3>
          <div className="space-y-2">
            {activityMetrics.topActiveReposWeek.map((repo, index) => {
              const maxCommits = activityMetrics.topActiveReposWeek[0].commitsLastWeek ?? 1;
              const percentage = ((repo.commitsLastWeek ?? 0) / maxCommits) * 100;
              
              return (
                <div key={repo.name} className="flex items-center gap-3">
                  <span className="text-sm font-medium text-gray-400 w-6 text-right">{index + 1}.</span>
                  <div className="flex-1">
                    <div className="flex justify-between items-center mb-1">
                      <span className="text-sm font-medium text-gray-200">{repo.name}</span>
                      <span className="text-sm font-bold text-blue-400">{repo.commitsLastWeek} commits</span>
                    </div>
                    <div className="w-full bg-gray-700 rounded-full h-2">
                      <div 
                        className="bg-gradient-to-r from-blue-500 to-blue-400 h-2 rounded-full transition-all duration-300"
                        style={{ width: `${percentage}%` }}
                      ></div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
      
      {/* Activity Insights */}
      <div className="mt-6 p-4 bg-blue-900/20 border border-blue-700/50 rounded-lg">
        <div className="flex items-start">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 mr-2 text-blue-400 mt-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10"></circle>
            <line x1="12" y1="16" x2="12" y2="12"></line>
            <line x1="12" y1="8" x2="12.01" y2="8"></line>
          </svg>
          <div className="text-sm text-gray-300">
            <strong className="text-blue-400">Executive Summary:</strong> 
            {activityMetrics.totalCommitsWeek > 0 ? (
              <span> Your team has made <strong>{activityMetrics.totalCommitsWeek}</strong> commits across <strong>{displayActiveReposWeek}</strong> repositories in the last 7 days, with <strong>{activityMetrics.activeContributorsWeek}</strong> active contributors. This month, there have been <strong>{activityMetrics.totalCommitsMonth}</strong> total commits.</span>
            ) : activityMetrics.commitMetricsUnavailableWeek || activityMetrics.commitMetricsUnavailableMonth ? (
              <span> Recent repository updates were detected, but commit-count activity metrics are unavailable in the current status payload. Restart the API host from this repo checkout or clear the status cache to rebuild those metrics.</span>
            ) : (
              <span> No commit activity detected in the last 7 days. Consider checking team engagement or data source configuration.</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default ChangeHistoryPanel;

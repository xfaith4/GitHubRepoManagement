import React from 'react';
import { InitIcon, UpdateIcon, SyncIcon, ExportIcon, ArchiveIcon, RefreshIcon, SpinnerIcon, DocReviewIcon, RoadmapIcon, ApiDocsIcon, HelpIcon } from './icons';
import { type OperationType, type AppSettings } from '../types';
import { canRunRepoActions, repoActionsBlockedReason } from '../lib/dataProvenance';

interface ActionBarProps {
  onAction: (operation: OperationType, repoNames?: string[]) => void;
  onExport: () => void;
  onRefresh: () => void;
  onInitClick: () => void;
  onDocReviewClick: () => void;
  onApiDocsClick: () => void;
  onHelpClick: () => void;
  isActionRunning: boolean;
  currentOperation: OperationType | null;
  settings: AppSettings | null;
  selectedRepos: Set<string>;
  /**
   * Repositories currently in scope. At 0, every repo-acting button is disabled
   * and the operator is pointed at the real blocker (scan a workspace) rather
   * than being allowed to click into a no-op.
   */
  repoCount: number;
  /**
   * Configured workspace roots that are not on disk. When present these are the
   * reason nothing is in scope, so the blocked-action hint names the path
   * instead of repeating the generic "scan a workspace first" remedy.
   */
  missingRoots?: string[];
}

interface ActionButtonProps {
    onClick: () => void;
    disabled: boolean;
    isLoading?: boolean;
    title: string;
    icon: React.ReactNode;
    // Accessible name so icon-only buttons (and buttons whose text label is
    // hidden at narrow widths) are never a guess for screen-reader / keyboard
    // users (Release 2.6 Phase 1). Falls back to `title` when omitted.
    ariaLabel?: string;
    // Consistent "Label · count" + separate status-tag pattern (Release 2.6
    // Phase 4): `count` renders as "· N" after the label; `statusTag` renders as
    // a small pill (e.g. "Planned") instead of being baked into the label text.
    count?: number;
    statusTag?: string;
    children?: React.ReactNode;
}

const ActionButton: React.FC<ActionButtonProps> = ({ onClick, disabled, isLoading, title, icon, ariaLabel, count, statusTag, children }) => (
    <button
        onClick={onClick}
        disabled={disabled || !!isLoading}
        title={title}
        aria-label={ariaLabel ?? title}
        className="flex items-center justify-center sm:justify-start gap-1.5 px-4 py-2 text-sm font-medium rounded-md transition-colors bg-gray-700 text-gray-200 hover:bg-gray-600 disabled:opacity-50 disabled:cursor-not-allowed"
    >
        <div className="w-4 h-4 flex-shrink-0">{isLoading ? <SpinnerIcon className="w-4 h-4" /> : icon}</div>
        {children}
        {typeof count === 'number' && count > 0 && (
            <span className="hidden sm:inline text-gray-300">· {count}</span>
        )}
        {statusTag && (
            <span
                data-testid="action-status-tag"
                className="ml-0.5 px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase tracking-wide bg-gray-600/70 text-gray-200 border border-gray-500/50"
            >
                {statusTag}
            </span>
        )}
    </button>
);


const ActionBar: React.FC<ActionBarProps> = ({ onAction, onExport, onRefresh, onInitClick, onDocReviewClick, onApiDocsClick, onHelpClick, isActionRunning, currentOperation, settings, selectedRepos, repoCount, missingRoots }) => {

    const selection = selectedRepos.size > 0 ? Array.from(selectedRepos) : undefined;
    const selectionCount = selectedRepos.size;
    const cloneImplemented = false;
    const archiveImplemented = false;

    // Repo-acting buttons need something to act on. Navigational/recovery
    // controls (Refresh, Settings, Help, API docs) stay enabled — they are the
    // way out of the empty state.
    const repoActionsEnabled = canRunRepoActions(repoCount, isActionRunning);
    const blockedReason = repoActionsBlockedReason(repoCount, missingRoots ?? []);
    // When nothing is in scope, the blocker replaces the action's own tooltip so
    // hovering a greyed-out button explains itself.
    const actionTitle = (normal: string) => blockedReason ?? normal;

    // Unified action label: always "<Label>" (hidden below sm) with the
    // selection count rendered separately as "· N" and status carried in a
    // small tag — never mixed into the label text (Release 2.6 Phase 4).
    const actionLabel = (text: string) => <span className="hidden sm:inline">{text}</span>;

    const handleUpdate = () => onAction('update', selection);
    const handleSync = () => onAction('sync', selection);

    const handleArchive = () => {
        if (!archiveImplemented) return;
        const repoList = selectionCount > 0 ? `${selectionCount} selected repos` : 'all inactive repos';
        if (settings && window.confirm(`This will archive ${repoList} inactive for over ${settings.daysInactive} days (local operation). Are you sure?`)) {
            onAction('archive', selection);
        }
    };

    return (
        <div className="p-4 border-b border-gray-700 flex flex-wrap items-center gap-3">
            <div data-testid="bulk-selection-note" className="w-full text-xs flex flex-wrap items-center gap-2">
                {blockedReason ? (
                    // Nothing in scope: the implicit-bulk-scope note is meaningless
                    // here, so the actual blocker takes its place.
                    <span
                        data-testid="no-repos-hint"
                        className="inline-flex items-center gap-1.5 rounded border border-amber-700/50 bg-amber-900/20 px-2 py-0.5 text-amber-200"
                    >
                        <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                            <circle cx="12" cy="12" r="10" /><line x1="12" y1="16" x2="12" y2="12" /><line x1="12" y1="8" x2="12.01" y2="8" />
                        </svg>
                        <span>{blockedReason}</span>
                    </span>
                ) : (
                    <>
                        {selectionCount > 0 ? (
                            <span className="text-gray-300">{selectionCount} repositories selected.</span>
                        ) : (
                            <span className="text-gray-400">Select one or more repositories to target specific bulk actions.</span>
                        )}
                        {/* Behavior-changing note promoted out of plain gray metadata
                            (Release 2.6 Phase 5): icon + bolded key phrase so it is not
                            missed. */}
                        <span className="inline-flex items-center gap-1.5 rounded border border-amber-700/50 bg-amber-900/20 px-2 py-0.5 text-amber-200">
                            <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <circle cx="12" cy="12" r="10" /><line x1="12" y1="16" x2="12" y2="12" /><line x1="12" y1="8" x2="12.01" y2="8" />
                            </svg>
                            <span>When none are selected, Pull/Fetch/Report apply to <strong className="font-semibold">the full filtered repository set</strong> ({repoCount}).</span>
                        </span>
                    </>
                )}
            </div>
            <div className="flex flex-wrap gap-3 flex-grow">
                 <ActionButton onClick={onInitClick} disabled={isActionRunning || !cloneImplemented} isLoading={currentOperation === 'init'} ariaLabel="Clone" statusTag={cloneImplemented ? undefined : 'Planned'} title={cloneImplemented ? "Clone repositories from GitHub into a local workspace (git clone via local backend)." : "Planned: clone repositories from GitHub into a local workspace (not implemented in this build)."} icon={<InitIcon className="w-4 h-4" />}>
                    {actionLabel('Clone')}
                </ActionButton>
                <ActionButton onClick={handleUpdate} disabled={!repoActionsEnabled} isLoading={currentOperation === 'update'} ariaLabel="Pull" count={selectionCount} title={actionTitle(`Run 'git pull' on ${selectionCount > 0 ? selectionCount + ' selected' : 'all active'} repositories.`)} icon={<UpdateIcon className="w-4 h-4" />}>
                    {actionLabel('Pull')}
                </ActionButton>
                <ActionButton onClick={handleSync} disabled={!repoActionsEnabled} isLoading={currentOperation === 'sync'} ariaLabel="Fetch" count={selectionCount} title={actionTitle(`Run 'git fetch --all --prune' on ${selectionCount > 0 ? selectionCount + ' selected' : 'all'} repositories.`)} icon={<SyncIcon className="w-4 h-4" />}>
                    {actionLabel('Fetch')}
                </ActionButton>
                <ActionButton onClick={onExport} disabled={!repoActionsEnabled} isLoading={currentOperation === 'export'} ariaLabel="Report" count={selectionCount} title={actionTitle(`Generate a timestamped collection status report in the repo-local reports folder and open the HTML report in a new tab for ${selectionCount > 0 ? selectionCount + ' selected' : 'all'} repositories.`)} icon={<ExportIcon className="w-4 h-4" />}>
                    {actionLabel('Report')}
                </ActionButton>
                <ActionButton onClick={onDocReviewClick} disabled={!repoActionsEnabled} isLoading={currentOperation === 'docreview'} ariaLabel="Doc Review" title={actionTitle('Run Doc Review Inventory, queue planning, and optional repo batch plan generation.')} icon={<DocReviewIcon className="w-4 h-4" />}>
                    {actionLabel('Doc Review')}
                </ActionButton>
                <ActionButton onClick={() => onAction('roadmap-scan')} disabled={!repoActionsEnabled} isLoading={currentOperation === 'roadmap-scan'} ariaLabel="Roadmap Scan" title={actionTitle('Scan all repositories for ROADMAP files and update the index.')} icon={<RoadmapIcon className="w-4 h-4" />}>
                    {actionLabel('Roadmap Scan')}
                </ActionButton>
                 <ActionButton onClick={handleArchive} disabled={!repoActionsEnabled || !settings || !archiveImplemented} isLoading={currentOperation === 'archive'} ariaLabel="Archive" count={selectionCount} statusTag={archiveImplemented ? undefined : 'Planned'} title={archiveImplemented ? `Archive ${selectionCount > 0 ? selectionCount + ' selected' : 'all'} repositories inactive for over ${settings?.daysInactive ?? 'N/A'} days (local).` : 'Planned: archive inactive repositories (not implemented in this build).'} icon={<ArchiveIcon className="w-4 h-4" />}>
                    {actionLabel('Archive')}
                </ActionButton>
            </div>
            <div className="flex gap-3">
                 <ActionButton onClick={onHelpClick} disabled={false} ariaLabel="Help" title="Open the end-to-end user guide for this application." icon={<HelpIcon className="w-4 h-4" />}>
                    <span className="hidden sm:inline">Help</span>
                 </ActionButton>
                 <ActionButton onClick={onApiDocsClick} disabled={false} ariaLabel="API docs" title="View API reference documentation for all backend endpoints." icon={<ApiDocsIcon className="w-4 h-4" />} />
                 {/* Settings moved to the page header (left of Sign out) so it is
                     reachable from every tab, not just the Repository Grid. */}
                 <ActionButton onClick={onRefresh} disabled={isActionRunning} ariaLabel="Refresh" title="Refresh the current view." icon={<RefreshIcon className="w-4 h-4" />} />
            </div>
        </div>
    );
};

export default ActionBar;
